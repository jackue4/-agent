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
import { wantsCodeEngine, runBuilder, roleOf, FILE_TOOLS, CREW, CODE_MODEL, codeTail, readyAssets } from './codegen.mjs';
import { LiveGame } from './live.mjs';
import { PlaytestWatch } from './playtest-watch.mjs';
import { BrowserPlaytest } from './browser-playtest.mjs';
import { moveConstruction } from './scene-edit.mjs';
import { commitConstruction, CONSTRUCTION_FILES } from './construction.mjs';
import { parsePartialJson } from './json.mjs';
import { GodotProject } from './gproject.mjs';
import { runProjectBuilder, gpRoleOf, GP_FILE_TOOLS, assetPath, assetsInUse } from './gpagent.mjs';
import { createWorkflow, recordEvidence, acceptanceFor, settleWorkflow, recoverWorkflow, resumeContext, invalidateWorkflow } from './workflow.mjs';
import { createIteration } from './iteration.mjs';
import { recordProductionActivity, requestedIterationOptions } from './production-activity.mjs';
import { enqueueParticipation, deliverParticipation } from './participation.mjs';
import { MODEL_OPTIONS, SKETCH_MODEL, SKETCH_FALLBACK_MODEL, assertModelSelection, resolveModelSelection } from './model-config.mjs';
import { SketchBoard, SketchArtist } from './sketch.mjs';
import { ArtDirector, artSlotsIn, mergeSlots } from './art-director.mjs';
import { assetIntent } from './art-intent.mjs';
import { ENHANCE_MODEL, enhanceUserPrompt, shouldEnhance } from './prompt-enhance.mjs';

/** New games are full Godot projects unless UGC_ENGINE=classic (spec templates + code SDK). */
const GP_ON = (process.env.UGC_ENGINE || 'godot') !== 'classic';
const isGp = g => g.meta.engine === 'godot';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const WEB = path.join(ROOT, 'web');
const DATA = path.resolve(process.env.UGC_DATA_DIR || path.join(ROOT, 'data'));
const PORT = Number(process.env.PORT || 5300);
const HOST = process.env.HOST || '10.0.4.94';
fs.mkdirSync(path.join(DATA, 'projects'), { recursive: true });
fs.mkdirSync(path.join(DATA, 'covers'), { recursive: true });
const factory = new AssetFactory(DATA);

// ---------------- storage ----------------
export const projects = new Map();
const uid = () => crypto.randomBytes(5).toString('hex');
const now = () => Date.now();

const SAVED_FIELDS = ['id', 'owner', 'created', 'updated', 'game', 'messages', 'chat', 'timeline', 'versions', 'published', 'running', 'prompt', 'draftCover', 'remixOf', 'codeLog', 'interrupted', 'workflow', 'build', 'sceneEdit', 'nextVersion', 'seq', 'log', 'participation', 'model', 'sketch', 'finalArt', 'artRequest'];
export class Project {
  constructor(d) {
    Object.assign(this, {
      id: uid(), owner: 'me', created: now(), updated: now(), game: emptyGame(), messages: [], chat: [], timeline: [], versions: [],
      published: null, running: false, prompt: '', workflow: null, build: null, nextVersion: 1, seq: 0, log: [],
    });
    for (const key of SAVED_FIELDS) if (d && Object.hasOwn(d, key)) this[key] = d[key];
    if (!/^[\w-]{1,128}$/.test(this.id)) throw new Error('无效项目 ID');
    this.seq = Math.max(0, Number.isSafeInteger(this.seq) ? this.seq : 0);
    this.log = (Array.isArray(this.log) ? this.log : []).filter(e => Number.isSafeInteger(e.seq) && e.seq <= this.seq).slice(-4000);
    this.nextVersion = Math.max(Number(this.nextVersion) || 1, 1, ...this.versions.map(v => (Number(v.v) || 0) + 1));
    this.assetJobs = [];
    this.clients = new Set();
    this.abort = null;
  }
  file() { return path.join(DATA, 'projects', this.id + '.json'); }
  save() {
    this.updated = now();
    const record = Object.fromEntries(SAVED_FIELDS.filter(key => this[key] !== undefined).map(key => [key, this[key]]));
    const target = this.file(), tmp = target + '.' + crypto.randomBytes(6).toString('hex') + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(record), { flag: 'wx' });
    fs.renameSync(tmp, target);
  }
  assetStates() {
    const out = {};
    for (const [id, a] of Object.entries(this.game.assets || {})) out[id] = { kind: a.kind, state: a.state, url: a.url || '', name: a.name, fallback: a.fallback || false };
    return out;
  }
  emit(ev) {
    ev = structuredClone(ev);
    ev.t = now();
    ev.seq = ++this.seq;
    const activity = recordProductionActivity(this.workflow, ev);
    if (activity) ev.activity = activity;
    if (ev.workflow?.id && this.workflow?.id === ev.workflow.id) ev.workflow.activity = structuredClone(this.workflow.activity || []);
    if (['tool_done', 'user', 'assistant', 'asset', 'turn_end', 'check', 'plan', 'error', 'design', 'test', 'roadmap', 'task', 'workflow', 'runtime_applied'].includes(ev.type)) {
      this.timeline.push(ev);
      if (this.timeline.length > 3000) this.timeline.splice(0, this.timeline.length - 3000);
    }
    this.log.push(ev);
    if (this.log.length > 4000) this.log.splice(0, this.log.length - 4000);
    const line = 'id: ' + ev.seq + '\ndata: ' + JSON.stringify(ev) + '\n\n';
    for (const c of this.clients) { try { c.write(line); } catch { this.clients.delete(c); } }
    try { this.sketchArtist?.observe(ev); } catch (error) { console.error('sketch observe', error); }
    // Persist meaningful checkpoints, not streamed code/thinking tokens.
    if (activity) this.save();
  }
}

export function sketchBoardOf(p) { return p.sketchBoard ||= new SketchBoard(p.sketch); }

/** Test/eval screenshots already on disk, as base64 for the sketch artist. */
function readCover(url) {
  const file = path.join(DATA, 'covers', path.basename(String(url).split('?')[0]));
  try { return fs.statSync(file).size < 1500000 ? fs.readFileSync(file).toString('base64') : null; } catch { return null; }
}

/** The sketch artist runs beside the builder for this round; it only reads builder events. */
function startSketch(p, { text, isFirst, signal }, deps) {
  const enabled = deps.sketchStream ? true : !(deps.runProjectBuilder || deps.runBuilder) && process.env.UGC_SKETCH !== '0';
  if (!enabled) return null;
  p.sketchArtist?.stop('stopped');
  const board = sketchBoardOf(p);
  const artist = new SketchArtist({
    board, prompt: text, model: process.env.UGC_SKETCH_MODEL || SKETCH_MODEL, fallbackModel: process.env.UGC_SKETCH_FALLBACK_MODEL || SKETCH_FALLBACK_MODEL, signal,
    orientation: p.game.meta.orientation, dimension: p.game.meta.dimension, design: p.game.design || null,
    keep: !isFirst && board.state.items.length > 0, runId: p.workflow?.id || uid(), readImage: readCover,
    ...(deps.sketchStream ? { stream: deps.sketchStream } : {}),
    onSave: () => { p.sketch = board.snapshot(); p.save(); },
    onStop: () => { if (p.sketchArtist === artist) p.sketchArtist = null; },
  });
  p.sketchArtist = artist;
  return artist.start();
}

function validateSelectedModel(value) {
  try { return assertModelSelection(value); }
  catch (error) { throw Object.assign(new Error(error.message), { statusCode: 400 }); }
}

export function projectModel(p) {
  return resolveModelSelection(p.model, { defaultModel: isGp(p.game) || p.game.meta.engine === 'code' ? CODE_MODEL : MODEL });
}

export function selectProjectModel(p, value) {
  if (p.running || p.mutating) throw Object.assign(new Error('制作进行中，请结束本轮后再切换'), { statusCode: 409 });
  const model = validateSelectedModel(value);
  p.model = model;
  p.save();
  return model;
}

function snapshotVersion(p, text, project = null) {
  const v = p.nextVersion++;
  p.versions.push({ v, t: now(), prompt: text, game: structuredClone(p.game), ...(project ? { gp: gpSnapshot(project) } : {}) });
  if (p.versions.length > 30) p.versions.shift();
  return v;
}

export function eventReplay(p, cursor = 0) {
  const since = Number.isSafeInteger(Number(cursor)) && Number(cursor) >= 0 ? Number(cursor) : 0;
  const firstSeq = p.log[0]?.seq ?? p.seq + 1;
  const reset = since > p.seq || since < firstSeq - 1;
  return { events: reset ? [] : p.log.filter(e => e.seq > since), seq: p.seq, firstSeq, reset, workflow: p.workflow, running: !!p.running };
}

const INTERRUPTED_NOTE = '上一轮搭建被打断了（平台重启）。回复「继续」我就按刚才的要求接着做。';

/** Text to run when the user asks to pick up a turn the server lost; drops the dangling request and notice. */
function resumeText(p, text) {
  if (!p.interrupted) return text;
  const extra = String(text || '').trim().replace(/^(继续|接着做|接着|continue|go on)[。.！!，, ]*/i, '');
  if (extra === String(text || '').trim() && extra) { p.interrupted = ''; return text; }
  const original = p.interrupted;
  p.interrupted = '';
  if (p.chat.at(-1)?.interrupted) p.chat.pop();
  if (p.chat.at(-1)?.role === 'user' && p.chat.at(-1).text === original) p.chat.pop();
  return extra ? original + '\n' + extra : original;
}

for (const f of fs.readdirSync(path.join(DATA, 'projects'))) {
  if (!/^[\w-]+\.json$/.test(f)) continue;
  try {
    const p = new Project(JSON.parse(fs.readFileSync(path.join(DATA, 'projects', f), 'utf8')));
    if (p.file() !== path.join(DATA, 'projects', f)) throw new Error('项目文件名与 ID 不匹配');
    const wasRunning = p.running || p.workflow?.status === 'running';
    recoverWorkflow(p.workflow);
    p.running = false;
    for (const a of Object.values(p.game.assets || {})) if (['pending', 'importing'].includes(a.state)) a.state = 'failed';
    const last = p.chat.at(-1);
    if (wasRunning || last?.role === 'user') {
      p.interrupted = p.workflow?.goal || (last?.role === 'user' ? last.text : p.prompt);
      p.chat.push({ role: 'assistant', text: INTERRUPTED_NOTE, t: now(), interrupted: true });
    }
    projects.set(p.id, p);
    if (wasRunning) p.save();
  } catch (e) { console.error('load project', f, e.message); }
}

// ---------------- asset worker ----------------
let activeAssets = 0;
const assetQueue = [];
function enqueueAssets(p, ids, control = {}) {
  for (const id of ids) assetQueue.push({ p, id, expected: p.game.assets[id], ...control });
  pumpAssets();
}
function pumpAssets() {
  while (activeAssets < 8 && assetQueue.length) {
    const { p, id, expected, signal: parentSignal, deadlineAt } = assetQueue.shift();
    const a = p.game.assets[id];
    if (!a || a !== expected || a.state !== 'pending') continue;
    const controller = new AbortController();
    const cancel = () => controller.abort(parentSignal.reason || new Error('本轮已停止，素材留待下一轮重试'));
    if (parentSignal?.aborted) cancel(); else parentSignal?.addEventListener('abort', cancel, { once: true });
    const timer = Number.isFinite(deadlineAt) ? setTimeout(() => controller.abort(new Error('已进入收口，未完成素材留待下一轮重试')), Math.max(0, deadlineAt - now())) : null;
    const current = () => projects.get(p.id) === p && p.game.assets[id] === a;
    const active = () => current() && !controller.signal.aborted;
    activeAssets++;
    const t0 = now();
    p.emit({ type: 'asset', id, kind: a.kind, name: a.name, prompt: a.prompt, state: 'pending', stage: 'queued', async: !!a.async });
    factory.generate(a, p.game.meta, (stage, extra = {}) => {
      if (active()) p.emit({ type: 'asset_stage', id, kind: a.kind, name: a.name, stage, ...extra });
    }, { signal: controller.signal }).then(r => {
      if (!active()) return;
      return applyGeneratedAsset(p, a, { ...r, ms: now() - t0 }, { signal: controller.signal });
    }).catch(e => {
      if (!current()) return;
      const cur = p.game.assets[id];
      if (cur) { cur.state = 'failed'; cur.error = String(e.message || e).slice(0, 200); }
      p.emit({ type: 'asset', id, kind: a.kind, name: a.name, state: 'failed', error: String(e.message || e).slice(0, 200), async: !!a.async });
      p.save();
    }).finally(() => { if (timer) clearTimeout(timer); parentSignal?.removeEventListener('abort', cancel); activeAssets--; pumpAssets(); });
  }
}

// ---------------- Godot projects ----------------
const godotProjects = new Map();
export function gpOf(p) {
  if (!godotProjects.has(p.id)) godotProjects.set(p.id, new GodotProject(p.id, { root: path.join(DATA, 'gprojects') }));
  return godotProjects.get(p.id);
}
const pckUrl = (p, build = p.build) => '/api/projects/' + p.id + '/game.pck?' + (build?.buildId ? 'build=' + encodeURIComponent(build.buildId) : 'v=' + encodeURIComponent(build?.version || p.game.meta.pck_version || ''));
const buildView = b => b ? Object.fromEntries(['buildId', 'sourceRevision', 'contentHash', 'version', 'bytes'].map(k => [k, b[k]])) : null;

function sourceManifestOf(p) {
  if (!isGp(p.game)) return null;
  const project = gpOf(p);
  if (!project.exists) return null;
  try {
    return { sourceRevision: project.revision(), files: project.list().map(file => file.path) };
  } catch {
    // A missing or unreadable source must never promote a planned module to saved.
    return null;
  }
}

function updateWorkflow(p, revision = '') {
  if (!p.workflow) return;
  p.workflow.sourceManifest = sourceManifestOf(p);
  if (p.workflow.completionRequested) settleWorkflow(p.workflow, revision || gpOf(p).revision());
  if (p.workflow.status === 'completed' && p.workflow.pendingMilestone && p.game.design) {
    const d = p.game.design, i = d.milestones.findIndex(m => m.id === p.workflow.pendingMilestone);
    if (i === d.current) { d.current++; p.emit({ type: 'roadmap', milestones: d.milestones, current: d.current }); }
    p.workflow.pendingMilestone = '';
  }
  p.emit({ type: 'workflow', workflow: p.workflow });
  p.save();
}

/** Ships a fresh build to every open preview. */
export function pushPck(p, b, label = '', agent = 'B') {
  if (!b?.ok || !b.buildId || gpOf(p).revision() !== b.sourceRevision) return false;
  const actual = gpOf(p).getBuild(b.buildId);
  if (!actual || actual.sourceRevision !== b.sourceRevision) return false;
  if (p.build && actual.version < p.build.version) return false;
  p.build = buildView(actual);
  if (p.sceneEdit) p.sceneEdit = { ...p.sceneEdit, dirty: false, sourceRevision: b.sourceRevision };
  p.game.meta.pck_version = actual.version;
  p.game.meta.build_id = b.buildId;
  p.game.meta.source_revision = b.sourceRevision;
  if (p.workflow && !p.workflow.evidence.some(e => e.kind === 'build' && e.buildId === b.buildId)) recordEvidence(p.workflow, { kind: 'build', ...actual });
  p.emit({ type: 'ops', ops: [{ op: 'pck', url: pckUrl(p), ...p.build, label, agent }] });
  if (p.workflow) updateWorkflow(p, b.sourceRevision);
  p.save();
  return true;
}

/** A generated file goes into res://assets/, the project is re-imported and the preview updated. */
export async function applyGeneratedAsset(p, asset, result, { signal, apply = gpAssetLanded } = {}) {
  const active = () => {
    if (signal?.aborted) throw signal.reason || new Error('素材导入已停止');
    if (projects.get(p.id) !== p || p.game.assets[asset.id] !== asset) throw new Error('素材任务已被替换');
  };
  active();
  Object.assign(asset, { state: 'importing', url: result.url, preview: result.preview || result.source || '', ms: result.ms }, result.kind ? { kind: result.kind, fallback: result.fallback } : {});
  p.emit({ type: 'asset_stage', id: asset.id, kind: asset.kind, name: asset.name, stage: 'importing' }); p.save();
  try {
    if (isGp(p.game)) await apply(p, asset, { signal });
    active();
    asset.state = 'ready';
    p.emit({ type: 'asset', id: asset.id, kind: asset.kind, fallback: asset.fallback, name: asset.name, state: 'ready', url: asset.url, preview: asset.preview, ms: asset.ms, async: !!asset.async }); p.save();
  } catch (error) {
    if (p.game.assets[asset.id] === asset) { asset.state = 'failed'; asset.error = String(error.message || error).slice(0, 200); p.save(); }
    throw error;
  }
}

async function gpAssetLanded(p, a, { signal } = {}) {
  try {
    const src = path.join(DATA, 'assets', path.basename(a.url));
    const rel = assetPath(a);
    const project = gpOf(p);
    if (!project.exists || !fs.existsSync(src)) throw new Error('素材文件尚未准备好，不能标记已导入');
    if (a.async) return landArt(p, a, { signal });
    await project.withLock(async () => {
      if (signal?.aborted) throw signal.reason || new Error('素材导入已停止');
      if (projects.get(p.id) !== p || p.game.assets[a.id] !== a) throw new Error('素材任务已被替换');
      project.writeAsset(rel, fs.readFileSync(src));
      invalidateWorkflow(p.workflow, '素材已更新，需要重新运行当前版本的检查与测试');
      p._gpSession?.note('素材到了：' + a.id + '（' + a.kind + '）→ res://' + rel + '，已经可以 load。确认代码里用到了它（替换掉对应的占位），然后 run_game 看一眼效果。');
      const b = await project.build({ signal });
      if (signal?.aborted) throw signal.reason || new Error('素材导入已停止');
      if (b.ok) pushPck(p, b, '素材到了：' + (a.name || a.id), 'A');
      else { if (p.workflow) updateWorkflow(p); throw new Error(b.error || '素材导入后构建失败'); }
    });
  } catch (e) { console.error('asset to project', e); throw e; }
}

// ---------------- art director (async final art, from the second round on) ----------------
const ART_FLUSH_MS = 6000;
/** Art written into a running round only well before its wrap-up, so final verification is stable. */
const artHeld = p => p.running && now() >= (p.workflow?.iteration?.wrapAt || Infinity) - 30000;
const codeHashOf = project => crypto.createHash('sha256').update(JSON.stringify(gpSnapshot(project) || {})).digest('hex');

/** Latest real gameplay screenshot (browser or native eval/test), base64 jpeg. */
function latestShot(p) {
  for (let i = p.log.length - 1; i >= 0; i--) {
    const ev = p.log[i];
    if ((ev.type === 'eval' || ev.type === 'test') && /^\/covers\//.test(ev.shot || '')) { const b = readCover(ev.shot); if (b) return b; }
  }
  return p.draftCover ? readCover(p.draftCover) : null;
}

/** A finished art file goes into the project; builds are batched so a burst of art costs one export. */
async function landArt(p, a, { signal } = {}) {
  const src = path.join(DATA, 'assets', path.basename(a.url));
  (p.artPending ||= new Map()).set(a.id, { rel: assetPath(a), src, name: a.name || a.id });
  if (signal?.aborted) throw signal.reason || new Error('美术导入已停止');
  if (!artHeld(p)) scheduleArtFlush(p);
}
function scheduleArtFlush(p, ms = ART_FLUSH_MS) {
  clearTimeout(p.artFlushTimer);
  p.artFlushTimer = setTimeout(() => { p.artFlushTimer = null; flushArt(p).catch(e => console.error('art flush', e)); }, ms);
}
export async function flushArt(p, { project = gpOf(p), verify = reverifyArt } = {}) {
  if (!p.artPending?.size || artHeld(p) || p.artFlushing) return null;
  p.artFlushing = true;
  try {
    const batch = [...p.artPending.entries()];
    p.artPending = new Map();
    let built = null;
    await project.withLock(async () => {
      for (const [, f] of batch) if (fs.existsSync(f.src)) project.writeAsset(f.rel, fs.readFileSync(f.src));
      invalidateWorkflow(p.workflow, '正式美术已替换铅笔稿，正在重新检查当前版本');
      built = await project.build({});
      if (built.ok) pushPck(p, built, '正式美术：' + batch.map(([, f]) => f.name).slice(0, 4).join('、') + (batch.length > 4 ? ' 等 ' + batch.length + ' 项' : ''), 'A');
      else if (p.workflow) updateWorkflow(p);
    });
    const ids = batch.map(([id]) => id);
    if (p.running) p._gpSession?.note('美术子代理已把这些铅笔美术位换成正式美术：' + ids.join('、') + '。代码无需改动；之后的试玩和测试针对最新版本。不要再为这些美术位申请素材。');
    else await verify(p, ids, { project });
    return { ids, built };
  } finally {
    p.artFlushing = false;
    if (p.artPending?.size && !artHeld(p)) scheduleArtFlush(p, 1000);
  }
}

/** After a round, art-only changes are re-verified automatically so the round's acceptance survives. */
export async function reverifyArt(p, ids = [], { project = gpOf(p) } = {}) {
  const run = p.workflow;
  if (p.running || !run) return null;
  const rev = project.revision();
  const c = await project.check({});
  const compiled = c.loaded && c.ok !== false && !(c.errors || []).some(e => e.kind !== 'warning');
  recordEvidence(run, { kind: 'compile', sourceRevision: c.sourceRevision || rev, ok: compiled, errors: c.errors });
  let t = null;
  if (compiled) {
    t = await project.selfTest({ orientation: p.game.meta.orientation === 'portrait' ? 'portrait' : 'landscape', shot: true, sourceRevision: c.sourceRevision });
    t.ok = t.ok && t.checks?.length > 0 && t.checks.every(x => x.ok) && !(t.errors || []).some(e => e.kind !== 'warning');
    recordEvidence(run, { kind: 'test', sourceRevision: t.sourceRevision, ok: t.ok, checks: t.checks || [], errors: t.errors || [] });
  }
  const latest = project.latestBuild;
  if (latest?.sourceRevision === rev) recordEvidence(run, { kind: 'build', ...latest, ok: true });
  if (compiled && t?.ok && run.artBase?.codeHash === codeHashOf(project) && run.artBase.played) {
    recordEvidence(run, { kind: 'play', sourceRevision: rev, ok: true, summary: '仅替换美术素材、代码未变：沿用本轮真实输入试玩结果（' + run.artBase.played + '）' });
  }
  if (p.running || p.workflow !== run) return null;
  if (run.artBase?.accepted) run.completionRequested = true;
  updateWorkflow(p, rev);
  const shot = t?.image_end || t?.image;
  const ev = shot ? shotToDisk(p, { shot }) : {};
  p.emit({ type: 'art', state: 'verified', ok: !!(compiled && t?.ok), ids, image: ev.shot || '', note: compiled && t?.ok ? '编译与 ' + t.checks.length + ' 项玩法断言通过' : '复验未通过：' + String((t?.errors || c.errors || [])[0]?.message || (t?.checks || []).find(x => !x.ok)?.what || '').slice(0, 120) });
  return { ok: !!(compiled && t?.ok), status: run.status };
}

/** Snapshot of what the finished round proved, so later art-only builds can carry it honestly. */
export function markArtBase(p, project) {
  const run = p.workflow;
  if (!run) return;
  const rev = project.revision();
  const play = run.evidence.findLast(e => e.kind === 'play' && e.ok && e.sourceRevision === rev);
  run.artBase = { codeHash: codeHashOf(project), accepted: ['completed', 'ready'].includes(run.status), played: play ? new Date(play.at).toLocaleTimeString('zh-CN', { hour12: false }) : '' };
}

function artDirectorOf(p) {
  if (p.artDirector?.running) return p.artDirector;
  const project = gpOf(p);
  p.artDirector = new ArtDirector({
    slots: () => mergeSlots(p.game.design?.art, artSlotsIn(gpSnapshot(project) || {})),
    shot: () => latestShot(p),
    design: () => ({ ...(p.game.design || {}), ...(p.artRequest ? { art_request: p.artRequest } : {}) }),
    meta: () => p.game.meta,
    existing: () => p.game.assets || {},
    generateKey: async (spec, signal) => {
      const asset = { id: spec.id, kind: 'keyart', name: spec.name, prompt: String(spec.prompt).slice(0, 400), async: true, state: 'pending', url: '' };
      p.game.assets[spec.id] = asset;
      p.emit({ type: 'asset', id: asset.id, kind: asset.kind, name: asset.name, state: 'pending', stage: 'queued', async: true });
      const r = await factory.generate(spec, p.game.meta, () => {}, { signal });
      await applyGeneratedAsset(p, asset, r, { signal });
      return asset;
    },
    enqueue: (a, signal) => {
      const cur = p.game.assets[a.id];
      if (cur && cur.state !== 'failed') return '已存在';
      p.game.assets[a.id] = { id: a.id, kind: a.kind, name: String(a.name || '').slice(0, 20), prompt: String(a.prompt).slice(0, 900), refs: a.refs, styled: true, async: true, state: 'pending', url: '' };
      p.emit({ type: 'ops', ops: [{ op: 'asset', id: a.id, kind: a.kind, state: 'pending', url: '' }] });
      enqueueAssets(p, [a.id], { signal });
      return '';
    },
    emit: ev => p.emit(ev),
  });
  return p.artDirector;
}
/** Finished art replaces the pencil look only once the player asked for it; games that already carry
 * a style key frame asked before this rule existed. */
export const finalArtOf = p => p.finalArt ?? Object.values(p.game?.assets || {}).some(a => a.kind === 'keyart');

export function startArt(p) {
  if (!isGp(p.game) || !p.game.design || !finalArtOf(p) || process.env.UGC_ART === '0') return null;
  const d = artDirectorOf(p);
  d.start();
  return d;
}

/** Text files of the project (without generated assets), kept with each version for restore. */
const gpSnapshot = project => project.exists ? project.sources(f => !f.startsWith('assets/')) : null;
function gpRestore(project, files) {
  for (const f of project.list()) if (f.text && !f.path.startsWith('assets/') && !(f.path in files) && f.path !== 'project.godot') project.remove(f.path);
  for (const [f, s] of Object.entries(files)) project.write(f, s);
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
  if (p.game.meta.engine === 'code' || isGp(p.game)) return true;
  const isNew = Object.keys(p.game.entities).length === 0;
  if (isNew && GP_ON) return true;
  return isNew && wantsCodeEngine((p.game.meta.genre_hint || '') + ' ' + text, opts.dimension || p.game.meta.dimension);
}

/** Progress shown while the model is still streaming a tool call's JSON. */
function codeProgress(name, json) {
  const step = (json.match(/"step"\s*:\s*"((?:[^"\\]|\\.)*)"/) || [])[1];
  const file = (json.match(/"(?:file|path)"\s*:\s*"([^"]*)"/) || [])[1];
  const ci = Math.max(json.indexOf('"code"'), json.indexOf('"content"'));
  const lines = ci >= 0 ? json.slice(ci).split('\\n').length : 0;
  const title = (json.match(/"title"\s*:\s*"((?:[^"\\]|\\.)*)"/) || [])[1];
  const sections = name === 'design_game' ? ['closest_game', 'core_loop', 'rules', 'layout', 'modules', 'milestones', 'build_steps', 'palette'].filter(k => json.includes('"' + k + '"')).length : 0;
  return { step, file, lines, title, sections };
}

const thinkLine = s => s.replace(/\s+/g, ' ').trim();

/** Earlier code-engine turns, one line each, so a follow-up knows what was asked and delivered. */
function codeRecap(p) {
  return (p.codeLog || []).slice(-6).map(t => '- 用户：「' + t.user.slice(0, 80) + '」→ ' + (t.summary || '（没有完成）').slice(0, 220) + (t.files?.length ? '（改了 ' + t.files.join('、') + '）' : '')).join('\n');
}

/** Test/eval screenshots go to disk; the stream and the saved timeline only carry a URL. */
function shotToDisk(p, ev) {
  if (!ev.shot || ev.shot.startsWith('/covers/')) return ev;
  const f = p.id + '_t' + now() + '_' + (ev.seq || Math.random().toString(36).slice(2, 6)) + '.jpg';
  try { fs.writeFileSync(path.join(DATA, 'covers', f), Buffer.from(ev.shot, 'base64')); return { ...ev, shot: '/covers/' + f }; } catch { return { ...ev, shot: '' }; }
}

export async function runCodeChat(p, text, opts = {}, deps = {}) {
  if (p.running || p.mutating) throw new Error('busy');
  const model = Object.hasOwn(opts, 'model') ? selectProjectModel(p, opts.model) : resolveModelSelection(p.model, { defaultModel: CODE_MODEL });
  const acceptedAt = now();
  p.watch?.stop();
  p.watch ||= new PlaytestWatch(p.id, { emit: ev => p.emit(ev) });
  p.assetAbort?.abort(new Error('开始新一轮制作，旧素材任务已停止'));
  p.running = true;
  const g = p.game;
  const isFirst = !g.design;
  const gp = isGp(g) || (isFirst && GP_ON && g.meta.engine !== 'code');
  if (isFirst) g.meta = { ...g.meta, engine: gp ? 'godot' : 'code', dimension: gp && (opts.dimension === '3d' || g.meta.dimension === '3d') ? '3d' : '2d' };
  g.code ||= { files: {} };
  const project = gp ? gpOf(p) : null;
  try { if (project) await project.withLock(() => project.create({ title: g.meta.title, orientation: g.meta.orientation })); }
  catch (e) { p.running = false; p.save(); throw e; }
  const previousWorkflow = p.workflow;
  const iterationOptions = requestedIterationOptions(opts.iteration, isFirst, acceptedAt);
  if (project) {
    const resuming = previousWorkflow && ['partial', 'failed', 'interrupted', 'cancelled', 'running', 'ready'].includes(previousWorkflow.status);
    p.workflow = createWorkflow({ goal: resuming && /^(继续|接着|下一步|continue)/i.test(text.trim()) && previousWorkflow?.goal ? previousWorkflow.goal : text, sourceRevision: project.revision(), previous: previousWorkflow });
    p.workflow.iteration = createIteration(iterationOptions);
  }
  p.chat.push({ role: 'user', text, t: now() });
  p.emit({ type: 'user', text });
  const intent = gp ? assetIntent(text) : { finalArt: false, kinds: [] };
  if (intent.finalArt) { p.finalArt = true; p.artRequest = text.slice(0, 300); }
  const ac = new AbortController();
  const assetRound = new AbortController();
  p.abort = ac;
  p.save();
  try { startSketch(p, { text, isFirst, signal: ac.signal }, deps); } catch (error) { console.error('sketch start', error); }
  if (project) {
    p.emit({ type: 'workflow', workflow: p.workflow });
    // Keep the last playable build visible. An empty-template export is not a first Demo.
    // The builder explicitly publishes a meaningful preview_checkpoint or accepted test build.
  }
  const startT = now();
  const filesBefore = JSON.stringify(g.code.files);
  let toolCount = 0;
  const texts = {};
  const flushText = agent => {
    for (const a of agent ? [agent] : Object.keys(texts)) {
      const s = texts[a];
      if (s && s.trim()) { p.chat.push({ role: 'assistant', agent: a, text: s, t: now() }); p.emit({ type: 'assistant', agent: a, text: s }); }
      texts[a] = '';
    }
  };
  const queued = new Set(Object.keys(g.assets || {}));
  const GP_KINDS = ['background', 'sprite', 'texture', 'model3d', 'music', 'sfx'];
  /** Returns '' when queued (or already queued), else why not. */
  const queueAsset = (a, control = {}) => {
    const id = String(a?.id || '').slice(0, 30).replace(/[^\w-]/g, '_') || 'art';
    if (!a?.prompt) return '素材缺少 prompt';
    if (queued.has(id)) return '';
    if (queued.size >= (gp ? 12 : 6)) return '素材数量已达上限';
    queued.add(id);
    const kind = gp ? (GP_KINDS.includes(a.kind) ? a.kind : 'sprite') : a.kind === 'sprite' ? 'sprite' : 'background';
    g.assets[id] = { id, kind, name: String(a.name || '').slice(0, 20), prompt: String(a.prompt).slice(0, 400), state: 'pending', url: '' };
    p.emit({ type: 'ops', ops: [{ op: 'asset', id, kind: g.assets[id].kind, state: 'pending', url: '' }] });
    p.emit({ type: 'crew', agent: 'A', state: 'thinking', text: '先去画素材：' + g.assets[id].name });
    const assetSignal = AbortSignal.any([ac.signal, assetRound.signal, ...(control.signal ? [control.signal] : [])]);
    enqueueAssets(p, [id], { signal: assetSignal, deadlineAt: control.deadlineAt || (gp ? p.workflow?.iteration?.wrapAt : undefined) });
    return '';
  };
  // art can start while the design is still streaming in
  const onDesignPartial = part => {
    if (Array.isArray(part.palette) && part.palette.length >= 3 && !g.meta.palette?.length) g.meta = { ...g.meta, palette: part.palette.filter(h => /^#?[0-9a-f]{6}$/i.test(String(h))) };
    if (typeof part.art_bible === 'string' && 'assets' in part) g.meta = { ...g.meta, art_bible: part.art_bible };
    // Full-project rounds enqueue only the finalized, budgeted design selection.
    if (!gp && g.meta.art_bible) for (const a of readyAssets(part)) queueAsset(a);
  };
  let participationResume = previousWorkflow && previousWorkflow.status !== 'completed' ? previousWorkflow.id : null;
  const hooks = {
    takeParticipation: () => { const context = deliverParticipation(p, now(), { resumeRunId: participationResume }); participationResume = null; return context; },
    watchStart: info => p.watch.start(info),
    watchFrame: (id, frame) => { if (p.running && !ac.signal.aborted) p.watch.frame(id, frame); },
    watchEnd: (id, result) => p.watch.end(id, result),
    emit: ev => {
      if (ev.type === 'test' || ev.type === 'eval') ev = shotToDisk(p, ev);
      if (ev.type === 'code_write') p.emit({ ...ev, code: undefined, preview: ev.code.slice(0, 9000) });
      else p.emit(ev);
    },
    pushCode: (files, label, agent) => { p.emit({ type: 'ops', ops: [{ op: 'code', files, label: label || '', agent: agent || 'B' }] }); p.save(); },
    pushPck: (b, label, agent) => pushPck(p, b, label, agent),
    requestAsset: (a, control) => queueAsset(a, control),
    assets: () => g.assets,
    workflow: run => { p.workflow = run; updateWorkflow(p); },
    onDesign: design => {
      g.meta = { ...g.meta, title: design.title, pitch: design.pitch, dimension: gp ? design.dimension || '2d' : '2d', engine: gp ? 'godot' : 'code', genre: design.genre, style: 'flat', filter: 'smooth',
        palette: design.palette, art_bible: design.art_bible, goal_text: design.goal_text, controls: design.controls, orientation: design.orientation };
      p.emit({ type: 'design', design, agent: 'A' });
      p.emit({ type: 'crew', agent: 'A', state: 'done', text: '方案定好了' });
      p.emit({ type: 'ops', ops: [{ op: 'set_meta', meta: g.meta, label: '开工：' + design.title, agent: 'A' }] });
      if (!gp) for (const a of design.assets) queueAsset(a);
      p.save();
    },
    aiPlay: () => p.emit({ type: 'ops', ops: [{ op: 'ai_play' }] }),
    mirrorEval: code => p.emit({ type: 'ops', ops: [{ op: 'eval', code }] }),
  };
  /** Streaming callbacks: everything is tagged with the crew member the agent is acting as right now. */
  const fileTools = gp ? GP_FILE_TOOLS : FILE_TOOLS;
  const roleFor = gp ? gpRoleOf : roleOf;
  const makeCb = session => {
    const last = {}, toolNames = {}, pending = {};
    const start = (id, name, role) => {
      delete pending[id];
      session.role = role;
      p.emit({ type: 'tool_start', id, name, agent: role });
      if (name === 'run_game' || name === 'game_eval' || name === 'run_test') p.emit({ type: 'crew', agent: role, state: 'testing', text: '试玩检查' });
    };
    return {
      onModel: info => {
        const record = { requestedModel: String(info.requestedModel || '').slice(0, 128), responseModel: String(info.responseModel || '').slice(0, 128) };
        if (p.workflow) p.workflow.model = record;
        p.emit({ type: 'model_response', runId: p.workflow?.id, ...record });
        p.save();
      },
      onText: d => { if (!d) return; const a = session.role; texts[a] = (texts[a] || '') + d; p.emit({ type: 'text', agent: a, delta: d }); },
      // Public feedback comes from observable tools, tasks and screenshots, not private reasoning.
      onThinking: () => {},
      onToolStart: (id, name) => {
        flushText();
        toolNames[id] = name; toolCount++;
        // file tools show under B or C, which is only known once the "file" field has streamed in
        if (fileTools.has(name)) pending[id] = true;
        else start(id, name, roleFor(name, {}, g.design));
      },
      onToolDelta: (id, json) => {
        const name = toolNames[id];
        if (pending[id]) {
          const file = (json.match(/"(?:file|path)"\s*:\s*"([^"]*)"/) || [])[1];
          if (!file) return;
          start(id, name, roleFor(name, { file, path: file }, g.design));
        }
        const t = now();
        if (t - (last[id] || 0) < (name === 'design_game' ? 250 : 160)) return;
        last[id] = t;
        const ev = { type: 'tool_progress', id, name, agent: session.role, ...codeProgress(name, json) };
        if (/^(write|patch)_(module|file)$/.test(name)) Object.assign(ev, codeTail(json) || {});
        if (name === 'design_game') { const part = parsePartialJson(json); if (part) { ev.partial = part; onDesignPartial(part); } }
        p.emit(ev);
      },
    };
  };
  let finish = null, turnOutput = null, turnError = null;
  p.emit({ type: 'turn_start', model, engine: gp ? 'godot' : 'code', crew: CREW, first: isFirst });
  if (isFirst) {
    p.emit({ type: 'phase', phase: 'design', text: '策划师正在构思玩法、规则和开发路线…', agents: ['A'] });
    p.emit({ type: 'crew', agent: 'A', state: 'thinking', text: '理解你的想法…' });
  } else {
    p.emit({ type: 'crew', agent: 'B', state: 'thinking', text: '看看要改哪里…' });
  }
  const artEnabled = gp && finalArtOf(p) && (deps.art ?? !(deps.runProjectBuilder || deps.runBuilder));
  if (artEnabled) { try { startArt(p); } catch (error) { console.error('art start', error); } }
  const live = deps.live || new LiveGame();
  let changedGp = [];
  // Tests inject the builder and must not call the gateway. Production always enhances first.
  const enhance = deps.enhancePrompt ?? ((deps.runProjectBuilder || deps.runBuilder) ? null : enhanceUserPrompt);
  let builderText = text;
  if (enhance && shouldEnhance(text, model)) {
    p.emit({ type: 'crew', agent: 'A', state: 'thinking', text: '先把你的想法整理成可执行的做法…' });
    try {
      const brief = await enhance({ text, isFirst, design: g.design, signal: ac.signal, model: ENHANCE_MODEL });
      if (brief) builderText = text + '\n\n' + brief;
    } catch (error) { console.error('prompt enhance', error); }
  }
  try {
    const args = { game: g, userText: builderText, isFirst, hooks, makeCb, signal: ac.signal, model, iterationOptions, recap: [codeRecap(p), resumeContext(previousWorkflow), gp ? '' : deliverParticipation(p)].filter(Boolean).join('\n\n'), live, workflow: p.workflow, artifactDir: project ? path.join(project.buildDir, 'tasks') : undefined, assetKinds: intent.kinds, finalArt: finalArtOf(p) };
    const { session, out } = gp
      ? await (deps.runProjectBuilder || runProjectBuilder)({ ...args, project, browserPlaytest: browserPlaytestOf(p), onSession: s => { p._gpSession = s; } })
      : await (deps.runBuilder || runBuilder)(args);
    turnOutput = out;
    if (gp) changedGp = [...session.changed];
    finish = session.finish;
    if (!gp && finish?.milestone_done && g.design) {
      const i = g.design.milestones.findIndex(m => m.id === finish.milestone_done);
      if (i >= g.design.current) g.design.current = i + 1;
      p.emit({ type: 'roadmap', milestones: g.design.milestones, current: g.design.current });
    }
  } catch (e) {
    turnError = e;
    if (ac.signal.aborted) p.emit({ type: 'error', message: '已停止' });
    else { console.error(e); p.emit({ type: 'error', message: String(e.message || e).slice(0, 300) }); }
  } finally {
    if (gp) assetRound.abort(new Error('本轮已结束，未完成素材留待下一轮重试'));
    p.watch?.stop();
    p.browserPlaytest?.stop();
    await live.stop();
    if (gp && p._gpSession) changedGp = [...p._gpSession.changed];
    p._gpSession = null;
    flushText();
    if (finish?.summary) p.chat.push({ role: 'assistant', text: finish.summary, suggestions: finish.suggestions || [], t: now() });
    const before = JSON.parse(filesBefore);
    const changed = gp ? changedGp : Object.keys({ ...before, ...g.code.files }).filter(f => before[f] !== g.code.files[f]);
    (p.codeLog ||= []).push({ t: now(), user: text, summary: finish?.summary || '', files: changed });
    if (p.codeLog.length > 30) p.codeLog.shift();
    p.running = false;
    p.abort = null;
    if (gp && p.workflow) {
      if (turnOutput?.budgetExpired && !ac.signal.aborted) {
        p.workflow.status = 'partial';
        p.workflow.completionRequested = false;
        p.workflow.issues = [...new Set([...(p.workflow.issues || []), '本轮已到时间上限，已保存成果；请试玩已有版本或选择下一步修复'])];
      } else if (ac.signal.aborted || turnOutput?.interrupted || turnError || !finish) {
        p.workflow.status = ac.signal.aborted ? 'cancelled' : turnOutput?.interrupted ? 'interrupted' : turnError ? 'failed' : 'partial';
        p.workflow.completionRequested = false;
        p.workflow.issues = [ac.signal.aborted ? '用户停止了本轮，已保存已合入内容' : turnOutput?.interrupted ? '执行中断，可继续未完成任务' : turnError ? String(turnError.message || turnError).slice(0, 500) : '本轮没有经过 finish 验收，不能标记完成'];
      }
      if (p.workflow.iteration) {
        p.workflow.iteration.endedAt ||= now();
        if (finish?.suggestions?.length) p.workflow.iteration.nextSteps = finish.suggestions;
        if (!['completed', 'ready'].includes(p.workflow.status)) p.workflow.iteration.phase = 'paused';
      }
      updateWorkflow(p);
      if (project?.exists) markArtBase(p, project);
      if (p.artPending?.size) scheduleArtFlush(p, 500);
      if (artEnabled && !ac.signal.aborted) { try { startArt(p); } catch (error) { console.error('art start', error); } }
    }
    const version = snapshotVersion(p, text, project);
    p.emit({ type: 'turn_end', status: gp ? p.workflow?.status || 'partial' : finish ? 'completed' : 'partial', workflow: p.workflow, summary: finish?.summary || '', suggestions: finish?.suggestions || [], version, ms: now() - startT, tools: toolCount, engine: gp ? 'godot' : 'code', pck: gp && g.meta.pck_version ? pckUrl(p) : undefined, build: p.build });
    p.save();
  }
}

export async function runChat(p, text, opts = {}, deps = {}) {
  if (p.running || p.mutating) throw new Error('busy');
  if (isCodeTurn(p, text, opts)) return runCodeChat(p, text, opts, deps);
  const model = Object.hasOwn(opts, 'model') ? selectProjectModel(p, opts.model) : resolveModelSelection(p.model, { defaultModel: MODEL });
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
  p.emit({ type: 'turn_start', model });
  try {
    await (deps.runAgent || runAgent)({
      messages: p.messages,
      signal: ac.signal,
      req: { model },
      cb: {
        onModel: info => { p.emit({ type: 'model_response', requestedModel: String(info.requestedModel || model).slice(0, 128), responseModel: String(info.responseModel || '').slice(0, 128) }); p.save(); },
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
    const version = snapshotVersion(p, text);
    p.running = false;
    p.abort = null;
    p.emit({ type: 'turn_end', status: ac.signal.aborted ? 'cancelled' : finInput ? 'completed' : 'partial', summary: finInput?.summary || '', suggestions: finInput?.suggestions || [], version, ms: now() - startT, tools: toolCount });
    p.save();
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

// cloudflared and other reverse proxies hold a text/event-stream until the first chunk clears
// their buffer (often 4 KB). A 2 KB pad stays inside that buffer, so remote viewers never see
// the strokes that arrive instantly on localhost. 8 KB forces the first frame out; each later
// write disables Nagle. Callers still need a snapshot poll, because a tunnel can stall again.
const SSE_PAD = '.'.repeat(8192);
function writeSse(res, chunk) {
  try {
    res.socket?.setNoDelay?.(true);
    res.write(chunk);
    if (typeof res.flush === 'function') res.flush();
    return true;
  } catch { return false; }
}
function openSse(req, res) {
  res.writeHead(200, {
    'content-type': 'text/event-stream; charset=utf-8', 'cache-control': 'no-store, no-transform',
    'content-encoding': 'identity', 'connection': 'keep-alive', 'x-accel-buffering': 'no',
    'access-control-allow-origin': '*',
  });
  if (res.flushHeaders) res.flushHeaders();
  req.socket?.setNoDelay?.(true);
  writeSse(res, 'retry: 2000\nevent: ping\ndata: ' + JSON.stringify({ pad: SSE_PAD }) + '\n\n');
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
export function projectView(p) {
  return { id: p.id, game: p.game, chat: p.chat, running: p.running, workflow: p.workflow, sourceManifest: sourceManifestOf(p), build: p.build, participation: p.participation || [], participationDelivery: isGp(p.game) ? 'live' : 'next_round', sceneDirty: !!p.sceneEdit?.dirty, sceneSourceRevision: p.sceneEdit?.sourceRevision || '', seq: p.seq, versions: p.versions.map(v => ({ v: v.v, t: v.t, prompt: v.prompt })), published: p.published, updated: p.updated, created: p.created, model: projectModel(p), pck: isGp(p.game) && p.game.meta.pck_version ? pckUrl(p) : null };
}

export function browserPlaytestOf(p) { return p.browserPlaytest ||= new BrowserPlaytest(p.id, { emit: ev => p.emit(ev) }); }

export async function editScene(p, body = {}) {
  if (!isGp(p.game) || !p.game.construction) return { status: 400, body: { error: '当前作品暂无可编辑关卡' } };
  if (p.running || p.mutating) return { status: 409, body: { error: '制作或保存正在进行，可以先观察场景，完成后再移动实体', snapshot: p.game.construction } };
  const requestKey = JSON.stringify([body.id, body.position, body.baseRevision]);
  const previousRequest = p._sceneRequests?.get(body.requestId);
  if (previousRequest) return previousRequest.key === requestKey ? { status: 200, body: previousRequest.result } : { status: 409, body: { error: '同一编辑请求不能重复用于不同操作', snapshot: p.game.construction } };
  p.mutating = true;
  const project = gpOf(p);
  try {
    return await project.withLock(() => {
      if (p.running) return { status: 409, body: { error: '新的制作已开始，请等待本轮保存', snapshot: p.game.construction } };
      const next = moveConstruction(p.game.construction, body);
      const before = { snapshot: p.game.construction, sceneEdit: p.sceneEdit, workflow: structuredClone(p.workflow), files: [...CONSTRUCTION_FILES].map(file => [file, project.read(file)]), state: project.state };
      try {
        commitConstruction(project, next);
        p.game.construction = next;
        const sourceRevision = project.revision();
        p.sceneEdit = { dirty: true, sourceRevision, revision: next.revision, updatedAt: now() };
        invalidateWorkflow(p.workflow, '关卡位置已编辑，试玩将使用新位置；完整玩法需重新验收');
        p.save();
      } catch (error) {
        p.game.construction = before.snapshot; p.sceneEdit = before.sceneEdit; p.workflow = before.workflow;
        for (const [file, value] of before.files) { if (value == null) project.remove(file); else project.write(file, value); }
        project.state = before.state;
        throw error;
      }
      const result = { ok: true, snapshot: next, sourceRevision: p.sceneEdit.sourceRevision, dirty: true, sceneDirty: true, sceneSourceRevision: p.sceneEdit.sourceRevision };
      p._sceneRequests ||= new Map(); p._sceneRequests.set(body.requestId, { key: requestKey, result });
      while (p._sceneRequests.size > 30) p._sceneRequests.delete(p._sceneRequests.keys().next().value);
      p.emit({ type: 'construction', origin: 'user', requestId: body.requestId, runId: next.runId, snapshot: next, sourceRevision: result.sourceRevision });
      p.emit({ type: 'scene_edit', sceneDirty: true, sceneSourceRevision: result.sourceRevision, requestId: body.requestId });
      if (p.workflow) updateWorkflow(p);
      return { status: 200, body: result };
    });
  } catch (error) { return { status: error.status || 400, body: { error: String(error.message || error), snapshot: p.game.construction, sourceRevision: project.revision() } }; }
  finally { p.mutating = false; }
}

export async function buildEditedScene(p) {
  if (!isGp(p.game) || !p.game.construction) return { status: 400, body: { error: '当前作品暂无可编辑关卡' } };
  if (p.running || p.mutating) return { status: 409, body: { error: '制作或保存正在进行，请稍后再试玩' } };
  p.mutating = true;
  try {
    return await gpOf(p).withLock(async () => {
      const project = gpOf(p), check = await project.check();
      if (p.workflow) recordEvidence(p.workflow, { kind: 'compile', ok: check.ok === true, sourceRevision: check.sourceRevision, errors: check.errors || [] });
      if (!check.ok) { p.save(); return { status: 422, body: { error: '编辑后的场景暂时无法运行', errors: check.errors, sceneDirty: true } }; }
      const build = await project.build({ sourceRevision: check.sourceRevision });
      if (!build.ok || !pushPck(p, build, '已应用你的场景调整', 'user')) return { status: 422, body: { error: build.error || '新场景包未能保存', sceneDirty: true } };
      p.sceneEdit = { ...(p.sceneEdit || {}), dirty: false, sourceRevision: build.sourceRevision, revision: p.game.construction.revision, updatedAt: now() }; p.save();
      p.emit({ type: 'scene_edit', sceneDirty: false, sceneSourceRevision: build.sourceRevision });
      return { status: 200, body: { ok: true, build: p.build, pck: pckUrl(p), sourceRevision: build.sourceRevision, sceneDirty: false, sceneSourceRevision: build.sourceRevision } };
    });
  } catch (error) { return { status: 500, body: { error: String(error.message || error), sceneDirty: !!p.sceneEdit?.dirty } }; }
  finally { p.mutating = false; }
}
const SPOTLIGHT = [
  title => /纸剑幸存者|PaperBlade/.test(title) && !/改编/.test(title),
  title => /StickBonk|火柴人大乱斗/.test(title) && !/改编/.test(title),
  title => /星刃/.test(title) && !/改编/.test(title),
  title => /跳一跳/.test(title),
  title => /僵尸危机3/.test(title) && /平台协作/.test(title),
  title => /消消乐/.test(title) && !/改编/.test(title),
  title => /羊了个羊/.test(title),
  title => title === '小丑牌',
];
function spotlightRank(title) {
  const text = String(title || '');
  const index = SPOTLIGHT.findIndex(match => match(text));
  return index < 0 ? SPOTLIGHT.length : index;
}
const hotScore = g => (g.plays || 0) + (g.likes || 0) * 3;
function orderFeed(list, sort) {
  const byFreshness = (x, y) => (y.t || 0) - (x.t || 0);
  const byHeat = (x, y) => hotScore(y) - hotScore(x) || byFreshness(x, y);
  if (sort === 'new') return [...list].sort(byFreshness);
  const picked = new Set(), head = [];
  for (let rank = 0; rank < SPOTLIGHT.length; rank++) {
    const hits = list.filter(g => spotlightRank(g.title) === rank).sort(byHeat);
    if (!hits.length) continue;
    head.push(hits[0]);
    picked.add(hits[0].id);
  }
  const rest = list.filter(g => !picked.has(g.id));
  rest.sort((x, y) => (x.featured === y.featured ? 0 : x.featured ? -1 : 1) || byHeat(x, y));
  return [...head, ...rest];
}
function playableProject(p) { return isGp(p.game) && !!(p.build?.buildId || p.game.meta.pck_version); }
function spotlightDraft(p) {
  const rank = spotlightRank(p?.game?.meta?.title);
  if (!p || p.published || rank >= SPOTLIGHT.length || !playableProject(p)) return null;
  const published = [...projects.values()].some(item => item.published && spotlightRank(item.published.game?.meta?.title) === rank);
  return published ? null : p;
}
function previewFeedItem(p) {
  const g = p.game;
  return { id: p.id, title: g.meta.title, pitch: g.meta.pitch || '', dimension: g.meta.dimension, orientation: g.meta.orientation || 'landscape', engine: g.meta.engine || '', genre: g.meta.genre, style: g.meta.style, cover: p.draftCover || '', author: '造梦玩家', plays: 0, likes: 0, t: p.updated || 0, prompt: p.prompt, remixOf: p.remixOf || null, featured: false };
}

function feedItem(p) {
  const g = p.published.game;
  return { id: p.id, title: g.meta.title, pitch: g.meta.pitch || '', dimension: g.meta.dimension, orientation: g.meta.orientation || 'landscape', engine: g.meta.engine || '', genre: g.meta.genre, style: g.meta.style, cover: p.published.cover, author: p.published.author || '造梦玩家', plays: p.published.plays || 0, likes: p.published.likes || 0, t: p.published.t, prompt: p.prompt, remixOf: p.remixOf || null, featured: !!p.published.featured };
}

export async function checkProject(p) {
  if (!isGp(p.game)) return checkGame(p.game);
  const project = gpOf(p);
  if (!project.exists) return { ok: false, issues: ['还没有可检查的 Godot 工程'] };
  return project.withLock(async () => {
    const report = await project.check();
    if (p.workflow) { recordEvidence(p.workflow, { kind: 'compile', sourceRevision: report.sourceRevision, ok: report.ok === true, errors: report.errors || [] }); updateWorkflow(p); }
    return { ...report, issues: (report.errors || []).filter(e => e.kind !== 'warning').map(e => e.message), acceptance: acceptanceFor(p.workflow, project.revision(), { requirePreview: true }) };
  });
}

export async function applyPreviewReceipt(p, body) {
  if (!isGp(p.game) || !p.workflow) return { status: 409, body: { error: '没有等待验收的完整工程任务' } };
  if (body?.kind !== 'runtime_ready' || typeof body.loaded !== 'boolean' || !Array.isArray(body.errors) || body.errors.length > 30) return { status: 400, body: { error: '无效运行时回执' } };
  return gpOf(p).withLock(() => {
    const project = gpOf(p), actual = project.getBuild(body.buildId), revision = project.revision();
    const expected = acceptanceFor(p.workflow, revision).build;
    if (!actual || actual.sourceRevision !== body.sourceRevision || revision !== actual.sourceRevision || expected?.buildId !== actual.buildId || p.build?.buildId !== actual.buildId) return { status: 409, body: { error: '回执属于旧版或未知预览包', build: p.build, workflow: p.workflow } };
    const errors = body.errors.map(e => typeof e === 'string' ? e.slice(0, 800) : { kind: String(e?.kind || 'error').slice(0, 30), message: String(e?.message || e?.text || '运行错误').slice(0, 800) });
    const ok = body.loaded && !errors.some(e => typeof e === 'string' || e.kind !== 'warning');
    const item = recordEvidence(p.workflow, { kind: 'preview', ok, sourceRevision: revision, buildId: actual.buildId, contentHash: actual.contentHash, errors, summary: '浏览器运行时启动回执；玩法验收独立记录' });
    p.emit({ type: 'runtime_applied', ok, buildId: actual.buildId, sourceRevision: revision, evidenceId: item.id, errors });
    updateWorkflow(p, revision);
    return { status: 200, body: { ok, workflow: p.workflow, build: p.build } };
  });
}

function pendingAssetIssues(p) {
  const assets = Object.values(p.game.assets || {});
  const inUse = isGp(p.game) ? assetsInUse(assets, gpSnapshot(gpOf(p))) : assets;
  return inUse.filter(a => a.state !== 'ready' && a.state !== 'failed').map(a => '素材尚未就绪：' + (a.name || a.id));
}

export async function publishProject(p, body = {}) {
  if (p.running) return { status: 409, body: { error: '搭建期间不能发布' } };
  const commit = () => {
    if (p.running || p.mutating) return { status: 409, body: { error: '工程正在修改，暂不能发布' } };
    let acceptedBuild = null;
    if (isGp(p.game)) {
      const project = gpOf(p), revision = project.revision();
      const gate = acceptanceFor(p.workflow, revision, { requirePreview: true });
      const issues = [...gate.issues, ...pendingAssetIssues(p)];
      if (!p.workflow?.completionRequested) issues.push('当前任务尚未请求完成验收');
      acceptedBuild = gate.build && project.getBuild(gate.build.buildId);
      if (!acceptedBuild || acceptedBuild.sourceRevision !== revision || acceptedBuild.buildId !== p.build?.buildId) issues.push('已验收的预览包不存在或与当前版本不一致');
      if (issues.length) return { status: 409, body: { error: '当前版本尚未满足发布条件', issues, workflow: p.workflow } };
      updateWorkflow(p, revision);
    }
    let cover = p.published?.cover || p.draftCover || '';
    if (typeof body.cover === 'string' && body.cover) { const f = p.id + '_' + now() + '.jpg'; fs.writeFileSync(path.join(DATA, 'covers', f), Buffer.from(body.cover, 'base64')); cover = '/covers/' + f; }
    if (body.title) p.game.meta.title = String(body.title).slice(0, 40);
    if (body.pitch) p.game.meta.pitch = String(body.pitch).slice(0, 120);
    if (body.prompt) p.prompt = String(body.prompt).slice(0, 300);
    p.published = { ...(p.published || {}), game: structuredClone(p.game), assets: p.assetStates(), cover, t: now(), pck: !!acceptedBuild,
      build: buildView(acceptedBuild), author: body.author || p.published?.author || '我', plays: p.published?.plays || 0, likes: p.published?.likes || 0 };
    p.save();
    return { status: 200, body: { ok: true, id: p.id, url: '/play.html?id=' + p.id } };
  };
  return isGp(p.game) ? gpOf(p).withLock(commit) : commit();
}

export async function requestHandler(req, res) {
  const url = new URL(req.url, 'http://x');
  const parts = url.pathname.split('/').filter(Boolean);
  try {
    if (parts[0] === 'api') {
      const [, a, id, b] = parts;
      if (a === 'models' && !id && req.method === 'GET') return send(res, 200, { models: MODEL_OPTIONS, defaultModel: CODE_MODEL });
      if (a === 'feed' && req.method === 'GET') {
        const sort = url.searchParams.get('sort') || 'hot';
        const list = [...projects.values()].filter(p => p.published).map(feedItem);
        if (sort !== 'new') {
          for (let rank = 0; rank < SPOTLIGHT.length; rank++) {
            if (list.some(g => spotlightRank(g.title) === rank)) continue;
            const drafts = [...projects.values()].filter(p => spotlightDraft(p) && spotlightRank(p.game.meta.title) === rank).sort((a, b) => (b.updated || 0) - (a.updated || 0));
            if (drafts[0]) list.push(previewFeedItem(drafts[0]));
          }
        }
        return send(res, 200, orderFeed(list, sort));
      }
      if (a === 'me' && req.method === 'GET') {
        const mine = [...projects.values()].filter(p => p.owner === 'me').sort((x, y) => y.updated - x.updated).map(p => ({ id: p.id, title: p.game.meta.title, dimension: p.game.meta.dimension, orientation: p.game.meta.orientation || 'landscape', entities: Object.keys(p.game.entities).length, published: !!p.published, cover: p.published?.cover || p.draftCover || '', updated: p.updated, plays: p.published?.plays || 0, likes: p.published?.likes || 0 }));
        return send(res, 200, mine);
      }
      if (a === 'games' && id && req.method === 'GET' && !b) {
        const p = projects.get(id);
        if (!p) return send(res, 404, { error: 'not found' });
        if (!p.published) {
          const draft = spotlightDraft(p);
          if (!draft) return send(res, 404, { error: 'not found' });
          return send(res, 200, { ...previewFeedItem(draft), spec: draft.game, assets: draft.assetStates(), build: buildView(draft.build), pck: pckUrl(draft) });
        }
        return send(res, 200, { ...feedItem(p), spec: p.published.game, assets: p.published.assets, build: p.published.build || null, pck: p.published.pck ? '/api/games/' + p.id + '/game.pck?' + (p.published.build ? 'build=' + p.published.build.buildId : 't=' + p.published.t) : null });
      }
      if (a === 'games' && id && b === 'game.pck' && req.method === 'GET') {
        const p = projects.get(id);
        if (!p?.published?.pck) return send(res, 404, { error: 'not found' });
        if (p.published.build) {
          const requested = url.searchParams.get('build') || p.published.build.buildId;
          if (requested !== p.published.build.buildId) return send(res, 404, { error: 'not published' });
          const built = gpOf(p).getBuild(requested);
          if (!built) return send(res, 404, { error: 'build not found' });
          return serveFile(req, res, built.path, 'public, max-age=31536000, immutable');
        }
        return serveFile(req, res, path.join(gpOf(p).dir, 'published.pck'), 'public, max-age=300');
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
        const requestedModel = Object.hasOwn(body, 'model') ? validateSelectedModel(body.model) : undefined;
        let p;
        if (body.remix) {
          const src = projects.get(body.remix);
          if (!src?.published) return send(res, 404, { error: 'source not found' });
          p = new Project({ game: JSON.parse(JSON.stringify(src.published.game)), model: requestedModel ?? src.model, remixOf: src.id, prompt: 'Remix: ' + src.published.game.meta.title });
          p.game.meta.title = src.published.game.meta.title + '（改编）';
          p.chat.push({ role: 'assistant', text: '已复制「' + src.published.game.meta.title + '」，告诉我你想怎么改编吧！比如换个主角、加个 Boss、改成夜晚……', t: now() });
          p.messages.push({ role: 'user', content: '（用户 Remix 了一个已发布的游戏，后续会提出修改要求）' }, { role: 'assistant', content: '好的，我会在现有游戏基础上修改。' });
          if (isGp(p.game)) {
            const from = gpOf(src), to = gpOf(p);
            if (from.exists) {
              await from.withLock(() => to.withLock(() => {
                fs.cpSync(from.dir, to.dir, { recursive: true, filter: f => !/[\\/](\.godot|build)([\\/]|$)|published\.pck$/.test(f.slice(from.dir.length)) });
                to.state = { version: 0, changed: [], deleted: [], needsExport: true, needsImport: true };
              }));
              delete p.game.meta.pck_version;
              delete p.game.meta.build_id;
              delete p.game.meta.source_revision;
              to.build().then(b => { if (b.ok) pushPck(p, b, '', 'C'); }).catch(e => console.error('remix build', e));
            }
          }
          snapshotVersion(p, 'Remix', isGp(p.game) ? gpOf(p) : null);
        } else {
          p = new Project({ prompt: body.prompt || '', model: requestedModel });
          // New projects use their actual target immediately; avoid loading a legacy engine
          // only to replace it with the Godot workshop when the first request begins.
          if (GP_ON) p.game.meta.engine = 'godot';
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
        if (b === 'model' && req.method === 'POST') {
          const body = await readBody(req, 4000);
          return send(res, 200, { ok: true, model: selectProjectModel(p, body.model) });
        }
        if (b === 'participation' && req.method === 'POST') { const result = enqueueParticipation(p, await readBody(req, 16000)); return send(res, result.status, result.body); }
        if (b === 'scene-edit' && req.method === 'POST') { const result = await editScene(p, await readBody(req, 16000)); return send(res, result.status, result.body); }
        if (b === 'scene-build' && req.method === 'POST') { const result = await buildEditedScene(p); return send(res, result.status, result.body); }
        if (b === 'runtime-client' && req.method === 'POST') {
          const result = browserPlaytestOf(p).heartbeat(await readBody(req, 16000));
          return send(res, result?.ok === false ? 400 : 200, result || { ok: true });
        }
        if (b === 'runtime-command' && req.method === 'GET') return send(res, 200, browserPlaytestOf(p).next(url.searchParams.get('clientId')));
        if (b === 'runtime-result' && req.method === 'POST') {
          const result = browserPlaytestOf(p).receive(await readBody(req, 2000000));
          return send(res, result?.ok === false ? 409 : 200, result || { ok: true });
        }
        if (b === 'watch' && req.method === 'GET') {
          if (parts[4] !== 'frame') return send(res, 200, p.watch?.snapshot() || null);
          const frame = p.watch?.image(url.searchParams.get('session'), url.searchParams.get('seq'));
          if (!frame) return send(res, 410, { error: '这帧已过期，请读取最新画面' });
          res.writeHead(200, { 'Content-Type': 'image/jpeg', 'Content-Length': frame.length, 'Cache-Control': 'no-store' });
          return res.end(frame);
        }
        if (b === 'game.pck' && req.method === 'GET') {
          const buildId = url.searchParams.get('build');
          if (buildId) {
            const built = gpOf(p).getBuild(buildId);
            return built ? serveFile(req, res, built.path, 'public, max-age=31536000, immutable') : send(res, 404, { error: 'build not found' });
          }
          // Legacy links remain usable only for their exact current legacy version.
          if (p.build) return send(res, 409, { error: '请使用不可变预览包地址', pck: pckUrl(p) });
          if (url.searchParams.get('v') && Number(url.searchParams.get('v')) !== p.game.meta.pck_version) return send(res, 404, { error: 'version not found' });
          return serveFile(req, res, gpOf(p).pckPath, 'no-cache');
        }
        if (b === 'events' && req.method === 'GET') {
          const cursor = req.headers['last-event-id'] ?? url.searchParams.get('since') ?? 0;
          const replay = eventReplay(p, cursor);
          if (url.searchParams.get('stream') !== '1') return send(res, 200, replay);
          // named ping: some proxies drop comment-only frames; EventSource.onmessage ignores 'ping'
          openSse(req, res);
          if (replay.reset) writeSse(res, 'id: ' + p.seq + '\ndata: ' + JSON.stringify({ type: 'reset', seq: p.seq, workflow: p.workflow }) + '\n\n');
          else for (const event of replay.events) writeSse(res, 'id: ' + event.seq + '\ndata: ' + JSON.stringify(event) + '\n\n');
          p.clients.add(res);
          const ka = setInterval(() => { if (!writeSse(res, 'event: ping\ndata: ' + Date.now() + '\n\n')) clearInterval(ka); }, 10000);
          req.on('close', () => { clearInterval(ka); p.clients.delete(res); });
          return;
        }
        if (b === 'sketch' && req.method === 'GET') {
          const board = sketchBoardOf(p);
          if (url.searchParams.get('stream') !== '1') return send(res, 200, { ...board.snapshot(), n: board.n });
          openSse(req, res);
          const detach = board.attach(res);
          const ka = setInterval(() => { if (!writeSse(res, 'event: ping\ndata: ' + Date.now() + '\n\n')) clearInterval(ka); }, 10000);
          req.on('close', () => { clearInterval(ka); detach(); });
          return;
        }
        if (b === 'chat' && req.method === 'POST') {
          const body = await readBody(req);
          if (p.running || p.mutating) return send(res, 409, { error: 'AI 正在搭建中' });
          if (Object.hasOwn(body, 'model')) selectProjectModel(p, body.model);
          if (!p.prompt) p.prompt = body.text;
          runChat(p, resumeText(p, String(body.text || '').slice(0, 2000)), body).catch(e => console.error(e));
          return send(res, 200, { ok: true });
        }
        if (b === 'resume' && req.method === 'POST') {
          const body = await readBody(req);
          if (p.running || p.mutating) return send(res, 409, { error: 'AI 正在搭建中' });
          if (!p.interrupted && !['partial', 'failed', 'interrupted', 'cancelled', 'ready'].includes(p.workflow?.status)) return send(res, 400, { error: '没有待继续的任务' });
          if (Object.hasOwn(body, 'model')) selectProjectModel(p, body.model);
          runChat(p, resumeText(p, '继续'), body).catch(e => console.error(e));
          return send(res, 200, { ok: true });
        }
        if (b === 'stop' && req.method === 'POST') { p.abort?.abort(); p.browserPlaytest?.stop(); p.assetAbort?.abort(new Error('用户停止了素材重试')); p.artDirector?.stop('用户停止了美术任务'); return send(res, 200, { ok: true }); }
        if (b === 'preview_receipt' && req.method === 'POST') {
          const result = await applyPreviewReceipt(p, await readBody(req, 64000));
          return send(res, result.status, result.body);
        }
        if (b === 'move' && req.method === 'POST') {
          const body = await readBody(req);
          if (body.id === '__player') p.game.player.position = body.position;
          else if (p.game.entities[body.id]) p.game.entities[body.id].position = body.position;
          p.save();
          return send(res, 200, { ok: true });
        }
        if (b === 'retry_assets' && req.method === 'POST') {
          if (p.running || p.mutating) return send(res, 409, { error: '本轮制作正在进行，素材重试请留到本轮结束后' });
          const ids = Object.values(p.game.assets).filter(a => a.state === 'failed' || a.fallback).map(a => a.id);
          p.assetAbort ||= new AbortController();
          if (p.assetAbort.signal.aborted) p.assetAbort = new AbortController();
          for (const id of ids) { const a = p.game.assets[id] = { ...p.game.assets[id], state: 'pending', error: '' }; if (a.fallback) { a.kind = 'model3d'; delete a.fallback; } p.emit({ type: 'asset', id, kind: a.kind, name: a.name, state: 'pending' }); }
          enqueueAssets(p, ids, { signal: p.assetAbort.signal, deadlineAt: now() + 600000 });
          p.save();
          return send(res, 200, { retried: ids });
        }
        if (b === 'check' && req.method === 'GET') return send(res, 200, await checkProject(p));
        if (b === 'restore' && req.method === 'POST') {
          if (p.running || p.mutating) return send(res, 409, { error: '搭建期间不能回退版本' });
          const body = await readBody(req);
          const v = p.versions.find(x => x.v === body.v);
          if (!v) return send(res, 404, { error: 'no version' });
          if (p.running || p.mutating) return send(res, 409, { error: '工程正在修改' });
          p.mutating = true;
          try {
            const restore = async () => {
              p.game = structuredClone(v.game);
              invalidateWorkflow(p.workflow, '已回退源码，需要重新验收当前版本');
              if (p.workflow) p.workflow.evidence = [];
              p.build = null;
              delete p.game.meta.build_id;
              delete p.game.meta.source_revision;
              if (isGp(p.game) && v.gp) {
                const project = gpOf(p);
                gpRestore(project, v.gp);
                const built = await project.build();
                if (built.ok) pushPck(p, built, '回到第 ' + v.v + ' 版', 'B');
              }
              if (p.workflow) updateWorkflow(p);
            };
            if (isGp(v.game)) await gpOf(p).withLock(restore); else await restore();
          } finally { p.mutating = false; }
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
          const result = await publishProject(p, await readBody(req));
          return send(res, result.status, result.body);
        }
        if (b === 'delete' && req.method === 'POST') {
          if (p.running || p.mutating) return send(res, 409, { error: '搭建期间不能删除项目' });
          p.mutating = true;
          await gpOf(p).withLock(() => { projects.delete(p.id); fs.rmSync(p.file(), { force: true }); fs.rmSync(gpOf(p).dir, { recursive: true, force: true }); godotProjects.delete(p.id); });
          return send(res, 200, { ok: true });
        }
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
    if (e.statusCode === 400 || e.statusCode === 409) return send(res, e.statusCode, { error: String(e.message || e) });
    console.error(e);
    send(res, 500, { error: String(e.message || e) });
  }
}
export const server = http.createServer(requestHandler);
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) server.listen(PORT, HOST, () => console.log('造梦 UGC demo on http://' + HOST + ':' + PORT));
