// The scene receives public work facts, never generated source or reasoning text.
const text = (value, size = 120) => typeof value === 'string' ? Array.from(value).slice(0, size).join('') : '';
const states = new Set(['thinking', 'coding', 'building', 'testing', 'fixing', 'saved', 'done', 'paused', 'gone']);
const terminal = new Set(['ready', 'completed', 'partial', 'interrupted', 'cancelled', 'failed']);
const phaseState = phase => ({ scope: 'thinking', build: 'building', verify: 'testing', review: 'paused', paused: 'paused' })[phase] || 'thinking';
const mainActor = (state, extra = {}) => ({ type: 'crew', agent: 'M', name: '主制作', color: '#8fdcf5', state, ...extra });
const normalizedFile = file => text(file, 240).replace(/^res:\/\//, '').replaceAll('\\', '/');
const modulePath = file => { const value = normalizedFile(file); return value && !value.startsWith('/') && !value.includes(':') && !value.split('/').includes('..') ? value : ''; };
const functionalModule = file => /\.gd$/i.test(file) && !/(^|\/)(addons|tests?)\/|(^|\/)(auto_test|test_[^/]*)\.gd$/i.test(file);
export function moduleKind(file, role = '') {
  const name = normalizedFile(file).split('/').at(-1).toLowerCase();
  for (const [kind, pattern] of [['deck', /^(card|deck|hand)(_|\.)/], ['score', /^(score|scoring)(_|\.)/], ['shop', /^(shop|store)(_|\.)/], ['rules', /^(rules|poker_eval|jokers)(_|\.)/], ['world', /^(world|level|arena|map)(_|\.)/]]) if (pattern.test(name)) return kind;
  const matches = [['deck', /牌面|牌堆|手牌|抽牌|发牌|纸牌交互/], ['score', /计分|得分|分数|倍率/], ['shop', /商店|买卖|交易/], ['rules', /规则|判定|效果结算|小丑(?:定义|效果|定义\/效果)/], ['world', /关卡|地形|地图|场景/]].filter(([, pattern]) => pattern.test(role));
  return matches.length === 1 ? matches[0][0] : 'generic';
}
export function plannedModules(project) {
  const rows = new Map();
  for (const row of Array.isArray(project?.game?.design?.modules) ? project.game.design.modules : []) {
    const file = modulePath(row.file); if (!file || rows.has(file)) continue;
    rows.set(file, { id: file, file, label: moduleForFile(project, file), kind: moduleKind(file, text(row.role, 240)), state: 'planned', detail: '已列入制作计划', sourceRevision: '', evidenceRefs: [] });
  }
  return [...rows.values()].slice(0, 60);
}
function currentModuleRevision(workflow, project, previous, event) {
  const savedRevision = workflow?.activity?.findLast(row => row.sourceRevision)?.sourceRevision;
  return text((event?.type === 'code_write' && event.sourceRevision) || (project?.sceneDirty ? project.sceneSourceRevision : '') || (event && previous?.sourceRevision) || workflow?.sourceRevision || savedRevision || previous?.sourceRevision || project?.build?.sourceRevision || workflow?.baseRevision || event?.sourceRevision, 100);
}
function overallModuleAcceptance(workflow, project, revision) {
  if (workflow?.status !== 'completed' || !revision || workflow.sourceRevision !== revision || project?.sceneDirty || workflow.issues?.length) return [];
  const evidence = (workflow.evidence || []).filter(row => row.sourceRevision === revision), latest = kind => evidence.findLast(row => row.kind === kind);
  const kinds = ['compile', 'test', 'build', 'preview', ...(workflow.iteration ? ['play'] : [])], rows = kinds.map(latest);
  if (rows.some(row => !row?.ok) || !latest('test').checks?.length || latest('test').checks.some(row => row.ok !== true)) return [];
  if (!latest('build').buildId || latest('build').buildId !== latest('preview').buildId || project?.build?.buildId && latest('build').buildId !== project.build.buildId || project?.build?.sourceRevision && project.build.sourceRevision !== revision) return [];
  if ((workflow.tasks || []).some(task => !['applied', 'verified'].includes(task.status))) return [];
  return rows.map(row => row.id).filter(Boolean);
}
export function moduleSnapshot(workflow, project, previous = null, event = null) {
  const revision = currentModuleRevision(workflow, project, previous, event), rows = new Map(plannedModules(project).map(row => [row.file, row]));
  // Native projects keep source outside game.code. A revision-bound inventory
  // proves reused files exist even when this round only changed the entry point.
  const manifestedFiles = [workflow?.sourceManifest, project?.sourceManifest]
    .filter(manifest => revision && manifest?.sourceRevision === revision && Array.isArray(manifest.files)).flatMap(manifest => manifest.files);
  const actualFiles = new Set([...manifestedFiles, ...(previous?.savedFiles || []), ...Object.keys(project?.game?.code?.files || {}),
    ...(workflow?.activity || []).filter(row => row.file && (row.kind === 'code_write' || row.status === 'saved')).map(row => row.file),
    ...(workflow?.tasks || []).filter(task => ['applied', 'verified'].includes(task.status)).flatMap(task => task.changed?.length ? task.changed : task.files || [])].map(modulePath).filter(Boolean));
  for (const file of actualFiles) if (!rows.has(file) && functionalModule(file)) rows.set(file, { id: file, file, label: moduleForFile(project, file), kind: moduleKind(file), state: 'planned', detail: '实际工程文件', sourceRevision: revision, evidenceRefs: [] });
  const file = modulePath(event?.file || event?.args?.file || event?.args?.path);
  if (file && !rows.has(file) && functionalModule(file)) rows.set(file, { id: file, file, label: moduleForFile(project, file), kind: moduleKind(file), state: 'planned', detail: '正在处理工程文件', sourceRevision: revision, evidenceRefs: [] });
  const oldRows = new Map((previous?.modules || []).map(row => [row.file, row]));
  const accepted = overallModuleAcceptance(workflow, project, revision);
  const currentEvidence = (workflow?.evidence || []).filter(row => row.sourceRevision === revision);
  const latestByKind = new Map(currentEvidence.map(row => [row.kind, row]));
  const failed = [...latestByKind.values()].filter(row => row.ok === false);
  const checkedRevision = event?.sourceRevision || event?.command?.sourceRevision;
  const currentCheck = !checkedRevision || !revision || checkedRevision === revision;
  const globalChecking = currentCheck && (event?.type === 'runtime_test' && event.command?.kind !== 'stop' && event.phase !== 'result'
    || ['tool_start', 'tool_progress'].includes(event?.type) && ['compile', 'preview_checkpoint', 'run_test', 'run_game', 'game_eval', 'export_game'].includes(event.name));
  const stopped = workflow && workflow.status !== 'running' && workflow.status !== 'completed';
  for (const row of rows.values()) {
    const old = oldRows.get(row.file), task = (workflow?.tasks || []).find(item => (item.files || []).includes(row.file) || (item.changed || []).includes(row.file));
    row.sourceRevision = revision;
    if (actualFiles.has(row.file)) { row.state = 'saved'; row.detail = '已保存 · 等待接入和验收'; }
    if (old?.sourceRevision === revision && ['writing', 'checking', 'failed'].includes(old.state)) { row.state = old.state; row.detail = old.detail; }
    if (task?.status === 'running' && row.state === 'planned') { row.state = 'writing'; row.detail = '任务正在制作此模块'; }
    if (task && ['failed', 'blocked'].includes(task.status)) { row.state = 'failed'; row.detail = text(task.error || '模块任务未完成', 100); }
    if (globalChecking && actualFiles.has(row.file)) { row.state = 'checking'; row.detail = '当前版本整体验收中'; }
    if (currentCheck && (event?.type === 'runtime_test' && event.phase === 'result' || ['compile', 'test', 'eval'].includes(event?.type))) {
      if (actualFiles.has(row.file)) { row.state = event.ok === false ? 'failed' : 'saved'; row.detail = event.ok === false ? '本项检查未通过，等待修复' : '本项检查已返回，等待整体验收'; }
    }
    if (row.file === file && event?.type === 'code_write') { row.state = 'saved'; row.detail = '已保存 · 等待接入和验收'; }
    else if (row.file === file && ['tool_start', 'tool_progress'].includes(event?.type) && /^(write|patch)_(file|module)$/.test(event.name)) { row.state = 'writing'; row.detail = text(event.step || '编写中 · 尚未保存', 100); }
    if (failed.length && row.state !== 'writing' && actualFiles.has(row.file)) { row.state = 'failed'; row.detail = '当前版本检查未通过，等待修复'; row.evidenceRefs = failed.map(item => item.id).filter(Boolean); }
    if (stopped && ['writing', 'checking'].includes(row.state)) { row.state = 'paused'; row.detail = actualFiles.has(row.file) ? '工作已暂停 · 已保存内容保留' : '工作已暂停 · 尚未确认保存'; }
    if (accepted.length && actualFiles.has(row.file)) { row.state = 'verified'; row.detail = '本轮当前版本整体验收通过'; row.evidenceRefs = accepted; }
  }
  return { modules: [...rows.values()].slice(0, 60), sourceRevision: revision };
}
export function moduleForFile(project, file) {
  const normalized = normalizedFile(file), modules = project?.game?.design?.modules;
  const match = (Array.isArray(modules) ? modules : []).find(row => normalizedFile(row.file) === normalized);
  return match?.role ? text(match.role, 28) : normalized === 'project.godot' ? '项目设置' : text(normalized.split('/').at(-1), 28);
}
function planOf(project) {
  const d = project?.game?.design || {}, milestones = Array.isArray(d.milestones) ? d.milestones : [];
  const milestone = milestones[Math.max(0, Number(d.current) || 0)] || milestones[0];
  return { title: text(d.title || project?.game?.meta?.title), core_loop: text(d.core_loop || d.pitch, 240),
    palette: (Array.isArray(d.palette) ? d.palette : []).filter(v => typeof v === 'string' && /^#[0-9a-f]{3,8}$/i.test(v)).slice(0, 6),
    milestone: text(typeof milestone === 'string' ? milestone : milestone?.name || milestone?.title || milestone?.goal),
    steps: (Array.isArray(d.build_steps) ? d.build_steps : []).filter(v => typeof v === 'string').slice(0, 6).map(v => text(v)), modules: plannedModules(project) };
}
export function restoreInworldWorkflow(workflow, project, previous = null) {
  const phase = workflow?.iteration?.phase || (workflow?.status === 'ready' || workflow?.status === 'completed' ? 'review' : 'scope');
  const status = workflow?.status || 'idle', active = status === 'running', sameRun = workflow?.id && workflow.id === previous?.runId;
  const main = active ? sameRun && previous.status === 'running' && previous.phase === phase ? previous.actors.M : mainActor(phaseState(phase), { text: '根据实际制作阶段恢复' })
    : mainActor(status === 'completed' ? 'done' : 'paused', { text: status === 'ready' ? '等待你试玩' : status === 'completed' ? '本轮已完成' : '等待下一步' });
  const actors = { M: main };
  if (active) for (const task of workflow?.tasks || []) if (task.status === 'running' && task.id) {
    const agent = 'task:' + task.id;
    actors[agent] = sameRun && previous?.actors[agent] || { type: 'crew', agent, taskId: task.id,
      name: task.role === 'scene' ? '场景制作' : task.role === 'review' ? '内容检查' : '玩法制作',
      color: task.role === 'scene' ? '#83ddbc' : '#c4b0ff', state: task.role === 'review' ? 'testing' : task.role === 'scene' ? 'building' : 'coding',
      step: text(task.title, 12), text: '任务正在执行', file: text(task.files?.[0], 240), module: moduleForFile(project, task.files?.[0]) };
  }
  const savedFiles = [...new Set([...(sameRun ? previous.savedFiles : []), ...(workflow?.activity || []).filter(row => row.file && (row.kind === 'code_write' || row.status === 'saved')).map(row => text(row.file, 240)),
    ...(workflow?.tasks || []).filter(task => ['applied', 'verified'].includes(task.status)).flatMap(task => task.changed?.length ? task.changed : task.files || [])].map(modulePath).filter(Boolean))].slice(-60);
  return { runId: workflow?.id || '', status, phase, actors, savedFiles, plan: planOf(project), ...moduleSnapshot(workflow, project, { ...(sameRun ? previous : {}), savedFiles }) };
}
export function reduceInworldEvent(current, event, workflow, project) {
  let state = current || restoreInworldWorkflow(workflow, project);
  if (event.runId && state.runId && event.runId !== state.runId) return state;
  if (['workflow', 'task', 'turn_end', 'design', 'roadmap', 'plan'].includes(event.type)) return restoreInworldWorkflow(workflow, project, state);
  if (event.type === 'turn_start') return { ...restoreInworldWorkflow(workflow, project), status: 'running', actors: { M: mainActor('thinking', { text: '确定本轮范围' }) } };
  if (terminal.has(state.status) || state.status !== 'running') return state;
  if (event.taskId && !state.actors['task:' + event.taskId]) return state;
  if (event.type === 'model_response' && (event.taskId || event.runId !== state.runId)) return state;
  const checkedRevision = event.sourceRevision || event.command?.sourceRevision;
  if (['runtime_test', 'compile', 'test', 'eval'].includes(event.type) && checkedRevision && state.sourceRevision && checkedRevision !== state.sourceRevision) return state;
  const agent = event.taskId && state.actors['task:' + event.taskId] ? 'task:' + event.taskId : 'M';
  const previous = state.actors[agent] || mainActor('thinking');
  let nextState = '', label = '', metadata = {};
  if (event.type === 'thinking' || event.type === 'model_response') { nextState = 'thinking'; label = '整理下一步'; }
  else if (event.type === 'tool_start' || event.type === 'tool_progress') {
    if (/^(write|patch)_(module|file)$/.test(event.name)) { nextState = 'coding'; label = '编写中 · 尚未保存'; }
    else if (['run_test', 'run_game', 'game_eval'].includes(event.name)) { nextState = 'testing'; label = event.name === 'run_test' ? '检查玩法规则' : '实际试玩检查'; }
    else if (['compile', 'preview_checkpoint', 'export_game', 'build_game'].includes(event.name)) { nextState = 'building'; label = '接入并检查模块'; }
    else if (['generate_asset', 'build_scene', 'apply_scene_ops', 'update_construction'].includes(event.name)) { nextState = 'building'; label = '搭建场景内容'; }
    else if (['design_game', 'web_fetch', 'read_file', 'list_files'].includes(event.name)) { nextState = 'thinking'; label = '查看与规划'; }
    else return state;
    const count = Number.isFinite(event.total) ? event.total : event.lines;
    const file = text(event.file || event.args?.file || event.args?.path || previous.file, 240);
    metadata = { file, module: moduleForFile(project, file), step: text(event.step, 12), lines: Number.isFinite(count) ? Math.max(0, Math.floor(count)) : 0 };
  } else if (event.type === 'code_write') {
    nextState = 'saved'; label = '已保存 · 等待接入'; metadata = { file: text(event.file, 240), module: moduleForFile(project, event.file), step: text(event.step, 12) };
    state = { ...state, savedFiles: [...new Set([...state.savedFiles, metadata.file].filter(Boolean))].slice(-60) };
  } else if (event.type === 'runtime_test') {
    const kind = event.command?.kind || event.kind;
    nextState = kind === 'stop' ? 'paused' : event.phase === 'result' && event.ok === false ? 'fixing' : 'testing';
    label = kind === 'stop' ? '等待下一步' : event.phase === 'result' ? event.ok ? '本项检查通过' : '本项检查未通过' : kind === 'test' ? '检查玩法规则' : '实际游戏验收';
  } else if (['compile', 'test', 'eval'].includes(event.type)) {
    nextState = event.ok === false ? 'fixing' : 'testing'; label = event.ok === false ? '发现问题，修复中' : event.ok === true ? '本项检查通过' : '等待检查结果';
  } else if (event.type === 'error') { nextState = 'paused'; label = '遇到问题，等待处理'; }
  else if (event.type === 'ops' && event.ops?.some(op => op.op === 'pck')) { nextState = 'saved'; label = '试玩包已生成'; }
  else return state;
  if (!states.has(nextState)) return state;
  return { ...state, actors: { ...state.actors, [agent]: { ...previous, state: nextState, text: label, ...metadata } }, ...moduleSnapshot(workflow, project, state, event) };
}
export function inworldMessages(previous, next, force = false) {
  if (!next) return [];
  const messages = [];
  const planChanged = JSON.stringify(next.plan) !== JSON.stringify(previous?.plan);
  const stageChanged = force || planChanged || next.phase !== previous?.phase;
  if (force) messages.push({ type: 'crew_clear' });
  // Creating the module stage clears the old overlay. Its phase must also be set
  // before active actors arrive, otherwise a previous paused phase suppresses them.
  if (stageChanged || next.status !== previous?.status || JSON.stringify(next.savedFiles) !== JSON.stringify(previous?.savedFiles) || JSON.stringify(next.modules) !== JSON.stringify(previous?.modules))
    messages.push({ type: 'workshop', phase: next.phase, status: next.status, plan: next.plan, savedFiles: next.savedFiles, modules: next.modules, restore: force });
  if (!force) for (const agent of Object.keys(previous?.actors || {})) if (!next.actors[agent]) messages.push({ type: 'crew', agent, state: 'gone' });
  for (const actor of Object.values(next.actors)) {
    const changed = JSON.stringify(actor) !== JSON.stringify(previous?.actors[actor.agent]);
    if (stageChanged || changed) messages.push((force || !changed) && actor.state === 'saved' ? { ...actor, state: 'paused', text: '最近内容已保存' } : actor);
  }
  return messages;
}
