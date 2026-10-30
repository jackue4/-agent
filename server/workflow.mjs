/** Durable workflow state. Evidence describes an exact source revision and build, never a role animation. */
import crypto from 'node:crypto';
import { updateIteration } from './iteration.mjs';

const clean = (s, n = 800) => String(s ?? '').replace(/\u001b\[[0-?]*[ -/]*[@-~]/g, '').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '').slice(0, n);
const errorText = e => {
  const raw = typeof e === 'string' ? e : e.message || e.text || JSON.stringify(e);
  const lines = [...String(raw).matchAll(/^(?:SCRIPT |USER )?ERROR:\s*(.+)$/gm)].map(m => m[1].trim());
  return clean(lines.length ? [...new Set(lines)].join('；') : raw);
};
const stamp = run => { run.updatedAt = Date.now(); return run; };
const recoverable = new Set(['partial', 'failed', 'interrupted', 'cancelled', 'running', 'ready']);
export function createWorkflow({ goal, sourceRevision = '', previous = null }) {
  const resume = previous && recoverable.has(previous.status);
  return {
    schema: 1, id: crypto.randomUUID(), goal: clean(goal, 4000), status: 'running',
    startedAt: Date.now(), updatedAt: Date.now(), baseRevision: sourceRevision,
    previousRunId: resume ? previous.id : null,
    tasks: resume ? structuredClone(previous.tasks || []).map(t => ['running', 'queued'].includes(t.status) ? { ...t, status: 'interrupted' } : t) : [],
    evidence: resume ? structuredClone(previous.evidence || []).slice(-80) : [],
    issues: [], completionRequested: false, pendingMilestone: '',
  };
}

export function upsertTask(run, task) {
  if (!run || !task?.id) return;
  const i = run.tasks.findIndex(t => t.id === task.id), prev = run.tasks[i];
  const restarting = prev && task.status === 'queued' && !['queued', 'running'].includes(prev.status);
  const next = { ...prev, ...structuredClone(task), attempt: (prev?.attempt || 1) + (restarting ? 1 : 0) };
  if (restarting) { delete next.resolution; delete next.verifiedRevision; next.verified = false; }
  if (i < 0) run.tasks.push(next); else run.tasks[i] = next;
  stamp(run);
  return next;
}

export function recordEvidence(run, evidence) {
  if (!run) return null;
  const item = {
    id: crypto.randomUUID(), at: Date.now(), kind: evidence.kind,
    sourceRevision: clean(evidence.sourceRevision, 64), ok: evidence.ok === true,
    ...(evidence.buildId ? { buildId: clean(evidence.buildId, 32) } : {}),
    ...(evidence.contentHash ? { contentHash: clean(evidence.contentHash, 64) } : {}),
    ...(evidence.version != null ? { version: evidence.version } : {}),
    ...(evidence.checks ? { checks: evidence.checks.slice(0, 100).map(c => ({ ok: c.ok === true, what: clean(c.what, 500) })) } : {}),
    ...(evidence.errors ? { errors: evidence.errors.filter(Boolean).slice(0, 20).map(e => typeof e === 'string' ? errorText(e) : { kind: clean(e.kind, 30), message: errorText(e), file: clean(e.file, 200), line: e.line }) } : {}),
    ...(evidence.summary ? { summary: clean(evidence.summary, 1200) } : {}),
  };
  run.evidence.push(item);
  if (run.evidence.length > 100) run.evidence.splice(0, run.evidence.length - 100);
  stamp(run);
  return item;
}

export function acceptanceFor(run, revision, { requirePreview = false, ignoreTasks = false } = {}) {
  const issues = [];
  if (!run || !revision) return { ok: false, issues: ['还没有当前版本的验收记录'], build: null };
  const evidence = (run.evidence || []).filter(e => e.sourceRevision === revision);
  const latest = kind => evidence.findLast(e => e.kind === kind);
  const compile = latest('compile'), test = latest('test'), build = latest('build');
  if (!compile?.ok) issues.push('当前版本尚未通过工程编译和启动检查');
  if (run.iteration && !latest('play')?.ok) issues.push('当前版本尚未完成真实输入试玩');
  if (!test?.ok || !test.checks?.length || test.checks.some(c => !c.ok)) issues.push('当前版本尚未通过含有效断言的玩法测试');
  if (!build?.ok || !/^[a-f0-9]{32}$/.test(build.buildId || '')) issues.push('当前版本尚未成功生成预览包');
  if (!ignoreTasks) for (const task of run.tasks || []) {
    if (!['applied', 'verified'].includes(task.status)) issues.push('任务未完成：' + task.title + (task.error ? '（' + clean(task.error, 180) + '）' : ''));
  }
  if (requirePreview) {
    const preview = evidence.findLast(e => e.kind === 'preview' && e.buildId === build?.buildId);
    if (!preview?.ok) issues.push('尚未收到当前预览包在浏览器中成功启动的回执');
  }
  return { ok: issues.length === 0, issues, build, compile, test };
}

/** The browser receipt proves startup only; gameplay acceptance comes from native checks above. */
export function settleWorkflow(run, revision) {
  if (!run) return run;
  const native = acceptanceFor(run, revision);
  run.sourceRevision = revision;
  if (!run.completionRequested) { run.issues = native.issues; return stamp(run); }
  if (!native.ok) { run.status = 'partial'; run.issues = native.issues; return stamp(run); }
  const full = acceptanceFor(run, revision, { requirePreview: true });
  run.status = full.ok ? 'completed' : 'ready';
  updateIteration(run.iteration, { phase: 'review' });
  run.issues = full.issues;
  if (full.ok) {
    run.completedAt = Date.now();
    for (const task of run.tasks) if (task.status === 'applied') Object.assign(task, { status: 'verified', verified: true, verifiedRevision: revision });
  }
  return stamp(run);
}

export function recoverWorkflow(run) {
  if (!run || run.status !== 'running') return run;
  run.status = 'interrupted';
  updateIteration(run.iteration, { phase: 'paused', reason: '服务中断，当前成果已保存', nextSteps: run.iteration?.nextSteps?.length ? run.iteration.nextSteps : ['继续处理未完成部分，并重新验证当前版本'] });
  run.completionRequested = false;
  run.issues = [...new Set([...(run.issues || []), '服务中断，已保留任务结果和失败现场，可继续处理未完成部分'])];
  for (const task of run.tasks || []) if (['running', 'queued'].includes(task.status)) Object.assign(task, { status: 'interrupted', finishedAt: Date.now() });
  return stamp(run);
}

export function invalidateWorkflow(run, reason) {
  if (!run) return;
  run.completionRequested = false;
  run.pendingMilestone = '';
  if (run.status !== 'running') run.status = 'partial';
  run.issues = [clean(reason || '工程已更新，需要重新验收')];
  return stamp(run);
}

export function resumeContext(run) {
  if (!run || !recoverable.has(run.status)) return '';
  return [
    '上轮未完成任务（从实际文件继续，不要重做已合入的内容）：' + clean(run.goal, 1800),
    '上轮状态：' + run.status,
    ...(run.tasks || []).map(t => `${t.id} [${t.status}] ${t.title} | 文件 ${t.files?.join(', ')} | ${clean(t.summary || t.error, 500)}`),
    '待处理：' + (run.issues || []).join('；'),
    ...(run.iteration ? ['本轮节奏：只推进一个改进；已有成果继续复用。下一步：' + (run.iteration.nextSteps || []).join('；')] : []),
    '失败任务用原 id 重新 delegate_tasks，或修复并通过当前版本测试后 resolve_task。完成与否必须由当前版本验收决定。',
  ].join('\n').slice(0, 7000);
}
