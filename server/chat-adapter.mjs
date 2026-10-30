// Company gateway is OpenAI-compatible at https://aigate.mini1.cn/v1.
// Text models use Chat Completions. Verified GPT 6 and 6.1 IDs reject function
// tools there and use /v1/responses. AIGATE_PROTOCOL=messages keeps the old
// Messages parser available for local protocol tests only.
const CHAT_SUFFIX = '/chat/completions';
const MESSAGES_SUFFIX = '/messages';
const RESPONSES_SUFFIX = '/responses';

export const usesChatProtocol = () => process.env.AIGATE_PROTOCOL !== 'messages';
const RESPONSES_MODELS = new Set(['gpt-6-astra', 'gpt-6-luna', 'gpt-6-sol', 'gpt-6.1-sol', 'gpt-6.1-terra']);
export const usesResponsesProtocol = model => RESPONSES_MODELS.has(model) && process.env.AIGATE_PROTOCOL !== 'messages';
// Opus 5.5 rejects both required and named tool_choice. Auto still calls tools.
const AUTO_TOOL_MODELS = new Set(['claude-opus-5-5']);

function openAIToolChoice(body, named) {
  if (AUTO_TOOL_MODELS.has(body.model)) return body.tool_choice ? 'auto' : undefined;
  if (body.tool_choice?.type === 'tool') return named(body.tool_choice.name);
  if (body.tool_choice?.type === 'any') return 'required';
  if (body.tool_choice?.type === 'auto') return 'auto';
  return undefined;
}

/** Accept an OpenAI /v1 base, or a legacy URL that already ends in /messages or /chat/completions. */
export function gatewayUrls(configured) {
  const url = new URL(configured);
  const path = url.pathname.replace(/\/+$/, '');
  let basePath = path;
  if (path.endsWith(CHAT_SUFFIX)) basePath = path.slice(0, -CHAT_SUFFIX.length);
  else if (path.endsWith(MESSAGES_SUFFIX)) basePath = path.slice(0, -MESSAGES_SUFFIX.length);
  else if (path.endsWith(RESPONSES_SUFFIX)) basePath = path.slice(0, -RESPONSES_SUFFIX.length);
  else if (!path.endsWith('/v1')) throw new Error('AIGATE_URL must be an OpenAI base ending in /v1, or end with /messages or /chat/completions');
  basePath = basePath.replace(/\/+$/, '');
  const endpoint = suffix => {
    const next = new URL(url.href);
    next.pathname = basePath + suffix;
    return next.href;
  };
  return { chat: endpoint(CHAT_SUFFIX), messages: endpoint(MESSAGES_SUFFIX), responses: endpoint(RESPONSES_SUFFIX) };
}

export function chatEndpoint(configured) {
  return gatewayUrls(configured).chat;
}

const textOf = blocks => typeof blocks === 'string' ? blocks : (Array.isArray(blocks) ? blocks : []).filter(block => block.type === 'text').map(block => block.text || '').join('\n');
function imagePart(block) {
  const source = block.source || {};
  if (source.type === 'base64') return { type: 'image_url', image_url: { url: 'data:' + source.media_type + ';base64,' + source.data } };
  if (source.type === 'url') return { type: 'image_url', image_url: { url: source.url } };
  throw new Error('Unsupported image source for selected model');
}
const userParts = blocks => blocks.filter(block => block.type === 'text' || block.type === 'image').map(block => block.type === 'image' ? imagePart(block) : { type: 'text', text: block.text || '' });

export function chatRequest(body) {
  const messages = [];
  if (body.system) messages.push({ role: 'system', content: textOf(body.system) });
  for (const message of body.messages) {
    if (typeof message.content === 'string') { messages.push({ role: message.role, content: message.content }); continue; }
    const blocks = Array.isArray(message.content) ? message.content : [];
    if (message.role === 'assistant') {
      const tools = blocks.filter(block => block.type === 'tool_use').map(block => ({ id: block.id, type: 'function', function: { name: block.name, arguments: JSON.stringify(block.input || {}) } }));
      messages.push({ role: 'assistant', content: textOf(blocks) || null, ...(tools.length ? { tool_calls: tools } : {}) });
    } else {
      const attachments = [];
      for (const block of blocks.filter(block => block.type === 'tool_result')) {
        const images = Array.isArray(block.content) ? block.content.filter(part => part.type === 'image') : [];
        const content = textOf(block.content) || (images.length ? 'The tool image is attached in the following user message.' : '');
        messages.push({ role: 'tool', tool_call_id: block.tool_use_id, content: (block.is_error ? 'Tool error: ' : '') + content });
        if (images.length) attachments.push({ type: 'text', text: 'Image from tool response ' + block.tool_use_id + ':' }, ...images.map(imagePart));
      }
      const content = [...userParts(blocks), ...attachments];
      if (content.length) messages.push({ role: 'user', content });
    }
  }
  const request = { model: body.model, messages, max_completion_tokens: body.max_tokens, stream: body.stream,
    tools: (body.tools || []).map(tool => ({ type: 'function', function: { name: tool.name, description: tool.description || '', parameters: tool.input_schema } })) };
  if (body.thinking && body.thinking.type !== 'disabled') {
    const effort = body.output_config?.effort;
    request.reasoning_effort = ['low', 'medium', 'high', 'xhigh'].includes(effort) ? effort : 'high';
  }
  const choice = openAIToolChoice(body, name => ({ type: 'function', function: { name } }));
  if (choice) request.tool_choice = choice;
  if (body.tool_choice?.disable_parallel_tool_use === true) request.parallel_tool_calls = false;
  return request;
}

function responsesImage(block) {
  const source = block.source || {};
  if (source.type === 'base64') return { type: 'input_image', image_url: 'data:' + source.media_type + ';base64,' + source.data };
  if (source.type === 'url') return { type: 'input_image', image_url: source.url };
  throw new Error('Unsupported image source for selected model');
}
const responsesUserParts = blocks => blocks.filter(block => block.type === 'text' || block.type === 'image').map(block => block.type === 'image' ? responsesImage(block) : { type: 'input_text', text: block.text || '' });

/** gpt-6.1-sol accepts function tools on the Responses API, not Chat Completions. */
export function responsesRequest(body) {
  const input = [];
  for (const message of body.messages) {
    if (typeof message.content === 'string') { input.push({ role: message.role === 'assistant' ? 'assistant' : 'user', content: message.content }); continue; }
    const blocks = Array.isArray(message.content) ? message.content : [];
    if (message.role === 'assistant') {
      const text = textOf(blocks);
      if (text) input.push({ role: 'assistant', content: text });
      for (const block of blocks.filter(block => block.type === 'tool_use')) input.push({ type: 'function_call', call_id: block.id, name: block.name, arguments: JSON.stringify(block.input || {}) });
    } else {
      const attachments = [];
      for (const block of blocks.filter(block => block.type === 'tool_result')) {
        const images = Array.isArray(block.content) ? block.content.filter(part => part.type === 'image') : [];
        const content = textOf(block.content) || (images.length ? 'The tool image is attached in the following user message.' : '');
        input.push({ type: 'function_call_output', call_id: block.tool_use_id, output: (block.is_error ? 'Tool error: ' : '') + content });
        if (images.length) attachments.push({ type: 'input_text', text: 'Image from tool response ' + block.tool_use_id + ':' }, ...images.map(responsesImage));
      }
      const content = [...responsesUserParts(blocks), ...attachments];
      if (content.length) input.push({ role: 'user', content });
    }
  }
  const request = { model: body.model, input, max_output_tokens: body.max_tokens, stream: body.stream,
    tools: (body.tools || []).map(tool => ({ type: 'function', name: tool.name, description: tool.description || '', parameters: tool.input_schema })) };
  if (body.system) request.instructions = textOf(body.system);
  if (body.thinking && body.thinking.type !== 'disabled') {
    const effort = body.output_config?.effort;
    request.reasoning = { effort: ['low', 'medium', 'high', 'xhigh'].includes(effort) ? effort : 'high' };
  }
  const choice = openAIToolChoice(body, name => ({ type: 'function', name }));
  if (choice) request.tool_choice = choice;
  if (body.tool_choice?.disable_parallel_tool_use === true) request.parallel_tool_calls = false;
  return request;
}

/** Normalize only public text/tool deltas; private reasoning is not persisted.
 * The existing agent retry, interruption, tool-result and cancellation logic stays
 * shared between protocols. Tool-call indices may interleave in streamed chunks. */
export async function* chatEvents(events) {
  let started = false, nextIndex = 0, textIndex = null;
  const tools = new Map();
  for await (const event of events) {
    if (event.error) { yield { type: 'error', error: event.error }; continue; }
    if (!started) { started = true; yield { type: 'message_start', message: { model: event.model || '' } }; }
    for (const choice of event.choices || []) {
      if (choice.index && choice.index !== 0) continue;
      const delta = choice.delta || {};
      if (typeof delta.content === 'string' && delta.content) {
        if (textIndex === null) { textIndex = nextIndex++; yield { type: 'content_block_start', index: textIndex, content_block: { type: 'text', text: '' } }; }
        yield { type: 'content_block_delta', index: textIndex, delta: { type: 'text_delta', text: delta.content } };
      }
      for (const call of delta.tool_calls || []) {
        const key = call.index ?? 0;
        if (!tools.has(key)) tools.set(key, { index: nextIndex++, id: '', name: '', pending: '', started: false });
        const tool = tools.get(key);
        if (call.id) tool.id = call.id;
        if (call.function?.name) {
          tool.name += call.function.name;
          if (tool.started) yield { type: 'content_block_delta', index: tool.index, delta: { type: 'tool_name_delta', name: tool.name } };
        }
        if (call.function?.arguments) tool.pending += call.function.arguments;
        if (!tool.started && tool.id && tool.name && tool.pending) {
          tool.started = true;
          yield { type: 'content_block_start', index: tool.index, content_block: { type: 'tool_use', id: tool.id, name: tool.name, input: {} } };
        }
        if (tool.started && tool.pending) {
          yield { type: 'content_block_delta', index: tool.index, delta: { type: 'input_json_delta', partial_json: tool.pending } };
          tool.pending = '';
        }
      }
      if (choice.finish_reason) {
        for (const tool of tools.values()) {
          if (!tool.started && tool.id && tool.name) {
            tool.started = true;
            yield { type: 'content_block_start', index: tool.index, content_block: { type: 'tool_use', id: tool.id, name: tool.name, input: {} } };
          }
        }
        if ([...tools.values()].some(tool => !tool.started)) throw new Error('Gateway returned an incomplete tool identity');
        yield { type: 'message_delta', delta: { stop_reason: ({ tool_calls: 'tool_use', length: 'max_tokens' })[choice.finish_reason] || 'end_turn' } };
        yield { type: 'message_stop' };
      }
    }
  }
}

/** Normalize Responses SSE into the same text and tool events as Chat Completions. */
export async function* responsesEvents(events) {
  let started = false, nextIndex = 0, textIndex = null;
  const tools = new Map();
  for await (const event of events) {
    if (event.type === 'error' || event.error) { yield { type: 'error', error: event.error || { message: event.message || 'unknown' } }; continue; }
    if (!started) { started = true; yield { type: 'message_start', message: { model: event.response?.model || event.model || '' } }; }
    if (event.type === 'response.output_text.delta' && event.delta) {
      if (textIndex === null) { textIndex = nextIndex++; yield { type: 'content_block_start', index: textIndex, content_block: { type: 'text', text: '' } }; }
      yield { type: 'content_block_delta', index: textIndex, delta: { type: 'text_delta', text: event.delta } };
    }
    if (event.type === 'response.output_item.added' && event.item?.type === 'function_call') {
      const item = event.item;
      const tool = { index: nextIndex++, id: item.call_id || '', name: item.name || '', pending: item.arguments || '', started: false };
      tools.set(event.output_index ?? tool.index, tool);
      if (tool.id && tool.name) {
        tool.started = true;
        yield { type: 'content_block_start', index: tool.index, content_block: { type: 'tool_use', id: tool.id, name: tool.name, input: {} } };
        if (tool.pending) { yield { type: 'content_block_delta', index: tool.index, delta: { type: 'input_json_delta', partial_json: tool.pending } }; tool.pending = ''; }
      }
    }
    if (event.type === 'response.function_call_arguments.delta' && event.delta) {
      const tool = tools.get(event.output_index);
      if (!tool) continue;
      if (tool.started) yield { type: 'content_block_delta', index: tool.index, delta: { type: 'input_json_delta', partial_json: event.delta } };
      else tool.pending += event.delta;
    }
    if (event.type === 'response.completed' || event.type === 'response.incomplete') {
      for (const tool of tools.values()) {
        if (!tool.started && tool.id && tool.name) {
          tool.started = true;
          yield { type: 'content_block_start', index: tool.index, content_block: { type: 'tool_use', id: tool.id, name: tool.name, input: {} } };
          if (tool.pending) yield { type: 'content_block_delta', index: tool.index, delta: { type: 'input_json_delta', partial_json: tool.pending } };
        }
      }
      if ([...tools.values()].some(tool => !tool.started)) throw new Error('Gateway returned an incomplete tool identity');
      const incomplete = event.type === 'response.incomplete' || event.response?.status === 'incomplete';
      yield { type: 'message_delta', delta: { stop_reason: incomplete ? 'max_tokens' : (tools.size ? 'tool_use' : 'end_turn') } };
      yield { type: 'message_stop' };
    }
  }
}
