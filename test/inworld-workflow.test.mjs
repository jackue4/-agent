import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const source = await readFile(new URL('../web/inworld-workflow.js', import.meta.url), 'utf8');
const { restoreInworldWorkflow, reduceInworldEvent, inworldMessages, moduleKind, moduleSnapshot } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
const workflow = { id: 'run-1', status: 'running', iteration: { phase: 'build' }, tasks: [], activity: [] };
const project = { game: { meta: { title: '小房间' }, design: { core_loop: '移动并躲避', palette: ['#ffeeaa'], build_steps: ['一个可玩房间'] } } };

test('only real running tasks create independent workers; role letters do not create workers', () => {
  let state = restoreInworldWorkflow(workflow, project);
  for (const agent of ['A', 'B', 'C']) state = reduceInworldEvent(state, { type: 'thinking', agent, text: 'PRIVATE_REASONING' }, workflow, project);
  assert.deepEqual(Object.keys(state.actors), ['M']);
  assert.doesNotMatch(JSON.stringify(state), /PRIVATE_REASONING/);
  const active = { ...workflow, tasks: [{ id: 'game', role: 'gameplay', status: 'running', title: '移动' }, { id: 'scene', role: 'scene', status: 'queued' }] };
  const next = restoreInworldWorkflow(active, project, state);
  assert.deepEqual(Object.keys(next.actors), ['M', 'task:game']);
  const stopped = restoreInworldWorkflow({ ...active, status: 'interrupted' }, project, next);
  assert.deepEqual(Object.keys(stopped.actors), ['M']);
  assert.equal(stopped.actors.M.state, 'paused');
  assert.equal(inworldMessages(next, stopped).find(m => m.agent === 'task:game').state, 'gone');
});

test('stream shows writing only; a real saved event changes state and recovery never replays completion', () => {
  const initial = restoreInworldWorkflow(workflow, project);
  const writing = reduceInworldEvent(initial, { type: 'tool_progress', name: 'write_file', step: '制作移动', file: 'main.gd', total: 210, code: 'PRIVATE_SOURCE', tail: 'PRIVATE_SOURCE' }, workflow, project);
  assert.equal(writing.actors.M.state, 'coding');
  assert.equal(writing.actors.M.lines, 210);
  assert.match(writing.actors.M.text, /尚未保存/);
  assert.equal(writing.savedFiles.length, 0);
  assert.doesNotMatch(JSON.stringify(writing), /PRIVATE_SOURCE/);
  const saved = reduceInworldEvent(writing, { type: 'code_write', file: 'main.gd' }, workflow, project);
  assert.equal(saved.actors.M.state, 'saved');
  assert.deepEqual(saved.savedFiles, ['main.gd']);
  const replay = inworldMessages(null, saved, true);
  assert.equal(replay.some(m => m.type === 'crew' && m.state === 'saved'), false);
  assert.equal(replay.find(m => m.type === 'workshop').savedFiles[0], 'main.gd');
});

test('a real same-run response start moves only the running coordinator out of saved, retaining its file context', () => {
  const project = { game: { design: { modules: [{ file: 'score.gd', role: '回声倍率' }] } } };
  const initial = restoreInworldWorkflow(workflow, project);
  const saved = reduceInworldEvent(initial, { type: 'code_write', file: 'score.gd' }, workflow, project);
  const response = { type: 'model_response', runId: workflow.id, model: 'PRIVATE_MODEL', text: 'PRIVATE_THOUGHTS' };
  const active = reduceInworldEvent(saved, response, workflow, project);
  assert.equal(active.actors.M.state, 'thinking'); assert.equal(active.actors.M.text, '整理下一步');
  assert.equal(active.actors.M.file, 'score.gd'); assert.equal(active.actors.M.module, '回声倍率');
  assert.equal(active.modules[0].state, 'saved'); assert.doesNotMatch(JSON.stringify(active), /PRIVATE_|coding/);
  for (const event of [{ ...response, runId: 'old-run' }, { ...response, runId: undefined }, { ...response, taskId: 'worker' }]) assert.equal(reduceInworldEvent(saved, event, workflow, project), saved);
  const stopped = restoreInworldWorkflow({ ...workflow, status: 'completed' }, project, saved);
  assert.equal(reduceInworldEvent(stopped, response, workflow, project), stopped);
});

test('late task and stale run events cannot resume workers or mislabel the main worker', () => {
  const initial = restoreInworldWorkflow(workflow, project);
  assert.equal(reduceInworldEvent(initial, { type: 'tool_start', name: 'write_file', taskId: 'finished-task' }, workflow, project), initial);
  assert.equal(reduceInworldEvent(initial, { type: 'tool_start', name: 'write_file', runId: 'old' }, workflow, project), initial);
  const done = restoreInworldWorkflow({ ...workflow, status: 'completed' }, project);
  assert.equal(done.actors.M.state, 'done');
  assert.equal(reduceInworldEvent(done, { type: 'tool_progress', name: 'write_file' }, workflow, project), done);
});

test('the yard idle state and plan contain actual facts without invented construction targets', () => {
  const idle = restoreInworldWorkflow(null, project);
  assert.equal(idle.actors.M.state, 'paused');
  assert.equal(idle.plan.core_loop, '移动并躲避');
  assert.equal('target' in idle.actors.M, false);
  assert.equal(idle.savedFiles.length, 0);
  assert.equal(idle.actors.M.name, '主制作');
});
test('module labels come from the actual design file mapping and change with the written file', () => {
  const planned = { game: { design: { modules: [{ file: 'scripts/player.gd', role: '移动与跳跃' }, { file: 'scripts/arena.gd', role: '关卡布局' }] } } };
  let state = restoreInworldWorkflow(workflow, planned);
  state = reduceInworldEvent(state, { type: 'tool_progress', name: 'write_file', file: 'res://scripts/player.gd', lines: 30, step: '跳跃落地' }, workflow, planned);
  assert.equal(state.actors.M.module, '移动与跳跃'); assert.equal(state.actors.M.step, '跳跃落地'); assert.equal(state.actors.M.state, 'coding');
  state = reduceInworldEvent(state, { type: 'code_write', file: 'scripts/player.gd' }, workflow, planned);
  assert.match(state.actors.M.text, /等待接入/); assert.equal(state.actors.M.state, 'saved');
  state = reduceInworldEvent(state, { type: 'tool_start', name: 'write_file', file: 'scripts/arena.gd' }, workflow, planned);
  assert.equal(state.actors.M.module, '关卡布局');
  state = reduceInworldEvent(state, { type: 'tool_start', name: 'write_file', file: 'unknown.gd' }, workflow, planned);
  assert.equal(state.actors.M.module, 'unknown.gd');
  state = reduceInworldEvent(state, { type: 'tool_start', name: 'write_file', file: 'project.godot' }, workflow, planned);
  assert.equal(state.actors.M.module, '项目设置');
});

const cardProject = { build: { buildId: 'build-2', sourceRevision: 'r2' }, game: { design: { modules: [
  { file: 'cards.gd', role: '手牌与牌面' }, { file: 'score.gd', role: '计分过程' }, { file: 'shop.gd', role: '商店购买' }, { file: 'rules.gd', role: '牌型规则' },
] } } };
test('planned module workbenches use real files and role artwork without inventing gameplay', () => {
  const state = restoreInworldWorkflow(workflow, cardProject);
  assert.equal(state.plan.modules.length, 4); assert.equal(state.modules.length, 4);
  assert.ok(state.modules.every(row => row.state === 'planned' && row.id === row.file && !row.evidenceRefs.length));
  assert.equal(moduleKind('card_view.gd'), 'deck'); assert.equal(moduleKind('main.gd', '计分和商店'), 'generic');
  assert.equal(moduleKind('echo.gd', '回声倍率模块'), 'score');
  assert.equal(moduleKind('effects.gd', '小丑定义/效果'), 'rules');
  assert.equal(moduleKind('effects.gd', '小丑效果'), 'rules');
  assert.equal(moduleKind('interaction.gd', '纸牌交互'), 'deck');
  assert.deepEqual(state.modules.map(row => row.kind), ['deck', 'score', 'shop', 'rules']);
});
test('writing is unsaved; code_write has a real revision; worker applied files are saved, never accepted alone', () => {
  const base = { ...workflow, sourceRevision: 'r1' };
  let state = restoreInworldWorkflow(base, cardProject);
  state = reduceInworldEvent(state, { type: 'tool_progress', name: 'write_file', file: 'score.gd', lines: 80 }, base, cardProject);
  assert.equal(state.modules.find(row => row.file === 'score.gd').state, 'writing');
  state = reduceInworldEvent(state, { type: 'code_write', file: 'score.gd', sourceRevision: 'r2' }, base, cardProject);
  assert.equal(state.sourceRevision, 'r2'); assert.equal(state.modules.find(row => row.file === 'score.gd').state, 'saved');
  state = reduceInworldEvent(state, { type: 'thinking' }, base, cardProject);
  assert.equal(state.sourceRevision, 'r2', 'unrelated events cannot rewind a saved source revision');
  const applied = moduleSnapshot({ ...base, tasks: [{ status: 'applied', files: ['cards.gd', 'project.godot', 'main.tscn'] }] }, cardProject);
  assert.equal(applied.modules.find(row => row.file === 'cards.gd').state, 'saved');
  assert.equal(applied.modules.some(row => ['project.godot', 'main.tscn'].includes(row.file)), false);
});
test('only whole acceptance for this exact current source and build makes modules verified', () => {
  const evidence = ['compile', 'test', 'build', 'preview', 'play'].map(kind => ({ id: kind + '-2', kind, sourceRevision: 'r2', buildId: 'build-2', ok: true, ...(kind === 'test' ? { checks: [{ what: '实际牌型断言', ok: true }] } : {}) }));
  const complete = { ...workflow, status: 'completed', sourceRevision: 'r2', tasks: [{ status: 'verified', files: ['cards.gd', 'score.gd'] }], evidence };
  const accepted = moduleSnapshot(complete, cardProject);
  assert.equal(accepted.modules[0].state, 'verified'); assert.match(accepted.modules[0].detail, /本轮当前版本整体验收通过/);
  assert.equal(accepted.modules[0].evidenceRefs.length, 5); assert.equal(accepted.modules[2].state, 'planned');
  for (const revised of [
    { ...complete, status: 'ready' }, { ...complete, sourceRevision: 'r3' },
    { ...complete, evidence: evidence.filter(row => row.kind !== 'play') },
    { ...complete, evidence: [...evidence, { ...evidence[1], id: 'failed-2', ok: false }] },
    { ...complete, evidence: evidence.map(row => row.kind === 'preview' ? { ...row, buildId: 'old-build' } : row) },
  ]) assert.equal(moduleSnapshot(revised, cardProject).modules.some(row => row.state === 'verified'), false);
  assert.equal(moduleSnapshot(complete, { ...cardProject, sceneDirty: true, sceneSourceRevision: 'r3' }).modules.some(row => row.state === 'verified'), false);
});

test('late checks of an older source cannot rewind or relabel the current saved module', () => {
  const run = { ...workflow, sourceRevision: 'r2' };
  let state = restoreInworldWorkflow(run, cardProject);
  state = reduceInworldEvent(state, { type: 'code_write', file: 'score.gd', sourceRevision: 'r2' }, run, cardProject);
  for (const event of [
    { type: 'runtime_test', phase: 'result', sourceRevision: 'r1', ok: false },
    { type: 'runtime_test', command: { sourceRevision: 'r1', kind: 'test' } },
    { type: 'compile', sourceRevision: 'r1', ok: true },
  ]) {
    assert.equal(reduceInworldEvent(state, event, run, cardProject), state);
    const direct = moduleSnapshot(run, cardProject, state, event);
    assert.equal(direct.sourceRevision, 'r2'); assert.equal(direct.modules.find(row => row.file === 'score.gd').state, 'saved');
  }
});
test('recovery restores factual module state without celebrating saves or creating support-file benches', () => {
  const recovered = restoreInworldWorkflow({ ...workflow, status: 'interrupted', sourceRevision: 'r2', activity: [
    { kind: 'code_write', file: 'cards.gd', sourceRevision: 'r2' }, { kind: 'code_write', file: 'project.godot' },
    { kind: 'code_write', file: 'README.md' }, { kind: 'code_write', file: 'tests/auto_test.gd' },
  ] }, cardProject);
  const snapshot = inworldMessages(null, recovered, true).find(row => row.type === 'workshop');
  assert.equal(snapshot.restore, true); assert.equal(snapshot.modules.length, 4);
  assert.equal(snapshot.modules[0].state, 'saved'); assert.equal(snapshot.modules[0].sourceRevision, 'r2');
  const legacy = restoreInworldWorkflow(null, { game: { code: { files: { 'main.gd': 'SOURCE', 'MODULE.md': 'DOC', 'project.godot': 'CONFIG', 'addons/ugc/ugc.gd': 'BRIDGE' } } } });
  assert.deepEqual(legacy.modules.map(row => row.file), ['main.gd']); assert.doesNotMatch(JSON.stringify(legacy), /SOURCE|CONFIG|BRIDGE/);
});

test('cold replay establishes module stage and phase before restoring real workers', () => {
  const run = { ...workflow, tasks: [{ id: 'score', role: 'gameplay', status: 'running', files: ['score.gd'], title: '制作计分' }] };
  const state = restoreInworldWorkflow(run, cardProject), replay = inworldMessages(null, state, true);
  assert.deepEqual(replay.slice(0, 2).map(row => row.type), ['crew_clear', 'workshop']);
  // Model the actual cold Godot boundary: first module creation clears the prior
  // overlay, and a paused workshop clamps active incoming workers to paused.
  const apply = (events, stage = { ready: false, phase: 'paused', actors: {} }) => {
    for (const event of events) {
      if (event.type === 'crew_clear') stage.actors = {};
      if (event.type === 'workshop') {
        if (!stage.ready && event.plan.modules.length) { stage.ready = true; stage.actors = {}; }
        stage.phase = event.phase;
      }
      if (event.type === 'crew') stage.actors[event.agent] = stage.phase === 'paused' ? 'paused' : event.state;
    }
    return stage;
  };
  const cold = apply(replay);
  assert.equal(cold.actors.M, 'building'); assert.equal(cold.actors['task:score'], 'coding');
  const unplanned = { ...state, plan: { ...state.plan, modules: [] } };
  const planArrival = inworldMessages(unplanned, state);
  assert.equal(planArrival[0].type, 'workshop'); assert.equal(planArrival.filter(row => row.type === 'crew').length, 2);
  assert.equal(apply(planArrival).actors['task:score'], 'coding');
  const resume = inworldMessages({ ...state, phase: 'paused' }, state);
  assert.equal(resume[0].type, 'workshop'); assert.equal(apply(resume, { ready: true, phase: 'paused', actors: {} }).actors['task:score'], 'coding');
  const saved = { ...state, actors: { M: { ...state.actors.M, state: 'saved' } } };
  assert.equal(inworldMessages({ ...saved, plan: unplanned.plan }, saved).find(row => row.type === 'crew').state, 'paused', 'resending an unchanged save must not replay a save celebration');
});

test('completed native iteration restores reused modules from a real revision-bound source inventory', async () => {
  const fixture = JSON.parse(await readFile(new URL('./fixtures/module-workshop-completed.json', import.meta.url), 'utf8'));
  const { project, actualFiles } = fixture, run = project.workflow;
  const withoutInventory = restoreInworldWorkflow(run, project);
  assert.deepEqual(withoutInventory.modules.filter(row => row.state === 'verified').map(row => row.file), ['main.gd']);
  const sourceManifest = { sourceRevision: run.sourceRevision, files: actualFiles };
  for (const [snapshot, currentRun] of [[{ ...project, sourceManifest }, run], [project, { ...run, sourceManifest }]]) {
    const state = restoreInworldWorkflow(currentRun, snapshot);
    assert.equal(state.modules.length, 6); assert.ok(state.modules.every(row => row.state === 'verified'));
    assert.ok(state.modules.every(row => row.sourceRevision === sourceManifest.sourceRevision && row.evidenceRefs.length === 5));
  }
  const stale = restoreInworldWorkflow(run, { ...project, sourceManifest: { ...sourceManifest, sourceRevision: run.baseRevision } });
  assert.deepEqual(stale.modules.filter(row => row.state === 'verified').map(row => row.file), ['main.gd']);
  const future = { ...project, sourceManifest, game: { ...project.game, design: { modules: [...project.game.design.modules, { file: 'future.gd', role: '尚未制作的下一步' }] } } };
  assert.equal(restoreInworldWorkflow(run, future).modules.find(row => row.file === 'future.gd').state, 'planned');
  for (const revision of [run.baseRevision, 'newer-unchecked-source']) {
    const changed = restoreInworldWorkflow({ ...run, sourceRevision: revision }, { ...project, sourceManifest: { ...sourceManifest, sourceRevision: revision } });
    assert.equal(changed.modules.some(row => row.state === 'verified'), false);
  }
});
