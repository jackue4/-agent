// "Godot project" engine: every game is a complete Godot 4 project on the server
// (data/gprojects/<id>/) that the AI edits like a developer would - scripts, scenes, resources,
// shaders, project.godot. The platform plugin (addons/ugc, autoload UGC) is restored on every
// build. Native runs (load check, live play, self-test) use the project folder directly; the web
// preview runs the shared engine with the game's own pack (build/game.pck), rebuilt in
// milliseconds for text edits by patching the last full export, and fully re-exported only when
// project.godot or imported assets change.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { AsyncLocalStorage } from 'node:async_hooks';
import { ROOT, godotBin } from './godot.mjs';
import { patchPck } from './pck.mjs';
import { startWatchFrames } from './watch-frames.mjs';
import { compatibilityIssues } from './capabilities.mjs';

export const GP_ROOT = path.join(path.resolve(process.env.UGC_DATA_DIR || path.join(ROOT, 'data')), 'gprojects');
export const TEMPLATE = path.join(ROOT, 'gp_template');
const OWN = 'addons/ugc';
const TEXT_EXT = new Set(['gd', 'tscn', 'tres', 'gdshader', 'gdshaderinc', 'godot', 'cfg', 'json', 'txt', 'md', 'csv']);
/** Text resources Godot can load raw from a pack (anything else needs the editor's import/export). */
const RAW_OK = new Set(['gd', 'tscn', 'tres', 'gdshader', 'gdshaderinc', 'json', 'txt', 'csv', 'md', 'cfg']);
const MAX_FILE = 200000;
const MAX_FILES = 120;
const RUN_TIMEOUT_MS = 45000;
const BUILD_ID = /^[a-f0-9]{32}$/;
const HASH = /^[a-f0-9]{64}$/;
const projectLocks = new Map();
const lockContext = new AsyncLocalStorage();
const digest = data => crypto.createHash('sha256').update(data).digest('hex');
const ignoredRoot = /^(?:\.godot|build|generated|\.git)(?:\/|$)/i;
const generatedFile = /\.(?:import|uid)$/i;
const inside = (root, target) => {
  const rel = path.relative(root, target);
  return rel !== '' && rel !== '..' && !rel.startsWith('..' + path.sep) && !path.isAbsolute(rel);
};

function treeFiles(root, skip = () => false) {
  const files = [];
  const walk = (dir, relative = '') => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const rel = relative ? relative + '/' + entry.name : entry.name;
      if (skip(rel) || generatedFile.test(rel)) continue;
      if (entry.isSymbolicLink()) throw new Error('工程不能包含符号链接：' + rel);
      if (entry.isDirectory()) walk(path.join(dir, entry.name), rel);
      else if (entry.isFile()) files.push(rel);
    }
  };
  if (fs.existsSync(root)) walk(root);
  return files.sort();
}

function treeRevision(root, skip) {
  const hash = crypto.createHash('sha256');
  for (const rel of treeFiles(root, skip)) {
    const bytes = fs.readFileSync(path.join(root, rel));
    hash.update(JSON.stringify(rel) + '\0' + bytes.length + '\0').update(bytes);
  }
  return hash.digest('hex');
}

// Godot reports resources still referenced during engine shutdown as ERROR, after the game already ran.
const SHUTDOWN_NOISE = /^ERROR: \d+ resources still in use at exit\b/;
const processFailed = r => r.aborted || r.timedOut || r.code !== 0 || (r.stdout + '\n' + r.stderr).split(/\r?\n/).some(l => /^(?:SCRIPT |USER )?ERROR:/.test(l) && !SHUTDOWN_NOISE.test(l));
const diagnostic = r => (r.stdout + '\n' + r.stderr).slice(-3000);
const reportError = message => ({ file: 'project.godot', line: 0, message, kind: 'error' });

const gbin = () => process.env.GODOT_BIN || godotBin();
const ext = p => (p.match(/\.([a-z0-9]+)$/i)?.[1] || '').toLowerCase();

/** Project-relative POSIX path, or throws for anything outside the editable part of the project. */
export function safePath(p) {
  let s = String(p || '').trim().replace(/\\/g, '/').replace(/^res:\/\//, '').replace(/^\.\//, '');
  if (!s || s.startsWith('/') || /^[a-z]:/i.test(s) || s.split('/').some(x => !x || x.endsWith('.'))) throw new Error('无效路径：' + p);
  if (ignoredRoot.test(s)) throw new Error('这个目录由平台管理：' + s);
  if (s.toLowerCase() === OWN || s.toLowerCase().startsWith(OWN + '/')) throw new Error('addons/ugc 是平台插件，不能修改');
  if (!/^[\w\-./]+$/.test(s)) throw new Error('路径只能用英文字母、数字、下划线、横线和点：' + s);
  return s;
}

// ------------------------------------------------------------------ safety scan

const DANGER = [
  [/\bOS\s*\.\s*(execute|execute_with_pipe|create_process|create_instance|shell_open|shell_show_in_file_manager|kill|crash|set_environment|unset_environment|move_to_trash|call|callv|call_deferred)\b/, 'OS 系统命令'],
  [/\bOS\b(?!\s*\.)/, 'OS 作为值传递'],
  [/\bJavaScriptBridge\b|\bJavaScriptObject\b/, 'JavaScriptBridge'],
  [/\bHTTPRequest\b|\bHTTPClient\b|\bStreamPeerTCP\b|\bStreamPeerTLS\b|\bPacketPeerUDP\b|\bPacketPeerDTLS\b|\bWebSocketPeer\b|\bWebRTC\w*|\bTCPServer\b|\bUDPServer\b|\bENetConnection\b|\bENetMultiplayerPeer\b/, '网络访问'],
  [/\bEngine\s*\.\s*get_singleton\b|\bClassDB\s*\.\s*instantiate\b|\bExpression\b/, '动态取单例/动态执行'],
  [/\bGDScript\s*\.\s*new\b|\.source_code\b|\bbytes_to_var_with_objects\b|\bstr_to_var\b/, '动态生成代码'],
  [/\bGDExtension\w*\b|\bNativeMenu\b/, '原生扩展'],
  [/@tool\b|\bEditorInterface\b|\bEditorPlugin\b/, '编辑器 API'],
];
const FILE_API = /\b(FileAccess|DirAccess)\s*\.\s*(\w+)/;

/** Security problems in one project file, as "file:line 禁止使用 X". .gd lines are checked with
 *  comments and strings blanked; other text (scenes can embed scripts) is checked raw. */
export function scanIssues(file, src) {
  const issues = [];
  const isGd = file.endsWith('.gd');
  String(src).split('\n').forEach((l, i) => {
    const code = isGd ? l.replace(/#.*$/, '').replace(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/g, '""') : l;
    for (const [re, what] of DANGER) if (re.test(code)) issues.push(file + ':' + (i + 1) + ' 禁止使用 ' + what);
    const fm = code.match(FILE_API);
    if (fm && !/(res|user):\/\//.test(l)) issues.push(file + ':' + (i + 1) + ' ' + fm[1] + ' 只能访问 res:// 或 user:// 下的路径（把路径字面量写在同一行）');
    if (/(["'])(?:[a-z]:[\\/]|\/(?:etc|usr|home|Users|tmp|var)\/)/i.test(l)) issues.push(file + ':' + (i + 1) + ' 不能使用本机绝对路径');
  });
  return issues;
}

// ------------------------------------------------------------------ class_name cache

/** `.godot/global_script_class_cache.cfg` for the project's scripts (normally the editor writes it). */
export function classCache(scripts) {
  const decl = {};
  for (const [p, src] of Object.entries(scripts)) {
    const cn = String(src).match(/^\s*(?:@\w+(?:\([^)]*\))?\s+)*class_name\s+([A-Za-z_]\w*)/m);
    const ex = String(src).match(/^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:class_name\s+\w+\s+)?extends\s+("[^"]+"|'[^']+'|[\w.]+)/m);
    decl[p] = { cls: cn?.[1] || '', ext: ex ? ex[1].replace(/^["']|["']$/g, '') : 'RefCounted', tool: /^\s*@tool\b/m.test(src), abstract: /^\s*@abstract\b/m.test(src) };
  }
  const baseOf = (p, depth = 0) => {
    const e = decl[p]?.ext || 'RefCounted';
    if (!e.startsWith('res://')) return e.split('.')[0];
    const q = e.slice(6);
    if (decl[q]?.cls) return decl[q].cls;
    return depth > 8 || !decl[q] ? 'RefCounted' : baseOf(q, depth + 1);
  };
  const items = Object.keys(decl).filter(p => decl[p].cls).sort().map(p => '{\n"base": &"' + baseOf(p) + '",\n"class": &"' + decl[p].cls + '",\n"icon": "",\n"is_abstract": ' + decl[p].abstract + ',\n"is_tool": ' + decl[p].tool + ',\n"language": &"GDScript",\n"path": "res://' + p + '"\n}');
  return 'list=[' + items.join(', ') + ']\n';
}

// ------------------------------------------------------------------ process helpers

export function throwIfAborted(signal) {
  if (!signal?.aborted) return;
  const error = new Error('操作已取消' + (signal.reason?.message ? '：' + signal.reason.message : ''));
  error.name = 'AbortError'; error.code = 'ABORT_ERR';
  throw error;
}

/** Runs Godot; cancellation is distinct from a process timeout and never starts pre-aborted work. */
export function runGodot(args, { cwd, timeoutMs = RUN_TIMEOUT_MS, signal, spawnProcess = spawn } = {}) {
  if (signal?.aborted) return Promise.resolve({ code: -1, stdout: '', stderr: '操作已取消', timedOut: false, aborted: true });
  return new Promise(resolve => {
    let ch;
    try { ch = spawnProcess(gbin(), args, { cwd, windowsHide: true }); }
    catch (e) { resolve({ code: -1, stdout: '', stderr: e.message, timedOut: false, aborted: !!signal?.aborted }); return; }
    let so = '', se = '', to = false, aborted = false, settled = false, forceTimer;
    ch.stdout.on('data', d => { so += d; if (so.length > 2e6) so = so.slice(-1e6); });
    ch.stderr.on('data', d => { se += d; if (se.length > 2e6) se = se.slice(-1e6); });
    const finish = (code, error = '') => {
      if (settled) return;
      settled = true; clearTimeout(timer); clearTimeout(forceTimer);
      signal?.removeEventListener('abort', abort);
      resolve({ code, stdout: so, stderr: se + error, timedOut: to, aborted });
    };
    const kill = () => {
      if (settled) return;
      try { ch.kill(); } catch { /* already gone */ }
      if (!settled && !forceTimer) forceTimer = setTimeout(() => { try { ch.kill('SIGKILL'); } catch { /* gone */ } }, 1000);
    };
    const abort = () => { aborted = true; kill(); };
    const timer = setTimeout(() => { to = true; kill(); }, timeoutMs);
    ch.on('close', code => finish(code));
    ch.on('error', e => finish(-1, '\n' + e.message));
    signal?.addEventListener('abort', abort, { once: true });
    if (signal?.aborted) abort();
  });
}

/** Last "[tag] {json}" line of stdout. */
export function tagged(stdout, tag) {
  const line = stdout.split(/\r?\n/).reverse().find(l => l.startsWith('[' + tag + '] '));
  if (!line) return null;
  try { return JSON.parse(line.slice(tag.length + 3)); } catch { return null; }
}

/** Errors Godot printed for project files that the in-game logger could not catch (parse errors
 *  of the main scene's script before autoloads run, missing resources). */
export function stderrErrors(text) {
  const out = [];
  const lines = String(text).split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^(?:SCRIPT |USER )?ERROR:\s*(.+)$/);
    if (!m) continue;
    const at = (lines[i + 1] || '').match(/at:.*?\(?res:\/\/([\w\-./]+):(\d+)\)?/) || m[1].match(/res:\/\/([\w\-./]*[\w\-/])(?::(\d+))?/);
    if (!at || at[1].startsWith(OWN + '/')) continue;
    out.push({ file: at[1], line: Number(at[2] || 0), message: m[1].trim(), kind: 'error' });
  }
  return out;
}

function mergeErrors(a, b) {
  const seen = new Set(a.map(e => e.file + ':' + e.line + ':' + e.message.slice(0, 60)));
  const out = [...a];
  for (const e of b) {
    const k = e.file + ':' + e.line + ':' + e.message.slice(0, 60);
    if (!seen.has(k) && !a.some(x => x.file === e.file && x.line === e.line)) { seen.add(k); out.push(e); }
  }
  return out;
}

// ------------------------------------------------------------------ project

const copyTree = (from, to, skip = () => false) => {
  fs.mkdirSync(to, { recursive: true });
  for (const e of fs.readdirSync(from, { withFileTypes: true })) {
    if (skip(e.name)) continue;
    const a = path.join(from, e.name), b = path.join(to, e.name);
    if (e.isDirectory()) copyTree(a, b, skip); else fs.copyFileSync(a, b);
  }
};

export class GodotProject {
  constructor(id, { root = GP_ROOT, template = TEMPLATE, runGodot: runner = runGodot } = {}) {
    this.id = String(id);
    if (!/^[\w-]{1,128}$/.test(this.id)) throw new Error('无效工程 ID');
    this.dir = path.join(path.resolve(root), this.id);
    this.template = path.resolve(template);
    this._runGodot = runner;
    this.buildDir = path.join(this.dir, 'build');
    this.stateFile = path.join(this.buildDir, 'state.json');
  }

  get exists() { return fs.existsSync(path.join(this.dir, 'project.godot')); }
  get pckPath() { return path.join(this.buildDir, 'game.pck'); }
  get state() { try { return JSON.parse(fs.readFileSync(this.stateFile, 'utf8')); } catch { return { version: 0, changed: [], deleted: [], needsExport: true, needsImport: true }; } }
  set state(s) {
    this._assertPath(this.stateFile);
    fs.mkdirSync(this.buildDir, { recursive: true });
    const tmp = this.stateFile + '.' + crypto.randomBytes(6).toString('hex') + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(s), { flag: 'wx' });
    fs.renameSync(tmp, this.stateFile);
  }
  _mark(fn) { const s = this.state; fn(s); this.state = s; }

  /** Shared across project objects; nested work in the same active transaction is reentrant. */
  withLock(fn) {
    let key = path.resolve(this.dir);
    if (process.platform === 'win32') key = key.toLowerCase();
    const inherited = lockContext.getStore();
    if (inherited?.get(key)?.active) return Promise.resolve().then(fn);
    const previous = projectLocks.get(key) || Promise.resolve();
    const run = previous.then(async () => {
      const token = { active: true };
      const context = new Map(inherited || []);
      context.set(key, token);
      try { return await lockContext.run(context, fn); }
      finally { token.active = false; }
    });
    const tail = run.then(() => {}, () => {});
    projectLocks.set(key, tail);
    void tail.then(() => { if (projectLocks.get(key) === tail) projectLocks.delete(key); });
    return run;
  }

  _assertPath(file) {
    const target = path.resolve(file);
    if (!inside(this.dir, target)) throw new Error('路径超出工程目录');
    if (!fs.existsSync(this.dir)) return target;
    const actualRoot = fs.realpathSync(this.dir);
    let ancestor = target;
    while (!fs.existsSync(ancestor)) ancestor = path.dirname(ancestor);
    const actual = fs.realpathSync(ancestor);
    if (actual !== actualRoot && !inside(actualRoot, actual)) throw new Error('实际路径超出工程目录');
    return target;
  }

  /** Content identity includes user text/assets and the platform plugin that will be restored. */
  revision() {
    const sources = treeRevision(this.dir, rel => ignoredRoot.test(rel) || rel.toLowerCase() === OWN || rel.toLowerCase().startsWith(OWN + '/'));
    const platform = treeRevision(path.join(this.template, OWN), rel => ignoredRoot.test(rel) || rel === 'build.json');
    return digest(sources + '\0' + platform);
  }

  getBuild(buildId) {
    if (typeof buildId !== 'string' || !BUILD_ID.test(buildId)) return null;
    try {
      const file = this._assertPath(path.join(this.buildDir, 'builds', buildId + '.pck'));
      const metadataFile = this._assertPath(path.join(this.buildDir, 'builds', buildId + '.json'));
      const metadata = JSON.parse(fs.readFileSync(metadataFile, 'utf8'));
      if (metadata.buildId !== buildId || !HASH.test(metadata.sourceRevision) || !HASH.test(metadata.contentHash) || !Number.isSafeInteger(metadata.version) || metadata.version < 1) return null;
      const bytes = fs.readFileSync(file);
      if (metadata.bytes !== bytes.length || digest(bytes) !== metadata.contentHash) return null;
      return { ...metadata, path: file };
    } catch { return null; }
  }

  get latestBuild() {
    const last = this.state.lastBuild;
    return this.getBuild(typeof last === 'string' ? last : last?.buildId);
  }

  /** New project from the template, sized for the orientation. */
  create({ title = '造梦游戏', orientation = 'landscape' } = {}) {
    if (this.exists) return this;
    copyTree(this.template, this.dir, n => ignoredRoot.test(n));
    const [w, h] = orientation === 'portrait' ? [720, 1280] : [1280, 720];
    let pg = fs.readFileSync(path.join(this.dir, 'project.godot'), 'utf8');
    pg = pg.replace(/config\/name="[^"]*"/, 'config/name="' + String(title).replace(/["\\\n]/g, '') + '"')
      .replace(/viewport_width=\d+/, 'viewport_width=' + w).replace(/viewport_height=\d+/, 'viewport_height=' + h);
    if (orientation === 'portrait') pg = pg.replace('[display]\n', '[display]\n\nwindow/handheld/orientation=1\n');
    fs.writeFileSync(path.join(this.dir, 'project.godot'), pg);
    this.state = { version: 0, changed: [], deleted: [], needsExport: true, needsImport: true };
    return this;
  }

  /** The platform plugin and its project.godot hooks are always the template's. */
  syncPlatform() {
    const own = path.join(this.dir, OWN);
    this._assertPath(own);
    const skip = rel => ignoredRoot.test(rel) || rel === 'build.json';
    const platformRevision = treeRevision(path.join(this.template, OWN), skip);
    if (this.state.platformRevision !== platformRevision || treeRevision(own, skip) !== platformRevision) {
      fs.rmSync(own, { recursive: true, force: true });
      copyTree(path.join(this.template, OWN), own, n => generatedFile.test(n) || n === 'build.json');
      this._mark(s => { s.platformRevision = platformRevision; s.needsImport = true; s.needsExport = true; });
    }
    const pf = path.join(this.dir, 'project.godot');
    let pg = fs.readFileSync(pf, 'utf8');
    const before = pg;
    if (!/^UGC="\*res:\/\/addons\/ugc\/ugc\.gd"/m.test(pg)) {
      pg = pg.replace(/^UGC=.*\n?/m, '');
      pg = /^\[autoload\]/m.test(pg) ? pg.replace(/^\[autoload\]\s*\n/m, '[autoload]\n\nUGC="*res://addons/ugc/ugc.gd"\n') : pg + '\n[autoload]\n\nUGC="*res://addons/ugc/ugc.gd"\n';
    }
    if (!/^theme\/custom_font=/m.test(pg)) pg = /^\[gui\]/m.test(pg) ? pg.replace(/^\[gui\]\s*\n/m, '[gui]\n\ntheme/custom_font="res://addons/ugc/font.ttf"\n') : pg + '\n[gui]\n\ntheme/custom_font="res://addons/ugc/font.ttf"\n';
    if (!/^config_version=5/m.test(pg)) pg = 'config_version=5\n' + pg;
    if (pg !== before) { fs.writeFileSync(pf, pg); this._mark(s => { s.needsExport = true; }); }
  }

  abs(rel) { return this._assertPath(path.join(this.dir, ...rel.split('/'))); }

  /** Editable files (project-relative), without engine metadata. */
  list() {
    return treeFiles(this.dir, rel => ignoredRoot.test(rel) || rel.toLowerCase() === OWN || rel.toLowerCase().startsWith(OWN + '/'))
      .map(rel => ({ path: rel, size: fs.statSync(this.abs(rel)).size, text: TEXT_EXT.has(ext(rel)) }));
  }

  read(rel) {
    rel = safePath(rel);
    const f = this.abs(rel);
    if (!fs.existsSync(f)) return null;
    if (!TEXT_EXT.has(ext(rel))) return { binary: true, size: fs.statSync(f).size };
    return fs.readFileSync(f, 'utf8');
  }

  /** All text sources (for grep, prompts and the class cache). */
  sources(filter = () => true) {
    const out = {};
    for (const f of this.list()) if (f.text && filter(f.path)) out[f.path] = fs.readFileSync(this.abs(f.path), 'utf8');
    return out;
  }

  /** Writes a text file after the safety scan. Returns issues (empty = written). */
  write(rel, text) {
    rel = safePath(rel);
    const e = ext(rel);
    if (!TEXT_EXT.has(e)) return ['只能用工具写文本文件（.gd .tscn .tres .gdshader .json …）；图片/音频用素材工具生成'];
    text = String(text ?? '').replace(/\r\n/g, '\n');
    if (text.length > MAX_FILE) return [rel + ' 太大（>' + MAX_FILE / 1000 + 'KB），请拆分'];
    const f = this.abs(rel);
    if (!fs.existsSync(f) && this.list().length >= MAX_FILES) return ['文件数量已达上限 ' + MAX_FILES];
    const issues = [...scanIssues(rel, text), ...compatibilityIssues(rel, text)];
    if (issues.length) return issues;
    fs.mkdirSync(path.dirname(f), { recursive: true });
    fs.writeFileSync(f, text);
    this._changed(rel);
    return [];
  }

  /** Binary asset (generated image/sound) placed into the project; needs an import + full export. */
  writeAsset(rel, buf) {
    rel = safePath(rel);
    const f = this.abs(rel);
    fs.mkdirSync(path.dirname(f), { recursive: true });
    fs.writeFileSync(f, buf);
    this._mark(s => { s.needsImport = true; s.needsExport = true; });
  }

  remove(rel) {
    rel = safePath(rel);
    if (rel.toLowerCase() === 'project.godot') return false;
    if (rel.toLowerCase() === 'addons') throw new Error('不能删除包含平台插件的目录');
    const f = this.abs(rel);
    if (!fs.existsSync(f)) return false;
    const directory = fs.statSync(f).isDirectory();
    const removed = directory ? treeFiles(f).map(name => rel + '/' + name) : [rel];
    fs.rmSync(f, { recursive: true, force: true });
    for (const x of ['.import', '.uid']) fs.rmSync(f + x, { force: true });
    this._mark(s => {
      s.changed = s.changed.filter(p => p !== rel && !p.startsWith(rel + '/'));
      for (const name of removed) if (!s.deleted.includes(name)) s.deleted.push(name);
      if (directory || !RAW_OK.has(ext(rel))) s.needsExport = true;
    });
    return true;
  }

  _changed(rel) {
    this._mark(s => {
      if (rel.toLowerCase() === 'project.godot' || !RAW_OK.has(ext(rel))) s.needsExport = true;
      else if (!s.changed.includes(rel)) s.changed.push(rel);
      s.deleted = s.deleted.filter(p => p !== rel);
    });
  }

  writeClassCache() {
    const text = classCache(this.sources(p => p.endsWith('.gd')));
    const f = path.join(this.dir, '.godot', 'global_script_class_cache.cfg');
    fs.mkdirSync(path.dirname(f), { recursive: true });
    if (!fs.existsSync(f) || fs.readFileSync(f, 'utf8') !== text) fs.writeFileSync(f, text);
    return text;
  }

  /** Serializes builds/runs that touch .godot/ (imports and exports must not overlap). */
  _serial(fn, { signal } = {}) {
    if (signal?.aborted) return Promise.reject(Object.assign(new Error('操作已取消'), { name: 'AbortError', code: 'ABORT_ERR' }));
    return this.withLock(() => { throwIfAborted(signal); return fn(); });
  }

  /** Godot initializes the custom theme before importing its font on the first editor scan. */
  _canRetryPlatformFontImport(result) {
    if (result.timedOut || result.code !== 0) return false;
    const errors = (result.stdout + '\n' + result.stderr).split(/\r?\n/).filter(line => /^(?:SCRIPT |USER )?ERROR:/.test(line));
    const transient = new Set([
      'ERROR: No loader found for resource: res://addons/ugc/font.ttf (expected type: unknown)',
      "ERROR: Error loading custom project font 'res://addons/ugc/font.ttf'",
    ]);
    if (!errors.length || !errors.every(line => transient.has(line.trimEnd()))) return false;
    try {
      const imported = fs.readFileSync(this._assertPath(path.join(this.dir, OWN, 'font.ttf.import')), 'utf8');
      if (!/^source_file="res:\/\/addons\/ugc\/font\.ttf"\r?$/m.test(imported)) return false;
      const resource = imported.match(/^path="res:\/\/(\.godot\/imported\/font\.ttf-[a-f0-9]{32}\.fontdata)"\r?$/m)?.[1];
      if (!resource) return false;
      const cached = fs.statSync(this._assertPath(path.join(this.dir, resource)));
      return cached.isFile() && cached.size > 0;
    } catch { return false; }
  }

  /** Editor import (needed once and after new binary assets). */
  importIfNeeded({ signal } = {}) {
    return this._serial(async () => {
      this.syncPlatform();
      if (!this.state.needsImport && fs.existsSync(path.join(this.dir, '.godot', 'imported'))) return { ok: true, skipped: true };
      this._mark(s => { s.needsImport = true; });
      const invoke = () => this._runGodot(['--headless', '--path', this.dir, '--import'], { cwd: this.dir, timeoutMs: 180000, signal });
      let r = await invoke();
      throwIfAborted(signal);
      const retried = !signal?.aborted && this._canRetryPlatformFontImport(r);
      if (retried) r = await invoke();
      throwIfAborted(signal);
      if (processFailed(r)) return { ok: false, error: '资源导入失败', code: r.code, timedOut: r.timedOut, log: diagnostic(r) };
      this.writeClassCache();
      this._mark(s => { s.needsImport = false; });
      return { ok: true, retried, log: diagnostic(r) };
    }, { signal });
  }

  /**
   * Web preview pack. Text-only edits since the last full export are patched into it (fast);
   * project.godot/asset changes or a missing base trigger a full export. Returns { version, full, ms }.
   */
  build({ signal, full = false, sourceRevision: expectedRevision } = {}) {
    return this._serial(async () => {
      const t0 = Date.now();
      let sourceRevision = '';
      try {
        this.syncPlatform();
        sourceRevision = this.revision();
        if (expectedRevision && expectedRevision !== sourceRevision) return { ok: false, error: '构建版本与请求版本不一致', sourceRevision, ms: Date.now() - t0 };
        const base = this._assertPath(path.join(this.buildDir, 'base.pck'));
        let st = this.state;
        const sourceFiles = Object.fromEntries(this.list().map(f => [f.path, digest(fs.readFileSync(this.abs(f.path)))]));
        const changed = Object.keys(sourceFiles).filter(rel => st.baseFiles?.[rel] !== sourceFiles[rel]);
        const deleted = Object.keys(st.baseFiles || {}).filter(rel => !(rel in sourceFiles));
        const requiresImport = [...changed, ...deleted].some(rel => rel.toLowerCase() === 'project.godot' || !RAW_OK.has(ext(rel)));
        const needFull = full || st.needsExport || !st.baseFiles || !fs.existsSync(base) || requiresImport;
        if (requiresImport) this._mark(s => { s.needsImport = true; s.needsExport = true; });
        if (needFull) {
          const imported = await this.importIfNeeded({ signal });
          throwIfAborted(signal);
          if (!imported.ok) return { ...imported, sourceRevision: this.revision(), ms: Date.now() - t0 };
        }
        sourceRevision = this.revision();
        if (expectedRevision && expectedRevision !== sourceRevision) return { ok: false, error: '构建版本与请求版本不一致', sourceRevision, ms: Date.now() - t0 };
        // Import may have changed source files; the manifest must describe the actual export inputs.
        const exportFiles = Object.fromEntries(this.list().map(f => [f.path, digest(fs.readFileSync(this.abs(f.path)))]));
        const tmp = this._assertPath(path.join(this.buildDir, 'base_new.pck'));
        let baseBytes;
        if (needFull) {
          fs.mkdirSync(this.buildDir, { recursive: true });
          fs.rmSync(tmp, { force: true });
          const r = await this._runGodot(['--headless', '--path', this.dir, '--export-pack', 'Web', 'build/base_new.pck'], { cwd: this.dir, timeoutMs: 240000, signal });
          throwIfAborted(signal);
          if (processFailed(r) || !fs.existsSync(tmp)) return { ok: false, error: '导出失败：' + diagnostic(r), sourceRevision, ms: Date.now() - t0 };
          baseBytes = fs.readFileSync(tmp);
        } else baseBytes = fs.readFileSync(base);
        if (this.revision() !== sourceRevision) return { ok: false, error: '构建期间源码或素材发生变化', sourceRevision, ms: Date.now() - t0 };
        st = this.state;
        const version = (st.version || 0) + 1;
        const buildId = crypto.randomBytes(16).toString('hex');
        const files = {};
        if (!needFull) for (const rel of changed) files[rel] = fs.readFileSync(this.abs(rel));
        const extra = {
          '.godot/global_script_class_cache.cfg': this.writeClassCache(),
          'addons/ugc/build.json': JSON.stringify({ buildId, sourceRevision, version }),
        };
        const out = patchPck(baseBytes, { files, deleted: needFull ? [] : deleted, extra });
        if (this.revision() !== sourceRevision) return { ok: false, error: '构建提交前源码或素材发生变化', sourceRevision, ms: Date.now() - t0 };
        const artifact = this._assertPath(path.join(this.buildDir, 'builds', buildId + '.pck'));
        const metadata = { ok: true, version, buildId, sourceRevision, contentHash: digest(out), full: needFull,
          ms: Date.now() - t0, bytes: out.length, createdAt: new Date().toISOString() };
        throwIfAborted(signal);
        fs.mkdirSync(path.dirname(artifact), { recursive: true });
        fs.writeFileSync(artifact, out, { flag: 'wx' });
        fs.writeFileSync(artifact.replace(/\.pck$/, '.json'), JSON.stringify(metadata), { flag: 'wx' });
        if (needFull) fs.renameSync(tmp, base);
        fs.writeFileSync(this.pckPath + '.tmp', out);
        fs.renameSync(this.pckPath + '.tmp', this.pckPath);
        this._mark(s => {
          s.version = version; s.lastBuild = metadata; s.needsExport = false;
          s.changed = needFull ? [] : changed; s.deleted = needFull ? [] : deleted;
          if (needFull) s.baseFiles = exportFiles;
        });
        return { ...metadata, path: artifact };
      } catch (e) {
        return { ok: false, error: '构建失败：' + String(e.message || e), ...(signal?.aborted ? { aborted: true } : {}), sourceRevision, ms: Date.now() - t0 };
      }
    }, { signal });
  }

  /** Native args shared by every run of the project folder. */
  _prep() { this.syncPlatform(); this.writeClassCache(); }

  /** Headless: compiles every script and starts the main scene briefly. { loaded, errors } */
  check(opts = {}) { return this._serial(() => this._check(opts), opts); }

  /** Import done and class cache written, so a native run sees every asset and class_name. */
  ready({ signal } = {}) { return this._serial(async () => { const r = await this.importIfNeeded({ signal }); throwIfAborted(signal); if (!r.ok) throw new Error(r.error + ': ' + r.log); this._prep(); }, { signal }); }

  async _check({ signal, sourceRevision: expectedRevision } = {}) {
    throwIfAborted(signal);
    this.syncPlatform();
    const incompatible = Object.entries(this.sources()).flatMap(([file, source]) => compatibilityIssues(file, source));
    if (incompatible.length) return { ok: false, loaded: false, sourceRevision: this.revision(), errors: incompatible.map(reportError) };
    if (expectedRevision && expectedRevision !== this.revision()) return { ok: false, loaded: false, sourceRevision: this.revision(), errors: [reportError('检查版本与请求版本不一致')] };
    const imported = await this.importIfNeeded({ signal });
    throwIfAborted(signal);
    if (!imported.ok) return { ok: false, loaded: false, sourceRevision: this.revision(), errors: [reportError(imported.error + ': ' + imported.log)] };
    this._prep();
    const sourceRevision = this.revision();
    if (expectedRevision && expectedRevision !== sourceRevision) return { ok: false, loaded: false, sourceRevision, errors: [reportError('检查版本与请求版本不一致')] };
    const r = await this._runGodot(['--headless', '--path', this.dir, '--audio-driver', 'Dummy', '--', '--ugc-check'], { cwd: this.dir, timeoutMs: 30000, signal });
    throwIfAborted(signal);
    const rep = tagged(r.stdout, 'ugc-check') || { loaded: false, errors: [] };
    rep.sourceRevision = sourceRevision;
    rep.errors = mergeErrors(rep.errors || [], stderrErrors(r.stdout + '\n' + r.stderr));
    const constructionText = this.read('scenes/construction.json');
    if (constructionText) {
      try {
        const scene = JSON.parse(constructionText);
        if (scene.schema === 1 && scene.dimension === '3d' && !rep.construction?.some(c => c.revision === scene.revision && c.objectCount === scene.objects.length && c.source_path === 'res://scenes/construction.json')) {
          rep.errors.push(reportError('实际游戏没有加载当前搭建的关卡。保留 main.tscn 的 res://scenes/construction.tscn 实例（Construction），不要在_ready移除它。'));
        }
      } catch { rep.errors.push(reportError('实际搭建关卡数据无法读取，请用 build_scene 修复')); }
    }
    if (r.timedOut) rep.errors.push({ file: 'main', line: 0, message: '启动超时（_ready 里可能有死循环）', kind: 'error' });
    else if (!tagged(r.stdout, 'ugc-check') && !rep.errors.length) rep.errors.push({ file: 'project.godot', line: 0, message: '游戏没能启动：' + (r.stdout + r.stderr).split(/\r?\n/).filter(l => /ERROR|Error/.test(l)).slice(-3).join(' | ').slice(0, 300), kind: 'error' });
    if (processFailed(r) && !rep.errors.some(e => e.kind !== 'warning')) rep.errors.push(reportError('Godot 检查进程失败：' + diagnostic(r)));
    if (this.revision() !== sourceRevision) rep.errors.push(reportError('检查期间源码或素材发生变化'));
    rep.ok = !!rep.loaded && !rep.errors.some(e => e.kind !== 'warning');
    return rep;
  }

  /** Windowed run of the main scene's auto_test() with start/end screenshots. */
  selfTest(opts = {}) { return this._serial(() => this._selfTest(opts), opts); }

  async _selfTest({ orientation = 'landscape', shot = true, signal, sourceRevision: expectedRevision, onFrame } = {}) {
    throwIfAborted(signal);
    this.syncPlatform();
    if (expectedRevision && expectedRevision !== this.revision()) return { ok: false, loaded: false, sourceRevision: this.revision(), errors: [reportError('自测版本与请求版本不一致')], checks: [], has_test: false };
    const imported = await this.importIfNeeded({ signal });
    throwIfAborted(signal);
    if (!imported.ok) return { ok: false, loaded: false, sourceRevision: this.revision(), errors: [reportError(imported.error + ': ' + imported.log)], checks: [], has_test: false };
    this._prep();
    const sourceRevision = this.revision();
    if (expectedRevision && expectedRevision !== sourceRevision) return { ok: false, loaded: false, sourceRevision, errors: [reportError('自测版本与请求版本不一致')], checks: [], has_test: false };
    const shotPath = path.join(this.buildDir, 'test_shot.jpg').replace(/\\/g, '/');
    for (const f of [shotPath, shotPath.replace(/\.jpg$/, '_end.jpg')]) fs.rmSync(f, { force: true });
    const res = orientation === 'portrait' ? '540x960' : '1280x720';
    const watching = typeof onFrame === 'function';
    const args = shot || watching ? ['--path', this.dir, '--audio-driver', 'Dummy', '--resolution', res, '--position', '40,40'] : ['--headless', '--path', this.dir, '--audio-driver', 'Dummy'];
    args.push('--', '--ugc-test', '--ugc-seed=1');
    if (shot) args.push('--ugc-shot=' + shotPath);
    const watchDir = watching ? fs.mkdtempSync(path.join(os.tmpdir(), 'ugc-watch-')) : null;
    if (watchDir) args.push('--ugc-watch=' + watchDir.replace(/\\/g, '/'));
    const reader = watchDir ? startWatchFrames(watchDir, { onFrame, signal }) : null;
    const t0 = Date.now();
    let r;
    try { r = await this._runGodot(args, { cwd: this.dir, timeoutMs: RUN_TIMEOUT_MS, signal }); }
    finally {
      try { await reader?.flush(); }
      finally {
        reader?.stop();
        if (watchDir && path.dirname(path.resolve(watchDir)) === path.resolve(os.tmpdir()) && path.basename(watchDir).startsWith('ugc-watch-')) {
          fs.rmSync(watchDir, { recursive: true, force: true });
        }
      }
    }
    throwIfAborted(signal);
    const rep = tagged(r.stdout, 'ugc-test') || { loaded: false, errors: [], checks: [], has_test: false, result: '' };
    rep.sourceRevision = sourceRevision;
    rep.errors = mergeErrors(rep.errors || [], stderrErrors(r.stdout + '\n' + r.stderr));
    if (r.timedOut) rep.errors.push({ file: 'main', line: 0, message: 'auto_test() 没有在 ' + RUN_TIMEOUT_MS / 1000 + ' 秒内结束（死循环或 await 等不到）', kind: 'error' });
    if (processFailed(r) && !rep.errors.some(e => e.kind !== 'warning')) rep.errors.push(reportError('Godot 自测进程失败：' + diagnostic(r)));
    if (this.revision() !== sourceRevision) rep.errors.push(reportError('自测期间源码或素材发生变化'));
    rep.checks = Array.isArray(rep.checks) ? rep.checks : [];
    const valid = rep.checks.filter(c => c && typeof c.ok === 'boolean' && typeof c.what === 'string' && c.what.trim());
    rep.assertionCount = valid.length;
    if (!valid.length) rep.errors.push(reportError('auto_test() 必须至少记录一条有效断言'));
    if (valid.length !== rep.checks.length) rep.errors.push(reportError('auto_test() 包含无效断言格式'));
    rep.ok = !!rep.loaded && !rep.errors.some(e => e.kind !== 'warning') && valid.every(c => c.ok) && !!rep.has_test;
    rep.ms = Date.now() - t0;
    const img = f => fs.existsSync(f) ? fs.readFileSync(f).toString('base64') : '';
    rep.image = shot ? img(shotPath) : '';
    rep.image_end = shot ? img(shotPath.replace(/\.jpg$/, '_end.jpg')) : '';
    return rep;
  }

  /** Args for a live windowed session (server/live.mjs). */
  liveArgs(dirForGodot, orientation) {
    this._prep();
    return ['--path', this.dir, '--audio-driver', 'Dummy', '--resolution', orientation === 'portrait' ? '540x960' : '1280x720', '--position', '40,40', '--', '--ugc-live=' + dirForGodot, '--ugc-seed=1'];
  }
}
