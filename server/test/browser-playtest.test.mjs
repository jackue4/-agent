import test from 'node:test';
import assert from 'node:assert/strict';
import { BrowserPlaytest } from '../browser-playtest.mjs';
import { ProjectSession } from '../gpagent.mjs';
import { emptyGame } from '../engine.mjs';
import { createWorkflow } from '../workflow.mjs';

const tick = () => new Promise(resolve => setImmediate(resolve));
const reply = (command, data = {}, phase = 'result') => ({ ...command, phase, data: { loaded: true, ok: true, errors: [], checks: [], state: {}, ...data } });
function fixture(t) {
  let now = 1000, revision = 'a'.repeat(64);
  const events = [], browser = new BrowserPlaytest('demo', { emit: e => events.push(e), clock: () => now, pollMs: 5, leaseMs: 100, timeoutMs: 100 });
  t.after(() => browser.stop());
  const project = { revision: () => revision, latestBuild: { buildId: 'b'.repeat(32), sourceRevision: revision, version: 1 }, build: async () => assert.fail('unexpected build') };
  browser.heartbeat({ clientId: 'visible-client', visible: true, supported: true });
  return { browser, project, events, advance: ms => { now += ms; }, edit: () => { revision = 'c'.repeat(64); } };
}
async function launch(f) {
  const pending = f.browser.startProject(f.project, 'landscape'); await tick();
  const command = f.browser.next('visible-client'); assert.equal(command.kind, 'run');
  assert.equal(f.browser.receive(reply(command)).ok, true); const result = await pending;
  return { command, result };
}

test('visible capability lease is required; hidden/expired clients are unavailable', async t => {
  const f = fixture(t); assert.equal(f.browser.available, true);
  f.advance(101); assert.equal(f.browser.available, false);
  await assert.rejects(f.browser.startProject(f.project, 'landscape'), /没有可用/);
  assert.equal(f.browser.heartbeat({ clientId: '../x', visible: true, supported: true }).ok, false);
});

test('run/eval bind one immutable runtime; duplicate, wrong-client and stale results cannot resolve', async t => {
  const f = fixture(t), { command, result } = await launch(f);
  assert.equal(result.mode, 'browser'); assert.equal(f.browser.running, true);
  assert.match(command.pckUrl, /game\.pck\?build=b{32}$/);
  const waiting = f.browser.eval('return 1', { step: '验证角色绕过箱子' }); const evalCommand = f.browser.next('visible-client');
  assert.equal(evalCommand.step, '验证角色绕过箱子');
  assert.equal(evalCommand.runtimeSession, command.runtimeSession); assert.notEqual(evalCommand.commandId, command.commandId);
  for (const key of ['clientId', 'commandId', 'runtimeSession', 'buildId', 'sourceRevision', 'kind']) assert.equal(f.browser.receive({ ...reply(evalCommand), [key]: 'wrong' }).ok, false, key);
  assert.equal(f.browser.receive(reply(command)).duplicate, true);
  f.browser.receive(reply(evalCommand, { checks: [{ ok: true, what: 'mid' }], metrics: { frames: 12, fps: 58, invalid: '60' } }, 'progress'));
  assert.equal(f.browser.pending.command.commandId, evalCommand.commandId);
  assert.deepEqual(f.events.at(-1).metrics, { frames: 12, fps: 58 });
  f.browser.receive(reply(evalCommand, { value: 1 })); assert.equal((await waiting).value, 1);
  assert.equal(f.browser.receive(reply(evalCommand)).duplicate, true);
});

test('test starts a fresh runtime and cannot pass with no/invalid/failed assertions', async t => {
  const f = fixture(t), first = await launch(f);
  for (const checks of [[], [{ what: 'no boolean' }], [{ ok: false, what: 'failed' }]]) {
    const waiting = f.browser.selfTest(f.project, { sourceRevision: f.project.revision() }); await tick();
    const command = f.browser.next('visible-client'); assert.equal(command.kind, 'test'); assert.notEqual(command.runtimeSession, first.command.runtimeSession);
    f.browser.receive(reply(command, { has_test: true, checks })); assert.equal((await waiting).ok, false);
  }
  const waiting = f.browser.selfTest(f.project, {}); await tick();
  f.browser.receive(reply(f.browser.next('visible-client'), { has_test: true, checks: [{ ok: true, what: 'moved' }] }));
  const result = await waiting; assert.equal(result.ok, true); assert.equal(result.assertionCount, 1); assert.equal(f.browser.running, false);
});

test('run and eval cannot pass when any executed valid assertion fails', async t => {
  const checks = [{ ok: true, what: 'D moved right' }, { ok: false, what: 'W movement blocked by relocated box B' }];
  for (const kind of ['run', 'eval']) await t.test(kind, async st => {
    const f = fixture(st);
    if (kind === 'eval') await launch(f);
    const waiting = kind === 'run' ? f.browser.startProject(f.project, 'landscape') : f.browser.eval('UGC.check(false, "blocked")');
    await tick();
    const command = f.browser.next('visible-client');
    assert.equal(f.browser.receive(reply(command, { ok: true, checks })).accepted, true);
    const result = await waiting;
    assert.equal(result.ok, false); assert.deepEqual(result.checks, checks);
    assert.equal(f.events.at(-1).phase, 'result'); assert.equal(f.events.at(-1).ok, false);
  });
});

test('display truncation cannot hide a late failed eval assertion', async t => {
  const f = fixture(t); await launch(f);
  const waiting = f.browser.eval('return true');
  const checks = Array.from({ length: 1000 }, (_, i) => ({ ok: true, what: 'check ' + i }));
  checks.push({ ok: false, what: 'late failure' });
  f.browser.receive(reply(f.browser.next('visible-client'), { checks }));
  assert.equal((await waiting).ok, false);
});

test('source edits, disconnects, timeout and cancellation fail bound commands without fallback', async t => {
  for (const cause of ['edit', 'hidden', 'lease', 'timeout', 'abort']) await t.test(cause, async st => {
    const f = fixture(st); await launch(f); const controller = new AbortController();
    const waiting = assert.rejects(f.browser.eval('await UGC.wait(20)', { signal: controller.signal, timeoutMs: 10 }));
    const command = f.browser.next('visible-client');
    if (cause === 'edit') { f.edit(); assert.equal(f.browser.receive(reply(command)).ok, false); }
    if (cause === 'hidden') f.browser.heartbeat({ clientId: 'visible-client', visible: false, supported: true });
    if (cause === 'lease') f.advance(101);
    if (cause === 'timeout') { f.advance(10011); f.browser.heartbeat({ clientId: 'visible-client', visible: true, supported: true }); }
    if (cause === 'abort') controller.abort();
    await waiting; assert.equal(f.browser.running, false); assert.equal(f.browser.receive(reply(command)).ok, false);
    assert.equal(f.browser.next('visible-client').kind, 'stop');
  });
});

test('stop or source mutation while build is pending cannot start a late runtime', async t => {
  const f = fixture(t); let done;
  f.project.latestBuild = null; f.project.build = () => new Promise(resolve => { done = resolve; });
  const waiting = assert.rejects(f.browser.startProject(f.project, 'landscape'), /停止|替换/);
  await tick(); f.browser.stop(); done({ ok: true, buildId: 'd'.repeat(32), sourceRevision: f.project.revision() }); await waiting;
  assert.equal(f.browser.running, false); assert.equal(f.browser.pending, null);
});

function sessionFixture(browser) {
  const calls = [], workflow = createWorkflow({ goal: 'browser test', sourceRevision: 'rev' });
  const project = { revision: () => 'rev', sources: () => ({}), withLock: async fn => fn(),
    latestBuild: null, check: async () => { calls.push('check'); return { ok: true, loaded: true, errors: [], sourceRevision: 'rev' }; },
    build: async () => { calls.push('build'); project.latestBuild = { ok: true, buildId: 'build', sourceRevision: 'rev' }; return project.latestBuild; },
    selfTest: async () => { calls.push('native-test'); return { ok: true, loaded: true, has_test: true, checks: [{ ok: true, what: 'test' }], errors: [], sourceRevision: 'rev' }; } };
  const live = { running: false, stop() { this.running = false; }, async startProject() { calls.push('native-run'); this.running = true; return { loaded: true, errors: [], state: {} }; }, async eval() { calls.push('native-eval'); return { ok: true, errors: [], state: {} }; } };
  const session = new ProjectSession(emptyGame(), project, { emit() {}, workflow() {}, assets: () => ({}), pushPck() { calls.push('push'); } }, { live, workflow, browserPlaytest: browser });
  return { session, calls, project };
}

test('ProjectSession uses browser execution and builds before browser self-test, with no native duplication', async () => {
  const browser = { available: true, running: false, stop() { this.running = false; }, async startProject() { this.running = true; return { loaded: true, ok: true, errors: [], state: {} }; }, async eval() { return { loaded: true, ok: true, errors: [], state: {}, metrics: { frames: 5 } }; }, async selfTest(project) { assert.equal(project.latestBuild?.sourceRevision, 'rev'); return { mode: 'browser', loaded: true, ok: true, has_test: true, checks: [{ ok: true, what: 'actual check' }], errors: [], sourceRevision: 'rev' }; } };
  const f = sessionFixture(browser);
  assert.equal((await f.session.exec('run_game', {})).mode, 'browser');
  assert.equal((await f.session.exec('game_eval', { code: 'return true' })).mode, 'browser');
  assert.equal((await f.session.exec('run_test', {})).mode, 'browser');
  assert.equal(f.calls.some(c => c.startsWith('native')), false); assert.ok(f.calls.includes('check')); assert.ok(f.calls.includes('build'));
});

test('ProjectSession reports native mode when no browser is available', async () => {
  const f = sessionFixture({ available: false, stop() {} });
  assert.equal((await f.session.exec('run_game', {})).mode, 'native'); assert.ok(f.calls.includes('native-run'));
});

test('a browser transport failure hands the rest of the round to the native window, honestly labelled', async () => {
  const browser = { available: true, stop() {}, async startProject() { throw new Error('浏览器验收超时，未取得有效结果'); }, async selfTest() { throw new Error('never used'); } };
  const f = sessionFixture(browser);
  const run = await f.session.exec('run_game', {});
  assert.equal(run.mode, 'native'); assert.match(run.fallback, /原生窗口/); assert.ok(f.calls.includes('native-run'));
  const play = await f.session.exec('game_eval', { code: 'UGC.press("ui_left", 0.2)', look: false });
  assert.equal(play.mode, 'native'); assert.equal(f.session.workflow.evidence.findLast(e => e.kind === 'play')?.ok, true);
  assert.equal((await f.session.exec('run_test', {})).mode, 'native', 'a flapping browser is not retried in the same round');
  assert.ok(f.calls.includes('native-test'));
});

test('game failures inside a working browser are not mistaken for a lost browser', async () => {
  const browser = { available: true, running: false, stop() { this.running = false; }, async startProject() { this.running = true; return { loaded: true, ok: false, errors: [{ kind: 'error', message: 'Invalid call' }], state: {} }; } };
  const f = sessionFixture(browser);
  const run = await f.session.exec('run_game', {});
  assert.equal(run.mode, 'browser'); assert.equal(run.ok, false); assert.equal(f.calls.some(c => c.startsWith('native')), false);
});

test('a browser that leaves mid-test hands the same revision to native verification', async () => {
  const browser = { available: true, stop() {}, async selfTest() { browser.available = false; throw new Error('验收浏览器连接已断开'); } };
  const f = sessionFixture(browser);
  const r = await f.session.exec('run_test', {});
  assert.equal(r.mode, 'native'); assert.equal(r.tests_ok, true); assert.match(r.fallback, /验收浏览器不可用.*原生窗口/);
  assert.ok(f.calls.includes('native-test'));
  const test = f.session.workflow.evidence.findLast(e => e.kind === 'test');
  assert.equal(test.ok, true);
  const later = await f.session.exec('run_game', {});
  assert.equal(later.mode, 'native', 'later live play follows current availability');
});

test('game_eval returns actual failed checks so the next repair can address them', async () => {
  const checks = [{ ok: true, what: 'D moved right' }, { ok: false, what: 'W movement blocked by relocated box B' }];
  const browser = { available: true, running: false, stop() { this.running = false; },
    async startProject() { this.running = true; return { loaded: true, ok: true, errors: [], state: {} }; },
    async eval() { return { loaded: true, ok: false, errors: [], checks, state: {} }; } };
  const f = sessionFixture(browser);
  await f.session.exec('run_game', {});
  const summary = await f.session.exec('game_eval', { code: 'UGC.press("ui_up", 1.0)', look: false });
  assert.equal(summary.ok, false); assert.deepEqual(summary.checks, checks);
  const play = f.session.workflow.evidence.find(e => e.kind === 'play');
  assert.equal(play.ok, false, 'failed eval must not create passing gameplay evidence');
  const native = sessionFixture({ available: false, stop() {} });
  await native.session.exec('run_game', {});
  assert.deepEqual((await native.session.exec('game_eval', { code: 'return 1', look: false })).checks, []);
});
