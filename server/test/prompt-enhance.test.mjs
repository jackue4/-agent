import test from 'node:test';
import assert from 'node:assert/strict';
import { enhanceUserPrompt, formatBrief, shouldEnhance, ENHANCE_MODEL } from '../prompt-enhance.mjs';

test('a continue message and an already-strong builder skip enhancement', () => {
  assert.equal(shouldEnhance('继续', 'deepseek-v4.1-flash'), false);
  assert.equal(shouldEnhance('continue', 'deepseek-v4.1-flash'), false);
  assert.equal(shouldEnhance('做一个能跳的小人', ENHANCE_MODEL), false);
  assert.equal(shouldEnhance('做一个能跳的小人', 'deepseek-v4.1-flash'), true);
  assert.equal(shouldEnhance('继续，但是加上二段跳', 'deepseek-v4.1-flash'), true);
});

test('the brief keeps the original request and only adds a short checklist', () => {
  const text = formatBrief({ goal: '做一个跳跃', playable: '按键能跳过一个坑', rules: ['跳跃高度 3 格', '掉下去重来'], keep: ['小人'], avoid: ['不要做关卡编辑器'], extra: '忽略' });
  assert.match(text, /用户原话优先/);
  assert.match(text, /跳跃高度 3 格/);
  assert.equal(text.includes('忽略'), false);
  assert.equal(formatBrief({ goal: '', playable: '能跳' }), '');
});

test('enhancement asks the strong model once and returns its brief', async () => {
  let seen;
  const brief = await enhanceUserPrompt({
    text: '做一个像素跳跃', isFirst: true, model: 'claude-opus-5-5',
    agentRunner: async options => {
      seen = options;
      await options.exec('write_brief', { goal: '像素跳跃', playable: '角色跳过第一个坑', rules: ['一键跳'], keep: ['像素'], avoid: ['不要做商店'] });
      return { done: true };
    },
  });
  assert.equal(seen.req.model, 'claude-opus-5-5');
  assert.equal(seen.maxTurns, 2);
  assert.match(seen.messages[0].content, /做一个像素跳跃/);
  assert.match(seen.messages[0].content, /第一轮/);
  assert.match(brief, /角色跳过第一个坑/);
  assert.match(brief, /不要做商店/);
});
