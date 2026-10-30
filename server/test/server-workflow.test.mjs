import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { Readable, Writable } from 'node:stream';
import { EventEmitter } from 'node:events';
import { emptyGame } from '../engine.mjs';
import { createWorkflow, recordEvidence } from '../workflow.mjs';

// Import the application without listening or generating; all storage is isolated.
const data = fs.mkdtempSync(path.join(os.tmpdir(), 'ugc-server-workflow-'));
process.env.UGC_DATA_DIR = data;
fs.mkdirSync(path.join(data, 'projects'));
const interrupted = createWorkflow({ goal: 'resume actual unfinished work' });
interrupted.tasks = [{ id: 'done', status: 'applied', title: 'done' }, { id: 'active', status: 'running', title: 'active' }];
fs.writeFileSync(path.join(data, 'projects', 'restoreme.json'), JSON.stringify({ id: 'restoreme', game: emptyGame(), running: true, chat: [{ role: 'assistant', text: 'working' }], workflow: interrupted, seq: 8, log: [{ type: 'user', seq: 8, text: 'hello' }], versions: [{ v: 42 }] }));
const api = await import('../server.mjs');
after(() => { assert.equal(api.server.listening, false); fs.rmSync(data, { recursive: true, force: true }); });

class Response extends Writable {
  constructor() { super(); this.parts = []; this.headers = {}; this.statusCode = 0; this.done = new Promise(resolve => this.on('finish', resolve)); }
  _write(chunk, _encoding, cb) { this.parts.push(Buffer.from(chunk)); cb(); }
  writeHead(status, headers) { this.statusCode = status; this.headers = headers; }
  flushHeaders() {}
  text() { return Buffer.concat(this.parts).toString(); }
  json() { return JSON.parse(this.text()); }
}
async function request(url, { method = 'GET', body, headers = {} } = {}) {
  const req = Readable.from(body === undefined ? [] : [Buffer.from(JSON.stringify(body))]);
  Object.assign(req, { url, method, headers });
  const res = new Response();
  await api.requestHandler(req, res); await res.done;
  return res;
}
function project() {
  const p = new api.Project({}); p.game.meta.engine = 'godot';
  api.projects.set(p.id, p);
  const gp = api.gpOf(p);
  fs.mkdirSync(gp.dir, { recursive: true });
  assert.deepEqual(gp.write('project.godot', 'config_version=5\n'), []);
  assert.deepEqual(gp.write('main.gd', 'extends Node\n'), []);
  p.workflow = createWorkflow({ goal: 'test goal', sourceRevision: gp.revision() });
  return { p, gp };
}

test('participation HTTP works during production without a project write lock and survives reload', async () => {
  const { p } = project(); p.running = true;
  p.game.design = { modules: [{ file: 'score.gd' }] };
  const body = { text: '计分再清楚一点', moduleFile: 'score.gd', requestId: 'http-feedback-01' };
  const response = await request('/api/projects/' + p.id + '/participation', { method: 'POST', body });
  assert.equal(response.statusCode, 200);
  assert.equal(response.json().participation[0].status, 'queued');
  assert.equal(p.running, true);
  assert.equal(api.projectView(p).participationDelivery, 'live');
  const restored = new api.Project(JSON.parse(fs.readFileSync(p.file(), 'utf8')));
  assert.equal(restored.participation[0].text, body.text);
  const duplicate = await request('/api/projects/' + p.id + '/participation', { method: 'POST', body });
  assert.equal(duplicate.json().participation.length, 1);
});
function buildFixture(p, gp, { version = 1, native = true } = {}) {
  const bytes = Buffer.from('immutable test artifact ' + crypto.randomUUID());
  const b = { ok: true, buildId: crypto.randomBytes(16).toString('hex'), sourceRevision: gp.revision(), contentHash: crypto.createHash('sha256').update(bytes).digest('hex'), version, bytes: bytes.length };
  fs.mkdirSync(path.join(gp.buildDir, 'builds'), { recursive: true });
  fs.writeFileSync(path.join(gp.buildDir, 'builds', b.buildId + '.pck'), bytes);
  fs.writeFileSync(path.join(gp.buildDir, 'builds', b.buildId + '.json'), JSON.stringify(b));
  if (native) {
    recordEvidence(p.workflow, { kind: 'compile', sourceRevision: b.sourceRevision, ok: true });
    recordEvidence(p.workflow, { kind: 'test', sourceRevision: b.sourceRevision, ok: true, checks: [{ ok: true, what: 'fixture assertion' }] });
  }
  assert.equal(api.pushPck(p, b), true);
  return { b, bytes };
}
const receipt = b => ({ kind: 'runtime_ready', buildId: b.buildId, sourceRevision: b.sourceRevision, loaded: true, errors: [] });

test('server import does not listen; startup resumes durable task state without rerunning', () => {
  assert.equal(api.server.listening, false);
  const p = api.projects.get('restoreme');
  assert.equal(p.running, false); assert.equal(p.workflow.status, 'interrupted');
  assert.equal(p.workflow.tasks[0].status, 'applied'); assert.equal(p.workflow.tasks[1].status, 'interrupted');
  assert.equal(p.interrupted, 'resume actual unfinished work'); assert.equal(p.seq, 8); assert.equal(p.nextVersion, 43);
  assert.equal(JSON.parse(fs.readFileSync(p.file(), 'utf8')).workflow.status, 'interrupted');
});

test('new projects open the configured Godot workshop before the first model request', async () => {
  const response = await request('/api/projects', { method: 'POST', body: { dimension: '2d' } });
  assert.equal(response.statusCode, 200);
  assert.equal(response.json().game.meta.engine, 'godot');
  assert.equal(response.json().running, false);
  assert.equal(response.json().participationDelivery, 'live');
});

test('atomic storage whitelist excludes live sessions, functions and cyclic objects', () => {
  const p = new api.Project({}); p._gpSession = { p }; p._toolNames = { x: 'transient' }; p.unexpected = 'not persisted'; p.abort = new AbortController();
  p.emit({ type: 'user', text: 'checkpoint' }); p.save();
  const disk = JSON.parse(fs.readFileSync(p.file(), 'utf8'));
  assert.equal(disk.seq, 1); assert.equal(disk.log.length, 1);
  for (const k of ['_gpSession', '_toolNames', 'unexpected', 'abort', 'clients']) assert.equal(k in disk, false);
  assert.equal(fs.readdirSync(path.dirname(p.file())).some(f => f.startsWith(p.id) && f.endsWith('.tmp')), false);
  assert.equal(new api.Project({ id: p.id, versions: [{ v: 80 }], nextVersion: 2 }).nextVersion, 81);
});

test('project instances are cached and isolated beneath UGC_DATA_DIR', () => {
  const { p, gp } = project();
  assert.equal(api.gpOf(p), gp); assert.ok(gp.dir.startsWith(path.join(data, 'gprojects')));
});

test('native source manifest lists actual files and changes with the source revision', () => {
  const { p, gp } = project();
  p.game.design = { modules: [{ file: 'future.gd' }] };
  const before = api.projectView(p).sourceManifest;
  assert.equal(before.sourceRevision, gp.revision());
  assert.deepEqual(before.files.sort(), ['main.gd', 'project.godot']);
  gp.write('score.gd', 'extends RefCounted\nconst PRIVATE_CONTENT = 42\n');
  const after = api.projectView(p).sourceManifest;
  assert.notEqual(after.sourceRevision, before.sourceRevision);
  assert.equal(after.sourceRevision, gp.revision());
  assert.equal(after.files.includes('score.gd'), true);
  assert.equal(after.files.includes('future.gd'), false);
  assert.equal(JSON.stringify(after).includes('PRIVATE_CONTENT'), false);
  gp.remove('score.gd');
  assert.deepEqual(api.projectView(p).sourceManifest, before);
  const uncreated = new api.Project({}); uncreated.game.meta.engine = 'godot';
  assert.equal(api.projectView(uncreated).sourceManifest, null);
  uncreated.game.meta.engine = 'code';
  assert.equal(api.projectView(uncreated).sourceManifest, null);
});

test('workflow checkpoints and turn end deliver the current native source manifest', async () => {
  const { p, gp } = project();
  await api.runCodeChat(p, 'module checkpoint', {}, { live: { stop() {} }, runProjectBuilder: async args => {
    gp.write('score.gd', 'extends RefCounted\n');
    args.hooks.workflow(args.workflow);
    const checkpoint = p.log.filter(event => event.type === 'workflow').at(-1);
    assert.equal(checkpoint.workflow.sourceManifest.sourceRevision, gp.revision());
    assert.ok(checkpoint.workflow.sourceManifest.files.includes('score.gd'));
    gp.write('shop.gd', 'extends RefCounted\n');
    return { session: { changed: new Set(['score.gd', 'shop.gd']), finish: null }, out: { done: true } };
  } });
  const last = p.log.at(-1);
  assert.equal(last.type, 'turn_end');
  assert.equal(last.workflow.sourceManifest.sourceRevision, gp.revision());
  assert.ok(last.workflow.sourceManifest.files.includes('shop.gd'));
  assert.deepEqual(last.workflow.sourceManifest, api.projectView(p).sourceManifest);
});

test('asset state views preserve fallback status for completion and publication checks', () => {
  const p = new api.Project({});
  p.game.assets = { a: { kind: 'sprite', state: 'ready', fallback: 'billboard', url: '/assets/a.png', name: 'a' }, b: { kind: 'sprite', state: 'ready' } };
  assert.equal(p.assetStates().a.fallback, 'billboard');
  assert.equal(p.assetStates().b.fallback, false);
});

test('event payloads are immutable snapshots and replay detects cursor gaps', () => {
  const p = new api.Project({}); const state = { status: 'running' };
  p.emit({ type: 'workflow', workflow: state }); state.status = 'completed';
  p.emit({ type: 'user', text: '2' }); p.emit({ type: 'user', text: '3' });
  assert.equal(p.log[0].workflow.status, 'running');
  assert.deepEqual(api.eventReplay(p, 1).events.map(e => e.seq), [2, 3]);
  p.log.shift(); assert.equal(api.eventReplay(p, 0).reset, true); assert.equal(api.eventReplay(p, 1).reset, false);
  assert.equal(api.eventReplay(p, 100).reset, true);
});

test('SSE explicitly streams, replays Last-Event-ID, and sends ordinary reset data', async () => {
  const { p } = project(); p.emit({ type: 'user', text: 'first' }); p.emit({ type: 'user', text: 'second' });
  const polled = await request('/api/projects/' + p.id + '/events?since=1');
  assert.match(polled.headers['content-type'], /application\/json/); assert.deepEqual(polled.json().events.map(e => e.seq), [2]);
  const req = new EventEmitter(); Object.assign(req, { url: '/api/projects/' + p.id + '/events?stream=1&since=0', method: 'GET', headers: { 'last-event-id': '1' } });
  const res = new Response(); await api.requestHandler(req, res); req.emit('close');
  assert.match(res.text(), /id: 2\ndata:/); assert.doesNotMatch(res.text(), /"text":"first"/); assert.equal(p.clients.size, 0);
  p.log = p.log.slice(1); req.headers = {}; const reset = new Response();
  await api.requestHandler(req, reset); req.emit('close');
  assert.match(reset.text(), /data: \{"type":"reset","seq":2/);
});

test('immutable PCK URLs serve their exact historical bytes and refuse unknown IDs', async () => {
  const { p, gp } = project(); const first = buildFixture(p, gp); const second = buildFixture(p, gp, { version: 2 });
  const a = await request('/api/projects/' + p.id + '/game.pck?build=' + first.b.buildId);
  assert.deepEqual(Buffer.concat(a.parts), first.bytes); assert.match(a.headers['cache-control'], /immutable/);
  const b = await request('/api/projects/' + p.id + '/game.pck?build=' + second.b.buildId);
  assert.deepEqual(Buffer.concat(b.parts), second.bytes);
  assert.equal((await request('/api/projects/' + p.id + '/game.pck?build=unknown')).statusCode, 404);
  assert.equal((await request('/api/projects/' + p.id + '/game.pck?v=1')).statusCode, 409);
  assert.match(api.projectView(p).pck, new RegExp(second.b.buildId));
});

test('late older build with the same source revision cannot replace current preview or evidence', () => {
  const { p, gp } = project(), first = buildFixture(p, gp), second = buildFixture(p, gp, { version: 2 });
  const seq = p.seq, evidence = structuredClone(p.workflow.evidence);
  assert.equal(first.b.sourceRevision, second.b.sourceRevision);
  assert.equal(api.pushPck(p, first.b), false);
  assert.equal(p.build.buildId, second.b.buildId); assert.equal(p.game.meta.pck_version, 2);
  assert.equal(p.seq, seq); assert.deepEqual(p.workflow.evidence, evidence);
});

test('ready only becomes completed after exact browser build receipt; milestone advances once', async () => {
  const { p, gp } = project(); p.game.design = { current: 0, milestones: [{ id: 'M1' }, { id: 'M2' }] };
  p.workflow.tasks.push({ id: 'a', title: 'a', status: 'applied', verified: false });
  const { b } = buildFixture(p, gp); p.workflow.completionRequested = true; p.workflow.pendingMilestone = 'M1';
  assert.equal((await api.publishProject(p)).status, 409);
  const r = await api.applyPreviewReceipt(p, receipt(b));
  assert.equal(r.status, 200); assert.equal(p.workflow.status, 'completed'); assert.equal(p.workflow.tasks[0].status, 'verified');
  assert.equal(p.game.design.current, 1);
  await api.applyPreviewReceipt(p, receipt(b)); assert.equal(p.game.design.current, 1);
  const published = await api.publishProject(p, { title: 'ready' });
  assert.equal(published.status, 200); assert.equal(p.published.build.buildId, b.buildId);
});

test('old/unknown/mismatched browser receipts cannot verify the current build', async () => {
  const { p, gp } = project(), first = buildFixture(p, gp), second = buildFixture(p, gp, { version: 2 });
  p.workflow.completionRequested = true;
  assert.equal((await api.applyPreviewReceipt(p, receipt(first.b))).status, 409);
  assert.equal((await api.applyPreviewReceipt(p, { ...receipt(second.b), sourceRevision: 'a'.repeat(64) })).status, 409);
  assert.equal((await api.applyPreviewReceipt(p, { ...receipt(second.b), kind: 'loaded' })).status, 400);
  gp.write('main.gd', 'extends Node2D\n');
  assert.equal((await api.applyPreviewReceipt(p, receipt(second.b))).status, 409);
  assert.equal(p.workflow.evidence.some(e => e.kind === 'preview'), false);
});

test('browser runtime errors invalidate prior startup success and block publication', async () => {
  const { p, gp } = project(), { b } = buildFixture(p, gp); p.workflow.completionRequested = true;
  await api.applyPreviewReceipt(p, receipt(b));
  const failed = await api.applyPreviewReceipt(p, { ...receipt(b), errors: [{ kind: 'error', message: 'runtime failure' }] });
  assert.equal(failed.body.ok, false); assert.equal(p.workflow.status, 'ready');
  assert.equal((await api.publishProject(p)).status, 409);
});

test('native evidence, task status, assets and current source all gate publication', async () => {
  const { p, gp } = project(), { b } = buildFixture(p, gp, { native: false }); p.workflow.completionRequested = true;
  await api.applyPreviewReceipt(p, receipt(b));
  assert.equal((await api.publishProject(p)).status, 409);
  recordEvidence(p.workflow, { kind: 'compile', ok: true, sourceRevision: b.sourceRevision });
  recordEvidence(p.workflow, { kind: 'test', ok: true, sourceRevision: b.sourceRevision, checks: [] });
  assert.equal((await api.publishProject(p)).status, 409);
  recordEvidence(p.workflow, { kind: 'test', ok: true, sourceRevision: b.sourceRevision, checks: [{ ok: true, what: 'assertion' }] });
  p.workflow.tasks.push({ id: 'bad', title: 'unresolved', status: 'failed' });
  assert.equal((await api.publishProject(p)).status, 409); p.workflow.tasks[0].status = 'applied';
  p.game.assets.x = { id: 'x', state: 'pending' }; assert.equal((await api.publishProject(p)).status, 409);
  delete p.game.assets.x; assert.equal((await api.publishProject(p)).status, 200);
  gp.write('main.gd', 'extends Node2D\n'); assert.equal((await api.publishProject(p)).status, 409);
});

test('check endpoint actually calls native check and returns failures', async () => {
  const { p, gp } = project(); let calls = 0;
  gp.check = async () => { calls++; return { loaded: false, ok: false, sourceRevision: gp.revision(), errors: [{ kind: 'error', message: 'parse failed', file: 'main.gd', line: 3 }] }; };
  const response = await request('/api/projects/' + p.id + '/check');
  assert.equal(calls, 1); assert.equal(response.json().ok, false); assert.deepEqual(response.json().issues, ['parse failed']);
  assert.equal(p.workflow.evidence.at(-1).kind, 'compile'); assert.equal(p.workflow.evidence.at(-1).ok, false);
});

test('busy guards stop restore/delete/publish without mutating existing state', async () => {
  const { p, gp } = project(); p.running = true;
  for (const route of ['restore', 'delete', 'publish']) {
    const response = await request('/api/projects/' + p.id + '/' + route, { method: 'POST', body: { v: 1 } }); assert.equal(response.statusCode, 409, route);
  }
  assert.equal(api.projects.get(p.id), p); assert.equal(gp.read('main.gd'), 'extends Node\n');
});

test('restore invalidates old acceptance and keeps monotonically increasing version counter', async () => {
  const { p, gp } = project(); buildFixture(p, gp); p.workflow.completionRequested = true;
  p.versions = [{ v: 50, prompt: 'old', game: structuredClone(p.game), gp: { 'project.godot': 'config_version=5\n', 'main.gd': 'extends Control\n' } }]; p.nextVersion = 51;
  gp.build = async () => ({ ok: false, error: 'no real export in test' });
  const response = await request('/api/projects/' + p.id + '/restore', { method: 'POST', body: { v: 50 } });
  assert.equal(response.statusCode, 200); assert.equal(gp.read('main.gd'), 'extends Control\n');
  assert.equal(p.workflow.completionRequested, false); assert.deepEqual(p.workflow.evidence, []); assert.equal(p.build, null); assert.equal(p.nextVersion, 51);
});

test('turn lifecycle persists partial or interrupted truth and never advances a claimed milestone', async () => {
  for (const interrupted of [false, true]) {
    const { p, gp } = project(); p.game.design = { current: 0, milestones: [{ id: 'M1' }] };
    gp.build = async () => ({ ok: false, error: 'no export in orchestration test' });
    await api.runCodeChat(p, 'continue work', {}, { live: { stop() {} }, runProjectBuilder: async args => {
      const session = { changed: new Set(['main.gd']), finish: null };
      args.onSession(session);
      assert.equal(args.workflow, p.workflow); args.hooks.workflow(args.workflow);
      assert.equal(JSON.parse(fs.readFileSync(p.file(), 'utf8')).running, true);
      return { session, out: interrupted ? { interrupted: true } : { done: true } };
    } });
    assert.equal(p.running, false); assert.equal(p.game.design.current, 0);
    const last = p.log.at(-1); assert.equal(last.type, 'turn_end'); assert.equal(last.status, interrupted ? 'interrupted' : 'partial');
    const disk = JSON.parse(fs.readFileSync(p.file(), 'utf8')); assert.equal(disk.seq, last.seq); assert.equal(disk.workflow.status, last.status);
    assert.equal('_gpSession' in disk, false);
  }
});

test('cancelled turn retains successfully applied task and finishes with cancelled status', async () => {
  const { p, gp } = project(); gp.build = async () => ({ ok: false });
  await api.runCodeChat(p, 'work', {}, { live: { stop() {} }, runProjectBuilder: async args => {
    args.workflow.tasks.push({ id: 'done', title: 'done', status: 'applied', verified: false });
    args.hooks.workflow(args.workflow); p.abort.abort();
    return { session: { changed: new Set(), finish: null }, out: { stopped: true } };
  } });
  assert.equal(p.workflow.status, 'cancelled'); assert.equal(p.workflow.tasks[0].status, 'applied');
  assert.equal(p.log.at(-1).status, 'cancelled');
});

test('history retention never reuses version numbers after thirty turns', async () => {
  const { p, gp } = project(); gp.build = async () => ({ ok: false });
  const deps = { live: { stop() {} }, runProjectBuilder: async args => {
    args.workflow.status = 'partial'; args.hooks.workflow(args.workflow);
    return { session: { changed: new Set(), finish: { status: 'partial', summary: 'saved', suggestions: [] } }, out: { done: true } };
  } };
  for (let i = 0; i < 33; i++) await api.runCodeChat(p, 'iteration ' + i, {}, deps);
  assert.equal(p.versions.length, 30); assert.equal(p.versions[0].v, 4); assert.equal(p.versions.at(-1).v, 33); assert.equal(p.nextVersion, 34);
  assert.equal(p.log.at(-1).version, 33);
});

test('round target is initialized before execution and bounded client options reach builder', async () => {
  const { p, gp } = project(); gp.build = async () => { throw new Error('empty prewarm must not run'); };
  await api.runCodeChat(p, '只优化移动手感', { iteration: { tier: 'quality', hardMs: Infinity } }, { live: { stop() {} }, runProjectBuilder: async args => {
    assert.equal(args.workflow.iteration.tier, 'quality');
    assert.equal(args.workflow.iteration.targetMs, 1500000);
    assert.equal(args.workflow.iteration.hardMs, 1800000);
    assert.equal(args.iterationOptions.targetMs, 1500000);
    assert.equal(JSON.parse(fs.readFileSync(p.file(), 'utf8')).workflow.iteration.tier, 'quality');
    return { session: { changed: new Set(), finish: null }, out: { done: true } };
  } });
  assert.equal(p.running, false); assert.equal(p.workflow.status, 'partial');
  assert.equal(p.workflow.iteration.phase, 'paused'); assert.ok(p.workflow.iteration.endedAt);
});

test('budget expiry is saved as partial with next steps, never as user stop or completion', async () => {
  const { p } = project();
  await api.runCodeChat(p, '首轮 Demo', {}, { live: { stop() {} }, runProjectBuilder: async args => {
    args.workflow.iteration.reason = 'deadline';
    args.workflow.tasks.push({ id: 'scene', title: '场景', status: 'applied' });
    return { session: { changed: new Set(), finish: { status: 'partial', summary: '已保留场景', suggestions: ['修复移动碰撞'] } }, out: { interrupted: true, budgetExpired: true } };
  } });
  assert.equal(p.workflow.status, 'partial'); assert.equal(p.workflow.completionRequested, false);
  assert.deepEqual(p.workflow.iteration.nextSteps, ['修复移动碰撞']);
  assert.equal(p.workflow.tasks[0].status, 'applied');
  assert.match(p.workflow.activity.at(-1).title, /时限/);
  assert.equal(p.workflow.issues.some(issue => issue.includes('用户停止')), false);
});

test('real progress is durable and attached to the exact sequenced event for reconnect', () => {
  const { p } = project();
  p.emit({ type: 'code_write', file: 'main.gd', step: '完成移动', code: 'not in activity' });
  const row = p.log.at(-1), disk = JSON.parse(fs.readFileSync(p.file(), 'utf8'));
  assert.equal(row.activity.id, `${p.workflow.id}:${row.seq}`);
  assert.equal(disk.workflow.activity.at(-1).file, 'main.gd');
  assert.equal(api.eventReplay(p, row.seq - 1).events[0].activity.id, row.activity.id);
  assert.equal(new api.Project(disk).workflow.activity.at(-1).id, row.activity.id);
});

test('downloaded assets waiting for import cannot appear ready or survive a cancelled import', async () => {
  const { p } = project(), ac = new AbortController();
  const asset = p.game.assets.sprite = { id: 'sprite', kind: 'sprite', state: 'pending', name: '主角' };
  let release;
  const pending = api.applyGeneratedAsset(p, asset, { url: '/assets/test.png' }, { signal: ac.signal, apply: async () => new Promise(resolve => { release = resolve; }) });
  assert.equal(asset.state, 'importing');
  assert.equal(p.log.some(e => e.type === 'asset' && e.state === 'ready'), false);
  ac.abort(new Error('round timebox ended')); release();
  await assert.rejects(pending, /round timebox ended/);
  assert.equal(asset.state, 'failed');
  assert.equal(p.log.some(e => e.type === 'asset' && e.state === 'ready'), false);
  assert.equal(JSON.parse(fs.readFileSync(p.file(), 'utf8')).game.assets.sprite.state, 'failed');
});

test('asset ready is emitted only after actual project import resolves', async () => {
  const { p } = project(); let imported = false;
  const asset = p.game.assets.sprite = { id: 'sprite', kind: 'sprite', state: 'pending' };
  await api.applyGeneratedAsset(p, asset, { url: '/assets/test.png' }, { apply: async () => { assert.equal(asset.state, 'importing'); imported = true; } });
  assert.equal(imported, true); assert.equal(asset.state, 'ready');
  assert.equal(p.log.at(-1).state, 'ready');
});

test('asset retry cannot escape an active creation round and stop cancels owned retries', async () => {
  const { p } = project(); p.running = true;
  p.game.assets.sprite = { id: 'sprite', kind: 'sprite', state: 'failed' };
  const denied = await request('/api/projects/' + p.id + '/retry_assets', { method: 'POST', body: {} });
  assert.equal(denied.statusCode, 409); assert.equal(p.game.assets.sprite.state, 'failed');
  p.running = false; p.assetAbort = new AbortController();
  await request('/api/projects/' + p.id + '/stop', { method: 'POST', body: {} });
  assert.equal(p.assetAbort.signal.aborted, true);
});
