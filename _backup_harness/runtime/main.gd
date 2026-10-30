extends Node
## UGC runtime entry point. Receives a JSON game spec + build ops from the web editor through
## JavaScriptBridge, animates the AI build in edit mode, and runs the game in play mode.
##
## Responsibilities are split across nodes:
##   Assets  (assets.gd)   – downloads / decodes AI assets, emits `changed(id)`
##   Audio   (audio.gd)    – buses, SFX voice pool, music + ducking
##   GameUI  (game_ui.gd)  – HUD, start / pause / result cards, toasts
##   World   (world2d.gd / world3d.gd) – the level itself
## This script owns the bridge protocol, the build-op queue and the game rules / state machine.
const U = preload("res://util.gd")
const Assets = preload("res://assets.gd")
const Audio = preload("res://audio.gd")
const GameUI = preload("res://game_ui.gd")
const UgcWorld2D = preload("res://world2d.gd")
const UgcWorld3D = preload("res://world3d.gd")
const CodeWorld = preload("res://code_world.gd")

enum State { EDIT, READY, PLAYING, PAUSED, OVER }

const TOPDOWN_GENRES := ["topdown", "top-down", "shooter", "maze", "rpg"]
const HINT_SECONDS := 7.0
const HUD_REFRESH_FRAMES := 6

var assets: Assets
var audio: Audio
var ui: GameUI
var spec := {}
var mode := "edit"
var dim := "2d"
var world = null
var state := State.EDIT

# run stats
var score := 0
var lives := 3
var start_lives := 3
var time_left := 0.0
var elapsed := 0.0
var collected := 0
var total_collect := 0
var defeated := 0
var total_enemies := 0
var damage_taken := 0
var game_over := false
var code_stars := 0
var kit: Node  ## the G autoload (kit.gd); created here when running without autoloads (tests)

# build queue
var op_queue: Array = []
var busy_building := false

# feel
var shake_amt := 0.0
var _hit_stop_left := 0.0

# bridge
var js_cb = null
var js_window = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	kit = get_node_or_null("/root/G")
	if kit == null:
		kit = preload("res://kit.gd").new()
		kit.name = "G"
		get_tree().root.add_child.call_deferred(kit)
	_setup_input()
	assets = Assets.new()
	assets.name = "Assets"
	assets.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(assets)
	assets.changed.connect(_on_asset_changed)
	audio = Audio.new()
	audio.name = "Audio"
	audio.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(audio)
	ui = GameUI.new()
	ui.name = "GameUI"
	add_child(ui)
	ui.start_requested.connect(_begin_play)
	ui.restart_requested.connect(restart)
	ui.resume_requested.connect(_resume)
	ui.pause_requested.connect(func(): if state == State.PLAYING: _pause())
	ui.show_hud(false)
	if OS.has_feature("web"):
		js_window = JavaScriptBridge.get_interface("window")
		js_cb = JavaScriptBridge.create_callback(_on_js)
		js_window.ugcReceive = js_cb
		emit_event({"type": "ready"})
	else:
		_native_boot()

# ---------------------------------------------------------------- native test harness

func _native_boot() -> void:
	var args := OS.get_cmdline_user_args()
	var path := _arg_value(args, "--spec=")
	if path != "" and FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(d) == TYPE_DICTIONARY:
			var m := "play" if "--play" in args else "edit"
			handle({"type": "load", "spec": d.get("spec", d), "assets": d.get("assets", {}), "mode": m, "start_card": "--start-card" in args})
			if typeof(d.get("ops")) == TYPE_ARRAY:
				handle({"type": "ops", "ops": d["ops"]})
	# deterministic UI states for screenshot regression: win | lose | pause
	var sim := _arg_value(args, "--simulate=")
	if sim != "":
		_simulate.call_deferred(sim)
	var bot_path := _arg_value(args, "--bot=")
	if bot_path != "" and dim == "2d":
		var bot = preload("res://bot2d.gd").new()
		var ids: Array[String] = []
		for s in bot_path.split(",", false):
			ids.append(s)
		bot.setup(self, ids)
		add_child(bot)
	if "--autotest" in args and is_code():
		_autotest.call_deferred()
	var shot := _arg_value(args, "--shot=")
	if shot != "" and not "--autotest" in args:
		var secs := _arg_value(args, "--shot-secs=")
		_native_shot(shot, secs.to_float() if secs != "" else 2.5)

func _simulate(what: String) -> void:
	await _wait(1.0)
	match what:
		"win":
			collected = maxi(total_collect - 1, 0)
			score = 42
			elapsed = 37.4
			_win()
		"lose":
			lives = 1
			lose_life()
		"pause":
			_pause()

## Server-side verification of an AI game: run it in play mode, call its auto_test() (which
## drives the game through G.click()/direct calls and asserts with G.check()), then print one
## JSON line the server parses. Quits on its own; the server also enforces a wall-clock limit.
func _autotest() -> void:
	var report := {"loaded": false, "errors": [], "checks": [], "has_test": false, "result": "", "score": 0}
	await _wait(0.4)
	if world and world.has_method("apply_code"):
		report["loaded"] = world.game != null and is_instance_valid(world.game)
		report["errors"].append_array(world.last_errors)
	var shot_path := _arg_value(OS.get_cmdline_user_args(), "--autotest-shot=")
	if report["loaded"] and shot_path != "" and DisplayServer.get_name() != "headless":
		await _wait(0.6)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(960, 540, Image.INTERPOLATE_BILINEAR)
		img.save_jpg(shot_path, 0.8)
		report["shot"] = shot_path
	if report["loaded"]:
		var g = world.game
		if g.has_method("auto_test"):
			report["has_test"] = true
			await g.auto_test()
		else:
			await _wait(1.5)
		await _wait(0.3)
	report["errors"].append_array(kit.take_errors())
	report["checks"] = kit.test_log
	report["result"] = "win" if (game_over and code_stars > 0) else ("lose" if game_over else "")
	report["score"] = kit.score
	print("[autotest] ", JSON.stringify(report))
	get_tree().quit()

static func _arg_value(args: PackedStringArray, prefix: String) -> String:
	for a in args:
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""

func _native_shot(path: String, secs: float) -> void:
	await get_tree().create_timer(secs, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()

func _setup_input() -> void:
	var binds := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"jump": [KEY_SPACE, KEY_K],
		"action": [KEY_J, KEY_F, KEY_ENTER],
		"cam_left": [KEY_Q],
		"cam_right": [KEY_E],
		"restart": [KEY_R],
		"pause": [KEY_ESCAPE, KEY_P],
	}
	for act in binds:
		if not InputMap.has_action(act):
			InputMap.add_action(act, 0.3)
		for k in binds[act]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(act, ev)

# ---------------------------------------------------------------- bridge

func _on_js(args: Array) -> void:
	if args.is_empty():
		return
	var d = JSON.parse_string(str(args[0]))
	if typeof(d) == TYPE_DICTIONARY:
		handle(d)

func emit_event(d: Dictionary) -> void:
	if OS.has_feature("web") and js_window:
		if js_window.ugcEmit:
			js_window.ugcEmit(JSON.stringify(d))
	else:
		print("[ugc] ", JSON.stringify(d).left(300))

func handle(d: Dictionary) -> void:
	match str(d.get("type", "")):
		"load":
			assets.register_all(d.get("assets", {}))
			_load_spec(d.get("spec", {}), str(d.get("mode", "edit")), bool(d.get("start_card", true)))
		"ops":
			var ops = d.get("ops", [])
			if typeof(ops) == TYPE_ARRAY:
				op_queue.append_array(ops)
				if not busy_building:
					_run_ops()
		"asset":
			assets.register(str(d.get("id", "")), str(d.get("kind", "sprite")), str(d.get("state", "pending")), str(d.get("url", "")))
		"play":
			_load_spec(d.get("spec", spec), "play", bool(d.get("start_card", false)))
		"edit":
			_load_spec(d.get("spec", spec), "edit")
		"say":
			if world:
				world.drone_say(str(d.get("text", "")))
		"crew", "blueprint", "blueprint_mark":
			_ensure_code_world()
			if world and mode == "edit":
				match str(d["type"]):
					"crew":
						world.crew(d)
					"blueprint":
						world.blueprint(d)
					_:
						world.blueprint_mark(str(d.get("file", "")), str(d.get("text", "")))
		"crew_clear":
			if world and world.has_method("crew_clear"):
				world.crew_clear()
		"focus":
			if world:
				world.focus(str(d.get("id", "")))
		"frame":
			if world:
				world.frame_all(true)
		"snapshot":
			_snapshot(str(d.get("req", "")), bool(d.get("hide_ui", true)))
		"mute":
			audio.set_muted(bool(d.get("value", true)))

func _snapshot(req: String, hide_ui: bool) -> void:
	var was_visible := ui.visible
	if hide_ui:
		ui.visible = false
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	ui.visible = was_visible
	var w := 640
	img.resize(w, int(img.get_height() * float(w) / img.get_width()), Image.INTERPOLATE_BILINEAR)
	emit_event({"type": "snapshot", "req": req, "data": Marshalls.raw_to_base64(img.save_jpg_to_buffer(0.85))})

# ---------------------------------------------------------------- spec lifecycle

func style_filter() -> String:
	return U.str_of(spec.get("meta", {}), "filter", "smooth")

## Portrait games (phone held upright) design for 720x1280, landscape for 1280x720. The stretch
## mode stays "expand", so the short side is fixed and the long side grows with the real screen.
func is_portrait() -> bool:
	return U.str_of(spec.get("meta", {}), "orientation", "landscape") == "portrait"

func _apply_orientation() -> void:
	var want := Vector2i(720, 1280) if is_portrait() else Vector2i(1280, 720)
	var root := get_tree().root
	if root.content_scale_size != want:
		root.content_scale_size = want

## The AI crew and plan board live in the code world; a brand-new project switches to it early so
## the planning phase already has something to watch.
func _ensure_code_world() -> void:
	if is_code() and world and world.has_method("crew"):
		return
	if mode != "edit":
		return
	var meta = spec.get("meta", {})
	if typeof(meta) != TYPE_DICTIONARY:
		meta = {}
	meta["engine"] = "code"
	meta["dimension"] = "2d"
	spec["meta"] = meta
	_load_spec(spec, "edit")

## AI-written games (code engine) run their own GDScript instead of the entity spec.
func is_code() -> bool:
	return U.str_of(spec.get("meta", {}), "engine", "") == "code"

func is_topdown() -> bool:
	return dim == "2d" and U.str_of(spec.get("meta", {}), "genre", "platformer") in TOPDOWN_GENRES

func _load_spec(s, m: String, start_card := false) -> void:
	spec = (s as Dictionary).duplicate(true) if typeof(s) == TYPE_DICTIONARY else {}
	mode = m
	op_queue.clear()
	busy_building = false
	get_tree().paused = false
	Engine.time_scale = 1.0
	_hit_stop_left = 0.0
	dim = U.str_of(spec.get("meta", {}), "dimension", "2d")
	_apply_orientation()
	if world and is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	if is_code():
		world = CodeWorld.new()
	elif dim == "3d":
		world = UgcWorld3D.new()
	else:
		world = UgcWorld2D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	move_child(world, 0)
	world.playing = m == "play"
	world.setup(self, spec)
	_reset_game()
	_start_music()
	ui.close_card()
	ui.set_title(U.str_of(spec.get("meta", {}), "title", ""))
	ui.set_minimal_hud(is_code())
	if is_code():
		ui.configure_touch("none", false)
	else:
		ui.configure_touch("3d" if dim == "3d" else ("topdown" if is_topdown() else "platformer"), bool(U.dict_of(spec, "player").get("can_shoot", false)))
	if m == "play":
		world.start_play()
		if start_card:
			state = State.READY
			get_tree().paused = true
			ui.show_hud(false)
			ui.show_start(U.str_of(spec.get("meta", {}), "title", "开始游戏"), objective_text(), controls())
		else:
			_begin_play()
	else:
		state = State.EDIT
		ui.show_hud(false)
	emit_event({"type": "loaded", "mode": m, "dimension": dim})

func _begin_play() -> void:
	state = State.PLAYING
	get_tree().paused = false
	ui.close_card()
	ui.show_hud(true)
	var instr := U.str_of(spec.get("rules", {}), "instructions", "")
	ui.set_hint(U.clean_text(instr) if instr != "" else objective_text(), true)
	audio.play("whoosh")
	_refresh_hud()

func restart() -> void:
	_load_spec(spec, "play", false)

func _pause() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	get_tree().paused = true
	ui.show_pause()

func _resume() -> void:
	if state != State.PAUSED:
		return
	state = State.PLAYING
	get_tree().paused = false
	ui.close_card()

func objective_text() -> String:
	if is_code():
		return U.clean_text(U.str_of(spec.get("meta", {}), "goal_text", ""))
	var r = spec.get("rules", {})
	match U.str_of(r, "win", "goal"):
		"collect_all": return "收集全部 %d 个收集物" % total_collect
		"defeat_all": return "击败全部 %d 个敌人" % total_enemies
		"score": return "得到 %d 分" % int(U.num(r, "target_score", 0))
		"survive": return "坚持 %d 秒" % int(U.num(r, "time_limit", 60))
	return "到达终点"

## [[keys, description], ...] for the start card.
func controls() -> Array:
	if is_code():
		return _code_controls()
	var can_shoot := bool(U.dict_of(spec, "player").get("can_shoot", false))
	var out: Array = []
	if GameUI.wants_touch():
		out = [["左侧摇杆", "移动"]]
		if dim == "3d" or not is_topdown():
			out.append(["跳", "跳跃"])
		if can_shoot:
			out.append(["射", "射击"])
		return out
	if dim == "3d":
		out = [["W A S D", "移动"], ["空格", "跳跃"], ["Q E", "转视角"]]
	elif is_topdown():
		out = [["W A S D", "移动"]]
	else:
		out = [["← →", "移动"], ["空格", "跳跃"]]
	if can_shoot:
		out.append(["J", "射击"])
	return out

## meta.controls: [[key, what], ...] written by the AI; touch devices get the touch wording.
func _code_controls() -> Array:
	var out: Array = []
	var cs = spec.get("meta", {}).get("controls", []) if typeof(spec.get("meta")) == TYPE_DICTIONARY else []
	if typeof(cs) != TYPE_ARRAY:
		return out
	for c in cs:
		if typeof(c) == TYPE_ARRAY and c.size() >= 2:
			var k := str(c[0])
			if GameUI.wants_touch():
				k = k.replace("鼠标点击", "点击").replace("鼠标拖动", "拖动").replace("鼠标", "手指")
			out.append([U.clean_text(k), U.clean_text(str(c[1]))])
		if out.size() >= 4:
			break
	return out

func _start_music() -> void:
	var mid := U.str_of(spec.get("world", {}), "music_asset", "")
	var st = assets.get_res(mid) if mid != "" else null
	audio.set_music(st if st is AudioStream else null)

func _reset_game() -> void:
	var r = spec.get("rules", {})
	score = 0
	collected = 0
	defeated = 0
	elapsed = 0.0
	damage_taken = 0
	game_over = false
	code_stars = 0
	start_lives = maxi(1, int(U.num(r, "lives", 3)))
	lives = start_lives
	time_left = U.num(r, "time_limit", 0.0)
	total_collect = 0
	total_enemies = 0
	var es = spec.get("entities", {})
	if typeof(es) == TYPE_DICTIONARY:
		for id in es:
			match U.str_of(es[id], "kind", ""):
				"collectible": total_collect += 1
				"enemy": total_enemies += 1
	_apply_sound_overrides()

func _apply_sound_overrides() -> void:
	audio.overrides.clear()
	var snd = spec.get("sounds", {})
	if typeof(snd) != TYPE_DICTIONARY:
		return
	for n in snd:
		var st = assets.get_res(str(snd[n]))
		if st is AudioStream:
			audio.overrides[n] = st

# ---------------------------------------------------------------- animated build ops

func _run_ops() -> void:
	busy_building = true
	if world and world.playing:
		_load_spec(spec, "edit")
		busy_building = true
	while not op_queue.is_empty():
		var op = op_queue.pop_front()
		if typeof(op) != TYPE_DICTIONARY:
			continue
		# long batches play faster so the build never drags
		var pace := clampf(4.0 / float(op_queue.size() + 1), 0.18, 0.55)
		await _apply_op(op, pace)
		if not is_instance_valid(world):
			break
		emit_event({"type": "op_done", "op_id": op.get("op_id", ""), "remaining": op_queue.size()})
	busy_building = false
	if world:
		world.drone_say("")
		world.frame_all(true)
	_reset_game()
	emit_event({"type": "build_idle"})

func _apply_op(op: Dictionary, pace: float) -> void:
	var label := str(op.get("label", ""))
	if label != "" and world and str(op.get("agent", "")) == "":
		world.drone_say(label)
	match str(op.get("op", "")):
		"set_meta":
			var meta = op.get("meta", {})
			var old_dim := dim
			var old_genre := U.str_of(spec.get("meta", {}), "genre", "")
			var old_engine := U.str_of(spec.get("meta", {}), "engine", "")
			spec["meta"] = meta
			var nd := U.str_of(meta, "dimension", "2d")
			var code_both := old_engine == "code" and U.str_of(meta, "engine", "") == "code"
			if code_both:
				kit.set_palette(CodeWorld.U_palette(spec))
			elif old_engine != U.str_of(meta, "engine", "") or nd != old_dim or (nd == "2d" and old_genre != U.str_of(meta, "genre", "")):
				_load_spec(spec, "edit")
				busy_building = true
			ui.set_title(U.str_of(meta, "title", ""))
			await _wait(pace * 0.4)
		"set_world":
			spec["world"] = op.get("world", {})
			world.spec = spec
			await world.op_world(pace)
			_start_music()
		"set_rules":
			spec["rules"] = op.get("rules", {})
			audio.play("sparkle", -4.0)
			await _wait(pace * 0.3)
		"set_settings":
			spec["settings"] = op.get("settings", {})
		"set_player":
			spec["player"] = op.get("player", {})
			world.spec = spec
			await world.op_player(spec["player"], pace)
		"add", "update", "set_entity":
			var id := str(op.get("id", ""))
			var e = op.get("entity", {})
			if id == "" or typeof(e) != TYPE_DICTIONARY:
				return
			if typeof(spec.get("entities")) != TYPE_DICTIONARY:
				spec["entities"] = {}
			spec["entities"][id] = e
			world.spec = spec
			await world.op_entity(id, e, pace)
		"remove":
			var rid := str(op.get("id", ""))
			if typeof(spec.get("entities")) == TYPE_DICTIONARY:
				spec["entities"].erase(rid)
			await world.op_remove(rid, pace)
		"asset":
			assets.register(str(op.get("id", "")), str(op.get("kind", "sprite")), str(op.get("state", "pending")), str(op.get("url", "")))
		"reload":
			_load_spec(op.get("spec", spec), "edit")
			busy_building = true
		"code":
			var files = op.get("files", {})
			if typeof(files) == TYPE_DICTIONARY and world and world.has_method("apply_code"):
				spec["code"] = {"files": files}
				await world.apply_code(files, label, str(op.get("agent", "")))

func _wait(secs: float) -> void:
	await get_tree().create_timer(secs, true, false, true).timeout

func _on_asset_changed(id: String) -> void:
	if world and is_instance_valid(world):
		world.refresh_assets(id)
	if U.str_of(spec.get("world", {}), "music_asset", "") == id:
		_start_music()
	_apply_sound_overrides()
	emit_event({"type": "asset_state", "id": id, "state": assets.state(id)})

func on_dragged(id: String, pos: Array) -> void:
	if id == "__player":
		if typeof(spec.get("player")) == TYPE_DICTIONARY:
			spec["player"]["position"] = pos
	elif typeof(spec.get("entities")) == TYPE_DICTIONARY and spec["entities"].has(id):
		spec["entities"][id]["position"] = pos
	emit_event({"type": "moved", "id": id, "position": pos})

# ---------------------------------------------------------------- feel services (used by worlds)

func sfx(n: String, vol := 0.0) -> void:
	if n == "coin":
		audio.play_combo(n)
	else:
		audio.play(n, vol)

func shake(a: float) -> void:
	shake_amt = maxf(shake_amt, a)

## Freeze gameplay for a few frames to sell an impact. Uses real time so it always recovers.
func hit_stop(secs: float) -> void:
	if state != State.PLAYING:
		return
	_hit_stop_left = maxf(_hit_stop_left, secs)
	Engine.time_scale = 0.05

func on_checkpoint() -> void:
	audio.play("checkpoint")
	ui.toast("检查点！", Color("#4cc9f0"), 1.0)

# ---------------------------------------------------------------- game rules

func add_score(v: int) -> void:
	score += v
	_refresh_hud()
	var r = spec.get("rules", {})
	var target := U.num(r, "target_score", 0.0)
	if U.str_of(r, "win", "") == "score" and target > 0.0 and score >= target:
		_win()

func on_collect() -> void:
	collected += 1
	_refresh_hud()
	if U.str_of(spec.get("rules", {}), "win", "goal") == "collect_all":
		var left := total_collect - collected
		if left <= 0:
			_win()
		elif left <= 3:
			ui.toast("还剩 %d 个！" % left, Color("#ffd23f"), 0.8)

func on_defeat() -> void:
	defeated += 1
	_refresh_hud()
	if U.str_of(spec.get("rules", {}), "win", "goal") == "defeat_all" and defeated >= total_enemies:
		_win()

func on_goal() -> void:
	var w := U.str_of(spec.get("rules", {}), "win", "goal")
	if w == "goal" or w == "":
		_win()
	elif w == "collect_all" and collected < total_collect:
		ui.toast("还差 %d 个收集物！" % (total_collect - collected), Color("#ffd23f"))
	elif w == "defeat_all" and defeated < total_enemies:
		ui.toast("还有 %d 个敌人！" % (total_enemies - defeated), Color("#ff8fa3"))

## Returns true when the player should respawn (still has lives).
func lose_life() -> bool:
	if game_over or state != State.PLAYING:
		return false
	lives -= 1
	damage_taken += 1
	hit_stop(0.09)
	_refresh_hud()
	if lives <= 0:
		_lose()
		return false
	return true

## Called by G.win()/G.lose() from AI code.
func code_over(win: bool, final_score: int, st: int) -> void:
	if game_over or mode != "play" or state != State.PLAYING:
		return
	score = final_score
	code_stars = st
	if win:
		_win()
	else:
		_lose()

func stars() -> int:
	if is_code():
		return clampi(code_stars, 1, 3)
	var r = spec.get("rules", {})
	var n := 1
	var all_collected := total_collect == 0 or collected >= total_collect
	if all_collected and (total_collect > 0 or damage_taken == 0):
		n += 1
	var par := U.num(r, "par_time", 0.0)
	if (par > 0.0 and elapsed <= par) or (par <= 0.0 and damage_taken == 0 and all_collected):
		n += 1
	return mini(n, 3)

func _result(win: bool) -> Dictionary:
	var r = spec.get("rules", {})
	var tip := ""
	if win:
		if total_collect > 0 and collected < total_collect:
			tip = "还有 %d 个收集物没拿到哦" % (total_collect - collected)
		elif U.num(r, "par_time", 0.0) > 0.0 and elapsed > U.num(r, "par_time", 0.0):
			tip = "再快一点就能拿到三星！"
	elif not is_code():
		tip = "别灰心，熟悉路线后再试一次！"
	return {
		"win": win, "stars": stars() if win else 0, "score": score, "time": elapsed,
		"par_time": U.num(r, "par_time", 0.0), "collected": collected, "total_collect": total_collect,
		"defeated": defeated, "total_enemies": total_enemies, "tip": tip,
		"title": U.clean_text(U.str_of(r, "win_text", "通关！") if win else U.str_of(r, "lose_text", "游戏结束")),
	}

func _win() -> void:
	if game_over or mode != "play":
		return
	game_over = true
	state = State.OVER
	audio.duck()
	audio.play("win")
	shake(6.0)
	var res := _result(true)
	await _wait(0.6)
	ui.show_hud(false)
	ui.show_result(res, func(_i): audio.play("star", 0.0, 1.0 + _i * 0.12))
	emit_event({"type": "game_over", "result": "win", "score": score, "time": elapsed, "stars": res["stars"]})

func _lose() -> void:
	if game_over or mode != "play":
		return
	game_over = true
	state = State.OVER
	audio.duck()
	audio.play("lose")
	await _wait(0.8)
	ui.show_hud(false)
	ui.show_result(_result(false), Callable())
	emit_event({"type": "game_over", "result": "lose", "score": score, "time": elapsed})

func _refresh_hud() -> void:
	if state == State.EDIT:
		return
	var r = spec.get("rules", {})
	var timer_mode := "none"
	var t := elapsed
	if U.num(r, "time_limit", 0.0) > 0.0:
		timer_mode = "down"
		t = time_left
	elif U.num(r, "par_time", 0.0) > 0.0:
		timer_mode = "up"
	ui.update_stats({
		"lives": lives, "collected": collected, "total_collect": total_collect, "defeated": defeated,
		"total_enemies": total_enemies, "score": score, "time": t, "timer_mode": timer_mode,
		"objective": U.str_of(r, "win", "goal"), "target_score": int(U.num(r, "target_score", 0)),
	})
	if world and world.has_method("progress"):
		ui.set_progress(world.progress())

# ---------------------------------------------------------------- frame loop

func _process(delta: float) -> void:
	_tick_hit_stop()
	match state:
		State.PLAYING:
			_tick_play(delta)
		State.OVER:
			if Input.is_action_just_pressed("restart"):
				restart()
		State.PAUSED:
			if Input.is_action_just_pressed("pause"):
				_resume()
	_tick_shake(delta)

func _tick_play(delta: float) -> void:
	if Input.is_action_just_pressed("pause"):
		_pause()
		return
	if Input.is_action_just_pressed("restart"):
		restart()
		return
	var real_dt := delta / maxf(Engine.time_scale, 0.0001) if _hit_stop_left > 0.0 else delta
	elapsed += real_dt
	if elapsed > HINT_SECONDS:
		ui.fade_hint()
	if time_left > 0.0:
		var before := int(ceil(time_left))
		time_left -= real_dt
		if time_left <= 10.0 and int(ceil(time_left)) != before and time_left > 0.0:
			audio.play("tick")
		if time_left <= 0.0:
			time_left = 0.0
			if U.str_of(spec.get("rules", {}), "win", "") == "survive":
				_win()
			else:
				_lose()
	if is_code():
		score = kit.score
	if Engine.get_process_frames() % HUD_REFRESH_FRAMES == 0:
		_refresh_hud()

func _tick_hit_stop() -> void:
	if _hit_stop_left <= 0.0:
		return
	_hit_stop_left -= get_process_delta_time() / maxf(Engine.time_scale, 0.0001)
	if _hit_stop_left <= 0.0:
		Engine.time_scale = 1.0

func _tick_shake(delta: float) -> void:
	if world == null or world.cam == null:
		return
	var real_dt := delta / maxf(Engine.time_scale, 0.0001)
	if shake_amt > 0.1:
		shake_amt = lerpf(shake_amt, 0.0, minf(1.0, real_dt * 9.0))
		if world.cam is Camera2D:
			world.cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amt
		else:
			world.cam.h_offset = randf_range(-1, 1) * shake_amt * 0.02
			world.cam.v_offset = randf_range(-1, 1) * shake_amt * 0.02
	elif shake_amt > 0.0:
		shake_amt = 0.0
		if world.cam is Camera2D:
			world.cam.offset = Vector2.ZERO
		else:
			world.cam.h_offset = 0.0
			world.cam.v_offset = 0.0