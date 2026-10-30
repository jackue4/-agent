// Participation receipts describe delivery, never implementation or acceptance.
const clip = (value, length = 160) => typeof value === 'string' ? Array.from(value).slice(0, length).join('') : '';
const filePath = value => clip(value, 240).replace(/^res:\/\//, '').replaceAll('\\', '/');
export function focusModule(event, modules = []) {
  const file = filePath(event?.file), row = modules.find(module => module.file === file);
  return row && file ? { file, label: clip(row.label || file.split('/').at(-1), 28), kind: row.kind || 'generic' } : null;
}
export function moduleSuggestions(focus) {
  const prompts = {
    deck: ['让牌面更容易辨认', '让选牌反馈更清晰'], score: ['解释分数是怎么算的', '让计分过程更有节奏'],
    shop: ['说明购买后的效果', '让商品比较更方便'], rules: ['解释关键规则', '把失败原因说清楚'],
    world: ['让目标更容易发现', '让移动路线更清楚'], generic: ['让这个模块更容易理解', '加强这个模块的操作反馈'],
  };
  return focus ? prompts[focus.kind] || prompts.generic : [];
}
export function participationRows(value) {
  return (Array.isArray(value) ? value : []).filter(row => row?.id && ['queued', 'applied'].includes(row.status)).slice(-60)
    .map(row => ({ id: String(row.id), text: clip(row.text, 2000), moduleFile: filePath(row.moduleFile), status: row.status, t: row.t, appliedAt: row.appliedAt }));
}
export function mergeParticipation(current, incoming) {
  const rows = new Map(participationRows(current).map(row => [row.id, row]));
  for (const row of participationRows(incoming)) if (rows.get(row.id)?.status !== 'applied' || row.status === 'applied') rows.set(row.id, row);
  return [...rows.values()].sort((a, b) => (Number(a.t) || 0) - (Number(b.t) || 0)).slice(-60);
}
export function participationLabel(row, { running = false, delivery = 'live' } = {}) {
  if (row.status === 'applied') return '已送达本轮';
  return running && delivery !== 'next_round' ? '等待下个工作节点' : '下轮开始时送达';
}
export function participationSummary(rows, context = {}) {
  const queued = rows.filter(row => row.status === 'queued').length;
  if (queued) return `${queued} 条建议 · ${participationLabel({ status: 'queued' }, context)}`;
  return rows.length ? '建议已送达本轮 · 尚不代表已经实现' : '';
}
