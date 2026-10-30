import test from 'node:test';
import assert from 'node:assert/strict';
import { enqueueParticipation, deliverParticipation } from '../participation.mjs';

const project = () => ({ game: { design: { modules: [{ file: 'score.gd' }] } }, workflow: { id: 'round1' }, events: [], emit(e) { this.events.push(structuredClone(e)); }, save() {} });
test('participation persists once, detects stale module and request conflicts', () => {
  const p = project();
  const input = { text: '慢一点展示倍率', moduleFile: 'score.gd', requestId: 'request-01' };
  assert.equal(enqueueParticipation(p, input, 123).status, 200);
  assert.equal(enqueueParticipation(p, input).status, 200);
  assert.equal(p.participation.length, 1);
  assert.equal(enqueueParticipation(p, { ...input, text: 'another' }).status, 409);
  assert.equal(enqueueParticipation(p, { ...input, requestId: 'request-02', moduleFile: 'gone.gd' }).status, 400);
  assert.equal(p.events[0].participation[0].status, 'queued');
});
test('delivery is explicit context only; queue survives until safe boundary and is not replayed', () => {
  const p = project();
  enqueueParticipation(p, { text: '展示筹码', requestId: 'request-01' });
  assert.equal(p.participation[0].status, 'queued');
  assert.match(deliverParticipation(p, 456), /不是完成证据/);
  assert.equal(p.participation[0].status, 'applied');
  assert.equal(p.participation[0].appliedAt, 456);
  assert.equal(p.participation[0].runId, 'round1');
  assert.equal(deliverParticipation(p), '');
  assert.equal(p.events[0].participation[0].status, 'queued');
});
test('bounded pending queue rejects empties and flood without losing previous suggestions', () => {
  const p = project();
  assert.equal(enqueueParticipation(p, { text: ' ', requestId: 'request-00' }).status, 400);
  for (let n = 0; n < 12; n++) assert.equal(enqueueParticipation(p, { text: 'idea' + n, requestId: 'request-' + n }).status, 200);
  assert.equal(enqueueParticipation(p, { text: 'extra', requestId: 'request-extra' }).status, 429);
  assert.equal(p.participation.length, 12);
});

test('an interrupted round restores previously delivered suggestions without claiming implementation', () => {
  const p = project();
  enqueueParticipation(p, { text: '慢放结算', requestId: 'request-01' });
  deliverParticipation(p, 10);
  p.workflow.id = 'round2';
  const context = deliverParticipation(p, 20, { resumeRunId: 'round1' });
  assert.match(context, /上一轮未完成，尚未确认落实/);
  assert.match(context, /慢放结算/);
  assert.equal(p.participation[0].deliveryCount, 2);
  assert.equal(p.participation[0].runId, 'round2');
  assert.equal(deliverParticipation(p, 30, { resumeRunId: 'round1' }), '');
});
