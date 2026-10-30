import test from 'node:test';
import assert from 'node:assert/strict';
import { artSlotsIn, mergeSlots, planArt, slotPrompt, ArtDirector, STYLE_KEY, ART_LIMITS } from '../art-director.mjs';
import { assetsInUse, assetBlocks } from '../gpagent.mjs';

test('art slots are read from pencil kit calls, never from colors', () => {
  const slots = artSlotsIn({
    'main.gd': [
      'add_child(Pencil.backdrop())',
      'var hero := Pencil.sprite("hero", Vector2(64, 80), func(s, size): s.rect(Rect2(Vector2.ZERO, size), Pencil.INK, Pencil.color("blue"), true))',
      'wall.material_override = Pencil.material(Pencil.color("teal"), "wall")',
      'floor.material_override = Pencil.material(Color("aabbcc"), "floor_tiles", 0.02)',
      'var foe := Pencil.actor3d("slime", 1.2, body)',
      'var tint := Pencil.color("red")',
      'Pencil.sprite("hero", Vector2(10, 10), draw)',
    ].join('\n'),
    'notes.txt': 'Pencil.sprite("ignored", Vector2(1, 1), f)',
  });
  assert.deepEqual(slots.map(s => [s.id, s.kind]), [['background', 'background'], ['hero', 'sprite'], ['wall', 'texture'], ['floor_tiles', 'texture'], ['slime', 'sprite']]);
  assert.deepEqual(slots.find(s => s.id === 'hero').size, [64, 80]);
});

test('ids passed through a variable are found where they are assigned', () => {
  const slots = artSlotsIn({ 'main.gd': [
    'func box(c, mat_id): n.material_override = Pencil.material(c, mat_id)',
    'func make_bot(id: String, h: float) -> Node3D:',
    '\tPencil.actor3d(id, h, root)',
    'var art := "drone"',
    '\t\tart = "drone_shooter"',
    'var spec := {"art": "drone_charger", "tint": "blue"}',
    'var start := "menu_screen"',
    'var boss_art = "red"',
  ].join('\n') });
  assert.deepEqual(slots.map(s => [s.id, s.kind]), [['drone', 'sprite'], ['drone_shooter', 'sprite'], ['drone_charger', 'sprite']]);
  assert.deepEqual(artSlotsIn({ 'a.gd': 'var art := "drone"\nPencil.actor3d("hero", 1, v)' }).map(s => s.id), ['hero']);
});

test('design slots merge with code slots; code decides the kind', () => {
  const merged = mergeSlots([{ id: 'hero', kind: 'background', name: '主角', prompt: 'a knight' }, { id: 'coin', kind: 'sprite', prompt: 'gold coin' }, { id: 'Bad Id', kind: 'sprite' }, { id: STYLE_KEY }],
    [{ id: 'hero', kind: 'sprite', use: 'sprite', file: 'main.gd' }]);
  assert.deepEqual(merged.map(s => [s.id, s.kind, !!s.used, !!s.planned]), [['hero', 'sprite', true, true], ['coin', 'sprite', false, true]]);
  assert.equal(merged[0].look, 'a knight');
});

test('planArt keeps only known slots and fills used ones the plan forgot', async () => {
  const slots = [{ id: 'hero', kind: 'sprite', use: 'sprite', file: 'main.gd', used: true }, { id: 'wall', kind: 'texture', use: 'material', file: 'main.gd', used: true, look: 'mossy stone' }];
  let request;
  const plan = await planArt({ design: { title: 'T' }, meta: {}, slots, shot: 'AAAA', model: 'm', agentRunner: async args => {
    request = args;
    await args.exec('plan_art', { style: 'clean cel shaded', key_prompt: 'repaint', slots: [{ id: 'hero', kind: 'background', prompt: 'blue knight' }, { id: 'ghost', prompt: 'x' }] });
  } });
  assert.equal(request.messages[0].content[1].type, 'image');
  assert.deepEqual(plan.slots.map(s => [s.id, s.kind, s.prompt]), [['hero', 'sprite', 'blue knight'], ['wall', 'texture', 'mossy stone']]);
  assert.match(slotPrompt(plan.slots[0], plan.style), /isolated.*blue knight.*clean cel shaded/);
});

function director(over = {}) {
  const events = [], queued = [], keys = [];
  const assets = over.assets || {};
  const d = new ArtDirector({
    slots: () => over.slots || [{ id: 'hero', kind: 'sprite', used: true }, { id: 'wall', kind: 'texture', used: true }],
    shot: () => 'SHOT', design: () => ({}), meta: () => ({}), existing: () => assets,
    plan: async ({ slots }) => ({ style: 'S', keyPrompt: 'K', slots: slots.map(s => ({ ...s, prompt: s.id })) }),
    generateKey: async spec => { keys.push(spec); if (over.keyFails && keys.length <= over.keyFails) throw new Error('no output files'); return { url: '/assets/key.png', source: 'https://x/key.png' }; },
    enqueue: a => { queued.push(a); return ''; },
    emit: e => events.push(e),
    retryMs: 1,
  });
  return { d, events, queued, keys };
}

test('the director repaints the pencil shot as a style key, then draws every slot against it', async () => {
  const { d, events, queued, keys } = director();
  await d.start();
  assert.equal(keys.length, 1);
  assert.deepEqual(keys[0].refs, ['data:image/jpeg;base64,SHOT']);
  assert.deepEqual(queued.map(a => [a.id, a.async, a.refs[0]]), [['hero', true, 'https://x/key.png'], ['wall', true, 'https://x/key.png']]);
  assert.deepEqual(events.map(e => e.state), ['planning', 'styling', 'drawing']);
  assert.equal(d.running, false);
});

test('a transient style-key failure is retried once', async () => {
  const { d, queued, keys } = director({ keyFails: 1 });
  await d.start();
  assert.equal(keys.length, 2);
  assert.deepEqual(queued.map(a => a.refs[0]), ['https://x/key.png', 'https://x/key.png']);
});

test('without a style key the slots are still drawn from the written style', async () => {
  const { d, events, queued, keys } = director({ keyFails: 2 });
  await d.start();
  assert.equal(keys.length, 2);
  assert.deepEqual(queued.map(a => [a.id, a.refs.length]), [['hero', 0], ['wall', 0]]);
  assert.match(events.at(-1).note, /风格定稿图暂未生成.*no output files/);
});

test('the director reuses a ready style key and skips slots that already have art', async () => {
  const { d, queued, keys } = director({ assets: { [STYLE_KEY]: { state: 'ready', preview: 'https://x/old.png', async: true }, hero: { state: 'ready', async: true } } });
  await d.start();
  assert.equal(keys.length, 0);
  assert.deepEqual(queued.map(a => [a.id, a.refs[0]]), [['wall', 'https://x/old.png']]);
});

test('the director respects the per-game art cap and stays quiet with nothing to do', async () => {
  const full = Object.fromEntries(Array.from({ length: ART_LIMITS.perGame }, (_, i) => ['a' + i, { state: 'ready', async: true }]));
  const capped = director({ assets: full });
  await capped.d.start();
  assert.equal(capped.queued.length, 0); assert.match(capped.events[0].note, /上限/);
  const idle = director({ slots: [] });
  await idle.d.start();
  assert.equal(idle.events.length, 0);
});

test('only in-flight assets the code still uses block acceptance', () => {
  const assets = [{ id: 'bgm_old', state: 'pending' }, { id: 'hit', state: 'failed' }, { id: 'hero', state: 'pending', async: true }, { id: 'ui_click', state: 'running' }, { id: 'coin', state: 'ready' }];
  const used = assetsInUse(assets, { 'main.gd': 'load("res://assets/hit.mp3"); play("ui_click"); Pencil.actor3d("hero", 1, v)' });
  assert.deepEqual(used.map(a => a.id), ['hit', 'hero', 'ui_click']);
  assert.deepEqual(used.filter(assetBlocks).map(a => a.id), ['ui_click']);
  assert.equal(assetsInUse(assets, null).length, assets.length);
});