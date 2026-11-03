extends Node2D
## A cosmetic build fairy flying over the real game while it is being made. It is driven only by
## platform work events and the assembly pass; it never reads input or touches game nodes.

signal departed(actor_id: String)

const FONT_PATH := "res://addons/ugc/font.ttf"
const STATES := ["thinking", "coding", "building", "testing", "fixing", "saved", "done", "paused", "gone"]
const SPEED := 520.0

var actor_id := ""
var title := "小精灵"
var state := "thinking"
var file := ""
var accent := Color("#8ff0ff")
var viewport_size := Vector2(1280, 720)
var destination := Vector2.ZERO
var walking := true          ## In flight towards `destination` (same field as the engineer actor).
var leaving := false
var particles: Array[Dictionary] = []
var bubble := ""
var bubble_time := 0.0
var action_time := 0.0
var casting := 0.0           ## > 0 while a build burst plays at the wand tip.
var module_name := ""
var _assist := false         ## The assembly pass owns the flight target.
var _hover := Vector2.ZERO
var _wander_clock := 0.0
var _flap := 0.0
var _face := 1.0
var _bob := 0.0
var _rng := RandomNumberGenerator.new()
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH) as Font

func setup(key: String, data: Dictionary, size: Vector2, _has_station: bool = false) -> void:
	actor_id = key
	name = "Fairy_" + str(absi(key.hash()))
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = absi(key.hash()) + 37
	viewport_size = size
	scale = Vector2.ONE * clampf(minf(size.x, size.y) / 420.0, 1.0, 2.4)
	var hue := float(absi(key.hash()) % 5) / 5.0
	accent = Color.from_hsv(0.5 + hue * 0.35, 0.45, 1.0)
	position = Vector2(-60.0, size.y * 0.3)
	_hover = _pick_spot()
	destination = _hover
	set_work(data)
	set_process_input(false)
	set_process_unhandled_input(false)

func set_work(data: Dictionary) -> void:
	var next := str(data.get("state", state))
	if next not in STATES:
		next = "paused"
	var changed := next != state
	if data.has("name"):
		title = str(data.name).strip_edges().left(8)
	if data.has("color"):
		accent = Color.from_string(str(data.color), accent)
	if data.has("file"):
		file = str(data.file).left(180)
	if data.has("module"):
		module_name = _safe(data.module)
	elif data.has("file") and not file.is_empty():
		module_name = _safe(file.replace("\\", "/").get_file().get_basename())
	state = next
	if changed:
		action_time = 0.0
		bubble = {"thinking": "构思中…", "coding": "施法写代码", "building": "搭建中", "testing": "试玩检查", "fixing": "修一修", "saved": "存好啦", "done": "完成啦", "paused": "歇一会", "gone": ""}.get(next, "")
		if not module_name.is_empty() and next in ["coding", "fixing", "building", "saved"]:
			bubble = module_name + " · " + bubble
		bubble_time = 1.8 if next not in ["paused", "gone"] else 0.0
		if next == "saved":
			_burst(position + Vector2(_face * 18, -6) * scale.x, 14)
	# Steps can carry short human text; never show code, JSON or paths.
	if changed and data.has("step"):
		var short := str(data.step).strip_edges().replace("\n", " ")
		if short != "" and not short.contains("{") and not short.contains("func ") and not short.contains("res://"):
			bubble = short.left(14)
	if state == "paused":
		walking = false
		leaving = false
		_assist = false
		destination = position
		particles.clear()
	elif state == "gone":
		_leave()
	else:
		leaving = false
		walking = position.distance_to(destination) > 3.0
	queue_redraw()

## The assembly pass sends the fairy to a piece of the real screen and plays the build burst.
func assist(point: Vector2, label := "") -> void:
	if leaving or state == "paused":
		return
	_assist = true
	destination = (point + Vector2(-34, -30)).clamp(Vector2(24, 40), viewport_size - Vector2(24, 24))
	walking = true
	if label != "":
		bubble = label.left(14)
		bubble_time = 1.0

func cast(at: Vector2, amount := 10) -> void:
	casting = 0.35
	_burst(at, amount)

func release() -> void:
	_assist = false
	_hover = _pick_spot()
	destination = _hover
	walking = true

func resize_canvas(size: Vector2) -> void:
	scale = Vector2.ONE * clampf(minf(size.x, size.y) / 420.0, 1.0, 2.4)
	if viewport_size == size:
		return
	viewport_size = size
	if not _assist and not leaving:
		_hover = _pick_spot()
		destination = _hover

func _leave() -> void:
	leaving = true
	walking = true
	_assist = false
	destination = Vector2(viewport_size.x + 80.0, -60.0)
	bubble_time = 0.0

func _pick_spot() -> Vector2:
	return Vector2(_rng.randf_range(0.18, 0.82) * viewport_size.x, _rng.randf_range(0.18, 0.62) * viewport_size.y)

func _process(delta: float) -> void:
	resize_canvas(get_viewport().get_visible_rect().size)
	advance(minf(delta, 0.1))

func advance(delta: float) -> void:
	if not is_inside_tree():
		return
	action_time += delta
	bubble_time = maxf(0.0, bubble_time - delta)
	casting = maxf(0.0, casting - delta)
	var resting := state == "paused"
	_flap += delta * (9.0 if resting else 26.0)
	_bob += delta * 2.4
	if state == "done" and not leaving and action_time >= 1.0:
		_leave()
	# Without an assembly target the fairy keeps flying between spots over the actual game.
	if not _assist and not leaving and not resting:
		_wander_clock -= delta
		var dwell := 2.6 if state == "thinking" else 1.2
		if not walking and _wander_clock <= 0.0:
			_hover = _pick_spot()
			destination = _hover
			walking = true
			_wander_clock = dwell
	if walking:
		var movement := destination - position
		if movement.length() > 2.0:
			if absf(movement.x) > 2.0:
				_face = signf(movement.x)
			# While assembling, the fairy must arrive within a fraction of a short piece time.
			var speed := maxf(SPEED * 1.6, movement.length() * 7.0) if _assist else SPEED * 0.55
			position = position.move_toward(destination, speed * delta)
			if particles.size() < 60:
				particles.append({"pos": position + Vector2(-_face * 10, 4) * scale.x, "velocity": Vector2(_rng.randf_range(-18, 18), _rng.randf_range(-6, 22)), "life": 0.6, "max": 0.6, "size": _rng.randf_range(1.5, 3.0), "trail": true})
		else:
			walking = false
			_wander_clock = 0.9 if state in ["coding", "fixing", "building"] else 2.2
			if leaving:
				departed.emit(actor_id)
				queue_free()
				return
	elif not resting and state in ["coding", "fixing", "building", "testing"] and int(action_time * 5.0) != int((action_time - delta) * 5.0):
		_burst(position + Vector2(_face * 22, -16) * scale.x, 3)
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p.life -= delta
		p.pos += p.velocity * delta
		p.velocity *= 0.94
		if p.life <= 0.0:
			particles.remove_at(i)
	queue_redraw()

func _burst(origin: Vector2, count: int) -> void:
	for i in count:
		if particles.size() >= 90:
			break
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		particles.append({"pos": origin, "velocity": dir * _rng.randf_range(40, 150), "life": _rng.randf_range(0.35, 0.8), "max": 0.8, "size": _rng.randf_range(2.0, 4.5), "trail": false})

static func _safe(value) -> String:
	var s := str(value).strip_edges().replace("\n", " ")
	if s.contains("{") or s.contains("res://") or s.contains("func "):
		return ""
	return s.left(10)

func _star(at: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var rr := r if i % 2 == 0 else r * 0.35
		pts.append(at + Vector2.from_angle(i * TAU / 8.0 - PI / 2.0) * rr)
	draw_colored_polygon(pts, color)

func _draw() -> void:
	# Particles live in canvas coordinates; the fairy itself is scaled with the viewport.
	for p in particles:
		var at: Vector2 = (p.pos - position) / scale.x
		var trail: bool = p["trail"]
		var a := clampf(float(p["life"]) / float(p["max"]), 0.0, 1.0)
		var col := accent.lerp(Color("#fff3b0"), 0.5 if trail else 0.2)
		col.a = a * (0.65 if trail else 0.95)
		_star(at, float(p["size"]) * (0.6 + a * 0.6), col)
	var bob := Vector2(0, sin(_bob) * 4.0)
	# Soft glow.
	for i in 4:
		draw_circle(bob, 30.0 - i * 6.0, Color(accent.r, accent.g, accent.b, 0.06 + i * 0.035))
	# Wings: two translucent pairs, flapping.
	var flap := 0.55 + absf(sin(_flap)) * 0.45
	var wing := Color(0.92, 0.98, 1.0, 0.55)
	var rim := Color(accent.r, accent.g, accent.b, 0.85)
	for side in [-1.0, 1.0]:
		for pair in 2:
			var size := Vector2(15.0 - pair * 4.0, 9.0 - pair * 2.0)
			var offset := Vector2(side * (9.0 + size.x * 0.55 * flap), -6.0 + pair * 10.0)
			draw_set_transform(bob + offset, side * (-0.5 + pair * 0.9), Vector2(flap, 1.0))
			draw_circle(Vector2.ZERO, size.x, wing)
			draw_arc(Vector2.ZERO, size.x, 0, TAU, 20, rim, 1.2, true)
	draw_set_transform(Vector2.ZERO)
	# Body: dress, head, hair.
	draw_colored_polygon(PackedVector2Array([bob + Vector2(0, -4), bob + Vector2(-8, 13), bob + Vector2(8, 13)]), accent.darkened(0.15))
	draw_circle(bob + Vector2(0, -10), 7.0, Color("#ffe2cf"))
	draw_arc(bob + Vector2(0, -11), 7.5, PI * 1.05, PI * 1.95, 12, accent.lightened(0.3), 4.0, true)
	draw_circle(bob + Vector2(_face * 2.5, -10), 1.2, Color("#30304a"))
	# Wand with a star tip; brighter while casting.
	var hand := bob + Vector2(_face * 7.0, 2.0)
	var tip := hand + Vector2(_face * 14.0, -12.0)
	draw_line(hand, tip, Color("#f5e3a3"), 2.0, true)
	var glow := 1.0 + casting * 4.0
	draw_circle(tip, 4.0 * glow, Color(1.0, 0.95, 0.6, 0.25))
	_star(tip, 5.0 + casting * 6.0, Color("#fff6b8"))
	if bubble_time > 0.0 and bubble != "" and _font != null:
		var fs := 14
		var w := _font.get_string_size(bubble, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 16.0
		var box := Rect2(bob + Vector2(-w * 0.5, -54), Vector2(w, 22))
		var left := (6.0 - position.x) / scale.x
		var right := (viewport_size.x - 6.0 - position.x) / scale.x
		box.position.x = clampf(box.position.x, left, maxf(left, right - w))
		box.position.y = maxf(box.position.y, (6.0 - position.y) / scale.y)
		var a := minf(1.0, bubble_time * 3.0)
		draw_rect(box, Color(0.08, 0.1, 0.2, 0.78 * a))
		draw_rect(box, Color(accent.r, accent.g, accent.b, 0.8 * a), false, 1.5)
		draw_string(_font, box.position + Vector2(8, 16), bubble, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a))
