import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const godot = process.env.GODOT_BIN || path.join(root, 'tools/godot/Godot_v4.7.2-stable_win64_console.exe');

test('native build fairy flies, assembles the real screen, stops and never mutates gameplay', { skip: !fs.existsSync(godot), timeout: 90000 }, t => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'ugc-crew-native-'));
  t.after(() => fs.rmSync(fixture, { recursive: true, force: true }));
  fs.cpSync(path.join(root, 'gp_template/addons'), path.join(fixture, 'addons'), { recursive: true });
  fs.copyFileSync(path.join(root, 'gp_template/project.godot'), path.join(fixture, 'project.godot'));
  fs.copyFileSync(path.join(root, 'test/fixtures/crew-native.gd'), path.join(fixture, 'main.gd'));
  fs.writeFileSync(path.join(fixture, 'main.tscn'), '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://main.gd" id="1"]\n[node name="CrewTest" type="Node2D"]\nscript = ExtResource("1")\n');
  const run = args => spawnSync(godot, ['--headless', '--path', fixture, ...args], { encoding: 'utf8', windowsHide: true, timeout: 60000 });
  const imported = run(['--editor', '--import', '--quit']);
  assert.equal(imported.status, 0, imported.stderr || imported.error?.message);
  // A fresh copy may report its custom font before the editor's first import. Runtime must be clean.
  const played = run(['--quit-after', '180']);
  assert.equal(played.status, 0, played.stderr || played.error?.message);
  assert.doesNotMatch(played.stdout + played.stderr, /SCRIPT ERROR:|Parse Error:|ERROR:/);
  const line = played.stdout.split(/\r?\n/).find(value => value.startsWith('CREW_NATIVE_RESULT '));
  assert.ok(line, played.stdout);
  const result = JSON.parse(line.slice('CREW_NATIVE_RESULT '.length));
  assert.equal(result.checks, 28);
  assert.deepEqual(result.failed, []);
});
