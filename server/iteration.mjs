/** Bounded creation rounds. Timestamps are durable; timers belong to a running session only. */
export const DEFAULT_TARGET_MS = 5 * 60000;
export const MAX_HARD_MS = 10 * 60000;
/**
 * Two creation tiers. "demo" is the fast first-playable round (a pencil Demo in about five
 * minutes); "quality" gives the builder a longer round and larger per-round budgets for research,
 * assets, delegation and test/fix loops.
 */
export const TIERS = {
  demo: { label: 'Demo', targetMs: DEFAULT_TARGET_MS, wrapReserveMs: 75000, overrunMs: 105000, maxHardMs: MAX_HARD_MS, delegationMs: 110000,
    assets: 2, fetches: 3, tests: 3, delegateBatches: 2, previewFailures: 3, maxTurns: 48, maxTokens: 24000 },
  quality: { label: '品质', targetMs: 25 * 60000, wrapReserveMs: 240000, overrunMs: 300000, maxHardMs: 30 * 60000, delegationMs: 150000,
    assets: 10, fetches: 8, tests: 6, delegateBatches: 4, previewFailures: 6, maxTurns: 140, maxTokens: 32000 },
};
export const tierOf = value => value === 'quality' ? 'quality' : 'demo';
export const tierLimits = value => TIERS[tierOf(value)];
const clean = (v, n = 300) => String(v ?? '').replace(/[\u0000-\u001f]/g, ' ').slice(0, n);
const finite = (v, fallback) => Number.isFinite(Number(v)) ? Number(v) : fallback;

export function createIteration({ kind = 'demo', tier = 'demo', targetMs, wrapMs, hardMs, startedAt = Date.now() } = {}) {
  const t = tierLimits(tier);
  const target = Math.max(1, Math.min(t.maxHardMs, finite(targetMs, t.targetMs)));
  const hard = Math.max(target, Math.min(t.maxHardMs, finite(hardMs, target + t.overrunMs)));
  const wrap = Math.max(0, Math.min(target, finite(wrapMs, target - Math.min(target * .25, t.wrapReserveMs))));
  const start = finite(startedAt, Date.now());
  return { kind: kind === 'iteration' ? 'iteration' : 'demo', tier: tierOf(tier), targetMs: target, hardMs: hard,
    startedAt: start, wrapAt: start + wrap, deadlineAt: start + hard, phase: 'scope', nextSteps: [] };
}

export function updateIteration(iteration, { phase, reason, nextSteps } = {}) {
  if (!iteration) return iteration;
  if (['scope', 'build', 'verify', 'review', 'paused'].includes(phase)) iteration.phase = phase;
  if (reason != null) iteration.reason = clean(reason, 500);
  if (Array.isArray(nextSteps)) iteration.nextSteps = nextSteps.filter(v => typeof v === 'string' && v.trim()).slice(0, 3).map(v => clean(v));
  return iteration;
}

export function remainingMs(iteration, now = Date.now()) { return Math.max(0, iteration.deadlineAt - now); }
export function delegationBudget(iteration, now = Date.now()) {
  // Stop workers at wrap-up, leaving time for integration, real input and assertions.
  return Math.max(0, Math.min(tierLimits(iteration.tier).delegationMs, iteration.wrapAt - now, remainingMs(iteration, now) - 60000));
}
export function iterationError(message, code = 'ITERATION_DEADLINE') {
  return Object.assign(new Error(message), { name: 'AbortError', code });
}
export function throwIfAborted(signal) { if (signal?.aborted) throw signal.reason instanceof Error ? signal.reason : iterationError('本轮已停止', 'ITERATION_CANCELLED'); }
export function abortable(promise, signal) {
  if (!signal) return Promise.resolve(promise);
  if (signal.aborted) return Promise.reject(signal.reason || iterationError('本轮已停止'));
  return new Promise((resolve, reject) => {
    const stop = () => reject(signal.reason || iterationError('本轮已停止'));
    signal.addEventListener('abort', stop, { once: true });
    Promise.resolve(promise).then(resolve, reject).finally(() => signal.removeEventListener('abort', stop));
  });
}

export function iterationClock(iteration, { signal, onWrap = () => {}, onTarget = () => {}, onAbort = () => {} } = {}) {
  const controller = new AbortController();
  const abort = reason => { if (!controller.signal.aborted) controller.abort(reason); };
  const parentAbort = () => abort(signal.reason || iterationError('用户已停止本轮', 'ITERATION_CANCELLED'));
  const stopped = () => onAbort(controller.signal.reason);
  controller.signal.addEventListener('abort', stopped, { once: true });
  if (signal?.aborted) parentAbort(); else signal?.addEventListener('abort', parentAbort, { once: true });
  if (remainingMs(iteration) <= 0) abort(iterationError('本轮达到时间上限，当前成果已保存'));
  const wrap = setTimeout(() => { if (!controller.signal.aborted) onWrap(); }, Math.max(0, iteration.wrapAt - Date.now()));
  const target = setTimeout(() => { if (!controller.signal.aborted) onTarget(); }, Math.max(0, iteration.startedAt + iteration.targetMs - Date.now()));
  const deadline = setTimeout(() => abort(iterationError('本轮达到时间上限，当前成果已保存')), remainingMs(iteration));
  return { signal: controller.signal, abort, dispose() {
    clearTimeout(wrap); clearTimeout(target); clearTimeout(deadline);
    signal?.removeEventListener('abort', parentAbort); controller.signal.removeEventListener('abort', stopped);
  } };
}
