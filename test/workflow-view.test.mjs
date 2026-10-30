import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';

const source = await readFile(new URL('../web/workflow-view.js', import.meta.url), 'utf8');
const { normalizeWorkflow, reduceWorkflow, workflowSummary, activeTaskCrew, createEventCursor, assessPreview, runtimeErrors, iterationView, formatElapsed, iterationRequest, reduceWritingProgress, studioTaskCards, blueprintView, activityFromEvent, mergeActivity, safeActivityImage, studioNextSteps } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));

test('writing metadata is transient, scoped and cleared by save, finish or a new run', () => {
  const event = { type: 'tool_progress', name: 'write_file', id: 'write-1', runId: 'run-1', file: 'main.gd', step: '核心玩法骨架', lines: 200, total: 210, tail: 'PRIVATE_SOURCE', code: 'PRIVATE_SOURCE' };
  const progress = reduceWritingProgress(null, event, 'run-1');
  assert.equal(progress.lines, 210);
  assert.equal(progress.step, '核心玩法骨架');
  assert.equal('code' in progress || 'tail' in progress, false);
  assert.equal(activityFromEvent(event, 'run-1'), null);
  assert.equal(reduceWritingProgress(progress, { ...event, runId: 'old' }, 'run-1'), progress);
  assert.equal(reduceWritingProgress(progress, { type: 'code_write', id: 'other' }, 'run-1'), progress);
  for (const end of [{ type: 'code_write', id: 'write-1' }, { type: 'tool_end', id: 'write-1' }, { type: 'turn_end' }, { type: 'workflow', workflow: { id: 'run-2', status: 'running' } }]) assert.equal(reduceWritingProgress(progress, end, 'run-1'), null);
  const card = studioTaskCards({ tasks: [], status: 'running' }, [], progress)[0];
  assert.equal(card.roleLabel, '主制作');
  assert.equal(card.statusLabel, '编写中 · 尚未保存');
  assert.match(card.writingLabel, /main.gd.*210 行/);
});

test('workflow task updates are scoped to their current run', () => {
  const state = normalizeWorkflow({ id: 'run-a', status: 'running', tasks: [{ id: 'a', title: '场景', status: 'running' }] });
  assert.equal(reduceWorkflow(state, { type: 'task', runId: 'old', task: { id: 'a', status: 'verified' } }), state);
  const next = reduceWorkflow(state, { type: 'task', runId: 'run-a', task: { id: 'a', status: 'applied' } });
  assert.equal(next.tasks[0].status, 'applied');
  assert.equal(next.tasks[0].title, '场景');
  assert.equal(state.tasks[0].status, 'running');
});
test('snapshot replaces stale tasks and keeps ready distinct from completed', () => {
  const next = reduceWorkflow(normalizeWorkflow({ id: 'old' }), { type: 'workflow', workflow: { id: 'new', status: 'ready', tasks: [] } });
  assert.equal(next.id, 'new');
  assert.match(workflowSummary(next).text, /等待预览/);
  assert.equal(workflowSummary(next).canRepair, false);
  assert.equal(workflowSummary({ status: 'partial' }).canRepair, true);
  assert.equal(workflowSummary({ status: 'cancelled' }).canRepair, true);
});
test('manual scene edits invalidate old acceptance without pretending a repair failed', () => {
  const issue = '关卡位置已编辑，试玩将使用新位置；完整玩法需重新验收';
  const edited = { status: 'partial', tasks: [], evidence: [], issues: [issue] };
  assert.equal(workflowSummary(edited, { sceneDirty: true }).text, '场景已修改，等待验收');
  assert.equal(workflowSummary(edited, { sceneDirty: false }).text, '场景已修改，等待验收');
  assert.equal(workflowSummary({ ...edited, issues: [], reason: issue }).text, '场景已修改，等待验收');
  assert.equal(workflowSummary({ status: 'completed' }, { sceneDirty: true }).tone, 'active');
  assert.equal(workflowSummary({ ...edited, issues: [issue, '碰撞断言失败'] }, { sceneDirty: true }).tone, 'error');
  assert.equal(workflowSummary({ ...edited, evidence: [{ kind: 'test', ok: false, sourceRevision: 'new' }] }, { sceneDirty: true, sourceRevision: 'new' }).tone, 'error');
  assert.equal(workflowSummary({ ...edited, evidence: [{ kind: 'test', ok: false, sourceRevision: 'old' }] }, { sceneDirty: true, sourceRevision: 'new' }).text, '场景已修改，等待验收');
});
test('turn end cannot complete a different run or invent a successful outcome', () => {
  const state = normalizeWorkflow({ id: 'run-a', status: 'running' });
  assert.equal(reduceWorkflow(state, { type: 'turn_end', runId: 'old', status: 'completed' }), state);
  assert.equal(reduceWorkflow(state, { type: 'turn_end', runId: 'run-a' }), state);
  assert.equal(reduceWorkflow(state, { type: 'turn_end', runId: 'run-a', status: 'partial' }).status, 'partial');
  assert.equal(reduceWorkflow(state, { type: 'turn_end', workflow: { id: 'run-a', status: 'ready' } }).status, 'ready');
});
test('scene crew shows only genuinely running tasks in two distinct existing positions', () => {
  const crew = activeTaskCrew({ tasks: [{ id: 'later', status: 'queued', role: 'gameplay' }, { id: 'rules', title: '战斗规则', status: 'running', role: 'gameplay' }, { id: 'world', title: '场景表现', status: 'running', role: 'scene' }, { id: 'finished', status: 'applied', role: 'review' }] });
  assert.deepEqual(crew.map(row => row.taskId), ['rules', 'world']);
  assert.deepEqual(crew.map(row => row.agent), ['B', 'C']);
  assert.deepEqual(crew.map(row => row.name), ['玩法制作', '场景制作']);
  assert.deepEqual(activeTaskCrew({ tasks: [{ id: 'rules', status: 'verified' }] }), []);
});
test('a future SSE event never advances across a gap', () => {
  const cursor = createEventCursor(10);
  assert.deepEqual(cursor.ingest({ seq: 13 }), []);
  assert.equal(cursor.seq, 10);
  assert.equal(cursor.gap, true);
  assert.deepEqual(cursor.ingest({ seq: 11 }).map(row => row.seq), [11]);
  assert.deepEqual(cursor.ingest({ seq: 12 }).map(row => row.seq), [12, 13]);
  assert.equal(cursor.seq, 13);
  assert.equal(cursor.gap, false);
});
test('overlapping poll replay and reconnect delivery are deduplicated', () => {
  const cursor = createEventCursor(3);
  assert.deepEqual(cursor.ingest({ seq: 5, value: 'live' }), []);
  assert.deepEqual(cursor.ingest({ seq: 4 }).map(row => row.seq), [4, 5]);
  assert.deepEqual(cursor.ingest({ seq: 5 }), []);
  assert.deepEqual(cursor.ingest({ seq: 2 }), []);
  assert.deepEqual(cursor.ingest({ seq: 6 }).map(row => row.seq), [6]);
});
test('log reset restores a snapshot boundary and preserves newer buffered events', () => {
  const cursor = createEventCursor(4);
  cursor.ingest({ seq: 21 }); cursor.ingest({ seq: 23 });
  assert.deepEqual(cursor.reset(20).map(row => row.seq), [21]);
  assert.equal(cursor.seq, 21);
  assert.deepEqual(cursor.ingest({ seq: 22 }).map(row => row.seq), [22, 23]);
});
test('an authoritative lower reset recovers a restored server instead of looping forever', () => {
  const cursor = createEventCursor(23);
  cursor.ingest({ seq: 25 });
  assert.deepEqual(cursor.reset(10), []);
  assert.equal(cursor.seq, 10);
  assert.equal(cursor.gap, false);
  assert.deepEqual(cursor.ingest({ seq: 11 }).map(row => row.seq), [11]);
});
const expected = { session: 'frame-new', buildId: 'build-new', sourceRevision: 12 };
const ready = { type: 'ready', previewSession: 'frame-new', buildId: 'build-new', sourceRevision: 12, loaded: true, errors: [] };
test('only current navigation and actual matching manifest produce success', () => {
  assert.equal(assessPreview({ ...ready, previewSession: 'frame-old' }, expected).status, 'stale');
  const result = assessPreview(ready, expected);
  assert.equal(result.status, 'verified');
  assert.deepEqual(result.receipt, { buildId: 'build-new', sourceRevision: 12, loaded: true, errors: [], kind: 'runtime_ready' });
});
test('legacy packs and mismatched versions remain explicitly unverified', () => {
  for (const ev of [{ ...ready, buildId: undefined }, { ...ready, sourceRevision: undefined }, { ...ready, sourceRevision: 11 }, { ...ready, buildId: 'old' }]) {
    const result = assessPreview(ev, expected);
    assert.equal(result.status, 'unverified'); assert.equal(result.receipt, undefined);
  }
  assert.equal(assessPreview(ready, { session: 'frame-new' }).status, 'unverified');
});
test('expected URL metadata attributes a failure but never a successful receipt', () => {
  const result = assessPreview({ type: 'js_error', previewSession: 'frame-new', expectedBuildId: 'build-new', message: 'PCK 下载失败' }, expected);
  assert.equal(result.status, 'failed');
  assert.equal(result.receipt.buildId, 'build-new');
  assert.equal(result.receipt.loaded, false);
  const spoofed = assessPreview({ type: 'ready', previewSession: 'frame-new', expectedBuildId: 'build-new', loaded: true }, expected);
  assert.equal(spoofed.status, 'unverified');
  assert.equal(spoofed.receipt, undefined);
});
test('missing scene and runtime errors cannot be reported as success', () => {
  assert.equal(assessPreview({ ...ready, loaded: false }, expected).status, 'failed');
  assert.equal(assessPreview({ ...ready, type: 'code_status', loaded: false }, expected).status, 'failed');
  const failed = assessPreview({ ...ready, type: 'code_status', errors: [{ file: 'main.gd', line: 4, message: '错误' }] }, expected);
  assert.equal(failed.status, 'failed'); assert.equal(failed.receipt.loaded, false);
  assert.match(failed.errors[0], /main.gd.*4.*错误/);
  assert.equal(assessPreview({ ...ready, errors: [{ kind: 'warning', message: '提示' }] }, expected).status, 'verified');
  assert.deepEqual(runtimeErrors(['一个错误']), ['一个错误']);
});
test('preview wrapper stamps the navigation token without fabricating a manifest', async () => {
  const html = await readFile(new URL('../web/gp.html', import.meta.url), 'utf8');
  const bridge = html.match(/<script>([\s\S]*?)<\/script>/)[1];
  const sent = [], listeners = {}, window = { addEventListener(type, fn) { listeners[type] = fn; } };
  const context = { window, parent: { postMessage(message, origin) { sent.push({ message, origin }); } }, location: { origin: 'http://10.0.4.94:5300', search: '?previewSession=frame-new&expectedBuildId=build-new' }, URLSearchParams, document: { getElementById() { return null; } }, setInterval() { return 1; }, clearInterval() {} };
  runInNewContext(bridge, context);
  window.ugcEmit(JSON.stringify({ type: 'ready', loaded: true }));
  assert.equal(sent[0].message.payload.previewSession, 'frame-new');
  assert.equal(sent[0].message.payload.buildId, undefined);
  assert.equal(sent[0].message.payload.sourceRevision, undefined);
  assert.equal(sent[0].origin, 'http://10.0.4.94:5300');
  window.ugcLoadFailure('打开失败');
  assert.equal(sent[1].message.payload.expectedBuildId, 'build-new');
  assert.equal(sent[1].message.payload.loaded, false);
  assert.equal(sent[1].message.payload.type, 'js_error');
});

test('iteration uses actual timestamps, and time never invents completed stages', () => {
  const run = { id: 'a', status: 'running', iteration: { kind: 'demo', phase: 'build', startedAt: 1000, targetMs: 480000, wrapAt: 361000, deadlineAt: 601000 } };
  assert.equal(iterationView(run, 181000).elapsedMs, 180000);
  assert.equal(iterationView(run, 181000).clockState, 'running');
  assert.equal(iterationView(run, 361000).clockState, 'wrap');
  const late = iterationView(run, 650000);
  assert.equal(late.clockState, 'overtime');
  assert.equal(late.phase, 'build');
  assert.equal(late.canChoose, false);
  assert.match(late.clockLabel, /尚未结束/);
  assert.equal('percent' in late, false);
});
test('completed, paused, and ready runs stop the elapsed clock at their actual recorded boundary', () => {
  const base = { id: 'a', startedAt: 1000, updatedAt: 121000, iteration: { phase: 'review', targetMs: 480000 } };
  assert.equal(iterationView({ ...base, status: 'completed', completedAt: 151000 }, 900000).elapsedMs, 150000);
  assert.equal(iterationView({ ...base, status: 'ready' }, 900000).elapsedMs, 120000);
  const paused = iterationView({ ...base, status: 'interrupted', iteration: { phase: 'paused' } }, 900000);
  assert.equal(paused.elapsedMs, 120000);
  assert.equal(paused.clockState, 'paused');
  assert.equal(paused.canChoose, true);
});
test('persisted iteration endedAt freezes real elapsed time even with a stale workflow update timestamp', () => {
  const run = { id: 'actual-demo', status: 'interrupted', startedAt: 1793089413385, updatedAt: 1793089413385,
    iteration: { phase: 'paused', startedAt: 1793089413346, endedAt: 1793089583650, targetMs: 480000 } };
  for (const now of [1793089600000, 1793093200000]) {
    const timing = iterationView(run, now);
    assert.equal(timing.elapsedMs, 170304);
    assert.equal(formatElapsed(timing.elapsedMs), '2:50');
    assert.equal(timing.clockState, 'paused');
  }
  const completed = { ...run, status: 'completed', completedAt: 1793090000000, iteration: { ...run.iteration, phase: 'review' } };
  assert.equal(iterationView(completed, 1793100000000).elapsedMs, 170304);
});
test('new running iteration uses its own start and never freezes at an old end value', () => {
  const next = { id: 'next-run', status: 'running', updatedAt: 1000, iteration: { phase: 'build', startedAt: 200000, endedAt: 170000, targetMs: 480000 } };
  assert.equal(iterationView(next, 202000).elapsedMs, 2000);
  assert.equal(iterationView(next, 203000).elapsedMs, 3000);
  assert.equal(iterationView(next, 203000).clockState, 'running');
});
test('legacy runs never receive an invented start or target, but retain real recorded timing', () => {
  const unknown = iterationView({ id: 'old', status: 'completed' }, 999999);
  assert.equal(unknown.elapsedMs, null);
  assert.equal(unknown.targetMs, null);
  assert.equal(unknown.hasIteration, false);
  const known = iterationView({ id: 'old', status: 'running', startedAt: 1000 }, 9000);
  assert.equal(known.elapsedMs, 8000);
  assert.equal(known.targetMs, null);
  assert.equal(formatElapsed(null), '—');
  assert.equal(formatElapsed(65000), '1:05');
  assert.equal(formatElapsed(-1), '0:00');
});
test('first send accepts only the two offered tiers', () => {
  assert.deepEqual(iterationRequest('quality'), { tier: 'quality' });
  for (const n of ['demo', undefined, null, 8, '10', 'max']) assert.deepEqual(iterationRequest(n), { tier: 'demo' });
});
test('two work cards show actual task status and do not invent a second active worker', () => {
  const one = studioTaskCards({ tasks: [{ id: 'world', role: 'scene', status: 'running', title: '搭建房间', files: ['view.gd'], changed: ['view.gd', 'maps.gd'] }] });
  assert.equal(one[0].id, 'world');
  assert.deepEqual(one[0].files, ['view.gd', 'maps.gd']);
  assert.equal(one[0].statusLabel, '正在制作');
  assert.equal(one.length, 1);
  const cards = studioTaskCards({ tasks: [{ id: 'done', status: 'verified' }, { id: 'bad', status: 'failed' }, { id: 'now', status: 'running' }] });
  assert.deepEqual(cards.map(card => card.id), ['now', 'bad']);
  assert.equal(cards[1].statusLabel, '失败');
});
test('a real coordinating tool action becomes one main work card, never two invented workers', () => {
  assert.deepEqual(studioTaskCards({ tasks: [] }), []);
  const rows = [{ id: 'tool1', at: 10, kind: 'tool', title: '正在制作游戏内容', status: 'running' }];
  const cards = studioTaskCards({ tasks: [], status: 'running', activity: rows });
  assert.equal(cards.length, 1);
  assert.equal(cards[0].roleLabel, '主制作');
  assert.equal(cards[0].title, '正在制作游戏内容');
  assert.equal(cards[0].status, 'running');
});
test('blueprint uses actual design and palette, and does not claim planned steps have run', () => {
  const empty = blueprintView({ game: { meta: { title: '未命名游戏' } } }, { goal: '一座小屋' });
  assert.equal(empty.hasDesign, false); assert.deepEqual(empty.steps, []); assert.deepEqual(empty.palette, []);
  const actual = blueprintView({ game: { design: { title: '霓虹守夜', core_loop: '撑过30秒', palette: ['#00e5ff', 'red; background:url(x)'], milestones: [{ name: '只做一张地图' }], build_steps: ['制作移动', '加入敌人'] } } }, { activity: [{ id: 'a', title: '正在写入移动' }] });
  assert.equal(actual.title, '霓虹守夜'); assert.equal(actual.description, '撑过30秒');
  assert.deepEqual(actual.palette, ['#00e5ff']); assert.equal(actual.milestone, '只做一张地图');
  assert.deepEqual(actual.steps, ['制作移动', '加入敌人']); assert.equal(actual.latest.title, '正在写入移动');
  assert.equal('completed' in actual, false);
});
test('activity attachments on any event are preferred to reconstructed descriptions', () => {
  const attached = { id: 'actual', at: 10, title: '断言检查通过', kind: 'test', image: '/covers/test.png', status: 'verified' };
  assert.deepEqual(activityFromEvent({ type: 'tool_result', seq: 8, activity: attached }, 'r'), attached);
  assert.equal(activityFromEvent({ type: 'task', runId: 'old', activity: attached }, 'r'), null);
  assert.equal(activityFromEvent({ type: 'text', delta: '现在应该好了' }, 'r'), null);
});
test('legacy raw events produce factual file/test/build activity only', () => {
  const file = activityFromEvent({ type: 'code_write', seq: 3, file: 'main.gd', step: '加入移动', t: 10 });
  assert.match(file.title, /main.gd/); assert.equal(file.status, 'applied');
  const failed = activityFromEvent({ type: 'test', seq: 4, ok: false, shot: '/covers/check.png', checks: [{ ok: false }] });
  assert.equal(failed.status, 'failed'); assert.match(failed.title, /发现问题/); assert.equal(failed.image, '/covers/check.png');
  const pack = activityFromEvent({ type: 'ops', seq: 5, ops: [{ op: 'pck', version: 2 }] });
  assert.equal(pack.status, 'applied'); assert.match(pack.detail, /2/);
});
test('snapshot activity and stream overlap merge once, with newer state and bounded storage', () => {
  const persisted = { id: 'a', at: 10, title: '开始检查', status: 'running' };
  const merged = mergeActivity({ activity: [persisted] }, [{ ...persisted, title: '检查失败', status: 'failed' }, { id: 'b', at: 20, title: '修复文件' }]);
  assert.equal(merged.length, 2); assert.equal(merged[0].title, '检查失败');
  assert.equal(mergeActivity({ activity: Array.from({ length: 100 }, (_, n) => ({ id: String(n), at: n, title: String(n) })) }).length, 40);
  assert.equal(normalizeWorkflow({ id: 'r', activity: Array.from({ length: 100 }, (_, n) => ({ id: n })) }).activity.length, 80);
});
test('old snapshot evidence remains visible without claiming a screenshot or fresh event', () => {
  const rows = mergeActivity({ evidence: [{ id: 'test1', at: 123, kind: 'test', ok: false, summary: '3项未通过' }] });
  assert.equal(rows[0].at, 123); assert.equal(rows[0].status, 'failed');
  assert.equal(rows[0].image, undefined); assert.equal(rows[0].detail, '3项未通过');
});
test('preview imagery allows local real captures and refuses active or remote URLs', () => {
  for (const value of ['/covers/a.png', 'data:image/png;base64,YQ==']) assert.equal(safeActivityImage(value), value);
  for (const value of ['javascript:alert(1)', '//example.com/a.png', '/\\example.com/a.png', 'https://example.com/a.png', 'data:image/svg+xml,<svg/>', '<img>']) assert.equal(safeActivityImage(value), '');
});
test('next step text is a choice, not an automatic new request', () => {
  assert.equal(studioNextSteps(null).length, 3);
  const steps = studioNextSteps({ iteration: { nextSteps: [{ id: 'a', title: '只调移动', prompt: '把移动速度略微调快' }] } });
  assert.deepEqual(steps, [{ id: 'a', title: '只调移动', prompt: '把移动速度略微调快' }]);
});
