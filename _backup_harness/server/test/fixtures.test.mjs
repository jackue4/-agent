import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { checkGame } from '../engine.mjs';

const load = name => {
  const raw = JSON.parse(fs.readFileSync(new URL('../../test/' + name, import.meta.url), 'utf8'));
  return raw.spec || raw;
};

for (const name of ['spec2d.json', 'spec3d.json']) {
  test('stored sample game ' + name + ' passes check_game with everything reachable', () => {
    const spec = load(name);
    const r = checkGame(spec);
    assert.equal(r.ok, true, r.issues.map(i => i.text).join('\n'));
    assert.ok(r.path.spawn, 'spawn surface found');
    assert.deepEqual(r.path.unreachable, []);
    assert.deepEqual(r.path.isolated, []);
    if (r.path.target) assert.ok(r.path.criticalPath.length >= 1);
    assert.deepEqual(spec, load(name), 'checking never mutates the stored game');
  });
}
