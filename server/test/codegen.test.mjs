import test from 'node:test';
import assert from 'node:assert/strict';
import { wantsCodeEngine, normalizePlan, CodeSession, designBrief, codeTurnPrompt, codeTail, readyAssets, moduleOwner, screenOf, roleOf, webText, outline, CODE_SYSTEM } from '../codegen.mjs';
import { staticCheck, bannedIssues, parseReport, parseStderrErrors } from '../runner.mjs';

test('routing: card/puzzle prompts use the code engine, platformers and 3D keep the template agent', () => {
  assert.equal(wantsCodeEngine('做一个小丑牌', '2d'), true);
  assert.equal(wantsCodeEngine('UNO 卡牌对战', '2d'), true);
  assert.equal(wantsCodeEngine('消消乐', '2d'), true);
  assert.equal(wantsCodeEngine('横版跑酷小狐狸', '2d'), false);
  assert.equal(wantsCodeEngine('马里奥那样的平台跳跃', '2d'), false);
  assert.equal(wantsCodeEngine('做一个小丑牌', '3d'), false);
});

test('static check blocks unsafe APIs and bad preloads but allows normal code', () => {
  const ok = 'extends Control\nconst Deck = preload("deck.gd")\nfunc _ready() -> void:\n\tvar s := "OS.exit in a string is fine" # OS. in a comment too\n\tG.sfx("pop")\n';
  assert.deepEqual(staticCheck('main.gd', ok), []);
  const bad = 'extends Node\nfunc _ready():\n\tOS.shell_open("x")\n\tvar f = FileAccess.open("user://a", 1)\n\tvar r = load("res://main.gd")\n\tJavaScriptBridge.eval("1")\n';
  const issues = staticCheck('main.gd', bad).join('\n');
  for (const w of ['OS', 'FileAccess', 'load()', 'JavaScriptBridge']) assert.match(issues, new RegExp(w.replace(/[()]/g, '\\$&')));
  assert.ok(staticCheck('main.gd', 'extends Node\nconst X = preload("res://kit.gd")\n').some(i => /preload/.test(i)));
  assert.ok(staticCheck('Main.gd', 'extends Node\n').length > 0);
  assert.ok(staticCheck('a.gd', 'func f():\n\tpass\n').some(i => /extends/.test(i)));
  assert.ok(staticCheck('a.gd', 'extends Node\nclass_name Foo\n').length > 0);
});

test('runner parses the autotest line and Godot error lines for ugc files', () => {
  const r = parseReport('noise\n[autotest] {"loaded":true,"errors":[],"checks":[{"ok":true,"what":"x"}],"has_test":true}\n');
  assert.equal(r.loaded, true);
  assert.equal(parseReport('nothing'), null);
  const errs = parseStderrErrors('SCRIPT ERROR: Parse Error: Unexpected "Indent".\n   at: GDScript::reload (user://ugc/1_2/v1/deck.gd:12)\nERROR: other\n   at: foo (core/x.cpp:3)\n');
  assert.deepEqual(errs, [{ file: 'deck.gd', line: 12, message: 'Parse Error: Unexpected "Indent".', kind: 'error' }]);
});

test('normalizePlan fills milestones, filters palette and bounds sizes', () => {
  const p = normalizePlan({ title: 'x'.repeat(50), palette: ['#ff0000', 'red', '#00ff00'], controls: [['点击', '选牌'], ['bad']] });
  assert.equal(p.title.length, 24);
  assert.deepEqual(p.palette, ['#ff0000', '#00ff00']);
  assert.equal(p.milestones[0].id, 'M1');
  assert.equal(p.controls.length, 1);
  assert.equal(p.current, 0);
});

function session() {
  const game = { meta: { title: 't', palette: [] }, code: { files: {} }, design: normalizePlan({ milestones: [{ id: 'M1', name: 'a', goal: 'g', acceptance: [] }, { id: 'M2', name: 'b', goal: 'g', acceptance: [] }] }) };
  const events = [];
  const s = new CodeSession(game, { emit: e => events.push(e), pushCode: () => {} });
  return { s, game, events };
}

test('write/patch modules: static issues reject the write, patches need a unique anchor', async () => {
  const { s, game, events } = session();
  const bad = await s.exec('write_module', { file: 'deck.gd', step: 's', code: 'extends RefCounted\nfunc f():\n\tOS.exit()\n' });
  assert.ok(bad.error);
  assert.equal(game.code.files['deck.gd'], undefined);
  const ok = await s.exec('write_module', { file: 'deck.gd', step: '洗牌', code: 'extends RefCounted\nfunc a() -> int:\n\treturn 1\nfunc b() -> int:\n\treturn 1\n' });
  assert.equal(ok.ok, true);
  assert.equal(events.at(-1).type, 'code_write');
  assert.ok((await s.exec('patch_module', { file: 'deck.gd', old: 'return 1', new: 'return 2' })).error); // ambiguous
  assert.equal((await s.exec('patch_module', { file: 'deck.gd', old: 'func a() -> int:\n\treturn 1', new: 'func a() -> int:\n\treturn 3' })).ok, true);
  assert.match(game.code.files['deck.gd'], /return 3/);
  assert.ok((await s.exec('delete_module', { file: 'main.gd' })).error);
});

test('update_plan keeps finished milestones; prompts carry the design and the current target', async () => {
  const { s, game } = session();
  game.design.current = 1;
  await s.exec('update_plan', { milestones: [{ id: 'M2', name: '新', goal: 'x', acceptance: ['y'] }, { id: 'M3', name: 'c', goal: 'z', acceptance: [] }] });
  assert.deepEqual(game.design.milestones.map(m => m.id), ['M1', 'M2', 'M3']);
  assert.equal(game.design.milestones[1].name, '新');
  assert.match(designBrief(game.design), /\[本轮目标\] M2/);
  assert.match(codeTurnPrompt(game, '继续', false), /推进里程碑 M2/);
  await s.exec('finish', { summary: 'ok', suggestions: ['a', 'b', 'c', 'd'], milestone_done: 'M2' });
  assert.equal(s.finish.suggestions.length, 3);
});

test('plan tool schema: required fields are unique and all declared', async () => {
  const fs = await import('node:fs');
  const t = fs.readFileSync(new URL('../codegen.mjs', import.meta.url), 'utf8');
  const req = JSON.parse(t.match(/required: (\['title'[^\]]*\])/)[1].replace(/'/g, '"'));
  assert.equal(new Set(req).size, req.length);
});

test('crew: streaming helpers show typed code and release finished asset prompts early', () => {
  const t = codeTail('{"step":"牌桌","file":"main.gd","code":"extends Control\\nfunc _ready():\\n\\tvar a = 1\\n\\tvar b');
  assert.equal(t.total, 4);
  assert.match(t.tail, /^extends Control/);
  assert.match(t.tail, /  var b$/);
  assert.equal(codeTail('{"step":"x","file":"a.gd"'), null);
  const one = { assets: [{ id: 'bg', kind: 'background', name: '牌桌', prompt: 'green felt' }, { id: 'j', name: '小丑', prompt: 'jok' }] };
  assert.deepEqual(readyAssets(one).map(a => a.id), ['bg']);
  assert.deepEqual(readyAssets({ ...one, genre: 'card' }).map(a => a.id), ['bg', 'j']);
});

test('crew roles: design work shows as A, scene files as C, logic and playtesting as B', () => {
  assert.equal(moduleOwner({ file: 'main.gd', owner: 'gameplay' }), 'scene');
  assert.equal(moduleOwner({ file: 'card_view.gd' }), 'scene');
  assert.equal(moduleOwner({ file: 'rules.gd' }), 'gameplay');
  const d = normalizePlan({ modules: [{ file: 'deck.gd', owner: 'gameplay' }, { file: 'table.gd', owner: 'gameplay' }] });
  assert.equal(roleOf('design_game', {}, null), 'A');
  assert.equal(roleOf('web_fetch', {}, null), 'A');
  assert.equal(roleOf('write_module', { file: 'main.gd' }, d), 'C');
  assert.equal(roleOf('write_module', { file: 'table.gd' }, d), 'B');   // the plan's owner beats the file-name guess
  assert.equal(roleOf('patch_module', { file: 'hud.gd' }, d), 'C');
  assert.equal(roleOf('game_eval', {}, d), 'B');
});

test('design_game stores the plan once and keeps the chosen orientation', async () => {
  const game = { meta: { title: 't', orientation: 'portrait' }, code: { files: {} } };
  const seen = [];
  const s = new CodeSession(game, { emit() {}, pushCode() {}, onDesign: d => seen.push(d) });
  assert.equal(s.role, 'A');
  const r = await s.exec('design_game', { title: '小丑牌', faithful: true, closest_game: 'Balatro', rules: ['a'], modules: [{ file: 'main.gd' }] });
  assert.equal(r.ok, true);
  assert.equal(game.design.orientation, 'portrait');
  assert.equal(game.design.faithful, true);
  assert.equal(seen.length, 1);
  assert.match(designBrief(game.design), /复刻：Balatro/);
  assert.ok((await s.exec('design_game', { title: 'again' })).error);
});

test('read_module and grep_code show numbered source', async () => {
  const { s, game } = session();
  game.code.files['deck.gd'] = 'extends RefCounted\nvar cards = []\nfunc draw() -> int:\n\treturn 1\n';
  const r = await s.exec('read_module', { file: 'deck.gd', offset: 3, limit: 1 });
  assert.equal(r.total_lines, 5);
  assert.match(r.text, /^\s+3\| func draw/);
  assert.ok((await s.exec('read_module', { file: 'nope.gd' })).error);
  const g = await s.exec('grep_code', { pattern: 'cards = [' });   // invalid regex falls back to plain text
  assert.equal(g.matches, 1);
  assert.match(g.results, /deck\.gd:2:/);
  assert.match(outline(game.code.files['deck.gd']), /3\| func draw/);
});

test('budget: past soft the result asks to wrap up, past hard only finish runs', async () => {
  const { s } = session();
  s.budget = { soft: 1, hard: 2 };
  s.t0 = Date.now() - 90000;
  const soft = await s.exec('grep_code', { pattern: 'x' });
  assert.match(soft.time_note, /请收尾/);
  s.t0 = Date.now() - 150000;
  assert.match((await s.exec('write_module', { file: 'a.gd', step: 's', code: 'extends Node\n' })).error, /时间已用完/);
  assert.equal((await s.exec('finish', { summary: 'done' })).ok, true);
  assert.equal(s.overHard(), true);
});

test('game_eval refuses banned APIs and preload before touching the game', async () => {
  const { s } = session();
  assert.match((await s.exec('game_eval', { code: 'OS.shell_open("x")' })).error, /OS/);
  assert.match((await s.exec('game_eval', { code: 'var R = preload("rules.gd")' })).error, /preload/);
  assert.match((await s.exec('game_eval', { code: 'return 1' })).error, /main\.gd/);
  assert.deepEqual(bannedIssues('eval', 'return "OS.exit"  # FileAccess'), []);
});

test('web_fetch text: strips markup, keeps table cells apart, rejects private hosts', async () => {
  const t = webText('<html><head><title>x</title></head><body><script>var a=1</script><h2>Jokers</h2><table><tr><td>Joker</td><td>+4 Mult</td></tr></table><p>a &amp; b</p></body></html>');
  assert.match(t, /Jokers/);
  assert.match(t, /Joker \| \+4 Mult/);
  assert.match(t, /a & b/);
  assert.doesNotMatch(t, /var a/);
  assert.equal(webText('== Wikitext ==\n\n\n\nline'), '== Wikitext ==\n\nline');
  const { s } = session();
  assert.match((await s.exec('web_fetch', { url: 'http://10.0.4.94:5300/' })).error, /公网/);
  assert.match((await s.exec('web_fetch', { url: 'file:///c:/x' })).error, /公网/);
});

test('prompts: a named game is replicated, follow-ups carry the recap and outline long code', () => {
  assert.match(CODE_SYSTEM, /不要换皮/);
  const fresh = { meta: { orientation: 'portrait', genre_hint: '卡牌' }, code: { files: {} } };
  const p0 = codeTurnPrompt(fresh, '做一个小丑牌', true);
  assert.match(p0, /竖屏/);
  assert.match(p0, /【类型】卡牌/);
  assert.match(p0, /design_game/);
  const game = { meta: {}, design: normalizePlan({ title: 'x' }), code: { files: { 'main.gd': 'extends Control\nfunc _ready():\n\t' + 'pass\n\t'.repeat(15000) } } };
  const p1 = codeTurnPrompt(game, '把按钮改大', false, '- 用户：「做一个小丑牌」→ 能玩一局');
  assert.match(p1, /之前几轮[\s\S]*做一个小丑牌/);
  assert.match(p1, /只列出顶层声明/);
  assert.match(p1, /2\| func _ready/);
});

test('orientation: portrait choice reaches the plan, the brief and the test runner', () => {
  assert.equal(screenOf('portrait').w, 720);
  assert.equal(screenOf('whatever').o, 'landscape');
  const d = normalizePlan({ orientation: 'portrait' });
  assert.equal(d.orientation, 'portrait');
  assert.match(designBrief(d), /竖屏 720x1280/);
  assert.match(designBrief(normalizePlan({})), /横屏 1280x720/);
  const s = new CodeSession({ meta: { title: 't', orientation: 'portrait' }, code: { files: {} } }, { emit() {}, pushCode() {} });
  assert.equal(s.meta.orientation, 'portrait');
});
