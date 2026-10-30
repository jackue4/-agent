import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createIteration, delegationBudget, updateIteration } from '../iteration.mjs';
import { createWorkflow, acceptanceFor, recordEvidence, recoverWorkflow, settleWorkflow } from '../workflow.mjs';
import { ProjectSession, runProjectBuilder } from '../gpagent.mjs';
import { runTaskBatch } from '../task-team.mjs';
import { emptyGame } from '../engine.mjs';

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const rev = 'a'.repeat(64);
function fixture({ iteration = true, signal, live, ...opts } = {}) {
  const files = { 'main.gd': 'extends Node\n' }, calls = { check: 0, build: 0, test: 0, pushes: 0 };
  let revision = rev, serial = Promise.resolve();
  const project = {
    revision: () => revision, read: p => files[p] ?? null, sources: () => ({ ...files }), list: () => Object.keys(files).map(path => ({ path, size: files[path].length })),
    write: (p, text) => { files[p] = text; revision = String(Object.values(files).join('').length).padStart(64, '0'); return []; },
    remove: p => { delete files[p]; return true; },
    withLock(fn) { const next = serial.then(fn, fn); serial = next.catch(() => {}); return next; },
    async check() { calls.check++; return { ok: true, loaded: true, sourceRevision: revision, errors: [] }; },
    async build() { calls.build++; const b = { ok: true, sourceRevision: revision, buildId: String(calls.build).padStart(32, '0'), version: calls.build }; project.latestBuild = b; return b; },
    async selfTest() { calls.test++; return { ok: true, loaded: true, has_test: true, sourceRevision: revision, errors: [], checks: [{ ok: true, what: 'input causes score change and restart restores state' }] }; },
  };
  const workflow = createWorkflow({ goal: 'One small playable loop', sourceRevision: revision });
  if (iteration) workflow.iteration = createIteration();
  const hooks = { emit() {}, workflow() {}, assets: () => ({}), pushPck() { calls.pushes++; }, signal };
  const game = emptyGame();
  const session = new ProjectSession(game, project, hooks, { workflow, live, ...opts });
  return { files, calls, project, workflow, hooks, game, session };
}
const task = (id, extra = {}) => ({ id, title: id, role: 'gameplay', files: [id + '.gd'], depends_on: [], prompt: 'Implement one small file', acceptance: ['works'], ...extra });
function nativeEvidence(f) {
  for (const kind of ['compile', 'test', 'build']) recordEvidence(f.workflow, { kind, ok: true, sourceRevision: f.project.revision(), buildId: '1'.repeat(32), checks: [{ ok: true, what: 'real assertion' }] });
}

test('demo and quality tiers have durable budgets with their own hard caps', () => {
  const d = createIteration({ startedAt: 1000 });
  assert.equal(d.tier, 'demo');
  assert.deepEqual([d.targetMs, d.wrapAt - 1000, d.hardMs], [300000, 225000, 405000]);
  const q = createIteration({ tier: 'quality', startedAt: 0 });
  assert.deepEqual([q.tier, q.targetMs, q.wrapAt, q.hardMs, q.deadlineAt], ['quality', 1500000, 1260000, 1800000, 1800000]);
  assert.equal(createIteration({ targetMs: 900000, hardMs: 900000 }).hardMs, 600000);
  assert.equal(createIteration({ tier: 'quality', targetMs: 1e9, hardMs: 1e9 }).hardMs, 1800000);
  assert.equal(createIteration({ tier: 'unknown' }).tier, 'demo');
  assert.equal(delegationBudget(d, 1000), 110000);
  assert.equal(delegationBudget(d, d.wrapAt), 0);
});

test('quality tier raises asset, test and turn budgets; demo keeps the fast limits', async () => {
  const f = fixture(); f.workflow.iteration = createIteration({ tier: 'quality' }); let requested = 0;
  f.hooks.requestAsset = () => { requested++; return ''; };
  const assets = Array.from({ length: 12 }, (_, i) => ({ id: 'a' + i, kind: 'sprite', name: 'a' + i, prompt: 'p' }));
  const result = await f.session.exec('design_game', { title: 'Big', assets });
  assert.equal(requested, 10); assert.match(result.notes.join(''), /前 10 个/);
  f.project.check = async () => ({ ok: false, loaded: false, sourceRevision: rev, errors: [{ kind: 'error', message: 'broken' }] });
  for (let i = 0; i < 6; i++) assert.equal((await f.session.exec('run_test', { look: false })).error?.includes('次数') ?? false, false);
  assert.match((await f.session.exec('run_test', { look: false })).error, /次数/);
  for (const tier of ['demo', 'quality']) {
    const g = fixture({ iteration: false }); let seen;
    await runProjectBuilder({ ...g, isFirst: true, userText: 'small', iterationOptions: { tier }, agentRunner: async options => { seen = options; return { done: true }; } });
    const design = seen.req.tools.find(t => t.name === 'design_game');
    assert.deepEqual([seen.maxTurns, seen.req.max_tokens], tier === 'quality' ? [140, 32000] : [48, 24000]);
    assert.equal(design.input_schema.properties.assets, undefined, 'the first round is a pencil Demo without AI assets');
    assert.equal(design.input_schema.properties.art.maxItems, 24);
    assert.match(seen.messages[0].content, tier === 'quality' ? /档位：品质/ : /档位：Demo/);
    assert.match(seen.messages[0].content, /Pencil/);
  }
});

test('old workflows keep their gates; new iterations additionally require current input-play evidence', () => {
  const f = fixture(); nativeEvidence(f);
  assert.match(acceptanceFor(f.workflow, rev).issues.join(' '), /真实输入/);
  recordEvidence(f.workflow, { kind: 'play', sourceRevision: 'b'.repeat(64), ok: true });
  assert.equal(acceptanceFor(f.workflow, rev).ok, false);
  recordEvidence(f.workflow, { kind: 'play', sourceRevision: rev, ok: true });
  assert.equal(acceptanceFor(f.workflow, rev).ok, true);
  delete f.workflow.iteration; assert.equal(acceptanceFor(f.workflow, rev).ok, true);
});

test('restart marks the durable iteration paused and retains completed work and next steps', () => {
  const f = fixture(); f.workflow.tasks = [{ id: 'a', status: 'applied' }, { id: 'b', status: 'running' }];
  updateIteration(f.workflow.iteration, { phase: 'build', nextSteps: ['Refine feedback'] });
  recoverWorkflow(f.workflow);
  assert.equal(f.workflow.iteration.phase, 'paused'); assert.equal(f.workflow.tasks[0].status, 'applied');
  assert.equal(f.workflow.tasks[1].status, 'interrupted'); assert.deepEqual(f.workflow.iteration.nextSteps, ['Refine feedback']);
});

test('writes and patches save without exporting; checkpoints reuse the same verified revision', async () => {
  const f = fixture();
  await f.session.exec('write_file', { path: 'view.gd', content: 'extends Node2D\n' });
  await f.session.exec('patch_file', { path: 'view.gd', old: 'Node2D', new: 'Control' });
  assert.equal(f.calls.check, 0); assert.equal(f.calls.build, 0);
  assert.equal((await f.session.exec('preview_checkpoint', {})).ok, true);
  assert.deepEqual([f.calls.check, f.calls.build, f.calls.pushes], [1, 1, 1]);
  assert.equal((await f.session.exec('preview_checkpoint', {})).cached, true);
  assert.equal(f.calls.check, 1); assert.equal(f.calls.build, 1);
  await f.session.exec('patch_file', { path: 'view.gd', old: 'Control', new: 'Node' });
  await f.session.exec('preview_checkpoint', {});
  assert.equal(f.calls.check, 2); assert.equal(f.calls.build, 2);
});

test('real input-play requires run_game plus successful input eval; state reads do not count', async () => {
  const live = { running: true, async startProject() { return { loaded: true, errors: [], state: {} }; }, async eval() { return { ok: true, errors: [], value: { score: 1 } }; } };
  const f = fixture({ live });
  await f.session.exec('game_eval', { code: 'UGC.click(game.get_node("Start"))', look: false });
  assert.equal(f.workflow.evidence.some(e => e.kind === 'play'), false);
  await f.session.exec('run_game', {});
  await f.session.exec('game_eval', { code: 'return game.score', look: false });
  assert.equal(f.workflow.evidence.some(e => e.kind === 'play'), false);
  await f.session.exec('game_eval', { code: 'await UGC.key(KEY_SPACE, .1)\nreturn game.score', look: false });
  assert.equal(f.workflow.evidence.findLast(e => e.kind === 'play').ok, true);
  live.eval = async () => ({ ok: false, errors: [{ kind: 'error', message: 'input failed' }] });
  await f.session.exec('game_eval', { code: 'UGC.click(game)', look: false });
  assert.equal(f.workflow.evidence.findLast(e => e.kind === 'play').ok, false);
});

test('first design permits zero generated assets and optional requests are limited', async () => {
  const f = fixture(); let requested = 0;
  f.hooks.requestAsset = () => { requested++; return ''; };
  const result = await f.session.exec('design_game', { title: 'Small', assets: [] });
  assert.equal(result.ok, true); assert.equal(requested, 0); assert.equal(result.notes.length, 0);
  for (let i = 0; i < 2; i++) assert.equal((await f.session.exec('generate_asset', { id: 'a' + i, kind: 'sprite' })).ok, true);
  assert.match((await f.session.exec('generate_asset', { id: 'third', kind: 'sprite' })).error, /最多/);
  assert.equal(requested, 2);
});

test('wrap-up blocks expansion but permits fixes and diagnostics', async () => {
  const f = fixture(); f.workflow.iteration.wrapAt = Date.now() - 1;
  for (const name of ['delegate_tasks', 'generate_asset', 'design_game', 'web_fetch']) assert.match((await f.session.exec(name, {})).error, /收口/);
  assert.equal((await f.session.exec('read_file', { path: 'main.gd' })).file, 'main.gd');
  assert.equal((await f.session.exec('patch_file', { path: 'main.gd', old: 'Node', new: 'Node2D' })).ok, true);
});

test('repair attempts are finite and partial completion preserves next steps', async () => {
  const f = fixture(); f.project.check = async () => ({ ok: false, loaded: false, sourceRevision: rev, errors: [{ kind: 'error', message: 'broken' }] });
  for (let i = 0; i < 3; i++) await f.session.exec('run_test', { look: false });
  assert.match((await f.session.exec('run_test', { look: false })).error, /次数/);
  const result = await f.session.exec('finish', { summary: 'Saved core', suggestions: ['Fix input'], status: 'partial' });
  assert.equal(result.status, 'partial'); assert.deepEqual(f.workflow.iteration.nextSteps, ['Fix input']);
  assert.equal(f.workflow.iteration.phase, 'paused'); assert.equal(f.workflow.completionRequested, false);
});

test('deadline aborts a stuck invocation, preserves writes and disallows late tool calls', async () => {
  const f = fixture({ iteration: false }); let ctx;
  const result = await runProjectBuilder({ ...f, isFirst: true, userText: 'small', iterationOptions: { targetMs: 20, wrapMs: 10, hardMs: 80 }, agentRunner: async options => {
    ctx = options; await options.exec('write_file', { path: 'saved.gd', content: 'extends Node\n' }); return new Promise(() => {});
  } });
  assert.equal(result.out.budgetExpired, true); assert.equal(ctx.signal.aborted, true);
  assert.equal(result.session.finish.status, 'partial'); assert.equal(result.session.finish.budgetExpired, true);
  assert.equal(f.files['saved.gd'], 'extends Node\n');
  assert.ok((await ctx.exec('write_file', { path: 'late.gd', content: 'extends Node\n' })).error);
  assert.equal(f.files['late.gd'], undefined); assert.equal(f.workflow.iteration.phase, 'paused');
});

test('pre-expired rounds never invoke the generator', async () => {
  const f = fixture(); f.workflow.iteration.deadlineAt = Date.now() - 1;
  const out = await runProjectBuilder({ ...f, isFirst: true, userText: 'small', agentRunner: () => assert.fail('must not run') });
  assert.equal(out.out.budgetExpired, true); assert.equal(out.session.finish.status, 'partial');
});

test('player participation is injected only at a main request boundary', async () => {
  const f = fixture({ iteration: false }); let delivered = 0;
  f.hooks.takeParticipation = () => ++delivered === 1 ? '玩家建议：逐张说明计分' : '';
  await runProjectBuilder({ ...f, isFirst: true, userText: 'small', agentRunner: async options => {
    assert.equal(delivered, 0);
    const before = options.messages.length;
    await options.beforeTurn(options.messages);
    assert.equal(options.messages.length, before + 1);
    assert.equal(options.messages.at(-1).role, 'user');
    assert.match(options.messages.at(-1).content, /逐张说明/);
    await options.beforeTurn(options.messages);
    assert.equal(options.messages.length, before + 1);
    return { done: true };
  } });
});

test('tool watchdog cancels actual work and suppresses late verification evidence', async () => {
  const f = fixture({ iteration: false }); let actualSignal, release;
  f.project.check = ({ signal }) => { actualSignal = signal; return new Promise(resolve => { release = resolve; }); };
  const result = await runProjectBuilder({ ...f, isFirst: true, userText: 'small', toolTimeoutMs: 25, agentRunner: async options => {
    await options.exec('preview_checkpoint', {}); return { done: true };
  } });
  assert.equal(actualSignal.aborted, true); assert.equal(result.out.timedOut, true);
  assert.equal(result.out.budgetExpired, false); assert.equal(result.session.finish.status, 'partial');
  release({ ok: true, loaded: true, sourceRevision: rev, errors: [] }); await sleep(5);
  assert.equal(f.calls.build, 0); assert.equal(f.workflow.evidence.length, 0);
});

test('waiting behind a slow project lock holder does not count as a tool timeout', async () => {
  const f = fixture({ iteration: false });
  const busy = f.project.withLock(() => sleep(80));
  const result = await runProjectBuilder({ ...f, isFirst: true, userText: 'small', toolTimeoutMs: 40, agentRunner: async options => {
    const r = await options.exec('write_file', { path: 'queued.gd', content: 'extends Node\n' });
    assert.equal(r.error, undefined); return { done: true };
  } });
  await busy;
  assert.notEqual(result.out.timedOut, true); assert.equal(f.files['queued.gd'], 'extends Node\n');
});

test('web requests receive the round cancellation signal and cannot continue the loop', async () => {
  const ac = new AbortController(), f = fixture({ iteration: false }); let actualSignal;
  const result = await runProjectBuilder({ ...f, signal: ac.signal, isFirst: true, userText: 'small', fetchImpl: (_url, options) => {
    actualSignal = options.signal; setTimeout(() => ac.abort(new Error('user stopped')), 10);
    return new Promise((_, reject) => options.signal.addEventListener('abort', () => reject(options.signal.reason), { once: true }));
  }, agentRunner: async options => { await options.exec('web_fetch', { url: 'https://example.com/' }); return { done: true }; } });
  assert.equal(actualSignal.aborted, true); assert.equal(result.session.finish.status, 'cancelled');
  assert.equal(result.out.budgetExpired, false);
});

test('queued writes recheck cancellation under the project lock', async () => {
  const f = fixture({ iteration: false }), ac = new AbortController(); let release;
  f.project.withLock = fn => new Promise(resolve => { release = () => Promise.resolve().then(fn).then(resolve, resolve); });
  const run = runProjectBuilder({ ...f, signal: ac.signal, isFirst: true, userText: 'small', agentRunner: async options => {
    const pending = options.exec('write_file', { path: 'late.gd', content: 'extends Node\n' }); setTimeout(() => ac.abort(), 5); await pending; return { done: true };
  } });
  const out = await run; release(); await sleep(5);
  assert.equal(out.session.finish.status, 'cancelled'); assert.equal(f.files['late.gd'], undefined);
});

test('a normal answer without finish cannot declare completion', async () => {
  const f = fixture({ iteration: false });
  const out = await runProjectBuilder({ ...f, isFirst: true, userText: 'small', agentRunner: async () => ({ done: true }) });
  assert.equal(out.session.finish.status, 'partial'); assert.equal(f.workflow.completionRequested, false);
});

test('builder uses inactivity timeout rather than wrapping every request in an absolute deadline', async () => {
  const f = fixture({ iteration: false });
  const fetchImpl = async () => assert.fail('no request expected');
  await runProjectBuilder({ ...f, isFirst: true, userText: 'small', fetchImpl, agentRunner: async options => {
    assert.equal(options.idleTimeoutMs, 90000);
    assert.equal(options.deps.fetchImpl, fetchImpl, 'do not wrap productive requests in AbortSignal.timeout');
    return { done: true };
  } });
});

test('worker deadline is absolute, rejects oversized batches and retains private candidates on timeout', async t => {
  const f = fixture(), dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ugc-iteration-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  let calls = 0;
  const invalid = await runTaskBatch({ project: f.project, artifactDir: dir, tasks: [task('a'), task('b'), task('c')], runWorker: async () => { calls++; } });
  assert.equal(invalid.ok, false); assert.equal(calls, 0);
  const expired = await runTaskBatch({ project: f.project, artifactDir: dir, deadlineAt: Date.now() - 1, tasks: [task('a')], runWorker: async () => { calls++; } });
  assert.equal(expired.tasks[0].status, 'cancelled'); assert.equal(calls, 0);
  let ctx;
  const timeout = await runTaskBatch({ project: f.project, artifactDir: dir, deadlineAt: Date.now() + 30, timeoutMs: 1000, tasks: [task('a')], runWorker: async value => {
    ctx = value; await ctx.exec('write_file', { path: 'a.gd', content: 'extends Node\n' }); return new Promise(() => {});
  } });
  assert.equal(timeout.tasks[0].status, 'cancelled'); assert.equal(ctx.signal.aborted, true);
  assert.equal(f.files['a.gd'], undefined);
  const saved = JSON.parse(fs.readFileSync(path.join(dir, timeout.tasks[0].artifact), 'utf8'));
  assert.equal(saved.candidate['a.gd'], 'extends Node\n');
});

test('complete round still waits for exact browser build receipt and blocks tools after finish', async () => {
  const live = { running: true, async startProject() { return { loaded: true, errors: [], state: {} }; }, async eval() { return { ok: true, errors: [], value: { score: 1 } }; } };
  const f = fixture({ live });
  const result = await runProjectBuilder({ ...f, live, isFirst: true, userText: 'small', agentRunner: async options => {
    await options.exec('run_game', {});
    await options.exec('game_eval', { code: 'await UGC.press("shoot", .1)\nreturn game.score', look: false });
    await options.exec('run_test', { look: false });
    const finish = await options.exec('finish', { summary: 'Core playable', suggestions: ['Refine one animation'], milestone_done: 'M1' });
    assert.equal(finish.status, 'ready');
    assert.ok((await options.exec('write_file', { path: 'late.gd', content: 'extends Node\n' })).error);
    return { done: true };
  } });
  assert.equal(result.session.finish.status, 'ready'); assert.equal(f.calls.build, 1);
  assert.deepEqual(f.workflow.iteration.nextSteps, ['Refine one animation']);
  recordEvidence(f.workflow, { kind: 'preview', sourceRevision: rev, buildId: 'f'.repeat(32), ok: true });
  settleWorkflow(f.workflow, rev); assert.equal(f.workflow.status, 'ready');
  recordEvidence(f.workflow, { kind: 'preview', sourceRevision: rev, buildId: f.project.latestBuild.buildId, ok: true });
  settleWorkflow(f.workflow, rev); assert.equal(f.workflow.status, 'completed');
  assert.equal(f.files['late.gd'], undefined);
});

test('round cancellation waits for worker terminal metadata while keeping independent applied work', async t => {
  const f = fixture(), ac = new AbortController(), dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ugc-round-team-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  let slow;
  const hooks = { ...f.hooks, workflow(run) {
    if (run.tasks.some(t => t.id === 'fast' && t.status === 'applied') && slow) setTimeout(() => ac.abort(new Error('stopped')), 5);
  } };
  const result = await runProjectBuilder({ ...f, hooks, signal: ac.signal, artifactDir: dir, isFirst: true, userText: 'small', runWorker: async ctx => {
    await ctx.exec('write_file', { path: ctx.task.files[0], content: 'extends Node\n' });
    if (ctx.task.id === 'slow') { slow = ctx; return new Promise(() => {}); }
    await ctx.exec('submit_task', { summary: 'Implemented candidate', acceptance: [{ criterion: 'works', evidence: 'fast.gd implementation', passed: true }] });
  }, agentRunner: async options => { await options.exec('delegate_tasks', { tasks: [task('fast'), task('slow')] }); return { done: true }; } });
  assert.equal(result.session.finish.status, 'cancelled');
  assert.deepEqual(f.workflow.tasks.map(t => t.status), ['applied', 'cancelled']);
  assert.equal(f.files['fast.gd'], 'extends Node\n'); assert.equal(f.files['slow.gd'], undefined);
  assert.equal(slow.signal.aborted, true);
  assert.ok((await slow.exec('submit_task', {})).error);
});
