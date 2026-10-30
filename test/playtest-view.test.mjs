import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const source = await readFile(new URL('../web/playtest-view.js', import.meta.url), 'utf8');
const { emptyPlaytest, reducePlaytest, normalizePlaytest, playtestPresentation, returnsToMaking } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
const snapshot = { sessionId: 'a', runId: 'run', sourceRevision: 'r1', kind: 'eval', step: '移动', status: 'live', frameSeq: 1, frameUrl: '/api/projects/p/watch/frame?session=a&seq=1', capturedAt: 1000, updatedAt: 1000 };
test('watch rejects old run, retired session and backward frames without reviving ended work', () => {
  const initial = reducePlaytest(emptyPlaytest('run'), snapshot, 'run');
  assert.equal(reducePlaytest(initial, { ...snapshot, runId: 'other' }, 'run'), initial);
  assert.equal(reducePlaytest(initial, { ...snapshot, frameSeq: 0 }, 'run'), initial);
  const next = reducePlaytest(initial, { ...snapshot, sessionId: 'b', status: 'starting', frameSeq: 0, frameUrl: '', updatedAt: 2000 }, 'run');
  assert.equal(next.watch.frameUrl, '');
  assert.equal(reducePlaytest(next, { ...snapshot, frameSeq: 99, updatedAt: 9999 }, 'run'), next);
  const end = reducePlaytest(initial, { ...snapshot, status: 'stopped', updatedAt: 2000 }, 'run');
  assert.equal(reducePlaytest(end, { ...snapshot, updatedAt: 3000 }, 'run'), end);
});
test('stale or missing frames are explicit and completion labels remain scoped to their kind', () => {
  assert.equal(playtestPresentation(snapshot, 5001).stale, true);
  assert.equal(playtestPresentation(snapshot, 5001).status, '画面未更新');
  assert.match(playtestPresentation({ ...snapshot, status: 'starting', frameSeq: 0, frameUrl: '' }, 6000).note, /等待首帧/);
  for (const [kind, label] of Object.entries({ run: '启动完成', eval: '本步操作完成', test: '本次断言检查通过' })) {
    const view = playtestPresentation({ ...snapshot, kind, status: 'passed' }, 9999);
    assert.equal(view.status, label);
    assert.match(view.note, /最后一帧/);
  }
  assert.equal(normalizePlaytest({ ...snapshot, frameUrl: 'https://other.example/image.jpg' }).frameUrl, '');
});
test('only real edit and scene events automatically return to making', () => {
  assert.equal(returnsToMaking({ type: 'tool_start', name: 'patch_file' }), true);
  assert.equal(returnsToMaking({ type: 'construction' }), true);
  assert.equal(returnsToMaking({ type: 'tool_start', name: 'build_scene' }), true);
  assert.equal(returnsToMaking({ type: 'tool_progress', name: 'write_file' }), false);
  assert.equal(returnsToMaking({ type: 'thinking' }), false);
});
