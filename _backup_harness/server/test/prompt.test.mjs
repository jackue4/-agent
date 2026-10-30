import test from 'node:test';
import assert from 'node:assert/strict';
import { TOOLS, SYSTEM } from '../prompt.mjs';
import { GameEngine, emptyGame, ENTITY_KINDS, AMBIENTS, PLATFORM_STYLES } from '../engine.mjs';
import { jumpMetrics, jumpModel } from '../physics.mjs';

const TYPES = ['object', 'array', 'string', 'number', 'integer', 'boolean'];

/** Minimal JSON-Schema structural validator for the subset the tools use. */
function validateSchema(s, where) {
  assert.ok(s && typeof s === 'object', where + ': schema must be an object');
  assert.ok(TYPES.includes(s.type), where + ': bad type ' + s.type);
  if (s.enum) {
    assert.ok(Array.isArray(s.enum) && s.enum.length, where + ': enum must be a non-empty array');
    assert.equal(new Set(s.enum).size, s.enum.length, where + ': enum has duplicates');
  }
  if (s.type === 'object' && s.properties) {
    for (const [k, v] of Object.entries(s.properties)) validateSchema(v, where + '.' + k);
    for (const r of s.required || []) assert.ok(r in s.properties, where + ': required "' + r + '" not in properties');
  }
  if (s.type === 'array') {
    assert.ok(s.items, where + ': array needs items');
    validateSchema(s.items, where + '[]');
    if (s.minItems !== undefined && s.maxItems !== undefined) assert.ok(s.minItems <= s.maxItems, where);
  }
}

test('every tool has a valid name, description and object input schema', () => {
  const names = TOOLS.map(t => t.name);
  assert.equal(new Set(names).size, names.length, 'duplicate tool names');
  for (const t of TOOLS) {
    assert.match(t.name, /^[a-z_][a-z0-9_]{0,63}$/);
    assert.ok(t.description && t.description.length > 4);
    assert.equal(t.input_schema.type, 'object');
    validateSchema(t.input_schema, t.name);
    assert.ok(JSON.parse(JSON.stringify(t)), 'serializable');
  }
});

test('every tool is implemented by the engine', () => {
  const e = new GameEngine({ game: emptyGame() });
  for (const t of TOOLS) assert.equal(typeof e['tool_' + t.name], 'function', t.name);
});

const tool = n => TOOLS.find(t => t.name === n).input_schema;

test('schemas expose the new spec fields', () => {
  const entityKind = tool('add_entities').properties.entities.items.properties.kind.enum;
  assert.deepEqual(entityKind, ENTITY_KINDS);
  assert.ok(entityKind.includes('checkpoint'));
  const plan = tool('plan_game');
  assert.ok(plan.required.includes('palette') && plan.required.includes('art_bible'));
  assert.equal(plan.properties.palette.minItems, 3);
  assert.equal(plan.properties.palette.maxItems, 5);
  const world = tool('set_world').properties.world.properties;
  assert.deepEqual(world.ambient.enum, AMBIENTS);
  assert.deepEqual(world.platform_style.enum, PLATFORM_STYLES);
  assert.ok(world.platform_asset);
  assert.ok(tool('set_rules').properties.rules.properties.par_time);
  const applyTo = tool('generate_assets').properties.assets.items.properties.apply_to.description;
  assert.match(applyTo, /"platforms"/);
  assert.equal(tool('generate_assets').properties.assets.maxItems, 8);
});

test('system prompt carries the physics-derived metrics and the design rules', () => {
  const m2 = jumpMetrics(jumpModel('2d'));
  const m3 = jumpMetrics(jumpModel('3d'));
  for (const v of [m2.comfortGap, m2.jumpDistance, m2.jumpHeight, m2.comfortRise]) assert.ok(SYSTEM.includes(v + 'px'), 'missing 2D ' + v);
  for (const v of [m3.comfortGap, m3.jumpDistance, m3.jumpHeight]) assert.ok(SYSTEM.includes(v + 'm'), 'missing 3D ' + v);
  for (const phrase of ['教学 → 练习 → 挑战 → 高潮', '前 1/4', '3000-6000px', '15-30 个平台', 'checkpoint', 'check_game', 'platform_asset', 'platform_style', 'ambient', 'par_time', '不要用 emoji', 'palette', 'art_bible', '弧线', '不挡路']) {
    assert.ok(SYSTEM.includes(phrase), 'prompt lacks ' + phrase);
  }
  assert.ok(!/\$\{/.test(SYSTEM), 'no unrendered template placeholders');
});
