import test from 'node:test';
import assert from 'node:assert/strict';
import { PlaytestWatch } from '../playtest-watch.mjs';
import { ProjectSession } from '../gpagent.mjs';
import { emptyGame } from '../engine.mjs';
import { createWorkflow } from '../workflow.mjs';

const jpeg = Buffer.from([255, 216, 1, 2, 255, 217]);
test('watch keeps only bounded real frames and rejects stale sessions and ended producers', () => {
  const events = [], watch = new PlaytestWatch('demo', { emit: e => events.push(e), clock: () => 1000 });
  const id = watch.start({ runId: 'round1', sourceRevision: 'rev1', kind: 'test', step: '检查重开' });
  assert.equal(watch.snapshot().frameUrl, '');
  assert.equal(watch.frame(id, { seq: 1, image: Buffer.from('invalid') }), false);
  for (let seq = 1; seq <= 20; seq++) assert.equal(watch.frame(id, { seq, image: jpeg, capturedAt: 999, checks: [{ what: '已执行', ok: true }] }), true);
  assert.equal(watch.frames.size, 8); assert.equal(watch.image(id, 1), null);
  assert.deepEqual(watch.image(id, 20), jpeg); assert.equal(events.length, 2);
  assert.equal(watch.frame(id, { seq: 19, image: jpeg }), false);
  watch.end(id, { status: 'failed', errors: [{ message: '重开失败' }] });
  assert.equal(watch.snapshot().status, 'failed'); assert.equal(watch.frame(id, { seq: 21, image: jpeg }), false);
  const next = watch.start({ runId: 'round2', kind: 'eval' });
  assert.equal(watch.image(id, 20), null); assert.equal(watch.snapshot().frameSeq, 0);
  assert.equal(watch.frame(id, { seq: 22, image: jpeg }), false);
  watch.stop(); assert.equal(watch.snapshot().status, 'stopped'); assert.equal(watch.frame(next, { seq: 1, image: jpeg }), false);
});

function fixture() {
  const workflow = createWorkflow({ goal: 'watch', sourceRevision: 'rev' }), watch = new PlaytestWatch('demo');
  const project = { revision: () => 'rev', sources: () => ({}), withLock: async fn => fn(), check: async () => ({ ok: true, loaded: true, sourceRevision: 'rev', errors: [] }), build: async () => ({ ok: true, sourceRevision: 'rev', buildId: 'build1' }) };
  const frames = []; let mirrorCalls = 0, callback;
  const live = { running: false, stop() { this.running = false; }, async startProject(_project, _orientation, opts) { this.running = true; callback = opts.onFrame; callback({ seq: 1, image: jpeg }); return { loaded: true, errors: [], state: {} }; }, async eval() { callback({ seq: 2, image: jpeg }); frames.push(watch.snapshot()); return { ok: true, errors: [], state: {} }; } };
  const session = new ProjectSession(emptyGame(), project, { emit() {}, workflow() {}, assets: () => ({}), mirrorEval() { mirrorCalls++; }, watchStart: info => watch.start(info), watchFrame: (id, f) => watch.frame(id, f), watchEnd: (id, r) => watch.end(id, r) }, { workflow, live });
  return { session, project, watch, frames, workflow, live, mirrorCalls: () => mirrorCalls };
}

test('real run/eval updates the visible session before returning, without replaying inputs', async () => {
  const f = fixture();
  await f.session.exec('run_game', { step: '检查开局' });
  const run = f.watch.snapshot(); assert.equal(run.status, 'passed'); assert.equal(run.kind, 'run'); assert.equal(run.frameSeq, 1);
  await f.session.exec('game_eval', { code: 'return true', step: '检查移动' });
  assert.equal(f.frames[0].status, 'live'); assert.notEqual(f.frames[0].sessionId, run.sessionId);
  assert.equal(f.watch.snapshot().status, 'passed'); assert.equal(f.mirrorCalls(), 0);
  assert.equal(f.workflow.evidence.some(e => e.kind === 'preview'), false);
});
test('self-test publishes intermediate checks and a failed result without accepting gameplay', async () => {
  const f = fixture();
  f.project.selfTest = async ({ onFrame }) => {
    onFrame({ seq: 1, image: jpeg, checks: [{ what: '开局', ok: true }] });
    assert.equal(f.watch.snapshot().status, 'live'); assert.equal(f.watch.snapshot().checks.length, 1);
    return { ok: false, loaded: true, has_test: true, sourceRevision: 'rev', checks: [{ what: '开局', ok: true }, { what: '重开', ok: false }], errors: [] };
  };
  await f.session.exec('run_test', {});
  assert.equal(f.watch.snapshot().status, 'failed'); assert.equal(f.watch.snapshot().checks.length, 2);
  assert.equal(f.workflow.evidence.find(e => e.kind === 'test').ok, false);
});
test('exception and partial stop end the watch; a late frame cannot revive it', async () => {
  const f = fixture(); f.project.check = async () => { throw new Error('compile failed'); };
  await f.session.exec('run_game', {}); assert.equal(f.watch.snapshot().status, 'failed');
  f.session.beginWatch('test', 'check'); f.session.savePartial('stopped', { cancelled: true });
  f.session.onWatchFrame({ seq: 99, image: jpeg }); assert.equal(f.watch.snapshot().status, 'stopped'); assert.equal(f.watch.snapshot().frameSeq, 0);
});
