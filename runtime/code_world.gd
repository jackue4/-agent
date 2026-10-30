extends Node2D
## World for AI-written games (meta.engine == "code"). The game is ordinary GDScript produced by
## the platform's code agent: spec.code.files maps file names to source, entry "main.gd".
##
## Each version is written to its own user://ugc/<key>/v<n>/ folder, so preload() between the
## game's modules never hits a stale cache. In edit mode a new version is "built" in front of the
## user: nodes that did not exist in the previous version start hidden and are revealed one by one
## by the builder drone, so any genre - cards, puzzles, sims - gets the same visible build process.
const Drone = preload("res://drone2d.gd")

const ENTRY := "main.gd"
const MAX_REVEAL := 42
const REVEAL_DEPTH := 5

var main = null
var spec := {}
var playing := false
var cam = null              ## no shared camera: games own their view (main.gd checks for null)
var game: Node = null
var version := 0
var last_errors: Array = []
var _layer: CanvasLayer     ## drone + build overlay above the game
var _drone = null
var _host: Node             ## parent of the running game node
var _key := ""
var _building := false
var kit: Node
var _crew := {}             ## agent id ("A" | "B" | "C") -> crew drone
var _blueprint: Control     ## quiet waiting scene, removed when the first game version loads
## Crew home spots as fractions of the screen (works for landscape and portrait).
const CREW_HOME := {"A": Vector2(0.12, 0.16), "B": Vector2(0.12, 0.84), "C": Vector2(0.88, 0.16)}

func setup(m, s: Dictionary) -> void:
	main = m
	spec = s
	kit = m.kit
	kit.main = m
	kit.reset()
	kit.set_palette(U_palette(s))
	_key = "%d_%d" % [int(Time.get_unix_time_from_system()), randi() % 100000]
	_cleanup_stale()
	_host = Node.new()
	_host.name = "Game"
	add_child(_host)
	_layer = CanvasLayer.new()
	_layer.layer = 30
	add_child(_layer)
	_drone = Drone.new()
	_drone.visible = false
	_drone.position = Vector2(-120, 120)
	_layer.add_child(_drone)
	var files = U_files(s)
	if not files.is_empty():
		_load_version(files, not playing, "")

static func U_palette(s: Dictionary) -> Array:
	var meta = s.get("meta", {})
	var p = meta.get("palette", []) if typeof(meta) == TYPE_DICTIONARY else []
	return p if typeof(p) == TYPE_ARRAY else []

static func U_files(s: Dictionary) -> Dictionary:
	var c = s.get("code", {})
	if typeof(c) != TYPE_DICTIONARY:
		return {}
	var f = c.get("files", {})
	return f if typeof(f) == TYPE_DICTIONARY else {}

## Hot update from the editor while the AI builds: rebuild with the reveal animation.
func apply_code(files: Dictionary, label: String, agent := "") -> void:
	var c = spec.get("code", {})
	if typeof(c) != TYPE_DICTIONARY:
		c = {}
	c["files"] = files
	spec["code"] = c
	await _load_version(files, true, label, agent)

func _load_version(files: Dictionary, animate: bool, label: String, agent := "") -> void:
	version += 1
	var dir := "user://ugc/%s/v%d" % [_key, version]
	DirAccess.make_dir_recursive_absolute(dir)
	for fname in files:
		var safe := str(fname).get_file()
		if not safe.ends_with(".gd"):
			continue
		var f := FileAccess.open(dir + "/" + safe, FileAccess.WRITE)
		if f:
			f.store_string(str(files[fname]))
			f.close()
	_cleanup_old(version)
	kit.forget_errors()
	var script = ResourceLoader.load(dir + "/" + ENTRY, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var errors: Array = kit.take_errors()
	if script == null or not (script is Script) or not script.can_instantiate():
		if errors.is_empty():
			errors.append({"file": ENTRY, "line": 0, "message": "main.gd 无法加载", "kind": "error"})
		_report(false, errors)
		if animate and _crew.has(agent):
			_crew[agent].say("这里有点小问题，正在修…")
		elif animate and _drone:
			_drone.visible = true
			_drone.say("这里有点小问题，正在修…")
		return
	var node = script.new()
	if not (node is Node):
		_report(false, [{"file": ENTRY, "line": 0, "message": "main.gd 必须 extends Node2D 或 Control", "kind": "error"}])
		return
	var old_paths := {}
	if game and is_instance_valid(game):
		old_paths = _paths(game)
		_host.remove_child(game)
		game.queue_free()
	game = node
	game.name = "AIGame"
	kit.game = game
	if game is Control:
		(game as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
	_host.add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	_report(true, kit.take_errors())
	_hide_blueprint()
	if animate and is_instance_valid(game):
		await _reveal(old_paths, label, agent)

func _report(ok: bool, errors: Array) -> void:
	last_errors = errors
	if main:
		main.emit_event({"type": "code_status", "ok": ok and _count_errors(errors) == 0, "loaded": ok, "version": version, "errors": errors.slice(0, 20)})

static func _count_errors(errors: Array) -> int:
	var n := 0
	for e in errors:
		if str(e.get("kind", "error")) == "error":
			n += 1
	return n

func _cleanup_old(keep: int) -> void:
	var base := "user://ugc/%s" % _key
	var d := DirAccess.open(base)
	if d == null:
		return
	for sub in d.get_directories():
		if sub.begins_with("v") and sub.substr(1).to_int() < keep - 1:
			_rm_tree(base + "/" + sub)

## Removes build folders left by earlier sessions (older than an hour).
func _cleanup_stale() -> void:
	var d := DirAccess.open("user://ugc")
	if d == null:
		return
	var cutoff := int(Time.get_unix_time_from_system()) - 3600
	for sub in d.get_directories():
		var t := sub.get_slice("_", 0).to_int()
		if t > 0 and t < cutoff:
			_rm_tree("user://ugc/" + sub)

static func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm_tree(path + "/" + sub)
	DirAccess.remove_absolute(path)

# ------------------------------------------------------------------ build reveal

func _paths(root: Node) -> Dictionary:
	var out := {}
	for n in _canvas_items(root, 0):
		out[str(root.get_path_to(n))] = true
	return out

func _canvas_items(n: Node, depth: int) -> Array:
	var out: Array = []
	if depth > REVEAL_DEPTH:
		return out
	for c in n.get_children():
		if c is CanvasItem and (c as CanvasItem).visible:
			out.append(c)
		if not (c is CanvasLayer and c == _layer):
			out.append_array(_canvas_items(c, depth + 1))
	return out

## Hides the items that are new in this version and brings them in one by one under the drone.
func _reveal(old_paths: Dictionary, label: String, agent := "") -> void:
	_building = true
	var drone = _drone
	if _crew.has(agent):
		drone = _crew[agent]
		drone.set_state("building")
		drone.show_code("")
	var items: Array = []
	for ci in _canvas_items(game, 0):
		if not old_paths.has(str(game.get_path_to(ci))):
			items.append(ci)
	# keep only the top-most new items when there are too many, so the build stays brisk
	var depth_cap := REVEAL_DEPTH
	while items.size() > MAX_REVEAL and depth_cap > 1:
		depth_cap -= 1
		items = items.filter(func(ci): return _depth(ci) <= depth_cap)
	if items.is_empty():
		_building = false
		if label != "":
			drone.visible = true
			drone.say("已更新")
		return
	var orig := {}
	for ci in items:
		orig[ci] = (ci as CanvasItem).modulate
		(ci as CanvasItem).modulate.a = 0.0
	drone.visible = true
	if label != "":
		drone.say("正在搭建…")
	var step := clampf(3.2 / items.size(), 0.06, 0.28)
	var i := 0
	for ci in items:
		if not is_instance_valid(ci) or not is_instance_valid(game):
			continue
		var r := _screen_rect(ci)
		var tw = drone.fly_to(r.get_center(), step * 0.9)
		await tw.finished
		if not is_instance_valid(ci):
			continue
		drone.beam(r)
		kit.sfx("pop", -8.0, 0.9 + minf(i, 16) * 0.03)
		var target: Color = orig[ci]
		var c := ci as CanvasItem
		var t2 := c.create_tween().set_parallel(true)
		t2.tween_property(c, "modulate", target, 0.22)
		if c is Control:
			var ctl := c as Control
			ctl.pivot_offset = ctl.size * 0.5
		var base_scale: Vector2 = c.get("scale")
		c.set("scale", base_scale * 0.6)
		t2.tween_property(c, "scale", base_scale, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1
	await get_tree().create_timer(0.35).timeout
	_building = false
	if _crew.has(agent):
		drone.say("")
		drone.set_state("coding")
		drone.hover_to(_home(agent), 0.7)
	if main:
		main.emit_event({"type": "code_built", "version": version, "revealed": items.size()})

func _depth(n: Node) -> int:
	var d := 0
	var p := n.get_parent()
	while p and p != game:
		d += 1
		p = p.get_parent()
	return d

static func _screen_rect(ci: CanvasItem) -> Rect2:
	var xf := ci.get_global_transform_with_canvas()
	if ci is Control:
		var sz := (ci as Control).size * xf.get_scale()
		return Rect2(xf.origin, sz if sz.length() > 4.0 else Vector2(60, 60))
	return Rect2(xf.origin - Vector2(40, 40), Vector2(80, 80))

# ------------------------------------------------------------------ game_eval

var _eval_n := 0

## Runs a snippet of AI-written GDScript against the running game: the snippet is the body of
## `func run(game, G)`, may await, and its return value comes back as JSON-safe data. The snippet
## is written under user://ugc/ so ErrorCapture reports its errors with line numbers.
func eval_code(code: String, timeout_ms := 15000) -> Dictionary:
	_eval_n += 1
	var dir := "user://ugc/%s/eval" % _key
	DirAccess.make_dir_recursive_absolute(dir)
	var fname := "eval_%d.gd" % _eval_n
	var src := "extends RefCounted\nfunc run(game, G):\n"
	for l in code.replace("\r", "").split("\n"):
		src += "\t" + l + "\n"
	src += "\treturn null\n"
	var f := FileAccess.open(dir + "/" + fname, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "value": null, "errors": [{"file": fname, "line": 0, "message": "无法写入 eval 脚本", "kind": "error"}]}
	f.store_string(src)
	f.close()
	kit.forget_errors()
	var script = ResourceLoader.load(dir + "/" + fname, "", ResourceLoader.CACHE_MODE_IGNORE)
	if script == null or not (script is Script) or not script.can_instantiate():
		var errs: Array = kit.take_errors()
		if errs.is_empty():
			errs.append({"file": fname, "line": 0, "message": "eval 代码无法编译", "kind": "error"})
		return {"ok": false, "value": null, "errors": _eval_lines(errs, fname)}
	var box := {"done": false, "value": null}
	_eval_run(script.new(), box)
	var t0 := Time.get_ticks_msec()
	while not box["done"] and Time.get_ticks_msec() - t0 < timeout_ms:
		await get_tree().process_frame
	var errors: Array = _eval_lines(kit.take_errors(), fname)
	if not box["done"]:
		errors.append({"file": fname, "line": 0, "message": "eval 超过 %d 秒没有结束（await 等不到或死循环）" % (timeout_ms / 1000), "kind": "error"})
	var n_err := _count_errors(errors)
	return {"ok": box["done"] and n_err == 0, "value": jsonable(box["value"]), "errors": errors}

func _eval_run(obj, box: Dictionary) -> void:
	box["value"] = await obj.run(game if is_instance_valid(game) else null, kit)
	box["done"] = true

## Line numbers of the snippet as the AI wrote it (the wrapper adds two header lines).
static func _eval_lines(errors: Array, fname: String) -> Array:
	for e in errors:
		if str(e.get("file", "")) == fname:
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
		TYPE_STRING:
			return (v as String).left(2000)
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [v.x, v.y]
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

# ------------------------------------------------------------------ interface used by main.gd

func start_play() -> void:
	if _drone:
		_drone.visible = false

func drone_say(text: String) -> void:
	if _drone and not playing:
		_drone.visible = text != "" or _drone.visible
		_drone.say(text)
		if text == "" and not _building:
			_drone.visible = false

func focus(_id: String) -> void:
	pass

func frame_all(_animate := true) -> void:
	pass

func refresh_assets(asset_id: String) -> void:
	kit.asset_ready.emit(asset_id)

func op_world(_dur: float) -> void:
	pass

func op_player(_d, _dur: float) -> void:
	pass

func op_entity(_id: String, _d, _dur: float) -> void:
	pass

func op_remove(_id: String, _dur: float) -> void:
	pass

# ------------------------------------------------------------------ AI crew (multi-agent build)

func _home(agent: String) -> Vector2:
	var s := get_viewport().get_visible_rect().size
	var f: Vector2 = CREW_HOME.get(agent, Vector2(0.5, 0.16))
	var p := s * f
	# keep the drone body and its speech bubble inside the screen on narrow (portrait) layouts
	p.x = clampf(p.x, 90.0, s.x - 90.0)
	p.y = clampf(p.y, 110.0, s.y - 90.0)
	return p

## Spawns, updates or retires one crew drone. d: {agent, name, color, state, text, code}.
func crew(d: Dictionary) -> void:
	if playing:
		return
	var agent := str(d.get("agent", ""))
	if agent == "":
		return
	var st := str(d.get("state", ""))
	var drone = _crew.get(agent)
	if drone == null:
		if st == "gone":
			return
		drone = Drone.new()
		_layer.add_child(drone)
		drone.make_crew(str(d.get("name", agent)), Color.from_string(str(d.get("color", "#8b5cf6")), Color("#8b5cf6")))
		var home := _home(agent)
		drone.position = get_viewport().get_visible_rect().size * 0.5 if agent != "A" else home
		_crew[agent] = drone
		drone.hover_to(home, 0.8)
		kit.sfx("sparkle", -6.0, 1.0 + float(_crew.size()) * 0.12)
	if st == "gone":
		_crew.erase(agent)
		var tw: Tween = drone.create_tween()
		tw.tween_property(drone, "modulate:a", 0.0, 0.4)
		tw.tween_callback(drone.queue_free)
		return
	# once the game is on screen the crew shrinks so it doesn't cover the game's own UI
	var small := game != null and is_instance_valid(game)
	drone.scale = Vector2(0.72, 0.72) if small else Vector2.ONE
	drone.modulate.a = 0.9 if small else 1.0
	if st != "":
		drone.set_state(st)
		drone.say(_crew_status(agent, st))
	if d.has("text"):
		drone.say(_crew_status(agent, drone.state) if str(d["text"]) != "" else "")
	if d.has("target") and _building == false:
		var tp = d["target"]
		if typeof(tp) == TYPE_ARRAY and tp.size() == 2:
			drone.hover_to(Vector2(float(tp[0]), float(tp[1])), 0.6)

func crew_clear() -> void:
	for a in _crew.keys():
		crew({"agent": a, "state": "gone"})

static func _crew_status(agent: String, state: String) -> String:
	match state:
		"thinking":
			return "构思中…"
		"coding", "building":
			return "构思中…" if agent == "A" else ("搭建场景…" if agent == "C" else "完善玩法…")
		"testing":
			return "试玩检查…"
		"done":
			return "已完成"
	return ""

## Keep planning inside the scene without exposing implementation details. The protocol still
## accepts the complete design, but only the title, palette and a short state reach the canvas.
func blueprint(d: Dictionary) -> void:
	if playing or (game and is_instance_valid(game)):
		return
	if _blueprint == null:
		_build_blueprint()
	var pal = d.get("palette", [])
	if typeof(pal) == TYPE_ARRAY and pal.size() >= 2:
		var bg: Color = Color.from_string(str(pal[pal.size() - 1 if pal.size() > 3 else 0]), Color("#1b1440"))
		(_blueprint.get_node("Bg") as ColorRect).color = bg.darkened(0.72)
	_set_bp_text("Box/Title", str(d.get("title", "")), true)
	var mods = d.get("modules", [])
	var st := _blueprint.get_node("Box/Status") as Label
	if typeof(mods) == TYPE_ARRAY and not mods.is_empty():
		st.text = "正在搭建游戏…"

## Module events advance the short status without rendering file names or technical details.
func blueprint_mark(_file: String, _text: String) -> void:
	if _blueprint == null:
		return
	(_blueprint.get_node("Box/Status") as Label).text = "正在搭建游戏…"

func _set_bp_text(path: String, text: String, big: bool) -> void:
	var l := _blueprint.get_node(path) as Label
	if text == "" or l.text == text:
		return
	var fresh := l.text == ""
	l.text = text
	if fresh:
		kit.fade_in(l, 0.3)
		if big:
			kit.pop(l, 1.12, 0.3)

func _build_blueprint() -> void:
	_blueprint = Control.new()
	_blueprint.name = "Blueprint"
	_blueprint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blueprint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.add_child(_blueprint)
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.color = Color("#120e2b")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blueprint.add_child(bg)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 16)
	var vs := get_viewport().get_visible_rect().size
	var bw := minf(620.0, vs.x - 80.0)
	box.position = Vector2((vs.x - bw) * 0.5, vs.y * 0.43)
	box.size = Vector2(bw, 120)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blueprint.add_child(box)
	var title: Label = kit.label("", 34, Color("#f3f0ff"), HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "Title"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(bw, 0)
	box.add_child(title)
	var st: Label = kit.label("正在构思游戏…", 20, Color("#aaa2c3"), HORIZONTAL_ALIGNMENT_CENTER)
	st.name = "Status"
	box.add_child(st)

func _hide_blueprint() -> void:
	if _blueprint and is_instance_valid(_blueprint):
		var b := _blueprint
		_blueprint = null
		var tw := b.create_tween()
		tw.tween_property(b, "modulate:a", 0.0, 0.35)
		tw.tween_callback(b.queue_free)
