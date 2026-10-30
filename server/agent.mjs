// Company AiGate gateway. OpenAI Chat Completions at https://aigate.mini1.cn/v1.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { SYSTEM, TOOLS } from './prompt.mjs';
import { parseLooseJson } from './json.mjs';
import { MODEL_SETTINGS } from './model-config.mjs';
import { messagesForModel } from './message-adapter.mjs';
import { usesChatProtocol, usesResponsesProtocol, gatewayUrls, chatRequest, chatEvents, responsesRequest, responsesEvents } from './chat-adapter.mjs';

const GATEWAY = process.env.AIGATE_URL || 'https://aigate.mini1.cn/v1';
export const MODEL = MODEL_SETTINGS.model;
// Gateway 502 bursts last tens of seconds; 2+4+8+16 s of backoff rides them out.
const MAX_ATTEMPTS = 5;
// Each stalled attempt already waited a full idle timeout.
const IDLE_ATTEMPTS = 3;
const RETRY_BASE_MS = 2000;
const TOOL_RESULT_LIMIT = 8000;
export const INTERRUPTED_NOTE = '\n\n（和 AI 的连接中断了，这一轮先搭到这里。已经搭好的内容都保留着，你可以说"继续"让我接着做。）';

export function apiKey() {
  if (process.env.AIGATE_API_KEY) return process.env.AIGATE_API_KEY;
  try {
    const t = fs.readFileSync(path.join(os.homedir(), '.dsh', '.credentials.yaml'), 'utf8');
    const m = t.match(/AIGATE_API_KEY:\s*['"]?([^'"\s]+)/);
    if (m) return m[1];
  } catch { /* fall through to the explicit error */ }
  throw new Error('AIGATE_API_KEY not configured');
}

/** A gateway/stream failure; retryable ones are 429, 5xx, overload and dropped connections. */
export class GatewayError extends Error {
  constructor(message, { status = 0, retryable = false } = {}) {
    super(message);
    this.name = 'GatewayError';
    this.status = status;
    this.retryable = retryable;
  }
}

export const isRetryableStatus = status => status === 429 || status === 529 || status >= 500;

/** Retry classification for errors thrown while requesting or reading a stream. */
export function isRetryableError(err, signal) {
  if (signal && signal.aborted) return false;
  if (err instanceof GatewayError) return err.retryable;
  return err instanceof Error; // fetch/network/body read failures
}

/** Data payloads of one SSE block ("event: x\ndata: {...}"), joined per the SSE spec. */
export function parseSseBlock(block) {
  const data = block.split(/\r?\n/).filter(l => l.startsWith('data:')).map(l => l.slice(5).replace(/^ /, '')).join('\n').trim();
  if (!data || data === '[DONE]') return null;
  return parseLooseJson(data);
}

/** Yields parsed SSE events from a byte stream (any async iterable of Uint8Array/string). */
export async function* sse(body, { onChunk } = {}) {
  const dec = new TextDecoder();
  let buf = '';
  for await (const chunk of body) {
    if (chunk?.length || chunk?.byteLength) onChunk?.();
    buf += typeof chunk === 'string' ? chunk : dec.decode(chunk, { stream: true });
    buf = buf.replace(/\r\n/g, '\n');
    let i;
    while ((i = buf.indexOf('\n\n')) >= 0) {
      const ev = parseSseBlock(buf.slice(0, i));
      buf = buf.slice(i + 2);
      if (ev) yield ev;
    }
  }
  const tail = parseSseBlock(buf);
  if (tail) yield tail;
}

/** Tool input from streamed JSON: tolerant parse, or a marker the loop reports back to the model. */
export function parseToolInput(json) {
  if (!json) return {};
  const v = parseLooseJson(json);
  return v && typeof v === 'object' && !Array.isArray(v) ? v : { __bad_json: json.slice(0, 2000) };
}

/** Assemble the final content blocks of a streamed message. */
export function finalizeBlocks(blocks) {
  return blocks.filter(Boolean).map(b => {
    if (b.type === 'tool_use') return { type: 'tool_use', id: b.id, name: b.name, input: parseToolInput(b._json) };
    if (b.type === 'text') return { type: 'text', text: b.text };
    if (b.type === 'thinking') return { type: 'thinking', thinking: b.thinking || '', signature: b.signature || '' };
    return b;
  }).filter(b => !(b.type === 'text' && !b.text));
}

export async function postMessages(body, signal, fetchImpl = fetch, { chat = false, responses = false } = {}) {
  let res;
  try {
    const endpoints = gatewayUrls(GATEWAY);
    const url = responses ? endpoints.responses : chat ? endpoints.chat : endpoints.messages;
    const openai = chat || responses;
    res = await fetchImpl(url, {
      method: 'POST', signal,
      headers: openai ? { 'content-type': 'application/json', authorization: 'Bearer ' + apiKey() } : { 'content-type': 'application/json', 'x-api-key': apiKey(), 'anthropic-version': '2023-06-01' },
      body: JSON.stringify(body),
    });
  } catch (e) {
    if (signal && signal.aborted) throw e;
    throw new GatewayError('无法连接 AI 服务：' + (e.message || e), { retryable: true });
  }
  if (!res.ok) {
    const t = await res.text().catch(() => '');
    throw new GatewayError('AI 服务返回 ' + res.status + '：' + t.slice(0, 300), { status: res.status, retryable: isRetryableStatus(res.status) });
  }
  return res;
}

/**
 * One streamed assistant message. Callbacks: onText(delta), onToolStart(id,name), onToolDelta(id, partialJson).
 * Errors carry .emitted = true when any delta already reached the user (such turns must not be retried).
 */
async function streamOnce(messages, cb, signal, fetchImpl, req = {}, idleTimeoutMs = 0) {
  const model = req.model || MODEL;
  const body = { model, max_tokens: req.max_tokens || 16000, system: req.system || SYSTEM, tools: req.tools || TOOLS, messages: messagesForModel(messages, model), stream: true };
  if (req.tool_choice) body.tool_choice = req.tool_choice;
  if (req.thinking) body.thinking = req.thinking;
  if (req.output_config) body.output_config = req.output_config;
  const responses = usesResponsesProtocol(model);
  const chat = !responses && usesChatProtocol(model);
  const blocks = [];
  let stop = null;
  let emitted = false;
  // Limit silence, not the lifetime of a productive streamed answer. A long tool argument
  // can take several minutes; every nonempty byte chunk renews the inactivity deadline.
  const idleMs = Number.isFinite(idleTimeoutMs) && idleTimeoutMs > 0 ? idleTimeoutMs : 0;
  const idle = idleMs ? new AbortController() : null;
  const requestSignal = idle ? (signal ? AbortSignal.any([signal, idle.signal]) : idle.signal) : signal;
  let idleTimer;
  const activity = () => {
    if (!idle || requestSignal.aborted) return;
    clearTimeout(idleTimer);
    idleTimer = setTimeout(() => idle.abort(Object.assign(new GatewayError('连接连续 ' + Math.ceil(idleMs / 1000) + ' 秒没有进展', { retryable: true }), { code: 'STREAM_IDLE_TIMEOUT' })), idleMs);
  };
  try {
    activity();
    const wire = responses ? responsesRequest(body) : chat ? chatRequest(body) : body;
    const res = await postMessages(wire, requestSignal, fetchImpl, { chat, responses });
    activity();
    const events = sse(res.body, { onChunk: activity });
    const parsed = responses ? responsesEvents(events) : chat ? chatEvents(events) : events;
    for await (const ev of parsed) {
      if (ev.type === 'message_start') {
        cb.onModel?.({ requestedModel: model, responseModel: typeof ev.message?.model === 'string' ? ev.message.model.slice(0, 128) : '' });
      } else if (ev.type === 'content_block_start') {
        const b = { ...ev.content_block };
        if (b.type === 'tool_use') { b._json = ''; emitted = true; cb.onToolStart?.(b.id, b.name); }
        if (b.type === 'text') b.text = b.text || '';
        blocks[ev.index] = b;
      } else if (ev.type === 'content_block_delta') {
        const b = blocks[ev.index];
        if (!b || !ev.delta) continue;
        if (ev.delta.type === 'text_delta') { b.text += ev.delta.text; emitted = true; cb.onText?.(ev.delta.text); }
        else if (ev.delta.type === 'input_json_delta') { b._json += ev.delta.partial_json; cb.onToolDelta?.(b.id, b._json); }
        else if (ev.delta.type === 'tool_name_delta') { b.name = ev.delta.name; }
        else if (ev.delta.type === 'thinking_delta') { b.thinking = (b.thinking || '') + ev.delta.thinking; if (ev.delta.thinking) cb.onThinking?.(ev.delta.thinking); }
        else if (ev.delta.type === 'signature_delta') { b.signature = (b.signature || '') + ev.delta.signature; }
      } else if (ev.type === 'message_delta') {
        if (ev.delta?.stop_reason) stop = ev.delta.stop_reason;
      } else if (ev.type === 'error') {
        const type = ev.error?.type || '';
        throw new GatewayError('AI 服务流错误：' + (ev.error?.message || type || 'unknown'), { retryable: /overloaded|api_error|rate_limit/.test(type) });
      }
    }
    if (!stop) throw new GatewayError('AI 回复中途断开', { retryable: true });
  } catch (e) {
    if (idle?.signal.aborted && !signal?.aborted) e = idle.signal.reason;
    e.emitted = emitted;
    e.partial = blocks;
    throw e;
  } finally { clearTimeout(idleTimer); }
  return { content: finalizeBlocks(blocks), stop };
}

/**
 * Streamed turn with retries: 429/5xx/network failures are retried (exponential backoff) as long as
 * nothing has been shown to the user yet. A failure after visible output returns { interrupted } with
 * the text already streamed, so the caller can end the turn gracefully.
 */
export async function streamTurn(messages, cb, signal, { fetchImpl = fetch, sleep = defaultSleep, req, idleTimeoutMs = 0 } = {}) {
  for (let attempt = 0; ; attempt++) {
    try {
      return await streamOnce(messages, cb, signal, fetchImpl, req, idleTimeoutMs);
    } catch (e) {
      if (signal && signal.aborted) throw e;
      if (e.emitted) {
        const text = (e.partial || []).filter(b => b && b.type === 'text' && b.text).map(b => b.text).join('');
        return { content: text ? [{ type: 'text', text }] : [], stop: 'interrupted', interrupted: e };
      }
      const max = e.code === 'STREAM_IDLE_TIMEOUT' ? IDLE_ATTEMPTS : MAX_ATTEMPTS;
      if (attempt >= max - 1 || !isRetryableError(e, signal)) throw e;
      await sleep(RETRY_BASE_MS * 2 ** attempt);
    }
  }
}

const defaultSleep = ms => new Promise(r => setTimeout(r, ms));

/** tool_result content: JSON, shortened with a marker instead of being cut mid-token. */
export function toolResultContent(result) {
  // results that carry images (e.g. a rendered screenshot) become text + image blocks
  if (result && Array.isArray(result.__blocks)) return result.__blocks;
  const s = JSON.stringify(result ?? null);
  if (s.length <= TOOL_RESULT_LIMIT) return s;
  return s.slice(0, TOOL_RESULT_LIMIT) + ' …（结果过长已截断）';
}

/** Run one tool call; any exception (or bad input) becomes an error result for the model. */
export async function runTool(exec, u) {
  try {
    if (u.input && u.input.__bad_json) throw new Error('工具参数 JSON 不完整（可能太长被截断），请把这一批拆小重新调用');
    const result = await exec(u.name, u.input || {}, u.id);
    return { result, isError: !!(result && result.error) };
  } catch (e) {
    return { result: { error: String((e && e.message) || e) }, isError: true };
  }
}

/**
 * Runs the tool loop until the model stops calling tools or calls finish.
 * exec(name, input, id) -> Promise<result object>. deps: { fetchImpl, sleep } for tests.
 */
export async function runAgent({ messages, cb, exec, signal, maxTurns = 24, deps = {}, finishTools = ['finish'], req, until, beforeTurn, idleTimeoutMs = 0 }) {
  for (let turn = 0; turn < maxTurns; turn++) {
    if (until?.()) return { done: false, stopped: true };
    await beforeTurn?.(messages);
    const { content, stop, interrupted } = await streamTurn(messages, cb, signal, { idleTimeoutMs, ...deps, req: deps.req || req });
    if (interrupted) {
      cb.onText?.(INTERRUPTED_NOTE);
      messages.push({ role: 'assistant', content: [{ type: 'text', text: (content.map(b => b.text).join('') || '') + INTERRUPTED_NOTE }] });
      return { done: false, interrupted: true, error: interrupted };
    }
    messages.push({ role: 'assistant', content: content.length ? content : [{ type: 'text', text: '…' }] });
    const uses = content.filter(b => b.type === 'tool_use');
    if (!uses.length) return { done: true };
    const results = [];
    let finished = false;
    for (const u of uses) {
      const { result, isError } = await runTool(exec, u);
      if (finishTools.includes(u.name) && !isError) finished = true;
      results.push({ type: 'tool_result', tool_use_id: u.id, content: toolResultContent(result), ...(isError ? { is_error: true } : {}) });
    }
    messages.push({ role: 'user', content: results });
    if (finished) return { done: true };
    if (stop === 'max_tokens') cb.onText?.('');
  }
  return { done: false };
}

// Strip thinking blocks + compact old turns so history stays small across iterations.
export function compactHistory(messages, keepRecent = 12) {
  const out = messages.map(m => ({ ...m, content: Array.isArray(m.content) ? m.content.filter(b => b.type !== 'thinking') : m.content }));
  if (out.length <= keepRecent) return out;
  const old = out.slice(0, out.length - keepRecent);
  const recent = out.slice(out.length - keepRecent);
  // ensure recent starts with a user plain-text message (not tool_result)
  while (recent.length && !(recent[0].role === 'user' && (typeof recent[0].content === 'string' || recent[0].content.some(b => b.type === 'text')))) {
    old.push(recent.shift());
  }
  const summary = old.filter(m => m.role === 'user' && (typeof m.content === 'string' || m.content.some(b => b.type === 'text')))
    .map(m => '- ' + (typeof m.content === 'string' ? m.content : m.content.filter(b => b.type === 'text').map(b => b.text).join(' ')).slice(0, 200)).join('\n');
  return [{ role: 'user', content: '（较早的对话已折叠。用户之前提过的要求：\n' + summary + '）' }, { role: 'assistant', content: '好的，我记得这些要求。' }, ...recent];
}
