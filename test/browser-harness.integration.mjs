// Native execution of the Web command harness, not a claim of browser acceptance.
// The final Web/PCK path is separately exercised by the platform/browser owner.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { GodotProject, runGodot, tagged } from '../server/gproject.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = `extends Node
const Harness = preload("res://addons/ugc/web_test_harness.gd")
var checks: Array:
\tget: return UGC.checks
var result := ""
var score := 0
var phase := 0
var test_mode := 0
var received: Array = []
var assertions: Array = []
var harness: Node
func game() -> Node: return self
func _state() -> Dictionary: return {"phase": phase}
func take_errors() -> Array: return UGC.take_errors()
func eval_code(code: String, timeout_ms: int) -> Dictionary: return await UGC.eval_code(code, timeout_ms)
func emit(message: Dictionary) -> void: received.append(message)
func verify(ok: bool, what: String) -> void: assertions.append({"ok": ok, "what": what})
func command(kind: String, command_id: String, payload := {}) -> Dictionary:
\treturn {"clientId": "fixture-client", "runId": "fixture-run", "runtimeSession": "fixture-runtime", "buildId": "fixture-build", "sourceRevision": "fixture-revision", "commandId": command_id, "kind": kind, "payload": payload.merged({"shot": false})}
func execute(request: Dictionary) -> Dictionary:
\tharness.submit(request)
\tvar started := Time.get_ticks_msec()
\twhile Time.get_ticks_msec() - started < 6000:
\t\tfor message in received:
\t\t\tif message.type == "runtime_test_result" and message.commandId == request.commandId:
\t\t\t\treturn message
\t\tawait get_tree().process_frame
\treturn {}
func auto_test() -> void:
\tif test_mode == 1:
\t\tUGC.check(false, "intentional failure")
\t\treturn
\tif test_mode == 2:
\t\tvar invalid: Array = []
\t\tprint(invalid[3])
\t\treturn
\tUGC.check(phase == 1, "phase persisted from eval")
\tawait UGC.wait(0.4)
\tUGC.check(true, "final test check")
func _ready() -> void: suite.call_deferred()
func suite() -> void:
\tharness = Harness.new()
\tadd_child(harness)
\tharness.configure(self, {"buildId": "fixture-build", "sourceRevision": "fixture-revision"}, "fixture-runtime")
\tvar run := await execute(command("run", "run-1"))
\tverify(not run.is_empty() and run.data.ok and run.data.loaded, "run reports actual loaded scene")
\tverify(run.get("runId") == "fixture-run", "run identity is preserved")
\tvar wrong := command("eval", "wrong", {"code": "game.phase = 99"})
\twrong.buildId = "old-build"
\tharness.submit(wrong)
\tawait UGC.wait(0.05)
\tverify(phase == 0, "wrong build cannot mutate game")
\tvar evaluated := await execute(command("eval", "eval-1", {"code": "await UGC.wait(0.4)\\ngame.phase += 1\\nUGC.check(game.phase == 1, \\\"eval moved\\\")\\nreturn game.phase".replace("\\n", "\\n"), "settle": 0.0}))
\tverify(not evaluated.is_empty() and evaluated.data.ok and evaluated.data.value == 1, "eval executes actual awaited game mutation")
\tverify(evaluated.data.checks.size() == 1, "eval reports only executed checks")
\tharness.submit(command("eval", "eval-1", {"code": "game.phase = 99"}))
\tawait UGC.wait(0.05)
\tverify(phase == 1, "duplicate command cannot execute twice")
\tvar tested := await execute(command("test", "test-1"))
\tverify(not tested.is_empty() and tested.data.has_test and tested.data.ok, "test calls actual auto_test")
\tverify(tested.data.checks.size() == 2, "test clears earlier step checks")
\tvar intermediate := false
\tfor message in received:
\t\tif message.type == "runtime_test_progress" and message.commandId == "test-1" and message.data.checks.size() == 1:
\t\t\tintermediate = true
\tverify(intermediate, "mid-test progress precedes completion")
\tverify(tested.data.metrics.has("frames") and tested.data.metrics.has("maxFrameMs") and tested.data.metrics.has("jankFrames"), "performance report exposes measured sample counters")
\ttest_mode = 1
\tvar failed := await execute(command("test", "failed-test"))
\tverify(not failed.is_empty() and not failed.data.ok, "a real failed assertion cannot pass")
\ttest_mode = 2
\tvar errored := await execute(command("test", "error-test"))
\tverify(errored.is_empty() or not errored.data.ok, "a real auto_test exception cannot pass")
\tvar max_fps_before := Engine.max_fps
\tvar rendering_before := RenderingServer.is_render_loop_enabled()
\tUGC._presentation(false)
\tUGC._presentation(false)
\tverify(get_tree().paused and Engine.max_fps == max_fps_before and not RenderingServer.is_render_loop_enabled(), "hidden authoring view pauses work and rendering without a browser-blocking frame cap")
\tUGC._presentation(true)
\tverify(not get_tree().paused and Engine.max_fps == max_fps_before and RenderingServer.is_render_loop_enabled() == rendering_before, "presentation restores exact original settings")
\tget_tree().paused = true
\tUGC._presentation(false)
\tUGC._presentation(true)
\tverify(get_tree().paused, "presentation preserves a previously paused game")
\tget_tree().paused = false
\tUGC._web_test = harness
\tUGC._presentation(false)
\tverify(not get_tree().paused and Engine.max_fps == max_fps_before, "active Web test cannot be paused by authoring hints")
\tUGC._web_test = null
\tharness.submit(command("stop", "stop-1"))
\tverify(get_tree().paused, "stop freezes completed runtime without replacing scene")
\tprint("[browser-harness] ", JSON.stringify({"checks": assertions, "events": received.size()}))
\tget_tree().quit(0 if assertions.all(func(row): return row.ok) else 1)
`;

test('new Web harness executes bound commands once and reports intermediate checks in an isolated Godot runtime', { timeout: 90000 }, async () => {
  const folder = path.join(root, 'artifacts', 'browser-runtime'); fs.mkdirSync(folder, { recursive: true });
  const isolated = fs.mkdtempSync(path.join(folder, 'harness-')), template = path.join(isolated, 'template');
  fs.cpSync(path.join(root, 'gp_template'), template, { recursive: true, filter: p => !/(?:^|[\\/])(?:\.godot|build|generated)(?:[\\/]|$)|\.(?:import|uid)$/.test(p) });
  const project = new GodotProject('fixture', { root: path.join(isolated, 'projects'), template }).create();
  project.write('main.gd', source);
  project.write('main.tscn', '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://main.gd" id="1"]\n[node name="Main" type="Node"]\nscript = ExtResource("1")\n');
  await project.ready();
  const result = await runGodot(['--headless', '--path', project.dir, '--audio-driver', 'Dummy'], { cwd: project.dir, timeoutMs: 15000 });
  fs.writeFileSync(path.join(isolated, 'native.log'), result.stdout + '\n' + result.stderr);
  const report = tagged(result.stdout, 'browser-harness');
  fs.writeFileSync(path.join(isolated, 'report.json'), JSON.stringify({ isolated, code: result.code, timedOut: result.timedOut, report }, null, 2));
  fs.writeFileSync(path.join(folder, 'harness-latest.json'), JSON.stringify({ isolated }, null, 2));
  assert.equal(result.code, 0, result.stdout + result.stderr); assert.equal(result.timedOut, false);
  assert.ok(report?.checks.length >= 10, result.stdout + result.stderr);
  assert.equal(report.checks.every(row => row.ok), true, JSON.stringify(report));
});
