extends Node3D
## Generated, collision-consistent voxel environments and reusable character art.

const CYAN := Color("58e4ec")
const ORANGE := Color("ff7445")
const STEEL := Color("263741")
const DARK := Color("101d27")
const PALE := Color("d9e4df")
const METAL_SHADER = preload("res://assets/world_metal.gdshader")
const FLOOR_SHADER = preload("res://assets/world_floor.gdshader")
const Scenery = preload("res://scripts/scenery.gd")
const DungeonLayout = preload("res://scripts/dungeon_layout.gd")
const DesertWorld = preload("res://scripts/desert_world.gd")
var _height_links: Array = []

var _materials: Dictionary = {}
var _boxes: Dictionary = {}
var _solids: Array[Rect2] = []
var _static_visual_grid: Dictionary = {}
var _static_rest: Dictionary = {}
var _static_tweens: Dictionary = {}
var _bounds := Rect2(-24.0, -28.0, 48.0, 52.0)
var _room: Node3D
var _art_clock := 0.0
var _freeze_amount := 0.0
var _floor_material: ShaderMaterial
var _animated_materials: Array[ShaderMaterial] = []
var _pulse_age := 10.0
var _pulse_center := Vector3.ZERO
var _pulse_strength := 0.0
var _pulse_radius := 5.8
var _pulse_travel := .62
var _pulse_prism := 0.0
var _dungeon := false
var _walkable: Array[Rect2] = []
var _dungeon_rooms: Array = []
## Per-floor art direction. main.gd applies sky/light/fog values; the world
## consumes floor, wall and accent colors while generating geometry.
const THEMES := [
	{"id":"cold","name":"冷钢车间","floor":Color("505963"),"floor_accent":Color("49bfff"),"room_tint":Color("343c42"),"corridor_tint":Color("303a42"),"wall":Color("465669"),"trim":Color("76808b"),"accent":Color("53caff"),"background":Color("3b4553"),"ambient":Color("99b8d0"),"ambient_energy":.26,"key":Color("ecf0f5"),"key_energy":.80,"fill":Color("517cb2"),"fill_energy":.22,"fog":Color("586575"),"fog_density":.0025,"flashlight":false},
	{"id":"desert","name":"远古遗迹 · 沙漠","floor":Color("ac966f"),"floor_accent":Color("9c8259"),"room_tint":Color("ac966f"),"corridor_tint":Color("9d8865"),"wall":Color("887457"),"trim":Color("c1a87e"),"accent":Color("d9b87a"),"background":Color("626365"),"ambient":Color("b6b0a5"),"ambient_energy":.30,"key":Color("ffe1ae"),"key_energy":.95,"fill":Color("8392a2"),"fill_energy":.18,"fog":Color("9c9384"),"fog_density":.002,"flashlight":false},
	{"id":"dark","name":"断电暗区","floor":Color("2c3836"),"floor_accent":Color("3fae8f"),"room_tint":Color("2f3a38"),"corridor_tint":Color("2a3332"),"wall":Color("222c2c"),"trim":Color("4e605c"),"accent":Color("6dffc4"),"background":Color("020506"),"ambient":Color("7da8b4"),"ambient_energy":.2,"key":Color("8fb3c0"),"key_energy":.26,"fill":Color("2f5466"),"fill_energy":.14,"fog":Color("030809"),"fog_density":.003,"flashlight":true},
	{"id":"neon","name":"霓虹紫域","floor":Color("322c42"),"floor_accent":Color("9d63ff"),"room_tint":Color("342d44"),"corridor_tint":Color("2e283e"),"wall":Color("2b2442"),"trim":Color("6c5e8c"),"accent":Color("d07bff"),"background":Color("0c0718"),"ambient":Color("b7a2ff"),"ambient_energy":.27,"key":Color("dccbff"),"key_energy":.62,"fill":Color("ff4fa8"),"fill_energy":.26,"fog":Color("1a0b2e"),"fog_density":.002,"flashlight":false},
	{"id":"frost","name":"寒霜冷库","floor":Color("3d4b57"),"floor_accent":Color("8fe8ff"),"room_tint":Color("404e5a"),"corridor_tint":Color("39454f"),"wall":Color("2f3d4a"),"trim":Color("8aa0ad"),"accent":Color("a4f4ff"),"background":Color("0b1622"),"ambient":Color("c9e6ff"),"ambient_energy":.34,"key":Color("e8f6ff"),"key_energy":.78,"fill":Color("6aa2d8"),"fill_energy":.24,"fog":Color("16283a"),"fog_density":.002,"flashlight":false},
]
var theme: Dictionary = THEMES[0]
var _path_segments: Array = [Vector4.ZERO,Vector4.ZERO,Vector4.ZERO,Vector4.ZERO]
var _path_ages := [10.0,10.0,10.0,10.0]
var _path_slot := 0

static func theme_for(depth: int) -> Dictionary:
	return THEMES[(maxi(1,depth)-1)%THEMES.size()]

## Rush-path ripple: slabs along a dash route rise in a travelling wave behind
## the hero. Four alternating slots let consecutive dash steps overlap smoothly.
func pulse_path(from: Vector3, to: Vector3, strength: float = 1.0) -> void:
	if not from.is_finite() or not to.is_finite(): return
	_path_slot = (_path_slot+1)%4
	_path_segments[_path_slot] = Vector4(from.x,from.z,to.x,to.z)
	_path_ages[_path_slot] = 0.0
	if _floor_material != null:
		_floor_material.set_shader_parameter("path_strength",clampf(strength,0.0,1.5))
		_push_path()

func _push_path() -> void:
	if _floor_material == null: return
	for i in 4: _floor_material.set_shader_parameter("path_seg_%d" % i,_path_segments[i])
	_floor_material.set_shader_parameter("path_ages",Vector4(_path_ages[0],_path_ages[1],_path_ages[2],_path_ages[3]))
var _doors: Array[Dictionary] = []
var _door_solids: Array[Rect2] = []
var _room_markers: Dictionary = {}

func pulse_floor(center: Vector3, strength: float = 1.0, radius: float = 5.8) -> void:
	if not center.is_finite() or not is_finite(strength) or not is_finite(radius): return
	_set_pulse(center,clampf(strength,0.0,1.5),clampf(radius,2.0,10.0),.62,0.0)

## Room-wide prismatic ripple (blessing pickup). The crest travels at a constant
## speed over 'duration' seconds per 'radius', trailed by smaller echo rings.
func pulse_floor_wave(center: Vector3, strength: float = 1.2, radius: float = 22.0, duration: float = .9) -> void:
	if not center.is_finite() or not is_finite(strength) or not is_finite(radius) or not is_finite(duration): return
	_set_pulse(center,clampf(strength,0.0,1.5),clampf(radius,2.0,30.0),clampf(duration,.2,2.0),1.0)

func pulse_lifetime() -> float:
	return maxf(1.1,_pulse_travel*1.6+.1)

func _set_pulse(center: Vector3, strength: float, radius: float, travel: float, prism: float) -> void:
	_pulse_center = center
	_pulse_strength = strength
	_pulse_radius = radius
	_pulse_travel = travel
	_pulse_prism = prism
	_pulse_age = 0.0
	if _floor_material != null:
		_floor_material.set_shader_parameter("pulse_travel",_pulse_travel)
		_floor_material.set_shader_parameter("pulse_prism",_pulse_prism)
		_floor_material.set_shader_parameter("pulse_center",_pulse_center)
		_floor_material.set_shader_parameter("pulse_strength",_pulse_strength)
		_floor_material.set_shader_parameter("pulse_radius",_pulse_radius)
		_floor_material.set_shader_parameter("pulse_age",_pulse_age)

func set_time_frozen(amount: float) -> void:
	var next := clampf(amount,0.0,1.0)
	if is_equal_approx(_freeze_amount,next): return
	_freeze_amount = next
	for mat in _materials.values(): mat.set_shader_parameter("freeze_amount",_freeze_amount)
	if _floor_material != null: _floor_material.set_shader_parameter("freeze_amount",_freeze_amount)

func _process(delta: float) -> void:
	_art_clock += delta*(1.0-_freeze_amount)
	for mat in _animated_materials:
		mat.set_shader_parameter("art_clock",_art_clock)
	if _floor_material != null:
		_floor_material.set_shader_parameter("art_clock",_art_clock)
		if _pulse_age < pulse_lifetime():
			_pulse_age += delta
			_floor_material.set_shader_parameter("pulse_age",_pulse_age)
		var path_live := false
		for i in 4:
			if _path_ages[i] < 3.0:
				_path_ages[i] += delta; path_live = true
		if path_live: _push_path()


func build(mode: String) -> Dictionary:
	for tween in _static_tweens.values():
		if tween is Tween and tween.is_running(): tween.kill()
	_static_tweens.clear(); _static_rest.clear(); _static_visual_grid.clear()
	_pulse_age = 10.0
	_path_ages = [10.0,10.0,10.0,10.0]
	_floor_material = null
	_height_links.clear()
	theme = theme_for(int(mode.trim_prefix("dungeon_"))) if mode.begins_with("dungeon_") else THEMES[0]
	_dungeon = mode.begins_with("dungeon_")
	_walkable.clear(); _dungeon_rooms = []; _doors.clear(); _door_solids.clear(); _room_markers.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_solids.clear()
	_room = Node3D.new()
	_room.name = "GeneratedEnvironment"
	add_child(_room)
	if mode == "hub":
		var result := _build_hub()
		_add_scenery()
		_index_static_visuals()
		return result
	if _dungeon:
		var result := _build_dungeon(maxi(1,int(mode.trim_prefix("dungeon_"))))
		_add_scenery()
		_index_static_visuals()
		return result
	var stage := maxi(1,int(mode.trim_prefix("stage_"))) if mode.begins_with("stage_") else 1
	var result := _build_arena(stage)
	_add_scenery()
	_index_static_visuals()
	return result


func _add_scenery() -> void:
	if theme.id == "desert": return # Sandstone cliffs are built with the desert courts.
	var scenery := Scenery.new()
	_room.add_child(scenery)
	var surfaces: Array = _walkable if _dungeon else [_bounds]
	scenery.build(_bounds,surfaces,theme.accent,theme.get("fog",Color("98b9d6")))

func _material(color: Color, emission: float = 0.0, size: Vector3 = Vector3.ONE, hero: bool = false) -> ShaderMaterial:
	var key := "%s_%.2f_%s_%s" % [color.to_html(), emission,size,hero]
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = METAL_SHADER
	mat.set_shader_parameter("base_color",color)
	mat.set_shader_parameter("half_extent",size*.5)
	mat.set_shader_parameter("emission_strength",emission)
	mat.set_shader_parameter("hero_surface",1.0 if hero else 0.0)
	mat.set_shader_parameter("freeze_amount",_freeze_amount)
	mat.set_shader_parameter("edge_color",color.lightened(.18) if color.r>color.b*1.1 else Color("7498aa"))
	if emission > 0 or hero: _animated_materials.append(mat)
	_materials[key] = mat
	return mat


func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, emission: float = 0.0) -> MeshInstance3D:
	var key := "%s" % size
	var mesh: BoxMesh
	if _boxes.has(key):
		mesh = _boxes[key]
	else:
		mesh = BoxMesh.new()
		mesh.size = size
		_boxes[key] = mesh
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(color, emission, size)
	instance.position = pos
	if size.y < 0.08:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _floor(rect: Rect2, tint: Color) -> void:
	box(_room, Vector3(rect.get_center().x, -0.55, rect.get_center().y), Vector3(rect.size.x + 0.5, 0.8, rect.size.y + 0.5), DARK)
	# Layered slab fascia and suspended structural supports, all below walk height.
	for side in [-1.0,1.0]:
		var x: float = rect.get_center().x+side*rect.size.x*.5
		box(_room,Vector3(x,-1.25,rect.get_center().y),Vector3(.42,.65,rect.size.y),theme.wall)
		box(_room,Vector3(x,-.65,rect.get_center().y),Vector3(.46,.065,rect.size.y),theme.accent,1.5)
		for edge in [-1.0,1.0]:
			var z: float = rect.get_center().y+edge*(rect.size.y*.5-.75)
			box(_room,Vector3(x,-5.0,z),Vector3(.85,8.0,1.4),theme.wall)
			box(_room,Vector3(x,-1.0,z),Vector3(1.05,.6,1.65),theme.trim)
	var nx := maxi(1,ceili(rect.size.x / 2.0))
	var nz := maxi(1,ceili(rect.size.y / 2.0))
	var step := Vector2(rect.size.x/nx,rect.size.y/nz)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.instance_count = nx * nz
	var tile_key := "floor_%s" % step
	var tile: BoxMesh
	if _boxes.has(tile_key): tile = _boxes[tile_key]
	else:
		tile = BoxMesh.new(); tile.size = Vector3(step.x-.022,.22,step.y-.022)
		_boxes[tile_key] = tile
	multimesh.mesh = tile
	# Every room and corridor uses this same resource: the pulse/stop clock must
	# reach all floor draws, not just whichever room was generated last.
	if _floor_material == null:
		_floor_material = ShaderMaterial.new(); _floor_material.shader = FLOOR_SHADER
		_floor_material.set_shader_parameter("base_color",theme.get("floor",Color("344351")))
		_floor_material.set_shader_parameter("accent_color",theme.get("floor_accent",Color("437e8c")))
		_floor_material.set_shader_parameter("path_accent",theme.get("accent",CYAN))
		_floor_material.set_shader_parameter("freeze_amount",_freeze_amount)
	var mat := _floor_material
	var i := 0
	for x in nx:
		for z in nz:
			var pos := Vector3(rect.position.x + (x+.5)*step.x, -.12, rect.position.y + (z+.5)*step.y)
			multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
			var shade := 0.93 + float((x * 13 + z * 7) % 5) * 0.025
			multimesh.set_instance_color(i, tint * Color(shade, shade, shade, 1.0))
			i += 1
	var draw := MultiMeshInstance3D.new()
	draw.multimesh = multimesh
	draw.material_override = mat
	# Shader waves lift slabs up to .95 m; include that displacement in culling.
	draw.extra_cull_margin = 1.1
	draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_room.add_child(draw)


func _solid(center: Vector3, size: Vector3) -> void:
	_solids.append(Rect2(center.x - size.x * 0.5, center.z - size.z * 0.5, size.x, size.z))


func _index_static_visuals() -> void:
	# Index small visible pieces once per build; the collision rects remain fixed.
	_static_visual_grid.clear()
	for item in _room.find_children("*","MeshInstance3D",true,false):
		var node: MeshInstance3D = item
		if node.mesh == null: continue
		var extent: Vector3 = node.mesh.get_aabb().size
		if maxf(extent.x,maxf(extent.y,extent.z)) > 6.0: continue
		var p: Vector3 = node.global_position
		var key := Vector2i(floori(p.x/2.5),floori(p.z/2.5))
		if not _static_visual_grid.has(key): _static_visual_grid[key] = []
		_static_visual_grid[key].append(node)


func _closest_rect_point(rect: Rect2, point: Vector2) -> Vector2:
	return Vector2(clampf(point.x,rect.position.x,rect.end.x),clampf(point.y,rect.position.y,rect.end.y))


func _segment_rect_contact(start: Vector2, end: Vector2, rect: Rect2) -> Variant:
	if rect.has_point(start):
		# A wide sweep can start within its padded wall. Only count a swing
		# directed toward the nearest face, never one moving away from it.
		var distances := [start.x-rect.position.x,rect.end.x-start.x,start.y-rect.position.y,rect.end.y-start.y]
		var face := distances.find(distances.min())
		var outward: Vector2 = [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN][face]
		return start if (end-start).dot(outward) > .0001 else null
	var corners := [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
	var nearest: Variant = null
	var best := INF
	for i in 4:
		var crossing: Variant = Geometry2D.segment_intersects_segment(start,end,corners[i],corners[(i+1)%4])
		if crossing == null: continue
		var distance: float = start.distance_squared_to(crossing)
		if distance < best: best = distance; nearest = crossing
	return nearest


func static_hit_segment(from: Vector3, to: Vector3, radius: float = .0) -> Dictionary:
	var a := Vector2(from.x,from.z)
	var b := Vector2(to.x,to.z)
	if a.distance_squared_to(b) < .0001: return {}
	var nearest := INF
	var result: Dictionary = {}
	for i in _solids.size():
		var rect: Rect2 = _solids[i]
		var contact: Variant = _segment_rect_contact(a,b,rect.grow(maxf(0,radius)))
		if contact == null: continue
		var distance: float = a.distance_squared_to(contact)
		if distance >= nearest: continue
		nearest = distance
		var surface := _closest_rect_point(rect,contact)
		var point := Vector3(surface.x,0,surface.y)
		point.y = ground_height(point)+.8
		result = {"index":i,"point":point,"normal":Vector3(a.x-b.x,0,a.y-b.y).normalized()}
	return result


func static_hits_radius(center: Vector3, radius: float, limit: int = 3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var origin := Vector2(center.x,center.z)
	for i in _solids.size():
		var surface := _closest_rect_point(_solids[i],origin)
		var distance := origin.distance_to(surface)
		if distance > radius+.05: continue
		var point := Vector3(surface.x,0,surface.y)
		point.y = ground_height(point)+.8
		var away := point-center; away.y = 0
		result.append({"index":i,"point":point,"normal":away.normalized() if away.length_squared() > .0001 else Vector3.FORWARD,"distance":distance})
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	if result.size() > limit: result.resize(limit)
	return result


func react_static_hit(hit: Dictionary) -> int:
	var index := int(hit.get("index",-1))
	if index < 0 or index >= _solids.size(): return 0
	var rect: Rect2 = _solids[index]
	var at: Vector3 = hit.point
	var cell := Vector2i(floori(at.x/2.5),floori(at.z/2.5))
	var candidates: Array[Dictionary] = []
	for dx in range(-1,2):
		for dz in range(-1,2):
			for item in _static_visual_grid.get(cell+Vector2i(dx,dz),[]):
				var node: MeshInstance3D = item
				if not is_instance_valid(node) or not node.visible: continue
				var p := node.global_position
				if not rect.grow(.5).has_point(Vector2(p.x,p.z)): continue
				if p.y < ground_height(at)+.14 or p.y > ground_height(at)+4.5: continue
				var score := Vector2(p.x-at.x,p.z-at.z).length_squared()+absf(p.y-at.y)*.08
				candidates.append({"node":node,"score":score})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return float(a.score) < float(b.score))
	var reacted := 0
	for candidate in candidates:
		if reacted >= 3 or float(candidate.score) > 8.0: break
		var node: MeshInstance3D = candidate.node
		var id := node.get_instance_id()
		if not _static_rest.has(id): _static_rest[id] = {"scale":node.scale,"position":node.position}
		if _static_tweens.has(id) and _static_tweens[id] is Tween: _static_tweens[id].kill()
		var rest: Dictionary = _static_rest[id]
		var push: Vector3 = node.get_parent().global_basis.inverse()*Vector3(hit.normal)
		node.position = rest.position+push*.09
		node.scale = rest.scale*Vector3(1.09,.80,1.09)
		var tween := node.create_tween().set_parallel(true)
		tween.tween_property(node,"position",rest.position,.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(node,"scale",rest.scale,.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_static_tweens[id] = tween
		reacted += 1
	return reacted


func _wall(pos: Vector3, length: float, along_x: bool, height: float = 1.45, accent: Color = CYAN) -> void:
	var shape := Vector3(length, height, 0.75) if along_x else Vector3(0.75, height, length)
	box(_room, pos + Vector3(0, height * 0.5, 0), shape, Color("2d3034"))
	box(_room, pos + Vector3(0, height + 0.06, 0), Vector3(shape.x + 0.12, 0.12, shape.z + 0.12), Color("55575b"))
	_solid(pos, shape)
	var segments := maxi(1, int(length / 2.0))
	for i in segments:
		var offset := -length * 0.5 + (float(i) + 0.5) * length / segments
		var p := pos + (Vector3(offset, height * 0.38, 0) if along_x else Vector3(0, height * 0.38, offset))
		var rib := Vector3(0.18, height * 0.9, 0.88) if along_x else Vector3(0.88, height * 0.9, 0.18)
		box(_room, p, rib, DARK)
		if i % 2 == 0:
			var strip := Vector3(0.75, 0.05, 0.91) if along_x else Vector3(0.91, 0.05, 0.75)
			box(_room, p + Vector3(0, height * 0.35, 0), strip, accent, 0.55)


func _crate(pos: Vector3, dimensions := Vector3(2.0, 1.7, 1.8), color := Color("983f30")) -> void:
	var node := Node3D.new()
	_room.add_child(node)
	node.position = pos
	box(node, Vector3(0, dimensions.y * 0.5, 0), dimensions, Color("222b32"))
	box(node, Vector3(0, dimensions.y * 0.5, 0), dimensions - Vector3(0.12, -0.04, 0.12), color.darkened(0.22))
	for side in [-1.0, 1.0]:
		box(node, Vector3(side * dimensions.x * 0.42, dimensions.y * 0.5, 0), Vector3(0.12, dimensions.y + 0.12, dimensions.z + 0.1), color.lightened(0.18))
		box(node, Vector3(0, dimensions.y * 0.5, side * dimensions.z * 0.51), Vector3(dimensions.x * 0.65, dimensions.y * 0.55, 0.035), color.darkened(0.45))
		box(node, Vector3(0, dimensions.y * 0.76, side * dimensions.z * 0.53), Vector3(dimensions.x * 0.65, 0.05, 0.04), theme.accent, 1.8)
	box(node, Vector3(0, dimensions.y + 0.03, 0), Vector3(dimensions.x * 0.54, 0.04, dimensions.z * 0.58), color.darkened(0.5))
	box(node, Vector3(0, dimensions.y * 0.5, -dimensions.z * 0.54), Vector3(0.23, 0.24, 0.06), PALE)
	_solid(pos, dimensions)


func _machine(pos: Vector3, color := CYAN, large: bool = false) -> void:
	var unit := Node3D.new()
	_room.add_child(unit)
	unit.position = pos
	var width := 2.8 if large else 1.8
	var height := 3.6 if large else 2.1
	box(unit, Vector3(0, 0.14, 0), Vector3(width + 0.4, 0.28, 2.2), Color("18232c"))
	box(unit, Vector3(0, height * 0.5, 0), Vector3(width, height, 1.6), Color("31444f"))
	box(unit, Vector3(0, height * 0.5, -0.84), Vector3(width * 0.75, height * 0.76, 0.1), DARK)
	for side in [-1.0, 1.0]:
		box(unit, Vector3(side * (width * 0.4), height * 0.5, -0.92), Vector3(0.07, height * 0.76, 0.09), color, 0.8)
	for i in 5:
		box(unit, Vector3(0, 0.5 + i * height * 0.13, -0.91), Vector3(width * 0.55, 0.06, 0.1), Color("425b69"))
		box(unit, Vector3(-width * 0.19, 0.54 + i * height * 0.13, -0.98), Vector3(0.12, 0.06, 0.05), color, 0.6)
	box(unit, Vector3(0, height + 0.08, 0), Vector3(width + 0.13, 0.16, 1.8), Color("54636b"))
	# Camera-facing reactor instrumentation; the original collision footprint remains.
	box(unit,Vector3(0,height*.50,.825),Vector3(width*.78,height*.76,.055),Color("101e27"))
	for side in [-1.0,1.0]:
		box(unit,Vector3(side*width*.37,height*.50,.87),Vector3(.075,height*.72,.045),color,.85)
	for i in 4:
		var y := .38+float(i)*height*.18
		box(unit,Vector3(0,y,.88),Vector3(width*.50,.12,.05),Color("49616c"))
		box(unit,Vector3(-width*.13,y+.012,.918),Vector3(width*.22,.04,.027),color,.75)
	box(unit,Vector3(width*.16,height*.78,.90),Vector3(.22,.17,.055),color,1.0)
	_solid(pos, Vector3(width + 0.4, height, 2.2))


func _floor_line(a: Vector3, b: Vector3, color: Color, width: float = 0.08, emission: float = 0.0) -> void:
	var delta := b - a
	var mesh := box(_room, (a + b) * 0.5 + Vector3(0, 0.016, 0), Vector3(width, 0.018, delta.length()), color, emission)
	mesh.rotation.y = atan2(delta.x, delta.z)


func _label(text: String, pos: Vector3, size: int, color: Color, ground: bool = true) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.009
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	label.no_depth_test = false
	label.position = pos
	if ground:
		label.rotation_degrees.x = -90
	_room.add_child(label)


func _hazard(pos: Vector3, horizontal: bool = true, length: float = 5.0) -> void:
	var count := int(length / 0.65)
	for i in count:
		var p := pos + (Vector3(i * 0.65 - length * 0.5, 0.025, 0) if horizontal else Vector3(0, 0.025, i * 0.65 - length * 0.5))
		var stripe := box(_room, p, Vector3(0.28, 0.02, 0.65) if horizontal else Vector3(0.65, 0.02, 0.28), Color("a98941"))
		stripe.rotation.y = 0.5 if horizontal else -0.5


func _build_dungeon(depth: int) -> Dictionary:
	var layout: Dictionary = DungeonLayout.build(depth)
	_bounds = layout.bounds
	_dungeon_rooms = layout.rooms
	_walkable.assign(layout.walkable)
	if layout.get("desert",false):
		_height_links = layout.links
		DesertWorld.new(self).build(layout)
		return layout
	for room in _dungeon_rooms:
		var accent := _dungeon_accent(str(room.kind))
		_floor(room.rect,theme.room_tint)
		var rect: Rect2 = room.rect
		var gaps := {"north":false,"south":false,"west":false,"east":false}
		for neighbor_id in room.neighbors:
			var neighbor: Dictionary = _dungeon_rooms[neighbor_id]
			var delta: Vector3 = neighbor.center-room.center
			gaps["east" if delta.x > .1 else ("west" if delta.x < -.1 else ("south" if delta.z > 0 else "north"))] = true
		for side in ["north","south","west","east"]:
			var horizontal: bool = side in ["north","south"]
			var length := rect.size.x if horizontal else rect.size.y
			var at := Vector3(room.center.x,0,rect.position.y if side == "north" else rect.end.y) if horizontal else Vector3(rect.position.x if side == "west" else rect.end.x,0,room.center.z)
			var axis := Vector3.RIGHT if horizontal else Vector3.BACK
			if gaps[side]:
				var segment := length*.5-4.5
				for sign_value in [-1.0,1.0]:
					_dungeon_wall(at+axis*sign_value*(4.5+segment*.5),segment,horizontal,accent)
			else: _dungeon_wall(at,length,horizontal,accent)
		for cover in room.covers:
			if str(cover.get("style","crate")) == "pillar": _pillar(cover.pos,cover.size,accent)
			elif str(cover.get("style","crate")) == "barrier": _barrier(cover.pos,cover.size,accent)
			else: _crate(cover.pos,cover.size,Color("566a7e") if room.kind != "elite" else Color("593e66"))
		_room_dressing(room,accent)
		# Functional identity comes from a ground name, a status rail, and sparse
		# machinery, leaving the room's central cross completely open for movement.
		var nameplate := Label3D.new()
		nameplate.text = "%02d  %s" % [int(room.id)+1,room.name]
		nameplate.font_size = 47; nameplate.pixel_size = .009; nameplate.outline_size = 0
		nameplate.rotation_degrees.x = -90; nameplate.modulate = accent
		nameplate.position = room.center+Vector3(0,.04,8.4)
		_room.add_child(nameplate)
		var status := box(_room,room.center+Vector3(0,.025,9.55),Vector3(5.0,.035,.08),accent,.75)
		var pool := OmniLight3D.new(); pool.visible = not preload("res://scripts/quality.gd").low()
		pool.position = room.center+Vector3(0,2,6); pool.light_color = accent
		pool.light_energy = .4; pool.omni_range = 7; pool.shadow_enabled = false
		_room.add_child(pool)
		_room_markers[room.id] = {"label":nameplate,"rail":status,"light":pool,"color":accent}
		for side in [-1.0,1.0]:
			_floor_line(room.center+Vector3(side*11,0,-8),room.center+Vector3(side*11,0,8),Color(accent,.5),.045,.35)
		if room.kind in ["entry","rest","treasure"]:
			_machine(room.center+Vector3(-10.6,0,-8.6),accent,false)
		if room.kind == "boss":
			for x in [-11.0,11.0]: _machine(room.center+Vector3(x,0,-9.6),accent,true)
			_label("CORE / %02d" % depth,room.center+Vector3(0,.04,-8.7),48,ORANGE)
	for link in layout.links:
		var corridor: Rect2 = link.corridor
		_floor(corridor,theme.corridor_tint)
		var vertical := corridor.size.y > corridor.size.x or is_equal_approx(_dungeon_rooms[link.a].center.x,_dungeon_rooms[link.b].center.x)
		var middle := Vector3(corridor.get_center().x,0,corridor.get_center().y)
		if vertical:
			for sign_value in [-1.0,1.0]:
				_dungeon_wall(middle+Vector3(sign_value*corridor.size.x*.5,0,0),corridor.size.y,false,theme.accent,.65)
				_floor_line(middle+Vector3(sign_value*2.9,0,-corridor.size.y*.5),middle+Vector3(sign_value*2.9,0,corridor.size.y*.5),theme.accent,.055,.65)
		else:
			for sign_value in [-1.0,1.0]:
				_dungeon_wall(middle+Vector3(0,0,sign_value*corridor.size.y*.5),corridor.size.x,true,theme.accent,.65)
				_floor_line(middle+Vector3(-corridor.size.x*.5,0,sign_value*2.9),middle+Vector3(corridor.size.x*.5,0,sign_value*2.9),theme.accent,.055,.65)
		_dungeon_door(_dungeon_rooms[link.a],_dungeon_rooms[link.b])
		_dungeon_door(_dungeon_rooms[link.b],_dungeon_rooms[link.a])
	_label("降落区 / %s" % str(theme.name),layout.spawn+Vector3(0,.04,2),39,theme.accent)
	return layout


func _dungeon_accent(kind: String) -> Color:
	return {"entry":theme.get("accent",CYAN),"combat":Color("ff925a"),"elite":Color("c38aff"),"treasure":Color("ffd16b"),"rest":Color("7ee5b1"),"boss":Color("ff6570")}.get(kind,CYAN)


func _dungeon_wall(pos: Vector3, length: float, along_x: bool, accent: Color, height: float = .95) -> void:
	if length <= .01: return
	var size := Vector3(length,height,.65) if along_x else Vector3(.65,height,length)
	box(_room,pos+Vector3(0,height*.5,0),size,theme.get("wall",Color("283440")))
	box(_room,pos+Vector3(0,height+.04,0),Vector3(size.x+.04,.08,size.z+.04),theme.get("trim",Color("61717a")))
	box(_room,pos+Vector3(0,height*.64,0),Vector3(length,.065,.68) if along_x else Vector3(.68,.065,length),theme.accent,2.2)
	var segments := maxi(1,int(length/3.5))
	for i in segments:
		var offset := -length*.5+(i+.5)*length/segments
		var p := pos+(Vector3(offset,0,0) if along_x else Vector3(0,0,offset))
		box(_room,p+Vector3(0,height*.5,0),Vector3(.28,height+.22,.82) if along_x else Vector3(.82,height+.22,.28),theme.trim)
	_solid(pos,size)


## Structural cover: a lit tech column. Collision equals the base footprint.
func _pillar(pos: Vector3, size: Vector3, accent: Color) -> void:
	var node := Node3D.new(); _room.add_child(node); node.position = pos
	box(node,Vector3(0,.12,0),Vector3(size.x+.25,.24,size.z+.25),Color("1a2229"))
	box(node,Vector3(0,size.y*.5,0),size,theme.get("wall",STEEL))
	for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
		box(node,Vector3(corner.x*size.x*.47,size.y*.5,corner.y*size.z*.47),Vector3(.09,size.y*.92,.09),accent,.9)
	box(node,Vector3(0,size.y+.05,0),Vector3(size.x+.1,.1,size.z+.1),theme.get("trim",PALE))
	box(node,Vector3(0,size.y*.72,size.z*.51),Vector3(size.x*.5,.08,.03),accent,1.1)
	_solid(pos,size)

## Low energy barrier: hip-high cover with a glowing hard-light top.
func _barrier(pos: Vector3, size: Vector3, accent: Color) -> void:
	var node := Node3D.new(); _room.add_child(node); node.position = pos
	box(node,Vector3(0,size.y*.35,0),Vector3(size.x,size.y*.7,size.z),theme.get("wall",STEEL))
	box(node,Vector3(0,size.y*.72,0),Vector3(size.x*.96,.06,size.z*.5),accent,1.2)
	for side in [-1.0,1.0]:
		box(node,Vector3(side*size.x*.5,size.y*.5,0),Vector3(.18,size.y,size.z+.12),theme.get("trim",PALE))
	_solid(pos,size)

## Non-colliding set dressing: hazard chevrons, ceiling light bars and wall
## conduits sit outside the walkable union or flush on the floor.
func _room_dressing(room: Dictionary, accent: Color) -> void:
	var c: Vector3 = room.center
	var rect: Rect2 = room.rect
	var kind := str(room.kind)
	# Corner armor wraps the existing wall footprint, with no extra blockers.
	for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
		var pos := c+Vector3(corner.x*rect.size.x*.5,0,corner.y*rect.size.y*.5)
		box(_room,pos+Vector3(0,.88,0),Vector3(.7,1.76,.7),theme.trim)
		box(_room,pos+Vector3(0,.85,corner.y*.36),Vector3(.22,1.35,.055),theme.accent,2.2)
		box(_room,pos+Vector3(0,1.78,0),Vector3(.8,.12,.8),PALE)
	# Floor emblem: a thin ring of segments around the room centre.
	var radius := 3.4 if kind != "boss" else 5.2
	for i in 12:
		if i % 3 == 2: continue
		var a0 := TAU*i/12.0; var a1 := TAU*(i+.7)/12.0
		_floor_line(c+Vector3(cos(a0),0,sin(a0))*radius,c+Vector3(cos(a1),0,sin(a1))*radius,Color(accent,.55),.06,.55)
	# Outer conduits run behind the walls, giving rooms depth without collisions.
	for side in [-1.0,1.0]:
		var z := rect.position.y-.9 if side < 0 else rect.end.y+.9
		box(_room,Vector3(c.x,.55,z),Vector3(rect.size.x*.8,.22,.22),Color("1c252c"))
		box(_room,Vector3(c.x,.82,z),Vector3(rect.size.x*.6,.06,.08),accent,.5)
	# Hazard stripes mark the combat arena corners.
	if kind in ["combat","elite","boss"]:
		for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
			var p := c+Vector3(corner.x*(rect.size.x*.5-1.4),0,corner.y*(rect.size.y*.5-1.4))
			for k in 3:
				var o := float(k)*.42
				_floor_line(p+Vector3(-corner.x*o,0,0),p+Vector3(0,0,-corner.y*o),Color("ffb347") if kind != "elite" else accent,.07,.4)

func _dungeon_door(room: Dictionary, neighbor: Dictionary) -> void:
	var dir: Vector3 = (neighbor.center-room.center).normalized()
	var horizontal := absf(dir.z) > .5
	var reach: float = room.rect.size.y*.5 if horizontal else room.rect.size.x*.5
	var at: Vector3 = room.center+dir*reach
	var side := Vector3.RIGHT if horizontal else Vector3.BACK
	for sign_value in [-1.0,1.0]:
		var p: Vector3 = at+side*sign_value*4.25
		box(_room,p+Vector3(0,1.3,0),Vector3(.5,2.6,.9) if horizontal else Vector3(.9,2.6,.5),STEEL)
		box(_room,p+Vector3(0,1.3,0),Vector3(.10,2.3,.96) if horizontal else Vector3(.96,2.3,.10),CYAN,.9)
		_solid(p,Vector3(.5,2.6,.9) if horizontal else Vector3(.9,2.6,.5))
	var gate := Node3D.new(); _room.add_child(gate); gate.position = at
	# Several narrow hard-light rails read as one locked gate without hiding enemies.
	for i in 7:
		box(gate,Vector3(0,.25+i*.30,0),Vector3(8,.075,.18) if horizontal else Vector3(.18,.075,8),Color("ff7468"),1.1)
	gate.visible = false
	var door_rect := Rect2(Vector2(at.x,at.z)-Vector2(4,.22),Vector2(8,.44)) if horizontal else Rect2(Vector2(at.x,at.z)-Vector2(.22,4),Vector2(.44,8))
	_doors.append({"room_id":int(room.id),"neighbor":int(neighbor.id),"rect":door_rect,"node":gate,"locked":false})
	# Visible chevrons point across the doorway into the neighboring room.
	for i in 2:
		var arrow := at-dir*(2.0+i*.7)
		_floor_line(arrow-dir*.4-side*.42,arrow,Color("a6bcc4"),.095,.15)
		_floor_line(arrow-dir*.4+side*.42,arrow,Color("a6bcc4"),.095,.15)


func room_at(pos: Vector3) -> int:
	if not _dungeon: return -1
	var point := Vector2(pos.x,pos.z)
	for room in _dungeon_rooms:
		if room.rect.has_point(point): return int(room.id)
	return -1

func ground_height(pos: Vector3) -> float:
	if _height_links.is_empty(): return 0.0
	var point := Vector2(pos.x,pos.z)
	for room in _dungeon_rooms:
		if room.rect.has_point(point): return float(room.elevation)
	for link in _height_links:
		var rect: Rect2 = link.corridor
		if not rect.grow(.02).has_point(point): continue
		var t := (pos.z-rect.position.y)/rect.size.y if link.vertical else (pos.x-rect.position.x)/rect.size.x
		var step_index := clampi(floori(t*float(link.steps)),0,int(link.steps)-1)
		return lerpf(float(link.height_start),float(link.height_end),float(step_index)/float(link.steps-1))
	return 0.0

func ground_position(pos: Vector3) -> Vector3:
	return Vector3(pos.x,ground_height(pos),pos.z)


func set_room_locked(id: int, locked: bool) -> void:
	if id < 0 or id >= _dungeon_rooms.size(): return
	for door in _doors:
		if door.room_id == id:
			door.locked = locked
			door.node.visible = locked
	_door_solids.clear()
	for door in _doors:
		if door.locked: _door_solids.append(door.rect)


func set_room_cleared(id: int, cleared: bool = true) -> void:
	if not _room_markers.has(id): return
	var room: Dictionary = _dungeon_rooms[id]
	room.cleared = cleared
	var marker: Dictionary = _room_markers[id]
	var color: Color = Color("78e5a8") if cleared else marker.color
	marker.label.text = "%02d  %s%s" % [id+1,room.name," / 已清理" if cleared else ""]
	marker.label.modulate = color
	marker.rail.material_override = _material(color,.75,Vector3(5,.035,.08))
	marker.light.light_color = color
	marker.light.light_energy = .6 if cleared else .4


func _inside_walkable(point: Vector2) -> bool:
	for rect in _walkable:
		if rect.grow(.001).has_point(point): return true
	return false


func _circle_inside_walkable(point: Vector2, radius: float) -> bool:
	if not _inside_walkable(point): return false
	if radius <= 0.0: return true
	# Sample the union itself. Eroding each individual rectangle creates false
	# walls where a room and its corridor share a perfectly walkable seam.
	for i in 16:
		var a := TAU*i/16.0
		if not _inside_walkable(point+Vector2(cos(a),sin(a))*radius): return false
	return true


func _build_arena(stage: int) -> Dictionary:
	_bounds = Rect2(-18,-15,36,30)
	var variant := (stage-1)%5
	var accent: Color = [Color("ff7047"),Color("ffa942"),Color("bd7fff"),Color("62dde7"),Color("ff5265")][variant]
	_floor(_bounds,Color("36383b"))
	_wall(Vector3(0,0,-15),36,true,1.9,accent)
	_wall(Vector3(-18,0,0),30,false,1.2,CYAN)
	_wall(Vector3(18,0,0),30,false,.7,accent)
	_wall(Vector3(0,0,15),36,true,.55,CYAN)
	# One readable arena: four islands of cover, broad lanes in every direction.
	var offset := .65 if variant%2==1 else -.35
	var covers := [Vector3(-8.4,0,-2.6+offset),Vector3(8.4,0,1.5-offset),Vector3(4.6-offset,0,-7.5),Vector3(-10.2,0,8.0)]
	for i in covers.size():
		var dimensions := Vector3(2.6,1.2,1.8) if i%2==0 else Vector3(1.8,1.45,2.3)
		_crate(covers[i],dimensions,Color("783c32") if variant != 2 else Color("4c3a60"))
		# Emissive box rails echo the bright cuboid outlines in the visual reference.
		for sx in [-1.0,1.0]:
			for sz in [-1.0,1.0]:
				box(_room,covers[i]+Vector3(sx*dimensions.x*.51,dimensions.y*.5,sz*dimensions.z*.51),Vector3(.045,dimensions.y+.05,.045),accent,1.3)
		for sy in [.12,dimensions.y]:
			for sz in [-1.0,1.0]:
				box(_room,covers[i]+Vector3(0,sy,sz*dimensions.z*.51),Vector3(dimensions.x,.045,.045),accent,1.0)
			for sx in [-1.0,1.0]:
				box(_room,covers[i]+Vector3(sx*dimensions.x*.51,sy,0),Vector3(.045,.045,dimensions.z),accent,1.0)
	# Rear reactor bank gives depth without turning the level into a maze.
	for x in [-14.5,-10.0,10.0,14.5]:
		_machine(Vector3(x,0,-13.4),accent,variant==4)
	for x in [-16.9,16.9]:
		for z in [-10.0,-3.0,4.0,11.0]:
			box(_room,Vector3(x,.025,z),Vector3(.3,.03,1.6),accent,.8)
	for x in [-16.0,16.0]:
		_floor_line(Vector3(x,0,-12),Vector3(x,0,13),CYAN,.045,.65)
	for z in [-11.0,12.0]:
		_floor_line(Vector3(-15,0,z),Vector3(15,0,z),Color("5b5d5f"),.045)
	for z in range(-9,12,3):
		box(_room,Vector3(-1.9,.018,z),Vector3(.06,.02,.55),Color("4d6b73"),.2)
		box(_room,Vector3(1.9,.018,z),Vector3(.06,.02,.55),Color("4d6b73"),.2)
	_hazard(Vector3(0,0,13.2),true,8)
	_hazard(Vector3(0,0,-11),true,6)
	_label("SECTOR  %02d" % stage,Vector3(-10.8,.035,11.6),66,Color("8a8e8f"))
	_label("STARBLADE  /  RECLAIM",Vector3(8,.035,-3.2),36,Color("616769"))
	_label("%02d  /  LOCKDOWN" % stage,Vector3(-9,2.2,-14.55),58,accent,false)
	# A clearly framed north gate with a four-metre opening.
	for x in [-2.4,2.4]:
		box(_room,Vector3(x,1.5,-13.4),Vector3(.65,3.0,1.0),Color("34383c"))
		box(_room,Vector3(x,1.5,-12.85),Vector3(.17,2.6,.07),CYAN,1.5)
		_solid(Vector3(x,0,-13.4),Vector3(.65,3,1))
	box(_room,Vector3(0,3.1,-13.4),Vector3(5.7,.45,1),Color("454a4e"))
	box(_room,Vector3(0,2.94,-12.85),Vector3(4.2,.065,.07),CYAN,1.2)
	_label("TRANSIT / 07",Vector3(0,3.55,-13.25),34,Color("a2d2d8"),false)
	# Shallow vents and cable trays are traversable details.
	for p in [Vector3(-13,0,-6),Vector3(12,0,8),Vector3(-5,0,-7),Vector3(6,0,6)]:
		box(_room,p+Vector3(0,.015,0),Vector3(1.4,.025,1.1),DARK)
		for i in 5: box(_room,p+Vector3(-.5+i*.25,.035,0),Vector3(.06,.02,.8),Color("47525a"))
	# Local colored pools, contrasting with neutral metal and the dark void.
	for p in [Vector3(-12,1.7,-12),Vector3(12,1.7,-12),Vector3(0,1.7,13)]:
		var light := OmniLight3D.new(); light.visible = not preload("res://scripts/quality.gd").low()
		_room.add_child(light)
		light.position = p
		light.light_color = accent if p.z < 0 else CYAN
		light.light_energy = 1.2
		light.omni_range = 6.5
	# Low-poly buttresses drop into the black space around the arena.
	for x in [-18.7,18.7]:
		for z in [-13.0,-6.0,1.0,8.0,14.0]:
			box(_room,Vector3(x,-1.5,z),Vector3(.7,3,1.3),Color("191d22"))
	# Pixel stencil chevrons and inset maintenance panels add scale without collision.
	for side in [-1.0,1.0]:
		for z in [-8.0,0.0,8.0]:
			for step in 3:
				box(_room,Vector3(side*(14.4+step*.22),.035,z+step*.22),Vector3(.19,.025,.2),Color("858886"))
		for z in [-11.0,11.0]:
			box(_room,Vector3(side*12,.02,z),Vector3(2.6,.025,1.35),Color("292d30"))
			for i in 4:
				box(_room,Vector3(side*12-1+i*.65,.045,z),Vector3(.3,.022,.075),accent,.55)
	# The nearest pair engage shortly after entry; rear defenders hold the gate.
	var points := [Vector3(-5.5,0,5),Vector3(6,0,5),Vector3(0,0,-7),Vector3(-12,0,0),Vector3(12,0,-4),Vector3(-6,0,-8),Vector3(9,0,-9),Vector3(0,0,-1)]
	var kinds: Array
	match variant:
		0: kinds = ["scout","scout","gunner","scout","scout"]
		1: kinds = ["gunner","scout","gunner","scout","sniper","scout"]
		2: kinds = ["gunner","gunner","sniper","scout","scout","gunner","sniper"]
		3: kinds = ["gunner","sniper","elite","scout","gunner","scout","gunner"]
		_: kinds = ["gunner","gunner","boss","scout","sniper"]
	var enemy_defs: Array = []
	for i in kinds.size(): enemy_defs.append({"pos":points[i],"kind":kinds[i]})
	return {"spawn":Vector3(0,0,10),"enemies":enemy_defs,"containers":[],"extracts":[{"pos":Vector3(0,0,-12),"name":"跃迁出口","locked":true}],"terminal":Vector3.ZERO,"bounds":_bounds,"breakables":_arena_breakables(stage,enemy_defs)}

func _build_hub() -> Dictionary:
	_bounds = Rect2(-14,-12,28,24)
	_floor(_bounds,Color("333b3f"))
	_wall(Vector3(0,0,-11.5),28,true,2.5,CYAN)
	_wall(Vector3(-13.5,0,0),23,false,1.35,CYAN)
	_wall(Vector3(13.5,0,0),23,false,.7,ORANGE)
	_wall(Vector3(0,0,11.6),27,true,.48,CYAN)
	# A walkable concourse links four distinct physical service stations.
	# The standing points are 1.5 metres south of the furniture origins.
	var stations := [
		{"kind":"workbench","pos":Vector3(-8,0,-2.5),"name":"飞剑工作台"},
		{"kind":"warehouse","pos":Vector3(-8,0,6),"name":"回收仓库"},
		{"kind":"shop","pos":Vector3(8,0,4.5),"name":"补给商店"},
		{"kind":"deploy","pos":Vector3(4,0,-6.5),"name":"出击跃迁门"},
		{"kind":"heroes","pos":Vector3(-2.5,0,-6.5),"name":"英雄终端"}
	]
	for entry in stations:
		var origin: Vector3 = entry.pos + Vector3(0,0,-1.5)
		var accent: Color = {"workbench":CYAN,"warehouse":Color("efb85c"),"shop":Color("9ddd91"),"deploy":Color("94a4ff"),"heroes":Color("b899ff")}[entry.kind]
		_station_pad(origin,accent,entry.kind == "deploy")
		match entry.kind:
			"workbench": _hub_workbench(origin)
			"warehouse": _hub_warehouse(origin)
			"shop": _hub_shop(origin)
			"deploy": _hub_gate(origin)
			"heroes": _hub_heroes(origin)
		_station_label(entry.name,entry.pos+Vector3(0,.05,.55),accent)
	# Open centre: subtle tiled inlay and navigation seams, no pedestal collider.
	box(_room,Vector3(0,.012,2.5),Vector3(5.8,.022,6.0),Color("2b3439"))
	for x in [-2.95,2.95]:
		_floor_line(Vector3(x,0,-.5),Vector3(x,0,5.5),Color("65868c"),.045,.12)
	for z in [-.55,5.55]:
		_floor_line(Vector3(-3,0,z),Vector3(3,0,z),Color("65868c"),.045,.12)
	_label("07",Vector3(0,.04,1.5),128,Color("657579"))
	_label("RECOVERY  HALL",Vector3(0,.04,4.8),34,Color("627578"))
	for x in [-3.8,3.8]:
		for z in range(-7,10,3):
			box(_room,Vector3(x,.024,z),Vector3(.05,.02,.55),CYAN,.25)
	# Facility details hug walls, keeping all four interaction approaches open.
	_machine(Vector3(-10.5,0,-9.6),CYAN)
	_machine(Vector3(-7.2,0,-9.6),CYAN)
	_machine(Vector3(10.2,0,-9.6),Color("9ddd91"))
	for x in [-11.8,11.8]:
		_floor_line(Vector3(x,0,-8),Vector3(x,0,9),Color("485b61"),.055)
		for z in [-7.0,-.5,8.7]:
			box(_room,Vector3(x,.04,z),Vector3(.2,.07,.6),CYAN,.55)
	# Recessed wall ribs and cable conduits, with a compact facility identifier.
	for x in [-12.0,-4.0,0.0,8.0,12.0]:
		box(_room,Vector3(x,1.2,-11.0),Vector3(.22,2.4,.25),Color("52616a"))
	box(_room,Vector3(-2,1.75,-10.98),Vector3(3.2,.72,.10),Color("16242c"))
	_label("STARBLADE  /  07",Vector3(-2,1.8,-10.88),36,Color("95c3c7"),false)
	for p in [Vector3(-11,0,1),Vector3(10.5,0,-4),Vector3(-4,0,9)]:
		box(_room,p+Vector3(0,.015,0),Vector3(1.3,.025,1.0),DARK)
		for i in 5: box(_room,p+Vector3(-.5+i*.25,.035,0),Vector3(.07,.02,.75),Color("54616a"))
	for p in [Vector3(-8,2.1,-3),Vector3(8,2.1,4),Vector3(4,2.4,-7)]:
		var light := OmniLight3D.new(); light.visible = not preload("res://scripts/quality.gd").low()
		_room.add_child(light)
		light.position = p
		light.light_color = Color("9ddd91") if p.x > 6 else CYAN
		light.light_energy = .8
		light.omni_range = 5.0
	return {"spawn":Vector3(0,0,3),"enemies":[],"containers":[],"extracts":[],"terminal":Vector3.ZERO,"bounds":_bounds,"stations":stations,"breakables":[]}


func _station_pad(origin: Vector3, accent: Color, gate: bool = false) -> void:
	var width := 5.4 if gate else 4.6
	box(_room,origin+Vector3(0,.018,.55),Vector3(width,.03,3.3),Color("232c32"))
	for x in [-width*.5,width*.5]:
		_floor_line(origin+Vector3(x,0,-1),origin+Vector3(x,0,2.2),accent,.05,.5)
	_floor_line(origin+Vector3(-width*.5,0,2.2),origin+Vector3(width*.5,0,2.2),accent,.05,.5)
	for x in [-.6,.6]:
		box(_room,origin+Vector3(x,.045,1.5),Vector3(.12,.02,.36),accent,.55)


func _station_label(text: String, pos: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.font = preload("res://scripts/quality.gd").font()
	label.text = text
	label.font_size = 32
	label.pixel_size = .009
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	label.position = pos
	label.rotation_degrees.x = -90
	_room.add_child(label)


func _hub_workbench(pos: Vector3) -> void:
	var station := Node3D.new()
	station.name = "WorkbenchStation"
	_room.add_child(station)
	station.position = pos
	for x in [-1.55,1.55]:
		box(station,Vector3(x,.5,0),Vector3(.33,1.0,1.2),Color("27343e"))
	box(station,Vector3(0,1.05,0),Vector3(3.8,.18,1.5),Color("6d7b80"))
	box(station,Vector3(0,1.16,.08),Vector3(2.35,.035,.95),Color("203943"))
	box(station,Vector3(0,.85,.77),Vector3(2.8,.12,.06),CYAN,.7)
	box(station,Vector3(0,1.68,-.63),Vector3(3.4,.94,.16),Color("263944"))
	box(station,Vector3(-.65,1.71,-.53),Vector3(1.7,.62,.04),Color("132a32"))
	for i in 4:
		box(station,Vector3(-1.22+i*.37,1.72,-.50),Vector3(.21,.23+float(i%2)*.14,.025),CYAN,.45)
	var sword := make_sword(CYAN)
	station.add_child(sword)
	sword.position = Vector3(-.15,1.26,.12)
	sword.rotation.y = PI*.5
	for side in [-1.0,1.0]:
		box(station,Vector3(side*1.48,1.4,-.28),Vector3(.24,.64,.24),Color("d09655"))
		var arm := box(station,Vector3(side*1.20,1.75,-.12),Vector3(.68,.16,.19),Color("b67d42"))
		arm.rotation.z = side*-.4
		box(station,Vector3(side*.94,1.58,.02),Vector3(.13,.36,.13),Color("e5c086"))
		box(station,Vector3(side*.94,1.39,.02),Vector3(.08,.08,.1),CYAN,1.2)
	_solid(pos,Vector3(3.8,2.2,1.5))


func _hub_warehouse(pos: Vector3) -> void:
	var station := Node3D.new()
	station.name = "WarehouseStation"
	_room.add_child(station)
	station.position = pos
	for x in [-1.9,1.9]:
		box(station,Vector3(x,1.35,0),Vector3(.19,2.7,1.5),Color("b17c48"))
		box(station,Vector3(x,1.35,.78),Vector3(.065,2.3,.05),Color("efb85c"),.45)
	for y in [.13,1.03,1.93,2.72]:
		box(station,Vector3(0,y,0),Vector3(4.0,.14,1.52),Color("5f6d72"))
	for row in 3:
		for col in 3:
			var c := Color("536d76") if (col+row)%2==0 else Color("836049")
			var p := Vector3(-1.25+col*1.25,.54+row*.89,.05)
			box(station,p,Vector3(.94,.65,1.02),c)
			box(station,p+Vector3(0,0,.53),Vector3(.78,.48,.04),c.darkened(.35))
			box(station,p+Vector3(0,.04,.565),Vector3(.30,.11,.025),Color("efb85c"),.55)
			box(station,p+Vector3(-.32,0,.57),Vector3(.06,.50,.04),Color("95a2a2"))
	box(station,Vector3(0,2.91,0),Vector3(2.5,.24,.3),Color("26323b"))
	box(station,Vector3(0,2.92,.17),Vector3(1.8,.065,.04),Color("efb85c"),.65)
	_solid(pos,Vector3(4.0,3.0,1.55))


func _hub_shop(pos: Vector3) -> void:
	var station := Node3D.new()
	station.name = "ShopStation"
	_room.add_child(station)
	station.position = pos
	var green := Color("9ddd91")
	box(station,Vector3(0,.52,0),Vector3(3.8,1.04,1.35),Color("36524e"))
	box(station,Vector3(0,1.09,0),Vector3(4.0,.16,1.52),Color("a3b3a6"))
	box(station,Vector3(0,.55,.71),Vector3(3.0,.63,.05),Color("213c39"))
	box(station,Vector3(0,.55,.75),Vector3(.20,.43,.03),green,.7)
	box(station,Vector3(0,.55,.76),Vector3(.62,.14,.03),green,.7)
	# Register and visible cyan / red bottles make this a supply counter.
	box(station,Vector3(1.24,1.25,.03),Vector3(.66,.22,.52),Color("273b42"))
	var screen := box(station,Vector3(1.24,1.48,.0),Vector3(.6,.42,.08),Color("15302b"))
	screen.rotation_degrees.x = -15
	box(station,Vector3(1.24,1.49,.065),Vector3(.43,.25,.025),green,.7)
	for i in 3:
		var color := CYAN if i%2==0 else Color("ff8070")
		box(station,Vector3(-1.25+i*.45,1.33,.1),Vector3(.22,.34,.24),color,.35)
		box(station,Vector3(-1.25+i*.45,1.54,.1),Vector3(.15,.08,.17),PALE)
	# Tiny vendor robot peeking from behind the counter, no extra gameplay actor.
	box(station,Vector3(-.2,1.24,-.47),Vector3(.55,.64,.42),Color("66877a"))
	box(station,Vector3(-.2,1.82,-.47),Vector3(.82,.62,.64),Color("ced9c6"))
	box(station,Vector3(-.2,1.83,-.13),Vector3(.66,.27,.06),Color("14312b"))
	for x in [-.4,0.0]:
		box(station,Vector3(x,1.86,-.09),Vector3(.11,.12,.025),green,1.0)
	for x in [-1.9,1.9]:
		box(station,Vector3(x,1.8,-.65),Vector3(.12,1.45,.14),Color("536f64"))
	box(station,Vector3(0,2.57,-.44),Vector3(4.1,.22,.65),Color("436457"))
	box(station,Vector3(0,2.48,-.08),Vector3(3.4,.055,.055),green,.8)
	_solid(pos,Vector3(4.1,2.7,1.55))


func _hub_gate(pos: Vector3) -> void:
	var station := Node3D.new()
	station.name = "DeployStation"
	_room.add_child(station)
	station.position = pos
	var violet := Color("94a4ff")
	for side in [-1.0,1.0]:
		box(station,Vector3(side*2.15,1.65,0),Vector3(.65,3.3,.95),Color("495362"))
		box(station,Vector3(side*2.15,1.6,.53),Vector3(.14,2.7,.06),violet,1.2)
		box(station,Vector3(side*2.15,.18,0),Vector3(.95,.36,1.35),Color("27313b"))
		_solid(pos+Vector3(side*2.15,0,0),Vector3(.95,3.3,1.35))
	box(station,Vector3(0,3.38,0),Vector3(5.0,.4,1.0),Color("5b6574"))
	box(station,Vector3(0,3.14,.53),Vector3(3.8,.07,.06),violet,1.0)
	# Back-wall strips suggest a charged portal; the opening and standing point stay free.
	for x in [-1.5,-.75,0.0,.75,1.5]:
		box(station,Vector3(x,1.6,-.48),Vector3(.025,2.65,.025),violet,.4)
	box(station,Vector3(0,.04,-.1),Vector3(3.7,.07,1.7),Color("3a415e"))
	for x in [-1.4,0.0,1.4]:
		box(station,Vector3(x,.085,.5),Vector3(.6,.025,.11),violet,.8)


func _hub_heroes(pos: Vector3) -> void:
	var station := Node3D.new()
	station.name = "HeroesStation"
	_room.add_child(station); station.position = pos
	box(station,Vector3(0,.38,0),Vector3(3.0,.76,1.05),Color("303346"))
	box(station,Vector3(0,.81,0),Vector3(3.25,.16,1.2),Color("6d6b87"))
	box(station,Vector3(0,.37,.56),Vector3(2.65,.42,.04),Color("182432"))
	for i in 3:
		var id: String = ["chrono","ember","flux"][i]
		var color: Color = [Color("73eaff"),Color("ff824e"),Color("c28cff")][i]
		var x := float(i-1)*1.02
		box(station,Vector3(x,.94,0),Vector3(.80,.12,.80),Color("263543"))
		box(station,Vector3(x,1.015,0),Vector3(.63,.025,.63),color,.7)
		var hero := make_hero(id)
		station.add_child(hero); hero.position = Vector3(x,1.03,0); hero.scale = Vector3.ONE*.55
		hero.rotation.y = PI
		box(station,Vector3(x,.38,.59),Vector3(.40,.065,.025),color,.85)
	for side in [-1.0,1.0]:
		box(station,Vector3(side*1.52,1.65,-.45),Vector3(.12,1.75,.13),Color("625779"))
		box(station,Vector3(side*1.52,1.65,-.36),Vector3(.04,1.45,.025),Color("bc99ff"),.7)
	box(station,Vector3(0,2.55,-.43),Vector3(3.2,.18,.25),Color("4f4967"))
	box(station,Vector3(0,2.45,-.28),Vector3(2.1,.035,.025),Color("bd9aff"),.8)
	_solid(pos,Vector3(3.25,2.65,1.2))


func _arena_breakables(stage: int, enemy_defs: Array) -> Array:
	# Data only: destructible collision belongs to the runtime, never _solids.
	var candidates := [Vector3(-13,0,7),Vector3(-13,0,3),Vector3(-4,0,3),Vector3(4,0,7),Vector3(12,0,6),Vector3(-12,0,-7),Vector3(13,0,-9),Vector3(0,0,2.5),Vector3(11,0,10),Vector3(-3,0,-10)]
	var result: Array = []
	for point in candidates:
		if blocked(point,.65) or point.distance_to(Vector3(0,0,10)) < 2.4 or point.distance_to(Vector3(0,0,-12)) < 2.4:
			continue
		var clear := true
		for e in enemy_defs:
			if point.distance_to(e.pos) < 1.7: clear = false
		if not clear: continue
		result.append({"pos":point,"kind":"canister" if (result.size()+stage)%3==0 else "crate"})
		if result.size() == 8: break
	return result


func make_breakable(kind: String) -> Node3D:
	if kind == "urn": return DesertWorld.new(self).make_urn()
	var node := Node3D.new()
	node.name = "BreakableCanister" if kind == "canister" else "BreakableCrate"
	if kind == "canister":
		box(node,Vector3(0,.50,0),Vector3(.61,.96,.61),Color("284651"))
		box(node,Vector3(0,.51,0),Vector3(.65,.64,.65),Color("3b6772"))
		for y in [.12,.90]:
			box(node,Vector3(0,y,0),Vector3(.72,.13,.72),Color("788e91"))
			box(node,Vector3(0,y+.075,0),Vector3(.64,.025,.64),CYAN,.55)
		box(node,Vector3(0,1.04,0),Vector3(.28,.18,.28),Color("405963"))
		for side in [-1.0,1.0]:
			box(node,Vector3(0,.50,side*.34),Vector3(.25,.34,.035),Color("152c34"))
			box(node,Vector3(0,.50,side*.365),Vector3(.08,.24,.025),CYAN,1.0)
			box(node,Vector3(0,.50,side*.37),Vector3(.20,.08,.025),CYAN,1.0)
	else:
		box(node,Vector3(0,.43,0),Vector3(.92,.84,.92),Color("75513d"))
		box(node,Vector3(0,.43,0),Vector3(.96,.57,.96),Color("45372f"))
		for side in [-1.0,1.0]:
			box(node,Vector3(side*.34,.43,0),Vector3(.11,.91,1.0),Color("b98754"))
			box(node,Vector3(0,.43,side*.49),Vector3(.43,.42,.035),Color("372a27"))
			box(node,Vector3(0,.43,side*.52),Vector3(.27,.08,.025),ORANGE,.9)
			box(node,Vector3(0,.43,side*.525),Vector3(.08,.27,.025),ORANGE,.9)
		box(node,Vector3(0,.88,0),Vector3(.46,.035,.55),Color("b0804b"))
		box(node,Vector3(0,.907,0),Vector3(.07,.02,.44),ORANGE,.7)
	return node


func blocked(pos: Vector3, radius: float = 0.4) -> bool:
	var p := Vector2(pos.x,pos.z)
	if _dungeon and not _circle_inside_walkable(p,radius): return true
	if not _dungeon and not _bounds.grow(-radius - 0.4).has_point(p):
		return true
	for rect in _door_solids:
		if rect.grow(radius).has_point(p): return true
	for rect in _solids:
		if rect.grow(radius).has_point(p):
			return true
	return false


func line_blocked(a: Vector3, b: Vector3) -> bool:
	var p := Vector2(a.x,a.z)
	var q := Vector2(b.x,b.z)
	if _dungeon:
		var count := maxi(1,ceili(p.distance_to(q)/.35))
		for i in count+1:
			if not _inside_walkable(p.lerp(q,float(i)/count)): return true
	var obstacles: Array[Rect2] = _solids
	if not _door_solids.is_empty():
		obstacles = _solids.duplicate(); obstacles.append_array(_door_solids)
	for rect in obstacles:
		if rect.has_point(p) or rect.has_point(q):
			return true
		var lo := rect.position
		var hi := rect.end
		if Geometry2D.segment_intersects_segment(p,q,lo,Vector2(hi.x,lo.y)) != null:
			return true
		if Geometry2D.segment_intersects_segment(p,q,Vector2(hi.x,lo.y),hi) != null:
			return true
		if Geometry2D.segment_intersects_segment(p,q,hi,Vector2(lo.x,hi.y)) != null:
			return true
		if Geometry2D.segment_intersects_segment(p,q,Vector2(lo.x,hi.y),lo) != null:
			return true
	return false


func make_actor(kind: String) -> Node3D:
	if kind == "player":
		return _make_cube_hero()
	if kind == "scout":
		return _make_scout()
	if kind == "sniper":
		return _make_sniper()
	var root := Node3D.new()
	root.name = kind.capitalize()
	var hero := kind == "player"
	var boss := kind == "boss"
	var elite := kind == "elite"
	var hull := PALE if hero else (Color("984231") if not elite else Color("60416c"))
	var glow := CYAN if hero else (Color("e393f8") if elite else ORANGE)
	var joints := Color("172734")
	# Chunky but articulated astronaut / sentry construction.
	for side in [-1.0,1.0]:
		var leg := Node3D.new()
		leg.name = "LegL" if side < 0 else "LegR"
		root.add_child(leg)
		leg.position = Vector3(side*0.23,0.52,0)
		box(leg,Vector3(0,-0.15,0),Vector3(0.28,0.43,0.32),joints)
		box(leg,Vector3(0,-0.12,-0.12),Vector3(0.30,0.23,0.13),hull)
		box(leg,Vector3(0,-0.39,-0.09),Vector3(0.35,0.24,0.57),Color("24323b"))
		box(leg,Vector3(0,-0.4,-0.35),Vector3(0.28,0.07,0.025),glow,0.3)
	box(root,Vector3(0,0.63,0),Vector3(0.63,0.23,0.43),joints)
	box(root,Vector3(0,0.98,0),Vector3(0.73,0.61,0.5),hull)
	box(root,Vector3(0,1.02,-0.28),Vector3(0.48,0.31,0.1),joints)
	box(root,Vector3(0,1.05,-0.34),Vector3(0.25,0.12,0.035),glow,1.1)
	box(root,Vector3(-0.2,0.79,-0.28),Vector3(0.1,0.11,0.05),ORANGE,0.15)
	box(root,Vector3(0,0.89,0.35),Vector3(0.58,0.54,0.22),Color("304754"))
	for side in [-1.0,1.0]:
		box(root,Vector3(side*0.23,0.92,0.49),Vector3(0.14,0.4,0.12),glow,0.35)
		var arm := Node3D.new()
		arm.name = "ArmL" if side < 0 else "ArmR"
		root.add_child(arm)
		arm.position = Vector3(side*0.48,1.08,0)
		box(arm,Vector3(0,-0.12,0),Vector3(0.26,0.47,0.29),joints)
		box(arm,Vector3(0,0.02,0),Vector3(0.35,0.25,0.39),hull if side > 0 else (Color("e1a465") if hero else hull))
		box(arm,Vector3(0,-0.34,-0.02),Vector3(0.28,0.22,0.31),hull)
	box(root,Vector3(0,1.38,0),Vector3(0.25,0.12,0.25),joints)
	box(root,Vector3(0,1.58,0),Vector3(0.68,0.48,0.57),hull)
	box(root,Vector3(0,1.58,-0.3),Vector3(0.57,0.25,0.07),Color("142832"))
	box(root,Vector3(0,1.6,-0.345),Vector3(0.49,0.11,0.035),glow,1.4)
	box(root,Vector3(0.38,1.59,0.02),Vector3(0.1,0.22,0.23),joints)
	box(root,Vector3(-0.38,1.59,0.02),Vector3(0.1,0.22,0.23),joints)
	if not hero:
		for side in [-1.0,1.0]:
			box(root,Vector3(side*0.49,0.75,-0.32),Vector3(0.27,0.23,0.65),Color("15232c"))
			box(root,Vector3(side*0.49,0.75,-0.66),Vector3(0.18,0.14,0.07),glow,0.7)
	if elite or boss:
		for side in [-1.0,1.0]:
			box(root,Vector3(side*0.53,1.27,0),Vector3(0.48,0.3,0.66),hull)
			box(root,Vector3(side*0.53,1.31,-0.35),Vector3(0.32,0.065,0.06),glow,0.8)
		root.scale = Vector3.ONE * (2.0 if boss else 1.25)
	if boss:
		box(root,Vector3(0,1.93,0),Vector3(0.18,0.25,0.2),ORANGE,0.9)
		box(root,Vector3(-0.3,1.92,0.1),Vector3(0.13,0.22,0.15),ORANGE,0.7)
		box(root,Vector3(0.3,1.92,0.1),Vector3(0.13,0.22,0.15),ORANGE,0.7)
	return root


func make_hero(id: String = "chrono") -> Node3D:
	if id not in ["chrono","ember","flux"]: id = "chrono"
	var root := _make_cube_hero()
	root.set_meta("hero_id",id)
	var accent: Color = {"chrono":Color("66e7ff"),"ember":Color("ff7547"),"flux":Color("c28aff")}[id]
	var hull: Color = {"chrono":Color("bad9dc"),"ember":Color("d5bdad"),"flux":Color("c5b6dd")}[id]
	root.get_node("CubeBody").material_override = _material(hull,0,Vector3(1.02,.98,.98),true)
	for child in root.find_children("*","MeshInstance3D",true,false):
		var mat = child.material_override
		if mat is ShaderMaterial:
			var color: Color = mat.get_shader_parameter("base_color")
			if color.is_equal_approx(CYAN):
				child.material_override = _material(accent,float(mat.get_shader_parameter("emission_strength")),Vector3(mat.get_shader_parameter("half_extent"))*2.0)
	match id:
		"chrono":
			_hero_ring(root,Vector3(0,1.225,0),.25,accent)
			box(root,Vector3(0,1.25,-.075),Vector3(.035,.025,.18),Color("eeffff"),.7)
			box(root,Vector3(.07,1.25,.015),Vector3(.15,.025,.035),accent,.9)
			for side in [-1.,1.]:
				var crystal := _hero_crystal(root,Vector3(side*.54,.96,.08),Vector3(.14,.42,.18),accent)
				crystal.rotation.z = side*-.2
		"ember":
			for side in [-1.,1.]:
				var fin := _hero_crystal(root,Vector3(side*.40,1.23,.13),Vector3(.20,.56,.34),accent)
				fin.rotation.z = side*-.35
				box(root,Vector3(side*.52,.64,-.01),Vector3(.05,.25,.40),Color("85352d"))
				box(root,Vector3(side*.55,.68,-.11),Vector3(.025,.07,.23),Color("ffc460"),.9)
			box(root,Vector3(0,.72,.63),Vector3(.20,.43,.10),Color("e97037"),.5)
		"flux":
			var orbit := _hero_ring(root,Vector3(0,1.43,0),.46,accent)
			orbit.rotation.z = .18
			for side in [-1.,1.]:
				box(root,Vector3(side*.56,.74,.02),Vector3(.13,.38,.34),Color("50446d"))
				box(root,Vector3(side*.63,.74,.02),Vector3(.045,.20,.23),accent,.8)
			_hero_crystal(root,Vector3(0,1.40,0),Vector3(.19,.28,.19),Color("f1dbff"))
	return root


func _hero_ring(parent: Node3D, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = radius-.025; torus.outer_radius = radius+.025
	torus.rings = 32; torus.ring_segments = 5
	var node := MeshInstance3D.new(); node.mesh = torus
	node.material_override = _material(color,.85,Vector3(radius*2,.05,radius*2))
	parent.add_child(node); node.position = pos
	return node


func _hero_crystal(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0; mesh.bottom_radius = .5; mesh.height = 1.0; mesh.radial_segments = 4
	var node := MeshInstance3D.new(); node.mesh = mesh
	node.material_override = _material(color,.28,Vector3.ONE)
	parent.add_child(node); node.position = pos; node.scale = size
	return node


func _beveled_box(parent: Node3D, pos: Vector3, size: Vector3, bevel: float, color: Color) -> MeshInstance3D:
	# Six gridded faces projected onto a rounded cuboid: real bevel geometry,
	# stable normals and no textures, so the hero stays crisp under squash/stretch.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size*.5
	var inner := half-Vector3.ONE*bevel
	var axes := [
		[Vector3.RIGHT,Vector3.BACK,Vector3.UP],
		[Vector3.LEFT,Vector3.FORWARD,Vector3.UP],
		[Vector3.UP,Vector3.RIGHT,Vector3.BACK],
		[Vector3.DOWN,Vector3.RIGHT,Vector3.FORWARD],
		[Vector3.BACK,Vector3.LEFT,Vector3.UP],
		[Vector3.FORWARD,Vector3.RIGHT,Vector3.UP]]
	for face in axes:
		var normal: Vector3 = face[0]
		var u: Vector3 = face[1]
		var v: Vector3 = face[2]
		var hu := half.dot(u.abs())
		var hv := half.dot(v.abs())
		var us := [-hu,-hu+bevel,hu-bevel,hu]
		var vs := [-hv,-hv+bevel,hv-bevel,hv]
		var origin := normal*half.dot(normal.abs())
		for i in 3:
			for j in 3:
				for corner in [Vector2i(i,j),Vector2i(i+1,j),Vector2i(i,j+1),Vector2i(i+1,j),Vector2i(i+1,j+1),Vector2i(i,j+1)]:
					var raw: Vector3 = origin+u*us[corner.x]+v*vs[corner.y]
					var inset := raw.clamp(-inner,inner)
					var rounded_normal := (raw-inset).normalized()
					surface.set_normal(rounded_normal)
					surface.add_vertex(inset+rounded_normal*bevel)
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	instance.material_override = _material(color,0.0,size,true)
	instance.position = pos
	parent.add_child(instance)
	return instance


func _make_cube_hero() -> Node3D:
	var root := Node3D.new()
	root.name = "Player"
	var body := _beveled_box(root,Vector3(0,.70,0),Vector3(1.02,.98,.98),.10,Color("cbdad8"))
	body.name = "CubeBody"
	# Face looks toward -Z, matching movement/attack heading. Large pixel eyes
	# remain legible at gameplay zoom without a humanoid silhouette.
	var face := _beveled_box(root,Vector3(0,.73,-.486),Vector3(.84,.47,.085),.035,Color("10232b"))
	face.name = "FacePanel"
	for side in [-1.0,1.0]:
		var eye := box(root,Vector3(side*.19,.79,-.537),Vector3(.145,.185,.025),CYAN,1.0)
		eye.name = "EyeL" if side < 0 else "EyeR"
		box(root,Vector3(side*.19-.025,.837,-.553),Vector3(.043,.045,.012),Color("edffef"),.4)
		box(root,Vector3(side*.31,.625,-.54),Vector3(.07,.035,.017),Color("ffad70"),.35)
		box(root,Vector3(side*.19,.91,-.54),Vector3(.18,.025,.02),Color("718e9a"),.10)
		# Inset shoulder trim and a tiny rear screw give the cube a manufactured shell.
		box(root,Vector3(side*.498,.93,.08),Vector3(.022,.055,.43),Color("426574"),.15)
		box(root,Vector3(side*.502,.55,.30),Vector3(.024,.065,.065),Color("638392"))
		var foot := _beveled_box(root,Vector3(side*.27,.145,.04),Vector3(.27,.16,.36),.045,Color("354c56"))
		foot.name = "HoverPadL" if side < 0 else "HoverPadR"
		box(root,Vector3(side*.27,.125,-.15),Vector3(.16,.045,.025),CYAN,.8)
	box(root,Vector3(0,.615,-.543),Vector3(.12,.025,.019),Color("80bec4"),.2)
	# A small coral badge and cyan crown stripe identify the hero from behind.
	box(root,Vector3(-.29,1.178,-.04),Vector3(.12,.025,.38),ORANGE,.3)
	box(root,Vector3(.12,1.178,-.04),Vector3(.35,.025,.09),CYAN,.55)
	for i in 3:
		box(root,Vector3(.13+float(i)*.095,1.185,.23),Vector3(.04,.018,.15),Color("466672"))
	_beveled_box(root,Vector3(0,.71,.51),Vector3(.45,.49,.14),.035,Color("385760"))
	box(root,Vector3(0,.72,.592),Vector3(.10,.32,.022),CYAN,.8)
	return root


func _make_scout() -> Node3D:
	var root := Node3D.new()
	root.name = "Scout"
	box(root,Vector3(0,0.6,0),Vector3(0.8,0.42,0.7),Color("89432f"))
	box(root,Vector3(0,0.85,0.07),Vector3(0.62,0.2,0.6),Color("d5764c"))
	box(root,Vector3(0,0.64,-0.37),Vector3(0.6,0.2,0.08),DARK)
	box(root,Vector3(0,0.65,-0.42),Vector3(0.42,0.08,0.035),ORANGE,1.2)
	for side in [-1.0,1.0]:
		for end in [-1.0,1.0]:
			box(root,Vector3(side*0.5,0.35,end*0.24),Vector3(0.22,0.48,0.21),Color("32404a"))
			box(root,Vector3(side*0.58,0.12,end*0.29),Vector3(0.32,0.16,0.34),DARK)
	box(root,Vector3(0,0.86,-0.2),Vector3(0.16,0.16,0.78),DARK)
	box(root,Vector3(0,0.86,-0.62),Vector3(0.12,0.1,0.08),ORANGE,0.8)
	return root


func _make_sniper() -> Node3D:
	var root := Node3D.new()
	root.name = "Sniper"
	box(root,Vector3(0,0.22,0),Vector3(1.1,0.28,1.05),Color("34414d"))
	for side in [-1.0,1.0]:
		box(root,Vector3(side*0.54,0.21,0),Vector3(0.24,0.31,1.23),DARK)
	box(root,Vector3(0,0.57,0),Vector3(0.61,0.45,0.6),Color("836044"))
	box(root,Vector3(0,0.94,0),Vector3(0.9,0.32,0.77),Color("c29c61"))
	box(root,Vector3(0,0.94,-0.55),Vector3(0.27,0.2,1.03),DARK)
	box(root,Vector3(0,0.94,-1.1),Vector3(0.23,0.15,0.09),ORANGE,0.8)
	box(root,Vector3(-0.28,1.15,-0.22),Vector3(0.16,0.18,0.23),ORANGE,0.8)
	box(root,Vector3(0.25,1.36,0.16),Vector3(0.07,0.65,0.07),Color("9ca7a4"))
	return root


func make_sword(color: Color) -> Node3D:
	var sword := Node3D.new()
	sword.name = "FlyingSword"
	box(sword,Vector3(0,0,0.28),Vector3(0.105,0.09,0.33),Color("31434c"))
	box(sword,Vector3(0,0,0.07),Vector3(0.41,0.1,0.1),Color("bbc8c7"))
	box(sword,Vector3(0,0,-0.37),Vector3(0.18,0.07,0.85),Color("dfedeb"))
	box(sword,Vector3(0,0.041,-0.37),Vector3(0.048,0.018,0.82),color,1.4)
	box(sword,Vector3(0,0,-0.83),Vector3(0.1,0.065,0.19),color,0.7)
	box(sword,Vector3(0,0,0.48),Vector3(0.16,0.12,0.08),color,0.5)
	return sword

