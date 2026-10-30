import test from 'node:test';
import assert from 'node:assert/strict';

process.env.AIGATE_API_KEY = 'test-key';
process.env.AIGATE_PROTOCOL = 'messages';
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

test('streamTurn gives up after 5 attempts with a readable error', async () => {
  const fetchImpl = scriptedFetch([errorResponse(503), errorResponse(502), errorResponse(502), errorResponse(429), errorResponse(500, 'down')]);
  await assert.rejects(streamTurn([], {}, undefined, { fetchImpl, ...noSleep }), /AI 服务返回 500：down/);
  assert.equal(fetchImpl.calls.length, 5);
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

test('beforeTurn is awaited after until and before each request, with completed tools visible', async () => {
  const order = [], messages = [{ role: 'user', content: 'go' }];
  let turn = 0;
  const result = await runAgent({
    messages, cb: {}, until: () => { order.push('until'); return false; },
    beforeTurn: async history => {
      order.push('hook:' + history.length);
      await Promise.resolve();
      history.push({ role: 'user', content: 'boundary ' + (++turn) });
      order.push('hook-done');
    },
    exec: async name => { order.push('tool:' + name); return { ok: true }; },
    deps: { ...noSleep, fetchImpl: async (_url, init) => {
      const request = JSON.parse(init.body);
      order.push('fetch:' + request.messages.at(-1).content);
      return streamResponse([sseText(toolEvents('t' + turn, turn === 1 ? 'inspect' : 'finish', '{}'))]);
    } },
  });
  assert.equal(result.done, true);
  assert.deepEqual(order, ['until', 'hook:1', 'hook-done', 'fetch:boundary 1', 'tool:inspect', 'until', 'hook:4', 'hook-done', 'fetch:boundary 2', 'tool:finish']);
});

test('until stops before beforeTurn and a hook failure propagates without a request', async () => {
  let hooks = 0, requests = 0;
  const common = { messages: [], cb: {}, exec: async () => ({}), deps: { fetchImpl: async () => { requests++; throw new Error('must not request'); } } };
  const stopped = await runAgent({ ...common, until: () => true, beforeTurn: async () => { hooks++; } });
  assert.deepEqual(stopped, { done: false, stopped: true });
  assert.equal(hooks, 0);
  const failure = new Error('boundary cancelled');
  await assert.rejects(runAgent({ ...common, beforeTurn: async () => { hooks++; throw failure; } }), error => error === failure);
  assert.equal(hooks, 1);
  assert.equal(requests, 0);
});

test('target model adapts tool images on the request while preserving stored history', async () => {
  const messages = [{ role: 'user', content: [{ type: 'tool_result', tool_use_id: 'shot', content: [{ type: 'image', source: { type: 'base64', media_type: 'image/png', data: 'eA==' } }] }] }];
  const original = structuredClone(messages);
  const fetchImpl = scriptedFetch([streamResponse([sseText(textEvents('seen'))])]);
  await streamTurn(messages, {}, undefined, { fetchImpl, req: { model: 'kimi-k3.1-pro-highspeed' } });
  assert.deepEqual(messages, original);
  assert.equal(fetchImpl.calls[0].model, 'kimi-k3.1-pro-highspeed');
  assert.equal(fetchImpl.calls[0].messages.length, 2);
  assert.equal(fetchImpl.calls[0].messages[0].content[0].type, 'tool_result');
  assert.equal(fetchImpl.calls[0].messages[1].content[1].type, 'image');
});

test('message_start reports only requested and returned model metadata', async () => {
  const events = textEvents('ok');
  events[0].message = { model: 'returned-model', id: 'private-message-id', content: [{ type: 'thinking', thinking: 'PRIVATE_REASONING_SENTINEL' }] };
  const seen = [];
  const fetchImpl = scriptedFetch([streamResponse([sseText(events)])]);
  const result = await streamTurn([], { onModel: value => seen.push(value) }, undefined, { fetchImpl, req: { model: 'requested-model' } });
  assert.deepEqual(seen, [{ requestedModel: 'requested-model', responseModel: 'returned-model' }]);
  assert.deepEqual(result.content, [{ type: 'text', text: 'ok' }]);
});

test('missing response model remains unknown and does not claim the requested model', async () => {
  const seen = [];
  const fetchImpl = scriptedFetch([streamResponse([sseText(textEvents('ok'))])]);
  await streamTurn([], { onModel: value => seen.push(value) }, undefined, { fetchImpl, req: { model: 'requested-model' } });
  assert.deepEqual(seen, [{ requestedModel: 'requested-model', responseModel: '' }]);
});
