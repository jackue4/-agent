const statuses = new Set(['starting', 'live', 'passed', 'failed', 'stopped']);
const clean = (value, max = 180) => typeof value === 'string' ? Array.from(value).slice(0, max).join('') : '';
export const watchIsActive = watch => ['starting', 'live'].includes(watch?.status);
export function emptyPlaytest(runId = '') { return { runId, watch: null, retired: [] }; }
export function normalizePlaytest(value) {
  if (!value || !value.sessionId || !value.runId || !statuses.has(value.status) || !['run', 'eval', 'test'].includes(value.kind)) return null;
  const frameUrl = typeof value.frameUrl === 'string' && /^\/(?!\/)[^\s<>\\]*$/.test(value.frameUrl) ? value.frameUrl : '';
  return { sessionId: clean(value.sessionId, 100), runId: clean(value.runId, 100), sourceRevision: clean(value.sourceRevision, 100), kind: value.kind,
    step: clean(value.step), status: value.status, frameSeq: Number.isSafeInteger(value.frameSeq) && value.frameSeq >= 0 ? value.frameSeq : 0,
    frameUrl, capturedAt: Number.isFinite(value.capturedAt) ? value.capturedAt : 0, updatedAt: Number.isFinite(value.updatedAt) ? value.updatedAt : 0,
    checks: (Array.isArray(value.checks) ? value.checks : []).slice(-12).map(row => ({ what: clean(row.what), ok: row.ok === true })),
    errors: (Array.isArray(value.errors) ? value.errors : []).slice(-4).map(error => clean(typeof error === 'string' ? error : error.message)) };
}
export function reducePlaytest(state, value, runId) {
  const current = state?.runId === runId ? state : emptyPlaytest(runId);
  const next = normalizePlaytest(value);
  if (!next || next.runId !== runId || current.retired.includes(next.sessionId)) return current;
  const old = current.watch;
  if (old?.sessionId === next.sessionId) {
    if (next.updatedAt < old.updatedAt || next.frameSeq < old.frameSeq) return current;
    if (!watchIsActive(old) && watchIsActive(next)) return current;
  } else if (old && next.updatedAt < old.updatedAt) return current;
  return { runId, watch: next, retired: old && old.sessionId !== next.sessionId ? [...current.retired, old.sessionId].slice(-40) : current.retired };
}
export function playtestPresentation(watch, now = Date.now(), displayedAt = watch?.capturedAt || 0) {
  if (!watch) return { label: '', status: '', active: false, stale: false, hasFrame: false };
  const active = watchIsActive(watch), hasFrame = Boolean(watch.frameUrl && watch.frameSeq > 0);
  const stale = active && hasFrame && displayedAt > 0 && now - displayedAt > 3000;
  const passed = { run: '启动完成', eval: '本步操作完成', test: '本次断言检查通过' };
  const status = stale ? '画面未更新' : watch.status === 'passed' ? passed[watch.kind] : ({ starting: '正在启动', live: '正在执行', failed: '本步检查未通过', stopped: '本次检查已停止' })[watch.status];
  return { label: { run: '实际启动画面', eval: '实际操作画面', test: '实际规则检查' }[watch.kind], status, active, stale, hasFrame,
    note: !hasFrame ? active ? '正在启动真实游戏，等待首帧' : '本次没有收到可显示的画面' : active ? stale ? '保留最近真实画面，等待更新' : '正在接收实际游戏画面' : '最后一帧真实画面 · 可返回制作' };
}
export function returnsToMaking(event) {
  return ['construction', 'code_write'].includes(event?.type) || event?.type === 'tool_start' && /^(write_file|patch_file|write_module|patch_module|build_scene|apply_scene_ops|update_construction)$/.test(event.name);
}
