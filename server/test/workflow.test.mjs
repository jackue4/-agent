import test from 'node:test';
import assert from 'node:assert/strict';
import { createWorkflow, upsertTask, recordEvidence, acceptanceFor, settleWorkflow, recoverWorkflow, resumeContext } from '../workflow.mjs';

const revision = 'a'.repeat(64), buildId = '1'.repeat(32);
function passing(run) {
  recordEvidence(run, { kind: 'compile', sourceRevision: revision, ok: true });
  recordEvidence(run, { kind: 'test', sourceRevision: revision, ok: true, checks: [{ ok: true, what: 'score increments after collecting' }] });
  recordEvidence(run, { kind: 'build', sourceRevision: revision, buildId, ok: true });
}
test('no evidence and zero assertion tests cannot complete', () => {
  const run = createWorkflow({ goal: 'play' });
  assert.equal(acceptanceFor(run, revision).ok, false);
  passing(run);
  recordEvidence(run, { kind: 'test', sourceRevision: revision, ok: true, checks: [] });
  assert.equal(acceptanceFor(run, revision).ok, false);
});
test('editing invalidates evidence and a failed newer test overrides previous success', () => {
  const run = createWorkflow({ goal: 'play' }); passing(run);
  assert.equal(acceptanceFor(run, revision).ok, true);
  assert.equal(acceptanceFor(run, 'b'.repeat(64)).ok, false);
  recordEvidence(run, { kind: 'test', sourceRevision: revision, ok: false, checks: [{ ok: false, what: 'lost health' }] });
  assert.equal(acceptanceFor(run, revision).ok, false);
});
test('completion requires an exact build receipt and unresolved tasks block it', () => {
  const run = createWorkflow({ goal: 'play' }); passing(run); run.completionRequested = true;
  upsertTask(run, { id: 'one', title: 'rules', status: 'failed' });
  settleWorkflow(run, revision); assert.equal(run.status, 'partial');
  upsertTask(run, { id: 'one', status: 'applied' });
  settleWorkflow(run, revision); assert.equal(run.status, 'ready');
  recordEvidence(run, { kind: 'preview', sourceRevision: revision, buildId: '2'.repeat(32), ok: true });
  settleWorkflow(run, revision); assert.equal(run.status, 'ready');
  recordEvidence(run, { kind: 'preview', sourceRevision: revision, buildId, ok: true });
  settleWorkflow(run, revision); assert.equal(run.status, 'completed');
  assert.equal(run.tasks[0].status, 'verified');
  recordEvidence(run, { kind: 'preview', sourceRevision: revision, buildId, ok: false });
  settleWorkflow(run, revision); assert.equal(run.status, 'ready');
});
test('restart and resume retain applied work, failures and attempt counts', () => {
  const run = createWorkflow({ goal: 'original goal' });
  upsertTask(run, { id: 'a', title: 'done', status: 'applied', files: ['done.gd'] });
  upsertTask(run, { id: 'b', title: 'unfinished', status: 'running' });
  recoverWorkflow(run);
  assert.equal(run.status, 'interrupted'); assert.equal(run.tasks[0].status, 'applied');
  assert.equal(run.tasks[1].status, 'interrupted'); assert.match(resumeContext(run), /done.gd/);
  const resumed = createWorkflow({ goal: 'continue', previous: run });
  upsertTask(resumed, { id: 'b', status: 'queued' });
  assert.equal(resumed.tasks[1].attempt, 2);
  assert.equal(run.tasks[1].attempt, 1);
  assert.equal(resumed.previousRunId, run.id);
});
