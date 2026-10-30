import test from 'node:test';
import assert from 'node:assert/strict';
import { parseLooseJson, parsePartialJson } from '../json.mjs';

test('parses plain JSON', () => {
  assert.deepEqual(parseLooseJson('{"a":1,"b":[1,2]}'), { a: 1, b: [1, 2] });
  assert.deepEqual(parseLooseJson('[1,2]'), [1, 2]);
});

test('strips code fences and surrounding prose', () => {
  assert.deepEqual(parseLooseJson('好的：\n```json\n{"a":1}\n```\n完成'), { a: 1 });
  assert.deepEqual(parseLooseJson('result => {"x":"y"} done'), { x: 'y' });
});

test('tolerates trailing commas but not inside strings', () => {
  assert.deepEqual(parseLooseJson('{"a":[1,2,],}'), { a: [1, 2] });
  assert.deepEqual(parseLooseJson('{"t":"a,]"}'), { t: 'a,]' });
});

test('returns the fallback for truncated or invalid input', () => {
  assert.equal(parseLooseJson('{"a":[1,2'), null);
  assert.equal(parseLooseJson('', 'fb'), 'fb');
  assert.equal(parseLooseJson('nope', 0), 0);
  assert.equal(parseLooseJson(undefined), null);
});

test('partial JSON: streaming tool input is closed for progress display', () => {
  assert.equal(parsePartialJson(''), null);
  assert.deepEqual(parsePartialJson('{"title":"脸谱牌'), { title: '脸谱牌' });
  assert.deepEqual(parsePartialJson('{"a":1,"rules":["x","y'), { a: 1, rules: ['x', 'y'] });
  assert.deepEqual(parsePartialJson('{"a":1,"ti'), { a: 1 });
  assert.deepEqual(parsePartialJson('{"a":1,"title":'), { a: 1 });
  assert.deepEqual(parsePartialJson('{"code":"line1\\nli'), { code: 'line1\nli' });
  assert.deepEqual(parsePartialJson('{"code":"a\\'), { code: 'a' });
  assert.deepEqual(parsePartialJson('{"m":[{"file":"a.gd","role":"x"},{"fi'), { m: [{ file: 'a.gd', role: 'x' }, {}] });
});
