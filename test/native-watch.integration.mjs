// Explicit real-window acceptance; intentionally excluded from the fast *.test.mjs suite.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { GodotProject, runGodot } from '../server/gproject.mjs';
import { LiveGame } from '../server/live.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const main = `extends Node2D
var phase := 0
var elapsed := 0.0
func _process(delta: float) -> void:
\telapsed += delta
\tqueue_redraw()
func _draw() -> void:
\tdraw_rect(Rect2(0, 0, 1280, 720), Color(0.08, 0.12, 0.19))
\tdraw_circle(Vector2(180 + fmod(elapsed * 220, 850), 380), 64, [Color.CORAL, Color.SKY_BLUE, Color.LIME_GREEN][phase % 3])
\tdraw_string(ThemeDB.fallback_font, Vector2(80, 120), "Native viewport: phase %d" % phase, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color.WHITE)
func auto_test() -> void:
\tphase = 1
\tUGC.check(true, "self-test began")
\tawait UGC.wait(0.8)
\tphase = 2
\tUGC.check(true, "self-test middle")
\tawait UGC.wait(0.8)
\tUGC.check(phase == 2, "self-test final")
`;

function jpegSize(bytes) {
  let offset = 2;
  while (offset < bytes.length - 9) {
    if (bytes[offset] !== 0xff) { offset++; continue; }
    const marker = bytes[offset + 1];
    if ([0xc0, 0xc1, 0xc2].includes(marker)) return { width: bytes.readUInt16BE(offset + 7), height: bytes.readUInt16BE(offset + 5) };
    if ([0xd8, 0xd9, 0x01].includes(marker)) { offset += 2; continue; }
    offset += 2 + bytes.readUInt16BE(offset + 2);
  }
  throw new Error('not a decodable JPEG header');
}

test('native viewport capture streams during live eval and self-test, then stops cleanly', { timeout: 150000 }, async t => {
  const artifactRoot = path.join(root, 'artifacts', 'native-watch'); fs.mkdirSync(artifactRoot, { recursive: true });
  const isolated = fs.mkdtempSync(path.join(artifactRoot, 'acceptance-'));
  const template = path.join(isolated, 'template');
  fs.cpSync(path.join(root, 'gp_template'), template, { recursive: true,
    filter: p => !/(?:^|[\\/])(?:\.godot|build|generated)(?:[\\/]|$)|\.(?:import|uid)$/.test(p) });
  const report = { isolated, startedAt: new Date().toISOString(), calls: [], streams: {} };
  const runner = async (args, opts) => {
    const result = await runGodot(args, opts), index = report.calls.length + 1;
    fs.writeFileSync(path.join(isolated, `process-${index}.log`), result.stdout + '\n' + result.stderr);
    report.calls.push({ args, code: result.code, timedOut: !!result.timedOut, aborted: !!result.aborted });
    return result;
  };
  const project = new GodotProject('watch-fixture', { root: path.join(isolated, 'projects'), template, runGodot: runner }).create({ title: 'Isolated native watch acceptance' });
  project.write('main.tscn', '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://main.gd" id="1"]\n[node name="Main" type="Node2D"]\nscript = ExtResource("1")\n');
  project.write('main.gd', main);
  const streams = {};
  const observer = name => f => {
    const list = streams[name] ||= [];
    const row = { seq: f.seq, capturedAt: f.capturedAt, receivedAt: Date.now(), checks: f.checks, state: f.state,
      bytes: f.image.length, ...jpegSize(f.image), hash: crypto.createHash('sha256').update(f.image).digest('hex') };
    list.push(row);
    fs.writeFileSync(path.join(isolated, `${name}-${String(list.length).padStart(2, '0')}.jpg`), f.image);
  };
  const live = new LiveGame({ cleanupDelayMs: 100 });
  try {
    await t.test('fresh import compiles the modified addon with no parse/runtime errors', async () => {
      const checked = await project.check(); report.check = checked;
      assert.equal(checked.ok, true, JSON.stringify(checked));
    });
    await t.test('selfTest streams multiple changing frames and assertions before completion', async () => {
      const result = await project.selfTest({ shot: false, onFrame: observer('self-test') }); report.selfTest = result;
      assert.equal(result.ok, true, JSON.stringify(result));
      const frames = streams['self-test']; assert.ok(frames.length >= 5, `only ${frames.length} frames`);
      assert.ok(frames.some(f => f.checks.length === 1)); assert.ok(frames.some(f => f.checks.length === 2));
      assert.equal(frames.at(-1).checks.length, 3); assert.ok(new Set(frames.map(f => f.hash)).size >= 4);
      assert.ok(frames.every(f => f.width <= 960 && f.height <= 960 && f.bytes < 1024 * 1024));
      assert.equal(fs.existsSync(report.calls.at(-1).args.find(a => a.startsWith('--ugc-watch=')).slice('--ugc-watch='.length)), false);
    });
    await t.test('long live eval delivers changing frames and middle assertions before resolving', async () => {
      const ready = await live.startProject(project, 'landscape', { onFrame: observer('live') });
      assert.equal(ready.loaded, true, JSON.stringify(ready)); assert.deepEqual(ready.errors, []);
      assert.ok(streams.live.length >= 1, 'ready must flush startup viewport');
      const start = Date.now();
      const result = await live.eval('UGC.check(true, "eval began")\ngame.phase = 1\nawait UGC.wait(0.8)\nUGC.check(true, "eval middle")\ngame.phase = 2\nawait UGC.wait(0.8)\nUGC.check(true, "eval final")\nreturn game.phase', { shot: false, timeoutMs: 5000 });
      report.eval = { ...result, startedAt: start, finishedAt: Date.now() };
      assert.equal(result.ok, true, JSON.stringify(result)); assert.equal(result.value, 2);
      const during = streams.live.filter(f => f.receivedAt >= start);
      assert.ok(during.length >= 5); assert.ok(during.some(f => f.checks.length === 1)); assert.ok(during.some(f => f.checks.length === 2));
      assert.equal(during.at(-1).checks.at(-1).what, 'eval final');
      assert.ok(new Set(during.map(f => f.hash)).size >= 4);
      fs.writeFileSync(path.join(isolated, 'live.log'), live.log);
    });
    await t.test('real eval cancellation kills the process, deletes its files and emits no late frames', async () => {
      const dir = live.dir, controller = new AbortController();
      const pending = assert.rejects(live.eval('UGC.check(true, "cancel started")\nawait UGC.wait(20)', { shot: false, signal: controller.signal }), { name: 'AbortError' });
      await sleep(450); controller.abort(); await pending;
      const count = streams.live.length; await sleep(400);
      assert.equal(streams.live.length, count); assert.equal(live.running, false); assert.equal(fs.existsSync(dir), false);
      report.cancellation = { noLateFrames: true, removed: true, frames: count };
    });
    await t.test('instant auto_test forces its final assertion into a frame before process exit', async () => {
      project.write('main.gd', main.replace(/func auto_test\(\) -> void:[\s\S]*/, 'func auto_test() -> void:\n\tphase = 2\n\tUGC.check(true, "instant final")\n'));
      const result = await project.selfTest({ shot: false, onFrame: observer('instant') }); report.instant = result;
      assert.equal(result.ok, true, JSON.stringify(result));
      assert.equal(streams.instant.at(-1).checks.at(-1).what, 'instant final');
    });
  } finally {
    live.stop(); report.streams = streams; report.finishedAt = new Date().toISOString();
    fs.writeFileSync(path.join(isolated, 'report.json'), JSON.stringify(report, null, 2));
    fs.writeFileSync(path.join(artifactRoot, 'latest.json'), JSON.stringify({ isolated, report: path.join(isolated, 'report.json') }, null, 2));
  }
});
