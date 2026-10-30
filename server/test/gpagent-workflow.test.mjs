import test from 'node:test';
import assert from 'node:assert/strict';
import { ProjectSession } from '../gpagent.mjs';
import { emptyGame } from '../engine.mjs';
import { createWorkflow, recordEvidence, upsertTask } from '../workflow.mjs';

function fixture() {
  let revision = 'a'.repeat(64);
  const project = { revision: () => revision, withLock: async fn => fn(), sources: () => ({}) };
  const workflow = createWorkflow({ goal: 'fix gameplay', sourceRevision: revision });
  const session = new ProjectSession(emptyGame(), project, { emit() {}, workflow() {}, assets: () => ({}) }, { workflow });
  function verify() {
    recordEvidence(workflow, { kind: 'compile', sourceRevision: revision, ok: true });
    recordEvidence(workflow, { kind: 'test', sourceRevision: revision, ok: true, checks: [{ ok: true, what: 'win after goal reached' }] });
    recordEvidence(workflow, { kind: 'build', sourceRevision: revision, buildId: '1'.repeat(32), ok: true });
  }
  return { session, workflow, verify, edit() { revision = 'b'.repeat(64); } };
}
test('finish no longer accepts a milestone without verified work', async () => {
  const f = fixture();
  assert.ok((await f.session.exec('finish', { summary: 'done', milestone_done: 'M1' })).error);
  assert.equal(f.session.finish, null);
});
test('native verification waits for the preview and a later edit rejects completion', async () => {
  const f = fixture(); f.verify();
  const result = await f.session.exec('finish', { summary: 'game works', milestone_done: 'M1' });
  assert.equal(result.status, 'ready'); assert.equal(f.session.finish.milestone_done, '');
  assert.equal(f.workflow.pendingMilestone, 'M1');
  const g = fixture(); g.verify(); g.edit();
  assert.ok((await g.session.exec('finish', { summary: 'done' })).error);
});
test('partial and exhausted budget can save work without falsely finishing a milestone', async () => {
  for (const expired of [true, false]) {
    const f = fixture();
    if (expired) { f.session.budget = { hard: 0, soft: 0 }; f.session.t0 -= 100; }
    const result = await f.session.exec('finish', { summary: 'work remains', status: expired ? 'complete' : 'partial', milestone_done: 'M1' });
    assert.equal(result.status, 'partial'); assert.equal(f.session.finish.milestone_done, '');
    assert.equal(f.workflow.completionRequested, false);
  }
});
test('failed tasks require current native acceptance before manual resolution', async () => {
  const f = fixture();
  upsertTask(f.workflow, { id: 'rules', title: '规则', status: 'failed', error: 'wrong score' });
  assert.ok((await f.session.exec('resolve_task', { id: 'rules', resolution: 'fixed score' })).error);
  f.verify();
  assert.equal((await f.session.exec('resolve_task', { id: 'rules', resolution: 'fixed score and ran core loop' })).ok, true);
  assert.equal(f.workflow.tasks[0].status, 'applied');
  assert.equal(f.workflow.tasks[0].verified, false);
});
test('verification-only turns get current evidence and expose a failed preview build', async () => {
  const f = fixture(), revision = f.session.project.revision();
  f.session.project.check = async () => ({ ok: true, loaded: true, errors: [], sourceRevision: revision });
  f.session.project.selfTest = async () => ({ ok: true, loaded: true, has_test: true, sourceRevision: revision, errors: [], checks: [{ ok: true, what: 'click collects exactly one' }] });
  f.session.project.build = async () => ({ ok: false, sourceRevision: revision, error: 'export failed' });
  const result = await f.session.exec('run_test', { look: false });
  assert.equal(result.ok, false); assert.equal(result.tests_ok, true);
  assert.equal(result.build.error, 'export failed'); assert.match(result.hint, /构建失败/);
  assert.equal(f.workflow.evidence.find(e => e.kind === 'compile').ok, true);
  assert.ok((await f.session.exec('finish', { summary: 'ready' })).error);
});
