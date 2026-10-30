extends Node2D
## Physical module desks are views of accepted plans and work facts, not game-rule simulations.
signal module_focused(event: Dictionary)

const ACTOR = preload("res://addons/ugc/crew_actor.gd")
const STATES := ["planned", "writing", "saved", "checking", "verified", "failed", "paused"]
const KINDS := ["deck", "score", "shop", "rules", "world", "generic"]
const LABELS := {"planned":"规划", "writing":"编写中", "saved":"已保存 · 待验收", "checking":"检查中", "verified":"本轮验收通过", "failed":"需要修复", "paused":"已暂停"}
const ACTIVE := ["thinking", "coding", "building", "testing", "fixing"]
const STOPPED := ["paused", "cancelled", "interrupted", "partial", "failed", "review", "ready", "completed"]
const INK := Color("10242d")
const PAPER := Color("edf4e9")
const MIST := Color("a8c0bc")
var modules: Dictionary = {}
var order: Array[String] = []
var actors: Dictionary = {}
var station_rects: Dictionary = {}
var selected_file := ""
var page := 0
var phase := "scope"
var title := "模块工坊"
var size := Vector2(1280, 720)
var elapsed := 0.0
var transition_count := 0
var _font: Font
var _hover := ""
var _detail_rect := Rect2()
var _previous_rect := Rect2()
var _next_rect := Rect2()
var _actor_data: Dictionary = {}
var _last_layout := Vector2.ZERO

func _ready() -> void:
	_font = load("res://addons/ugc/font.ttf")
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	layout(get_viewport_rect().size)

static func normalize_file(value: Variant) -> String:
	return str(value).strip_edges().replace("\\", "/").trim_prefix("res://")

static func _text(value: Variant, maximum := 80) -> String:
	return str(value).replace("\n", " ").replace("\r", " ").strip_edges().left(maximum)

func set_plan(plan: Dictionary) -> void:
	title = _text(plan.get("title", "模块工坊"), 36)
	if not plan.get("modules") is Array:
		return
	var next_order: Array[String] = []
	for source in plan.modules.slice(0, 32):
		if not source is Dictionary:
			continue
		var file := normalize_file(source.get("file", ""))
		if file.is_empty() or next_order.has(file):
			continue
		next_order.append(file)
		var kind := str(source.get("kind", "generic"))
		var row: Dictionary = modules.get(file, {"file":file, "id":file, "state":"planned", "detail":"尚在规划，未表示实现", "sourceRevision":"", "evidenceRefs":[]})
		row.label = _text(source.get("role", file.get_file().get_basename()), 36)
		row.kind = kind if kind in KINDS else "generic"
		row.interface = _text(source.get("interface", ""), 160)
		row.owner = _text(source.get("owner", ""), 24)
		modules[file] = row
	for file in modules.keys():
		if not next_order.has(file):
			modules.erase(file)
	order = next_order
	if not modules.has(selected_file):
		selected_file = ""
	page = clampi(page, 0, maxi(0, ceili(order.size() / 4.0) - 1))
	layout(size)
	queue_redraw()

func apply_workshop(message: Dictionary) -> void:
	if message.get("plan") is Dictionary:
		set_plan(message.plan)
	phase = str(message.get("phase", phase))
	if message.get("modules") is Array:
		for source in message.modules.slice(0, 32):
			if not source is Dictionary:
				continue
			var file := normalize_file(source.get("file", source.get("id", "")))
			if not modules.has(file):
				continue
			var state := str(source.get("state", "planned"))
			if state not in STATES:
				state = "planned"
			var row: Dictionary = modules[file]
			if row.state != state:
				transition_count += 1
			row.state = state
			row.label = _text(source.get("label", row.label), 36)
			row.detail = _text(source.get("detail", ""), 180)
			row.sourceRevision = _text(source.get("sourceRevision", ""), 80)
			row.evidenceRefs = source.get("evidenceRefs", []).duplicate() if source.get("evidenceRefs") is Array else []
			var kind := str(source.get("kind", row.kind))
			row.kind = kind if kind in KINDS else "generic"
	if message.get("actors") is Array:
		var present := {}
		for actor in message.actors.slice(0, 4):
			if actor is Dictionary:
				present[str(actor.get("agent", ""))] = true
				set_actor(actor)
		for id in actors.keys():
			if not present.has(id):
				set_actor({"agent":id, "state":"gone"})
	if phase in STOPPED:
		stop_workers()
	queue_redraw()

func set_actor(source: Dictionary) -> void:
	var id := str(source.get("agent", "")).left(96)
	if id.is_empty():
		return
	var data: Dictionary = _actor_data.get(id, {}).duplicate(true)
	data.merge(source, true)
	if phase in STOPPED and str(data.get("state", "paused")) in ACTIVE:
		data.state = "paused"
	_actor_data[id] = data
	if str(data.get("state", "paused")) in ["gone", "done"]:
		if actors.has(id):
			actors[id].queue_free()
			actors.erase(id)
		_actor_data.erase(id)
		return
	if not actors.has(id):
		if actors.size() >= 4:
			return
		var actor = ACTOR.new()
		add_child(actor)
		actors[id] = actor
		actor.setup(id, data, size, true)
	else:
		actors[id].set_work(data)
	_position_actor(id)
	queue_redraw()

func _position_actor(id: String) -> void:
	var actor = actors[id]
	var data: Dictionary = _actor_data[id]
	var file := normalize_file(data.get("file", ""))
	var at_entrance := id == "M" and not station_rects.has(file)
	var was_elsewhere := bool(actor.get_meta("module_elsewhere", false))
	var elsewhere := at_entrance and not file.is_empty()
	actor.set_meta("module_elsewhere", elsewhere)
	actor.visible = station_rects.has(file) or file.is_empty() or at_entrance
	actor.scale = Vector2.ONE * (0.62 if size.x < 900 else 0.92)
	var feet := Vector2(48, size.y - 92)
	var work := feet + Vector2(42, -48)
	if station_rects.has(file):
		var rect: Rect2 = station_rects[file]
		var same: Array = actors.keys().filter(func(key):return normalize_file(_actor_data.get(key, {}).get("file", "")) == file)
		var slot := same.find(id)
		feet = Vector2(rect.end.x - (32 if slot % 2 == 0 else 102), rect.end.y + (14 if size.x < 900 else 24))
		work = feet + Vector2(-42, -48)
	# Location is presentation only: retain the real file, phase and chosen page.
	if elsewhere:
		var module_label := _actor_module_label(data, file)
		actor.bubble = module_label.left(8) + "·另一页·" + ACTOR._short_status(actor.state) if order.has(file) else module_label.left(8) + "·入口·" + ACTOR._short_status(actor.state)
	elif was_elsewhere:
		actor.bubble = actor.module_name + "·" + ACTOR._short_status(actor.state)
	# Reuse the original actor's path and typing, but target this actual module's desk.
	actor.viewport_size = size
	actor.work_point = work
	actor.target_normalized = work / size
	actor.explicit_target = true
	if actor.state in ACTIVE:
		actor.destination = feet
		actor.walking = actor.position.distance_to(feet) > 3.0
		actor._face = -1.0
	elif actor.state in ["paused", "saved"] and not station_rects.has(file):
		actor.position = feet
		actor.destination = feet

func _actor_module_label(data: Dictionary, file: String) -> String:
	var label := _text(data.get("module", ""), 28)
	if label.is_empty():
		label = str(modules.get(file, {}).get("label", file.get_file().get_basename()))
	return label

func main_work_label() -> String:
	if not actors.has("M"):
		return ""
	var data: Dictionary = _actor_data["M"]
	var file := normalize_file(data.get("file", ""))
	if file.is_empty() or station_rects.has(file):
		return ""
	var location := "第 %d 页（另一页）" % [order.find(file) / 4 + 1] if order.has(file) else "入口工作位"
	return _actor_module_label(data, file) + " · " + location + " · " + ACTOR._short_status(actors.M.state)

func stop_workers() -> void:
	for id in actors:
		actors[id].set_work({"state":"paused"})
		_actor_data[id].state = "paused"

func clear_workers() -> void:
	for actor in actors.values():
		actor.queue_free()
	actors.clear()
	_actor_data.clear()

func layout(view_size: Vector2) -> void:
	size = view_size
	_last_layout = size
	station_rects.clear()
	var compact := size.x < 900
	var margin := 22.0 if compact else 64.0
	var top := 66.0 if compact else 122.0
	var gap := Vector2(22, 36) if compact else Vector2(52, 66)
	var bottom := 90.0 if compact else 152.0
	var row_height := maxf(88, (size.y - top - bottom - gap.y) * 0.5)
	var cell := Vector2((size.x - margin * 2 - gap.x) * 0.5, row_height)
	for i in range(page * 4, mini(order.size(), page * 4 + 4)):
		var slot := i % 4
		station_rects[order[i]] = Rect2(Vector2(margin + (slot % 2) * (cell.x + gap.x), top + (slot / 2) * (cell.y + gap.y)), cell)
	_detail_rect = Rect2(margin, size.y - (64 if compact else 102), size.x - margin * 2, 42 if compact else 72)
	_previous_rect = Rect2(size.x - margin - 88, 16 if compact else 38, 36, 30)
	_next_rect = Rect2(size.x - margin - 36, 16 if compact else 38, 36, 30)
	for id in actors:
		_position_actor(id)
	queue_redraw()

func focus_module(file: String) -> void:
	file = normalize_file(file)
	if not UGC.show_crew or not modules.has(file):
		return
	selected_file = file
	page = order.find(file) / 4
	layout(size)
	var event := {"type":"module_focus", "file":file, "label":str(modules[file].label)}
	module_focused.emit(event)
	UGC.emit(event)

func change_page(direction: int) -> void:
	page = clampi(page + direction, 0, maxi(0, ceili(order.size() / 4.0) - 1))
	layout(size)

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not UGC.show_crew:
		return
	if event is InputEventMouseMotion:
		_hover = ""
		for file in station_rects:
			if station_rects[file].has_point(event.position):
				_hover = file
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for file in station_rects:
			if station_rects[file].has_point(event.position):
				focus_module(file)
				get_viewport().set_input_as_handled()
				return
		if order.size() > 4 and (_previous_rect.has_point(event.position) or _next_rect.has_point(event.position)):
			change_page(-1 if _previous_rect.has_point(event.position) else 1)
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not UGC.show_crew:
		visible = false
		stop_workers()
		return
	if _last_layout != get_viewport_rect().size:
		layout(get_viewport_rect().size)
	if phase not in STOPPED and modules.values().any(func(row):return row.state in ["writing", "checking"]):
		elapsed += minf(delta, 0.1)
		queue_redraw()

func _color(state: String) -> Color:
	return {"planned":Color("8ea9c7"), "writing":Color("f3c77b"), "saved":Color("81c4dc"), "checking":Color("bcaae7"), "verified":Color("87dab8"), "failed":Color("f19a89"), "paused":Color("acb8b5")}.get(state, Color.WHITE)

func display_state(row: Dictionary) -> String:
	var state := str(row.state)
	return "paused" if phase in STOPPED and state in ["writing", "checking"] else state

func _label(text: String, at: Vector2, px: int, color: Color, width := -1.0) -> void:
	if _font == null:
		return
	var value := text
	if width > 0:
		while value.length() > 1 and _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width:
			value = value.left(value.length() - 2) + "…"
	draw_string(_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)

func _box(rect: Rect2, color: Color, radius := 10.0, border := Color.TRANSPARENT, thickness := 1) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(radius))
	style.border_color = border
	style.set_border_width_all(thickness)
	draw_style_box(style, rect)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), INK)
	var compact := size.x < 900
	var margin := 22.0 if compact else 64.0
	for n in 18:
		draw_line(Vector2(n * size.x / 17, size.y * 0.22), Vector2(size.x * 0.5 + (n * size.x / 17 - size.x * 0.5) * 1.6, size.y), Color("1b3740"), 1)
	for n in 7:
		var y := size.y * 0.22 + n * size.y * 0.13
		draw_line(Vector2(0, y), Vector2(size.x, y), Color("1b3740"), 1)
	_label(title, Vector2(margin, 36 if compact else 56), 24 if compact else 34, PAPER, size.x - margin * 2 - 120)
	_label("模块工坊 · 桌上的造型是制作示意", Vector2(margin, 55 if compact else 85), 13 if compact else 19, MIST)
	if order.size() > 4:
		_box(_previous_rect, Color("294952"), 7)
		_box(_next_rect, Color("294952"), 7)
		_label("<", _previous_rect.position + Vector2(12, 24), 25, PAPER)
		_label(">", _next_rect.position + Vector2(12, 24), 25, PAPER)
		_label("%d/%d" % [page + 1, ceili(order.size() / 4.0)], Vector2(_previous_rect.position.x + 28, _previous_rect.end.y + 17), 12 if compact else 16, MIST)
	for file in station_rects:
		_draw_station(station_rects[file], modules[file], file == selected_file, file == _hover)
	_box(_detail_rect, Color("1a343e"), 10)
	if modules.has(selected_file):
		var row: Dictionary = modules[selected_file]
		var state := display_state(row)
		var text := str(row.detail)
		if text.is_empty():
			text = str(row.get("interface", "")) if row.state == "planned" else "点击模块可与游戏助手继续完善"
		_label(str(row.label) + " · " + str(LABELS[state]), _detail_rect.position + Vector2(14, 18 if compact else 25), 14 if compact else 21, _color(state), _detail_rect.size.x - 28)
		_label(text, _detail_rect.position + Vector2(14, 35 if compact else 53), 12 if compact else 17, MIST, _detail_rect.size.x - 28)
	else:
		var main_label := main_work_label()
		if not main_label.is_empty():
			_label(main_label, _detail_rect.position + Vector2(14, 18 if compact else 25), 14 if compact else 21, PAPER, _detail_rect.size.x - 28)
			_label("主制作留在入口，翻页查看由你决定", _detail_rect.position + Vector2(14, 35 if compact else 53), 12 if compact else 17, MIST, _detail_rect.size.x - 28)
		else:
			_label("点击工作台，查看真实模块与当前进展", _detail_rect.position + Vector2(16, 27 if compact else 43), 16 if compact else 23, PAPER, _detail_rect.size.x - 32)

func _draw_station(rect: Rect2, row: Dictionary, selected: bool, hovered: bool) -> void:
	var compact := size.x < 900
	var state := display_state(row)
	var color := _color(state)
	var foot := rect.end.y + (14 if compact else 24)
	_ellipse(rect.get_center() + Vector2(0, rect.size.y * 0.5 + 15), Vector2(rect.size.x * 0.46, 13), Color(0, 0, 0, 0.2))
	for x in [rect.position.x + 20, rect.end.x - 20]:
		draw_rect(Rect2(x - 4, rect.end.y - 5, 8, foot - rect.end.y + 14), Color("38545a"))
	_box(rect.grow_individual(0, 0, 0, 9), Color("29454e"), 12)
	_box(rect, Color("29454d") if row.state == "planned" else Color("36565d"), 12, color if selected or hovered else Color("58777a"), 3 if selected else 1)
	draw_line(rect.position + Vector2(12, 2), Vector2(rect.end.x - 12, rect.position.y + 2), color, 3)
	var icon_scale := 0.60 if compact else 1.0
	var center := rect.position + Vector2(40 if compact else 73, rect.size.y * 0.48)
	_draw_icon(str(row.kind), center, icon_scale, color, str(row.state))
	var left := rect.position.x + (78 if compact else 142)
	var width := rect.end.x - left - 18
	_label(str(row.label), Vector2(left, rect.position.y + (27 if compact else 45)), 19 if compact else 28, PAPER, width)
	_label(str(LABELS[state]), Vector2(left, rect.position.y + (49 if compact else 77)), 14 if compact else 20, color, width)
	if not compact:
		_label(str(row.get("interface", "")), Vector2(left, rect.position.y + 107), 16, MIST, width)
	if row.state == "planned":
		_label("规划示意", Vector2(center.x - 25 * icon_scale, rect.end.y - 10), 11 if compact else 15, color)
	elif row.state in ["writing", "checking"] and phase not in STOPPED:
		var x := rect.position.x + 12 + fmod(elapsed * 70, rect.size.x - 24)
		draw_circle(Vector2(x, rect.end.y - 4), 2.5, color)

func _ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	draw_set_transform(center, 0, radius)
	draw_circle(Vector2.ZERO, 1, color)
	draw_set_transform(Vector2.ZERO)

func _draw_icon(kind: String, center: Vector2, amount: float, color: Color, state: String) -> void:
	draw_set_transform(center, 0, Vector2.ONE * amount)
	var paper := Color("d6e4d8") if state != "planned" else Color("8da8b6")
	match kind:
		"deck":
			for i in 3:
				_box(Rect2(-32 + i * 9, -33 - i * 5, 46, 64), Color("294b60"), 5, paper, 2)
			_box(Rect2(-8, -31, 43, 59), paper, 5)
			draw_colored_polygon(PackedVector2Array([Vector2(13,-18),Vector2(25,-2),Vector2(13,14),Vector2(1,-2)]), Color("9f5663"))
		"score":
			for i in 4:
				_box(Rect2(-35, 20 - i * 9, 37, 12), color.darkened(i * 0.07), 6, Color("ab8962"))
			_box(Rect2(8, -31, 40, 54), Color("193840"), 6, paper, 2)
			_label("×", Vector2(18, 6), 30, color)
		"shop":
			_box(Rect2(-39, -12, 78, 49), Color("795e4b"), 4)
			_box(Rect2(-45, -35, 90, 26), color, 3)
			for i in 5:
				draw_rect(Rect2(-45 + i * 18, -35, 9, 26), Color("d7e6d8"))
			for i in 3:
				_box(Rect2(-28 + i * 22, 0, 15, 20), Color("bcd6c6"), 3)
		"rules":
			for i in 3:
				_box(Rect2(-42 + i * 27, -28 + abs(i - 1) * 9, 31, 52), paper, 4, Color("597e81"))
				draw_circle(Vector2(-27 + i * 27, -7 + abs(i - 1) * 9), 6, color.darkened(0.3))
		"world":
			for y in 3:
				for x in 3:
					var at := Vector2((x-y)*18, (x+y)*9-20)
					draw_colored_polygon(PackedVector2Array([at+Vector2(0,-9),at+Vector2(18,0),at+Vector2(0,9),at+Vector2(-18,0)]), color.darkened((x+y)%2 * 0.2))
			draw_line(Vector2(0,-17),Vector2(0,-42),paper,3)
			draw_colored_polygon(PackedVector2Array([Vector2(1,-43),Vector2(20,-36),Vector2(1,-29)]),paper)
		_:
			_box(Rect2(-36,-24,72,52),Color("315b67"),9,paper,2)
			for i in 3:
				draw_circle(Vector2(-20+i*20,2),6,color)
	draw_set_transform(Vector2.ZERO)
