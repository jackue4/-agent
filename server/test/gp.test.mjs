import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { readPck, writePck, patchPck } from '../pck.mjs';
import { safePath, scanIssues, classCache, stderrErrors, tagged, GodotProject, GP_ROOT } from '../gproject.mjs';
import { gpRoleOf, gpBrief, gpTurnPrompt, ProjectSession, GP_SYSTEM, assetPath } from '../gpagent.mjs';
import { normalizePlan } from '../codegen.mjs';

const pack = files => writePck({ version: { format: 3, major: 4, minor: 7, patch: 2 }, files: new Map(Object.entries(files).map(([k, v]) => [k, Buffer.from(v)])) });

test('pck: written packs read back file for file, aligned', () => {
  const buf = pack({ 'project.binary': 'PB', 'main.gdc': 'tokens', 'main.gd.remap': '[remap]\npath="res://main.gdc"\n', 'a/b.txt': 'x'.repeat(33) });
  assert.equal(buf.readUInt32LE(0), 0x43504447);
  const back = readPck(buf);
  assert.equal(back.version.minor, 7);
  assert.deepEqual([...back.files.keys()], ['project.binary', 'main.gdc', 'main.gd.remap', 'a/b.txt']);
  assert.equal(back.files.get('a/b.txt').toString(), 'x'.repeat(33));
  assert.deepEqual(writePck(back), buf);
});

test('pck: a patched script replaces the exported token and remap files', () => {
  const base = pack({ 'project.binary': 'PB', 'main.gdc': 'tokens', 'main.gd.remap': 'r', 'main.tscn.remap': 'r2', 'old.gdc': 't', 'old.gd.remap': 'r3' });
  const out = readPck(patchPck(base, { files: { 'main.gd': 'extends Node\n', 'main.tscn': '[gd_scene format=3]\n' }, deleted: ['old.gd'], extra: { '.godot/global_script_class_cache.cfg': 'list=[]\n' } }));
  const names = [...out.files.keys()].sort();
  assert.deepEqual(names, ['.godot/global_script_class_cache.cfg', 'main.gd', 'main.tscn', 'project.binary']);
  assert.equal(out.files.get('main.gd').toString(), 'extends Node\n');
});

test('paths: only the editable part of the project is reachable', () => {
  assert.equal(safePath('res://scenes/level.tscn'), 'scenes/level.tscn');
  assert.equal(safePath('scripts\\player.gd'), 'scripts/player.gd');
  for (const bad of ['../x.gd', '/etc/passwd', 'C:/x.gd', 'a//b.gd', '.godot/x.cfg', 'build/game.pck', 'addons/ugc/ugc.gd', 'addons/ugc', '中文.gd', '']) {
    assert.throws(() => safePath(bad), undefined, bad);
  }
});

test('scan: native features pass, escapes out of the sandbox do not', () => {
  const ok = 'class_name Hero\nextends CharacterBody2D\nconst Bullet = preload("res://bullet.tscn")\nfunc _ready():\n\tvar t = load("res://assets/hero.png")\n\tvar f = FileAccess.open("user://save.json", FileAccess.WRITE)\n\tprint(OS.get_name(), ProjectSettings.get_setting("display/window/size/viewport_width"))\n\t# OS.execute is only mentioned in a comment\n\tvar s = "JavaScriptBridge in a string"\n';
  assert.deepEqual(scanIssues('hero.gd', ok), []);
  const bad = {
    'OS 系统命令': 'func f():\n\tOS.execute("cmd", [])',
    'OS 作为值传递': 'func f():\n\tvar o = OS\n\to.call("execute")',
    JavaScriptBridge: 'func f():\n\tJavaScriptBridge.eval("alert(1)")',
    网络访问: 'var h := HTTPRequest.new()',
    动态生成代码: 'func f():\n\tvar g = GDScript.new()',
    '动态取单例/动态执行': 'func f():\n\tEngine.get_singleton("JavaScriptBridge")',
    编辑器: '@tool\nextends Node',
    'res:// 或 user://': 'func f(p):\n\tFileAccess.open(p, FileAccess.READ)',
  };
  for (const [what, src] of Object.entries(bad)) assert.ok(scanIssues('x.gd', src).some(i => i.includes(what)), what + ' → ' + scanIssues('x.gd', src));
  assert.ok(scanIssues('a.tscn', '[sub_resource type="GDScript" id="1"]\nscript/source = "extends Node\\nfunc _ready(): OS.shell_open(\\"x\\")"').length > 0);
  assert.ok(scanIssues('x.gd', 'var p = "C:/Windows/system32"').some(i => i.includes('绝对路径')));
});

test('class cache: class_name scripts with their global base class', () => {
  const cfg = classCache({
    'actors/hero.gd': 'class_name Hero\nextends CharacterBody2D\n',
    'actors/boss.gd': '@icon("res://x.svg")\nclass_name Boss extends "res://actors/hero.gd"\n',
    'util.gd': 'extends Node\n',
    'data/deck.gd': '@abstract\nclass_name Deck\n',
  });
  assert.match(cfg, /^list=\[/);
  assert.match(cfg, /"class": &"Hero"[\s\S]*?"path": "res:\/\/actors\/hero.gd"/);
  assert.match(cfg, /"base": &"Hero",\n"class": &"Boss"/);
  assert.match(cfg, /"base": &"RefCounted",\n"class": &"Deck",\n"icon": "",\n"is_abstract": true/);
  assert.doesNotMatch(cfg, /util\.gd/);
  assert.equal(classCache({ 'a.gd': 'extends Node\n' }), 'list=[]\n');
});

test('godot output: errors for project files are kept, the platform plugin is ignored', () => {
  const out = 'SCRIPT ERROR: Parse Error: Identifier "foo" not declared.\n   at: GDScript::reload (res://scripts/player.gd:12)\nERROR: Failed loading resource: res://assets/hero.png.\nERROR: x\n   at: (res://addons/ugc/ugc.gd:3)\n[ugc-check] {"loaded":true,"errors":[]}\n';
  const errs = stderrErrors(out);
  assert.deepEqual(errs.map(e => e.file + ':' + e.line), ['scripts/player.gd:12', 'assets/hero.png:0']);
  assert.deepEqual(tagged(out, 'ugc-check'), { loaded: true, errors: [] });
});

test('project: template copy is sized for the orientation and keeps the platform hooks', () => {
  const id = 'unit_' + process.pid;
  const p = new GodotProject(id);
  try {
    p.create({ title: '竖屏 "测试"', orientation: 'portrait' });
    const pg = fs.readFileSync(path.join(p.dir, 'project.godot'), 'utf8');
    assert.match(pg, /viewport_width=720/);
    assert.match(pg, /viewport_height=1280/);
    assert.match(pg, /config\/name="竖屏 测试"/);
    assert.deepEqual(p.write('project.godot', '[application]\nrun/main_scene="res://main.tscn"\n'), []);
    p.syncPlatform();
    const synced = fs.readFileSync(path.join(p.dir, 'project.godot'), 'utf8');
    assert.match(synced, /^config_version=5/);
    assert.match(synced, /UGC="\*res:\/\/addons\/ugc\/ugc\.gd"/);
    assert.match(synced, /theme\/custom_font="res:\/\/addons\/ugc\/font\.ttf"/);
    assert.ok(p.state.needsExport);
    assert.deepEqual(p.write('scripts/a.gd', 'extends Node\n'), []);
    assert.deepEqual(p.state.changed, ['scripts/a.gd']);
    assert.ok(p.list().some(f => f.path === 'scripts/a.gd') && !p.list().some(f => f.path.startsWith('addons/ugc')));
    assert.ok(p.write('art.png', 'x')[0].includes('素材工具'));
    assert.ok(p.remove('scripts/a.gd'));
    assert.deepEqual(p.state.deleted, ['scripts/a.gd']);
  } finally { fs.rmSync(p.dir, { recursive: true, force: true }); }
  assert.ok(p.dir.startsWith(GP_ROOT));
});

test('gp roles: scenes, shaders and view scripts are C, logic is B, design and art are A', () => {
  const d = normalizePlan({ modules: [{ file: 'scripts/board.gd', owner: 'gameplay' }] });
  assert.equal(gpRoleOf('design_game', {}, d), 'A');
  assert.equal(gpRoleOf('generate_asset', {}, d), 'A');
  assert.equal(gpRoleOf('write_file', { path: 'levels/level1.tscn' }, d), 'C');
  assert.equal(gpRoleOf('patch_file', { path: 'shaders/glow.gdshader' }, d), 'C');
  assert.equal(gpRoleOf('write_file', { path: 'scripts/hud.gd' }, d), 'C');
  assert.equal(gpRoleOf('write_file', { path: 'scripts/board.gd' }, d), 'B');
  assert.equal(gpRoleOf('write_file', { path: 'scripts/rules.gd' }, d), 'B');
  assert.equal(gpRoleOf('game_eval', {}, d), 'B');
});

test('gp prompts: native Godot is described, follow-ups list the project', () => {
  assert.match(GP_SYSTEM, /class_name/);
  assert.match(GP_SYSTEM, /\.tscn/);
  assert.match(GP_SYSTEM, /3D/);
  assert.match(GP_SYSTEM, /UGC\.press/);
  assert.equal(assetPath({ id: 'hero', kind: 'model3d' }), 'assets/hero.glb');
  assert.equal(assetPath({ id: 'bgm', kind: 'music', url: '/assets/abc.mp3' }), 'assets/bgm.mp3');
  const fake = { list: () => [{ path: 'main.gd' }, { path: 'main.tscn' }], sources: () => ({ 'main.gd': 'extends Node2D\nfunc _ready():\n\tpass\n' }) };
  const fresh = gpTurnPrompt({ meta: { orientation: 'portrait', dimension: '3d' } }, fake, '做一个 3D 跑酷', true);
  assert.match(fresh, /竖屏/);
  assert.match(fresh, /3D 游戏/);
  assert.match(fresh, /【竖屏 3D】.*KEEP_WIDTH/);
  assert.doesNotMatch(gpTurnPrompt({ meta: { orientation: 'landscape', dimension: '3d' } }, fake, '做一个 3D 跑酷', true), /KEEP_WIDTH/);
  assert.doesNotMatch(gpTurnPrompt({ meta: { orientation: 'portrait' } }, fake, '做一个跑酷', true), /KEEP_WIDTH/);
  const d = { ...normalizePlan({ title: '跑酷', rules: ['跳'] }), dimension: '3d' };
  assert.match(gpBrief(d), /3D/);
  assert.doesNotMatch(gpBrief(d), /KEEP_WIDTH/);
  assert.match(gpBrief({ ...d, orientation: 'portrait' }), /竖屏 3D：.*KEEP_WIDTH/);
  const next = gpTurnPrompt({ meta: {}, design: d }, fake, '把跳跃调高一点', false, '- 用户：「做跑酷」→ 能跑');
  assert.match(next, /# 工程文件\nmain\.gd\nmain\.tscn/);
  assert.match(next, /2\| func _ready/);
  assert.match(next, /之前几轮/);
});

test('gp session: writes are scanned, patched in place, reported per file', async () => {
  const id = 'unit_s_' + process.pid;
  const project = new GodotProject(id).create({});
  const events = [];
  const game = { meta: { orientation: 'landscape' }, design: normalizePlan({ title: 't' }) };
  const s = new ProjectSession(game, project, { emit: e => events.push(e) });
  s.tryLoad = async () => ({ ok: true, loaded: true });
  try {
    assert.match((await s.exec('write_file', { path: 'evil.gd', step: 'x', content: 'extends Node\nfunc f():\n\tOS.execute("x", [])\n' })).error, /OS 系统命令/);
    assert.equal((await s.exec('write_file', { path: 'scripts/rules.gd', step: '规则', content: 'extends RefCounted\nfunc score(a):\n\treturn a * 2\n' })).ok, true);
    assert.equal(events.at(-1).type, 'code_write');
    assert.equal(events.at(-1).created, true);
    assert.equal((await s.exec('patch_file', { path: 'scripts/rules.gd', old: 'a * 2', new: 'a * 3' })).ok, true);
    assert.match(project.read('scripts/rules.gd'), /a \* 3/);
    assert.match((await s.exec('read_file', { path: 'scripts/rules.gd', offset: 3, limit: 1 })).text, /^\s+3\| \treturn a \* 3/);
    assert.match((await s.exec('grep_files', { pattern: 'func score', path: 'scripts' })).results, /scripts\/rules\.gd:2:/);
    assert.match((await s.exec('list_files', {})).files, /scripts\/rules\.gd/);
    assert.ok((await s.exec('read_file', { path: 'addons/ugc/ugc.gd' })).error);
    assert.ok((await s.exec('write_file', { path: 'addons/ugc/ugc.gd', step: 'x', content: 'x' })).error);
    assert.match((await s.exec('game_eval', { code: 'JavaScriptBridge.eval("1")' })).error, /JavaScriptBridge/);
    assert.deepEqual([...s.changed], ['scripts/rules.gd']);
  } finally { fs.rmSync(project.dir, { recursive: true, force: true }); }
});

test('gp design: art is optional and no more than two new assets are requested per round', async () => {
  const design = async assets => {
    const asked = [];
    const s = new ProjectSession({ meta: {}, design: null }, { exists: true, revision: () => 'a'.repeat(64) }, { emit() {}, requestAsset: a => { asked.push(a.id); return ''; } });
    return { r: await s.exec('design_game', { title: 't', assets }), asked };
  };
  const thin = await design([{ id: 'bg', kind: 'background', name: '背景', prompt: 'sky' }, { id: 'music', kind: 'music', name: '音乐', prompt: 'chiptune' }]);
  assert.deepEqual(thin.asked, ['bg', 'music']);
  assert.equal(thin.r.notes.length, 0);
  const rich = await design(['hero', 'enemy', 'coin'].map(id => ({ id, kind: 'sprite', name: id, prompt: id })).concat([{ id: 'ground', kind: 'texture', name: '地面', prompt: 'grass' }]));
  assert.deepEqual(rich.asked, ['hero', 'enemy']);
  assert.match(rich.r.notes.join(' '), /下一轮/);
  assert.match(rich.r.assets.join(' '), /hero → res:\/\/assets\/hero\.png/);
});
