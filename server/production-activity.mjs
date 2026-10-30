// A compact public projection of real execution events. No token stream or invented progress.
import { TIERS, tierOf } from './iteration.mjs';
const tidy = (value, limit = 220) => String(value ?? '').replace(/\u001b\[[0-?]*[ -/]*[@-~]/g, '').replace(/[\u0000-\u001f]/g, ' ').slice(0, limit);
const toolTitles = {
  build_scene: ['build', '正在现场搭建关卡'],
  design_game: ['scope', '正在确定这一轮的可玩范围'], update_plan: ['scope', '正在规划后续的小步骤'],
  delegate_tasks: ['build', '正在分配独立制作任务'], read_file: ['build', '正在检查已有内容'],
  grep_files: ['build', '正在定位需要修改的内容'], list_files: ['scope', '正在查看工程现状'],
  write_file: ['build', '正在制作游戏内容'], patch_file: ['build', '正在调整游戏内容'],
  generate_asset: ['build', '正在准备视觉或声音素材'], preview_checkpoint: ['build', '正在生成可试玩片段'],
  run_game: ['verify', '正在启动游戏实测'], game_eval: ['verify', '正在操作游戏检查效果'],
  run_test: ['verify', '正在验证玩法规则'], resolve_task: ['verify', '正在核对修复结果'],
  finish: ['verify', '正在核对本轮交付'],
};
const artTitles = { planning: '美术子代理正在规划正式画风', styling: '正在把铅笔 Demo 画成风格定稿', drawing: '美术子代理正在逐个绘制正式美术', verified: '正式美术已接入并自动复验', failed: '美术子代理暂未完成', idle: '美术位已全部就绪' };
const evidenceTitles = { compile: '工程检查', test: '玩法断言', build: '预览构建', preview: '浏览器启动确认', play: '实际操作试玩' };
const same = (rows, key) => rows.some(row => row.key === key);
export function recordProductionActivity(workflow, event) {
  if (!workflow?.id || !event || event.runId && event.runId !== workflow.id) return null;
  const rows = workflow.activity ||= [];
  let data, recordedAt = event.t || Date.now(), key = `${event.type}:${event.seq}`;
  const stage = workflow.iteration?.phase || 'build';
  if (event.type === 'turn_start') data = { kind: 'scope', stage: 'scope', title: event.first ? '开始制作首个可玩 Demo' : '开始这一轮改进', status: 'running' };
  else if (event.type === 'design') data = { kind: 'scope', stage: 'scope', title: '本轮范围已确定', detail: event.design?.milestones?.[0]?.title || event.design?.core_loop || event.design?.title, status: 'done' };
  else if (event.type === 'phase') { key = `phase:${event.phase}:${event.text}`; data = { kind: 'phase', stage: { design: 'scope', build: 'build', test: 'verify' }[event.phase] || stage, title: event.text || '正在继续制作', status: 'running' }; }
  else if (event.type === 'task' && event.task?.id) {
    const task = event.task;
    key = `task:${task.id}:${task.attempt || 1}:${task.status}:${task.last_tool || ''}`;
    const labels = { queued: '等待开始', running: '正在制作', applied: '成果已合入，等待验收', verified: '整体验收通过', failed: '遇到问题，保留现场', blocked: '等待前置任务', cancelled: '已停止', interrupted: '已中断' };
    data = { kind: 'task', stage: task.status === 'verified' ? 'verify' : 'build', title: tidy(task.title || task.id, 70) + ' · ' + (labels[task.status] || '状态更新'), taskId: task.id,
      detail: task.error ? '待处理：' + tidy(task.error, 140) : task.last_tool && task.status === 'running' ? toolTitles[task.last_tool]?.[1] || '正在处理独立任务' : (task.changed || task.files || []).join('、'), status: task.status };
  } else if (event.type === 'tool_start' && toolTitles[event.name]) {
    const [phase, title] = toolTitles[event.name]; data = { kind: 'tool', stage: phase, title, status: 'running' }; key = `tool:${event.id}`;
  } else if (event.type === 'construction') data = { kind: 'construction', stage: 'build', title: event.snapshot?.step || '关卡已搭建', detail: '场景版本 ' + event.snapshot?.revision + ' · ' + event.snapshot?.objects?.length + ' 个真实对象', status: 'saved' };
  else if (event.type === 'code_write') data = { kind: 'file', stage: 'build', title: event.created ? '新内容已保存' : '游戏内容已更新', detail: event.step || event.file, file: event.file, sourceRevision: event.sourceRevision || workflow.sourceRevision, status: 'saved' };
  else if (event.type === 'test_start') data = { kind: 'test', stage: 'verify', title: '开始第 ' + event.run + ' 次玩法验证', status: 'running' };
  else if (event.type === 'test' || event.type === 'eval') data = { kind: event.type, stage: 'verify', title: event.type === 'test' ? event.ok ? '玩法验证通过' : '发现问题，准备修复' : event.ok ? '实际试玩画面已回传' : '实际试玩发现问题', detail: event.step || (event.checks?.length ? event.checks.filter(c => c.ok).length + '/' + event.checks.length + ' 项检查通过' : ''), status: event.ok ? 'passed' : 'failed', image: /^\/covers\/[\w.-]+$/.test(event.shot || '') ? event.shot : undefined };
  else if (event.type === 'asset' && ['ready', 'failed'].includes(event.state)) data = { kind: 'asset', stage: 'build', title: event.state === 'ready' ? event.async ? '正式美术已替换铅笔稿' : '素材已准备好' : '素材暂未完成', detail: event.name || event.id, status: event.state };
  else if (event.type === 'art' && artTitles[event.state]) {
    key = `art:${event.seq}`;
    data = { kind: 'art', stage: 'build', title: artTitles[event.state], detail: event.error || event.note || (event.queued ? '已开始绘制 ' + event.queued.length + ' 个美术位' : event.slots ? '找到 ' + event.slots + ' 个待上色的铅笔美术位' : event.style || ''), status: event.state === 'failed' ? 'failed' : event.state === 'verified' ? event.ok ? 'passed' : 'failed' : 'running', image: /^\/(covers|assets)\/[\w.-]+$/.test(event.image || '') ? event.image : undefined };
  }
  else if (event.type === 'ops') {
    const pack = event.ops?.find(op => op.op === 'pck');
    if (pack) { key = `build:${pack.buildId}`; data = { kind: 'build', stage: 'verify', title: '新试玩包已生成', detail: '点击试玩可打开此版本' + (pack.label ? ' · ' + pack.label : ''), status: 'built' }; }
  } else if (event.type === 'workflow') {
    // A compacted activity feed must not rediscover old evidence as a fresh success.
    const seen = new Set(workflow.activityEvidenceIds || []);
    const evidence = workflow.evidence?.findLast(e => !seen.has(e.id) && (!workflow.startedAt || e.at >= workflow.startedAt));
    workflow.activityEvidenceIds = [...new Set([...seen, ...(workflow.evidence || []).map(e => e.id)])].slice(-200);
    if (evidence && evidenceTitles[evidence.kind]) { recordedAt = evidence.at || recordedAt; key = `evidence:${evidence.id}`; data = { kind: evidence.kind, stage: 'verify', title: evidenceTitles[evidence.kind] + (evidence.ok ? '通过' : '未通过'), status: evidence.ok ? 'passed' : 'failed', sourceRevision: evidence.sourceRevision, detail: evidence.kind === 'preview' ? '首帧确认，玩法验收另行记录' : evidence.checks?.length ? evidence.checks.filter(c => c.ok).length + '/' + evidence.checks.length + ' 项检查通过' : '' }; }
  } else if (event.type === 'turn_end') {
    data = { kind: 'handoff', stage: ['completed', 'ready'].includes(event.status) ? 'review' : 'paused', title: event.status === 'completed' ? '这一轮已完成，交给你试玩' : event.status === 'ready' ? '本地验收通过，等待窗口确认' : workflow.iteration?.reason === 'deadline' ? '已到本轮时限，成果已保留' : '这一轮已保存，待继续处理', status: event.status };
  }
  if (!data || same(rows, key)) return null;
  const item = { id: `${workflow.id}:${event.seq}`, key: tidy(key, 300), at: recordedAt, ...Object.fromEntries(Object.entries(data).filter(([, v]) => v !== undefined).map(([k, v]) => [k, tidy(v, k === 'image' ? 240 : k === 'title' ? 120 : 220)])) };
  rows.push(item);
  if (rows.length > 60) rows.splice(0, rows.length - 60);
  return item;
}

/** Clients choose a tier (demo | quality), never a raw duration or the execution cap. */
export function requestedIterationOptions(value, isFirst, startedAt = Date.now()) {
  const tier = tierOf(value?.tier);
  return { kind: isFirst ? 'demo' : 'iteration', tier, targetMs: TIERS[tier].targetMs, startedAt };
}
