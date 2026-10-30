// 造梦 UGC platform demo server: projects, AI agent, asset pipeline, SSE build stream, feed.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';
import { runAgent, compactHistory, MODEL } from './agent.mjs';
import { GameEngine, emptyGame, checkGame } from './engine.mjs';
import { AssetFactory } from './aigc.mjs';
import { wantsCodeEngine, planGame, runProgrammer, runCrewBuild, CREW, CODE_MODEL, codeTail, readyAssets } from './codegen.mjs';
import { parsePartialJson } from './json.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const WEB = path.join(ROOT, 'web');
const DATA = path.join(ROOT, 'data');
const PORT = Number(process.env.PORT || 5300);
fs.mkdirSync(path.join(DATA, 'projects'), { recursive: true });
fs.mkdirSync(path.join(DATA, 'covers'), { recursive: true });
const factory = new AssetFactory(DATA);

// ---------------- storage ----------------
const projects = new Map();
const uid = () => crypto.randomBytes(5).toString('hex');
const now = () => Date.now();

class Project {
  constructor(d) {
    Object.assign(this, {
      id: uid(), owner: 'me', created: now(), updated: now(), game: emptyGame(), messages: [], chat: [], timeline: [], versions: [],
      published: null, running: false, prompt: '',
    }, d);
    this.assetJobs = [];
    this.clients = new Set();
    this.seq = 0;         // monotonic id for every event, so a reconnecting client can resume
    this.log = [];        // recent events, replayed to pollers (see GET .../events?since=)
    this.abort = null;
  }
  file() { return path.join(DATA, 'projects', this.id + '.json'); }
  save() {
    this.updated = now();
    const { clients, abort, assetJobs, ...rest } = this;
    fs.writeFileSync(this.file(), JSON.stringify(rest));
  }
  assetStates() {
    const out = {};
    for (const [id, a] of Object.entries(this.game.assets || {})) out[id] = { kind: a.kind, state: a.state, url: a.url || '', name: a.name };
    return out;
  }
  emit(ev) {
    ev.t = now();
    ev.seq = ++this.seq;
    if (['tool_done', 'user', 'assistant', 'asset', 'turn_end', 'check', 'plan', 'error', 'design', 'test', 'roadmap'].includes(ev.type)) {
      this.timeline.push(ev);
      if (this.timeline.length > 3000) this.timeline.splice(0, this.timeline.length - 3000);
    }
    this.log.push(ev);
    if (this.log.length > 4000) this.log.splice(0, this.log.length - 4000);
    const line = 'data: ' + JSON.stringify(ev) + '\n\n';
    for (const c of this.clients) c.write(line);
  }
}

for (const f of fs.readdirSync(path.join(DATA, 'projects'))) {
  try {
    const p = new Project(JSON.parse(fs.readFileSync(path.join(DATA, 'projects', f), 'utf8')));
    p.running = false;
    for (const a of Object.values(p.game.assets || {})) if (a.state === 'pending') a.state = 'failed';
    projects.set(p.id, p);
  } catch (e) { console.error('load project', f, e.message); }
}

// ---------------- asset worker ----------------
let activeAssets = 0;
const assetQueue = [];
function enqueueAssets(p, ids) {
  for (const id of ids) assetQueue.push({ p, id });
  pumpAssets();
}
function pumpAssets() {
  while (activeAssets < 6 && assetQueue.length) {
    const { p, id } = assetQueue.shift();
    const a = p.game.assets[id];
    if (!a || a.state !== 'pending') continue;
    activeAssets++;
    const t0 = now();
    p.emit({ type: 'asset', id, kind: a.kind, name: a.name, prompt: a.prompt, state: 'pending', stage: 'queued' });
    factory.generate(a, p.game.meta, (stage, extra = {}) => {
      p.emit({ type: 'asset_stage', id, kind: a.kind, name: a.name, stage, ...extra });
    }).then(r => {
      const cur = p.game.assets[id];
      if (!cur || cur.prompt !== a.prompt) return;
      Object.assign(cur, { state: 'ready', url: r.url, preview: r.preview || r.source || '', ms: now() - t0 }, r.kind ? { kind: r.kind, fallback: r.fallback } : {});
      p.emit({ type: 'asset', id, kind: cur.kind, fallback: cur.fallback, name: a.name, state: 'ready', url: r.url, preview: cur.preview, ms: cur.ms });
      p.save();
    }).catch(e => {
      const cur = p.game.assets[id];
      if (cur && cur.prompt === a.prompt) { cur.state = 'failed'; cur.error = String(e.message || e).slice(0, 200); }
      p.emit({ type: 'asset', id, kind: a.kind, name: a.name, state: 'failed', error: String(e.message || e).slice(0, 200) });
      p.save();
    }).finally(() => { activeAssets--; pumpAssets(); });
  }
}

// ---------------- agent run ----------------
function partialSummary(name, json) {
  if (name === 'add_entities') {
    const n = (json.match(/"kind"\s*:/g) || []).length;
    const step = (json.match(/"step"\s*:\s*"([^"]*)/) || [])[1];
    const names = [...json.matchAll(/"name"\s*:\s*"([^"]+)"/g)].map(m => m[1]);
    return { step, count: n, last: names[names.length - 1] || '' };
  }
  if (name === 'generate_assets') {
    const names = [...json.matchAll(/"name"\s*:\s*"([^"]+)"/g)].map(m => m[1]);
    return { count: names.length, last: names[names.length - 1] || '' };
  }
  if (name === 'plan_game') {
    return { title: (json.match(/"title"\s*:\s*"([^"]*)/) || [])[1] || '', steps: [...json.matchAll(/"steps"[\s\S]*/g)].length ? (json.split('"steps"')[1] || '').match(/"([^"]+)"/g)?.map(s => s.slice(1, -1)) || [] : [] };
  }
  return {};
}

/** Which agent handles this turn: code engine for existing code games and non-platformer requests. */
function isCodeTurn(p, text, opts) {
  if (p.game.meta.engine === 'code') return true;
  const isNew = Object.keys(p.game.entities).length === 0;
  return isNew && wantsCodeEngine((p.game.meta.genre_hint || '') + ' ' + text, opts.dimension || p.game.meta.dimension);
}

/** Progress shown while the model is still streaming a tool call's JSON. */
function codeProgress(name, json) {
  const step = (json.match(/"step"\s*:\s*"((?:[^"\\]|\\.)*)"/) || [])[1];
  const file = (json.match(/"file"\s*:\s*"([^"]*)"/) || [])[1];
  const ci = json.indexOf('"code"');
  const lines = ci >= 0 ? json.slice(ci).split('\\n').length : 0;
  const title = (json.match(/"title"\s*:\s*"((?:[^"\\]|\\.)*)"/) || [])[1];
  const sections = name === 'design_game' ? ['closest_game', 'core_loop', 'rules', 'layout', 'modules', 'milestones', 'build_steps', 'palette'].filter(k => json.includes('"' + k + '"')).length : 0;
  return { step, file, lines, title, sections };
}

const thinkLine = s => s.replace(/\s+/g, ' ').trim();

async function runCodeChat(p, text, opts = {}) {
  p.running = true;
  const g = p.game;
  const isFirst = !g.design;
  p.chat.push({ role: 'user', text, t: now() });
  p.emit({ type: 'user', text });
  const ac = new AbortController();
  p.abort = ac;
  const startT = now();
  let toolCount = 0;
  const texts = {};
  const flushText = agent => {
    for (const a of agent ? [agent] : Object.keys(texts)) {
      const s = texts[a];
      if (s && s.trim()) { p.chat.push({ role: 'assistant', agent: a, text: s, t: now() }); p.emit({ type: 'assistant', agent: a, text: s }); }
      texts[a] = '';
    }
  };
  const toolNames = {};
  let onDesign = null;
  /** Callbacks for one agent: everything it streams is tagged with its id so the UI can give it a lane and a drone. */
  const cbFor = agent => {
    const last = {};
    let think = '', thinkAt = 0;
    return {
      onText: d => { if (!d) return; texts[agent] = (texts[agent] || '') + d; p.emit({ type: 'text', agent, delta: d }); },
      onThinking: d => {
        think += d;
        const t = now();
        if (t - thinkAt < 400) return;
        thinkAt = t;
        p.emit({ type: 'thinking', agent, text: thinkLine(think).slice(-220) });
      },
      onToolStart: (id, name) => {
        flushText(agent); think = '';
        toolNames[id] = name; toolCount++;
        p.emit({ type: 'tool_start', id, name, agent });
      },
      onToolDelta: (id, json) => {
        const t = now();
        const name = toolNames[id];
        if (t - (last[id] || 0) < (name === 'design_game' ? 250 : 160)) return;
        last[id] = t;
        const ev = { type: 'tool_progress', id, name, agent, ...codeProgress(name, json) };
        if (name === 'write_module' || name === 'patch_module') Object.assign(ev, codeTail(json) || {});
        if (name === 'design_game') { const part = parsePartialJson(json); if (part) { ev.partial = part; onDesign?.(part); } }
        p.emit(ev);
      },
    };
  };
  let finish = null;
  p.emit({ type: 'turn_start', model: CODE_MODEL, engine: 'code', crew: CREW, first: isFirst });
  const queued = new Set(Object.keys(g.assets || {}));
  const queueAsset = a => {
    const id = String(a.id).slice(0, 30).replace(/[^\w-]/g, '_') || 'art';
    if (queued.has(id) || queued.size >= 3) return;
    queued.add(id);
    g.assets[id] = { id, kind: a.kind === 'sprite' ? 'sprite' : 'background', name: String(a.name || '').slice(0, 20), prompt: String(a.prompt).slice(0, 400), state: 'pending', url: '' };
    p.emit({ type: 'ops', ops: [{ op: 'asset', id, kind: g.assets[id].kind, state: 'pending', url: '' }] });
    p.emit({ type: 'crew', agent: 'C', state: 'thinking', text: '先去画素材：' + g.assets[id].name });
    enqueueAssets(p, [id]);
  };
  try {
    if (isFirst) {
      p.emit({ type: 'phase', phase: 'design', text: '策划师正在构思玩法、规则和开发路线…', agents: ['A'] });
      p.emit({ type: 'crew', agent: 'A', state: 'thinking', text: '理解你的想法…' });
      // art can start while the rest of the design is still being written
      onDesign = part => {
        if (Array.isArray(part.palette) && part.palette.length >= 3 && !g.meta.palette?.length) g.meta = { ...g.meta, palette: part.palette.filter(h => /^#?[0-9a-f]{6}$/i.test(String(h))) };
        if (typeof part.art_bible === 'string' && 'assets' in part) g.meta = { ...g.meta, art_bible: part.art_bible };
        if (g.meta.art_bible) for (const a of readyAssets(part)) queueAsset(a);
      };
      const orientation = g.meta.orientation || 'landscape';
      const design = await planGame((g.meta.genre_hint ? '【类型】' + g.meta.genre_hint + '\n' : '') + text, { cb: cbFor('A'), signal: ac.signal, orientation });
      design.orientation = orientation;
      onDesign = null;
      g.design = design;
      g.meta = { ...g.meta, title: design.title, pitch: design.pitch, dimension: '2d', engine: 'code', genre: design.genre, style: 'flat', filter: 'smooth',
        palette: design.palette, art_bible: design.art_bible, goal_text: design.goal_text, controls: design.controls, orientation };
      g.code = { files: {} };
      p.emit({ type: 'design', design, agent: 'A' });
      p.emit({ type: 'crew', agent: 'A', state: 'done', text: '方案交给团队啦' });
      p.emit({ type: 'ops', ops: [{ op: 'set_meta', meta: g.meta, label: '开工：' + design.title, agent: 'A' }] });
      for (const a of design.assets) queueAsset(a);
      p.save();
    }
    const hooks = {
      emit: ev => {
        // test screenshots go to disk; the stream and the saved timeline only carry a URL
        if (ev.type === 'test' && ev.shot) { const f = p.id + '_t' + now() + '.jpg'; try { fs.writeFileSync(path.join(DATA, 'covers', f), Buffer.from(ev.shot, 'base64')); ev = { ...ev, shot: '/covers/' + f }; } catch { ev = { ...ev, shot: '' }; } }
        if (ev.type === 'code_write') { p.emit({ ...ev, code: undefined, preview: ev.code.slice(0, 9000) }); } else p.emit(ev); },
      pushCode: (files, label, agent) => { p.emit({ type: 'ops', ops: [{ op: 'code', files, label: label || '', agent: agent || 'B' }] }); p.save(); },
    };
    let session;
    if (isFirst && process.env.UGC_CREW !== '0') {
      ({ session } = await runCrewBuild({ game: g, userText: text, hooks, cbFor, signal: ac.signal }));
    } else {
      p.emit({ type: 'phase', phase: 'code', text: '玩法程序员开始写代码', agents: ['B'] });
      p.emit({ type: 'crew', agent: 'B', state: 'thinking', text: '看看要改哪里…' });
      ({ session } = await runProgrammer({ game: g, userText: text, isFirst, hooks, cbFor, signal: ac.signal }));
    }
    finish = session.finish;
    if (finish?.milestone_done) {
      const i = g.design.milestones.findIndex(m => m.id === finish.milestone_done);
      if (i >= g.design.current) g.design.current = i + 1;
      p.emit({ type: 'roadmap', milestones: g.design.milestones, current: g.design.current });
    }
  } catch (e) {
    if (ac.signal.aborted) p.emit({ type: 'error', message: '已停止' });
    else { console.error(e); p.emit({ type: 'error', message: String(e.message || e).slice(0, 300) }); }
  } finally {
    flushText();
    if (finish?.summary) p.chat.push({ role: 'assistant', text: finish.summary, suggestions: finish.suggestions || [], t: now() });
    p.versions.push({ v: p.versions.length + 1, t: now(), prompt: text, game: JSON.parse(JSON.stringify(p.game)) });
    if (p.versions.length > 30) p.versions.shift();
    p.running = false;
    p.abort = null;
    p.save();
    p.emit({ type: 'turn_end', summary: finish?.summary || '', suggestions: finish?.suggestions || [], version: p.versions.length, ms: now() - startT, tools: toolCount });
  }
}

async function runChat(p, text, opts = {}) {
  if (p.running) throw new Error('busy');
  if (isCodeTurn(p, text, opts)) return runCodeChat(p, text, opts);
  p.running = true;
  const isNew = Object.keys(p.game.entities).length === 0;
  let content = text;
  if (opts.dimension && isNew) content = '【用户选择：' + (opts.dimension === '3d' ? '3D' : '2D') + ' 游戏】' + text;
  if (!isNew) {
    const g = p.game;
    const brief = Object.values(g.entities).map(e => e.id + '(' + e.kind + (e.name ? ',' + e.name : '') + ') @' + JSON.stringify(e.position) + ' size' + JSON.stringify(e.size) + (e.asset ? ' asset=' + e.asset : '')).join('\n');
    content = '【当前游戏状态】\nmeta: ' + JSON.stringify(g.meta) + '\nworld: ' + JSON.stringify(g.world) + '\nrules: ' + JSON.stringify(g.rules) + '\nplayer: ' + JSON.stringify(g.player) + '\nassets: ' + JSON.stringify(Object.values(g.assets).map(a => ({ id: a.id, kind: a.kind, name: a.name, state: a.state }))) + '\nentities:\n' + brief + '\n\n【用户的新要求】' + text;
    if (opts.selection) content += '\n（用户当前在画面里选中了：' + opts.selection + '）';
  }
  p.chat.push({ role: 'user', text, t: now() });
  p.emit({ type: 'user', text });
  p.messages = compactHistory(p.messages);
  p.messages.push({ role: 'user', content });
  const engine = new GameEngine(p);
  const ac = new AbortController();
  p.abort = ac;
  let assistantText = '';
  let toolCount = 0;
  const startT = now();
  p.emit({ type: 'turn_start', model: MODEL });
  try {
    await runAgent({
      messages: p.messages,
      signal: ac.signal,
      cb: {
        onText: d => { if (!d) return; assistantText += d; p.emit({ type: 'text', delta: d }); },
        onToolStart: (id, name) => {
          if (assistantText.trim()) { p.chat.push({ role: 'assistant', text: assistantText, t: now() }); p.emit({ type: 'assistant', text: assistantText }); }
          assistantText = '';
          (p._toolNames ||= {})[id] = name;
          p.emit({ type: 'tool_start', id, name });
        },
        onToolDelta: (() => { const last = {}; return (id, json) => { const t = now(); if (t - (last[id] || 0) < 120) return; last[id] = t; const name = (p._toolNames || {})[id]; p.emit({ type: 'tool_progress', id, ...partialSummary(name || guessName(json), json) }); }; })(),
      },
      exec: async (name, input, id) => {
        toolCount++;
        const { ops, jobs, result } = engine.apply(name, input);
        if (ops.length) p.emit({ type: 'ops', id, ops });
        const card = { type: 'tool_done', id, name, input: slimInput(name, input), result: name === 'check_game' ? result : undefined, opCount: ops.length };
        p.emit(card);
        if (name === 'plan_game') p.emit({ type: 'plan', title: input.title, pitch: input.pitch, steps: input.steps || [], dimension: input.dimension, style: input.style });
        if (name === 'check_game') p.emit({ type: 'check', ...result });
        if (jobs && jobs.length) enqueueAssets(p, jobs);
        p.save();
        // pace: give the browser time to animate before the model continues
        return result;
      },
    });
  } catch (e) {
    if (ac.signal.aborted) p.emit({ type: 'error', message: '已停止' });
    else { console.error(e); p.emit({ type: 'error', message: String(e.message || e).slice(0, 300) }); }
  } finally {
    if (assistantText.trim()) { p.chat.push({ role: 'assistant', text: assistantText, t: now() }); p.emit({ type: 'assistant', text: assistantText }); }
    const fin = [...p.messages].reverse().find(m => m.role === 'assistant' && Array.isArray(m.content) && m.content.some(b => b.type === 'tool_use' && b.name === 'finish'));
    const finInput = fin ? fin.content.find(b => b.name === 'finish').input : null;
    if (finInput && finInput.summary) p.chat.push({ role: 'assistant', text: finInput.summary, suggestions: finInput.suggestions || [], t: now() });
    p.versions.push({ v: p.versions.length + 1, t: now(), prompt: text, game: JSON.parse(JSON.stringify(p.game)) });
    if (p.versions.length > 30) p.versions.shift();
    p.running = false;
    p.abort = null;
    p.save();
    p.emit({ type: 'turn_end', summary: finInput?.summary || '', suggestions: finInput?.suggestions || [], version: p.versions.length, ms: now() - startT, tools: toolCount });
  }
}
function guessName(json) { return /"entities"/.test(json) ? 'add_entities' : /"assets"/.test(json) ? 'generate_assets' : /"steps"/.test(json) ? 'plan_game' : ''; }
function slimInput(name, input) {
  const list = v => (Array.isArray(v) ? v.filter(x => x && typeof x === 'object') : []);
  if (name === 'add_entities') return { step: input.step, entities: list(input.entities).map(e => ({ id: e.id, kind: e.kind, name: e.name })) };
  if (name === 'update_entities') return { step: input.step, changes: list(input.changes).map(c => ({ id: c.id, keys: Object.keys(c).filter(k => k !== 'id') })) };
  if (name === 'generate_assets') return { assets: list(input.assets).map(a => ({ id: a.id, kind: a.kind, name: a.name, prompt: a.prompt, apply_to: a.apply_to })) };
  return input;
}

// ---------------- http ----------------
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.json': 'application/json', '.glb': 'model/gltf-binary', '.mp3': 'audio/mpeg', '.ico': 'image/x-icon', '.ttf': 'font/ttf', '.webp': 'image/webp' };

function send(res, code, obj) {
  const body = typeof obj === 'string' ? obj : JSON.stringify(obj);
  res.writeHead(code, { 'content-type': typeof obj === 'string' ? 'text/plain; charset=utf-8' : 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  res.end(body);
}
// Godot's web build ships a ~40 MB .wasm; over a phone link that is minutes of nothing unless
// we gzip it. Text-like files and wasm compress well (wasm → ~9 MB), so serve them encoded.
const GZIP_EXT = new Set(['.wasm', '.js', '.mjs', '.html', '.css', '.json', '.svg', '.txt']);
const GZIP_MIN = 1024;
const gzCache = new Map();   // file -> { mtime, size, buf }
function gzipFile(file, st, cb) {
  const hit = gzCache.get(file);
  if (hit && hit.mtime === st.mtimeMs && hit.size === st.size) return cb(null, hit.buf);
  zlib.gzip(fs.readFileSync(file), { level: 9 }, (err, buf) => {
    if (err) return cb(err);
    gzCache.set(file, { mtime: st.mtimeMs, size: st.size, buf });
    cb(null, buf);
  });
}
function serveFile(req, res, file, cache = 'no-cache') {
  fs.stat(file, (err, st) => {
    if (err || !st.isFile()) return send(res, 404, 'not found');
    const ext = path.extname(file).toLowerCase();
    const headers = { 'content-type': MIME[ext] || 'application/octet-stream', 'cache-control': cache, 'access-control-allow-origin': '*', 'cross-origin-resource-policy': 'cross-origin', 'cross-origin-embedder-policy': 'require-corp', 'cross-origin-opener-policy': 'same-origin' };
    const wantsGzip = GZIP_EXT.has(ext) && st.size >= GZIP_MIN && /\bgzip\b/.test(req.headers['accept-encoding'] || '');
    if (!wantsGzip) {
      headers['content-length'] = st.size;
      res.writeHead(200, headers);
      if (req.method === 'HEAD') return res.end();
      return fs.createReadStream(file).pipe(res);
    }
    gzipFile(file, st, (e2, buf) => {
      if (e2) { headers['content-length'] = st.size; res.writeHead(200, headers); return fs.createReadStream(file).pipe(res); }
      headers['content-encoding'] = 'gzip';
      headers['content-length'] = buf.length;
      headers.vary = 'accept-encoding';
      res.writeHead(200, headers);
      res.end(req.method === 'HEAD' ? undefined : buf);
    });
  });
}
async function readBody(req, limit = 8 * 1024 * 1024) {
  const chunks = [];
  let n = 0;
  for await (const c of req) { n += c.length; if (n > limit) throw new Error('body too large'); chunks.push(c); }
  const s = Buffer.concat(chunks).toString('utf8');
  return s ? JSON.parse(s) : {};
}
function projectView(p) {
  return { id: p.id, game: p.game, chat: p.chat, running: p.running, versions: p.versions.map(v => ({ v: v.v, t: v.t, prompt: v.prompt })), published: p.published, updated: p.updated, created: p.created, model: p.game.meta.engine === 'code' ? CODE_MODEL : MODEL };
}
function feedItem(p) {
  const g = p.published.game;
  return { id: p.id, title: g.meta.title, pitch: g.meta.pitch || '', dimension: g.meta.dimension, orientation: g.meta.orientation || 'landscape', engine: g.meta.engine || '', genre: g.meta.genre, style: g.meta.style, cover: p.published.cover, author: p.published.author || '造梦玩家', plays: p.published.plays || 0, likes: p.published.likes || 0, t: p.published.t, prompt: p.prompt, remixOf: p.remixOf || null };
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  const parts = url.pathname.split('/').filter(Boolean);
  try {
    if (parts[0] === 'api') {
      const [, a, id, b] = parts;
      if (a === 'feed' && req.method === 'GET') {
        const list = [...projects.values()].filter(p => p.published).map(feedItem);
        const sort = url.searchParams.get('sort') || 'hot';
        list.sort((x, y) => sort === 'new' ? y.t - x.t : (y.plays + y.likes * 3) - (x.plays + x.likes * 3) || y.t - x.t);
        return send(res, 200, list);
      }
      if (a === 'me' && req.method === 'GET') {
        const mine = [...projects.values()].filter(p => p.owner === 'me').sort((x, y) => y.updated - x.updated).map(p => ({ id: p.id, title: p.game.meta.title, dimension: p.game.meta.dimension, orientation: p.game.meta.orientation || 'landscape', entities: Object.keys(p.game.entities).length, published: !!p.published, cover: p.published?.cover || p.draftCover || '', updated: p.updated, plays: p.published?.plays || 0, likes: p.published?.likes || 0 }));
        return send(res, 200, mine);
      }
      if (a === 'games' && id && req.method === 'GET' && !b) {
        const p = projects.get(id);
        if (!p || !p.published) return send(res, 404, { error: 'not found' });
        return send(res, 200, { ...feedItem(p), spec: p.published.game, assets: p.published.assets });
      }
      if (a === 'games' && id && b === 'play' && req.method === 'POST') {
        const p = projects.get(id); if (p?.published) { p.published.plays = (p.published.plays || 0) + 1; p.save(); }
        return send(res, 200, { ok: true });
      }
      if (a === 'games' && id && b === 'like' && req.method === 'POST') {
        const p = projects.get(id); if (p?.published) { p.published.likes = (p.published.likes || 0) + 1; p.save(); }
        return send(res, 200, { likes: p?.published?.likes || 0 });
      }
      if (a === 'projects' && !id && req.method === 'POST') {
        const body = await readBody(req);
        let p;
        if (body.remix) {
          const src = projects.get(body.remix);
          if (!src?.published) return send(res, 404, { error: 'source not found' });
          p = new Project({ game: JSON.parse(JSON.stringify(src.published.game)), remixOf: src.id, prompt: 'Remix: ' + src.published.game.meta.title });
          p.game.meta.title = src.published.game.meta.title + '（改编）';
          p.chat.push({ role: 'assistant', text: '已复制「' + src.published.game.meta.title + '」，告诉我你想怎么改编吧！比如换个主角、加个 Boss、改成夜晚……', t: now() });
          p.messages.push({ role: 'user', content: '（用户 Remix 了一个已发布的游戏，后续会提出修改要求）' }, { role: 'assistant', content: '好的，我会在现有游戏基础上修改。' });
          p.versions.push({ v: 1, t: now(), prompt: 'Remix', game: JSON.parse(JSON.stringify(p.game)) });
        } else {
          p = new Project({ prompt: body.prompt || '' });
          p.game.meta.orientation = body.orientation === 'portrait' ? 'portrait' : 'landscape';
          if (body.genre_hint) p.game.meta.genre_hint = String(body.genre_hint).slice(0, 20);
          if (body.dimension === '3d') { p.game.meta.dimension = '3d'; p.game.player.position = [0, 2, 0]; p.game.settings = { gravity: 24 }; }
        }
        projects.set(p.id, p);
        p.save();
        return send(res, 200, projectView(p));
      }
      const p = id ? projects.get(id) : null;
      if (a === 'projects' && id && !p) return send(res, 404, { error: 'not found' });
      if (a === 'projects' && p) {
        if (!b && req.method === 'GET') return send(res, 200, projectView(p));
        if (b === 'events' && (url.searchParams.get('since') !== null || url.searchParams.get('poll') !== null)) {
          // Polling twin of the SSE stream: proxies that buffer text/event-stream (mobile networks,
          // tunnels, corporate filters) make the live build invisible, so the client can fall back to
          // this. Same events, same order, resumed by seq.
          const since = Number(url.searchParams.get('since') || 0);
          const events = since > 0 ? p.log.filter(e => e.seq > since) : p.log.slice(-200);
          return send(res, 200, { events, seq: p.seq, running: !!p.running });
        }
        if (b === 'events') {
          // Reverse proxies (cloudflared, nginx, Cloudflare) buffer text/event-stream unless told not to.
          // no-transform + identity keep them from compressing, x-accel-buffering is nginx's switch, and
          // the 4 KB comment padding forces the very first TCP/QUIC frame out before any real event fires.
          res.writeHead(200, {
            'content-type': 'text/event-stream; charset=utf-8', 'cache-control': 'no-store, no-transform',
            'content-encoding': 'identity', 'connection': 'keep-alive', 'x-accel-buffering': 'no',
            'access-control-allow-origin': '*',
          });
          if (res.flushHeaders) res.flushHeaders();
          // named events (not comments): some proxies drop comment-only frames; EventSource.onmessage ignores 'ping'
          res.write('retry: 2000\nevent: ping\ndata: ' + JSON.stringify({ pad: '.'.repeat(2048) }) + '\n\n');
          p.clients.add(res);
          const ka = setInterval(() => res.write('event: ping\ndata: ' + Date.now() + '\n\n'), 10000);
          req.on('close', () => { clearInterval(ka); p.clients.delete(res); });
          return;
        }
        if (b === 'chat' && req.method === 'POST') {
          const body = await readBody(req);
          if (p.running) return send(res, 409, { error: 'AI 正在搭建中' });
          if (!p.prompt) p.prompt = body.text;
          runChat(p, String(body.text || '').slice(0, 2000), body).catch(e => console.error(e));
          return send(res, 200, { ok: true });
        }
        if (b === 'stop' && req.method === 'POST') { p.abort?.abort(); return send(res, 200, { ok: true }); }
        if (b === 'move' && req.method === 'POST') {
          const body = await readBody(req);
          if (body.id === '__player') p.game.player.position = body.position;
          else if (p.game.entities[body.id]) p.game.entities[body.id].position = body.position;
          p.save();
          return send(res, 200, { ok: true });
        }
        if (b === 'retry_assets' && req.method === 'POST') {
          const ids = Object.values(p.game.assets).filter(a => a.state === 'failed' || a.fallback).map(a => a.id);
          for (const id of ids) { const a = p.game.assets[id]; a.state = 'pending'; a.error = ''; if (a.fallback) { a.kind = 'model3d'; delete a.fallback; } p.emit({ type: 'asset', id, kind: a.kind, name: a.name, state: 'pending' }); }
          enqueueAssets(p, ids);
          p.save();
          return send(res, 200, { retried: ids });
        }
        if (b === 'check' && req.method === 'GET') return send(res, 200, checkGame(p.game));
        if (b === 'restore' && req.method === 'POST') {
          const body = await readBody(req);
          const v = p.versions.find(x => x.v === body.v);
          if (!v) return send(res, 404, { error: 'no version' });
          p.game = JSON.parse(JSON.stringify(v.game));
          p.chat.push({ role: 'assistant', text: '已回到第 ' + v.v + ' 版：「' + (v.prompt || '').slice(0, 30) + '」', t: now() });
          p.messages.push({ role: 'user', content: '（用户把游戏回退到了第 ' + v.v + ' 版，之后的修改已撤销）' }, { role: 'assistant', content: '明白，后续修改将基于回退后的版本。' });
          p.save();
          return send(res, 200, projectView(p));
        }
        if (b === 'cover' && req.method === 'POST') {
          const body = await readBody(req);
          if (body.data) { const f = p.id + '_draft.jpg'; fs.writeFileSync(path.join(DATA, 'covers', f), Buffer.from(body.data, 'base64')); p.draftCover = '/covers/' + f + '?t=' + now(); p.save(); }
          return send(res, 200, { ok: true });
        }
        if (b === 'publish' && req.method === 'POST') {
          const body = await readBody(req);
          let cover = p.published?.cover || p.draftCover || '';
          if (body.cover) { const f = p.id + '_' + now() + '.jpg'; fs.writeFileSync(path.join(DATA, 'covers', f), Buffer.from(body.cover, 'base64')); cover = '/covers/' + f; }
          if (body.title) p.game.meta.title = String(body.title).slice(0, 40);
          if (body.pitch) p.game.meta.pitch = String(body.pitch).slice(0, 120);
          if (body.prompt) p.prompt = String(body.prompt).slice(0, 300);
          const assets = p.assetStates();
          p.published = { ...(p.published || {}), game: JSON.parse(JSON.stringify(p.game)), assets, cover, t: now(), author: body.author || p.published?.author || '我', plays: p.published?.plays || 0, likes: p.published?.likes || 0 };
          p.save();
          return send(res, 200, { ok: true, id: p.id, url: '/play.html?id=' + p.id });
        }
        if (b === 'delete' && req.method === 'POST') { projects.delete(p.id); fs.rmSync(p.file(), { force: true }); return send(res, 200, { ok: true }); }
      }
      return send(res, 404, { error: 'no route' });
    }
    // static
    if (parts[0] === 'assets') return serveFile(req, res, path.join(DATA, 'assets', path.basename(url.pathname)), 'public, max-age=31536000, immutable');
    if (parts[0] === 'covers') return serveFile(req, res, path.join(DATA, 'covers', path.basename(url.pathname)), 'public, max-age=3600');
    let rel = decodeURIComponent(url.pathname);
    if (rel === '/' || rel === '') rel = '/index.html';
    const file = path.normalize(path.join(WEB, rel));
    if (!file.startsWith(WEB)) return send(res, 403, 'forbidden');
    const cache = rel.startsWith('/game/') && /\.(wasm)$/.test(rel) ? 'public, max-age=86400' : 'no-cache';
    return serveFile(req, res, file, cache);
  } catch (e) {
    console.error(e);
    send(res, 500, { error: String(e.message || e) });
  }
});
server.listen(PORT, () => console.log('造梦 UGC demo on http://127.0.0.1:' + PORT + '  model=' + MODEL));