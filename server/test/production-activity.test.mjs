import test from 'node:test';
import assert from 'node:assert/strict';
import { recordProductionActivity, requestedIterationOptions } from '../production-activity.mjs';

function fixture() {
  const workflow = { id: 'run', status: 'running', tasks: [], evidence: [], iteration: { phase: 'build' } };
  let seq = 0;
  return { workflow, emit: event => recordProductionActivity(workflow, { seq: ++seq, t: 1000 + seq, ...event }) };
}
test('private thinking and raw code progress never become public production records', () => {
  const { workflow, emit } = fixture();
  assert.equal(emit({ type: 'thinking', text: 'private token stream' }), null);
  assert.equal(emit({ type: 'tool_progress', code: 'uncommitted source' }), null);
  assert.deepEqual(workflow.activity, []);
});
test('saved source, applied task and startup receipts have distinct claims', () => {
  const { workflow, emit } = fixture();
  const saved = emit({ type: 'code_write', file: 'main.gd', created: true, step: '角色移动', code: 'PRIVATE_SOURCE' });
  assert.equal(saved.status, 'saved'); assert.equal(saved.file, 'main.gd');
  assert.equal(JSON.stringify(saved).includes('PRIVATE_SOURCE'), false);
  const applied = emit({ type: 'task', runId: 'run', task: { id: 'scene', title: '场景', status: 'applied', changed: ['view.gd'] } });
  assert.match(applied.title, /等待验收/);
  workflow.evidence.push({ id: 'receipt', kind: 'preview', ok: true });
  assert.match(emit({ type: 'workflow' }).detail, /玩法验收另行记录/);
});
test('worker failures and rejected gameplay checks remain visible as failures', () => {
  const { emit } = fixture();
  assert.equal(emit({ type: 'task', task: { id: 'rules', title: '玩法', status: 'failed', error: 'no submission' } }).status, 'failed');
  const failed = emit({ type: 'test', ok: false, checks: [{ ok: true }, { ok: false }] });
  assert.equal(failed.status, 'failed'); assert.match(failed.detail, /1\/2/);
});
test('only local captured screenshots enter the projection, text is bounded', () => {
  const { emit } = fixture();
  assert.equal(emit({ type: 'eval', ok: true, shot: '/covers/test-1.jpg' }).image, '/covers/test-1.jpg');
  for (const shot of ['https://remote/track.jpg', 'javascript:alert(1)', '/covers/../secret', 'data:image/png;base64,a']) {
    assert.equal(emit({ type: 'eval', ok: true, shot }).image, undefined);
  }
  assert.ok(emit({ type: 'code_write', step: 'a'.repeat(10000) }).detail.length <= 220);
});
test('repeated snapshots and worker progress deduplicate while actual file changes remain', () => {
  const { workflow, emit } = fixture();
  workflow.evidence.push({ id: 'compile', kind: 'compile', ok: true });
  emit({ type: 'workflow' }); emit({ type: 'workflow' });
  const task = { id: 'rules', status: 'running', attempt: 1, last_tool: 'read_file' };
  emit({ type: 'task', task }); emit({ type: 'task', task });
  emit({ type: 'task', task: { ...task, last_tool: 'write_file' } });
  assert.equal(workflow.activity.length, 3);
  assert.equal(emit({ type: 'task', runId: 'another', task }), null);
});
test('bounded saved activity survives JSON roundtrip and excludes unstarted success', () => {
  const { workflow, emit } = fixture();
  for (let i = 0; i < 90; i++) emit({ type: 'code_write', file: `file${i}.gd` });
  assert.equal(workflow.activity.length, 60);
  assert.equal(workflow.activity[0].file, 'file30.gd');
  assert.deepEqual(JSON.parse(JSON.stringify(workflow)).activity, workflow.activity);
  assert.equal(workflow.activity.some(item => item.status === 'passed'), false);
});
test('handoff distinguishes actual completion, awaiting preview and saved partial work', () => {
  const { workflow, emit } = fixture();
  assert.match(emit({ type: 'turn_end', status: 'ready' }).title, /等待窗口确认/);
  workflow.iteration.reason = 'deadline';
  assert.match(emit({ type: 'turn_end', status: 'partial' }).title, /时限/);
  assert.equal(emit({ type: 'turn_end', status: 'partial' }).stage, 'paused');
  assert.match(emit({ type: 'turn_end', status: 'completed' }).title, /交给你试玩/);
});
test('client may select the demo or quality tier but cannot grant unlimited execution', () => {
  assert.deepEqual(requestedIterationOptions({ tier: 'demo' }, true, 100), { kind: 'demo', tier: 'demo', targetMs: 300000, startedAt: 100 });
  assert.deepEqual(requestedIterationOptions({ tier: 'quality' }, true, 100), { kind: 'demo', tier: 'quality', targetMs: 1500000, startedAt: 100 });
  for (const value of [undefined, {}, { tier: 'max' }, { targetMinutes: 10 }, { targetMinutes: 999 }]) assert.equal(requestedIterationOptions(value, false).tier, 'demo');
  assert.deepEqual(requestedIterationOptions({ tier: 'quality', targetMs: 1e12, hardMs: Infinity, startedAt: 0, kind: 'skip_checks' }, false, 100), { kind: 'iteration', tier: 'quality', targetMs: 1500000, startedAt: 100 });
});

test('compaction never replays an old passed test with a fresh timestamp', () => {
  const { workflow, emit } = fixture();
  workflow.startedAt = 100;
  workflow.evidence.push({ id: 'test-old', at: 200, kind: 'test', sourceRevision: 'old', ok: true });
  assert.equal(emit({ type: 'workflow' }).at, 200);
  for (let i = 0; i < 65; i++) emit({ type: 'code_write', file: 'edited.gd' });
  workflow.sourceRevision = 'new';
  assert.equal(emit({ type: 'workflow' }), null);
  assert.equal(workflow.activity.some(item => item.kind === 'test'), false);
});

test('carried previous-round evidence is historical, not new production progress', () => {
  const { workflow, emit } = fixture(); workflow.startedAt = 500;
  workflow.evidence.push({ id: 'previous', at: 200, kind: 'test', ok: true });
  assert.equal(emit({ type: 'workflow' }), null);
});
