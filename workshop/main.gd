extends Node2D
## An actual Godot construction yard before a generated game exists.
## Props represent accepted plans and saved files, never invented game objects or completion.

const INK := Color("101b26")
const TEAL := Color("6de2c9")
const GOLD := Color("f0c477")
const MIST := Color("93b6bc")
const FLOOR := Color("213540")
const LOCATIONS := [Vector2(0.26, 0.58), Vector2(0.50, 0.48), Vector2(0.74, 0.58)]
const CONSTRUCTION_YARD = preload("res://addons/ugc/construction_yard.gd")
const CONSTRUCTION_EDITOR = preload("res://addons/ugc/construction_editor.gd")
const MODULE_WORKSHOP = preload("res://module_workshop.gd")
var construction_yard: Node3D
var construction_editor: Node3D
var module_workshop: Node2D
## The clickable module whiteboard is opt-in; 2D creation shows a blank stage until the first build.
var use_module_workshop := false
var _overview_camera := Transform3D.IDENTITY
var _work_camera := Transform3D.IDENTITY
var _has_overview := false
var _work_focus := 0.0
var _construction_message_id := 0
var plan: Dictionary = {}
var saved_files: Dictionary = {}
var actors: Array = []
var phase := "waiting"
var elapsed := 0.0
var pulse := 0.0
var plan_age := 0.0
var font: Font

func _ready() -> void:
	font = load("res://addons/ugc/font.ttf")
	set_meta("creation_yard", true)
	queue_redraw()

func set_plan(value: Dictionary) -> void:
	if str(value.get("title", "")) != str(plan.get("title", "")):
		plan_age = 0.0
	plan = value.duplicate(true)
	if use_module_workshop and not is_instance_valid(construction_yard) and value.get("modules") is Array and not value.modules.is_empty():
		_ensure_module_workshop()
		module_workshop.set_plan(value)
	queue_redraw()

func _ensure_module_workshop() -> void:
	if is_instance_valid(module_workshop):
		return
	UGC.clear_crew()
	module_workshop = MODULE_WORKSHOP.new()
	module_workshop.name = "ModuleWorkshop"
	add_child(module_workshop)

func on_workshop(value: Dictionary) -> void:
	actors = value.get("actors", []) if value.get("actors", []) is Array else []
	phase = str(value.get("phase", phase))
	if value.get("savedFiles") is Array:
		for file in value.savedFiles:
			if file is String:
				mark_saved("", file)
	if value.get("plan") is Dictionary:
		set_plan(value.plan)
	if is_instance_valid(construction_yard):
		construction_yard.apply_workshop(value)
		_update_editor_busy()
	elif is_instance_valid(module_workshop):
		module_workshop.apply_workshop(value)
	for actor in actors:
		if actor is Dictionary and str(actor.get("state", "")) == "saved":
			mark_saved(str(actor.get("agent", "")), str(actor.get("file", "")))
	queue_redraw()

func set_dimension(dimension: String) -> void:
	if dimension != "3d" or is_instance_valid(construction_yard):
		return
	if is_instance_valid(module_workshop):
		remove_child(module_workshop)
		module_workshop.queue_free()
		module_workshop = null
	construction_yard = CONSTRUCTION_YARD.new()
	construction_yard.name = "ConstructionWorld"
	add_child(construction_yard)
	construction_editor = CONSTRUCTION_EDITOR.new()
	construction_yard.add_child(construction_editor)
	construction_editor.setup(construction_yard)
	construction_editor.frame_requested.connect(_restore_overview_camera)
	# Keep construction lighting independent of the generated game's platform revision.
	# The Web Compatibility renderer clipped pastel colors under the former FILMIC/high-energy rig.
	construction_yard.world_environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	construction_yard.world_environment.environment.ambient_light_energy = 0.25
	for child in construction_yard.get_children():
		if child is DirectionalLight3D:
			child.light_energy = 0.55
	UGC.clear_crew()
	queue_redraw()

func uses_world_crew() -> bool:
	return is_instance_valid(construction_yard) or is_instance_valid(module_workshop)

func on_crew(value: Dictionary) -> void:
	if is_instance_valid(construction_yard):
		construction_yard.set_actor(value)
		_update_editor_busy()
	elif is_instance_valid(module_workshop):
		module_workshop.set_actor(value)

func handle_editor(message: Dictionary) -> void:
	if not is_instance_valid(construction_editor):
		return
	if not UGC.show_crew and bool(message.get("enabled", false)):
		return
	construction_editor.handle(message)

func _update_editor_busy() -> void:
	if not is_instance_valid(construction_editor):
		return
	var active := false
	for actor in construction_yard.actors.values():
		if actor.requested_state in ["thinking", "coding", "building", "testing", "fixing"]:
			active = true
			break
	construction_editor.set_busy(active)

func _restore_overview_camera() -> void:
	if _has_overview:
		construction_yard.camera.transform = _overview_camera
		_work_focus = 0.0

func clear_world_crew() -> void:
	if is_instance_valid(construction_yard):
		construction_yard.clear_workers()
		_update_editor_busy()
	if is_instance_valid(module_workshop):
		module_workshop.clear_workers()

func apply_construction(message: Dictionary) -> Dictionary:
	set_dimension("3d")
	_construction_message_id += 1
	var message_id := _construction_message_id
	if message.get("snapshot") is Dictionary:
		construction_editor.before_snapshot(message.snapshot, bool(message.get("restore", false)))
	if _has_overview and not construction_editor.camera_owned:
		construction_yard.camera.transform = _overview_camera
	var result: Dictionary = await construction_yard.apply_construction(message)
	if message_id != _construction_message_id:
		return result
	# Camera input remains live throughout construction animation. Preserve the latest view,
	# rather than the view from before an awaited snapshot began.
	var manual_camera: Transform3D = construction_yard.camera.transform
	var keep_camera: bool = construction_editor.camera_owned
	if bool(result.get("loaded", false)):
		if keep_camera:
			if _has_overview:
				construction_yard.camera.transform = _overview_camera
			construction_yard.configure_camera(message.snapshot.get("camera", {}))
		_fit_construction_camera()
	construction_editor.after_snapshot(result)
	_update_editor_busy()
	if keep_camera:
		construction_yard.camera.transform = manual_camera
	queue_redraw()
	return result

func _fit_construction_camera() -> void:
	# Keep the committed view direction and look-at point; only move the yard camera backward.
	# All eight corners of every rotated object's real AABB must fit inside a padded frustum.
	var camera: Camera3D = construction_yard.camera
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(1.0, viewport_size.y)
	var vertical_tan := tan(deg_to_rad(camera.fov) * 0.5)
	var horizontal_tan := vertical_tan * aspect
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		horizontal_tan = vertical_tan
		vertical_tan /= aspect
	var inverse := camera.global_transform.affine_inverse()
	var pull_back := 0.0
	for row in construction_yard.level.snapshot.get("objects", []):
		var bounds: AABB = construction_yard.level.object_aabb(row)
		for corner in 8:
			var point: Vector3 = inverse * bounds.get_endpoint(corner)
			pull_back = maxf(pull_back, absf(point.y) / (vertical_tan * 0.84) + point.z)
			pull_back = maxf(pull_back, absf(point.x) / (horizontal_tan * 0.9) + point.z)
	if pull_back > 0.0:
		camera.position += camera.basis.z * (pull_back + 0.05)
	_overview_camera = camera.transform
	_work_camera = _overview_camera
	_has_overview = true
	_work_focus = 0.0

func _update_work_camera(delta: float) -> void:
	if not _has_overview or not is_instance_valid(construction_yard):
		return
	if is_instance_valid(construction_editor) and construction_editor.camera_owned:
		return
	var worker: Node3D = null
	for actor in construction_yard.actors.values():
		if actor.state in ["coding", "fixing"] and not actor.walking and actor.desk_open > 0.7:
			worker = actor
			if actor.actor_id == "M":
				break
	if worker != null:
		# A temporary world-space close view, not an overlay. Preserve the overview's direction.
		var target: Vector3 = worker.position + Vector3.UP * 0.95 + worker.basis.z * 0.55
		_work_camera = Transform3D(_overview_camera.basis, target + _overview_camera.basis.z * 12.5)
	_work_focus = move_toward(_work_focus, 1.0 if worker != null else 0.0, delta * 1.6)
	construction_yard.camera.transform = _overview_camera.interpolate_with(_work_camera, _work_focus)

func mark_saved(_agent: String, file: String) -> void:
	if file == "" or saved_files.has(file):
		return
	saved_files[file] = true
	pulse = 1.0
	queue_redraw()

func _process(dt: float) -> void:
	elapsed += minf(dt, 0.05)
	plan_age += dt
	pulse = maxf(0.0, pulse - dt)
	_update_work_camera(dt)
	queue_redraw()

func _label(text: String, at: Vector2, size: int, color: Color, centered := false) -> void:
	if font == null:
		return
	var pos := at
	if centered:
		pos.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _line(a: Vector2, b: Vector2, color: Color, width := 1.0) -> void:
	draw_line(a, b, color, width, true)

func _iso_box(p: Vector2, size: Vector2, height: float, color: Color) -> void:
	var a := p + Vector2(-size.x * 0.5, -size.y * 0.5)
	var b := p + Vector2(size.x * 0.5, -size.y * 0.5)
	var c := p + Vector2(size.x * 0.5, size.y * 0.5)
	var d := p + Vector2(-size.x * 0.5, size.y * 0.5)
	var rise := Vector2(0, -height)
	draw_colored_polygon(PackedVector2Array([d, c, c + rise, d + rise]), color.darkened(0.35))
	draw_colored_polygon(PackedVector2Array([b, c, c + rise, b + rise]), color.darkened(0.17))
	draw_colored_polygon(PackedVector2Array([a + rise, b + rise, c + rise, d + rise]), color)
	_line(a + rise, b + rise, color.lightened(0.15), 2.0)
	_line(a + rise, d + rise, color.lightened(0.12), 2.0)

func _bench(p: Vector2, index: int) -> void:
	var col := [TEAL, GOLD, Color("b4a0ed")][index] as Color
	# Leg shadows and feet establish a floor, not floating status cards.
	draw_set_transform(p + Vector2(0, 20), 0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, 105, Color(0.02, 0.06, 0.08, 0.5))
	draw_set_transform(Vector2.ZERO)
	for dx in [-76.0, 76.0]:
		draw_rect(Rect2(p + Vector2(dx - 6, -30), Vector2(12, 64)), Color("132531"))
		_line(p + Vector2(dx - 7, 34), p + Vector2(dx + 8, 34), Color("4c6973"), 3.0)
	_iso_box(p, Vector2(194, 72), 38, Color("47616a"))
	_line(p + Vector2(-92, 0), p + Vector2(92, 0), col.darkened(0.35), 3)
	if index == 0:
		# An accepted design appears as a drafting sheet, not finished level geometry.
		draw_rect(Rect2(p + Vector2(-69, -64), Vector2(132, 44)), Color("8cb7b1"))
		if not plan.is_empty():
			for i in 4:
				_line(p + Vector2(-58 + i * 30, -59), p + Vector2(-58 + i * 30, -26), Color("4f8585"))
			for i in 3:
				_line(p + Vector2(-61, -55 + i * 12), p + Vector2(51, -55 + i * 12), Color("4f8585"))
			draw_rect(Rect2(p + Vector2(-25, -55), Vector2(51, 21)), Color("2c6269"), false, 2)
			_line(p + Vector2(-16, -43), p + Vector2(17, -43), TEAL, 3)
		draw_circle(p + Vector2(74, -45), 10, GOLD)
	elif index == 1:
		_iso_box(p + Vector2(-15, -30), Vector2(55, 32), 26, Color("37606b"))
		for i in 3:
			draw_circle(p + Vector2(-28 + i * 13, -60), 3, TEAL if saved_files.size() > i else Color("203843"))
		_line(p + Vector2(34, -43), p + Vector2(69, -38), GOLD, 6)
		draw_rect(Rect2(p + Vector2(60, -50), Vector2(24, 14)), Color("91a8ae"))
	else:
		draw_rect(Rect2(p + Vector2(-16, -72), Vector2(16, 38)), Color("2b414d"))
		draw_rect(Rect2(p + Vector2(-61, -119), Vector2(120, 73)), Color("142732"))
		draw_rect(Rect2(p + Vector2(-54, -112), Vector2(106, 59)), Color("274d55"))
		var wave := PackedVector2Array()
		for i in 25:
			wave.append(p + Vector2(-48 + i * 4, -82 + sin(i * 0.6) * 10))
		draw_polyline(wave, col.darkened(0.15), 2, true)
		draw_circle(p + Vector2(38, -58), 2.5, col)
	_label(["设计台", "装配台", "检查台"][index], p + Vector2(0, 65), 17, MIST, true)

func _draw() -> void:
	var size := get_viewport_rect().size
	if is_instance_valid(module_workshop):
		return
	if is_instance_valid(construction_yard):
		_label(str(plan.get("title", "三维关卡施工现场")).left(32), Vector2(size.x * 0.5, 40), 24, Color("e3f5ee"), true)
		var count: int = construction_yard.level.objects.size()
		var note := "等待提交场景物体" if count == 0 else "%d 个已保存物体 · 与游戏共用关卡" % count
		draw_rect(Rect2(0, size.y - 66, size.x, 66), Color(0.04, 0.09, 0.13, 0.82))
		_label(note, Vector2(size.x * 0.5, size.y - 42), 15, MIST, true)
		var edit_hint := "左键选中/拖动 · 方向键/PgUp/PgDn微调 · Esc取消"
		if not construction_editor.can_move():
			edit_hint = "左键选中 · 当前仅观察镜头"
		var hint := edit_hint + " · 右键环绕 · 中键或Shift+右键平移 · 滚轮缩放 · Home全景"
		_label(hint, Vector2(size.x * 0.5, size.y - 18), 13, Color("dfede7"), true)
		return
	_draw_stage(size)

## Before the first build a blank game screen stands in; the real game replaces it as soon as a
## pack exists. Nothing drawn here pretends to be game content or progress.
func _draw_stage(size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), INK)
	var screen := Rect2(size * Vector2(0.1, 0.17), size * Vector2(0.8, 0.66))
	draw_rect(screen, Color("16283a"))
	var step := 32.0
	var x := screen.position.x + step
	while x < screen.end.x:
		_line(Vector2(x, screen.position.y), Vector2(x, screen.end.y), Color(0.43, 0.88, 0.79, 0.07))
		x += step
	var y := screen.position.y + step
	while y < screen.end.y:
		_line(Vector2(screen.position.x, y), Vector2(screen.end.x, y), Color(0.43, 0.88, 0.79, 0.07))
		y += step
	var corner := 26.0
	for c in [screen.position, Vector2(screen.end.x, screen.position.y), screen.end, Vector2(screen.position.x, screen.end.y)]:
		var sx := 1.0 if c.x < size.x * 0.5 else -1.0
		var sy := 1.0 if c.y < size.y * 0.5 else -1.0
		_line(c, c + Vector2(corner * sx, 0), TEAL, 3)
		_line(c, c + Vector2(0, corner * sy), TEAL, 3)
	# Ambient dust in the empty screen; it brightens briefly when a real file is saved.
	for i in 18:
		var t := elapsed * (0.05 + (i % 5) * 0.012) + i * 0.37
		var p := screen.position + Vector2(fposmod(sin(i * 12.9898) * 43758.5453, 1.0) * screen.size.x, fposmod(t, 1.0) * screen.size.y)
		draw_circle(p, 1.6 + (i % 3), Color(1.0, 0.93, 0.66, 0.12 + 0.25 * pulse))
	var title := str(plan.get("title", "新游戏")).left(32)
	_label(title, Vector2(size.x * 0.5, size.y * 0.11), 28, Color("e3f5ee"), true)
	var note := "小精灵会把第一版画面直接搭在这里"
	if phase == "scope":
		note = "小精灵正在规划第一版画面"
	if phase in ["build", "verify"]:
		note = "第一版正在制作，生成后会直接出现在这块屏幕上"
	if phase in ["paused", "cancelled", "interrupted", "partial", "failed"]:
		note = "工作已暂停，成果保留"
	_label(note, screen.get_center() + Vector2(0, 8), 18, MIST, true)
	if not saved_files.is_empty():
		_label("已保存 %d 份内容" % saved_files.size(), Vector2(size.x * 0.5, screen.end.y + 34), 15, MIST, true)
