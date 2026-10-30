// Runs an AI-written game (code engine) inside the real Godot runtime and reports what happened:
// compile/runtime errors from AI files, the game's own auto_test() assertions, win/lose, and an
// optional screenshot. This is the ground truth the code agent repairs against.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { ROOT, godotBin } from './godot.mjs';

/** Godot console binary, resolved lazily so a missing tool fails at use, not at import. */
export const GODOT = process.env.GODOT_BIN || null;
const gpath = () => GODOT || godotBin();
const RUNTIME = path.join(ROOT, 'runtime');
const TIMEOUT_MS = 40000;
const MAX_PARALLEL = 2;
let active = 0;
const waiters = [];

async function slot() {
  if (active < MAX_PARALLEL) { active++; return; }
  await new Promise(r => waiters.push(r));
  active++;
}
function release() { active--; const w = waiters.shift(); if (w) w(); }

/** Error lines Godot prints for user://ugc files (fallback when the in-game logger missed them). */
export function parseStderrErrors(text) {
  const out = [];
  const lines = text.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^(?:SCRIPT )?ERROR:\s*(.+)$/);
    if (!m) continue;
    const at = (lines[i + 1] || '').match(/at:.*?\(?user:\/\/ugc\/[^)]*?([\w.-]+\.gd):(\d+)\)?/);
    if (!at) continue;
    out.push({ file: at[1], line: Number(at[2]), message: m[1].trim(), kind: 'error' });
  }
  return out;
}

/** Parses the "[autotest] {...}" line printed by main.gd. */
export function parseReport(stdout) {
  const line = stdout.split(/\r?\n/).reverse().find(l => l.startsWith('[autotest] '));
  if (!line) return null;
  try { return JSON.parse(line.slice('[autotest] '.length)); } catch { return null; }
}

/**
 * files: {name: source}; meta: game meta (palette, title …).
 * opts.shot: also render one frame (windowed run) and return it as base64 JPEG.
 */
export async function runCodeTest(files, meta = {}, { shot = false, signal } = {}) {
  await slot();
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ugc-run-'));
  const specPath = path.join(dir, 'spec.json');
  const shotPath = path.join(dir, 'shot.jpg');
  fs.writeFileSync(specPath, JSON.stringify({ spec: { meta: { ...meta, engine: 'code', dimension: '2d' }, code: { files } }, assets: {} }));
  const args = ['--path', RUNTIME, '--audio-driver', 'Dummy'];
  if (shot) args.push('--resolution', meta.orientation === 'portrait' ? '540x960' : '1280x720', '--position', '40,40');
  else args.unshift('--headless');
  args.push('--', '--spec=' + specPath, '--play', '--autotest');
  if (shot) args.push('--autotest-shot=' + shotPath);
  const t0 = Date.now();
  try {
    const { stdout, stderr, timedOut } = await new Promise(resolve => {
      const ch = spawn(gpath(), args, { cwd: RUNTIME, windowsHide: true });
      let so = '', se = '';
      ch.stdout.on('data', d => { so += d; if (so.length > 2e6) so = so.slice(-1e6); });
      ch.stderr.on('data', d => { se += d; if (se.length > 2e6) se = se.slice(-1e6); });
      let to = false;
      const kill = () => { to = true; try { ch.kill(); } catch { /* already gone */ } };
      const timer = setTimeout(kill, TIMEOUT_MS);
      signal?.addEventListener('abort', kill, { once: true });
      ch.on('close', () => { clearTimeout(timer); resolve({ stdout: so, stderr: se, timedOut: to }); });
      ch.on('error', e => { clearTimeout(timer); resolve({ stdout: so, stderr: se + '\n' + e.message, timedOut: false }); });
    });
    const report = parseReport(stdout) || { loaded: false, errors: [], checks: [], has_test: false, result: '' };
    const seen = new Set(report.errors.map(e => e.file + ':' + e.line));
    for (const e of parseStderrErrors(stdout + '\n' + stderr)) if (!seen.has(e.file + ':' + e.line)) { seen.add(e.file + ':' + e.line); report.errors.push(e); }
    if (timedOut) report.errors.push({ file: 'main.gd', line: 0, message: '运行超时：auto_test() 没有在 ' + TIMEOUT_MS / 1000 + ' 秒内结束（可能有死循环或 await 永远等不到）', kind: 'error' });
    if (!parseReport(stdout) && !timedOut && !report.errors.length) report.errors.push({ file: 'main.gd', line: 0, message: '游戏没能启动（runtime 无报告）', kind: 'error' });
    const failed = (report.checks || []).filter(c => !c.ok);
    const errs = report.errors.filter(e => e.kind !== 'warning');
    report.ok = report.loaded && errs.length === 0 && failed.length === 0 && report.has_test;
    report.ms = Date.now() - t0;
    if (shot && fs.existsSync(shotPath)) report.image = fs.readFileSync(shotPath).toString('base64');
    const endPath = shotPath.replace(/\.jpg$/, '_end.jpg');
    if (shot && fs.existsSync(endPath)) report.image_end = fs.readFileSync(endPath).toString('base64');
    return report;
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
    release();
  }
}

/** Static guard for AI code: no file/OS/network/JS access, no loading outside the game's own files. */
const BANNED = [
  [/\bOS\s*\./, 'OS'], [/\bFileAccess\b/, 'FileAccess'], [/\bDirAccess\b/, 'DirAccess'], [/\bJavaScriptBridge\b/, 'JavaScriptBridge'],
  [/\bJavaScriptObject\b/, 'JavaScriptObject'], [/\bHTTPRequest\b|\bHTTPClient\b|\bStreamPeer|\bPacketPeer|\bWebSocket|\bTCPServer|\bUDPServer|\bENet/, '网络'],
  [/\bResourceLoader\b|\bResourceSaver\b/, 'ResourceLoader'], [/(^|[^\w.])load\s*\(/, 'load()'], [/\bProjectSettings\b/, 'ProjectSettings'],
  [/\bEngine\s*\.\s*(get_singleton|register)/, 'Engine singleton'], [/\bClassDB\b/, 'ClassDB'], [/\bExpression\b/, 'Expression'],
  [/\bThread\b|\bMutex\b|\bSemaphore\b|\bWorkerThreadPool\b/, '线程'], [/\.quit\s*\(/, 'quit()'], [/change_scene/, 'change_scene'],
  [/\bGDScript\s*\.\s*new\b|\.source_code\b/, '动态脚本'], [/\bset_script\s*\(/, 'set_script'], [/@tool\b/, '@tool'], [/\bclass_name\b/, 'class_name'],
  [/\bDisplayServer\b/, 'DisplayServer'], [/\bget_node\s*\(\s*["']\/root/, '访问平台节点'],
];
/** Banned API uses, as "file:line 禁止使用 X" (comments and string literals are ignored). */
export function bannedIssues(file, src) {
  const issues = [];
  String(src).split('\n').forEach((l, i) => {
    const code = l.replace(/#.*$/, '').replace(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/g, '""');
    for (const [re, what] of BANNED) if (re.test(code)) issues.push(file + ':' + (i + 1) + ' 禁止使用 ' + what);
  });
  return issues;
}

export function staticCheck(file, src) {
  const issues = [];
  if (!/^[a-z][a-z0-9_]{0,40}\.gd$/.test(file)) issues.push('文件名只能是小写字母/数字/下划线 + .gd：' + file);
  if (src.length > 60000) issues.push(file + ' 太长（>60KB），请拆成更多模块');
  issues.push(...bannedIssues(file, src));
  src.split('\n').forEach((l, i) => {
    const pm = l.match(/preload\s*\(\s*["']([^"']+)["']/);
    if (pm && !/^[a-z][a-z0-9_]*\.gd$/.test(pm[1])) issues.push(file + ':' + (i + 1) + ' preload 只能引用本游戏的其它模块，写成 preload("deck.gd")');
  });
  if (!/^\s*extends\s+\w+/m.test(src)) issues.push(file + ' 第一行需要 extends（Node / Node2D / Control / RefCounted …）');
  return issues;
}
