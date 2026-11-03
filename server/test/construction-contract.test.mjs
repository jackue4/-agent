import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { applyConstruction, commitConstruction, constructionScaffold, CONSTRUCTION_FILES } from '../construction.mjs';
import { GodotProject } from '../gproject.mjs';
import { ProjectSession, runProjectBuilder } from '../gpagent.mjs';
import { emptyGame } from '../engine.mjs';
import { createWorkflow } from '../workflow.mjs';
import { createIteration } from '../iteration.mjs';

const floor = (extra = {}) => ({ op: 'upsert', id: 'floor', kind: 'box', position: [0, -.5, 0], size: [24, 1, 24], color: '#456789', solid: true, ...extra });
const batch = (ops = [floor()], extra = {}) => ({ step: '真实地面', baseRevision: 0, ops, ...extra });
const initial = () => applyConstruction(null, batch(), { runId: 'real-run' });
const copy = value => structuredClone(value);

function fixture(t) {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'ugc-construction-'));
  const template = path.join(temporary, 'template');
  fs.mkdirSync(path.join(template, 'addons/ugc'), { recursive: true });
  for (const [file, content] of Object.entries({
    'project.godot': 'config_version=5\n[application]\nrun/main_scene="res://main.tscn"\n',
    'main.gd': 'extends Node3D\n', 'main.tscn': '[gd_scene format=3]\n[node name="Main" type="Node3D"]\n',
    'addons/ugc/ugc.gd': 'extends Node\n', 'export_presets.cfg': '[preset.0]\nname="Web"\n',
  })) fs.writeFileSync(path.join(template, file), content);
  const project = new GodotProject('fixture', { root: path.join(temporary, 'projects'), template,
    runGodot: () => { throw new Error('fast contract tests must not launch Godot'); } }).create();
  t.after(() => {
    assert.ok(path.resolve(temporary).startsWith(path.resolve(os.tmpdir()) + path.sep));
    assert.match(path.basename(temporary), /^ugc-construction-/);
    fs.rmSync(temporary, { recursive: true, force: true });
  });
  return project;
}

function sessionFixture(t, { dimension = '3d', required = true, signal } = {}) {
  const project = fixture(t), game = emptyGame(), events = [];
  game.meta = { ...game.meta, dimension, engine: 'godot' };
  const workflow = createWorkflow({ goal: 'small scene', sourceRevision: project.revision() });
  workflow.iteration = createIteration({ kind: required ? 'demo' : 'iteration' });
  const hooks = { signal, emit(event) { events.push(copy(event)); }, workflow() {}, assets: () => ({}) };
  const session = new ProjectSession(game, project, hooks, { workflow, requireVisibleConstruction: required });
  return { project, game, workflow, hooks, events, session };
}

async function twoBatches(f) {
  assert.equal((await f.session.exec('build_scene', batch())).ok, true);
  assert.equal((await f.session.exec('build_scene', batch([floor({ id: 'landmark', kind: 'cone', position: [5, 2, 0], size: [2, 4, 2] })], { baseRevision: 1 }))).ok, true);
}

test('scene commits have stable IDs and real numeric geometry, and later updates preserve untouched properties', () => {
  const first = initial();
  const second = applyConstruction(first, batch([{ op: 'upsert', id: 'floor', position: [2, -.5, 3] }, floor({ id: 'landmark', kind: 'cone', size: [2, 5, 2], position: [5, 2.5, 0] })], { baseRevision: 1 }), { runId: 'real-run' });
  assert.equal(second.revision, 2);
  assert.equal(second.dimension, '3d');
  assert.equal(second.runId, 'real-run');
  assert.equal(second.objects.length, 2);
  assert.deepEqual(second.objects[0].position, [2, -.5, 3]);
  assert.deepEqual(second.objects[0].size, [24, 1, 24]);
  assert.equal(second.objects[0].solid, true);
  assert.deepEqual(first, initial(), 'input snapshot must not mutate in place');
});

test('malformed final operation rejects the entire batch without leaking earlier valid operations', () => {
  const previous = initial(), before = copy(previous);
  assert.throws(() => applyConstruction(previous, batch([floor({ id: 'valid_new' }), floor({ id: 'bad_new', position: [Infinity, 0, 0] })], { baseRevision: 1 })), /有限数字/);
  assert.deepEqual(previous, before);
  assert.equal(previous.objects.some(o => o.id === 'valid_new'), false);
});

test('IDs reject JSON non-string values, paths, node traversal, duplicates and oversized identifiers', () => {
  for (const id of [null, 123, true, ['floor'], { name: 'floor' }, '', '../floor', 'floor/child', 'res://floor', 'x'.repeat(49)]) {
    assert.throws(() => applyConstruction(null, batch([floor({ id })])), undefined, 'must reject id ' + JSON.stringify(id));
  }
  assert.throws(() => applyConstruction(null, batch([floor(), floor()])), /重复|唯一/);
});

test('position, size and rotation reject non-finite, wrong-shape and coercible values', () => {
  for (const field of ['position', 'size', 'rotation']) {
    for (const value of [[NaN, 1, 1], [Infinity, 1, 1], [-Infinity, 1, 1], ['1', 1, 1], [1, 2], [1, 2, 3, 4], null]) {
      assert.throws(() => applyConstruction(null, batch([floor({ [field]: value })])), /有限数字/, field + ': ' + JSON.stringify(value));
    }
  }
  for (const value of [[0, 1, 1], [-1, 1, 1], [101, 1, 1]]) assert.throws(() => applyConstruction(null, batch([floor({ size: value })])));
  assert.throws(() => applyConstruction(null, batch([floor({ position: [201, 0, 0] })])));
  assert.throws(() => applyConstruction(null, batch([floor({ rotation: [361, 0, 0] })])));
});

test('unknown operations, shapes, colors and nonboolean collisions are rejected', () => {
  for (const invalid of [{ op: 'execute' }, { kind: 'Script' }, { color: 'url(secret)' }, { color: '#123' }, { solid: 'false' }]) {
    assert.throws(() => applyConstruction(null, batch([floor(invalid)])));
  }
  const safe = applyConstruction(null, batch([floor({ script: 'malicious.gd', code: 'PRIVATE_SOURCE', label: '层\u0000级\n'.repeat(30) })]));
  assert.doesNotMatch(JSON.stringify(safe), /PRIVATE_SOURCE|malicious\.gd/);
  assert.ok(safe.objects[0].label.length <= 60);
  assert.doesNotMatch(safe.objects[0].label, /[\u0000-\u001f]/);
});

test('each batch is small and total scene capacity cannot be exceeded', () => {
  for (const ops of [[], Array.from({ length: 9 }, (_, i) => floor({ id: `obj${i}` }))]) assert.throws(() => applyConstruction(null, batch(ops)));
  let state = null;
  for (let group = 0; group < 12; group++) state = applyConstruction(state, batch(Array.from({ length: 8 }, (_, i) => floor({ id: `obj${group * 8 + i}` })), { baseRevision: state?.revision || 0 }));
  assert.equal(state.objects.length, 96);
  const before = copy(state);
  assert.throws(() => applyConstruction(state, batch([floor({ id: 'overflow' })], { baseRevision: state.revision })), /96/);
  assert.deepEqual(state, before);
});

test('stale base revisions, unknown removal and no-op repeats cannot manufacture construction progress', () => {
  const first = initial();
  assert.throws(() => applyConstruction(first, batch([floor({ id: 'new' })], { baseRevision: 0 })), /版本/);
  assert.throws(() => applyConstruction(first, batch([{ op: 'remove', id: 'missing' }], { baseRevision: 1 })), /不存在/);
  assert.throws(() => applyConstruction(first, batch([floor()], { baseRevision: 1 })), /没有实际/);
  assert.equal(first.revision, 1);
});

test('degenerate or non-finite cameras are rejected before committing a snapshot', () => {
  for (const camera of [{ position: [0, 0, 0], lookAt: [0, 0, 0] }, { position: [0, 10, 0], lookAt: [0, 0, 0] }, { position: [NaN, 5, 5] }]) {
    assert.throws(() => applyConstruction(null, batch([floor()], { camera })));
  }
});

test('scaffold and final managed scene refer to the same canonical JSON, not a separate decorative scene', t => {
  const project = fixture(t), state = initial();
  const files = commitConstruction(project, state, { scaffold: true });
  assert.deepEqual(new Set(files), new Set(['main.gd', 'main.tscn', ...CONSTRUCTION_FILES]));
  assert.deepEqual(JSON.parse(project.read('scenes/construction.json')), state);
  assert.match(project.read('main.tscn'), /path="res:\/\/scenes\/construction\.tscn"/);
  assert.match(project.read('main.tscn'), /\[node name="Construction" parent="\." instance=ExtResource\("2"\)\]/);
  assert.match(project.read('scenes/construction.tscn'), /source_path = "res:\/\/scenes\/construction\.json"/);
  assert.match(project.read('scenes/construction.tscn'), /res:\/\/addons\/ugc\/construction_scene\.gd/);
  assert.match(constructionScaffold(state)['main.gd'], /Camera3D\.new/);
  assert.match(constructionScaffold(state)['main.gd'], /if view\.y > view\.x:\n\t\tcamera\.keep_aspect = Camera3D\.KEEP_WIDTH/);
});

test('later scene batches do not replace already-written gameplay scripts or their entry scene', t => {
  const project = fixture(t), first = initial();
  commitConstruction(project, first, { scaffold: true });
  project.write('main.gd', 'extends Node3D\nvar user_gameplay = 19\n');
  const main = project.read('main.tscn');
  const second = applyConstruction(first, batch([floor({ id: 'tower' })], { baseRevision: 1 }));
  commitConstruction(project, second);
  assert.match(project.read('main.gd'), /user_gameplay = 19/);
  assert.equal(project.read('main.tscn'), main);
  assert.equal(JSON.parse(project.read('scenes/construction.json')).objects.length, 2);
});

test('write rejection restores the whole prior bundle and build bookkeeping', t => {
  const project = fixture(t), first = initial();
  commitConstruction(project, first, { scaffold: true });
  const before = Object.fromEntries(project.list().map(f => [f.path, project.read(f.path)]));
  const previousState = copy(project.state), revision = project.revision();
  const second = applyConstruction(first, batch([floor({ id: 'tower' })], { baseRevision: 1 }));
  const write = project.write.bind(project); let rejected = false;
  project.write = (file, content) => {
    if (!rejected && file === 'scenes/construction.tscn') { rejected = true; return ['injected disk/validation rejection']; }
    return write(file, content);
  };
  assert.throws(() => commitConstruction(project, second), /injected/);
  assert.deepEqual(Object.fromEntries(project.list().map(f => [f.path, project.read(f.path)])), before);
  assert.deepEqual(project.state, previousState, 'a rejected commit cannot alter import/export or changed/deleted bookkeeping');
  assert.equal(project.revision(), revision);
});

test('first-batch failure leaves no orphan managed files and restores the original entry files', t => {
  const project = fixture(t), before = Object.fromEntries(project.list().map(f => [f.path, project.read(f.path)])), previousState = copy(project.state);
  const write = project.write.bind(project); let rejected = false;
  project.write = (file, content) => {
    if (!rejected && file === 'main.gd') { rejected = true; return ['injected scaffold failure']; }
    return write(file, content);
  };
  assert.throws(() => commitConstruction(project, initial(), { scaffold: true }), /injected/);
  assert.deepEqual(Object.fromEntries(project.list().map(f => [f.path, project.read(f.path)])), before);
  assert.deepEqual(project.state, previousState);
});

test('a new 3D demo must make two real nonempty scene commits before long code or delegation', async t => {
  const f = sessionFixture(t);
  for (const name of ['write_file', 'patch_file', 'delegate_tasks']) {
    assert.match((await f.session.exec(name, { path: 'main.gd', content: 'extends Node3D\n' })).error, /build_scene/);
  }
  assert.equal((await f.session.exec('build_scene', batch())).ok, true);
  assert.match((await f.session.exec('write_file', { path: 'logic.gd', content: 'extends Node\n' })).error, /build_scene/);
  assert.equal((await f.session.exec('build_scene', batch([{ op: 'remove', id: 'floor' }], { baseRevision: 1 }))).ok, true);
  assert.equal(f.game.construction.revision, 2);
  assert.match((await f.session.exec('write_file', { path: 'logic.gd', content: 'extends Node\n' })).error, /build_scene/, 'empty scene cannot unlock long code');
  assert.equal((await f.session.exec('build_scene', batch([floor()], { baseRevision: 2 }))).ok, true);
  assert.equal((await f.session.exec('write_file', { path: 'logic.gd', content: 'extends Node\n' })).saved, true);
});

test('2D projects retain ordinary writes and reject unsupported 3D scene tools honestly', async t => {
  const f = sessionFixture(t, { dimension: '2d' });
  assert.equal((await f.session.exec('write_file', { path: 'logic.gd', content: 'extends Node2D\n' })).saved, true);
  assert.match((await f.session.exec('build_scene', batch())).error, /3D|3d/);
  assert.equal(f.game.construction, undefined);
});

test('an existing completed 3D project continuation does not gain the new-demo construction gate', async t => {
  const f = sessionFixture(t, { required: false });
  f.game.meta.pck_version = 1;
  const original = f.project.read('main.tscn');
  let written;
  await runProjectBuilder({ ...f, isFirst: false, userText: '只调整原有操作', agentRunner: async options => {
    written = await options.exec('write_file', { path: 'legacy_fix.gd', content: 'extends Node\nvar preserved = true\n' });
    return { done: true };
  } });
  assert.equal(written.saved, true);
  assert.equal(f.game.construction, undefined);
  assert.equal(f.project.read('main.tscn'), original);
});

test('scene events are emitted only after the canonical file commit and do not manufacture game acceptance', async t => {
  const f = sessionFixture(t);
  f.hooks.emit = event => {
    if (event.type === 'construction') {
      assert.deepEqual(JSON.parse(f.project.read('scenes/construction.json')), event.snapshot);
      assert.equal(event.sourceRevision, f.project.revision());
    }
    f.events.push(copy(event));
  };
  await twoBatches(f);
  assert.equal(f.events.filter(e => e.type === 'construction').length, 2);
  assert.deepEqual(f.workflow.evidence, []);
  assert.equal(f.events.some(e => e.type === 'runtime_applied' || e.type === 'ops' && e.ops?.some(op => op.op === 'pck')), false);
});

test('invalid batch does not mutate game snapshot, files, revision, or emit construction completion', async t => {
  const f = sessionFixture(t); await twoBatches(f);
  const before = copy(f.game.construction), revision = f.project.revision(), events = f.events.filter(e => e.type === 'construction').length;
  const result = await f.session.exec('build_scene', batch([floor({ id: 'valid' }), floor({ id: 'bad', size: [NaN, 1, 1] })], { baseRevision: 2 }));
  assert.ok(result.error);
  assert.deepEqual(f.game.construction, before);
  assert.deepEqual(JSON.parse(f.project.read('scenes/construction.json')), before);
  assert.equal(f.project.revision(), revision);
  assert.equal(f.events.filter(e => e.type === 'construction').length, events);
});

test('managed files cannot be changed via spelling variants in ordinary write, patch or delete tools', async t => {
  const f = sessionFixture(t); await twoBatches(f);
  const revision = f.project.revision();
  for (const name of ['write_file', 'patch_file', 'delete_file']) {
    for (const file of ['scenes/construction.json', './scenes/construction.json', 'SCENES/CONSTRUCTION.JSON', 'scenes\\construction.json', 'res://scenes/construction.json', './scenes/construction.tscn']) {
      const result = await f.session.exec(name, { path: file, content: '{}', old: '"schema": 1', new: '"schema": 2' });
      assert.ok(result.error, name + ' must reject ' + file);
      assert.equal(f.project.revision(), revision, name + ' changed ' + file);
    }
  }
  const delegated = await f.session.exec('delegate_tasks', { tasks: [{ id: 'unsafe', title: 'wrong owner', role: 'scene', files: ['SCENES/CONSTRUCTION.JSON'], depends_on: [], prompt: 'replace', acceptance: ['works'] }] });
  assert.match(delegated.error, /build_scene|管理/);
});

test('pre-aborted and stopped sessions cannot commit or emit late construction', async t => {
  const controller = new AbortController(), f = sessionFixture(t, { signal: controller.signal });
  const revision = f.project.revision(); controller.abort(new Error('cancelled'));
  assert.ok((await f.session.exec('build_scene', batch())).error);
  assert.equal(f.project.revision(), revision);
  assert.equal(f.game.construction, undefined);
  assert.equal(f.events.some(e => e.type === 'construction'), false);
  const stopped = sessionFixture(t); stopped.session.savePartial('stopped', { cancelled: true });
  assert.ok((await stopped.session.exec('build_scene', batch())).error);
  assert.equal(stopped.game.construction, undefined);
});

test('cancellation while waiting for the shared project lock prevents a late scene write', async t => {
  const controller = new AbortController(), f = sessionFixture(t, { signal: controller.signal });
  let release, entered;
  const acquired = new Promise(resolve => { entered = resolve; });
  const blocked = f.project.withLock(async () => { entered(); await new Promise(resolve => { release = resolve; }); });
  await acquired;
  const revision = f.project.revision();
  const pending = f.session.exec('build_scene', batch());
  await new Promise(resolve => setImmediate(resolve));
  controller.abort(new Error('stopped before scene ownership'));
  release();
  await blocked;
  assert.ok((await pending).error);
  await f.project.withLock(() => {});
  assert.equal(f.project.revision(), revision);
  assert.equal(f.game.construction, undefined);
  assert.equal(f.events.some(e => e.type === 'construction'), false);
});
