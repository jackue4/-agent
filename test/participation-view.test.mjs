import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const source = await readFile(new URL('../web/participation-view.js', import.meta.url), 'utf8');
const { focusModule, moduleSuggestions, participationRows, mergeParticipation, participationLabel, participationSummary } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
test('module focus uses an actual known file and its authoritative label, never iframe-invented labels', () => {
  const rows = [{ file: 'score.gd', label: '计分规则', kind: 'score' }];
  const focus = focusModule({ file: 'res://score.gd', label: '伪造的全新功能' }, rows);
  assert.deepEqual(focus, { file: 'score.gd', label: '计分规则', kind: 'score' });
  assert.equal(focusModule({ file: '../score.gd' }, rows), null);
  assert.equal(focusModule({ file: 'unknown.gd' }, rows), null);
  assert.ok(moduleSuggestions(focus).includes('解释分数是怎么算的'));
});
test('queued and delivered receipts never imply implementation and respect next-round delivery', () => {
  const queued = { id: '1', status: 'queued', text: '调整选牌', t: 1 };
  assert.equal(participationLabel(queued, { running: true }), '等待下个工作节点');
  assert.equal(participationLabel(queued, { running: true, delivery: 'next_round' }), '下轮开始时送达');
  assert.equal(participationLabel(queued, { running: false }), '下轮开始时送达');
  const applied = { ...queued, status: 'applied' };
  assert.equal(participationLabel(applied), '已送达本轮');
  assert.match(participationSummary([applied]), /尚不代表已经实现/);
  assert.deepEqual(participationRows([{ id: 'fake', status: 'completed' }]), []);
});
test('a slower POST response cannot regress an already delivered SSE receipt', () => {
  const applied = { id: '1', text: '更清晰', status: 'applied', t: 1, appliedAt: 2 };
  const merged = mergeParticipation([applied], [{ ...applied, status: 'queued', appliedAt: undefined }, { id: '2', text: '下一条', status: 'queued', t: 3 }]);
  assert.equal(merged[0].status, 'applied'); assert.equal(merged[0].appliedAt, 2); assert.equal(merged.length, 2);
});
