/** Independent task workers stage text changes in memory; only the coordinator commits them. */
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { runAgent } from './agent.mjs';
import { CODE_MODEL } from './codegen.mjs';
import { safePath, scanIssues } from './gproject.mjs';

const MAX_TASKS = 2;
const MAX_FILE_CHARS = 200000;
const MAX_CANDIDATE_CHARS = 600000;
const TEXT_EXT = new Set(['gd', 'tscn', 'tres', 'gdshader', 'gdshaderinc', 'godot', 'cfg', 'json', 'txt', 'md', 'csv']);
const terminal = new Set(['applied', 'failed', 'blocked', 'cancelled']);
const clean = (v, max = 1200) => String(v ?? '').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '').slice(0, max);
const TRACE_LIMIT = 40;
const diagnosticText = (value, max = 500) => clean(String(value?.message ?? value ?? '').slice(0, 20000)
  .replace(/\u001b\[[0-?]*[ -/]*[@-~]/g, '')
  .replace(/-----BEGIN [^-]*PRIVATE KEY-----[\s\S]*?(?:-----END [^-]*PRIVATE KEY-----|$)/g, '[REDACTED PRIVATE KEY]')
  .replace(/\bBearer\s+[^\s"'<>]+/gi, 'Bearer [REDACTED]')
  .replace(/\b(?:sk|pk)-[A-Za-z0-9_-]{12,}\b/g, '[REDACTED KEY]')
  .replace(/(\b(?:authorization|proxy-authorization|api[_-]?key|access[_-]?token|refresh[_-]?token|token|password|secret)\b["']?\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;&]+)/gi, '$1[REDACTED]')
  .replace(/https?:\/\/[^\s"'<>]+/gi, value => { try { return new URL(value).origin + '/[REDACTED URL]'; } catch { return '[REDACTED URL]'; } }), max);

function workerEnd(result, submitted) {
  let reason = submitted ? 'submitted' : 'no_submit';
  if (result?.interrupted) reason = 'interrupted';
  else if (result?.stopped) reason = 'stopped';
  else if (result?.error || result?.ok === false) reason = 'worker_error';
  else if (result?.done === false) reason = 'turn_limit';
  const error = diagnosticText(result?.error || (result?.interrupted !== true ? result?.interrupted : ''));
  return { reason, ...(typeof result?.done === 'boolean' ? { done: result.done } : {}), ...(error ? { error } : {}) };
}

function workerFailure(end) {
  const message = {
    interrupted: '任务执行中断', turn_limit: '任务达到最大执行轮次，尚未完成交付',
    stopped: '任务执行提前停止', worker_error: '任务执行失败',
    no_submit: '执行者结束但没有 submit_task，任务未交付',
  }[end.reason];
  return message ? message + (end.error ? '：' + end.error : '') : '';
}

export const DELEGATE_TASKS_TOOL = {
  name: 'delegate_tasks',
  description: '并行委派独立开发或只读审查任务。任务在候选区工作，依赖成功后才能启动；每个可写文件只能归属一个任务。合入不等于整体验收，通过后仍需主任务运行和测试最新工程。',
  input_schema: {
    type: 'object', required: ['tasks'], additionalProperties: false,
    properties: { tasks: { type: 'array', minItems: 1, maxItems: MAX_TASKS, items: {
      type: 'object', required: ['id', 'title', 'role', 'files', 'depends_on', 'prompt', 'acceptance'], additionalProperties: false,
      properties: {
        id: { type: 'string', pattern: '^[A-Za-z0-9_-]{1,48}$' },
        title: { type: 'string', maxLength: 80 },
        role: { type: 'string', enum: ['gameplay', 'scene', 'review'] },
        files: { type: 'array', maxItems: 2, items: { type: 'string' }, description: '最多 1–2 个小文件的精确路径；review 可为空且始终只读。' },
        depends_on: { type: 'array', maxItems: 1, items: { type: 'string' } },
        prompt: { type: 'string', maxLength: 6000 },
        acceptance: { type: 'array', minItems: 1, maxItems: 12, items: { type: 'string', maxLength: 300 } },
      },
    } } },
  },
};

const WORKER_TOOLS = [
  { name: 'read_file', description: '读取任务开始时的工程快照或自己的候选内容。', input_schema: { type: 'object', required: ['path'], properties: { path: { type: 'string' }, offset: { type: 'integer' }, limit: { type: 'integer' } } } },
  { name: 'list_files', description: '列出快照及自己的候选文件。', input_schema: { type: 'object', properties: {} } },
  { name: 'grep_files', description: '在快照和自己的候选中搜索纯文本。', input_schema: { type: 'object', required: ['pattern'], properties: { pattern: { type: 'string' }, path: { type: 'string' } } } },
  { name: 'write_file', description: '将允许列表内的文本文件写入内存候选区，不修改正式工程。', input_schema: { type: 'object', required: ['path', 'content'], properties: { path: { type: 'string' }, content: { type: 'string' } } } },
  { name: 'patch_file', description: '在候选区唯一替换 old 文本。', input_schema: { type: 'object', required: ['path', 'old', 'new'], properties: { path: { type: 'string' }, old: { type: 'string' }, new: { type: 'string' } } } },
  { name: 'submit_task', description: '提交候选和逐项实现证据。这是任务交付，不代表运行测试或整体验收通过。', input_schema: { type: 'object', required: ['summary', 'acceptance'], properties: {
    summary: { type: 'string' }, acceptance: { type: 'array', items: { type: 'object', required: ['criterion', 'evidence', 'passed'], properties: { criterion: { type: 'string' }, evidence: { type: 'string' }, passed: { type: 'boolean' } } } },
  } } },
];

function normalizedPath(value) {
  if (typeof value !== 'string') throw new Error('文件路径必须是字符串');
  const rel = value.trim().replace(/\\/g, '/').replace(/^res:\/\//i, '').replace(/^\.\//, '');
  if (rel.split('/').some(s => !s || s === '.' || s === '..' || s.startsWith('.') || /[. ]$/.test(s) || /^(con|prn|aux|nul|com\d|lpt\d)(\.|$)/i.test(s))) throw new Error('无效文件路径：' + clean(value, 120));
  safePath(rel.toLowerCase()); // Protect platform paths on case-insensitive filesystems too.
  if (!TEXT_EXT.has(path.posix.extname(rel).slice(1).toLowerCase())) throw new Error('只能委派可编辑文本文件：' + rel);
  return rel;
}

function snapshotOf(project) {
  const sources = project.sources();
  const files = new Map();
  for (const [p, text] of Object.entries(sources)) {
    if (typeof text !== 'string') continue;
    const rel = normalizedPath(p), key = rel.toLowerCase();
    if (files.has(key)) throw new Error('工程有大小写冲突文件：' + rel);
    files.set(key, { path: rel, content: text });
  }
  return files;
}

function normalizeTasks(input) {
  if (!Array.isArray(input) || !input.length || input.length > MAX_TASKS) throw new Error('tasks 必须包含 1–2 个小任务');
  const ids = new Set(), owners = new Map();
  const tasks = input.map(t => {
    if (!t || typeof t !== 'object' || typeof t.id !== 'string' || !/^[A-Za-z0-9_-]{1,48}$/.test(t.id) || ids.has(t.id)) throw new Error('任务 id 无效或重复');
    ids.add(t.id);
    if (!['gameplay', 'scene', 'review'].includes(t.role)) throw new Error('任务角色无效：' + t.id);
    if (typeof t.title !== 'string' || !t.title.trim() || t.title.length > 80 || typeof t.prompt !== 'string' || !t.prompt.trim() || t.prompt.length > 6000) throw new Error('任务标题或说明无效：' + t.id);
    if (!Array.isArray(t.files) || t.files.length > 2 || (t.role !== 'review' && !t.files.length)) throw new Error('任务文件允许列表无效（最多 2 个小文件）：' + t.id);
    if (!Array.isArray(t.depends_on) || t.depends_on.length > 1 || t.depends_on.some(x => typeof x !== 'string')) throw new Error('任务依赖无效：' + t.id);
    if (!Array.isArray(t.acceptance) || !t.acceptance.length || t.acceptance.length > 12 || t.acceptance.some(x => typeof x !== 'string' || !x.trim() || x.length > 300)) throw new Error('任务验收项无效：' + t.id);
    const files = t.files.map(normalizedPath), seen = new Set();
    for (const p of files) {
      const key = p.toLowerCase();
      if (seen.has(key)) throw new Error('任务文件重复：' + p);
      seen.add(key);
      if (t.role !== 'review') {
        if (owners.has(key)) throw new Error('文件归属冲突：' + p + '（' + owners.get(key) + ' / ' + t.id + '）');
        owners.set(key, t.id);
      }
    }
    return { id: t.id, title: clean(t.title, 80), role: t.role, files, depends_on: [...new Set(t.depends_on)], prompt: t.prompt, acceptance: [...new Set(t.acceptance)] };
  });
  const byId = new Map(tasks.map(t => [t.id, t])), visiting = new Set(), visited = new Set();
  function visit(id) {
    if (visiting.has(id)) throw new Error('任务依赖形成循环：' + id);
    if (visited.has(id)) return;
    visiting.add(id);
    for (const dep of byId.get(id).depends_on) {
      if (!byId.has(dep)) throw new Error('依赖不存在：' + dep);
      visit(dep);
    }
    visiting.delete(id); visited.add(id);
  }
  tasks.forEach(t => visit(t.id));
  return tasks;
}

function metadata(t) {
  return { id: t.id, title: t.title, role: t.role, status: 'queued', files: [...t.files], depends_on: [...t.depends_on],
    summary: '', error: '', startedAt: null, finishedAt: null, changed: [], review_only: t.role === 'review', verified: false };
}

const abortError = signal => Object.assign(new Error(clean(signal.reason?.message || signal.reason || '任务已取消', 500)), { name: 'AbortError' });
function throwAborted(signal) { if (signal.aborted) throw abortError(signal); }
function abortable(promise, signal) {
  if (signal.aborted) return Promise.reject(abortError(signal));
  return new Promise((resolve, reject) => {
    const stop = () => reject(abortError(signal));
    signal.addEventListener('abort', stop, { once: true });
    Promise.resolve(promise).then(resolve, reject).finally(() => signal.removeEventListener('abort', stop));
  });
}

function workerPrompt(task, game, snapshot, dependencies) {
  const listing = [...snapshot.values()].map(f => f.path).join('\n');
  let available = 40000;
  const content = [];
  for (const p of task.files) {
    const f = snapshot.get(p.toLowerCase());
    if (!f || f.content.length > available) continue;
    content.push('## ' + f.path + '\n' + f.content); available -= f.content.length;
  }
  const design = game?.design;
  const brief = design ? { title: clean(design.title, 80), core_loop: clean(design.core_loop), rules: (Array.isArray(design.rules) ? design.rules : []).slice(0, 30).map(x => clean(x, 400)), modules: (Array.isArray(design.modules) ? design.modules : []).slice(0, 30).map(m => ({ file: clean(m.file, 160), role: clean(m.role, 200), interface: clean(m.interface, 600) })) } : {};
  return '你是独立任务执行者。只完成此小任务，不扩展范围，最多两分半内一次提交完整候选；主任务负责整合。\n' + JSON.stringify({ task, design: brief, dependencies }, null, 2)
    + '\n工程文件（任务开始时的快照；前置任务已合入）：\n' + listing + '\n允许文件的已有内容：\n' + content.join('\n\n')
    + '\n需要时使用 read_file / grep_files。write_file / patch_file 仅保存内存候选；submit_task 必须逐项提供实现证据。你没有运行游戏或测试的工具，不要声称已经运行或已通过整体验收。';
}

export async function defaultRunWorker(ctx, agentRunner = runAgent) {
  const invoke = async maxTurns => {
    const result = await agentRunner({
      messages: ctx.messages, signal: ctx.signal, maxTurns, finishTools: ['submit_task'], idleTimeoutMs: 90000,
      until: () => ctx.signal.aborted,
      cb: { onToolStart: (_id, name) => ctx.onProgress({ tool: name }), onText: () => {}, onModel: value => ctx.onModel?.(value) },
      req: { model: ctx.model ?? CODE_MODEL, max_tokens: 16000, tools: ctx.tools, system: '你是游戏开发任务执行者。严格遵守精确文件允许列表。只用提供的工具。候选提交只证明实现已准备好，实际编译、试玩与整体需求验收由协调者进行。审查任务只读。全程使用简体中文。' },
      exec: ctx.exec,
    });
    ctx.onWorkerEnd?.(workerEnd(result, ctx.hasSubmission()));
    return result;
  };
  let result = await invoke(16);
  // Only a normal early answer can be reminded once. Failures are retained, never retried away.
  if (result?.done === true && !result.error && !result.interrupted && !result.stopped && !ctx.hasSubmission() && !ctx.signal.aborted) {
    ctx.onReminder?.();
    ctx.messages.push({ role: 'user', content: '你尚未调用 submit_task，因此候选没有交付。这是唯一一次续交提醒：继续检查已有候选，完成后调用 submit_task 并逐项提供实现证据；若未完成，明确把对应验收项标记 passed=false。不要仅口头宣布完成，也不要声称运行过游戏。' });
    result = await invoke(4);
  }
  return result;
}

/**
 * runWorker(ctx) is injectable, but must use ctx.exec to stage changes and submit_task.
 * Return values alone never mark a task submitted. Worker output is unverified until the
 * caller checks/tests the resulting project revision. No model call occurs with an injected worker.
 */
export async function runTaskBatch({ project, game = {}, tasks: input, signal, onTask = () => {}, artifactDir,
  runWorker = defaultRunWorker, maxConcurrency = 2, timeoutMs = 150000, deadlineAt = Infinity, model = CODE_MODEL } = {}) {
  let tasks;
  try {
    tasks = normalizeTasks(input);
    if (!project || typeof project.withLock !== 'function' || typeof project.sources !== 'function' || typeof project.write !== 'function' || typeof project.remove !== 'function') throw new Error('工程缺少共享锁或文件接口');
  } catch (e) {
    return { ok: false, tasks: [], changed: [], errors: [{ task_id: '', error: clean(e.message, 500) }] };
  }
  const controller = new AbortController();
  const abortParent = () => controller.abort(signal.reason || new Error('任务已取消'));
  if (signal?.aborted) abortParent(); else signal?.addEventListener('abort', abortParent, { once: true });
  const duration = Math.max(0, Math.min(Number.isFinite(timeoutMs) ? timeoutMs : 150000, 150000, deadlineAt - Date.now()));
  const batchDeadlineAt = Date.now() + duration;
  if (duration <= 0) controller.abort(new Error('协作任务可用时间已用完'));
  const timer = setTimeout(() => controller.abort(new Error('协作任务超时')), duration);
  const batchId = 'team-' + Date.now() + '-' + crypto.randomUUID().slice(0, 8);
  const artifactRoot = artifactDir || path.join(project.buildDir || path.join(os.tmpdir(), 'ugc-task-team'), 'tasks');
  const records = new Map(tasks.map(t => [t.id, metadata(t)]));
  const outputs = new Map(), active = new Map();
  const emit = record => { try { onTask(structuredClone(record)); } catch { /* UI failure must not mutate task outcome. */ } };
  const update = (id, values) => { const r = records.get(id); Object.assign(r, values); emit(r); return r; };
  const artifact = (task, record, snapshot, candidate, submission, diagnostics) => {
    try {
      const relative = batchId + '/' + task.id + '.json';
      const target = path.join(artifactRoot, ...relative.split('/'));
      fs.mkdirSync(path.dirname(target), { recursive: true });
      const { prompt, ...request } = task;
      fs.writeFileSync(target, JSON.stringify({ version: 2, task: record, request: { ...request, promptChars: prompt.length }, submission, diagnostics,
        baseline: Object.fromEntries([...candidate.keys()].map(k => [snapshot.get(k)?.path || candidate.get(k).path, snapshot.get(k)?.content ?? null])),
        candidate: Object.fromEntries([...candidate.values()].map(f => [f.path, f.content])),
      }, null, 2));
      record.artifact = relative;
      return true;
    } catch (e) { record.artifact_error = diagnosticText(e, 300); return false; }
  };
  for (const record of records.values()) emit(record);

  async function execute(task) {
    let snapshot = new Map(), candidate = new Map(), submission = null, closed = false;
    const record = records.get(task.id);
    const diagnostics = { toolCalls: 0, traceDropped: 0, reminders: 0, workerRuns: [], tools: [] };
    const keepTool = (name, input, result) => {
      if (closed) return;
      const row = { at: Date.now(), tool: WORKER_TOOLS.some(t => t.name === name) ? name : '[unknown]', ok: !result?.error };
      if (typeof input?.path === 'string') { try { row.path = normalizedPath(input.path); } catch { /* Do not store arbitrary invalid paths. */ } }
      if (result?.error) row.error = diagnosticText(result.error);
      if (Number.isSafeInteger(result?.chars)) row.chars = result.chars;
      if (result?.staged) row.staged = true;
      if (result?.submitted) row.submitted = true;
      diagnostics.toolCalls++;
      diagnostics.tools.push(row);
      if (diagnostics.tools.length > TRACE_LIMIT) { diagnostics.tools.shift(); diagnostics.traceDropped++; }
    };
    try {
      throwAborted(controller.signal);
      snapshot = await abortable(project.withLock(() => { throwAborted(controller.signal); return snapshotOf(project); }), controller.signal);
      task.files = task.files.map(p => snapshot.get(p.toLowerCase())?.path || p);
      update(task.id, { status: 'running', startedAt: Date.now(), files: [...task.files], base_revision: typeof project.revision === 'function' ? project.revision() : null });
      const allowed = new Set(task.files.map(p => p.toLowerCase()));
      let calls = 0;
      const get = p => candidate.get(p.toLowerCase()) || snapshot.get(p.toLowerCase());
      const stage = (rel, value) => {
        if (task.role === 'review' || !allowed.has(rel.toLowerCase())) throw new Error('文件不在任务可写范围：' + rel);
        if (typeof value !== 'string') throw new Error('文件内容必须是字符串');
        const content = value.replace(/\r\n/g, '\n');
        if (content.length > MAX_FILE_CHARS) throw new Error('候选文件超过 200000 字符');
        const issues = scanIssues(rel.toLowerCase(), content);
        if (issues.length) throw new Error(issues.slice(0, 8).join('\n'));
        const key = rel.toLowerCase(), p = snapshot.get(key)?.path || task.files.find(f => f.toLowerCase() === key);
        const count = [...candidate].reduce((n, [k, f]) => n + (k === key ? 0 : f.content.length), content.length);
        if (count > MAX_CANDIDATE_CHARS) throw new Error('任务候选总量超过 600000 字符');
        candidate.set(key, { path: p, content });
        return { ok: true, staged: true, path: p, chars: content.length, note: '仅候选区已保存，未编译或运行。' };
      };
      const perform = async (name, input = {}) => {
        try {
          throwAborted(controller.signal);
          if (closed || submission) throw new Error('任务已提交或关闭');
          if (++calls > 100) throw new Error('任务工具调用达到上限');
          if (!WORKER_TOOLS.some(t => t.name === name)) throw new Error('未知或未授权工具：' + clean(name, 80));
          if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('工具参数必须是对象');
          if (name === 'list_files') return { files: [...new Set([...snapshot.values(), ...candidate.values()].map(f => f.path))] };
          if (name === 'submit_task') {
            if (typeof input.summary !== 'string' || !input.summary.trim() || input.summary.length > 1600) throw new Error('提交需要简短 summary');
            if (!Array.isArray(input.acceptance) || input.acceptance.length > 12) throw new Error('提交需要逐项 acceptance 证据');
            const evidence = task.acceptance.map(criterion => {
              const row = input.acceptance.find(a => a && a.criterion === criterion);
              if (!row || typeof row.evidence !== 'string' || !row.evidence.trim() || row.evidence.length > 1200 || typeof row.passed !== 'boolean') throw new Error('验收项缺少明确结果或实现证据：' + criterion);
              return { criterion, evidence: clean(row.evidence), passed: row.passed, verified: false };
            });
            if (task.role !== 'review' && evidence.every(e => e.passed) && ![...candidate].some(([k, f]) => snapshot.get(k)?.content !== f.content)) throw new Error('开发任务没有候选变更，不能仅口头提交');
            submission = { summary: clean(input.summary, 1600), acceptance: evidence };
            return { ok: true, submitted: true, verified: false };
          }
          if (name === 'grep_files') {
            if (typeof input.pattern !== 'string' || !input.pattern || input.pattern.length > 200) throw new Error('搜索词长度必须为 1–200');
            const only = input.path ? normalizedPath(input.path).toLowerCase() : null;
            const merged = new Map([...snapshot, ...candidate]), hits = [];
            for (const [key, f] of merged) {
              if (only && key !== only) continue;
              f.content.split('\n').forEach((line, i) => { if (hits.length < 60 && line.toLowerCase().includes(input.pattern.toLowerCase())) hits.push({ path: f.path, line: i + 1, text: line.slice(0, 180) }); });
            }
            return { matches: hits };
          }
          const rel = normalizedPath(input.path), f = get(rel);
          if (name === 'read_file') {
            if (!f) throw new Error('快照中没有此文件：' + rel);
            const lines = f.content.split('\n'), start = Math.max(0, Math.floor(Number(input.offset) || 1) - 1), count = Math.min(300, Math.max(1, Math.floor(Number(input.limit) || 120)));
            return { path: f.path, total_lines: lines.length, text: lines.slice(start, start + count).map((l, i) => (start + i + 1) + ': ' + l).join('\n').slice(0, 12000) };
          }
          if (name === 'write_file') return stage(rel, input.content);
          if (!f || typeof input.old !== 'string' || !input.old) throw new Error('patch_file 需要已有文件和非空 old');
          const old = input.old.replace(/\r\n/g, '\n');
          if (f.content.split(old).length !== 2) throw new Error('old 必须唯一匹配');
          if (typeof input.new !== 'string') throw new Error('new 必须是字符串');
          return stage(rel, f.content.replace(old, () => input.new.replace(/\r\n/g, '\n')));
        } catch (e) { return { error: diagnosticText(e, 1000) }; }
      };
      const exec = async (name, input = {}) => {
        const result = await perform(name, input);
        keepTool(name, input, result);
        return result;
      };
      const dependencies = task.depends_on.map(id => ({ ...structuredClone(records.get(id)), submission: outputs.get(id) || null }));
      const ctx = { model, task: structuredClone(task), messages: [{ role: 'user', content: workerPrompt(task, game, snapshot, dependencies) }],
        tools: structuredClone(WORKER_TOOLS.filter(t => task.role !== 'review' || !['write_file', 'patch_file'].includes(t.name))), exec, signal: controller.signal,
        projectSnapshot: Object.fromEntries([...snapshot.values()].map(f => [f.path, f.content])), dependencies,
        onProgress: value => { if (!closed && !controller.signal.aborted) update(task.id, { last_tool: WORKER_TOOLS.some(t => t.name === value?.tool) ? value.tool : '[unknown]' }); },
        onModel: value => {
          if (!closed && !controller.signal.aborted) update(task.id, { model: {
            requestedModel: typeof value?.requestedModel === 'string' ? clean(value.requestedModel, 128) : '',
            responseModel: typeof value?.responseModel === 'string' ? clean(value.responseModel, 128) : '',
          } });
        },
        hasSubmission: () => submission !== null, deadlineAt: batchDeadlineAt,
        onWorkerEnd: end => {
          if (!closed && diagnostics.workerRuns.length < 2) diagnostics.workerRuns.push({
            reason: ['submitted', 'interrupted', 'turn_limit', 'stopped', 'worker_error', 'no_submit'].includes(end?.reason) ? end.reason : 'worker_error',
            ...(typeof end?.done === 'boolean' ? { done: end.done } : {}),
            ...(end?.error ? { error: diagnosticText(end.error) } : {}), at: Date.now(),
          });
        },
        onReminder: () => { if (!closed) diagnostics.reminders = 1; },
      };
      const result = await abortable(Promise.resolve().then(() => runWorker(ctx)), controller.signal);
      closed = true;
      throwAborted(controller.signal);
      record.worker_end = workerEnd(result, submission !== null);
      if (!diagnostics.workerRuns.length) diagnostics.workerRuns.push({ ...record.worker_end, at: Date.now() });
      const failure = workerFailure(record.worker_end);
      if (failure) throw new Error(failure);
      if (submission.acceptance.some(a => !a.passed)) throw new Error('提交包含未完成项：' + submission.acceptance.filter(a => !a.passed).map(a => a.criterion).join(', '));
      if (!artifact(task, record, snapshot, candidate, submission, diagnostics)) throw new Error('不能保存候选现场，未合入：' + record.artifact_error);
      const changed = [...candidate].filter(([k, f]) => snapshot.get(k)?.content !== f.content);
      await abortable(project.withLock(async () => {
        throwAborted(controller.signal);
        const current = snapshotOf(project);
        for (const [key, f] of changed) if ((current.get(key)?.content ?? null) !== (snapshot.get(key)?.content ?? null)) throw new Error('候选基线冲突，正式文件已变化：' + f.path);
        if (project.list && project.list().length + changed.filter(([key]) => !current.has(key)).length > 120) throw new Error('合入后工程文件数量超过 120');
        const oldState = project.state == null ? null : structuredClone(project.state), attempted = [];
        try {
          for (const [key, f] of changed) {
            throwAborted(controller.signal);
            attempted.push([key, f]);
            const issues = project.write(f.path, f.content);
            if (!Array.isArray(issues) || issues.length) throw new Error('合入失败：' + f.path + ' ' + (Array.isArray(issues) ? issues.join('; ') : 'write 接口返回值无效'));
          }
          throwAborted(controller.signal);
        } catch (e) {
          const rollbackErrors = [];
          for (const [key, f] of attempted.reverse()) {
            try {
              const original = snapshot.get(key);
              const result = original ? project.write(original.path, original.content) : project.remove(f.path);
              if (original && result?.length) throw new Error(result.join('; '));
            } catch (rollbackError) { rollbackErrors.push(f.path + ': ' + clean(rollbackError.message, 120)); }
          }
          if (oldState != null) project.state = oldState;
          if (rollbackErrors.length) throw new Error(e.message + '；回滚错误：' + rollbackErrors.join('; '));
          throw e;
        }
      }), controller.signal);
      outputs.set(task.id, submission);
      Object.assign(record, { status: 'applied', changed: changed.map(([, f]) => f.path), summary: submission.summary, acceptance: submission.acceptance, finishedAt: Date.now(), revision: typeof project.revision === 'function' ? project.revision() : null });
    } catch (e) {
      if (!record.worker_end) record.worker_end = { reason: controller.signal.aborted ? 'cancelled' : 'worker_error', error: diagnosticText(e) };
      Object.assign(record, { status: controller.signal.aborted ? 'cancelled' : 'failed', error: diagnosticText(e, 1000), finishedAt: Date.now() });
      if (submission) Object.assign(record, { summary: submission.summary, acceptance: submission.acceptance });
    } finally {
      closed = true;
      artifact(task, record, snapshot, candidate, submission, diagnostics);
      emit(record);
    }
  }

  try {
    const concurrency = Math.max(1, Math.min(2, Math.floor(Number(maxConcurrency) || 2)));
    while ([...records.values()].some(r => !terminal.has(r.status))) {
      for (const task of tasks) {
        const r = records.get(task.id);
        if (r.status !== 'queued' || active.has(task.id)) continue;
        if (controller.signal.aborted) { update(task.id, { status: 'cancelled', error: clean(controller.signal.reason?.message || '任务已取消', 500), finishedAt: Date.now() }); continue; }
        const deps = task.depends_on.map(id => records.get(id));
        if (deps.some(d => terminal.has(d.status) && d.status !== 'applied')) { update(task.id, { status: 'blocked', error: '前置任务未成功：' + deps.filter(d => d.status !== 'applied').map(d => d.id).join(', '), finishedAt: Date.now() }); continue; }
        if (active.size >= concurrency || deps.some(d => d.status !== 'applied')) continue;
        const work = execute(task).finally(() => active.delete(task.id));
        active.set(task.id, work);
      }
      if (active.size) await Promise.race(active.values());
      else if ([...records.values()].some(r => !terminal.has(r.status))) throw new Error('任务调度无法继续');
    }
  } finally {
    clearTimeout(timer);
    signal?.removeEventListener('abort', abortParent);
  }
  const result = [...records.values()];
  return { ok: result.every(r => r.status === 'applied'), tasks: result,
    changed: [...new Set(result.flatMap(r => r.changed))], errors: result.filter(r => r.status !== 'applied').map(r => ({ task_id: r.id, error: r.error })) };
}
