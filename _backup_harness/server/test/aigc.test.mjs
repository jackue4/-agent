import test from 'node:test';
import assert from 'node:assert/strict';
import {
  parseTaskId, parseTaskStatus, extractUrls, pickModelUrl, parseRpcBody, httpError, toolResultText, submitError,
  isRetryable, backoffMs, McpError, styleSuffix, imagePrompt, styleWords,
} from '../aigc.mjs';

test('parseTaskId handles the Chinese and English reply forms', () => {
  assert.equal(parseTaskId('任务已提交\n任务ID: img_123-abc\n请稍候'), 'img_123-abc');
  assert.equal(parseTaskId('任务ID：abc'), 'abc');
  assert.equal(parseTaskId('{"task_id": "t-9"}'), 't-9');
  assert.equal(parseTaskId('Task ID = Z1'), 'Z1');
  assert.equal(parseTaskId('错误: 余额不足'), null);
});

test('parseTaskStatus classifies terminal and running states', () => {
  const done = parseTaskStatus('状态: completed\n结果: url=https://cdn.x/a.png');
  assert.deepEqual(done, { state: 'done', raw: 'completed', urls: ['https://cdn.x/a.png'] });
  assert.equal(parseTaskStatus('status: "succeeded"').state, 'done');
  for (const s of ['failed', 'error', 'cancelled']) assert.equal(parseTaskStatus('状态: ' + s).state, 'failed');
  assert.deepEqual(parseTaskStatus('状态: processing 进度 40% https://x/preview.png'), { state: 'running', raw: 'processing', urls: [] });
  assert.equal(parseTaskStatus('').state, 'running');
});

test('extractUrls prefers url= fields, falls back to bare URLs, trims punctuation and dedupes', () => {
  assert.deepEqual(extractUrls('url=https://a/1.png, url=https://a/2.glb'), ['https://a/1.png', 'https://a/2.glb']);
  assert.deepEqual(extractUrls('see (https://a/x.png). and "https://a/x.png"'), ['https://a/x.png']);
  assert.deepEqual(extractUrls('no links'), []);
  assert.deepEqual(extractUrls('url=ftp://nope'), [], 'non-http url= values are ignored');
});

test('pickModelUrl prefers glb then fbx', () => {
  assert.equal(pickModelUrl(['https://a/p.png', 'https://a/m.fbx', 'https://a/m.glb?x=1']), 'https://a/m.glb?x=1');
  assert.equal(pickModelUrl(['https://a/p.png', 'https://a/m.FBX']), 'https://a/m.FBX');
  assert.equal(pickModelUrl(['https://a/p.png']), 'https://a/p.png');
});

test('parseRpcBody reads JSON and SSE bodies', () => {
  assert.deepEqual(parseRpcBody('{"jsonrpc":"2.0","id":3,"result":{}}'), { jsonrpc: '2.0', id: 3, result: {} });
  const sse = 'event: message\ndata: {"jsonrpc":"2.0","method":"notifications/progress"}\n\ndata: {"jsonrpc":"2.0","id":4,"result":{"ok":1}}\n\n';
  assert.deepEqual(parseRpcBody(sse).result, { ok: 1 });
  assert.equal(parseRpcBody('data: {broken'), null);
  assert.equal(parseRpcBody('{broken'), null);
});

test('httpError classifies statuses', () => {
  assert.equal(httpError(200, ''), null);
  assert.equal(httpError(404, '').session, true);
  assert.equal(httpError(503, '').retryable, true);
  assert.equal(httpError(429, '').retryable, true);
  const e = httpError(403, 'forbidden');
  assert.equal(e.retryable, false);
  assert.match(e.message, /403.*forbidden/);
});

test('isRetryable: network and 5xx yes, protocol and tool errors no', () => {
  assert.equal(isRetryable(new TypeError('fetch failed')), true);
  assert.equal(isRetryable(Object.assign(new Error('x'), { name: 'TimeoutError' })), true);
  assert.equal(isRetryable(new Error('read ECONNRESET')), true);
  assert.equal(isRetryable(new McpError('5xx', { retryable: true })), true);
  assert.equal(isRetryable(new McpError('bad', {})), false);
  assert.equal(isRetryable(new Error('任务失败')), false);
  assert.equal(isRetryable(null), false);
});

test('backoffMs grows exponentially with bounded jitter and a cap', () => {
  const mid = () => 0.5;
  assert.deepEqual([0, 1, 2, 3].map(a => backoffMs(a, 100, 10000, mid)), [100, 200, 400, 800]);
  assert.equal(backoffMs(20, 100, 1000, mid), 1000);
  assert.equal(backoffMs(0, 100, 1000, () => 0), 75);
  assert.equal(backoffMs(0, 100, 1000, () => 1), 125);
});

test('toolResultText and submitError produce readable text', () => {
  assert.equal(toolResultText({ content: [{ type: 'text', text: 'a' }, { type: 'image' }, { type: 'text', text: 'b' }] }), 'a\n\nb');
  assert.equal(toolResultText(null), '');
  assert.match(submitError('generate_image_async', '错误: 内容违规\n请修改').message, /素材任务提交失败（generate_image_async）：内容违规/);
  assert.match(submitError('removebg', '').message, /空响应/);
});

test('every image prompt carries the art bible before kind framing', () => {
  const meta = { style: 'pixel', art_bible: 'moody neon cyberpunk alleys' };
  for (const kind of ['sprite', 'background', 'texture', 'model3d']) {
    const p = imagePrompt(kind, 'a robot cat', meta);
    assert.ok(p.startsWith('a robot cat, moody neon cyberpunk alleys, ' + styleWords('pixel')), kind + ': ' + p);
  }
  assert.match(imagePrompt('texture', 'grass', meta), /seamless tileable/);
  assert.equal(styleSuffix({ style: 'anime' }), styleWords('anime'), 'no bible -> plain style words');
  assert.equal(styleSuffix('cartoon'), styleWords('cartoon'), 'bare style strings still work');
  assert.equal(styleSuffix(undefined), styleWords('cartoon'));
});
