import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createWorkflow, recordEvidence } from '../workflow.mjs';
import { createIteration } from '../iteration.mjs';

const data = fs.mkdtempSync(path.join(os.tmpdir(), 'ugc-art-flow-'));
process.env.UGC_DATA_DIR = data;
process.env.UGC_ART = '0';
fs.mkdirSync(path.join(data, 'projects'));
const api = await import('../server.mjs');
after(() => fs.rmSync(data, { recursive: true, force: true }));

const BUILD = 'b'.repeat(32);
function fakeProject() {
  const f = { rev: '1'.repeat(64), code: { 'main.gd': 'extends Node2D' }, writes: [], tests: 0, exists: true };
  Object.assign(f, {
    revision: () => f.rev,
    sources: filter => Object.fromEntries(Object.entries(f.code).filter(([k]) => filter(k))),
    withLock: fn => fn(),
    writeAsset: rel => { f.writes.push(rel); f.rev = String(f.writes.length + 1).repeat(64); },
    build: async () => (f.latestBuild = { ok: true, buildId: BUILD, sourceRevision: f.rev, version: 2, contentHash: 'c'.repeat(64) }),
    check: async () => ({ ok: true, loaded: true, errors: [], sourceRevision: f.rev }),
    selfTest: async () => { f.tests++; return { ok: true, loaded: true, has_test: true, checks: [{ ok: true, what: 'core loop' }], errors: [], sourceRevision: f.rev }; },
    latestBuild: null,
  });
  return f;
}
function acceptedRound(fake) {
  const p = new api.Project({}); p.game.meta.engine = 'godot';
  api.projects.set(p.id, p);
  p.workflow = createWorkflow({ goal: 'demo', sourceRevision: fake.rev });
  p.workflow.iteration = createIteration({ kind: 'iteration' });
  for (const kind of ['compile', 'test', 'build', 'play']) recordEvidence(p.workflow, { kind, ok: true, sourceRevision: fake.rev, buildId: BUILD, checks: [{ ok: true, what: 'x' }] });
  p.workflow.status = 'completed';
  api.markArtBase(p, fake);
  const src = path.join(data, 'hero.png'); fs.writeFileSync(src, 'png');
  p.artPending = new Map([['hero', { rel: 'assets/hero.png', src, name: '主角' }]]);
  return p;
}

test('art landing after a round is batched, rebuilt and re-verified, carrying the real play evidence', async () => {
  const fake = fakeProject(), p = acceptedRound(fake);
  const events = []; const emit = p.emit.bind(p); p.emit = ev => { events.push(ev); emit(ev); };
  const r = await api.flushArt(p, { project: fake });
  assert.deepEqual(r.ids, ['hero']); assert.deepEqual(fake.writes, ['assets/hero.png']); assert.equal(fake.tests, 1);
  const play = p.workflow.evidence.findLast(e => e.kind === 'play');
  assert.equal(play.sourceRevision, fake.rev); assert.match(play.summary, /代码未变/);
  assert.equal(p.workflow.status, 'ready', 'native acceptance restored; the new pack still needs its browser receipt');
  const art = events.find(e => e.type === 'art');
  assert.equal(art.state, 'verified'); assert.equal(art.ok, true);
});

test('a code change since the round never inherits its play evidence', async () => {
  const fake = fakeProject(), p = acceptedRound(fake);
  fake.code['main.gd'] = 'extends Node2D\n# changed';
  await api.flushArt(p, { project: fake });
  assert.equal(p.workflow.evidence.findLast(e => e.kind === 'play').sourceRevision === fake.rev, false);
  assert.equal(p.workflow.status, 'partial');
});

test('art waits while a running round is wrapping up', async () => {
  const fake = fakeProject(), p = acceptedRound(fake);
  p.running = true; p.workflow.iteration.wrapAt = Date.now() - 1;
  assert.equal(await api.flushArt(p, { project: fake }), null);
  assert.equal(fake.writes.length, 0); assert.equal(p.artPending.size, 1);
});
