import crypto from 'node:crypto';

const clean = (value, limit) => String(value ?? '').replace(/[\u0000-\u0008\u000b-\u001f]/g, '').trim().slice(0, limit);
export function enqueueParticipation(project, input, time = Date.now()) {
  const text = clean(input?.text, 800);
  const requestId = clean(input?.requestId, 80);
  if (!text) return { status: 400, body: { error: '请填写想调整的内容' } };
  if (!/^[\w-]{8,80}$/.test(requestId)) return { status: 400, body: { error: '缺少有效的请求标识，请重试' } };
  const entries = project.participation ||= [];
  const previous = entries.find(e => e.requestId === requestId);
  if (previous) {
    if (previous.text !== text || previous.moduleFile !== clean(input.moduleFile, 160)) return { status: 409, body: { error: '同一请求不能提交不同内容' } };
    return { status: 200, body: { ok: true, participation: entries } };
  }
  if (entries.filter(e => e.status === 'queued').length >= 12) return { status: 429, body: { error: '已有 12 条建议排队，请等当前建议送达后再提交' } };
  const moduleFile = clean(input?.moduleFile, 160);
  if (moduleFile && !(project.game?.design?.modules || []).some(m => m.file === moduleFile)) return { status: 400, body: { error: '模块已变更，请重新选择或提交整体建议' } };
  entries.push({ id: crypto.randomUUID(), requestId, text, moduleFile, status: 'queued', t: time });
  project.participation = entries.filter(e => e.status === 'queued' || entries.indexOf(e) >= entries.length - 60);
  project.emit?.({ type: 'participation', participation: project.participation });
  project.save?.();
  return { status: 200, body: { ok: true, participation: project.participation } };
}

/** Delivered to the next request context, never evidence that the requested change is implemented. */
export function deliverParticipation(project, time = Date.now(), { resumeRunId } = {}) {
  const pending = (project.participation || []).filter(e => e.status === 'queued' || resumeRunId && e.status === 'applied' && e.runId === resumeRunId);
  if (!pending.length) return '';
  const text = '玩家在制作现场补充的建议（不是完成证据）：\n' + pending.map(e => '- ' + (e.status === 'applied' ? '【上一轮未完成，尚未确认落实】' : '') + (e.moduleFile ? '[' + e.moduleFile + '] ' : '') + e.text).join('\n') + '\n请结合本轮目标处理；小调整在安全节点落实并验证，超出本轮范围的明确放入下一步。不要仅因收到建议就宣称完成。';
  for (const item of pending) { item.status = 'applied'; item.appliedAt = time; item.runId = project.workflow?.id || ''; item.deliveryCount = (item.deliveryCount || 0) + 1; }
  project.emit?.({ type: 'participation', participation: project.participation });
  project.save?.();
  return text;
}
