import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';

const source = await readFile(new URL('../web/inworld-workflow.js', import.meta.url), 'utf8');
const { restoreInworldWorkflow: restore, reduceInworldEvent: reduce, inworldMessages: messages } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
const project = { game: { meta: { title: '隔离合同夹具', dimension: '2d' }, design: {} } };
const workflow = (extra = {}) => ({ id: 'run-current', status: 'running', tasks: [], activity: [], iteration: { phase: 'build' }, ...extra });
const task = (id, status = 'running', role = 'gameplay') => ({ id, status, role, title: '制作真实任务', files: [`${id}.gd`] });

test('one coordinator does not fabricate a parallel crew from role names or legacy agent tags', () => {
  const w = workflow(), initial = restore(w, project);
  assert.deepEqual(Object.keys(initial.actors), ['M']);
  for (const agent of ['A', 'B', 'C']) {
    const next = reduce(initial, { type: 'tool_progress', name: 'write_file', agent, lines: 5 }, w, project);
    assert.deepEqual(Object.keys(next.actors), ['M']);
  }
});

test('only actual running tasks become parallel workers; terminal and queued tasks do not', () => {
  const w = workflow({ tasks: [task('view', 'running', 'scene'), task('sim'), task('review', 'queued'), task('old', 'applied'), task('bad', 'failed')] });
  const state = restore(w, project);
  assert.deepEqual(Object.keys(state.actors), ['M', 'task:view', 'task:sim']);
  assert.equal(state.actors['task:view'].taskId, 'view');
  assert.equal(state.actors['task:view'].file, 'view.gd');
  assert.equal(state.actors['task:sim'].taskId, 'sim');
});

test('work is attributed to the actual task, and ended or unknown task events cannot impersonate the coordinator', () => {
  const w = workflow({ tasks: [task('sim')] }), initial = restore(w, project);
  const next = reduce(initial, { type: 'tool_progress', name: 'write_file', taskId: 'sim', file: 'sim.gd', lines: 10 }, w, project);
  assert.equal(next.actors['task:sim'].state, 'coding');
  assert.equal(next.actors.M, initial.actors.M);
  for (const taskId of ['unknown', 'ended']) assert.equal(reduce(next, { type: 'tool_progress', name: 'write_file', taskId }, w, project), next);
});

test('streamed code and private reasoning are omitted, metadata is bounded, and partial text is not a saved file', () => {
  const w = workflow(), initial = restore(w, project);
  const next = reduce(initial, { type: 'tool_progress', name: 'write_file', file: 'x'.repeat(400), step: '步骤'.repeat(30), total: 42.8,
    code: 'PRIVATE_SOURCE', tail: 'PRIVATE_SOURCE', thinking: 'PRIVATE_REASONING', text: 'PRIVATE_REASONING', arguments: { secret: 'PRIVATE_SOURCE' } }, w, project);
  assert.equal(next.actors.M.lines, 42);
  assert.equal(Array.from(next.actors.M.file).length, 240);
  assert.equal(Array.from(next.actors.M.step).length, 12);
  assert.equal(next.actors.M.state, 'coding');
  assert.match(next.actors.M.text, /尚未保存/);
  assert.deepEqual(next.savedFiles, []);
  assert.doesNotMatch(JSON.stringify(messages(initial, next)), /PRIVATE_|arguments|thinking/);
});

test('a saved file is deduplicated and does not create a game object, successful test, or ready receipt', () => {
  const w = workflow(), event = { type: 'code_write', file: 'main.gd', objects: ['InventedEnemy'] };
  let state = restore(w, project);
  state = reduce(state, event, w, project);
  state = reduce(state, event, w, project);
  assert.deepEqual(state.savedFiles, ['main.gd']);
  assert.equal(state.actors.M.state, 'saved');
  assert.match(state.actors.M.text, /已保存 · 等待接入/);
  assert.doesNotMatch(JSON.stringify(messages(null, state, true)), /InventedEnemy|preview_receipt|game_over|"loaded"|"type":"ready"/);
});

test('save history is bounded and only derives from actual saved events', () => {
  const w = workflow(); let state = restore(w, project);
  for (let i = 0; i < 70; i++) state = reduce(state, { type: 'code_write', file: `part-${i}.gd` }, w, project);
  assert.equal(state.savedFiles.length, 60);
  assert.equal(state.savedFiles[0], 'part-10.gd');
  assert.equal(state.savedFiles.at(-1), 'part-69.gd');
  const recovered = restore(workflow({ activity: [{ kind: 'code_write', file: 'real.gd' }, { kind: 'tool_progress', file: 'unsaved.gd' }] }), project);
  assert.deepEqual(recovered.savedFiles, ['real.gd']);
});

test('failed checks stay visibly repairing; starting or passing one check does not claim the whole game finished', () => {
  const w = workflow(), initial = restore(w, project);
  const failed = reduce(initial, { type: 'compile', ok: false }, w, project);
  assert.equal(failed.actors.M.state, 'fixing');
  assert.match(failed.actors.M.text, /发现问题/);
  const passed = reduce(failed, { type: 'test', ok: true }, w, project);
  assert.equal(passed.status, 'running');
  assert.equal(passed.actors.M.state, 'testing');
  assert.match(passed.actors.M.text, /本项检查通过/);
});

test('unit self-test is not described as actual input gameplay', () => {
  const w = workflow(), initial = restore(w, project);
  const unit = reduce(initial, { type: 'tool_start', name: 'run_test' }, w, project);
  assert.equal(unit.actors.M.state, 'testing');
  assert.doesNotMatch(unit.actors.M.text, /实际试玩/);
  for (const name of ['run_game', 'game_eval']) {
    assert.match(reduce(initial, { type: 'tool_start', name }, w, project).actors.M.text, /试玩/);
  }
});

test('terminal snapshots stop work and cannot be restarted by late progress or file events', () => {
  for (const status of ['ready', 'completed', 'partial', 'interrupted', 'cancelled', 'failed']) {
    const w = workflow({ status, tasks: [task('late')] }), stopped = restore(w, project);
    assert.deepEqual(Object.keys(stopped.actors), ['M']);
    assert.ok(['paused', 'done'].includes(stopped.actors.M.state));
    for (const event of [{ type: 'tool_progress', name: 'write_file' }, { type: 'code_write', file: 'late.gd' }, { type: 'thinking' }]) {
      assert.equal(reduce(stopped, event, w, project), stopped);
    }
  }
});

test('old run events do not mutate a current run or expose its old files', () => {
  const w = workflow(), current = restore(w, project);
  for (const type of ['thinking', 'code_write', 'task', 'turn_end']) {
    assert.equal(reduce(current, { type, runId: 'run-old', file: 'old.gd' }, w, project), current);
  }
});

test('authoritative new-run recovery clears old identities and stale file history', () => {
  const old = restore(workflow({ tasks: [task('old')], activity: [{ kind: 'code_write', file: 'old.gd' }] }), project);
  const next = restore(workflow({ id: 'run-next', tasks: [task('next')] }), project, old);
  assert.equal(next.runId, 'run-next');
  assert.deepEqual(Object.keys(next.actors), ['M', 'task:next']);
  assert.deepEqual(next.savedFiles, []);
  assert.ok(messages(old, next).some(row => row.agent === 'task:old' && row.state === 'gone'));
});

test('task completion removes its avatar; a repeated identical snapshot does not replay work', () => {
  const w = workflow({ tasks: [task('sim')] }), initial = restore(w, project);
  const next = restore({ ...w, tasks: [task('sim', 'applied')] }, project, initial);
  assert.ok(messages(initial, next).some(row => row.agent === 'task:sim' && row.state === 'gone'));
  assert.deepEqual(messages(next, restore({ ...w, tasks: [] }, project, next)), []);
});

test('reconnect replaces crew and restores file props without replaying saved-work animations', () => {
  const w = workflow();
  const state = reduce(restore(w, project), { type: 'code_write', file: 'main.gd' }, w, project);
  const replay = messages(null, state, true);
  assert.deepEqual(replay[0], { type: 'crew_clear' });
  assert.equal(replay.find(row => row.type === 'crew').state, 'paused');
  assert.deepEqual(replay.find(row => row.type === 'workshop').savedFiles, ['main.gd']);
  assert.equal(replay.some(row => row.state === 'saved'), false);
});

test('2D and 3D project dimensions produce the same safe creative-layer messages without game coordinates', () => {
  const w = workflow({ tasks: [task('scene', 'running', 'scene')] });
  const two = restore(w, project), three = restore(w, { game: { ...project.game, meta: { ...project.game.meta, dimension: '3d' } } });
  assert.deepEqual(messages(null, two, true), messages(null, three, true));
  assert.equal(messages(null, three, true).some(row => 'position' in row || 'target' in row), false);
});

test('accepted-plan snapshot is a bounded public description, not source code or a synthetic entity list', () => {
  const plan = { title: '图'.repeat(150), core_loop: '玩'.repeat(400), build_steps: Array.from({ length: 15 }, () => '阶段'.repeat(90)), palette: ['red', '#12abef', 'url(secret)'], code: 'PRIVATE_CODE', entities: ['FakeEnemy'] };
  const state = restore(workflow(), { game: { design: plan } });
  assert.equal(Array.from(state.plan.title).length, 120);
  assert.equal(Array.from(state.plan.core_loop).length, 240);
  assert.equal(state.plan.steps.length, 6);
  assert.deepEqual(state.plan.palette, ['#12abef']);
  assert.doesNotMatch(JSON.stringify(state.plan), /PRIVATE_CODE|FakeEnemy|url\(/);
});

test('iframe bridge preserves actual manifest identity and navigation token instead of inventing build evidence', async () => {
  const html = await readFile(new URL('../web/gp.html', import.meta.url), 'utf8');
  const script = html.match(/<script>\s*([\s\S]*?)<\/script>/)[1], posts = [];
  const context = { location: { search: '?previewSession=current-nav&expectedBuildId=expected-query', origin: 'http://fixture.invalid' }, URLSearchParams,
    parent: { postMessage: (value, origin) => posts.push({ value, origin }) }, document: { getElementById: () => null }, setInterval: () => 1, clearInterval() {}, window: { addEventListener() {} } };
  runInNewContext(script, context);
  context.window.ugcEmit(JSON.stringify({ type: 'ready', buildId: 'actual-pack', sourceRevision: 'actual-revision', loaded: true }));
  assert.equal(posts[0].value.payload.buildId, 'actual-pack');
  assert.equal(posts[0].value.payload.sourceRevision, 'actual-revision');
  assert.equal(posts[0].value.payload.previewSession, 'current-nav');
  assert.equal(posts[0].origin, 'http://fixture.invalid');
  context.window.ugcEmit(JSON.stringify({ type: 'workshop_ready', surface: 'workshop' }));
  const workshop = posts[1].value.payload;
  assert.equal(workshop.type, 'workshop_ready');
  assert.equal(workshop.surface, 'workshop');
  assert.equal('buildId' in workshop, false);
  assert.equal('sourceRevision' in workshop, false);
  assert.equal('loaded' in workshop, false);
});
