import test from 'node:test';
import assert from 'node:assert/strict';

process.env.AIGATE_API_KEY = 'test-key';
const { runAgent, streamTurn, sse, parseSseBlock, parseToolInput, toolResultContent, runTool, compactHistory, isRetryableStatus, INTERRUPTED_NOTE } = await import('../agent.mjs');

const enc = new TextEncoder();
const sseText = events => events.map(e => 'event: ' + e.type + '\ndata: ' + JSON.stringify(e) + '\n\n').join('');

/** A fake Response whose body streams the given chunks, optionally failing mid-stream. */
function streamResponse(chunks, { failAfter = Infinity } = {}) {
  return {
    ok: true, status: 200,
    body: (async function* () {
      let i = 0;
      for (const c of chunks) {
        if (i++ >= failAfter) throw new TypeError('terminated');
        yield enc.encode(c);
      }
      if (failAfter !== Infinity) throw new TypeError('terminated');
    })(),
  };
}
const errorResponse = (status, text = 'busy') => ({ ok: false, status, text: async () => text });

const textEvents = text => [
  { type: 'message_start', message: {} },
  { type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } },
  { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text } },
  { type: 'content_block_stop', index: 0 },
  { type: 'message_delta', delta: { stop_reason: 'end_turn' } },
  { type: 'message_stop' },
];
const toolEvents = (id, name, json) => [
  { type: 'content_block_start', index: 0, content_block: { type: 'tool_use', id, name, input: {} } },
  { type: 'content_block_delta', index: 0, delta: { type: 'input_json_delta', partial_json: json.slice(0, 5) } },
  { type: 'content_block_delta', index: 0, delta: { type: 'input_json_delta', partial_json: json.slice(5) } },
  { type: 'message_delta', delta: { stop_reason: 'tool_use' } },
];

/** fetch stub replaying a scripted list of responses (or thrown errors). */
function scriptedFetch(script) {
  const calls = [];
  const fn = async (url, init) => {
    calls.push(JSON.parse(init.body));
    const next = script.shift();
    if (!next) throw new Error('unexpected extra request');
    if (next instanceof Error) throw next;
    return typeof next === 'function' ? next() : next;
  };
  fn.calls = calls;
  return fn;
}
const noSleep = { sleep: async () => {} };
const recorder = () => { const out = { text: '', tools: [] }; return { out, cb: { onText: d => { out.text += d; }, onToolStart: (id, n) => out.tools.push(n) } }; };

test('sse parser joins data lines, handles CRLF, split chunks and a trailing block', async () => {
  assert.deepEqual(parseSseBlock('event: x\ndata: {"a":\ndata: 1}'), { a: 1 });
  assert.equal(parseSseBlock('data: [DONE]'), null);
  const chunks = ['data: {"n":1}\r\n\r\nda', 'ta: {"n":2}\n\n', 'data: {"n":3}'];
  const got = [];
  for await (const ev of sse(chunks)) got.push(ev.n);
  assert.deepEqual(got, [1, 2, 3]);
});

test('parseToolInput is tolerant and flags truncated JSON', () => {
  assert.deepEqual(parseToolInput(''), {});
  assert.deepEqual(parseToolInput('{"a":[1,],}'), { a: [1] });
  assert.ok(parseToolInput('{"a":[1').__bad_json);
  assert.ok(parseToolInput('[1,2]').__bad_json, 'non-object input is rejected');
});

test('retryable statuses', () => {
  for (const s of [429, 500, 502, 503, 529]) assert.equal(isRetryableStatus(s), true);
  for (const s of [400, 401, 403, 404]) assert.equal(isRetryableStatus(s), false);
});

test('streamTurn retries 429/5xx/network failures before any output', async () => {
  const fetchImpl = scriptedFetch([errorResponse(429), new TypeError('fetch failed'), streamResponse([sseText(textEvents('你好'))])]);
  const { out, cb } = recorder();
  const r = await streamTurn([], cb, undefined, { fetchImpl, ...noSleep });
  assert.equal(fetchImpl.calls.length, 3);
  assert.deepEqual(r.content, [{ type: 'text', text: '你好' }]);
  assert.equal(r.stop, 'end_turn');
  assert.equal(out.text, '你好');
});

test('streamTurn gives up after 3 attempts with a readable error', async () => {
  const fetchImpl = scriptedFetch([errorResponse(503), errorResponse(502), errorResponse(500, 'down')]);
  await assert.rejects(streamTurn([], {}, undefined, { fetchImpl, ...noSleep }), /AI 服务返回 500：down/);
  assert.equal(fetchImpl.calls.length, 3);
});

test('streamTurn does not retry client errors', async () => {
  const fetchImpl = scriptedFetch([errorResponse(400, 'bad request')]);
  await assert.rejects(streamTurn([], {}, undefined, { fetchImpl, ...noSleep }), /400/);
  assert.equal(fetchImpl.calls.length, 1);
});

test('stream dropped before any output is retried', async () => {
  const fetchImpl = scriptedFetch([streamResponse([sseText([{ type: 'message_start', message: {} }])], { failAfter: 1 }), streamResponse([sseText(textEvents('ok'))])]);
  const r = await streamTurn([], {}, undefined, { fetchImpl, ...noSleep });
  assert.equal(fetchImpl.calls.length, 2);
  assert.equal(r.content[0].text, 'ok');
});

test('stream ending without a stop reason counts as dropped', async () => {
  const fetchImpl = scriptedFetch([streamResponse([sseText([{ type: 'message_start', message: {} }])]), streamResponse([sseText(textEvents('ok'))])]);
  await streamTurn([], {}, undefined, { fetchImpl, ...noSleep });
  assert.equal(fetchImpl.calls.length, 2);
});

test('overloaded stream error event is retried; invalid_request is not', async () => {
  const overloaded = streamResponse([sseText([{ type: 'error', error: { type: 'overloaded_error', message: 'Overloaded' } }])]);
  const f1 = scriptedFetch([overloaded, streamResponse([sseText(textEvents('ok'))])]);
  await streamTurn([], {}, undefined, { fetchImpl: f1, ...noSleep });
  assert.equal(f1.calls.length, 2);
  const f2 = scriptedFetch([streamResponse([sseText([{ type: 'error', error: { type: 'invalid_request_error', message: 'nope' } }])])]);
  await assert.rejects(streamTurn([], {}, undefined, { fetchImpl: f2, ...noSleep }), /nope/);
});

test('a drop after text was shown is not retried; the turn ends gracefully', async () => {
  const partial = sseText(textEvents('先铺一条小路').slice(0, 3));
  const fetchImpl = scriptedFetch([streamResponse([partial], { failAfter: 1 })]);
  const { out, cb } = recorder();
  const messages = [{ role: 'user', content: '做个游戏' }];
  const r = await runAgent({ messages, cb, exec: async () => ({}), deps: { fetchImpl, ...noSleep } });
  assert.equal(fetchImpl.calls.length, 1, 'no retry after visible output');
  assert.equal(r.done, false);
  assert.equal(r.interrupted, true);
  assert.equal(out.text, '先铺一条小路' + INTERRUPTED_NOTE);
  const last = messages[messages.length - 1];
  assert.equal(last.role, 'assistant');
  assert.equal(last.content[0].text, '先铺一条小路' + INTERRUPTED_NOTE, 'history keeps the partial text and the note');
});

test('a drop after a tool call started is not retried either', async () => {
  const partial = sseText(toolEvents('t1', 'add_entities', '{"step":"x","entities":[]}').slice(0, 2));
  const fetchImpl = scriptedFetch([streamResponse([partial], { failAfter: 1 })]);
  const { out, cb } = recorder();
  const r = await runAgent({ messages: [], cb, exec: async () => ({}), deps: { fetchImpl, ...noSleep } });
  assert.equal(r.interrupted, true);
  assert.deepEqual(out.tools, ['add_entities']);
  assert.equal(fetchImpl.calls.length, 1);
});

test('aborted requests are not retried', async () => {
  const ac = new AbortController();
  ac.abort();
  const err = Object.assign(new Error('aborted'), { name: 'AbortError' });
  const fetchImpl = scriptedFetch([err, streamResponse([sseText(textEvents('x'))])]);
  await assert.rejects(streamTurn([], {}, ac.signal, { fetchImpl, ...noSleep }), /aborted/);
  assert.equal(fetchImpl.calls.length, 1);
});

test('runAgent loops tools, returns errors as is_error tool_results, and stops on finish', async () => {
  const fetchImpl = scriptedFetch([
    streamResponse([sseText([...toolEvents('t1', 'add_entities', '{"step":"a","entities":[],}'), { type: 'message_stop' }])]),
    streamResponse([sseText(toolEvents('t2', 'explode', '{}'))]),
    streamResponse([sseText(toolEvents('t3', 'finish', '{"summary":"好了","suggestions":[]}'))]),
  ]);
  const seen = [];
  const exec = async (name, input) => {
    seen.push([name, input]);
    if (name === 'explode') throw new Error('boom');
    return { ok: true };
  };
  const messages = [{ role: 'user', content: 'go' }];
  const r = await runAgent({ messages, cb: {}, exec, deps: { fetchImpl, ...noSleep } });
  assert.deepEqual(r, { done: true });
  assert.deepEqual(seen.map(s => s[0]), ['add_entities', 'explode', 'finish']);
  assert.deepEqual(seen[0][1], { step: 'a', entities: [] }, 'trailing commas tolerated');
  const results = messages.filter(m => m.role === 'user' && Array.isArray(m.content)).map(m => m.content[0]);
  assert.equal(results[0].is_error, undefined);
  assert.deepEqual(results[1], { type: 'tool_result', tool_use_id: 't2', content: '{"error":"boom"}', is_error: true });
  assert.equal(fetchImpl.calls[1].messages.length, 3, 'second request carries the tool_result');
});

test('runTool: bad JSON and error results are flagged', async () => {
  const bad = await runTool(async () => ({}), { name: 'x', input: { __bad_json: '{' } });
  assert.equal(bad.isError, true);
  assert.match(bad.result.error, /JSON 不完整/);
  assert.equal((await runTool(async () => ({ error: 'unknown tool' }), { name: 'x', input: {} })).isError, true);
  assert.equal((await runTool(async () => undefined, { name: 'x', input: {} })).isError, false);
});

test('toolResultContent truncates long results with a marker', () => {
  assert.equal(toolResultContent({ a: 1 }), '{"a":1}');
  assert.equal(toolResultContent(undefined), 'null');
  const long = toolResultContent({ s: 'x'.repeat(10000) });
  assert.ok(long.length < 8100);
  assert.match(long, /已截断/);
});

test('compactHistory drops thinking and folds old turns', () => {
  const msgs = [];
  for (let i = 0; i < 10; i++) {
    msgs.push({ role: 'user', content: '需求' + i });
    msgs.push({ role: 'assistant', content: [{ type: 'thinking', thinking: 'hmm' }, { type: 'text', text: 'ok' + i }] });
  }
  const out = compactHistory(msgs, 6);
  assert.match(out[0].content, /需求0/);
  assert.equal(out[2].role, 'user');
  assert.ok(out.every(m => !Array.isArray(m.content) || m.content.every(b => b.type !== 'thinking')));
  assert.equal(compactHistory(msgs.slice(0, 2)).length, 2);
});
