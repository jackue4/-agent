import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { EventEmitter, getEventListeners } from 'node:events';
import { spawn } from 'node:child_process';
import { runGodot } from '../gproject.mjs';
import { LiveGame } from '../live.mjs';

const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
const tick = () => new Promise(resolve => setImmediate(resolve));

test('runGodot pre-abort never spawns and reports cancellation rather than timeout', async () => {
  const controller = new AbortController(); controller.abort();
  const result = await runGodot([], { signal: controller.signal, spawnProcess: () => assert.fail('must not spawn') });
  assert.equal(result.aborted, true); assert.equal(result.timedOut, false); assert.equal(result.code, -1);
});

test('runGodot cancels an actual owned helper process and detaches its signal listener', async () => {
  const controller = new AbortController(); let child;
  const resultPromise = runGodot([], { signal: controller.signal, timeoutMs: 10000, spawnProcess: () => {
    child = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { windowsHide: true }); return child;
  } });
  controller.abort(new Error('deadline'));
  const result = await resultPromise;
  assert.equal(result.aborted, true); assert.equal(result.timedOut, false);
  assert.ok(child.exitCode !== null || child.signalCode !== null);
  assert.equal(getEventListeners(controller.signal, 'abort').length, 0);
});

test('runGodot timeout remains distinguishable from cancellation', async () => {
  const result = await runGodot([], { timeoutMs: 10, spawnProcess: () =>
    spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { windowsHide: true }) });
  assert.equal(result.timedOut, true); assert.equal(result.aborted, false);
});

function fixture(t, { ready = true } = {}) {
  const children = [], dirs = [];
  const live = new LiveGame({ cleanupDelayMs: 0, spawnProcess: (_bin, args) => {
    const child = new EventEmitter(); child.stdout = new EventEmitter(); child.stderr = new EventEmitter(); child.kills = 0;
    child.kill = () => { child.kills++; setImmediate(() => child.emit('close', null)); return true; };
    const dir = args.find(a => a.startsWith('--live=')).slice(7); dirs.push(dir); children.push(child);
    if (ready) fs.writeFileSync(path.join(dir, 'ready.json'), JSON.stringify({ loaded: true, state: {} }));
    return child;
  } });
  const project = { dir: os.tmpdir(), ready: async () => {}, liveArgs: dir => ['--live=' + dir] };
  t.after(async () => {
    live.stop(); await new Promise(resolve => setTimeout(resolve, 5));
    for (const dir of dirs) {
      const target = path.resolve(dir);
      assert.equal(path.dirname(target), path.resolve(os.tmpdir())); assert.match(path.basename(target), /^ugc-live-/);
      fs.rmSync(target, { recursive: true, force: true });
    }
  });
  return { live, project, children, dirs };
}

test('pre-aborted live startup performs no preparation, spawn or command write', async t => {
  const { live, project, children } = fixture(t);
  const controller = new AbortController(); controller.abort();
  project.ready = () => assert.fail('must not prepare');
  await assert.rejects(live.startProject(project, 'landscape', { signal: controller.signal }), { name: 'AbortError' });
  await assert.rejects(live.start({}, {}, { signal: controller.signal }), { name: 'AbortError' });
  await assert.rejects(live.eval('return 1', { signal: controller.signal }), { name: 'AbortError' });
  assert.equal(children.length, 0); assert.equal(live.dir, null);
});

test('cancellation while project preparation is pending prevents a late live launch', async t => {
  const { live, project, children } = fixture(t); const prepared = deferred();
  project.ready = () => prepared.promise;
  const controller = new AbortController();
  const pending = assert.rejects(live.startProject(project, 'landscape', { signal: controller.signal }), { name: 'AbortError' });
  controller.abort(); prepared.resolve(); await pending;
  assert.equal(children.length, 0); assert.equal(live.running, false);
});

test('explicit stop while preparation is pending also prevents a late launch', async t => {
  const { live, project, children } = fixture(t); const prepared = deferred();
  project.ready = () => prepared.promise;
  const pending = assert.rejects(live.startProject(project, 'landscape'), /停止或被替换/);
  live.stop(); prepared.resolve(); await pending;
  assert.equal(children.length, 0);
});

test('abort during startup kills its child and ends the readiness wait', async t => {
  const { live, project, children } = fixture(t, { ready: false });
  const controller = new AbortController();
  const pending = assert.rejects(live.startProject(project, 'landscape', { signal: controller.signal }), { name: 'AbortError' });
  await tick(); controller.abort(); await pending;
  assert.equal(children[0].kills, 1); assert.equal(live.running, false);
  assert.equal(getEventListeners(controller.signal, 'abort').length, 0);
});

test('abort during eval stops the temporary process instead of accepting a late result', async t => {
  const { live, project, children } = fixture(t);
  await live.startProject(project, 'landscape');
  const controller = new AbortController();
  const pending = assert.rejects(live.eval('await game.long_work()', { signal: controller.signal }), { name: 'AbortError' });
  assert.ok(fs.existsSync(path.join(live.dir, 'cmd_1.json')));
  fs.writeFileSync(path.join(live.dir, 'res_1.json'), JSON.stringify({ ok: true, value: 'late success' }));
  controller.abort(); await pending;
  assert.equal(children[0].kills, 1); assert.equal(live.running, false);
  assert.equal(getEventListeners(controller.signal, 'abort').length, 0);
});

test('old launch signal and delayed child-close cannot stop a newer live session', async t => {
  const { live, project, children } = fixture(t); const old = new AbortController();
  await live.startProject(project, 'landscape', { signal: old.signal });
  await live.startProject(project, 'landscape');
  old.abort(); await tick();
  assert.equal(live.running, true); assert.equal(children[1].kills, 0);
  assert.equal(getEventListeners(old.signal, 'abort').length, 0);
});

test('aborted eval cannot stop a newer session and cannot create another command', async t => {
  const { live, project, children } = fixture(t);
  await live.startProject(project, 'landscape'); const controller = new AbortController();
  const pending = live.eval('return 1', { signal: controller.signal });
  await live.startProject(project, 'landscape'); controller.abort();
  await assert.rejects(pending, { name: 'AbortError' });
  assert.equal(live.running, true); assert.equal(children[1].kills, 0);
  assert.equal(fs.existsSync(path.join(live.dir, 'cmd_1.json')), false);
});
