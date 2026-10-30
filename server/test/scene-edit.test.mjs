import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { applyConstruction, commitConstruction } from '../construction.mjs';
import { moveConstruction } from '../scene-edit.mjs';
import { createWorkflow } from '../workflow.mjs';
const data = fs.mkdtempSync(path.join(os.tmpdir(), 'ugc-scene-edit-test-'));
process.env.UGC_DATA_DIR = data;
const api = await import('../server.mjs');
after(() => fs.rmSync(data, { recursive: true, force: true }));
const scene = () => applyConstruction(null, { ops: [{ op: 'upsert', id: 'floor', kind: 'box', position: [0, -.5, 0], size: [12, 1, 12], solid: true }, { op: 'upsert', id: 'crate', label: '箱子', kind: 'box', position: [1, .5, 2], size: [1, 1, 1], color: '#ffc857', solid: true }] }, { runId: 'round' });
const edit = (snapshot, change = {}) => ({ id: 'crate', position: [3, .5, 4], baseRevision: snapshot.revision, requestId: crypto.randomUUID(), ...change });
function fixture() {
  const p = new api.Project({}); p.game.meta.engine = 'godot'; p.game.meta.dimension = '3d';
  api.projects.set(p.id, p); const project = api.gpOf(p); project.create();
  p.game.construction = scene(); commitConstruction(project, p.game.construction, { scaffold: true });
  p.workflow = createWorkflow({ goal: 'fixture', sourceRevision: project.revision() }); p.workflow.status = 'completed'; p.workflow.completionRequested = true; p.save();
  return { p, project };
}
test('manual movement preserves identity, geometry and all other scene objects', () => {
  const original = scene(), next = moveConstruction(original, edit(original));
  assert.equal(next.revision, 2); assert.equal(next.runId, original.runId);
  assert.deepEqual(next.objects[0], original.objects[0]);
  assert.deepEqual(next.objects[1], { ...original.objects[1], position: [3, .5, 4] });
  assert.deepEqual(original.objects[1].position, [1, .5, 2]);
});
test('stale, missing, malformed and unchanged movements cannot produce a scene revision', () => {
  const s = scene();
  for (const change of [{ baseRevision: 0 }, { baseRevision: undefined }, { id: 'missing' }, { position: [1,2] }, { position: [Infinity,0,0] }, { position: ['1',0,0] }, { position: [201,0,0] }, { requestId: '../bad' }, { position: [1,.5,2] }]) assert.throws(() => moveConstruction(s, edit(s, change)));
});
test('saved scene edits survive reload and invalidate old acceptance, with idempotent retries', async () => {
  const { p, project } = fixture(), body = edit(p.game.construction);
  const result = await api.editScene(p, body); assert.equal(result.status, 200);
  assert.equal(p.workflow.status, 'partial'); assert.equal(p.workflow.completionRequested, false);
  assert.deepEqual(JSON.parse(project.read('scenes/construction.json')), p.game.construction);
  const restored = new api.Project(JSON.parse(fs.readFileSync(p.file())));
  assert.equal(api.projectView(restored).sceneDirty, true); assert.equal(restored.game.construction.revision, 2);
  assert.equal((await api.editScene(p, body)).status, 200); assert.equal(p.game.construction.revision, 2);
  assert.equal((await api.editScene(p, { ...body, position: [0,0,0] })).status, 409);
  assert.equal((await api.editScene(p, edit(p.game.construction, { baseRevision: 1 }))).status, 409);
  assert.equal(p.log.some(e => e.type === 'construction' && e.origin === 'user'), true);
  assert.equal(p.log.some(e => e.type === 'runtime_applied'), false);
});
test('busy editors reject transformations and reverse movement uses a fresh revision', async () => {
  const { p } = fixture(); p.running = true;
  assert.equal((await api.editScene(p, edit(p.game.construction))).status, 409); p.running = false; p.mutating = true;
  assert.equal((await api.editScene(p, edit(p.game.construction))).status, 409); p.mutating = false;
  await api.editScene(p, edit(p.game.construction));
  const undo = await api.editScene(p, edit(p.game.construction, { position: [1,.5,2] }));
  assert.equal(undo.status, 200); assert.equal(p.game.construction.revision, 3); assert.deepEqual(p.game.construction.objects[1].position, [1,.5,2]);
});
test('a failed durable save restores both canonical scene files and project metadata', async () => {
  const { p, project } = fixture(), before = project.read('scenes/construction.json'), state = project.state, source = project.revision();
  p.save = () => { throw new Error('disk unavailable'); };
  const r = await api.editScene(p, edit(p.game.construction)); assert.equal(r.status, 400);
  assert.equal(p.game.construction.revision, 1); assert.equal(p.workflow.status, 'completed'); assert.equal(p.sceneEdit, undefined);
  assert.equal(project.read('scenes/construction.json'), before); assert.deepEqual(project.state, state); assert.equal(project.revision(), source);
});
test('build errors keep edits dirty and successful builds identify the new exact scene', async () => {
  const { p, project } = fixture(); await api.editScene(p, edit(p.game.construction));
  project.check = async () => ({ ok: false, sourceRevision: project.revision(), errors: [{ message: 'broken script' }] });
  assert.equal((await api.buildEditedScene(p)).status, 422); assert.equal(p.sceneEdit.dirty, true); assert.equal(p.mutating, false);
  project.check = async () => ({ ok: true, sourceRevision: project.revision(), errors: [] });
  project.build = async () => {
    const bytes = Buffer.from('new canonical scene fixture'), buildId = crypto.randomBytes(16).toString('hex');
    const b = { ok: true, buildId, sourceRevision: project.revision(), version: 1, bytes: bytes.length, contentHash: crypto.createHash('sha256').update(bytes).digest('hex') };
    fs.mkdirSync(path.join(project.buildDir,'builds'), { recursive:true });
    fs.writeFileSync(path.join(project.buildDir,'builds',buildId+'.pck'),bytes); fs.writeFileSync(path.join(project.buildDir,'builds',buildId+'.json'),JSON.stringify(b)); return b;
  };
  const r = await api.buildEditedScene(p); assert.equal(r.status, 200); assert.equal(r.body.sceneDirty, false);
  assert.equal(r.body.build.sourceRevision, project.revision()); assert.match(r.body.pck, /build=/);
  assert.equal(p.workflow.evidence.some(e => e.kind === 'test' || e.kind === 'preview'), false);
});
