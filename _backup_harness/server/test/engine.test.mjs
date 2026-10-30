import test from 'node:test';
import assert from 'node:assert/strict';
import { GameEngine, emptyGame, normalizeEntity, normalizeMeta, normalizeWorld, normalizeRules, checkGame, emojiIssues, ENTITY_KINDS, KIND_CN, AMBIENTS, PLATFORM_STYLES } from '../engine.mjs';
import { newEngine, check, plat2, onTop2, hasIssue, issueTexts } from './helpers.mjs';

// ------------------------------------------------------------ normalizeEntity

test('normalizeEntity fills 2D defaults per kind, including checkpoint', () => {
  const cp = normalizeEntity('cp1', { kind: 'checkpoint', position: [10, 20] }, '2d');
  assert.deepEqual(cp, { kind: 'checkpoint', id: 'cp1', position: [10, 20], size: [56, 110], color: '#4cc9f0' });
  assert.deepEqual(normalizeEntity('g', { kind: 'goal', position: [0, 0] }, '2d').size, [72, 120]);
  assert.deepEqual(normalizeEntity('p', { kind: 'platform', position: [0, 0] }, '2d').size, [200, 40]);
});

test('normalizeEntity fills 3D defaults and expands 2D vectors', () => {
  assert.deepEqual(normalizeEntity('cp', { kind: 'checkpoint', position: [1, 2, 3] }, '3d').size, [1, 2.2, 1]);
  const e = normalizeEntity('x', { kind: 'platform', position: [5, 7], size: [3, 1] }, '3d');
  assert.deepEqual(e.position, [5, 1, 7], 'a 2-vector position becomes [x, 1, z]');
  assert.deepEqual(e.size, [3, 1, 3], 'a 2-vector size gets depth = width');
});

test('normalizeEntity coerces junk safely', () => {
  const e = normalizeEntity('j', { kind: 'dragon', position: ['12', null], size: [-5, 'abc'] }, '2d');
  assert.equal(e.kind, 'decor', 'unknown kinds fall back to decor');
  assert.deepEqual(e.position, [12, 0]);
  assert.deepEqual(e.size, [4, 110], 'sizes are clamped and NaN replaced by defaults');
  assert.deepEqual(normalizeEntity('s', '{"kind":"enemy","position":[1,2]}', '2d').position, [1, 2], 'JSON strings are accepted');
  assert.deepEqual(normalizeEntity('n', null, '3d').position, [0, 1, 0]);
  assert.equal(normalizeEntity('c', { kind: 'enemy', position: [0, 0], color: '#123456' }, '2d').color, '#123456', 'explicit colours are kept');
  assert.equal(normalizeEntity('player', { kind: 'player', position: [0, 0] }, '2d').id, undefined, 'player has no id field');
});

test('entity kinds and Chinese names cover checkpoint', () => {
  assert.ok(ENTITY_KINDS.includes('checkpoint'));
  assert.ok(!ENTITY_KINDS.includes('player'));
  for (const k of ENTITY_KINDS) assert.ok(KIND_CN[k], 'missing KIND_CN for ' + k);
});

// ------------------------------------------------------------ meta / world / rules

test('normalizeMeta validates palette and art bible', () => {
  assert.deepEqual(normalizeMeta({ palette: ['#ff0000', '#00ff00', '#00f', 'red', '#123456', '#abcdef', '#000000'] }).palette, ['#ff0000', '#00ff00', '#00f', '#123456', '#abcdef']);
  assert.equal(normalizeMeta({ palette: ['#ff0000', 'blue'] }).palette, undefined, 'fewer than 3 valid colours are dropped');
  assert.equal(normalizeMeta({ palette: '["#111111","#222222","#333333"]' }).palette.length, 3, 'JSON-string palette accepted');
  assert.equal(normalizeMeta({ art_bible: '  soft   pastel\nstorybook ' }).art_bible, 'soft pastel storybook');
  assert.equal(normalizeMeta({ art_bible: '   ' }).art_bible, undefined);
  assert.equal(normalizeMeta({ art_bible: 'x'.repeat(500) }).art_bible.length, 300);
});

test('normalizeWorld keeps only known ambients', () => {
  for (const a of AMBIENTS) assert.equal(normalizeWorld({ ambient: a }).ambient, a);
  assert.equal(normalizeWorld({ ambient: 'fireflies' }).ambient, undefined);
  assert.deepEqual(normalizeWorld({ platform_asset: 'tile' }), { platform_asset: 'tile' });
});

test('normalizeWorld keeps only known platform styles', () => {
  assert.deepEqual(PLATFORM_STYLES, ['grass', 'snow', 'stone', 'wood', 'candy', 'sand', 'ice', 'lava', 'cloud', 'metal']);
  for (const s of PLATFORM_STYLES) assert.equal(normalizeWorld({ platform_style: s }).platform_style, s);
  assert.equal(normalizeWorld({ platform_style: 'marble' }).platform_style, undefined);
  assert.equal('platform_style' in normalizeWorld({}), false);
});

test('emoji in player-visible text is reported as a warning', () => {
  const g = emptyGame();
  assert.deepEqual(emojiIssues(g), []);
  g.rules.instructions = '跑到终点🏁';
  g.rules.win_text = '赢啦！';
  g.entities.s = { id: 's', kind: 'sign', text: '小心❤️' };
  g.entities.t = { id: 't', kind: 'text', text: '★ 第一关 →' };
  const issues = emojiIssues(g);
  assert.equal(issues.length, 1);
  assert.equal(issues[0].level, 'warn');
  assert.match(issues[0].text, /rules\.instructions、s$/);
});

test('normalizeRules keeps a positive rounded par_time', () => {
  assert.equal(normalizeRules({ par_time: '45.6' }).par_time, 46);
  assert.equal(normalizeRules({ par_time: 0 }).par_time, undefined);
  assert.equal(normalizeRules({ par_time: 'soon' }).par_time, undefined);
  assert.equal('par_time' in normalizeRules({ win: 'goal' }), false);
});

// ------------------------------------------------------------ tool ops

test('plan_game sets meta (palette, art_bible) and resets physics for the dimension', () => {
  const e = new GameEngine({ game: emptyGame() });
  const { ops, result } = e.apply('plan_game', { title: '森林', dimension: '3d', genre: 'platformer', style: 'lowpoly', pitch: 'p', steps: ['a'], palette: ['#112233', '#445566', '#778899'], art_bible: 'chunky low poly toy world' });
  assert.equal(result.ok, true);
  assert.equal(ops.length, 1);
  assert.equal(ops[0].op, 'set_meta');
  assert.match(ops[0].label, /森林/);
  assert.deepEqual(e.game.meta.palette, ['#112233', '#445566', '#778899']);
  assert.equal(e.game.meta.art_bible, 'chunky low poly toy world');
  assert.equal(e.game.meta.filter, 'smooth');
  assert.deepEqual(e.game.settings, { gravity: 24 });
  assert.equal(e.game.player.position.length, 3, 'player converted to 3D');
});

test('plan_game converts existing entities when switching dimension', () => {
  const e = newEngine();
  e.apply('add_entities', { step: 's', entities: [{ id: 'a', kind: 'platform', position: [100, 0] }] });
  e.apply('plan_game', { title: 't', dimension: '3d', genre: 'platformer', style: 'pixel', pitch: '', steps: [] });
  assert.equal(e.game.entities.a.position.length, 3);
  assert.equal(e.game.meta.filter, 'pixel');
});

test('set_world merges, normalizes ambient, and emits set_world', () => {
  const e = newEngine();
  e.apply('set_world', { world: { background_color: '#000', ambient: 'snow' } });
  const { ops } = e.apply('set_world', { label: '下雪了', world: { platform_asset: 'tile', ambient: 'lava' } });
  assert.deepEqual(ops, [{ op: 'set_world', world: { background_color: '#000', platform_asset: 'tile' }, label: '下雪了' }]);
});

test('set_rules merges and emits set_rules with par_time', () => {
  const e = newEngine();
  const { ops } = e.apply('set_rules', { rules: { par_time: 60, lives: 5 } });
  assert.equal(ops[0].op, 'set_rules');
  assert.equal(ops[0].rules.par_time, 60);
  assert.equal(ops[0].rules.win, 'goal', 'existing rule fields kept');
});

test('set_player normalizes and emits set_player', () => {
  const e = newEngine();
  const { ops } = e.apply('set_player', { player: { position: [5, 50], speed: 400 } });
  assert.equal(ops[0].op, 'set_player');
  assert.deepEqual(ops[0].player.size, [64, 64]);
  assert.equal(ops[0].player.speed, 400);
  assert.equal(ops[0].player.kind, 'player');
});

test('add_entities emits one add op per entity, dedupes and cleans ids', () => {
  const e = newEngine();
  e.apply('add_entities', { step: 's', entities: [{ id: 'coin', kind: 'collectible', position: [0, 0] }] });
  const { ops, result } = e.apply('add_entities', { step: 's', entities: [{ id: 'coin', kind: 'collectible', position: [10, 0], name: '金币' }, { id: 'bad id!', kind: 'checkpoint', position: [0, 0] }, { kind: 'enemy', position: [1, 1] }] });
  assert.deepEqual(ops.map(o => o.op), ['add', 'add', 'add']);
  assert.equal(ops[0].id, 'coin_b');
  assert.equal(ops[0].label, '收集物：金币');
  assert.equal(ops[1].id, 'bad_id_');
  assert.equal(ops[1].label, '检查点：bad_id_');
  assert.match(ops[2].id, /^e_/);
  assert.equal(result.entities, 4);
});

test('add_entities accepts a JSON-string array and ignores non-arrays', () => {
  const e = newEngine();
  assert.equal(e.apply('add_entities', { step: 's', entities: '[{"id":"a","kind":"platform","position":[0,0]}]' }).ops.length, 1);
  assert.equal(e.apply('add_entities', { step: 's', entities: 'not json' }).ops.length, 0);
  assert.equal(e.apply('add_entities', '{"step":"s","entities":[{"id":"b","kind":"goal","position":[0,0]}]}').ops.length, 1, 'whole input as JSON string');
});

test('update_entities shallow-merges, re-normalizes and skips unknown ids', () => {
  const e = newEngine();
  e.apply('add_entities', { step: 's', entities: [{ id: 'a', kind: 'platform', position: [0, 0], name: '石台' }] });
  const { ops } = e.apply('update_entities', { step: 's', changes: [{ id: 'a', size: [300, 40], kind: 'checkpoint' }, { id: 'nope', size: [1, 1] }] });
  assert.equal(ops.length, 1);
  assert.equal(ops[0].op, 'update');
  assert.equal(ops[0].label, '调整：石台');
  assert.deepEqual(e.game.entities.a.size, [300, 40]);
  assert.equal(e.game.entities.a.kind, 'checkpoint');
  assert.equal(e.game.entities.a.name, '石台');
});

test('remove_entities emits remove ops only for existing ids', () => {
  const e = newEngine();
  e.apply('add_entities', { step: 's', entities: [{ id: 'a', kind: 'platform', position: [0, 0] }] });
  const { ops, result } = e.apply('remove_entities', { ids: ['a', 'ghost'] });
  assert.deepEqual(ops, [{ op: 'remove', id: 'a', label: '移除：a' }]);
  assert.equal(result.entities, 0);
});

test('unknown tool returns an error result without ops', () => {
  const e = newEngine();
  assert.deepEqual(e.apply('teleport', {}), { ops: [], result: { error: 'unknown tool teleport' } });
});

test('finish and check_game return results without ops', () => {
  const e = newEngine();
  assert.deepEqual(e.apply('finish', { summary: 's', suggestions: [] }), { ops: [], result: { ok: true } });
  const c = e.apply('check_game', {});
  assert.deepEqual(c.ops, []);
  assert.equal(typeof c.result.ok, 'boolean');
});

// ------------------------------------------------------------ generate_assets binding

function assetEngine() {
  const e = newEngine();
  e.apply('add_entities', { step: 's', entities: [
    { id: 'slime1', kind: 'enemy', position: [0, 0] }, { id: 'slime2', kind: 'enemy', position: [100, 0] }, { id: 'coin', kind: 'collectible', position: [0, 0] },
  ] });
  return e;
}

test('generate_assets starts jobs and emits pending asset ops', () => {
  const e = assetEngine();
  const { ops, jobs, result } = e.apply('generate_assets', { assets: [{ id: 'hero', kind: 'sprite', name: '小狐狸', prompt: 'fox', apply_to: ['player'] }] });
  assert.deepEqual(jobs, ['hero']);
  assert.deepEqual(result.started, ['hero']);
  assert.match(result.note, /后台/);
  assert.deepEqual(ops[0], { op: 'asset', id: 'hero', kind: 'sprite', state: 'pending', url: '' });
  assert.equal(ops[1].op, 'set_player');
  assert.equal(ops[1].player.asset, 'hero');
  assert.equal(e.game.assets.hero.state, 'pending');
});

test('generate_assets binds world targets including platforms', () => {
  const e = assetEngine();
  const { ops } = e.apply('generate_assets', { assets: [
    { id: 'bg', kind: 'background', name: '森林', prompt: 'forest', apply_to: ['background'] },
    { id: 'tile', kind: 'texture', name: '草地砖', prompt: 'grass', apply_to: ['platforms'] },
    { id: 'gtex', kind: 'texture', name: '地面', prompt: 'dirt', apply_to: ['ground'] },
    { id: 'bgm', kind: 'music', name: '音乐', prompt: 'happy', apply_to: ['music'] },
  ] });
  const w = e.game.world;
  assert.equal(w.background_asset, 'bg');
  assert.equal(w.platform_asset, 'tile');
  assert.equal(w.ground_asset, 'gtex');
  assert.equal(w.music_asset, 'bgm');
  const labels = ops.filter(o => o.op === 'set_world').map(o => o.label);
  assert.deepEqual(labels, ['换上背景', '平台换上贴图', '地面换上贴图', '配上音乐']);
});

test('generate_assets binds sfx, kind: groups and single entities', () => {
  const e = assetEngine();
  const { ops } = e.apply('generate_assets', { assets: [
    { id: 'ding', kind: 'sfx', name: '叮', prompt: 'coin', apply_to: ['sfx:coin'] },
    { id: 'slime', kind: 'sprite', name: '史莱姆', prompt: 'slime', apply_to: ['kind:enemy'] },
    { id: 'gold', kind: 'sprite', name: '金币', prompt: 'coin', apply_to: ['coin', 'missing_id'] },
  ] });
  assert.equal(e.game.sounds.coin, 'ding');
  assert.equal(e.game.entities.slime1.asset, 'slime');
  assert.equal(e.game.entities.slime2.asset, 'slime');
  assert.equal(e.game.entities.coin.asset, 'gold');
  assert.deepEqual(ops.filter(o => o.op === 'update').map(o => o.id), ['slime1', 'slime2', 'coin']);
});

test('generate_assets reuses an identical pending/ready asset but regenerates failed or changed ones', () => {
  const e = assetEngine();
  const a = { id: 'hero', kind: 'sprite', name: 'h', prompt: 'fox', apply_to: [] };
  e.apply('generate_assets', { assets: [a] });
  assert.deepEqual(e.apply('generate_assets', { assets: [a] }).jobs, []);
  e.game.assets.hero.state = 'failed';
  assert.deepEqual(e.apply('generate_assets', { assets: [a] }).jobs, ['hero']);
  assert.deepEqual(e.apply('generate_assets', { assets: [{ ...a, prompt: 'wolf' }] }).jobs, ['hero']);
});

test('generate_assets caps a call at 8 assets', () => {
  const e = assetEngine();
  const assets = Array.from({ length: 12 }, (_, i) => ({ id: 'a' + i, kind: 'sprite', name: 'n', prompt: 'p' + i, apply_to: [] }));
  assert.equal(e.apply('generate_assets', { assets }).jobs.length, 8);
});

// ------------------------------------------------------------ check_game: rules & shape

test('check_game result shape keeps the frontend contract and adds path', () => {
  const r = check({ player: { position: [100, 40] }, entities: [plat2('a', 0, 400, 0), onTop2('goal', 'goal', 300, 0), onTop2('c', 'collectible', 200, 0)] });
  assert.deepEqual(Object.keys(r).sort(), ['counts', 'issues', 'metrics', 'ok', 'path']);
  assert.deepEqual(r.counts, { entities: 3, platforms: 1, collectibles: 1, enemies: 0, goals: 1, checkpoints: 0 });
  for (const k of ['jumpHeight', 'jumpDistance', 'comfortGap', 'comfortRise', 'bounceHeight']) assert.equal(typeof r.metrics[k], 'number');
  assert.deepEqual(Object.keys(r.path).sort(), ['criticalPath', 'hardestJump', 'isolated', 'spawn', 'target', 'tooHard', 'unreachable']);
  assert.ok(r.issues.every(i => (i.level === 'error' || i.level === 'warn') && typeof i.text === 'string' && typeof i.hint === 'string'));
  assert.equal(r.ok, true, issueTexts(r).join('\n'));
});

test('check_game rule issues: missing goal / collectibles / enemies / score / instructions', () => {
  const base = [plat2('a', 0, 400, 0)];
  const p = { position: [100, 40] };
  assert.ok(hasIssue(check({ player: p, entities: base }), 'error', /没有放置终点/));
  assert.ok(hasIssue(check({ player: p, entities: base, rules: { win: 'collect_all' } }), 'error', /没有收集物/));
  assert.ok(hasIssue(check({ player: p, entities: base, rules: { win: 'defeat_all' } }), 'error', /没有敌人/));
  assert.ok(hasIssue(check({ player: p, entities: base, rules: { win: 'score' } }), 'error', /分数目标/));
  assert.ok(!hasIssue(check({ player: p, entities: base, rules: { win: 'score', target_score: 50 } }), 'error', /分数目标/));
  assert.ok(hasIssue(check({ player: p, entities: base }), 'warn', /没有收集物/));
  assert.ok(hasIssue(check({ player: p, entities: base, rules: { instructions: ' ' } }), 'warn', /操作\/目标提示/));
  assert.ok(hasIssue(check({ player: p, entities: base, rules: { lose_text: '再来😢' } }), 'warn', /emoji/));
});

test('check_game uses custom player physics in metrics', () => {
  const r = check({ player: { position: [100, 40], jump: 1000 }, entities: [plat2('a', 0, 400, 0)] });
  assert.ok(r.metrics.jumpHeight > 160);
});

test('checkGame works directly on stored games (no engine)', () => {
  const g = emptyGame();
  g.entities.a = normalizeEntity('a', plat2('a', -100, 400, 0), '2d');
  g.player.position = [0, 40];
  const r = checkGame(g);
  assert.equal(r.path.spawn, 'a');
});

// ------------------------------------------------------------ check_game: top-down

const td = (entities, player = { position: [0, 0] }) => check({ genre: 'topdown', player, entities });
const room = [
  { id: 'wall_top', kind: 'platform', position: [0, 600], size: [1600, 40], solid: true },
  { id: 'wall_bottom', kind: 'platform', position: [0, -600], size: [1600, 40], solid: true },
  { id: 'wall_left', kind: 'platform', position: [-800, 0], size: [40, 1200], solid: true },
  { id: 'wall_right', kind: 'platform', position: [800, 0], size: [40, 1200], solid: true },
];

test('top-down: clean map has no jump checks and no path', () => {
  const r = td([...room, { id: 'goal', kind: 'goal', position: [500, 300] }, { id: 'c', kind: 'collectible', position: [200, 0] }]);
  assert.equal(r.ok, true, issueTexts(r).join('\n'));
  assert.equal(r.path, null);
  assert.ok(!r.issues.some(i => /跳|孤岛|出生点下方/.test(i.text)));
});

test('top-down: player in a wall is an error, items in walls warn', () => {
  const r = td([...room, { id: 'goal', kind: 'goal', position: [500, 300] }, { id: 'c', kind: 'collectible', position: [800, 0] }], { position: [-800, 0] });
  assert.ok(hasIssue(r, 'error', /主角」和墙体/));
  assert.ok(hasIssue(r, 'warn', /「c」和墙体「wall_right」重叠/));
});

test('top-down: overlapping actors warn, enemy on spawn is an error', () => {
  const r = td([...room, { id: 'goal', kind: 'goal', position: [500, 300] }, { id: 'c1', kind: 'collectible', position: [200, 0] }, { id: 'c2', kind: 'collectible', position: [210, 0] }, { id: 'bat', kind: 'enemy', position: [10, 10] }]);
  assert.ok(hasIssue(r, 'warn', /「c1」和「c2」叠在一起/));
  assert.ok(hasIssue(r, 'error', /出生点和「bat」重叠/));
});

test('top-down: things outside the walled area are flagged, a single wall strip is not a map', () => {
  const r = td([...room, { id: 'goal', kind: 'goal', position: [2000, 0] }, { id: 'c', kind: 'collectible', position: [0, 200] }]);
  assert.ok(hasIssue(r, 'warn', /「goal」在地图边界/));
  const strip = td([{ id: 'w', kind: 'platform', position: [0, 300], size: [1000, 40], solid: true }, { id: 'goal', kind: 'goal', position: [400, 0] }, { id: 'c', kind: 'collectible', position: [-200, 0] }]);
  assert.ok(!strip.issues.some(i => /边界/.test(i.text)), issueTexts(strip).join('\n'));
});
test('a sign on top of the spawn point is flagged as hidden behind the player', () => {
  const base = { entities: [plat2('g', -200, 1200, 0), onTop2('goal', 'goal', 800, 0)], player: { position: [0, 40] } };
  const hidden = check({ ...base, entities: [...base.entities, { id: 's', kind: 'sign', text: '加油', position: [20, 40], size: [160, 80] }] });
  assert.ok(hasIssue(hidden, 'warn', /告示牌.*出生点重叠/), issueTexts(hidden).join('\n'));
  const clear = check({ ...base, entities: [...base.entities, { id: 's', kind: 'sign', text: '加油', position: [300, 40], size: [160, 80] }] });
  assert.ok(!hasIssue(clear, 'warn', /告示牌/), issueTexts(clear).join('\n'));
});

test('3D sign beside the spawn on another z lane is not flagged', () => {
  const ents = [{ id: 'g', kind: 'platform', position: [0, -0.3, 0], size: [10, 0.6, 10] }, { id: 'goal', kind: 'goal', position: [3, 1.6, 0] }];
  const r = check({ dimension: '3d', entities: [...ents, { id: 's', kind: 'sign', text: 'hi', position: [0, 1, 4], size: [2.4, 1.4, 0.2] }], player: { position: [0, 1, 0] } });
  assert.ok(!hasIssue(r, 'warn', /告示牌/), issueTexts(r).join('\n'));
});
