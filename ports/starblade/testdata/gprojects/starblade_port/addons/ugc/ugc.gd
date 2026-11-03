extends Node
## 造梦 platform plugin, the autoload `UGC` in every AI-made Godot project. The platform owns this
## folder (it is restored on every build). It gives the game a small API (win/lose/score, test
## input, describe) and connects the running game to the platform:
## - native `--ugc-live=<dir>`: command-file channel the server uses for game_eval and screenshots
## - native `--ugc-test` / `--ugc-check`: self-test and load check, one JSON line on stdout
## - web: postMessage bridge to the editor (ready / errors / game_over out, eval / ai_play in)

const EVAL_DIR := "user://ugc_eval"
const OWN_DIR := "res://addons/ugc/"
const OVERLAY_LAYER := 128
const BUILD_FAIRY = preload("res://addons/ugc/build_fairy.gd")
const BUILD_ASSEMBLY = preload("res://addons/ugc/build_assembly.gd")

var show_clicks := false     ## AI test drives leave a ripple where they click
var show_crew := false:      ## Cosmetic actors exist only in an explicitly enabled creation view.
	set(value):
		show_crew = value
		if not value:
			clear_crew()
			if is_instance_valid(_assembly):
				_assembly.queue_free()
			_assembly = null
			var root := game() if is_inside_tree() else null
			if root != null and root.has_meta("creation_yard") and root.has_method("handle_editor"):
				root.call("handle_editor", {"enabled": false, "action": "undo_preview"})
var score := 0
var result := ""             ## "win" | "lose" once the game reports it
var checks: Array = []       ## [{ok, what}] from UGC.check()
var _capture: ErrorCapture
var _overlay: CanvasLayer
var _t0 := 0
var _eval_n := 0
var _eval_queue: Array = []
var _eval_busy := false
var _js_window = null
var _js_cb = null
var _web_build: Dictionary = {}
var _watch_dir := ""
var _watch_seq := 0
var _watch_capturing := false
var _web_test: Node
var _presentation_suspended := false
var _presentation_paused := false
var _presentation_render_loop := true
var _assembly: Node2D

## Script errors raised by the game's own files (res:// outside this addon) and eval snippets.
## Logger callbacks may arrive on any thread, hence the mutex.
class ErrorCapture extends Logger:
	var mutex := Mutex.new()
	var entries: Array = []
	var seen := {}
	static func _ours(f: String) -> bool:
		return (f.begins_with("res://") and not f.begins_with(OWN_DIR)) or f.begins_with(EVAL_DIR)
	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtrace: Array[ScriptBacktrace]) -> void:
		var where := file
		var ln := line
		if not _ours(where):
			where = ""
			for bt in script_backtrace:
				if bt.get_frame_count() > 0 and _ours(bt.get_frame_file(0)):
					where = bt.get_frame_file(0)
					ln = bt.get_frame_line(0)
					break
		var msg := code if rationale == "" else code + " (" + rationale + ")"
		if where == "":
			var m := RegEx.create_from_string("res://[\\w/.\\-]+").search(msg)
			if m == null or m.get_string().begins_with(OWN_DIR):
				return
			where = m.get_string()
			ln = 0
		var e := {"file": where.trim_prefix("res://"), "line": ln, "message": msg.strip_edges(), "kind": "warning" if error_type == ERROR_TYPE_WARNING else "error"}
		var key := "%s:%d:%s" % [e.file, ln, e.message]
		mutex.lock()
		if not seen.has(key) and entries.size() < 200:
			seen[key] = true
			entries.append(e)
		mutex.unlock()
	func take() -> Array:
		mutex.lock()
		var out := entries.duplicate()
		entries.clear()
		mutex.unlock()
		return out

func _init() -> void:
	_capture = ErrorCapture.new()
	OS.add_logger(_capture)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_t0 = Time.get_ticks_msec()
	_overlay = CanvasLayer.new()
	_overlay.layer = OVERLAY_LAYER
	add_child(_overlay)
	if OS.has_feature("web"):
		_web_boot.call_deferred()
		return
	var args := OS.get_cmdline_user_args()
	var sd := _arg(args, "--ugc-seed=")
	if sd != "":
		seed(sd.to_int())
	if DisplayServer.get_name() != "headless":
		_watch_dir = _arg(args, "--ugc-watch=")
		if _watch_dir != "":
			_watch_loop.call_deferred()
	var live := _arg(args, "--ugc-live=")
	if live != "":
		_live_loop.call_deferred(live)
	elif "--ugc-test" in args:
		_self_test.call_deferred(_arg(args, "--ugc-shot="))
	elif "--ugc-check" in args:
		_load_check.call_deferred()

# ------------------------------------------------------------------ game API

## The running game's root (the main scene).
func game() -> Node:
	return get_tree().current_scene

func win(final_score := -1) -> void:
	_over("win", final_score)

func lose(final_score := -1) -> void:
	_over("lose", final_score)

func add_score(n: int) -> void:
	score += n

func _over(r: String, final_score: int) -> void:
	if final_score >= 0:
		score = final_score
	result = r
	emit({"type": "game_over", "result": r, "score": score})

## Awaitable delay: `await UGC.wait(0.3)`
func wait(secs: float) -> Signal:
	return get_tree().create_timer(secs, false).timeout

func check(ok: bool, what: String) -> bool:
	checks.append({"ok": ok, "what": what})
	return ok

func toast(text: String, color := Color.WHITE, secs := 1.6) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := get_viewport().get_visible_rect().size
	l.position = Vector2(0, vs.y * 0.08)
	l.size = Vector2(vs.x, 40)
	_overlay.add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(secs)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)

# ------------------------------------------------------------------ test input

## Simulated left click at a viewport position (goes through normal GUI and _input handling).
func click_at(pos: Vector2) -> void:
	var vp := get_viewport()
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	vp.push_input(mv, true)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		vp.push_input(ev, true)
	if show_clicks:
		var r := Ripple.new()
		r.position = pos
		_overlay.add_child(r)

## Click the centre of a Control, or the screen position of a Node2D.
func click(n: Node) -> void:
	if n is Control and is_instance_valid(n) and (n as Control).is_visible_in_tree():
		click_at((n as Control).get_global_rect().get_center())
	elif n is Node2D and is_instance_valid(n):
		click_at((n as Node2D).get_global_transform_with_canvas().origin)

## Drag with the left mouse button from a to b over `secs`.
func drag(a: Vector2, b: Vector2, secs := 0.3) -> void:
	var vp := get_viewport()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.pressed = true
	ev.position = a
	ev.global_position = a
	vp.push_input(ev, true)
	var steps := maxi(2, int(secs * 30))
	for i in steps:
		var p := a.lerp(b, float(i + 1) / steps)
		var mv := InputEventMouseMotion.new()
		mv.position = p
		mv.global_position = p
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		vp.push_input(mv, true)
		await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = b
	up.global_position = b
	vp.push_input(up, true)

## Hold an input action (from the project's input map) for `secs`: `await UGC.press("jump", 0.2)`
func press(action: String, secs := 0.1) -> void:
	_action(action, true)
	await get_tree().create_timer(secs, false).timeout
	_action(action, false)

func hold(action: String, down := true) -> void:
	_action(action, down)

func _action(action: String, down: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = down
	ev.strength = 1.0 if down else 0.0
	Input.parse_input_event(ev)

## Hold a physical key for `secs`: `await UGC.key(KEY_SPACE, 0.2)`
func key(keycode: Key, secs := 0.1) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.pressed = down
		Input.parse_input_event(ev)
		if down:
			await get_tree().create_timer(secs, false).timeout

class Ripple extends Node2D:
	var t := 0.0
	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
	func _process(dt: float) -> void:
		t += dt * 2.2
		queue_redraw()
		if t >= 1.0:
			queue_free()
	func _draw() -> void:
		var a := 1.0 - t
		draw_circle(Vector2.ZERO, 10.0 + 6.0 * t, Color(1, 1, 1, 0.35 * a))
		draw_arc(Vector2.ZERO, 14.0 + 34.0 * t, 0.0, TAU, 40, Color(1, 0.85, 0.3, a), 4.0, true)

## Node tree with types, screen rects, visibility and text, for checking layouts.
func describe(root: Node = null, depth := 3) -> Array:
	var out: Array = []
	if root == null:
		root = game()
	if root != null and is_instance_valid(root):
		_describe(root, root, depth, out)
	return out

func _describe(root: Node, n: Node, depth: int, out: Array) -> void:
	if out.size() >= 120:
		return
	var d := {"path": str(root.get_path_to(n)), "type": n.get_class()}
	if n is Control:
		var r := (n as Control).get_global_rect()
		d["rect"] = [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]
		d["visible"] = (n as Control).is_visible_in_tree()
	elif n is Node2D:
		var p := (n as Node2D).get_global_transform_with_canvas().origin
		d["screen"] = [roundi(p.x), roundi(p.y)]
		d["visible"] = (n as Node2D).is_visible_in_tree()
	elif n is Node3D:
		var p3 := (n as Node3D).global_position
		d["pos3"] = [snappedf(p3.x, 0.01), snappedf(p3.y, 0.01), snappedf(p3.z, 0.01)]
		d["visible"] = (n as Node3D).is_visible_in_tree()
	var t = n.get("text")
	if typeof(t) == TYPE_STRING and t != "":
		d["text"] = (t as String).left(40)
	out.append(d)
	if depth > 0:
		for c in n.get_children():
			_describe(root, c, depth - 1, out)

# ------------------------------------------------------------------ eval

## Runs a snippet as the body of `func run(game)` (may await); the return value comes back as
## JSON-safe data. Written under user:// so its errors carry line numbers.
func eval_code(code: String, timeout_ms := 15000) -> Dictionary:
	_eval_n += 1
	DirAccess.make_dir_recursive_absolute(EVAL_DIR)
	var path := "%s/eval_%d_%d.gd" % [EVAL_DIR, _t0, _eval_n]
	var src := "extends RefCounted\nfunc run(game):\n"
	for l in code.replace("\r", "").split("\n"):
		src += "\t" + l + "\n"
	src += "\treturn null\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "value": null, "errors": [{"file": "eval", "line": 0, "message": "无法写入 eval 脚本", "kind": "error"}]}
	f.store_string(src)
	f.close()
	_capture.take()
	var script = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if script == null or not (script is Script) or not script.can_instantiate():
		var errs := _eval_lines(_capture.take(), path)
		if errs.is_empty():
			errs.append({"file": "eval", "line": 0, "message": "eval 代码无法编译", "kind": "error"})
		DirAccess.remove_absolute(path)
		return {"ok": false, "value": null, "errors": errs}
	var box := {"done": false, "value": null}
	_eval_run(script.new(), box)
	var t0 := Time.get_ticks_msec()
	while not box["done"] and Time.get_ticks_msec() - t0 < timeout_ms:
		await get_tree().process_frame
	var errors := _eval_lines(_capture.take(), path)
	if not box["done"]:
		errors.append({"file": "eval", "line": 0, "message": "eval 超过 %d 秒没有结束（await 等不到或死循环）" % (timeout_ms / 1000), "kind": "error"})
	DirAccess.remove_absolute(path)
	var n_err := 0
	for e in errors:
		if e["kind"] == "error":
			n_err += 1
	return {"ok": box["done"] and n_err == 0, "value": jsonable(box["value"]), "errors": errors}

func _eval_run(obj, box: Dictionary) -> void:
	box["value"] = await obj.run(game())
	box["done"] = true

static func _eval_lines(errors: Array, path: String) -> Array:
	var short := path.trim_prefix("res://")
	for e in errors:
		if str(e.get("file", "")) == short:
			e["file"] = "eval"
			e["line"] = maxi(0, int(e.get("line", 0)) - 2)
	return errors

static func jsonable(v, depth := 0):
	if depth > 6:
		return str(v)
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return v
		TYPE_FLOAT:
			return snappedf(v, 0.001)
		TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(v).left(2000)
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [v.x, v.y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
		TYPE_RECT2, TYPE_RECT2I:
			return [v.position.x, v.position.y, v.size.x, v.size.y]
		TYPE_COLOR:
			return "#" + (v as Color).to_html(false)
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				if out.size() >= 60:
					out["…"] = "%d keys" % v.size()
					break
				out[str(k)] = jsonable(v[k], depth + 1)
			return out
		TYPE_OBJECT:
			if not is_instance_valid(v):
				return null
			if v is Node:
				return "<%s %s>" % [v.get_class(), v.name]
			return "<%s>" % v.get_class()
	if typeof(v) == TYPE_ARRAY or typeof(v) >= TYPE_PACKED_BYTE_ARRAY:
		var arr: Array = Array(v)
		var out: Array = []
		for i in mini(arr.size(), 60):
			out.append(jsonable(arr[i], depth + 1))
		if arr.size() > 60:
			out.append("… %d items" % arr.size())
		return out
	return str(v)

func take_errors() -> Array:
	return _capture.take()

# ------------------------------------------------------------------ native harness

## Live session (server/live.mjs): the game keeps running while the server drops numbered command
## files into `dir`; each gets a JSON reply, optionally with a screenshot or a strip of frames.
func _live_loop(dir: String) -> void:
	show_clicks = true
	await _frames(20)
	var ready := {"loaded": game() != null, "errors": _capture.take()}
	if ready["loaded"]:
		ready["shot"] = await _save_shot(dir + "/shot_0.jpg")
	ready["state"] = _state()
	_write(dir, "ready", ready)
	var n := 1
	while true:
		var cmd_path := "%s/cmd_%d.json" % [dir, n]
		if not FileAccess.file_exists(cmd_path):
			await get_tree().process_frame
			continue
		var cmd = JSON.parse_string(FileAccess.get_file_as_string(cmd_path))
		var res := {}
		if typeof(cmd) == TYPE_DICTIONARY:
			match str(cmd.get("type", "")):
				"quit":
					get_tree().quit()
					return
				"eval":
					res = await eval_code(str(cmd.get("code", "")), int(cmd.get("timeout_ms", 15000)))
			var frames := int(cmd.get("frames", 1))
			if bool(cmd.get("shot", false)):
				await get_tree().create_timer(float(cmd.get("settle", 0.3)), true, false, true).timeout
				var p := "%s/shot_%d.jpg" % [dir, n]
				if frames > 1:
					res["shot"] = await _save_strip(p, frames, float(cmd.get("span", 1.0)))
				else:
					res["shot"] = await _save_shot(p)
			res["errors"] = res.get("errors", []) + _capture.take()
		res["state"] = _state()
		if _watch_dir != "":
			await _watch_capture()
		_write(dir, "res_%d" % n, res)
		n += 1

## Self-test in a fresh process: screenshot, the main scene's auto_test(), screenshot, report.
func _self_test(shot_path: String) -> void:
	var report := {"loaded": false, "errors": [], "checks": [], "has_test": false, "result": "", "score": 0}
	await _frames(20)
	var g := game()
	report["loaded"] = g != null
	if g and shot_path != "":
		report["shot"] = await _save_shot(shot_path)
	if g:
		if g.has_method("auto_test"):
			report["has_test"] = true
			await g.auto_test()
		else:
			await wait(1.5)
		await _frames(10)
		if shot_path != "" and is_instance_valid(g):
			report["shot_end"] = await _save_shot(shot_path.get_basename() + "_end.jpg")
	# Commit final assertions and the actual final viewport even for a very short test.
	if _watch_dir != "":
		await _watch_capture()
	report["errors"] = _capture.take()
	report["checks"] = checks
	report["result"] = result
	report["score"] = score
	print("[ugc-test] ", JSON.stringify(report))
	get_tree().quit()

## Headless load check: compiles every script of the game and starts the main scene briefly.
func _load_check() -> void:
	for p in _scripts("res://"):
		ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REUSE)
	await _frames(15)
	var report := {"loaded": game() != null, "errors": _capture.take(), "construction": construction_report()}
	print("[ugc-check] ", JSON.stringify(report))
	get_tree().quit()

func construction_report() -> Array:
	var out: Array = []
	for node in get_tree().get_nodes_in_group("ugc_construction_scene"):
		out.append({"revision": int(node.get_meta("construction_revision", -1)), "objectCount": int(node.get_meta("objects_count", 0)), "source_path": str(node.get("source_path"))})
	return out

func _scripts(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		var p := dir.path_join(sub)
		if not sub.begins_with(".") and p + "/" != OWN_DIR and sub != "build":
			out.append_array(_scripts(p))
	return out

func _state() -> Dictionary:
	return {"score": score, "result": result, "time": snappedf((Time.get_ticks_msec() - _t0) / 1000.0, 0.1), "scene": str(game().scene_file_path if game() else "")}

## Independent of eval/auto_test awaits. This captures only this game's viewport.
func _watch_loop() -> void:
	while is_inside_tree() and _watch_dir != "":
		await _watch_capture()
		await get_tree().create_timer(0.25, true, false, true).timeout

func _watch_capture() -> void:
	while _watch_capturing:
		await get_tree().process_frame
	if _watch_dir == "" or not is_inside_tree():
		return
	_watch_capturing = true
	var img := await _grab()
	if img == null or img.is_empty():
		_watch_capturing = false
		return
	var scale_factor := 960.0 / maxf(img.get_width(), img.get_height())
	if scale_factor < 1.0:
		img.resize(maxi(1, int(img.get_width() * scale_factor)), maxi(1, int(img.get_height() * scale_factor)), Image.INTERPOLATE_BILINEAR)
	img.convert(Image.FORMAT_RGB8)
	var next_seq := _watch_seq + 1
	var frame := "frame_%d.jpg" % (next_seq % 2)
	var tmp := _watch_dir.path_join(frame + ".tmp")
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file != null:
		file.store_buffer(img.save_jpg_to_buffer(0.72))
		file.close()
		if DirAccess.rename_absolute(tmp, _watch_dir.path_join(frame)) == OK:
			_watch_seq = next_seq
			var observed_checks: Array = []
			for i in range(maxi(0, checks.size() - 200), checks.size()):
				observed_checks.append({"ok": bool(checks[i].get("ok", false)), "what": str(checks[i].get("what", "")).left(500)})
			_write(_watch_dir, "watch", {"seq": _watch_seq, "frame": frame, "capturedAt": int(Time.get_unix_time_from_system() * 1000.0), "checks": observed_checks, "state": _state()})
	_watch_capturing = false

func _write(dir: String, fname: String, d: Dictionary) -> void:
	var tmp := "%s/%s.tmp" % [dir, fname]
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(d))
	f.close()
	DirAccess.rename_absolute(tmp, "%s/%s.json" % [dir, fname])

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

## JPEG of the current frame, long side at most 960 px.
func _save_shot(path: String) -> String:
	if DisplayServer.get_name() == "headless":
		return ""
	var img := await _grab()
	var s := 960.0 / maxf(img.get_width(), img.get_height())
	if s < 1.0:
		img.resize(int(img.get_width() * s), int(img.get_height() * s), Image.INTERPOLATE_BILINEAR)
	img.save_jpg(path, 0.8)
	return path

## `count` frames spread over `span` seconds tiled into one JPEG (shows motion in real-time games).
func _save_strip(path: String, count: int, span: float) -> String:
	if DisplayServer.get_name() == "headless":
		return ""
	count = clampi(count, 2, 9)
	var cols := 2 if count <= 4 else 3
	var rows := ceili(float(count) / cols)
	var cell := Vector2i.ZERO
	var sheet: Image = null
	for i in count:
		if i > 0:
			await get_tree().create_timer(span / (count - 1), true, false, true).timeout
		var img := await _grab()
		if sheet == null:
			var s := 960.0 / maxf(img.get_width() * cols, img.get_height() * rows)
			cell = Vector2i(int(img.get_width() * s), int(img.get_height() * s))
			sheet = Image.create(cell.x * cols, cell.y * rows, false, Image.FORMAT_RGB8)
		img.convert(Image.FORMAT_RGB8)
		img.resize(cell.x, cell.y, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, cell), Vector2i((i % cols) * cell.x, (i / cols) * cell.y))
	sheet.save_jpg(path, 0.8)
	return path

static func _arg(args: PackedStringArray, prefix: String) -> String:
	for a in args:
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""

# ------------------------------------------------------------------ web bridge

func _web_boot() -> void:
	_js_window = JavaScriptBridge.get_interface("window")
	_js_cb = JavaScriptBridge.create_callback(_on_js)
	_js_window.ugcReceive = _js_cb
	var q = JavaScriptBridge.eval("location.search", true)
	var m := RegEx.create_from_string("[?&]seed=(\\d+)").search(str(q))
	if m:
		seed(m.get_string(1).to_int())
	show_crew = str(q).contains("edit=1")
	if show_crew and str(q).contains("dim=3d") and game() != null and game().has_meta("creation_yard") and game().has_method("set_dimension"):
		game().call("set_dimension", "3d")
	if str(q).contains("ai=1"):
		show_clicks = true
		toast("AI 正在试玩", Color("#ffd166"), 2.0)
	if show_crew and not str(q).contains("workshop=1") and not str(q).contains("runtimeTest=1"):
		_web_assemble.call_deferred(str(q).contains("assemble=1") and not str(q).contains("ai=1"))
	var manifest_path := OWN_DIR + "build.json"
	if FileAccess.file_exists(manifest_path):
		var manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if manifest is Dictionary:
			for field in ["buildId", "sourceRevision", "version"]:
				if manifest.has(field):
					_web_build[field] = manifest[field]
	if str(q).contains("runtimeTest=1"):
		var harness_script = load(OWN_DIR + "web_test_harness.gd")
		_web_test = harness_script.new()
		add_child(_web_test)
		_web_test.configure(self, _web_build, str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('runtimeSession') || ''", true)))
	await _frames(20)
	# A loaded scene and a rendered frame are separate facts. Report after both.
	await RenderingServer.frame_post_draw
	if str(q).contains("workshop=1") or (game() != null and game().has_meta("creation_yard")):
		emit({"type": "workshop_ready", "surface": "workshop", "loaded": game() != null, "errors": _capture.take()})
		_report_errors()
		return
	var ready: Dictionary = _web_build.duplicate()
	ready.merge({"type": "ready", "engine": "godot", "loaded": game() != null, "errors": _capture.take(), "manifest": not _web_build.is_empty()})
	ready["construction"] = construction_report()
	emit(ready)
	if _web_test == null:
		_report_errors()

## Runtime errors seen in the preview go to the editor every second (only when there are new ones).
func _report_errors() -> void:
	while true:
		var errs := _capture.take()
		if not errs.is_empty():
			var report: Dictionary = _web_build.duplicate()
			report.merge({"type": "code_status", "ok": false, "loaded": game() != null, "errors": errs.slice(0, 20)})
			emit(report)
		await get_tree().create_timer(1.0, true, false, true).timeout

func _on_js(args: Array) -> void:
	if args.is_empty():
		return
	var d = JSON.parse_string(str(args[0]))
	if typeof(d) != TYPE_DICTIONARY:
		return
	match str(d.get("type", "")):
		"presentation":
			_presentation(bool(d.get("active", true)))
		"runtime_test":
			if _web_test != null and d.get("command") is Dictionary:
				_web_test.submit(d.command)
		"editor_control":
			var root := game()
			if show_crew and root != null and root.has_meta("creation_yard") and root.has_method("handle_editor"):
				root.call("handle_editor", d)
		"eval":
			if _web_test != null:
				return
			_eval_queue.append(str(d.get("code", "")))
			if not _eval_busy:
				_drain_evals()
		"ai_play":
			show_clicks = true
			toast("AI 正在试玩", Color("#ffd166"), 2.0)
		"mute":
			AudioServer.set_bus_mute(0, bool(d.get("value", false)))
		"snapshot":
			_snapshot(str(d.get("req", "")))
		"crew":
			crew(d)
		"crew_clear":
			clear_crew()
		"workshop":
			workshop(d)
		"construction":
			construction(d)
		"blueprint":
			_blueprint(d)

## A hidden authoring iframe keeps its bridge, scene and original pause settings.
## The separate runtime-test instance must never be paused by this presentation hint.
func _presentation(active: bool) -> void:
	if _web_test != null:
		return
	if not active and not _presentation_suspended:
		_presentation_suspended = true
		_presentation_paused = get_tree().paused
		_presentation_render_loop = RenderingServer.is_render_loop_enabled()
		get_tree().paused = true
		# A frame cap can sleep the shared Web main thread and throttle another iframe.
		# Suspend scene work/drawing only; leave the engine and browser scheduling intact.
		RenderingServer.set_render_loop_enabled(false)
	elif active and _presentation_suspended:
		_presentation_suspended = false
		RenderingServer.set_render_loop_enabled(_presentation_render_loop)
		get_tree().paused = _presentation_paused

# ------------------------------------------------------------------ Cosmetic Node2D creation crew

var _crew: Dictionary = {}
var _crew_canvas: Node2D

func _ensure_crew_canvas() -> void:
	if is_instance_valid(_crew_canvas):
		return
	_crew_canvas = Node2D.new()
	_crew_canvas.name = "UGCCreationCanvas"
	_crew_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	# Overlay coordinates are viewport coordinates: Camera2D and 3D cameras cannot displace them.
	# No input handlers, Control panels, collision shapes, or game-node transforms are added.
	_overlay.add_child(_crew_canvas)

func clear_crew() -> void:
	_crew.clear()
	if is_instance_valid(_crew_canvas):
		_crew_canvas.hide()
		_crew_canvas.queue_free()
	_crew_canvas = null
	var root := game()
	if root != null and root.has_meta("creation_yard") and root.has_method("clear_world_crew"):
		root.call("clear_world_crew")

func crew(d: Dictionary) -> void:
	if not show_crew:
		return
	var root := game()
	if root != null and root.has_meta("creation_yard") and root.has_method("uses_world_crew") and root.call("uses_world_crew"):
		root.call("on_crew", d)
		return
	var agent := str(d.get("agent", "")).left(96)
	if agent.is_empty():
		return
	var st := str(d.get("state", "thinking"))
	var c = _crew.get(agent)
	if not is_instance_valid(c):
		if st in ["gone", "done"] or _crew.size() >= 4:
			return
		_ensure_crew_canvas()
		c = BUILD_FAIRY.new()
		_crew_canvas.add_child(c)
		c.add_to_group("ugc_crew_actor")
		c.setup(agent, d, get_viewport().get_visible_rect().size, game() != null and game().has_meta("creation_yard"))
		c.connect("departed", _crew_left.bind(c))
		_crew[agent] = c
	else:
		c.set_work(d)
	if st == "saved":
		mark_saved(agent, str(d.get("file", "")))

func _crew_left(agent: String, actor: Node) -> void:
	if _crew.get(agent) == actor:
		_crew.erase(agent)

# ------------------------------------------------------------------ build assembly

## Compares the visible pieces of this build with `previous` (the last build's baseline) and,
## when `animate`, plays the assembly pass over what is new. Returns this build's baseline.
func assemble(previous: Dictionary, animate := true) -> Dictionary:
	var root := game()
	if root == null or root.has_meta("creation_yard"):
		return {}
	var view := get_viewport().get_visible_rect()
	var rows: Array = BUILD_ASSEMBLY.scan(root, view)
	var baseline: Dictionary = BUILD_ASSEMBLY.baseline_of(rows)
	if not show_crew or not animate:
		return baseline
	var pieces: Array = BUILD_ASSEMBLY.diff(rows, previous)
	if pieces.is_empty():
		pieces = [{"key": "", "rect": view.grow(-6), "label": "画面", "kind": "changed"}]
	if is_instance_valid(_assembly):
		_assembly.queue_free()
	_assembly = BUILD_ASSEMBLY.new()
	_overlay.add_child(_assembly)
	_overlay.move_child(_assembly, 0)
	_assembly.finished.connect(func(count: int): emit({"type": "assembly_done", "pieces": count}))
	_assembly.start(pieces)
	return baseline

func _web_assemble(animate: bool) -> void:
	await _frames(2)
	var key := JSON.stringify("ugc_assembly:" + str(JavaScriptBridge.eval("(new URLSearchParams(location.search).get('pck')||'').split('?')[0]", true)))
	var stored = JSON.parse_string(str(JavaScriptBridge.eval("(()=>{try{return localStorage.getItem(" + key + ")||'{}'}catch(e){return '{}'}})()", true)))
	var baseline := assemble(stored if stored is Dictionary else {}, animate)
	if not baseline.is_empty():
		JavaScriptBridge.eval("(()=>{try{localStorage.setItem(" + key + "," + JSON.stringify(JSON.stringify(baseline)) + ")}catch(e){}})()", true)

## Optional creation-yard hooks. They do not infer or edit actual generated game objects.
func set_plan(plan: Dictionary) -> void:
	if not show_crew:
		return
	var root := game()
	if root != null and root.has_meta("creation_yard") and root.has_method("set_plan"):
		root.call("set_plan", plan)

func mark_saved(agent: String, file: String) -> void:
	if not show_crew or file.is_empty():
		return
	var root := game()
	if root != null and root.has_meta("creation_yard") and root.has_method("mark_saved"):
		root.call("mark_saved", agent, file)

func workshop(d: Dictionary) -> void:
	if not show_crew:
		return
	var plan = d.get("plan")
	if plan is Dictionary:
		set_plan(plan)
	var actors = d.get("actors")
	if actors is Array:
		var active: Dictionary = {}
		for row in actors.slice(0, 4):
			if row is Dictionary:
				active[str(row.get("agent", ""))] = true
				crew(row)
		for agent in _crew.keys():
			if not active.has(agent):
				crew({"agent": agent, "state": "gone"})
	var root := game()
	if root != null and root.has_meta("creation_yard") and root.has_method("on_workshop"):
		root.call("on_workshop", d)

## Construction is an authoring-only message, never an ordinary game mutation or build receipt.
func construction(d: Dictionary) -> void:
	if not show_crew:
		return
	var root := game()
	if root == null or not root.has_meta("creation_yard") or not root.has_method("apply_construction"):
		return
	var result: Dictionary = await root.call("apply_construction", d)
	if bool(result.get("ignored", false)):
		return
	result.merge({"type": "construction_applied", "surface": "construction"}, true)
	emit(result)

## Title and status on the template's placeholder screen while the game is being designed.
func _blueprint(d: Dictionary) -> void:
	var g := game()
	var st = g.get_node_or_null("Status") if g else null
	if st == null or not (st is Label) or g.scene_file_path != "res://main.tscn" or g.get_child_count() > 2:
		return
	var title := str(d.get("title", ""))
	var status := str(d.get("status", "正在构思游戏…"))
	(st as Label).text = (title + "\n\n" if title != "" else "") + status

func _snapshot(req: String) -> void:
	var img := await _grab()
	var s := 960.0 / maxf(img.get_width(), img.get_height())
	if s < 1.0:
		img.resize(int(img.get_width() * s), int(img.get_height() * s), Image.INTERPOLATE_BILINEAR)
	emit({"type": "snapshot", "req": req, "data": Marshalls.raw_to_base64(img.save_jpg_to_buffer(0.8))})

func _drain_evals() -> void:
	_eval_busy = true
	while not _eval_queue.is_empty():
		var r := await eval_code(_eval_queue.pop_front())
		if not r["ok"]:
			emit({"type": "eval_result", "ok": false, "errors": r["errors"].slice(0, 6)})
	_eval_busy = false

func emit(d: Dictionary) -> void:
	if _js_window and _js_window.ugcEmit:
		_js_window.ugcEmit(JSON.stringify(d))
	elif not OS.has_feature("web"):
		print("[ugc] ", JSON.stringify(d).left(300))
