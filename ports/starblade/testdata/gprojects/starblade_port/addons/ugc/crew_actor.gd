extends Node2D
## A cosmetic engineer driven only by platform work events. No game nodes, inputs or collisions.

signal departed(actor_id: String)

const PORTRAIT_PATH := "res://addons/ugc/pixel-engineer.png"
const FONT_PATH := "res://addons/ugc/font.ttf"
const STATES := ["thinking", "coding", "building", "testing", "fixing", "saved", "done", "paused", "gone"]
const STATIONS := [Vector2(0.26, 0.58), Vector2(0.50, 0.48), Vector2(0.74, 0.58)]

var actor_id := ""
var title := "工程师"
var state := "thinking"
var file := ""
var task_id := ""
var accent := Color("#67d8d1")
var work_point := Vector2.ZERO
var destination := Vector2.ZERO
var viewport_size := Vector2(1280, 720)
var target_normalized := Vector2(0.5, 0.48)
var external_station := false
var explicit_target := false
var walking := true
var leaving := false
var action_time := 0.0
var gait_time := 0.0
var bubble_time := 0.0
var bubble := ""
var particles: Array[Dictionary] = []
var completed_strokes := 0
var emitted_particles := 0
var desk_open := 0.0
var typing := false
var typing_time := 0.0
var left_key_presses := 0
var right_key_presses := 0
var left_hand := Vector2.ZERO
var right_hand := Vector2.ZERO
var _key_beat := -1
var module_name := ""
var module_step := ""
var module_flash := 0.0
var module_changes := 0
var _spark_clock := 0.0
var _last_stroke := -1
var _face := 1.0
var _rng := RandomNumberGenerator.new()
var _portrait: Texture2D
var _font: Font

func _ready() -> void:
	# A fresh project's scripts are parsed before PNG/font import. Loading in _ready keeps
	# that first import valid; the all_resources export preset still includes both assets.
	_font = ThemeDB.fallback_font
	if ResourceLoader.exists(PORTRAIT_PATH):
		_portrait = load(PORTRAIT_PATH) as Texture2D
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH) as Font

func setup(key: String, data: Dictionary, size: Vector2, has_station: bool = false) -> void:
	actor_id = key
	name = "Engineer_" + str(absi(key.hash()))
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	external_station = has_station
	_rng.seed = absi(key.hash()) + 71
	viewport_size = size
	position = Vector2(-70.0, size.y * 0.82)
	if str(data.get("state", "")) == "paused":
		position = Vector2(95.0, size.y * 0.82)
	set_work(data)
	set_process_input(false)
	set_process_unhandled_input(false)
	queue_redraw()

func set_work(data: Dictionary) -> void:
	var previous_module := module_name + "|" + file
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
	if data.has("taskId"):
		task_id = str(data.taskId).left(80)
	if data.has("step"):
		module_step = _safe_module(data.step)
	if data.has("module"):
		module_name = _safe_module(data.module)
	elif data.has("file") and not file.is_empty():
		module_name = _safe_module(file.replace("\\", "/").get_file().get_basename())
	elif module_name.is_empty() and data.has("step"):
		module_name = module_step
	if module_name + "|" + file != previous_module:
		module_changes += 1
		module_flash = 1.2
	var target = data.get("target")
	if target is Dictionary and target.has("x") and target.has("y"):
		var x := float(target.x)
		var y := float(target.y)
		if is_finite(x) and is_finite(y):
			target_normalized = Vector2(clampf(x, 0.08, 0.92), clampf(y, 0.18, 0.80))
			explicit_target = true
	elif not file.is_empty() or not task_id.is_empty() or destination == Vector2.ZERO:
		var key := file if not file.is_empty() else (task_id if not task_id.is_empty() else actor_id)
		target_normalized = STATIONS[absi(key.hash()) % STATIONS.size()]
		explicit_target = false
	state = next
	if changed:
		action_time = 0.0
		_last_stroke = -1
		_spark_clock = 0.0
		_key_beat = -1
		bubble = _short_status(next)
		bubble_time = 1.6 if next not in ["paused", "gone"] else 0.0
	# Never render source, partial JSON, or internal reasoning in the scene.
	if data.has("step") and not str(data.step).is_empty() and changed:
		var short := str(data.step).strip_edges().replace("\n", " ")
		if not short.contains("{") and not short.contains("func ") and not short.contains("res://"):
			bubble = short.left(12)
	if not module_name.is_empty():
		var short_state: String = {"coding":"编写", "fixing":"修正", "saved":"已保存", "testing":"观察", "building":"搭建", "thinking":"规划", "paused":"暂停", "done":"结束"}.get(state, "")
		bubble = module_name + "·" + short_state
	_update_destination()
	if state in ["paused", "saved", "done"]:
		walking = false
		leaving = false
		destination = position
		particles.clear()
		typing = false
	elif state == "gone":
		_leave()
	else:
		leaving = false
		walking = position.distance_to(destination) > 3.0
	queue_redraw()

func resize_canvas(size: Vector2) -> void:
	if viewport_size == size:
		return
	viewport_size = size
	_update_destination()
	if leaving:
		destination = Vector2(viewport_size.x + 90.0, minf(position.y, viewport_size.y - 20.0))
	elif state == "paused":
		position = position.clamp(Vector2(24, 100), viewport_size - Vector2(24, 10))
		destination = position

func _update_destination() -> void:
	work_point = viewport_size * target_normalized
	# Two workers using one bench stand on opposite sides, never modifying game geometry.
	var side := -1.0 if absi(actor_id.hash()) % 2 == 0 else 1.0
	destination = (work_point + Vector2(side * 42.0, 48.0)).clamp(Vector2(35, 110), viewport_size - Vector2(35, 12))
	_face = -side

func _leave() -> void:
	leaving = true
	walking = true
	destination = Vector2(viewport_size.x + 100.0, minf(position.y + 40.0, viewport_size.y - 10.0))
	bubble_time = 0.0
	particles.clear()
	typing = false

func _process(delta: float) -> void:
	resize_canvas(get_viewport().get_visible_rect().size)
	advance(minf(delta, 0.1))

func advance(delta: float) -> void:
	if not is_inside_tree():
		return
	action_time += delta
	module_flash = maxf(0.0, module_flash - delta)
	bubble_time = maxf(0.0, bubble_time - delta)
	if state == "done" and not leaving and action_time >= 0.8:
		_leave()
	if walking:
		var movement := destination - position
		if movement.length() > 1.0:
			_face = signf(movement.x) if absf(movement.x) > 1.0 else _face
			position = position.move_toward(destination, 240.0 * delta)
			gait_time += delta * 9.0
		else:
			walking = false
			if leaving:
				departed.emit(actor_id)
				queue_free()
				return
			_face = signf(work_point.x - position.x)
			action_time = 0.0
	elif state == "building":
		var stroke := int(action_time * 1.6)
		if stroke != _last_stroke:
			_last_stroke = stroke
			completed_strokes += 1
			_sparks(position + Vector2(_face * 28.0, -29.0), 5)
	var desk_active := not walking and not leaving and state in ["coding", "fixing"]
	desk_open = move_toward(desk_open, 1.0 if desk_active else 0.0, delta * 3.5)
	typing = desk_active and desk_open >= 0.95
	if typing:
		typing_time += delta
		var tap := sin(typing_time * TAU * 4.0)
		left_hand = Vector2(_face * 40.0, -29.0 - maxf(0.0, tap) * 4.0)
		right_hand = Vector2(_face * 61.0, -31.0 - maxf(0.0, -tap) * 4.0)
		var beat := int(typing_time * 8.0)
		if beat != _key_beat:
			_key_beat = beat
			completed_strokes += 1
			if beat % 2 == 0:
				left_key_presses += 1
			else:
				right_key_presses += 1
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p.life -= delta
		p.pos += p.velocity * delta
		p.velocity.y += 100.0 * delta
		if p.life <= 0.0:
			particles.remove_at(i)
	queue_redraw()

func _sparks(origin: Vector2, count: int) -> void:
	for i in count:
		if particles.size() >= 36:
			break
		particles.append({"pos": origin, "velocity": Vector2(_rng.randf_range(-75, 75), _rng.randf_range(-100, -25)), "life": _rng.randf_range(0.18, 0.45)})
		emitted_particles += 1

func _draw() -> void:
	if not external_station and not leaving and state not in ["coding", "fixing"] and desk_open < 0.01:
		_draw_station(work_point - position)
	if desk_open > 0.001:
		_draw_coding_desk()
	for p in particles:
		var spark: Vector2 = p.pos - position
		draw_line(spark, spark - Vector2(p.velocity) * 0.035, Color(1.0, 0.82, 0.35, minf(1.0, float(p.life) * 5)), 2.0)
	_draw_engineer()
	if (bubble_time > 0.0 or not module_name.is_empty()) and not walking and state not in ["paused", "gone"]:
		_draw_bubble()

func _draw_coding_desk() -> void:
	# A portable desk unfolds at the actor, independent of any authored scene geometry.
	draw_set_transform(Vector2.ZERO, 0, Vector2(_face, maxf(0.001, desk_open)))
	for x in [23.0, 92.0]:
		draw_line(Vector2(x, -26), Vector2(x - 5, 1), Color("#263f50"), 5)
	draw_colored_polygon(PackedVector2Array([Vector2(13,-33),Vector2(83,-41),Vector2(105,-31),Vector2(34,-22)]), Color("#526d78"))
	draw_line(Vector2(34, -22), Vector2(105, -31), accent, 2)
	# Hinged screen and blank editor-like blocks; no code, progress percentage or success icon.
	var lid := clampf((desk_open - 0.3) / 0.7, 0.0, 1.0)
	var top := -40.0 - lid * 36.0
	draw_colored_polygon(PackedVector2Array([Vector2(65,-38),Vector2(100,-42),Vector2(100,top-4),Vector2(65,top)]), Color("#163546"))
	if lid > 0.3:
		var module_key := absi((module_name + file).hash())
		for line in 4:
			var y := top + 8.0 + line * 5.5
			var length_adjust := (module_key >> (line * 3)) % 9
			draw_line(Vector2(70, y), Vector2(96 - length_adjust, y - 2), Color("#ffe2a1") if module_flash > 0.0 else Color(accent, 0.7), 2)
	draw_colored_polygon(PackedVector2Array([Vector2(31,-32),Vector2(65,-36),Vector2(78,-29),Vector2(44,-25)]), Color("#1b3442"))
	for row in 2:
		for column in 6:
			var p := Vector2(35 + column * 5 + row * 6, -31 + row * 3 - column * 0.5)
			draw_line(p, p + Vector2(3, -0.3), Color("#a8d9d1"), 1.5)
	draw_set_transform(Vector2.ZERO)

func _draw_station(at: Vector2) -> void:
	var dark := Color(0.08, 0.16, 0.21, 0.86)
	draw_set_transform(at)
	draw_colored_polygon(PackedVector2Array([Vector2(-42, 3), Vector2(0, -14), Vector2(42, 3), Vector2(0, 20)]), Color(accent, 0.10))
	draw_line(Vector2(-30, -13), Vector2(-30, 13), dark, 5)
	draw_line(Vector2(29, -13), Vector2(29, 13), dark, 5)
	draw_rect(Rect2(-39, -25, 78, 13), dark)
	draw_line(Vector2(-39, -25), Vector2(39, -25), accent, 2)
	draw_rect(Rect2(-20, -40, 32, 16), Color("#163444"))
	draw_line(Vector2(-16, -35), Vector2(7, -35), Color(accent, 0.8), 2)
	draw_line(Vector2(-16, -30), Vector2(-2, -30), Color(accent, 0.55), 2)
	draw_string(_font, Vector2(-23, 31), "工具工位", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.78, 0.88, 0.89, 0.8))
	draw_set_transform(Vector2.ZERO)

func _draw_engineer() -> void:
	var walk := sin(gait_time) if walking else 0.0
	var busy := not walking and state in ["coding", "building", "fixing", "testing"]
	var hit := maxf(0.0, sin(action_time * TAU * 1.6)) if busy and state == "building" else 0.0
	var bob := absf(walk) * -3.0 + hit * 2.0
	# Grounded shadow, two independently stepping boots, torso, articulated arms and helmet.
	draw_set_transform(Vector2(0, 2), 0, Vector2(1, 0.28))
	draw_circle(Vector2.ZERO, 25, Color(0.02, 0.06, 0.10, 0.32))
	draw_set_transform(Vector2(0, bob))
	var left_boot := Vector2(-10 + walk * 5, walk * 3)
	var right_boot := Vector2(10 - walk * 5, -walk * 3)
	draw_line(Vector2(-8, -23), left_boot - Vector2(0, 4), Color("#236b79"), 9)
	draw_line(Vector2(8, -23), right_boot - Vector2(0, 4), Color("#2b8790"), 9)
	draw_rect(Rect2(left_boot - Vector2(8, 6), Vector2(16, 8)), Color("#273246"))
	draw_rect(Rect2(right_boot - Vector2(8, 6), Vector2(16, 8)), Color("#35465b"))
	draw_colored_polygon(PackedVector2Array([Vector2(-16,-52),Vector2(14,-52),Vector2(18,-22),Vector2(-17,-22)]), Color("#197f8c"))
	draw_rect(Rect2(-13,-48,6,20), accent)
	draw_rect(Rect2(6,-48,5,20), accent)
	draw_rect(Rect2(-18,-27,36,7), Color("#af692c"))
	draw_rect(Rect2(-4,-27,9,7), Color("#e0c891"))
	var hand := Vector2(_face * (25.0 + hit * 4.0), -37.0 - hit * 18.0)
	if walking:
		hand.y += walk * 8.0
	elif state in ["saved", "done"]:
		hand = Vector2(_face * 19.0, lerpf(-39.0, -26.0, minf(1.0, action_time / 0.7)))
	elif state == "paused":
		hand = Vector2(_face * 21.0, -28)
	if typing:
		hand = right_hand
	draw_line(Vector2(_face * 13, -47), hand, Color("#259ba4"), 10)
	draw_circle(hand, 5.5, Color("#f0dfab"))
	var other := Vector2(-_face * 21, -30 - walk * 7)
	if typing:
		other = left_hand
	draw_line(Vector2(-_face * 13, -47), other, Color("#176d80"), 9)
	draw_circle(other, 5, Color("#d9c998"))
	# Reuse the original pixel engineer's face/helmet; limbs animate independently.
	if _portrait != null:
		draw_texture_rect_region(_portrait, Rect2(-31 + _face * 2, -98, 62, 58), Rect2(280, 8, 720, 680))
	else:
		draw_circle(Vector2(0, -67), 19, Color("#f0d4a0"))
		draw_rect(Rect2(-23, -91, 46, 19), Color("#ffc84b"))
		draw_rect(Rect2(-27, -75, 54, 7), Color("#ffc84b"))
	if not walking:
		_draw_tool(hand, busy)
	draw_set_transform(Vector2.ZERO)
	if not leaving:
		draw_string(_font, Vector2(-30, 19), title, HORIZONTAL_ALIGNMENT_CENTER, 60, 11, Color(0.84,0.94,0.96,0.88))

func _draw_tool(hand: Vector2, busy: bool) -> void:
	match state:
		"building":
			draw_line(hand, hand + Vector2(_face * 2, -17), Color("#a2693f"), 4)
			draw_rect(Rect2(hand + Vector2(-9, -22), Vector2(18, 8)), Color("#b5c6ce"))
		"testing":
			draw_rect(Rect2(hand - Vector2(7, 8), Vector2(14, 17)), Color("#102e3e"))
			draw_rect(Rect2(hand - Vector2(4, 5), Vector2(8, 9)), accent)
			var ray := Vector2(_face * 75, -29 + sin(action_time * 2.5) * 19)
			draw_line(hand, ray, Color(accent, 0.45), 2)
			draw_arc(ray, 12, -1.3, 1.3, 16, Color(accent, 0.65), 2)
		"thinking":
			draw_rect(Rect2(-24, -36, 30, 21), Color("#c9e4d8"))
			draw_line(Vector2(-20,-30), Vector2(1,-30), Color("#35768a"), 2)
			draw_line(Vector2(-20,-25), Vector2(-7,-25), Color("#35768a"), 2)
		"saved", "done":
			if action_time < 0.8:
				draw_line(hand, hand + Vector2(_face * 9, 0), Color("#bacbd3"), 4)
			if state == "saved" and action_time < 1.2:
				draw_polyline(PackedVector2Array([Vector2(-6,-110),Vector2(-1,-105),Vector2(9,-116)]), Color("#8fe1a4"), 3)

func _draw_bubble() -> void:
	if bubble.is_empty():
		return
	var width := clampf(_font.get_string_size(bubble, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 18, 40, 178)
	var x := clampf(-width * 0.5, 8.0 - position.x, viewport_size.x - position.x - width - 8.0)
	var rect := Rect2(x, -134, width, 25)
	draw_style_box(_bubble_style(), rect)
	draw_colored_polygon(PackedVector2Array([Vector2(-4,-109),Vector2(0,-103),Vector2(5,-109)]), Color("#f3e9cb"))
	draw_string(_font, Vector2(x + 9,-116), bubble, HORIZONTAL_ALIGNMENT_LEFT, width - 16, 13, Color("#244353"))

func _bubble_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#f3e9cb")
	style.set_corner_radius_all(6)
	return style

static func _short_status(value: String) -> String:
	return {"thinking":"看看设计", "coding":"编写逻辑", "building":"搭建中", "testing":"观察试玩", "fixing":"修正逻辑", "saved":"已保存", "done":"收工", "paused":"暂停"}.get(value, "")

static func _safe_module(value: Variant) -> String:
	var text := str(value).strip_edges().replace("\n", " ")
	if text.contains("{") or text.contains("func ") or text.contains("res://"):
		return ""
	return text.left(12)
