extends CanvasLayer
## Screen-facing combat feedback. Records keep a world point, never an enemy node.

const MAX_ITEMS := 50
const COLORS := {
	"normal":Color("fff4db"), "critical":Color("ffd16a"),
	"dot":Color("e0a2ff"), "frost":Color("98eaff"),
	"armor":Color("badcff")
}
const HUD_ZONES := [
	# Immersive HUD: room caption + boss bar, minimap, combo meter, vitals, skill cards.
	Rect2(440,24,560,166), Rect2(1180,20,260,212), Rect2(1140,420,300,170),
	Rect2(0,730,440,170), Rect2(1020,595,420,305), Rect2(420,700,540,60)
]

var reduced_motion := false
var _camera: Camera3D
var _canvas: Control
var _font: Font
var _frozen := false
var _serial := 0
var _rng := RandomNumberGenerator.new()
var _live: Array[Dictionary] = []


func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_setup()


func configure(camera: Camera3D) -> void:
	_camera = camera
	_setup()


func _setup() -> void:
	if not is_inside_tree() or is_instance_valid(_canvas): return
	_canvas = Control.new()
	_canvas.name = "CombatDamageNumbers"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.focus_mode = Control.FOCUS_NONE
	add_child(_canvas)
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = preload("res://scripts/quality.gd").font()


func popup(world_pos: Vector3, amount: float, critical: bool = false, kind: String = "normal") -> Label:
	if not is_inside_tree() or not is_instance_valid(_camera) or not _camera.is_inside_tree(): return null
	if not is_finite(amount) or amount <= 0 or not world_pos.is_finite(): return null
	if _camera.is_position_behind(world_pos): return null
	var screen := _camera.unproject_position(world_pos)
	var viewport_size := get_viewport().get_visible_rect().size
	if not Rect2(Vector2.ZERO,viewport_size).has_point(screen): return null
	_setup()
	var style := _style(kind,critical)
	var is_crit: bool = style == "critical"
	var font_size := 43 if is_crit else (26 if style in ["dot","frost"] else (29 if style == "armor" else 34))
	var text := str(roundi(amount)) if amount >= 10 or is_equal_approx(amount,roundf(amount)) else String.num(amount,1)
	if is_crit: text = "暴击 " + text
	var label := Label.new()
	label.name = "Damage_%d" % _serial
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.focus_mode = Control.FOCUS_NONE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font",_font)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",COLORS[style])
	label.add_theme_color_override("font_outline_color",Color(.008,.014,.022,.98))
	label.add_theme_constant_override("outline_size",9 if is_crit else 7)
	label.add_theme_color_override("font_shadow_color",Color(.005,.009,.015,.85))
	label.add_theme_constant_override("shadow_offset_x",2)
	label.add_theme_constant_override("shadow_offset_y",4)
	label.add_theme_constant_override("shadow_outline_size",4)
	_canvas.add_child(label)
	label.size = label.get_minimum_size()+Vector2(12,6)
	label.pivot_offset = label.size*.5
	var nearby := 0
	var widest := label.size.x
	for entry in _live:
		if float(entry.age) < .45 and Vector2(entry.projected).distance_to(screen) < 62:
			nearby += 1
			if is_instance_valid(entry.node): widest = maxf(widest,entry.node.size.x)
	var spacing := clampf(widest*.7,48,105)
	var lanes := [Vector2.ZERO,Vector2(-spacing,-34),Vector2(spacing,-16),Vector2(-spacing*.4,-69),Vector2(spacing*.65,-59)]
	var offset: Vector2 = lanes[nearby%5]+Vector2(_rng.randf_range(-5,5),-float(nearby/5)*26.0)
	var lifetime := 1.12 if is_crit else (.86 if style in ["dot","frost"] else .98)
	var entry := {"node":label,"world":world_pos,"projected":screen,"age":0.0,"duration":lifetime,"style":style,"offset":offset,"velocity":Vector2(_rng.randf_range(-15,15),-48 if is_crit else -37),"peak":1.34 if is_crit else 1.18}
	_serial += 1
	while _live.size() >= (24 if preload("res://scripts/quality.gd").low() else MAX_ITEMS): _remove(0)
	_live.append(entry)
	_pose(entry,viewport_size)
	return label


func _style(kind: String, critical: bool) -> String:
	if critical or kind.to_lower() in ["critical","crit"]: return "critical"
	match kind.to_lower():
		"dot","poison","burn","hangover","doom": return "dot"
		"frost","ice","chill": return "frost"
		"armor","shield": return "armor"
	return "normal"


func set_frozen(value: bool) -> void:
	_frozen = value


func active_count() -> int:
	return _live.size()


func clear_all() -> void:
	while not _live.is_empty(): _remove(_live.size()-1)


func _remove(index: int) -> void:
	var label: Label = _live[index].node
	if is_instance_valid(label):
		if label.get_parent() != null: label.get_parent().remove_child(label)
		label.queue_free()
	_live.remove_at(index)


func _process(delta: float) -> void:
	if _frozen or _live.is_empty(): return
	var viewport_size := get_viewport().get_visible_rect().size
	for i in range(_live.size()-1,-1,-1):
		var entry: Dictionary = _live[i]
		entry.age = float(entry.age)+maxf(0,delta)
		if float(entry.age) >= float(entry.duration):
			_remove(i)
			continue
		if not is_instance_valid(entry.node):
			_live.remove_at(i)
			continue
		var label: Label = entry.node
		if is_instance_valid(_camera) and _camera.is_inside_tree():
			label.visible = not _camera.is_position_behind(entry.world)
			if label.visible:
				entry.projected = _camera.unproject_position(entry.world)
				label.visible = Rect2(Vector2.ZERO,viewport_size).has_point(entry.projected)
		_pose(entry,viewport_size)


func _pose(entry: Dictionary, viewport_size: Vector2) -> void:
	var label: Label = entry.node
	var age: float = entry.age
	var scale_amount := 1.0
	if not reduced_motion:
		if age < .075: scale_amount = lerpf(.67,float(entry.peak),1.0-pow(1.0-age/.075,3))
		elif age < .20: scale_amount = lerpf(float(entry.peak),1.0,(age-.075)/.125)
	label.scale = Vector2.ONE*scale_amount
	var drift: Vector2 = Vector2(entry.velocity)*age*(.4 if reduced_motion else 1.0)
	var desired: Vector2 = Vector2(entry.projected)+(Vector2.ZERO if reduced_motion else Vector2(entry.offset))+drift
	var extents: Vector2 = (label.size*float(entry.peak)+Vector2(20,20))*.5
	var center := _safe_center(desired,extents,viewport_size)
	label.position = center-label.size*.5
	var fade_start: float = float(entry.duration)*.61
	label.modulate.a = 1.0-clampf((age-fade_start)/maxf(.01,float(entry.duration)-fade_start),0,1)


func _safe_center(desired: Vector2, extents: Vector2, viewport_size: Vector2) -> Vector2:
	var margin := Vector2(12,12)
	var low := margin+extents
	var high := viewport_size-margin-extents
	var original := desired.clamp(low,high)
	var candidates: Array[Vector2] = [original,viewport_size*.5]
	var zones := _hud_zones(viewport_size)
	for zone in zones:
		candidates.append(Vector2(zone.position.x-extents.x-3,original.y).clamp(low,high))
		candidates.append(Vector2(zone.end.x+extents.x+3,original.y).clamp(low,high))
		candidates.append(Vector2(original.x,zone.position.y-extents.y-3).clamp(low,high))
		candidates.append(Vector2(original.x,zone.end.y+extents.y+3).clamp(low,high))
	var best := viewport_size*.5
	var distance := INF
	for candidate in candidates:
		var box := Rect2(candidate-extents,extents*2)
		var blocked := false
		for zone in zones:
			if box.intersects(zone): blocked = true; break
		if not blocked and candidate.distance_squared_to(desired) < distance:
			best = candidate
			distance = candidate.distance_squared_to(desired)
	return best


func _hud_zones(viewport_size: Vector2) -> Array[Rect2]:
	var zones: Array[Rect2] = []
	var factor := viewport_size/Vector2(1440,900)
	for zone in HUD_ZONES:
		zones.append(Rect2(zone.position*factor,zone.size*factor))
	return zones
