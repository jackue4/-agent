import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const source = await readFile(new URL('../web/construction-view.js', import.meta.url), 'utf8');
const { validConstruction, acceptConstruction, assessConstructionReceipt } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
const scene = { schema: 1, dimension: '3d', revision: 3, runId: 'run-a', objects: [{ id: 'floor' }] };
test('construction snapshots advance only on a committed current-run newer revision', () => {
  assert.equal(validConstruction(scene), true);
  assert.equal(acceptConstruction(null, scene, 'run-a', 'run-a'), scene);
  assert.equal(acceptConstruction(scene, { ...scene, revision: 4 }, 'run-b', 'run-a'), scene);
  assert.equal(acceptConstruction(scene, { ...scene, revision: 2 }, 'run-a', 'run-a'), scene);
  assert.equal(acceptConstruction(scene, { type: 'tool_progress', lines: 500 }, 'run-a', 'run-a'), scene);
});
test('construction receipts prove only the current scene revision and actual object count', () => {
  const receipt = { type: 'construction_applied', surface: 'construction', revision: 3, runId: 'run-a', loaded: true, objectCount: 1, errors: [] };
  assert.equal(assessConstructionReceipt(receipt, scene).loaded, true);
  assert.equal(assessConstructionReceipt({ ...receipt, revision: 2 }, scene), null);
  assert.equal(assessConstructionReceipt({ ...receipt, runId: 'old' }, scene), null);
  assert.equal(assessConstructionReceipt({ ...receipt, type: 'ready' }, scene), null);
  assert.equal(assessConstructionReceipt({ ...receipt, objectCount: 0 }, scene).loaded, false);
  assert.equal(assessConstructionReceipt({ ...receipt, errors: ['mesh failure'] }, scene).loaded, false);
});
