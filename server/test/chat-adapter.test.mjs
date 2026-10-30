import test from 'node:test';
import assert from 'node:assert/strict';
import { chatEndpoint, chatRequest, gatewayUrls, responsesRequest, usesChatProtocol, usesResponsesProtocol } from '../chat-adapter.mjs';
process.env.AIGATE_API_KEY = 'synthetic-test-key';
const { runAgent, streamTurn } = await import('../agent.mjs');
const model = 'gpt-6.1-sol';
const chatModel = 'deepseek-v4.1-flash';
const response = chunks => ({ ok: true, status: 200, body: (async function* () { for (const chunk of chunks) yield new TextEncoder().encode('data: ' + JSON.stringify(chunk) + '\n\n'); })() });
const chunk = (delta, finish_reason = null) => ({ model: chatModel, choices: [{ index: 0, delta, finish_reason }] });
const toolChunk = (id, name, input, finish = 'tool_calls') => chunk({ tool_calls: [{ index: 0, id, function: { name, arguments: JSON.stringify(input) } }] }, finish);

test('chat endpoint accepts the OpenAI base and preserves configured gateway prefixes', () => {
  assert.equal(chatEndpoint('https://aigate.mini1.cn/v1'), 'https://aigate.mini1.cn/v1/chat/completions');
  assert.equal(chatEndpoint('https://aigate.mini1.cn/v1/'), 'https://aigate.mini1.cn/v1/chat/completions');
  assert.equal(gatewayUrls('https://aigate.mini1.cn/v1').messages, 'https://aigate.mini1.cn/v1/messages');
  assert.equal(gatewayUrls('https://aigate.mini1.cn/v1').responses, 'https://aigate.mini1.cn/v1/responses');
  assert.equal(chatEndpoint('https://gateway.test/v1/messages'), 'https://gateway.test/v1/chat/completions');
  assert.equal(chatEndpoint('https://gateway.test/proxy/aigate/v1/messages?route=test'), 'https://gateway.test/proxy/aigate/v1/chat/completions?route=test');
  assert.equal(chatEndpoint('https://gateway.test/api/messages/'), 'https://gateway.test/api/chat/completions');
  assert.throws(() => chatEndpoint('https://gateway.test/unrelated'), /must be an OpenAI base/);
  for (const id of [model, 'claude-sonnet-5-5', 'deepseek-v4.1-flash', 'kimi-k3.1-pro-highspeed']) assert.equal(usesChatProtocol(id), true);
  assert.equal(usesResponsesProtocol(model), true);
  for (const id of ['gpt-6-sol', 'gpt-6-luna', 'gpt-6-astra', 'gpt-6.1-terra']) assert.equal(usesResponsesProtocol(id), true);
  assert.equal(usesResponsesProtocol(chatModel), false);
  assert.equal(usesResponsesProtocol('claude-opus-5-5'), false);
  assert.equal(chatRequest({ model: 'claude-opus-5-5', messages: [], tools: [], max_tokens: 8, stream: true, tool_choice: { type: 'tool', name: 'finish' } }).tool_choice, 'auto');
});

test('request adapter keeps tool IDs/errors/images, strips foreign signatures and leaves history unchanged', () => {
  const image = { type: 'image', source: { type: 'base64', media_type: 'image/png', data: 'eA==' } };
  const messages = [
    { role: 'user', content: 'start' },
    { role: 'assistant', content: [{ type: 'thinking', thinking: 'PRIVATE_SENTINEL', signature: 'SIGNED_SENTINEL' }, { type: 'text', text: 'inspect' }, { type: 'tool_use', id: 'call_1', name: 'shot', input: { x: 1 } }] },
    { role: 'user', content: [{ type: 'tool_result', tool_use_id: 'call_1', is_error: true, content: [{ type: 'text', text: 'assertion failed' }, image] }] },
  ];
  const original = structuredClone(messages);
  const out = chatRequest({ model, messages, system: 'system', tools: [{ name: 'shot', input_schema: { type: 'object' } }], max_tokens: 24000, stream: true, thinking: { type: 'adaptive', display: 'summarized' } });
  assert.deepEqual(messages, original);
  assert.equal(out.model, model);
  assert.equal(out.max_completion_tokens, 24000);
  assert.equal(out.max_tokens, undefined);
  assert.equal(out.thinking, undefined);
  assert.equal(out.reasoning_effort, 'high');
  assert.deepEqual(out.messages[2].tool_calls, [{ id: 'call_1', type: 'function', function: { name: 'shot', arguments: '{"x":1}' } }]);
  assert.deepEqual(out.messages[3], { role: 'tool', tool_call_id: 'call_1', content: 'Tool error: assertion failed' });
  assert.equal(out.messages[4].content[1].image_url.url, 'data:image/png;base64,eA==');
  assert.doesNotMatch(JSON.stringify(out), /PRIVATE_SENTINEL|SIGNED_SENTINEL/);
});

test('tool choice and explicit effort remain request semantics rather than model fallback', () => {
  const base = { model, messages: [], tools: [], max_tokens: 1000, stream: true, thinking: { type: 'adaptive' } };
  assert.equal(chatRequest({ ...base, tool_choice: { type: 'any' } }).tool_choice, 'required');
  const out = chatRequest({ ...base, output_config: { effort: 'medium' }, tool_choice: { type: 'tool', name: 'finish', disable_parallel_tool_use: true } });
  assert.equal(out.reasoning_effort, 'medium');
  assert.deepEqual(out.tool_choice, { type: 'function', function: { name: 'finish' } });
  assert.equal(out.parallel_tool_calls, false);
  assert.equal(out.model, model);
});

test('production stream adapter routes chat models and rejoins split/interleaved tool calls', async () => {
  const seen = [], starts = [], identities = [];
  const fetchImpl = async (url, init) => {
    seen.push({ url, body: JSON.parse(init.body) });
    return response([
      chunk({ reasoning_content: 'PRIVATE_REASONING_SENTINEL' }),
      chunk({ content: 'Inspecting' }),
      chunk({ tool_calls: [{ index: 0, id: 'a', function: { name: 'read_' } }, { index: 1, id: 'b', function: { name: 'other', arguments: '{"n":' } }] }),
      chunk({ tool_calls: [{ index: 0, function: { name: 'file', arguments: '{"path":' } }, { index: 1, function: { arguments: '2}' } }] }),
      chunk({ tool_calls: [{ index: 0, function: { arguments: '"x.gd"}' } }] }, 'tool_calls'),
    ]);
  };
  const result = await streamTurn([], { onToolStart: (id, name) => starts.push([id, name]), onModel: data => identities.push(data) }, undefined, { fetchImpl, req: { model: chatModel, max_tokens: 16000, thinking: { type: 'adaptive' }, tools: [] } });
  assert.ok(seen[0].url.endsWith('/v1/chat/completions'));
  assert.equal(seen[0].body.max_completion_tokens, 16000);
  assert.equal(seen[0].body.reasoning_effort, 'high');
  assert.deepEqual(result.content, [{ type: 'text', text: 'Inspecting' }, { type: 'tool_use', id: 'a', name: 'read_file', input: { path: 'x.gd' } }, { type: 'tool_use', id: 'b', name: 'other', input: { n: 2 } }]);
  assert.deepEqual(starts, [['b', 'other'], ['a', 'read_file']]);
  assert.deepEqual(identities, [{ requestedModel: chatModel, responseModel: chatModel }]);
  assert.equal(result.stop, 'tool_use');
  assert.doesNotMatch(JSON.stringify(result), /PRIVATE_REASONING_SENTINEL/);
});

test('late function name fragments update the actual execution name without corrupting arguments', async () => {
  const result = await streamTurn([], {}, undefined, { req: { model: chatModel }, fetchImpl: async () => response([
    chunk({ tool_calls: [{ index: 0, id: 'x', function: { name: 'write_', arguments: '{' } }] }),
    chunk({ tool_calls: [{ index: 0, function: { name: 'file', arguments: '"path":"x"}' } }] }, 'tool_calls'),
  ]) });
  assert.deepEqual(result.content[0], { type: 'tool_use', id: 'x', name: 'write_file', input: { path: 'x' } });
});

test('runAgent replays actual error tool results through the selected protocol and finishes normally', async () => {
  const requests = [], called = [];
  const out = await runAgent({ messages: [{ role: 'user', content: 'go' }], cb: {}, req: { model: chatModel },
    deps: { fetchImpl: async (_url, init) => { const body = JSON.parse(init.body); requests.push(body); return response([requests.length === 1 ? toolChunk('x', 'inspect', {}) : toolChunk('y', 'finish', {})]); } },
    exec: async name => { called.push(name); return name === 'inspect' ? { error: 'known failure' } : { ok: true }; },
  });
  assert.equal(out.done, true);
  assert.deepEqual(called, ['inspect', 'finish']);
  assert.equal(requests[1].messages.at(-1).role, 'tool');
  assert.equal(requests[1].messages.at(-1).tool_call_id, 'x');
  assert.match(requests[1].messages.at(-1).content, /Tool error:.*known failure/);
  assert.ok(requests.every(request => request.model === chatModel && !('max_tokens' in request)));
});

test('dropped GPT stream after a tool begins is interrupted without executing or switching models', async () => {
  let requests = 0, calls = 0;
  const result = await runAgent({ messages: [], cb: {}, req: { model: chatModel }, exec: async () => { calls++; },
    deps: { fetchImpl: async () => { requests++; return response([chunk({ tool_calls: [{ index: 0, id: 'x', function: { name: 'inspect', arguments: '{"p":' } }] })]); } },
  });
  assert.equal(result.interrupted, true);
  assert.equal(result.done, false);
  assert.equal(calls, 0);
  assert.equal(requests, 1);
});

test('GPT cancellation propagates without retries or a second protocol request', async () => {
  const controller = new AbortController(); controller.abort();
  let calls = 0;
  await assert.rejects(streamTurn([], {}, controller.signal, { req: { model: chatModel }, fetchImpl: async () => { calls++; throw Object.assign(new Error('cancelled'), { name: 'AbortError' }); } }), /cancelled/);
  assert.equal(calls, 1);
});

test('gpt function tools use the responses route and replay tool output', async () => {
  const seen = [];
  const fetchImpl = async (url, init) => {
    const body = JSON.parse(init.body);
    seen.push({ url, body });
    const call = body.input?.some(item => item.type === 'function_call_output')
      ? { type: 'response.output_item.added', output_index: 0, item: { type: 'function_call', call_id: 'y', name: 'finish', arguments: '{}' } }
      : { type: 'response.output_item.added', output_index: 0, item: { type: 'function_call', call_id: 'x', name: 'inspect', arguments: '{}' } };
    return response([
      { type: 'response.created', response: { model } },
      call,
      { type: 'response.completed', response: { status: 'completed', model } },
    ]);
  };
  const called = [];
  const out = await runAgent({ messages: [{ role: 'user', content: 'go' }], cb: {}, req: { model, max_tokens: 1024, thinking: { type: 'adaptive' }, tools: [] },
    deps: { fetchImpl }, exec: async name => { called.push(name); return name === 'inspect' ? { error: 'known failure' } : { ok: true }; } });
  assert.equal(out.done, true);
  assert.deepEqual(called, ['inspect', 'finish']);
  assert.ok(seen.every(row => row.url.endsWith('/v1/responses')));
  assert.equal(seen[0].body.max_output_tokens, 1024);
  assert.equal(seen[0].body.reasoning.effort, 'high');
  assert.equal(seen[0].body.max_completion_tokens, undefined);
  assert.equal(seen[1].body.input.at(-1).type, 'function_call_output');
  assert.equal(seen[1].body.input.at(-1).call_id, 'x');
  assert.match(seen[1].body.input.at(-1).output, /Tool error:.*known failure/);
  const image = { type: 'image', source: { type: 'base64', media_type: 'image/png', data: 'eA==' } };
  const converted = responsesRequest({ model, messages: [{ role: 'user', content: [{ type: 'tool_result', tool_use_id: 'shot', content: [{ type: 'text', text: 'missed' }, image] }] }], tools: [], max_tokens: 8, stream: true });
  assert.equal(converted.input.at(-1).content.find(part => part.type === 'input_image').image_url, 'data:image/png;base64,eA==');
  assert.doesNotMatch(JSON.stringify(converted), /signature/);
});
