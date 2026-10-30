import test from 'node:test';
import assert from 'node:assert/strict';
import { DEFAULT_MODEL, MODEL_OPTIONS, MODEL_SETTINGS, assertModelSelection, resolveModelSelection, loadModelConfig } from '../model-config.mjs';
import { messagesForModel } from '../message-adapter.mjs';

const config = (local, env = {}) => loadModelConfig({ env, configPath: '/fixture/model.json', readFile: () => JSON.stringify(local) });

test('public options are the verified gateway IDs and cannot be mutated', () => {
  assert.deepEqual(MODEL_OPTIONS.map(row => row.id), [
    'claude-opus-5-5', 'claude-opus-5', 'claude-opus-4-8', 'claude-sonnet-5-5',
    'gpt-6.1-sol', 'gpt-6.1-terra', 'gpt-6-sol', 'gpt-6-luna', 'gpt-6-astra',
    'gpt-5.6-sol', 'gpt-5.6-luna', 'gpt-5.6-terra', 'gpt-5.5', 'gpt-5.4-pro', 'gpt-5.4', 'gpt-5.4-mini', 'gpt-5.4-nano', 'gpt-5.2',
    'deepseek-v4.1-flash', 'kimi-k3.1-pro-highspeed',
  ]);
  assert.ok(Object.isFrozen(MODEL_OPTIONS));
  for (const row of MODEL_OPTIONS) {
    assert.ok(Object.isFrozen(row));
    assert.ok(row.label.length > 0);
    assert.equal(assertModelSelection(row.id), row.id);
  }
});

test('explicit project selection rejects unknown IDs, aliases, blanks and non-strings', () => {
  for (const value of [undefined, null, '', 'Sonnet 5.5', 'deepseek', ' gpt-6.1-sol', 'kimi-k3.1-pro', {}, 1]) assert.throws(() => assertModelSelection(value), /有效模型/);
  assert.throws(() => resolveModelSelection(''), /有效模型/);
  assert.throws(() => resolveModelSelection('unlisted-custom'), /有效模型/);
});

test('missing legacy selection preserves the configured default without a hidden model fallback', () => {
  assert.equal(resolveModelSelection(undefined), MODEL_SETTINGS.codeModel);
  assert.equal(resolveModelSelection(null), MODEL_SETTINGS.codeModel);
  assert.equal(resolveModelSelection(undefined, { defaultModel: 'admin-private-model' }), 'admin-private-model');
  assert.equal(resolveModelSelection('gpt-6.1-sol', { defaultModel: 'admin-private-model' }), 'gpt-6.1-sol');
  assert.throws(() => resolveModelSelection(undefined, { defaultModel: '' }), /默认模型配置无效/);
});

test('platform-local selection applies to primary and project/worker requests with explicit sources', () => {
  const r = config({ model: 'kimi-k3.1-pro-highspeed', codeModel: 'project-v2' });
  assert.equal(r.model, DEFAULT_MODEL);
  assert.equal(r.codeModel, 'project-v2');
  assert.equal(r.modelSource, 'local:model');
  assert.equal(r.codeModelSource, 'local:codeModel');
  assert.equal(r.configFile, '/fixture/model.json');
  assert.ok(Object.isFrozen(r));
});

test('environment precedence is explicit and primary override also reaches project workers', () => {
  assert.deepEqual([config({ model: 'local', codeModel: 'local-code' }, { UGC_MODEL: 'override' }).model,
    config({ model: 'local', codeModel: 'local-code' }, { UGC_MODEL: 'override' }).codeModel], ['override', 'override']);
  const r = config({ model: 'local', codeModel: 'local-code' }, { UGC_MODEL: 'primary', UGC_CODE_MODEL: 'code' });
  assert.equal(r.model, 'primary');
  assert.equal(r.codeModel, 'code');
  assert.equal(r.modelSource, 'env:UGC_MODEL');
  assert.equal(r.codeModelSource, 'env:UGC_CODE_MODEL');
});

test('missing local file uses the requested default; inherited primary selection is traceable', () => {
  const r = loadModelConfig({ env: {}, readFile: () => { throw Object.assign(new Error('missing'), { code: 'ENOENT' }); } });
  assert.equal(r.model, DEFAULT_MODEL);
  assert.equal(r.codeModel, DEFAULT_MODEL);
  assert.equal(r.modelSource, 'default');
  assert.equal(r.configFile, null);
  assert.equal(config({ model: 'one' }).codeModelSource, 'local:model');
});

test('invalid configuration never falls back and never echoes private file content', () => {
  for (const local of [null, [], { apiKey: 'PRIVATE_SENTINEL' }, { model: '' }, { model: 'x\nPRIVATE_SENTINEL' }]) {
    assert.throws(() => config(local), e => !e.message.includes('PRIVATE_SENTINEL'));
  }
  for (const env of [{ UGC_MODEL: '' }, { UGC_CODE_MODEL: ' bad ' }]) assert.throws(() => config({}, env), /环境变量无效/);
  assert.throws(() => loadModelConfig({ env: {}, readFile: () => '{PRIVATE_SENTINEL' }), e => !e.message.includes('PRIVATE_SENTINEL'));
  assert.throws(() => loadModelConfig({ env: {}, readFile: () => { throw Object.assign(new Error('PRIVATE_SENTINEL'), { code: 'EACCES' }); } }), /无法读取/);
});

test('image adapter preserves tool identity, text, errors, thinking and immutable stored history', () => {
  const image = { type: 'image', source: { type: 'base64', media_type: 'image/png', data: 'aGVsbG8=' } };
  const messages = [
    { role: 'assistant', content: [{ type: 'thinking', thinking: 'signed', signature: 'sig' }, { type: 'tool_use', id: 'shot1', name: 'capture', input: {} }] },
    { role: 'user', content: [{ type: 'tool_result', tool_use_id: 'shot1', is_error: true, content: [{ type: 'text', text: 'actual screenshot' }, image] }] },
  ];
  const original = structuredClone(messages);
  const adapted = messagesForModel(messages, DEFAULT_MODEL);
  assert.deepEqual(messages, original);
  assert.equal(adapted[0], messages[0]);
  assert.deepEqual(adapted[1].content[0], { type: 'tool_result', tool_use_id: 'shot1', is_error: true, content: [{ type: 'text', text: 'actual screenshot' }] });
  assert.equal(adapted.length, 3);
  assert.equal(adapted[2].role, 'user');
  assert.equal(adapted[2].content[1], image);
  assert.match(adapted[2].content[0].text, /shot1/);
  assert.ok(!adapted[1].content.some(x => x.type === 'image'), 'gateway drops images mixed into a tool-result message');
});

test('image-only results retain a valid tool result and multiple attachments keep their IDs', () => {
  const image = { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: 'eA==' } };
  const messages = [{ role: 'user', content: ['a', 'b'].map(id => ({ type: 'tool_result', tool_use_id: id, content: [image] })) }];
  const out = messagesForModel(messages, DEFAULT_MODEL);
  assert.deepEqual(out[0].content.map(x => x.tool_use_id), ['a', 'b']);
  assert.ok(out[0].content[0].content[0].text.length);
  assert.match(out[1].content[0].text, /a:/);
  assert.match(out[1].content[2].text, /b:/);
  assert.deepEqual(out[1].content.filter(x => x.type === 'image'), [image, image]);
});

test('other models and already top-level images pass through without compatibility changes', () => {
  const messages = [{ role: 'user', content: [{ type: 'text', text: 'x' }, { type: 'image', source: {} }] }];
  assert.equal(messagesForModel(messages, 'other-model'), messages);
  assert.equal(messagesForModel(messages, DEFAULT_MODEL)[0], messages[0]);
});
