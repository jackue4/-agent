import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { EventEmitter, getEventListeners } from 'node:events';
import { startWatchFrames } from '../watch-frames.mjs';
import { LiveGame } from '../live.mjs';
import { GodotProject } from '../gproject.mjs';

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const image = Buffer.from([0xff, 0xd8, 0, 1, 2, 0xff, 0xd9]);
function writeFrame(dir, seq, extra = {}) {
  const frame = `frame_${seq % 2}.jpg`;
  fs.writeFileSync(path.join(dir, frame), image);
  fs.writeFileSync(path.join(dir, 'watch.json'), JSON.stringify({ seq, frame, capturedAt: Date.now(), checks: [], state: { time: seq }, ...extra }));
}
function temporary(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ugc-watch-test-'));
  t.after(() => {
    assert.equal(path.dirname(path.resolve(dir)), path.resolve(os.tmpdir()));
    assert.match(path.basename(dir), /^ugc-watch-test-/);
    fs.rmSync(dir, { recursive: true, force: true });
  });
  return dir;
}

test('reader flush delivers actual JPEG bytes and bounded executed checks exactly once', async t => {
  const dir = temporary(t), frames = [];
  writeFrame(dir, 1, { checks: [{ ok: true, what: 'moved' }] });
  const reader = startWatchFrames(dir, { onFrame: f => frames.push(f), intervalMs: 1000 }); t.after(reader.stop);
  await reader.flush(); await reader.flush();
  assert.equal(frames.length, 1); assert.deepEqual(frames[0].image, image);
  assert.deepEqual(frames[0].checks, [{ ok: true, what: 'moved' }]);
  writeFrame(dir, 2, { checks: Array.from({ length: 201 }, () => ({ ok: false, what: 'x'.repeat(510) })) });
  await reader.flush(); assert.equal(frames.length, 2);
  assert.equal(frames[1].checks.length, 200); assert.equal(frames[1].checks[0].what.length, 500);
});

test('reader rejects malformed metadata, paths, oversize/non-JPEG images and stale sequences', async t => {
  const dir = temporary(t), frames = [];
  const reader = startWatchFrames(dir, { onFrame: f => frames.push(f), intervalMs: 1000 }); t.after(reader.stop);
  for (const bad of [{ frame: '../secret.jpg' }, { seq: -1 }, { seq: 1.5 }, { capturedAt: null }, { checks: null }, { state: [] }]) {
    writeFrame(dir, 1, bad); await reader.flush();
  }
  writeFrame(dir, 1); fs.writeFileSync(path.join(dir, 'frame_1.jpg'), 'not an image'); await reader.flush();
  fs.writeFileSync(path.join(dir, 'frame_1.jpg'), Buffer.alloc(5 * 1024 * 1024 + 1)); await reader.flush();
  assert.equal(frames.length, 0);
  writeFrame(dir, 3); await reader.flush(); writeFrame(dir, 2); await reader.flush();
  assert.deepEqual(frames.map(f => f.seq), [3]);
});

test('pre-abort, stop, abort and replacement suppress pending or subsequent frames', async t => {
  const dir = temporary(t), controller = new AbortController(); writeFrame(dir, 1);
  const frames = []; controller.abort();
  const pre = startWatchFrames(dir, { onFrame: f => frames.push(f), signal: controller.signal });
  await pre.flush(); assert.equal(frames.length, 0);
  const signal = new AbortController(); let current = true;
  const reader = startWatchFrames(dir, { onFrame: f => frames.push(f), signal: signal.signal, isCurrent: () => current, intervalMs: 1000 });
  current = false; await reader.flush(); assert.equal(frames.length, 0);
  current = true; await reader.flush(); assert.equal(frames.length, 1);
  writeFrame(dir, 2); signal.abort(); await reader.flush(); assert.equal(frames.length, 1);
  assert.equal(getEventListeners(signal.signal, 'abort').length, 0);
  const stopped = startWatchFrames(dir, { onFrame: f => frames.push(f) }); stopped.stop(); await stopped.flush();
  assert.equal(frames.length, 1);
});

test('a slow observer is serialized and a rejected callback does not break later frames', async t => {
  const dir = temporary(t), seen = []; let active = 0, maximum = 0;
  writeFrame(dir, 1);
  const reader = startWatchFrames(dir, { intervalMs: 10, onFrame: async f => {
    active++; maximum = Math.max(maximum, active); seen.push(f.seq); await sleep(30); active--;
    if (f.seq === 1) throw new Error('observer failed');
  } }); t.after(reader.stop);
  await reader.flush(); writeFrame(dir, 2); await reader.flush();
  assert.equal(maximum, 1); assert.deepEqual(seen, [1, 2]);
});

function liveFixture(t) {
  const children = [], dirs = [];
  const live = new LiveGame({ cleanupDelayMs: 0, spawnProcess: (_bin, args) => {
    const child = new EventEmitter(); child.stdout = new EventEmitter(); child.stderr = new EventEmitter();
    child.kill = () => { setImmediate(() => child.emit('close', null)); return true; };
    const dir = args.find(a => a.startsWith('--ugc-watch=')).slice('--ugc-watch='.length);
    dirs.push(dir); children.push(child); writeFrame(dir, 1);
    fs.writeFileSync(path.join(dir, 'ready.json'), JSON.stringify({ loaded: true }));
    return child;
  } });
  const project = { dir: os.tmpdir(), ready: async () => {}, liveArgs: dir => ['--', '--ugc-live=' + dir] };
  t.after(async () => { live.stop(); await sleep(15); for (const dir of dirs) assert.equal(fs.existsSync(dir), false); });
  return { live, project, children, dirs };
}

test('live startup flushes before ready, keeps streaming during eval, and stops on abort', async t => {
  const { live, project, dirs } = liveFixture(t), frames = [], controller = new AbortController();
  const ready = await live.startProject(project, 'landscape', { onFrame: f => frames.push(f) });
  assert.equal(ready.loaded, true); assert.equal(frames.length, 1);
  const waiting = assert.rejects(live.eval('await G.wait(2)', { signal: controller.signal }), { name: 'AbortError' });
  writeFrame(dirs[0], 2, { checks: [{ ok: true, what: 'mid-eval' }] });
  await live._watchReader.flush(); assert.equal(frames.at(-1).checks[0].what, 'mid-eval');
  controller.abort(); await waiting;
  const count = frames.length; await sleep(25); assert.equal(frames.length, count); assert.equal(live.running, false);
});

test('replaced session, delayed old close and crash cannot deliver or stop the new reader', async t => {
  const { live, project, children, dirs } = liveFixture(t), old = [], next = [];
  await live.startProject(project, 'landscape', { onFrame: f => old.push(f) });
  const previous = live._watchReader;
  await live.startProject(project, 'landscape', { onFrame: f => next.push(f) });
  children[0].emit('close', 1); await previous.flush();
  writeFrame(dirs[1], 2); await live._watchReader.flush();
  assert.equal(old.length, 1); assert.deepEqual(next.map(f => f.seq), [1, 2]);
  children[1].emit('close', 1); await live._watchReader.flush(); await sleep(20);
  assert.equal(live.running, false); assert.equal(fs.existsSync(dirs[1]), false);
});

function selfTestFixture(t, run) {
  const temporaryDir = temporary(t), template = path.join(temporaryDir, 'template');
  const put = (file, data) => { const out = path.join(template, file); fs.mkdirSync(path.dirname(out), { recursive: true }); fs.writeFileSync(out, data); };
  put('project.godot', 'config_version=5\n[application]\nrun/main_scene="res://main.tscn"\n');
  put('main.tscn', '[gd_scene format=3]\n[node name="Main" type="Node"]\n'); put('main.gd', 'extends Node\n');
  put('addons/ugc/ugc.gd', 'extends Node\n'); put('export_presets.cfg', '[preset.0]\nname="Web"\n');
  return new GodotProject('watch', { root: path.join(temporaryDir, 'projects'), template, runGodot: async (args, opts) => {
    if (args.includes('--import')) { fs.mkdirSync(path.join(opts.cwd, '.godot', 'imported'), { recursive: true }); return { code: 0, stdout: '', stderr: '' }; }
    return run(args, opts);
  } }).create();
}

test('selfTest uses a visible renderer for onFrame, flushes short-test assertions, removes watch directory', async t => {
  let watchDir; const frames = [];
  const project = selfTestFixture(t, async args => {
    assert.equal(args.includes('--headless'), false);
    watchDir = args.find(a => a.startsWith('--ugc-watch=')).slice('--ugc-watch='.length);
    writeFrame(watchDir, 1, { checks: [{ ok: true, what: 'final short test' }] });
    return { code: 0, stderr: '', stdout: '[ugc-test] ' + JSON.stringify({ loaded: true, errors: [], has_test: true, checks: [{ ok: true, what: 'final short test' }] }) };
  });
  const result = await project.selfTest({ shot: false, onFrame: f => frames.push(f) });
  assert.equal(result.ok, true); assert.equal(result.image, ''); assert.equal(frames.length, 1);
  assert.equal(frames[0].checks[0].what, 'final short test'); assert.equal(fs.existsSync(watchDir), false);
});

test('selfTest abort cleans its directory without delivering a late frame', async t => {
  let watchDir; const frames = [], controller = new AbortController();
  const project = selfTestFixture(t, async args => {
    watchDir = args.find(a => a.startsWith('--ugc-watch=')).slice('--ugc-watch='.length);
    controller.abort(); writeFrame(watchDir, 1);
    return { code: -1, aborted: true, stderr: '', stdout: '' };
  });
  await assert.rejects(project.selfTest({ shot: false, signal: controller.signal, onFrame: f => frames.push(f) }), { name: 'AbortError' });
  assert.equal(frames.length, 0); assert.equal(fs.existsSync(watchDir), false);
});
