// Shared, DOM-free state rules for the creation page and its regression tests.
export const RUN_LABELS = Object.freeze({ running: '制作中', ready: '验收通过，等待预览确认', completed: '本次制作已完成', partial: '部分完成，仍需修复', interrupted: '制作已中断', cancelled: '制作已停止', failed: '制作遇到问题' });
export const TASK_LABELS = Object.freeze({ queued: '等待开始', running: '正在制作', applied: '已写入，待验收', verified: '验收通过', failed: '失败', blocked: '等待处理', cancelled: '已停止', interrupted: '已中断' });
export const ROLE_LABELS = Object.freeze({ gameplay: '玩法制作', scene: '场景制作', review: '内容审查' });
export function activeTaskCrew(workflow) {
  return (workflow?.tasks || []).filter(task => task.status === 'running').slice(0, 2).map((task, slot) => ({ type: 'crew', agent: slot === 0 ? 'B' : 'C', taskId: task.id, name: ROLE_LABELS[task.role] || '制作任务', color: task.role === 'scene' ? '#34d399' : task.role === 'review' ? '#f472b6' : '#a78bfa', state: task.role === 'review' ? 'testing' : 'coding', text: task.title || '正在处理任务', code: '', slot }));
}
export function normalizeWorkflow(value) {
  if (!value || typeof value !== 'object' || !value.id) return null;
  return { ...value, tasks: Array.isArray(value.tasks) ? value.tasks : [], evidence: Array.isArray(value.evidence) ? value.evidence : [], issues: Array.isArray(value.issues) ? value.issues : [], activity: Array.isArray(value.activity) ? value.activity.slice(-80) : [] };
}
export function reduceWorkflow(current, event) {
  if (event.type === 'workflow') return normalizeWorkflow(event.workflow);
  if (event.type === 'turn_end' && event.workflow?.id === current?.id) return normalizeWorkflow(event.workflow);
  if (event.type === 'task' && current && event.runId === current.id && event.task?.id) {
    const tasks = current.tasks.slice(), index = tasks.findIndex(task => task.id === event.task.id);
    if (index < 0) tasks.push({ ...event.task }); else tasks[index] = { ...tasks[index], ...event.task };
    return { ...current, tasks };
  }
  if (event.type === 'turn_end' && current && event.runId === current.id && RUN_LABELS[event.status]) return { ...current, status: event.status };
  return current;
}
export function workflowSummary(workflow, scene = {}) {
  if (!workflow) return { text: '等待你的创作想法', tone: 'idle', canRepair: false };
  const status = workflow.status;
  const editNotice = value => /^关卡位置已编辑，试玩将使用新位置；完整玩法需重新验收$/.test(String(typeof value === 'string' ? value : value?.message || ''));
  const pendingEdit = scene.sceneDirty || [workflow.reason, workflow.iteration?.reason, ...(workflow.issues || [])].some(editNotice);
  const latestEvidence = new Map();
  for (const row of workflow.evidence || []) if (!scene.sourceRevision || !row.sourceRevision || row.sourceRevision === scene.sourceRevision) latestEvidence.set(row.kind, row);
  const realError = ['failed', 'interrupted'].includes(status) || Boolean(workflow.error)
    || (workflow.tasks || []).some(task => ['failed', 'blocked'].includes(task.status) || task.error)
    || (workflow.issues || []).some(issue => !editNotice(issue))
    || [...latestEvidence.values()].some(row => row.ok === false);
  if (status !== 'running' && pendingEdit && !realError) return { text: '场景已修改，等待验收', tone: 'active', canRepair: false };
  return { text: RUN_LABELS[status] || '制作状态待确认', tone: ['partial', 'failed', 'interrupted'].includes(status) ? 'error' : status === 'completed' ? 'success' : 'active', canRepair: ['partial', 'failed', 'interrupted', 'cancelled'].includes(status) };
}
export const STUDIO_STAGES = Object.freeze([{ id: 'scope', label: '定范围' }, { id: 'build', label: '制作' }, { id: 'verify', label: '试玩验收' }, { id: 'review', label: '交给你玩' }]);
const terminalRuns = new Set(['completed', 'partial', 'interrupted', 'cancelled', 'failed']);
const timestamp = value => typeof value === 'number' && Number.isFinite(value) ? value : typeof value === 'string' ? Date.parse(value) || 0 : 0;
export function iterationView(workflow, now = Date.now()) {
  const iteration = workflow?.iteration || {}, terminal = terminalRuns.has(workflow?.status);
  let phase = iteration.phase;
  if (!STUDIO_STAGES.some(stage => stage.id === phase) && phase !== 'paused') {
    phase = ['ready', 'completed'].includes(workflow?.status) ? 'review'
      : workflow?.evidence?.some(item => ['test', 'compile', 'build'].includes(item.kind)) ? 'verify'
      : workflow?.tasks?.length ? 'build' : 'scope';
  }
  const paused = phase === 'paused' || ['interrupted', 'cancelled', 'failed', 'partial'].includes(workflow?.status);
  const startedAt = timestamp(iteration.startedAt) || timestamp(workflow?.startedAt);
  // Iteration end is the actual production boundary. Workflow updated/completed
  // timestamps may precede it, or follow later when a preview receipt is saved.
  const stoppedAt = timestamp(iteration.endedAt) || timestamp(workflow?.endedAt) || timestamp(workflow?.completedAt) || timestamp(workflow?.finishedAt) || timestamp(workflow?.updatedAt);
  const stopped = terminal || paused || workflow?.status === 'ready';
  const elapsedMs = startedAt ? Math.max(0, (stopped && stoppedAt ? stoppedAt : now) - startedAt) : null;
  const targetMs = Number(iteration.targetMs) > 0 ? Number(iteration.targetMs) : null;
  const wrapAt = timestamp(iteration.wrapAt), deadlineAt = timestamp(iteration.deadlineAt);
  const timedOut = !stopped && deadlineAt > 0 && now >= deadlineAt;
  const wrapping = !stopped && wrapAt > 0 && now >= wrapAt;
  const pastTarget = !stopped && targetMs && elapsedMs >= targetMs;
  const clockState = paused ? 'paused' : stopped ? 'stopped' : timedOut ? 'overtime' : wrapping || pastTarget ? 'wrap' : 'running';
  const clockLabel = paused ? '已暂停 · 等你决定下一步' : terminal ? '本轮已结束' : workflow?.status === 'ready' ? '等待你打开试玩确认'
    : timedOut ? '已超过约定上限 · 尚未结束' : wrapping ? '已到收口时间 · 优先验收已有内容' : pastTarget ? '已到目标时间 · 仍在制作' : targetMs ? '目标时间是约定，不是完成保证' : '旧记录未设置本轮目标';
  return { phase, phaseIndex: STUDIO_STAGES.findIndex(stage => stage.id === phase), paused, elapsedMs, targetMs, clockState, clockLabel, reason: String(iteration.reason || ''), kind: iteration.tier === 'quality' ? iteration.kind === 'iteration' ? '品质 · 本轮改进' : '品质 · 完整游戏' : iteration.kind === 'iteration' ? '本轮改进' : '首个可玩 Demo', hasIteration: Boolean(workflow?.iteration), canChoose: Boolean(workflow && !['running'].includes(workflow.status)), nextSteps: Array.isArray(iteration.nextSteps) ? iteration.nextSteps : [] };
}
export function formatElapsed(ms) {
  if (ms == null) return '—';
  const seconds = Math.floor(Math.max(0, ms) / 1000);
  return Math.floor(seconds / 60) + ':' + String(seconds % 60).padStart(2, '0');
}
/** Two creation tiers; minutes mirror the server's targets and are shown before a round starts. */
export const CREATION_TIERS = { demo: { label: 'Demo', minutes: 8 }, quality: { label: '品质', minutes: 25 } };
export function iterationRequest(value) { return { tier: value === 'quality' ? 'quality' : 'demo' }; }
export function canForwardTestInput(mode, godot, loadedBuild, currentBuild) {
  if (mode !== 'edit') return false;
  if (!godot) return true;
  return Boolean(loadedBuild?.loaded === true && loadedBuild.buildId && currentBuild?.buildId
    && loadedBuild.buildId === currentBuild.buildId && loadedBuild.sourceRevision != null && currentBuild.sourceRevision != null
    && String(loadedBuild.sourceRevision) === String(currentBuild.sourceRevision));
}
export function isWritingProgress(event) { return event?.type === 'tool_progress' && /^(write|patch)_(module|file)$/.test(event.name); }
// Transient stream metadata is not a saved file or an activity log entry.
// Explicitly select fields so neither source code nor private reasoning is retained.
export function reduceWritingProgress(current, event, runId) {
  if (event.runId && runId && event.runId !== runId) return current;
  if (isWritingProgress(event)) {
    const same = current?.id === event.id;
    const count = Number.isFinite(event.total) ? event.total : event.lines;
    return { id: event.id || '', runId, agent: event.agent || '', taskId: event.taskId || '', file: String(event.file || (same ? current.file : '') || '').slice(0, 240),
      step: String(event.step || (same ? current.step : '') || '').slice(0, 120), lines: Number.isFinite(count) ? Math.max(0, Math.floor(count)) : same ? current.lines : 0 };
  }
  if (!current) return null;
  if (['turn_start', 'turn_end', 'error'].includes(event.type)) return null;
  if (event.type === 'workflow' && (event.workflow?.id !== current.runId || event.workflow?.status !== 'running')) return null;
  if (event.type === 'tool_start' && event.id !== current.id) return null;
  if (['code_write', 'tool_result', 'tool_end', 'tool_stream_end'].includes(event.type)
    && ((!event.id && (!event.file || event.file === current.file)) || event.id === current.id)) return null;
  return current;
}
export function studioTaskCards(workflow, live = [], writing = null) {
  const ranks = { running: 0, failed: 1, blocked: 1, queued: 2, applied: 3, verified: 4, interrupted: 5, cancelled: 6 };
  const tasks = [...(workflow?.tasks || [])].sort((a, b) => (ranks[a.status] ?? 9) - (ranks[b.status] ?? 9));
  if (tasks.length) return tasks.slice(0, 2).map(task => ({ ...task, roleLabel: ROLE_LABELS[task.role] || '制作任务', files: Array.isArray(task.changed) && task.changed.length ? task.changed : Array.isArray(task.files) ? task.files : [], statusLabel: TASK_LABELS[task.status] || '状态待确认' }));
  if (writing) return [{ id: 'main-work', roleLabel: '主制作', title: writing.step || '正在编写工程内容', status: 'running', statusLabel: '编写中 · 尚未保存',
    files: writing.file ? [writing.file] : [], writingLabel: (writing.file ? writing.file + ' · ' : '') + '已收到 ' + writing.lines + ' 行' }];
  const rows = mergeActivity(workflow, live), latest = rows.at(-1);
  if (!latest) return [];
  const file = rows.findLast(row => row.file)?.file;
  const active = latest.status === 'running' && workflow?.status === 'running';
  return [{ id: 'main-work', roleLabel: '主制作', title: latest.title, status: active ? 'running' : latest.status || 'idle',
    statusLabel: active ? '当前实际工作' : ['failed', 'blocked'].includes(latest.status) ? '遇到问题' : workflow?.status === 'running' ? '最近完成的动作' : '本轮工作记录', files: file ? [file] : [] }];
}
export function blueprintView(project, workflow, live = []) {
  const design = project?.game?.design || {}, rows = mergeActivity(workflow, live);
  const milestones = Array.isArray(design.milestones) ? design.milestones : [];
  const current = milestones[Math.max(0, Number(design.current) || 0)] || milestones[0];
  const palette = (Array.isArray(design.palette) ? design.palette : []).filter(color => typeof color === 'string' && /^#[0-9a-f]{3,8}$/i.test(color)).slice(0, 6);
  return { hasDesign: Boolean(design.title || design.core_loop), title: String(design.title || (project?.game?.meta?.title !== '未命名游戏' ? project?.game?.meta?.title : '') || '从一个可玩的想法开始'),
    description: String(design.core_loop || design.pitch || ''), idea: String(workflow?.goal || ''), palette,
    milestone: typeof current === 'string' ? current : String(current?.name || current?.title || current?.goal || ''),
    steps: (Array.isArray(design.build_steps) ? design.build_steps : []).filter(step => typeof step === 'string').slice(0, 4), latest: rows.at(-1) || null };
}
export function safeActivityImage(value) {
  if (typeof value !== 'string') return '';
  return /^\/(?!\/)[^\s<>\\]*$/.test(value) || /^data:image\/(png|jpeg|webp);base64,[a-z0-9+/=]+$/i.test(value) ? value : '';
}
export function activityFromEvent(event, runId) {
  if (!event || (event.runId && runId && event.runId !== runId)) return null;
  if (isWritingProgress(event)) return null;
  const base = { id: 'event-' + (event.seq ?? event.id ?? [event.type, event.t, event.file || event.name || ''].join('-')), at: event.at || event.t || null, kind: event.type, taskId: event.taskId || '', file: event.file || '', status: event.ok === false ? 'failed' : event.ok === true ? 'verified' : 'running' };
  if (event.activity?.id) return { ...event.activity, image: safeActivityImage(event.activity.image) };
  if (event.type === 'task' && event.task) return { ...base, taskId: event.task.id, title: event.task.title || '制作任务', detail: TASK_LABELS[event.task.status] || event.task.status, status: event.task.status };
  if (event.type === 'code_write') return { ...base, title: '已写入 ' + (event.file || '工程文件'), detail: event.step || '', status: 'applied' };
  if (event.type === 'tool_start') return { ...base, title: ({ design_game: '正在确定这一轮的范围', delegate_tasks: '正在安排协作任务', run_test: '开始实际试玩检查', run_game: '打开游戏检查画面', game_eval: '检查游戏行为', export_game: '正在生成试玩包', web_fetch: '核对游戏参考' })[event.name] || (/^(write|patch)_/.test(event.name) ? '正在编写工程内容' : '正在执行制作检查'), detail: event.file || event.step || '' };
  if (event.type === 'tool_progress' && (event.file || event.step)) return { ...base, id: 'tool-' + (event.id || event.name || '') + '-' + (event.file || ''), title: event.step || '正在处理 ' + event.file, detail: event.file || '' };
  if (['compile', 'test', 'eval'].includes(event.type)) return { ...base, title: ({ compile: '代码检查', test: '实际试玩检查', eval: '游戏行为检查' })[event.type] + (event.ok === true ? '通过' : event.ok === false ? '发现问题' : '已返回结果'), detail: event.errors?.map(e => typeof e === 'string' ? e : e.message).filter(Boolean).slice(0, 2).join('；') || (event.checks?.length ? event.checks.length + ' 项实际检查' : ''), image: safeActivityImage(event.shot || event.image) };
  if (event.type === 'ops') { const pack = event.ops?.find(op => op.op === 'pck'); if (pack) return { ...base, title: '新试玩包已生成', detail: pack.version != null ? '版本 ' + pack.version : '可打开查看实际效果', status: 'applied' }; }
  if (event.type === 'error') return { ...base, title: '制作遇到问题', detail: event.message || '', status: 'failed' };
  return null;
}
export function mergeActivity(workflow, live = []) {
  const rows = new Map();
  for (const row of [...(workflow?.activity || []), ...live]) if (row?.title && row.id) rows.set(row.id, { ...row, image: safeActivityImage(row.image) });
  if (!rows.size) for (const e of workflow?.evidence || []) rows.set(e.id, { id: e.id, at: e.at, title: ({ compile: '代码检查', test: '实际试玩检查', build: '试玩包生成', preview: '浏览器首帧确认' })[e.kind] || '制作检查', detail: e.summary || '', status: e.ok ? 'verified' : 'failed' });
  return [...rows.values()].sort((a, b) => timestamp(a.at) - timestamp(b.at)).slice(-40);
}
export function studioNextSteps(workflow) {
  const rows = Array.isArray(workflow?.iteration?.nextSteps) ? workflow.iteration.nextSteps : [];
  const defaults = ['打磨操作手感', '改善画面辨识', '调整难度节奏'];
  return (rows.length ? rows : defaults).slice(0, 3).map((row, i) => {
    const title = typeof row === 'string' ? row : row.title || row.label || row.text || '一个小改进';
    return { id: String(typeof row === 'object' ? row.id || i : i), title: String(title), prompt: typeof row === 'object' && row.prompt ? String(row.prompt) : '这一轮只做一个改进：' + title + '。保留当前可玩的版本，完成后实际试玩验收，再交给我选择下一步。' };
  });
}
// A future event is buffered. Only the next consecutive sequence advances the cursor.
export function createEventCursor(initial = 0) {
  let cursor = Number.isSafeInteger(initial) && initial >= 0 ? initial : 0;
  const pending = new Map();
  const drain = () => { const out = []; while (pending.has(cursor + 1)) { out.push(pending.get(++cursor)); pending.delete(cursor); } return out; };
  return {
    get seq() { return cursor; },
    get gap() { return pending.size > 0 && !pending.has(cursor + 1); },
    ingest(event) {
      if (!Number.isSafeInteger(event?.seq)) return [event];
      if (event.seq <= cursor) return [];
      pending.set(event.seq, event);
      return drain();
    },
    reset(next) {
      if (!Number.isSafeInteger(next) || next < 0) return [];
      // An authoritative reset can also represent a restored server snapshot. Old
      // buffered events then belong to the abandoned sequence and must be dropped.
      if (next < cursor) pending.clear();
      cursor = next;
      for (const seq of pending.keys()) if (seq <= cursor) pending.delete(seq);
      return drain();
    },
  };
}
export function runtimeErrors(value) {
  const rows = Array.isArray(value) ? value : value ? [value] : [];
  return rows.filter(row => row?.kind !== 'warning').map(row => typeof row === 'string' ? row : [row.file, row.line ? '第 ' + row.line + ' 行' : '', row.message || row.error || '运行错误'].filter(Boolean).join('：')).slice(0, 20);
}
export function assessPreview(event, expected) {
  if (!expected || event.previewSession !== expected.session) return { status: 'stale' };
  const errors = runtimeErrors(event.errors);
  if (event.type === 'js_error') errors.unshift(String(event.message || '预览打开失败'));
  if ((event.type === 'ready' && event.loaded !== true) || event.loaded === false) errors.unshift('游戏场景未成功载入');
  const revisionMatches = String(event.sourceRevision ?? '') === String(expected.sourceRevision ?? '');
  const manifestMatches = Boolean(expected.buildId && event.buildId && expected.sourceRevision != null && event.sourceRevision != null && event.buildId === expected.buildId && revisionMatches);
  const failed = errors.length > 0;
  // The URL expectation is only sufficient to attribute failure, never success.
  if (failed) return { status: 'failed', errors, receipt: expected.buildId ? { buildId: expected.buildId, sourceRevision: expected.sourceRevision, loaded: false, errors, kind: 'runtime_ready' } : null };
  if (event.type !== 'ready') return { status: 'ignore' };
  if (!manifestMatches) return { status: 'unverified', errors: [], message: event.buildId ? '预览版本与当前制作版本不一致，尚未验证。' : '此游戏包缺少版本凭证，场景可见，但尚未验证当前制作结果。' };
  return { status: 'verified', errors: [], receipt: { buildId: event.buildId, sourceRevision: event.sourceRevision, loaded: true, errors: [], kind: 'runtime_ready' } };
}
