extends SceneTree
## Headless runtime test suite. Run from ugc-platform/runtime:
##   godot --headless --path . --script res://tests/run_tests.gd
## Exits with code 1 on any failure so CI / npm scripts can gate on it.
const U = preload("res://util.gd")
const Synth = preload("res://sfx_synth.gd")
const PlatformDraw = preload("res://platform2d.gd")
const GameUI = preload("res://game_ui.gd")
const MainScene = preload("res://main.tscn")

var failures: Array[String] = []
var passed := 0
var error_log := ErrorCollector.new()

## Captures engine/script errors so a run that logs SCRIPT ERROR fails even when every
## assertion passed (GDScript runtime errors don't throw).
class ErrorCollector extends Logger:
	var errors: Array[String] = []
	var _mutex := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		errors.append("%s:%d %s %s" % [file, line, function, rationale if rationale != "" else code])
		_mutex.unlock()
	func _log_message(_message: String, _error: bool) -> void:
		pass

func _initialize() -> void:
	OS.add_logger(error_log)
	_run.call_deferred()

func check(cond: bool, what: String) -> void:
	if cond:
		passed += 1
	else:
		failures.append(what)
		printerr("  FAIL: ", what)

func _run() -> void:
	test_util()
	test_synth()
	test_platform_style()
	test_time_format()
	await test_game_2d()
	await test_feel_2d()
	await test_touch()
	await test_game_3d()
	var uniq := {}
	for e in error_log.errors:
		uniq[e] = true
	for e in uniq:
		failures.append("runtime error: " + e)
		printerr("  ERROR: ", e)
	print("\n%d passed, %d failed" % [passed, failures.size()])
	OS.remove_logger(error_log)
	quit(1 if failures.size() > 0 else 0)

# ------------------------------------------------------------------ pure units

func test_util() -> void:
	print("util")
	check(U.v2([3, 4], Vector2.ZERO) == Vector2(3, 4), "v2 from array")
	check(U.v2({"x": 1}, Vector2(0, 9)) == Vector2(1, 9), "v2 from partial dict")
	check(U.v2("junk", Vector2(7, 7)) == Vector2(7, 7), "v2 default on junk")
	check(U.v3([1, 2], Vector3(0, 5, 0)) == Vector3(1, 5, 2), "v3 from xz pair keeps default y")
	check(U.num({"a": "2.5"}, "a", 0.0) == 2.5, "num parses numeric string")
	check(U.num({"a": "x"}, "a", 1.0) == 1.0, "num default on bad string")
	check(U.num(null, "a", 3.0) == 3.0, "num tolerates null dict")
	check(U.str_of({"a": null}, "a", "d") == "d", "str_of null -> default")
	check(U.col("#ff0000", Color.BLACK) == Color(1, 0, 0), "col hex")
	check(U.col("", Color.BLUE) == Color.BLUE, "col empty -> default")
	check(U.clean_text("🦊 到家啦！") == "到家啦！", "clean_text strips astral emoji")
	check(U.clean_text("☀️晴天") == "晴天", "clean_text strips BMP symbol + VS16")
	check(U.default_size_2d("checkpoint") != Vector2.ZERO, "checkpoint has a 2D size")

func test_synth() -> void:
	print("sfx synth")
	for n in ["step", "land", "stomp", "checkpoint", "tick", "star"]:
		var s: AudioStreamWAV = Synth.make(n)
		check(s != null and s.data.size() > 1000, "synth %s produces audio" % n)
		if s:
			var peak := 0
			for i in range(0, s.data.size(), 2):
				peak = maxi(peak, absi(s.data.decode_s16(i)))
			check(peak > 2000 and peak <= 32767, "synth %s has sane peak (%d)" % [n, peak])
	check(Synth.make("nope") == null, "unknown synth -> null")

func test_platform_style() -> void:
	print("platform style")
	check(PlatformDraw.infer_style(Color("#7cc44f")) == "grass", "green -> grass")
	check(PlatformDraw.infer_style(Color("#ffffff")) == "snow", "white -> snow")
	check(PlatformDraw.infer_style(Color("#808080")) == "stone", "grey -> stone")
	check(PlatformDraw.infer_style(Color("#8b5a2b")) == "wood", "brown -> wood")
	check(PlatformDraw.infer_style(Color("#ff8fab")) == "candy", "pink -> candy")
	check(PlatformDraw.infer_style(Color("#4cc9f0")) == "ice", "cyan -> ice")

func test_time_format() -> void:
	check(GameUI.fmt_time(0.0) == "0:00", "fmt 0")
	check(GameUI.fmt_time(75.9) == "1:15", "fmt 75.9")

# ------------------------------------------------------------------ integration

func _boot(spec: Dictionary, mode: String) -> Node:
	var m: Node = MainScene.instantiate()
	root.add_child(m)
	await process_frame
	m.handle({"type": "load", "spec": spec, "assets": {}, "mode": mode, "start_card": false})
	for i in 5:
		await physics_frame
	return m

func _free(m: Node) -> void:
	paused = false
	Engine.time_scale = 1.0
	m.queue_free()
	await process_frame

func _spec2d() -> Dictionary:
	return {
		"meta": {"title": "T", "dimension": "2d", "genre": "platformer"},
		"world": {"background_color": "#88ccff", "ambient": "leaves"},
		"player": {"position": [0, 60]},
		"rules": {"win": "collect_all", "lives": 2, "par_time": 30},
		"entities": {
			"ground": {"kind": "platform", "position": [600, 0], "size": [1600, 40]},
			"c1": {"kind": "collectible", "position": [200, 60]},
			"c2": {"kind": "collectible", "position": [400, 60]},
			"cp": {"kind": "checkpoint", "position": [800, 75]},
			"e1": {"kind": "enemy", "position": [1000, 50]},
			"sign": {"kind": "sign", "position": [100, 90], "text": "🍄 一段很长很长的告示牌文字，需要自动换行缩小"},
			"goal": {"kind": "goal", "position": [1300, 80]},
		},
	}

func test_game_2d() -> void:
	print("2d game flow")
	var m := await _boot(_spec2d(), "play")
	check(m.world != null and m.dim == "2d", "2d world created")
	check(m.state == m.State.PLAYING, "starts playing without start card")
	check(m.total_collect == 2 and m.total_enemies == 1, "counts collectibles / enemies")
	check(m.world.ents.size() == 7, "all entities spawned")
	check(m.world.progress() >= 0.0 and m.world.progress() <= 0.05, "progress near 0 at spawn")
	# checkpoint becomes the respawn point
	var cp = m.world.ents["cp"]
	m.world.reach_checkpoint(cp)
	check(m.world.player.spawn.x > 700.0, "checkpoint moves respawn point")
	# collect both -> win with stars
	m.on_collect()
	check(not m.game_over, "not over after first collect")
	m.elapsed = 12.0
	m.on_collect()
	check(m.game_over and m.state == m.State.OVER, "collect_all wins")
	check(m.stars() == 3, "3 stars: all collected, under par, no damage (got %d)" % m.stars())
	await _free(m)
	# lose flow
	m = await _boot(_spec2d(), "play")
	check(m.lose_life() == true, "first hit keeps playing")
	check(m.lose_life() == false and m.game_over, "last life ends the game")
	await _free(m)
	# pause / resume & restart
	m = await _boot(_spec2d(), "play")
	m._pause()
	check(paused and m.state == m.State.PAUSED, "pause freezes tree")
	m._resume()
	check(not paused and m.state == m.State.PLAYING, "resume")
	m.hit_stop(0.05)
	check(Engine.time_scale < 1.0, "hit stop slows time")
	for i in 30:
		await process_frame
	check(Engine.time_scale == 1.0, "hit stop recovers")
	await _free(m)
	# edit mode + build ops
	m = await _boot(_spec2d(), "edit")
	check(m.state == m.State.EDIT and not m.ui.hud_root.visible, "edit mode hides HUD")
	m.handle({"type": "ops", "ops": [{"op": "add", "id": "p2", "entity": {"kind": "platform", "position": [300, 200], "size": [200, 30]}}, {"op": "remove", "id": "c1"}]})
	for i in 240:
		await process_frame
		if not m.busy_building:
			break
	check(not m.busy_building, "build queue drains")
	check(m.world.ents.has("p2") and not m.spec["entities"].has("c1"), "ops applied to world and spec")
	await _free(m)
	# garbage spec never crashes
	m = await _boot({"meta": "x", "entities": [1, 2], "player": 5}, "play")
	check(m.world != null, "garbage spec still produces a world")
	await _free(m)

## Drives the real player controller with input actions and checks the movement contract
## the server's reachability model relies on (jump height, variable jump, stomp).
func test_feel_2d() -> void:
	print("2d feel")
	var s := {
		"meta": {"dimension": "2d"}, "rules": {"win": "defeat_all", "lives": 3},
		"player": {"position": [0, 40]},
		"entities": {
			"ground": {"kind": "platform", "position": [0, 0], "size": [3000, 40]},
			"e": {"kind": "enemy", "position": [600, 45], "behavior": "idle"},
		},
	}
	var m := await _boot(s, "play")
	var p = m.world.player
	for i in 30:
		await physics_frame
	check(p.is_on_floor(), "player settles on ground")
	var y0: float = p.global_position.y
	# full jump: hold
	Input.action_press("jump")
	var min_y := y0
	for i in 90:
		await physics_frame
		min_y = minf(min_y, p.global_position.y)
	Input.action_release("jump")
	var full_h := y0 - min_y
	var expect: float = p.jump * p.jump / (2.0 * p.gravity)
	check(absf(full_h - expect) < expect * 0.12, "full jump height %.0f ~ v^2/2g %.0f" % [full_h, expect])
	for i in 60:
		await physics_frame
	check(p.is_on_floor(), "lands again")
	# short hop: tap
	Input.action_press("jump")
	await physics_frame
	await physics_frame
	Input.action_release("jump")
	min_y = y0
	for i in 60:
		await physics_frame
		min_y = minf(min_y, p.global_position.y)
	check(y0 - min_y < full_h * 0.5, "tap jump is a short hop (%.0f vs %.0f)" % [y0 - min_y, full_h])
	# run right
	var x0: float = p.global_position.x
	Input.action_press("move_right")
	for i in 30:
		await physics_frame
	Input.action_release("move_right")
	check(p.global_position.x - x0 > 100.0, "runs right")
	# stomp: drop the player onto the enemy
	var en = m.world.ents["e"]
	p.global_position = en.global_position + Vector2(0, -160)
	p.velocity = Vector2(0, 300)
	for i in 60:
		await physics_frame
		if m.game_over:
			break
	check(m.defeated == 1 and m.game_over, "stomping the enemy defeats it and wins defeat_all")
	check(m.lives == 3, "stomp does not hurt the player")
	await _free(m)

func test_touch() -> void:
	print("touch controls")
	var tc: Control = preload("res://touch_controls.gd").new()
	root.add_child(tc)
	tc.size = Vector2(1280, 720)
	tc.configure("platformer", false)
	var ev := InputEventScreenTouch.new()
	ev.index = 0; ev.pressed = true; ev.position = Vector2(200, 600)
	tc._input(ev)
	var dr := InputEventScreenDrag.new()
	dr.index = 0; dr.position = Vector2(300, 560)
	tc._input(dr)
	check(Input.is_action_pressed("move_right") and not Input.is_action_pressed("move_up"), "stick drag right presses move_right only (platformer)")
	var b := InputEventScreenTouch.new()
	b.index = 1; b.pressed = true; b.position = tc.buttons[0]["center"]
	tc._input(b)
	check(Input.is_action_pressed("jump"), "jump button presses jump")
	ev.pressed = false
	tc._input(ev)
	b.pressed = false
	tc._input(b)
	check(not Input.is_action_pressed("move_right") and not Input.is_action_pressed("jump"), "release clears actions")
	tc.queue_free()
	Input.emulate_mouse_from_touch = true

func test_game_3d() -> void:
	print("3d game flow")
	var s := {
		"meta": {"title": "T3", "dimension": "3d"},
		"world": {"sky_color": "#7ec8f2", "ambient": "snow"},
		"player": {"position": [0, 2, 0]},
		"rules": {"win": "goal"},
		"entities": {
			"g": {"kind": "platform", "position": [0, 0, 0], "size": [10, 1, 10]},
			"c": {"kind": "collectible", "position": [2, 1.5, 0]},
			"cp": {"kind": "checkpoint", "position": [3, 1.6, 2]},
			"goal": {"kind": "goal", "position": [4, 2, 0]},
		},
	}
	var m := await _boot(s, "play")
	check(m.world != null and m.dim == "3d", "3d world created")
	check(m.world.ents.size() == 4, "3d entities spawned")
	m.on_goal()
	check(m.game_over, "3d goal wins")
	await _free(m)
