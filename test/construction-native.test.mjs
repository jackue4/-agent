import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const godot = process.env.GODOT_BIN || path.join(root, 'tools/godot/Godot_v4.7.2-stable_win64_console.exe');

test('native 3D construction uses committed geometry, shares game loader, rejects stale data and stops workers', { skip: !fs.existsSync(godot), timeout: 90000 }, t => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'ugc-construction-native-'));
  t.after(() => fs.rmSync(fixture, { recursive: true, force: true }));
  fs.cpSync(path.join(root, 'workshop'), fixture, { recursive: true });
  fs.cpSync(path.join(root, 'gp_template/addons'), path.join(fixture, 'addons'), { recursive: true });
  fs.renameSync(path.join(fixture, 'main.gd'), path.join(fixture, 'yard_root.gd'));
  fs.copyFileSync(path.join(root, 'test/fixtures/construction-native.gd'), path.join(fixture, 'main.gd'));
  const run = args => spawnSync(godot, ['--headless', '--path', fixture, ...args], { encoding: 'utf8', windowsHide: true, timeout: 60000 });
  const imported = run(['--editor', '--import', '--quit']);
  assert.equal(imported.status, 0, imported.stderr || imported.error?.message);
  assert.doesNotMatch(imported.stdout + imported.stderr, /SCRIPT ERROR:|Parse Error:/);
  const played = run(['--quit-after', '600']);
  assert.equal(played.status, 0, played.stdout + played.stderr || played.error?.message);
  assert.doesNotMatch(played.stdout + played.stderr, /SCRIPT ERROR:|Parse Error:|ERROR:/);
  const line = played.stdout.split(/\r?\n/).find(value => value.startsWith('CONSTRUCTION_NATIVE_RESULT '));
  assert.ok(line, played.stdout);
  const result = JSON.parse(line.slice('CONSTRUCTION_NATIVE_RESULT '.length));
  assert.ok(result.checks >= 30, result);
  assert.deepEqual(result.failed, []);
});
