extends Node3D
## Layered one-shot effects for the Compatibility renderer. No global TIME uniforms,
## no persistent Tweens, no screen texture and no gameplay state are used here.

const DISC = preload("res://assets/vfx_disc.gdshader")
const ARC = preload("res://assets/vfx_arc.gdshader")
const COLUMN = preload("res://assets/vfx_column.gdshader")
const TIME_SHELL = preload("res://assets/vfx_time_shell.gdshader")
const ECHO = preload("res://assets/vfx_echo.gdshader")
const GRAVITY = preload("res://assets/vfx_gravity.gdshader")
const GUARD = preload("res://assets/vfx_guard.gdshader")
const SLAM = preload("res://assets/vfx_slam.gdshader")
const SLAM_COLUMN = preload("res://assets/vfx_slam_column.gdshader")
const EMBER_SPRITE = preload("res://assets/vfx_ember_sprite.gdshader")
const EMBER_SLAM_STRIP = preload("res://assets/generated/ember_slam_strip.png")
const EMBER_FLAME_STRIP = preload("res://assets/generated/ember_flame_strip.png")
const KINDS := ["spear_thrust","spin","impact","static_shard","lightning","wave","rupture","doom_mark","doom","frost","poison","deflect","loot_burst","loot_land","break","time_stop","time_shatter","rush_slash","afterimage","clear_burst","rewind_step","flame_spin","gravity_well","gravity_burst","prism_guard","slam_mark","sky_slam","enemy_shatter","cross_slash","speed_lines"]
const DEFAULT_COLOR := Color("72e8ff")
const BOX_CACHE_CAP := 128
const PRIORITY_KINDS := ["time_stop","gravity_well","prism_guard"]
const PROTECTED_KINDS := ["time_stop","gravity_well","prism_guard","slam_mark","sky_slam"]
const DURATION := {"spear_thrust":.52,"spin":.68,"impact":.55,"static_shard":.36,"lightning":.65,"wave":.92,"rupture":.92,"doom_mark":1.12,"doom":.88,"frost":1.14,"poison":1.55,"deflect":.60,"loot_burst":1.25,"loot_land":.82,"break":.86,"time_stop":2.8,"time_shatter":1.05,"rush_slash":.54,"afterimage":.62,"clear_burst":1.2,"rewind_step":.62,"flame_spin":.46,"gravity_well":3.05,"gravity_burst":.90,"prism_guard":4.05,"slam_mark":.53,"sky_slam":.95,"enemy_shatter":.65,"cross_slash":.34,"speed_lines":.42}

@export_range(1,96) var max_effects: int = 32
@export var ground_height := .045
var frozen := false
var _live: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _serial := 0
var _evictions := 0
var _box_meshes: Dictionary = {}
var _boundary_meshes: Dictionary = {}


func _ready() -> void:
	_rng.randomize()


func play(kind: String, pos: Vector3, color: Color = DEFAULT_COLOR, direction: Vector3 = Vector3.FORWARD, effect_scale: float = 1.0) -> Node3D:
	if not kind in KINDS: return null
	while _live.size() >= maxi(1,max_effects):
		var victim := 0
		for i in _live.size():
			if not _live[i].kind in PROTECTED_KINDS:
				victim = i
				break
		var old: Dictionary = _live[victim]
		_live.remove_at(victim)
		_dispose(old)
		_evictions += 1
	var root := Node3D.new()
	root.name = "FX_%s_%d" % [kind,_serial]
	_serial += 1
	add_child(root)
	var heading := Vector3(direction.x,0,direction.z)
	if heading.length_squared() < .001: heading = Vector3.FORWARD
	var size_factor := clampf(effect_scale,.15,3.0)
	root.global_transform = Transform3D(Basis(Vector3.UP,atan2(-heading.x,-heading.z)).scaled(Vector3.ONE*size_factor),pos)
	root.set_meta("fx_kind",kind)
	root.set_meta("fx_duration",DURATION[kind])
	var record := {"node":root,"kind":kind,"age":0.0,"duration":float(DURATION[kind]),"parts":[],"particles":[],"color":color,"ground":(ground_height-pos.y)/size_factor}
	_live.append(record)
	match kind:
		"spear_thrust": _thrust(record)
		"spin": _spin(record)
		"impact": _impact(record)
		"static_shard": _static_shard(record)
		"lightning": _lightning(record)
		"wave", "rupture": _wave(record)
		"doom_mark": _doom_mark(record)
		"doom": _doom(record)
		"frost": _frost(record)
		"poison": _poison(record)
		"deflect": _deflect(record)
		"loot_burst": _loot_burst(record)
		"loot_land": _loot_land(record)
		"break": _break(record)
		"time_stop": _time_stop(record)
		"time_shatter": _time_shatter(record)
		"rush_slash": _rush_slash(record)
		"afterimage": _afterimage(record)
		"clear_burst": _clear_burst(record)
		"rewind_step": _rewind_step(record)
		"flame_spin": _flame_spin(record)
		"gravity_well": _gravity_well(record)
		"gravity_burst": _gravity_burst(record)
		"prism_guard": _prism_guard(record)
		"slam_mark": _slam_mark(record)
		"sky_slam": _sky_slam(record)
		"enemy_shatter": _enemy_shatter(record)
		"cross_slash": _cross_slash(record)
		"speed_lines": _speed_lines(record)
	_animate(record)
	return root


func set_effect_duration(node: Node3D, duration: float) -> bool:
	# Persistent ability fields follow their gameplay duration. Entry flashes and
	# burst particles keep their sharp timing; sustained geometry stretches.
	if not is_instance_valid(node) or not is_finite(duration) or duration <= 0: return false
	for record in _live:
		if record.node != node: continue
		if not record.kind in PRIORITY_KINDS: return false
		var target := clampf(duration,.1,30.0)
		var ratio := target/maxf(.001,float(record.duration))
		for part in record.parts:
			if float(part.duration) > .9:
				part.duration *= ratio
				part.delay *= ratio
		record.age *= ratio
		record.duration = target
		node.set_meta("fx_duration",target)
		_animate(record)
		return true
	return false


func set_frozen(value: bool) -> void:
	frozen = value
	for record in _live:
		for emitter in record.particles:
			if is_instance_valid(emitter): emitter.speed_scale = 0.0 if frozen else 1.0


func freeze(value: bool = true) -> void:
	set_frozen(value)


func resume() -> void:
	set_frozen(false)


func clear_all() -> void:
	for record in _live: _dispose(record)
	_live.clear()


func active_count() -> int:
	return _live.size()


func get_stats() -> Dictionary:
	var emitters := 0
	var parts := 0
	for record in _live:
		emitters += record.particles.size()
		parts += record.parts.size()
	return {"active":_live.size(),"parts":parts,"particle_emitters":emitters,"frozen":frozen,"spawned":_serial,"cap_evictions":_evictions,"cached_meshes":_box_meshes.size()}


func _process(delta: float) -> void:
	if frozen: return
	for i in range(_live.size()-1,-1,-1):
		var record: Dictionary = _live[i]
		if not is_instance_valid(record.node) or record.node.is_queued_for_deletion():
			_live.remove_at(i)
			continue
		record.age += maxf(0,delta)
		if record.age >= record.duration:
			_dispose(record)
			_live.remove_at(i)
		else: _animate(record)


func _dispose(record: Dictionary) -> void:
	if is_instance_valid(record.node):
		if record.node.get_parent() == self: remove_child(record.node)
		record.node.queue_free()


func _material(color: Color, additive: bool = true) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * .35
	return material


func _part(record: Dictionary, mesh: Mesh, pos: Vector3, color: Color, duration: float, delay: float = 0.0, additive: bool = true) -> Dictionary:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.material_override = _material(color,additive)
	record.node.add_child(node)
	node.position = pos
	var part := {"node":node,"material":node.material_override,"pos":pos,"delay":delay,"duration":duration,"start_scale":Vector3.ONE,"end_scale":Vector3.ONE,"velocity":Vector3.ZERO,"gravity":0.0,"spin":Vector3.ZERO,"alpha":color.a,"fade_power":1.3,"flicker":false}
	record.parts.append(part)
	return part


func _box(record: Dictionary, pos: Vector3, size: Vector3, color: Color, duration: float, delay: float = 0.0, additive: bool = true) -> Dictionary:
	var key := str(size)
	var mesh: BoxMesh
	if _box_meshes.has(key): mesh = _box_meshes[key]
	else:
		# Some impact rays have random lengths. Keep cached resources bounded too.
		if _box_meshes.size() >= BOX_CACHE_CAP: _box_meshes.erase(_box_meshes.keys()[0])
		mesh = BoxMesh.new(); mesh.size = size
		_box_meshes[key] = mesh
	return _part(record,mesh,pos,color,duration,delay,additive)


func _line(record: Dictionary, from: Vector3, to: Vector3, width: float, color: Color, duration: float, delay: float = 0.0) -> Dictionary:
	var distance := from.distance_to(to)
	var part := _box(record,(from+to)*.5,Vector3(width,width,maxf(.01,distance)),color,duration,delay)
	if distance > .001:
		var heading: Vector3 = record.node.global_basis*(to-from)
		var up := Vector3.FORWARD if absf(heading.normalized().dot(Vector3.UP)) > .98 else Vector3.UP
		part.node.look_at_from_position(part.node.global_position,part.node.global_position+heading,up)
	part.start_scale = Vector3(1,1,.35)
	part.end_scale = Vector3(.20,.20,1.08)
	return part


func _bolt(record: Dictionary, from: Vector3, to: Vector3, width: float, color: Color, duration: float, delay: float = 0.0) -> Dictionary:
	# Electrical segments and impacts must connect immediately, unlike growing thrusts.
	var part := _line(record,from,to,width,color,duration,delay)
	part.start_scale = Vector3(1,1,1.02)
	part.end_scale = Vector3(.25,.25,1.02)
	return part


func _disc(record: Dictionary, radius: float, color: Color, style: float, duration: float, delay: float = 0.0, ground: bool = true) -> Dictionary:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE * radius * 2.0
	var part := _part(record,mesh,Vector3(0,record.ground if ground else .06,0),color,duration,delay)
	var material := ShaderMaterial.new()
	material.shader = DISC
	material.set_shader_parameter("tint",color)
	material.set_shader_parameter("style",style)
	material.set_shader_parameter("opacity",color.a)
	part.node.material_override = material
	part.material = material
	part["shader"] = true
	part["rotate_rune"] = .5 if style == 1.0 else 0.0
	return part


func _arc(record: Dictionary, radius: float, thickness: float, angle_span: float, color: Color, duration: float, delay: float = 0.0) -> Dictionary:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 40
	for i in steps:
		for corner in [Vector2i(i,0),Vector2i(i+1,0),Vector2i(i,1),Vector2i(i+1,0),Vector2i(i+1,1),Vector2i(i,1)]:
			var u := float(corner.x)/steps
			var a := -angle_span*.5+angle_span*u
			var r: float = radius-thickness+thickness*corner.y
			surface.set_uv(Vector2(u,corner.y))
			surface.set_normal(Vector3.UP)
			surface.add_vertex(Vector3(sin(a)*r,0,-cos(a)*r))
	var part := _part(record,surface.commit(),Vector3.ZERO,color,duration,delay)
	var material := ShaderMaterial.new()
	material.shader = ARC
	material.set_shader_parameter("tint",color)
	material.set_shader_parameter("opacity",color.a)
	part.node.material_override = material
	part.material = material
	part["shader"] = true
	return part


func _range_boundary(record: Dictionary, radius: float, color: Color, duration: float) -> void:
	# This thin ground ring communicates gameplay reach; the ornamental inner
	# effect can remain compact. All callers use one of three fixed base radii.
	if not _boundary_meshes.has(radius):
		var mesh := TorusMesh.new()
		mesh.inner_radius = radius-.025
		mesh.outer_radius = radius+.025
		mesh.rings = 64
		mesh.ring_segments = 6
		_boundary_meshes[radius] = mesh
	var part := _part(record,_boundary_meshes[radius],Vector3(0,record.ground+.018,0),color,duration)
	part.fade_power = .16
	part.node.set_meta("gameplay_radius",radius)


func _column(record: Dictionary, radius: float, height: float, color: Color, duration: float, delay: float = 0.0) -> Dictionary:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius*.72; mesh.bottom_radius = radius
	mesh.height = height; mesh.radial_segments = 32
	mesh.cap_top = false; mesh.cap_bottom = false
	var part := _part(record,mesh,Vector3(0,height*.5,0),color,duration,delay)
	var material := ShaderMaterial.new()
	material.shader = COLUMN
	material.set_shader_parameter("tint",color)
	material.set_shader_parameter("opacity",color.a)
	part.node.material_override = material
	part.material = material
	part["shader"] = true
	return part


func _crystal(record: Dictionary, pos: Vector3, size: Vector3, color: Color, duration: float, delay: float = 0.0) -> Dictionary:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := [Vector3(-.5,-.22,0),Vector3(0,-.22,-.5),Vector3(.5,-.22,0),Vector3(0,-.22,.5)]
	for i in 4:
		for tip in [Vector3(0,.5,0),Vector3(0,-.5,0)]:
			var a: Vector3 = ring[i]
			var b: Vector3 = ring[(i+1)%4]
			var normal := (b-a).cross(tip-a).normalized()
			for point in [a,b,tip]:
				surface.set_normal(normal)
				surface.add_vertex(point*size)
	var part := _part(record,surface.commit(),pos,color,duration,delay,false)
	part.material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	part.material.roughness = .32
	part.material.metallic = .12
	return part


func _particles(record: Dictionary, count: int, color: Color, velocity: float, duration: float, spread: float = 180.0, gravity: float = -7.0, direction: Vector3 = Vector3.UP, size: Vector3 = Vector3(.065,.11,.065)) -> void:
	var emitter := CPUParticles3D.new()
	emitter.emitting = false
	emitter.amount = clampi(count,3,18 if preload("res://scripts/quality.gd").low() else 40)
	emitter.one_shot = true
	emitter.explosiveness = 1.0
	emitter.lifetime = duration
	emitter.lifetime_randomness = .22
	emitter.direction = direction
	emitter.spread = spread
	emitter.gravity = Vector3(0,gravity,0)
	emitter.initial_velocity_min = velocity*.45
	emitter.initial_velocity_max = velocity
	emitter.scale_amount_min = .45
	emitter.scale_amount_max = 1.4
	emitter.angular_velocity_min = -220
	emitter.angular_velocity_max = 220
	emitter.local_coords = true
	emitter.speed_scale = 0.0 if frozen else 1.0
	var mesh := BoxMesh.new()
	mesh.size = size * 1.4
	var material := _material(Color.WHITE,false)
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	emitter.mesh = mesh
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0,.18,.68,1.0])
	ramp.colors = PackedColorArray([color.lightened(.8),color,Color(color,.65),Color(color,0.0)])
	emitter.color_ramp = ramp
	var curve := Curve.new()
	curve.add_point(Vector2(0,.25)); curve.add_point(Vector2(.12,1)); curve.add_point(Vector2(1,.05))
	emitter.scale_amount_curve = curve
	record.node.add_child(emitter)
	record.particles.append(emitter)
	emitter.emitting = true
	emitter.restart()


func _ember_sprite(record: Dictionary, texture: Texture2D, pos: Vector3, size: Vector2, duration: float, opacity: float) -> Dictionary:
	var mesh := QuadMesh.new()
	mesh.size = size
	var layer := _part(record,mesh,pos,Color.WHITE,duration,0.0,false)
	var material := ShaderMaterial.new()
	material.shader = EMBER_SPRITE
	material.set_shader_parameter("atlas",texture)
	material.set_shader_parameter("opacity",opacity)
	layer.node.material_override = material
	layer.material = material
	layer["shader"] = true
	layer.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var camera := get_viewport().get_camera_3d()
	if camera != null: layer.node.look_at(camera.global_position,Vector3.UP)
	return layer


func _shards(record: Dictionary, count: int, color: Color, velocity: float, duration: float, delay: float = 0.0, upward: float = 1.8, gravity: float = -7.0) -> void:
	for i in count:
		var a := TAU*i/maxi(1,count)+_rng.randf_range(-.15,.15)
		var part := _box(record,Vector3.ZERO,Vector3(.065,.16,.065),color,duration,delay,false)
		part.velocity = Vector3(cos(a)*velocity*_rng.randf_range(.55,1),upward*_rng.randf_range(.6,1.2),sin(a)*velocity*_rng.randf_range(.55,1))
		part.gravity = gravity
		part.spin = Vector3(_rng.randf_range(-6,6),_rng.randf_range(-6,6),_rng.randf_range(-6,6))
		part.start_scale = Vector3.ONE * _rng.randf_range(.7,1.4)
		part.end_scale = Vector3.ONE*.1


func _animate(record: Dictionary) -> void:
	for part in record.parts:
		var node: MeshInstance3D = part.node
		var time: float = record.age-part.delay
		node.visible = time >= 0.0 and time < part.duration
		if not node.visible: continue
		var p := clampf(time/part.duration,0,1)
		var scale_hold := float(part.get("scale_hold",0.0))
		var motion_progress := clampf((p-scale_hold)/maxf(.001,1.0-scale_hold),0,1)
		var eased := 1.0-pow(1.0-motion_progress,2.0)
		node.position = part.pos + part.velocity*time + Vector3(0,.5*part.gravity*time*time,0)
		if part.has("orbit_radius"):
			var a: float = part.orbit_phase+time*part.orbit_speed
			node.position += Vector3(cos(a),0,sin(a))*part.orbit_radius*(1.0+p*float(part.get("orbit_expand",.7)))
		node.scale = part.start_scale.lerp(part.end_scale,eased)
		if not part.spin.is_zero_approx(): node.rotation = part.get("base_rotation",Vector3.ZERO)+part.spin*time
		if part.get("shader",false):
			part.material.set_shader_parameter("progress",p)
			if part.has("rotate_rune"): part.material.set_shader_parameter("rotation_offset",time*part.rotate_rune)
		else:
			var fade_hold := float(part.get("fade_hold",0.0))
			var fade_progress := clampf((p-fade_hold)/maxf(.001,1.0-fade_hold),0,1)
			var fade := pow(1.0-fade_progress,float(part.fade_power))
			if part.flicker: fade *= .45+.55*stepf(.0,sin(time*91.0))
			var color: Color = part.material.albedo_color
			color.a = float(part.alpha)*fade
			part.material.albedo_color = color


func stepf(edge: float, value: float) -> float:
	return 1.0 if value >= edge else 0.0


func _thrust(r: Dictionary) -> void:
	var c: Color = r.color
	_line(r,Vector3(0,0,.45),Vector3(0,0,-3.3),.082,Color("fff9e9"),.21)
	_line(r,Vector3(0,0,.10),Vector3(0,0,-3.15),.30,Color(c,.70),.29,.02)
	for side in [-1.0,1.0]:
		var p := _line(r,Vector3(side*.58,.05,.2),Vector3(side*.08,.05,-2.8),.064,c,.32)
		p.velocity = Vector3(0,0,-.8)
	var arc := _arc(r,.8,.31,PI*.8,Color(c,.95),.32)
	arc.pos = Vector3(0,0,-2.75)
	arc.node.rotation.x = PI*.5
	var tip := _crystal(r,Vector3(0,0,-2.75),Vector3(.25,1.1,.25),c.lightened(.7),.22)
	tip.node.rotation.x = PI*.5
	_particles(r,16,c,5.0,.42,19,-.7,Vector3.FORWARD,Vector3(.035,.035,.19))


func _spin(r: Dictionary) -> void:
	var c: Color = r.color
	for i in 3:
		var arc := _arc(r,2.35-i*.28,.72-i*.10,PI*1.4,Color(c,1.0-i*.16),.43+i*.05,i*.035)
		arc.pos.y = .05+i*.08
		arc.spin = Vector3(0,-11.0+i*2,0)
		arc["base_rotation"] = Vector3(0,i*.65,0)
	_disc(r,2.7,Color(c,.52),0,.55,.02)
	_particles(r,26,c,4.1,.57,180,-1.0,Vector3.UP,Vector3(.055,.055,.13))


func _impact(r: Dictionary) -> void:
	var c: Color = r.color
	var core := _box(r,Vector3.ZERO,Vector3(.32,.32,.32),Color("fff8df"),.18)
	core.start_scale = Vector3.ONE*1.7; core.end_scale = Vector3.ONE*.1
	for i in 7:
		var a := TAU*i/7.0
		var end := Vector3(cos(a),sin(a)*.65,-.10)*_rng.randf_range(.7,1.25)
		_line(r,end*.12,end,.064,Color(c,.95),.27)
	_disc(r,1.05,Color(c,.6),0,.40)
	var slash := _arc(r,.73,.20,PI*.92,Color(c,.8),.20)
	slash.node.rotation = Vector3(PI*.42,0,.35)
	for i in 4:
		var chip := _box(r,Vector3.ZERO,Vector3(.11,.085,.13),Color("91a8b8"),.34,0,false)
		var a := float(i)*TAU/4.0
		chip.velocity = Vector3(cos(a)*2.4,1.4,sin(a)*2.4)
		chip.gravity = -7.0; chip.spin = Vector3(3,a,4)
	_particles(r,20,c,4.0,.48,180,-8)


func _static_shard(r: Dictionary) -> void:
	# A brief rim glint and a few chips, kept dim enough for the darker rooms.
	var rim := Color("bad6dc",.82)
	_disc(r,.42,Color(r.color,.25),0,.24)
	for side in [-1.0,1.0]:
		var edge := _line(r,Vector3(side*.35,-.42,-.025),Vector3(side*.46,.42,-.025),.070,rim,.19)
		edge.start_scale = Vector3.ONE
		edge.end_scale = Vector3(.35,.35,.72)
		var corner := _line(r,Vector3(side*.46,.42,-.025),Vector3(side*.12,.53,-.025),.055,Color(r.color,.78),.17)
		corner.start_scale = Vector3.ONE
	for i in 5:
		var a := TAU*float(i)/5.0+_rng.randf_range(-.22,.22)
		var chip := _crystal(r,Vector3(cos(a)*.30,sin(a)*.26,0),Vector3(.12,.21,.07),Color(r.color,.78),.32)
		chip.velocity = Vector3(cos(a)*1.5,sin(a)*1.1+.45,-.6)
		chip.gravity = -3.4
		chip.spin = Vector3(4,3,5)


func _lightning(r: Dictionary) -> void:
	var c: Color = r.color
	var points: Array[Vector3] = [Vector3(.22,3.8,0),Vector3(-.34,2.8,.08),Vector3(.35,2.05,-.10),Vector3(-.23,1.2,.04),Vector3.ZERO]
	for i in range(points.size()-1):
		var glow := _bolt(r,points[i],points[i+1],.24,Color(c,.72),.35,i*.009)
		glow.flicker = true
		var core := _bolt(r,points[i],points[i+1],.070,Color("f8fcff"),.29,i*.009)
		core.flicker = true
	for side in [-1.0,1.0]:
		_bolt(r,Vector3(0,2.1,0),Vector3(side*.8,1.7,-.25),.048,c,.25,.04)
		_bolt(r,Vector3(side*.8,1.7,-.25),Vector3(side*.65,1.1,-.42),.042,c,.25,.04)
	_disc(r,1.65,Color(c,.7),3,.55,.04)
	_particles(r,22,c,4.6,.52,90,-9)


func _wave(r: Dictionary) -> void:
	var c: Color = r.color
	_disc(r,3.4,c,2,.75)
	_disc(r,2.8,Color(c,.42),0,.70,.08)
	var ring := _arc(r,2.8,.09,TAU,Color(c,.6),.64,.03)
	ring.start_scale = Vector3.ONE*.18; ring.end_scale = Vector3(1.2,.4,1.2)
	ring.pos.y = -.1
	_shards(r,16,c.lightened(.2),3.5,.70,.0,.7,-3)
	_particles(r,25,c,4.4,.73,180,-.2,Vector3.UP,Vector3(.04,.11,.04))


func _doom_mark(r: Dictionary) -> void:
	var c: Color = r.color
	_disc(r,1.55,Color(c,.72),1,1.10)
	_disc(r,1.15,Color(c,.32),3,1.08)
	for i in 6:
		var a := TAU*i/6
		var marker := _box(r,Vector3(cos(a)*1.1,r.ground+.05,sin(a)*1.1),Vector3(.11,.04,.28),Color(c,.76),1.10)
		marker.node.rotation.y = -a
		marker.velocity = Vector3(-cos(a)*.32,0,-sin(a)*.32)
		marker.fade_power = .35


func _doom(r: Dictionary) -> void:
	var c: Color = r.color
	_disc(r,2.15,Color(c,.85),1,.75)
	_disc(r,1.65,Color(c,.4),3,.64)
	var pillar := _bolt(r,Vector3(0,4.2,0),Vector3(0,.05,0),.36,Color(c,.9),.30)
	pillar.flicker = true
	_bolt(r,Vector3(0,3.9,0),Vector3.ZERO,.095,Color("fff2dd"),.25)
	_column(r,.62,3.8,Color(c,.8),.43)
	_disc(r,2.7,c,2,.65)
	for i in 6:
		var a := TAU*i/6
		var p := _crystal(r,Vector3(cos(a)*.7,.35,sin(a)*.7),Vector3(.17,.66,.17),c,.48)
		p.velocity = Vector3(cos(a)*2.2,2.0,sin(a)*2.2); p.gravity = -8
		p.spin = Vector3(0,3.0,.5)
	_shards(r,18,c,3.5,.65,.0,2.0,-9)
	_particles(r,20,c.lightened(.3),4.2,.65,135,-8)


func _frost(r: Dictionary) -> void:
	var c: Color = r.color
	_disc(r,2.2,Color(c,.75),3,.92)
	_disc(r,2.65,Color(c,.38),0,.82,.04)
	for i in 7:
		var a := TAU*i/7
		var p := _crystal(r,Vector3(cos(a)*.85,-.05,sin(a)*.85),Vector3(.30,1.2+float(i%3)*.18,.30),c.lightened(.25),.85,i*.025)
		p.node.rotation = Vector3(.24*cos(a),a,.24*sin(a))
		p.pos.y = .38
		p.start_scale = Vector3(.9,.12,.9); p.end_scale = Vector3(.55,1.45,.55)
		p.fade_power = .65
	_particles(r,30,c.lightened(.4),2.9,1.0,180,-1.4,Vector3.UP,Vector3(.07,.07,.07))


func _poison(r: Dictionary) -> void:
	var c: Color = r.color
	_disc(r,2.1,Color(c,.60),1,1.35)
	_disc(r,1.6,Color(c,.25),0,1.2,.12)
	_column(r,.85,1.55,Color(c,.45),1.25,.05)
	for i in 10:
		var a := i*2.4
		var p := _box(r,Vector3(0,.1,0),Vector3(.13,.13,.13),Color(c,.75),1.1,float(i%4)*.08,false)
		p["orbit_radius"] = .45+float(i%3)*.23
		p["orbit_phase"] = a; p["orbit_speed"] = 1.1
		p.velocity = Vector3(0,.65+float(i%2)*.25,0)
		p.spin = Vector3(1.4,2.0,.4)
		p.start_scale = Vector3.ONE*.35; p.end_scale = Vector3.ONE*1.2
	_particles(r,16,c,1.0,1.25,70,.5,Vector3.UP,Vector3(.055,.055,.055))


func _deflect(r: Dictionary) -> void:
	var c: Color = r.color
	for i in 2:
		var arc := _arc(r,1.25+i*.18,.12,PI*1.15,Color(c,.95-i*.3),.37+i*.08)
		arc.node.rotation.x = PI*.5
		arc.start_scale = Vector3.ONE*.65; arc.end_scale = Vector3.ONE*1.25
	_line(r,Vector3(-.65,0,-.15),Vector3(.65,0,-.15),.04,Color.WHITE,.14)
	_line(r,Vector3(0,-.65,-.15),Vector3(0,.65,-.15),.04,Color.WHITE,.14)
	_particles(r,22,c,5.1,.46,38,-2,Vector3.FORWARD,Vector3(.04,.04,.17))


func _loot_burst(r: Dictionary) -> void:
	var c: Color = r.color
	_disc(r,1.85,Color(c,.8),1,1.0)
	_disc(r,2.55,Color(c,.6),0,.75)
	_column(r,.65,4.1,Color(c,.85),1.1)
	_line(r,Vector3(0,.15,0),Vector3(0,3.8,0),.045,c.lightened(.8),.65)
	for i in 12:
		var p := _box(r,Vector3(0,.15,0),Vector3(.08,.20,.08),c.lightened(.25),.95,i*.012)
		p["orbit_radius"] = .45+float(i%3)*.13
		p["orbit_phase"] = float(i)*2.4; p["orbit_speed"] = 3.0
		p.velocity = Vector3(0,1.2+float(i%4)*.48,0)
		p.spin = Vector3(.6,3,0)
	_particles(r,24,c,3.1,.95,35,-2,Vector3.UP,Vector3(.05,.12,.05))


func _loot_land(r: Dictionary) -> void:
	var c: Color = r.color
	_disc(r,1.35,Color(c,.75),1,.70)
	_disc(r,1.95,Color(c,.5),0,.60)
	for i in 4:
		var a := TAU*i/4
		var p := _box(r,Vector3(cos(a)*1.05,.18,sin(a)*1.05),Vector3(.12,.12,.34),c,.55,.025*i)
		p.node.rotation.y = -a
		p.velocity = Vector3(-cos(a)*1.0,.35,-sin(a)*1.0)
		p.end_scale = Vector3.ONE*.2
	var gem := _box(r,Vector3(0,.5,0),Vector3(.22,.22,.22),c.lightened(.6),.46)
	gem.spin = Vector3(1,3,1); gem.velocity = Vector3(0,.9,0)
	_particles(r,12,c,2.1,.63,100,-6)


func _break(r: Dictionary) -> void:
	var c: Color = r.color
	_disc(r,1.65,Color(c,.45),0,.48)
	_shards(r,20,c.darkened(.15),3.6,.72,.0,2.6,-10)
	_particles(r,28,c.lightened(.4),4.4,.69,115,-11,Vector3.UP,Vector3(.10,.12,.10))
	var core := _box(r,Vector3(0,.15,0),Vector3(.24,.24,.24),c.lightened(.8),.12)
	core.end_scale = Vector3.ONE*.05


func _time_stop(r: Dictionary) -> void:
	var c: Color = r.color
	_disc(r,4.0,Color(c,.88),4,2.6)
	_disc(r,4.35,Color(c,.45),0,.70)
	var sphere := SphereMesh.new()
	sphere.radius = 3.45; sphere.height = 6.9
	sphere.radial_segments = 48; sphere.rings = 24
	var shell := _part(r,sphere,Vector3(0,.45,0),c,2.65)
	var mat := ShaderMaterial.new(); mat.shader = TIME_SHELL
	mat.set_shader_parameter("tint",c); mat.set_shader_parameter("opacity",.8)
	shell.node.material_override = mat; shell.material = mat; shell["shader"] = true
	shell.start_scale = Vector3.ONE*.60; shell.end_scale = Vector3.ONE*1.02
	for i in 3:
		var arc := _arc(r,3.4,.055,PI*1.42,Color(c,.47),2.45,i*.025)
		arc.pos.y = .4
		arc.node.rotation = Vector3(.9+i*.5,i*1.9,.3)
		arc.start_scale = Vector3.ONE*.78; arc.end_scale = Vector3.ONE
	for i in 12:
		var a := TAU*i/12.0
		var p := _box(r,Vector3(sin(a)*3.55,r.ground+.025,cos(a)*3.55),Vector3(.065,.04,.31 if i%3==0 else .16),c.lightened(.35),2.5)
		p.node.rotation.y = a
		p.fade_power = .4
	for endpoint in [Vector3(.75,0,-2.7),Vector3(1.7,0,.6)]:
		var hand := _bolt(r,Vector3(0,r.ground+.04,0),endpoint+Vector3(0,r.ground+.04,0),.045,c.lightened(.55),2.5)
		hand.fade_power = .45
	for i in 12:
		var a := i*2.4
		var shard := _box(r,Vector3(sin(a)*2.8,.35+float(i%4)*.4,cos(a)*2.8),Vector3(.08,.22,.08),Color(c,.65),2.35)
		shard.node.rotation = Vector3(i*.3,a,.6)
		shard.fade_power = .45


func _time_shatter(r: Dictionary) -> void:
	var c: Color = r.color
	_disc(r,4.0,Color(c,.92),2,.7)
	_disc(r,3.5,Color(c,.5),4,.55)
	for i in 24:
		var a := TAU*i/24.0
		var p := _crystal(r,Vector3(cos(a)*1.5,.35+float(i%3)*.6,sin(a)*1.5),Vector3(.13,.55,.09),c.lightened(.25),.85)
		p.velocity = Vector3(cos(a)*3.2,1.6,sin(a)*3.2)
		p.gravity = -3.0; p.spin = Vector3(2.1,i*.3,.9)
		p.start_scale = Vector3.ONE; p.end_scale = Vector3.ONE*.14
	_particles(r,30,c,5.0,.85,180,-3,Vector3.UP,Vector3(.06,.16,.035))


func _rush_slash(r: Dictionary) -> void:
	var c: Color = r.color
	for i in 3:
		var slash := _arc(r,2.9-i*.16,.52-i*.10,PI*.8,Color(c,1.0-i*.25),.25+i*.055,i*.015)
		slash.pos = Vector3(-.2*i,.06+i*.09,-.4)
		slash.node.rotation.y = -.28+i*.16
		slash.start_scale = Vector3(.80,1,1.75)
		slash.end_scale = Vector3(.86,1,2.1)
		slash.velocity = Vector3(0,0,-2.1)
	_bolt(r,Vector3(.05,.02,.9),Vector3(0,.02,-5.8),.07,c.lightened(.8),.17)
	for side in [-1.,1.]:
		_line(r,Vector3(side*.56,.0,1.0),Vector3(side*.12,.0,-4.3),.06,Color(c,.7),.27)
	_particles(r,24,c,8.2,.45,12,-.2,Vector3.BACK,Vector3(.04,.04,.24))
	_disc(r,1.3,Color(c,.25),0,.30)


## Two crossing blade strokes snap across the struck enemy, an X that reads at
## any camera angle; a hot core and a short spark spray sell the cut.
func _cross_slash(r: Dictionary) -> void:
	var c: Color = r.color
	var tilt := _rng.randf_range(-.35,.35)
	for k in 2:
		var angle := tilt+(PI*.25 if k == 0 else -PI*.25)
		var axis := Vector3(cos(angle),sin(angle)*.55,sin(angle)*.35).normalized()
		var stroke := _line(r,-axis*1.25,axis*1.25,.11,Color(c.lightened(.55),.95),.22,k*.035)
		stroke.start_scale = Vector3(1.6,1.6,.05); stroke.end_scale = Vector3(.12,.12,1.15)
		var glow := _line(r,-axis*1.45,axis*1.45,.26,Color(c,.42),.28,k*.035)
		glow.start_scale = Vector3(1.0,1.0,.05); glow.end_scale = Vector3(.25,.25,1.2)
	var core := _box(r,Vector3.ZERO,Vector3(.34,.34,.34),Color(1,1,1,.95),.12)
	core.start_scale = Vector3.ONE*1.6; core.end_scale = Vector3.ONE*.1
	_disc(r,.95,Color(c,.4),0,.24,0,false).end_scale = Vector3.ONE*1.8
	_particles(r,10,c,6.5,.26,160,-4.0,Vector3.UP,Vector3(.035,.035,.18))

## Rush streaks: long thin lines stretched along the dash, offset around the
## body silhouette and staggered so the trail tears past like wind.
func _speed_lines(r: Dictionary) -> void:
	var c: Color = r.color
	for i in 9:
		var lateral := _rng.randf_range(-1.05,1.05)
		var height := _rng.randf_range(.15,1.65)
		var length := _rng.randf_range(2.2,4.8)
		var back := _rng.randf_range(.2,1.4)
		var from := Vector3(lateral,height,back)
		var to := Vector3(lateral*.8,height,back+length)
		var width := .035 if i % 3 else .07
		var line := _line(r,from,to,width,Color(c.lightened(.35) if i % 2 else c,.85),_rng.randf_range(.18,.34),i*.012)
		line.start_scale = Vector3(1,1,.15); line.end_scale = Vector3(.1,.1,1.25)
	var sheet := _disc(r,1.25,Color(c,.22),0,.26)
	sheet.end_scale = Vector3(.4,1,2.6)
	_box(r,Vector3(0,.8,.9),Vector3(.9,1.3,.03),Color(c,.25),.2).end_scale = Vector3(.2,1,1)

func _afterimage(r: Dictionary) -> void:
	var c: Color = r.color
	var body := _box(r,Vector3(0,.70,0),Vector3(1.02,.98,.98),Color(c,.7),.58)
	var mat := ShaderMaterial.new(); mat.shader = ECHO
	mat.set_shader_parameter("tint",c); mat.set_shader_parameter("opacity",.82)
	body.node.material_override = mat; body.material = mat; body["shader"] = true
	body.start_scale = Vector3.ONE; body.end_scale = Vector3(1.02,.95,1.02)
	var panel := _box(r,Vector3(0,.73,-.51),Vector3(.84,.47,.025),Color(c,.13),.50)
	panel.fade_power = 1.7
	for side in [-1.,1.]:
		_box(r,Vector3(side*.19,.79,-.54),Vector3(.145,.185,.027),c.lightened(.7),.43)
	for y in [.22,1.18]:
		_line(r,Vector3(-.47,y,-.47),Vector3(.47,y,-.47),.024,Color(c,.8),.48)


func _clear_burst(r: Dictionary) -> void:
	var c: Color = r.color
	_disc(r,4.1,Color(c,.8),2,.78)
	_disc(r,3.6,Color(c,.5),0,.66,.04)
	for i in 36:
		var angle := TAU*i/36.0+_rng.randf_range(-.1,.1)
		var size := .13+float(i%4)*.045
		var color := c.lightened(.75) if i%3==0 else c
		var part := _box(r,Vector3(0,.35,0),Vector3(size,size*(.8+float(i%2)*.8),size),color,1.02,0.0,false)
		var speed := _rng.randf_range(2.8,6.0)
		part.velocity = Vector3(cos(angle)*speed,_rng.randf_range(2.5,5.0),sin(angle)*speed)
		part.gravity = -10.0; part.spin = Vector3(2.0,angle,3.0)
		part.end_scale = Vector3.ONE*.18
	_particles(r,32,c.lightened(.5),6.2,.90,140,-9.0,Vector3.UP,Vector3(.09,.15,.09))


func _rewind_step(r: Dictionary) -> void:
	_afterimage(r)
	var c: Color = r.color
	for i in 2:
		var arc := _arc(r,1.15,.10,PI*1.5,Color(c,.8),.32,i*.025)
		arc.pos.y = .7
		arc.node.rotation = Vector3(PI*.5,i*PI*.5,.45)
		arc.start_scale = Vector3.ONE*.9; arc.end_scale = Vector3.ONE*.35
	_disc(r,1.75,Color(c,.7),4,.4)
	_particles(r,14,c,3.5,.42,70,0.0,Vector3.UP,Vector3(.035,.14,.035))


func _flame_spin(r: Dictionary) -> void:
	var c: Color = r.color
	_range_boundary(r,4.1,Color(c,.30),.43)
	var first: int = r.parts.size()
	_ember_sprite(r,EMBER_FLAME_STRIP,Vector3(0,2.25,0),Vector2(10.5,6.0),.43,.86)
	for i in 3:
		var arc := _arc(r,2.2-float(i)*.27,.45,PI*1.4,Color(c,1.0-float(i)*.22),.24+i*.025,i*.012)
		arc.pos.y = .18+float(i)*.10
		arc.spin = Vector3(0,-15.0+i*1.8,0)
		arc["base_rotation"] = Vector3(0,float(i)*1.4,0)
	for i in 6:
		var a := TAU*i/6.0
		var spark := _crystal(r,Vector3(cos(a)*1.5,.35,sin(a)*1.5),Vector3(.12,.48,.12),Color("ffd384"),.30)
		spark.velocity = Vector3(cos(a)*2.0,1.0,sin(a)*2.0); spark.gravity = -3.0
	_disc(r,2.35,Color(c,.43),0,.35)
	_particles(r,18,c.lightened(.25),4.6,.39,160,-4.0)
	_scale_decoration(r,first,4.1/3.6)


func _gravity_well(r: Dictionary) -> void:
	var c: Color = r.color
	_range_boundary(r,4.8,Color(c,.43),3.04)
	var first: int = r.parts.size()
	var mesh := PlaneMesh.new(); mesh.size = Vector2.ONE*6.3
	var field := _part(r,mesh,Vector3(0,r.ground,0),c,3.04)
	var mat := ShaderMaterial.new(); mat.shader = GRAVITY
	mat.set_shader_parameter("tint",c)
	field.node.material_override = mat; field.material = mat; field["shader"] = true
	for i in 2:
		var arc := _arc(r,2.8-float(i)*.3,.045,PI*1.35,Color(c,.37),3.0)
		arc.pos.y = .07+float(i)*.04; arc.spin = Vector3(0,-1.3-float(i)*.4,0)
		arc["base_rotation"] = Vector3(0,float(i)*PI,0)
	for i in 8:
		var p := _box(r,Vector3(0,.14+float(i%2)*.10,0),Vector3(.08,.14,.08),Color(c,.7),3.0)
		p["orbit_radius"] = 1.7+float(i%3)*.25; p["orbit_phase"] = float(i)*TAU/8
		p["orbit_speed"] = -1.8; p["orbit_expand"] = -.25
		p.spin = Vector3(0,2.0,.5); p.fade_power = .18
	_scale_decoration(r,first,4.8/4.2)


func _gravity_burst(r: Dictionary) -> void:
	var c: Color = r.color
	_range_boundary(r,4.8,Color(c,.35),.20)
	var first: int = r.parts.size()
	var ring := _arc(r,3.1,.12,TAU,Color(c,.9),.16)
	ring.pos.y = .08; ring.start_scale = Vector3.ONE; ring.end_scale = Vector3.ONE*.05
	_disc(r,3.2,c,2,.65,.12)
	var core := _box(r,Vector3(0,.5,0),Vector3(.35,.35,.35),c.lightened(.85),.16,.12)
	core.end_scale = Vector3.ONE*.08
	_shards(r,22,c.lightened(.15),4.0,.65,.12,2.5,-6.0)
	_particles(r,18,c,3.5,.64,130,-6.0)
	_scale_decoration(r,first,4.8/4.2)


func _prism_guard(r: Dictionary) -> void:
	var c: Color = r.color
	_range_boundary(r,2.3,Color(c,.28),4.0)
	var first: int = r.parts.size()
	for i in 6:
		var a := TAU*float(i)/6.0
		var mesh := QuadMesh.new(); mesh.size = Vector2(.86,1.25)
		var panel := _part(r,mesh,Vector3(0,.85,0),c,4.0)
		var mat := ShaderMaterial.new(); mat.shader = GUARD; mat.set_shader_parameter("tint",c)
		panel.node.material_override = mat; panel.material = mat; panel["shader"] = true
		panel["orbit_radius"] = 1.18; panel["orbit_phase"] = a
		panel["orbit_speed"] = .35; panel["orbit_expand"] = 0.0
		panel.spin = Vector3(0,-.35,0); panel["base_rotation"] = Vector3(0,PI*.5-a,0)
	for y in [.18,1.52]:
		var ring := _arc(r,1.25,.028,TAU,Color(c,.45),4.0)
		ring.pos.y = y
	_scale_decoration(r,first,2.3/2.0)


func _scale_decoration(r: Dictionary, first: int, factor: float) -> void:
	# Grow existing authored layers with the revised base range. The exact
	# gameplay boundary is created beforehand and must not be scaled twice.
	for i in range(first,r.parts.size()):
		var p: Dictionary = r.parts[i]
		var on_ground := is_equal_approx(float(p.pos.y),float(r.ground))
		p.pos *= factor; p.velocity *= factor; p.gravity *= factor
		if on_ground: p.pos.y = r.ground
		p.start_scale *= factor; p.end_scale *= factor
		if p.has("orbit_radius"): p.orbit_radius *= factor
	for emitter in r.particles: emitter.scale *= factor


func _slam_disc(r: Dictionary, warning: bool, duration: float) -> Dictionary:
	var mesh := PlaneMesh.new(); mesh.size = Vector2.ONE*9.6
	var p := _part(r,mesh,Vector3(0,r.ground+.014,0),r.color,duration)
	var material := ShaderMaterial.new(); material.shader = SLAM
	material.set_shader_parameter("tint",r.color)
	material.set_shader_parameter("warning",1.0 if warning else 0.0)
	material.set_shader_parameter("opacity",.80 if warning else .95)
	p.node.material_override = material; p.material = material; p["shader"] = true
	return p


func _slam_mark(r: Dictionary) -> void:
	var c: Color = r.color
	_range_boundary(r,4.8,Color(c,.42),.53)
	_slam_disc(r,true,.53)
	# Short inward arrows establish the locked landing point, without an early hit.
	for i in 4:
		var a := float(i)*PI*.5+PI*.25
		var dir := Vector3(cos(a),0,sin(a))
		var arrow := _arc(r,.32,.085,PI*.65,Color(c,.72),.53)
		arrow.pos = dir*3.4+Vector3(0,r.ground+.025,0)
		arrow.velocity = -dir*2.5
		arrow.node.rotation.y = -a-PI*.5


func _sky_slam(r: Dictionary) -> void:
	var c: Color = r.color
	_range_boundary(r,4.8,Color(c,.45),.34)
	_slam_disc(r,false,.94)
	_ember_sprite(r,EMBER_SLAM_STRIP,Vector3(0,4.8,0),Vector2(10.5,10.5),.85,.94)
	# Hold the vertical mass through the first .20 seconds. A rapidly shrinking
	# transparent cylinder used to disappear before the impact's visible peak.
	for layer in 2:
		var mesh := CylinderMesh.new()
		mesh.top_radius = .14 if layer == 0 else .46
		mesh.bottom_radius = .78 if layer == 0 else 1.16
		mesh.height = 4.8 if layer == 0 else 3.7
		mesh.radial_segments = 8
		var pillar := _part(r,mesh,Vector3(0,mesh.height*.5,0),Color("ff8a34"),.38+layer*.05)
		var mat := ShaderMaterial.new(); mat.shader = SLAM_COLUMN
		mat.set_shader_parameter("tint",Color("ff9a45") if layer == 0 else Color("ff6926"))
		mat.set_shader_parameter("opacity",.95 if layer == 0 else .32)
		pillar.node.material_override = mat; pillar.material = mat; pillar["shader"] = true
		pillar["scale_hold"] = .52
		pillar.end_scale = Vector3(1.45,.68,1.45)
		pillar.node.rotation.y = layer*PI*.125
	var core := _box(r,Vector3(0,2.1,0),Vector3(.38,4.2,.38),Color("fff2c1"),.34)
	core["scale_hold"] = .58; core["fade_hold"] = .57
	core.end_scale = Vector3(1.4,.12,1.4); core.fade_power = .8
	for i in 5:
		var a := TAU*i/5.0
		var flame := _crystal(r,Vector3(cos(a)*.62,1.25,sin(a)*.62),Vector3(.32,2.8,.42),Color("ffb15c"),.39)
		flame.node.rotation = Vector3(sin(a)*.24,a,cos(a)*.24)
		flame["scale_hold"] = .46; flame["fade_hold"] = .38
		flame.end_scale = Vector3(.5,.15,.5)
	for i in 3:
		var ring := _arc(r,4.65-i*.72,.25+i*.10,PI*1.68,Color(c,.83-i*.18),.44+i*.13,i*.03)
		ring.pos.y = r.ground+.025+i*.018
		ring.start_scale = Vector3(.15,1,.15); ring.end_scale = Vector3.ONE
		ring.spin = Vector3(0,1.3-i*.9,0); ring["base_rotation"] = Vector3(0,i*2.2,0)
	for i in 24:
		var a := TAU*float(i)/24.0+_rng.randf_range(-.20,.20)
		var outer := i%3 == 0
		var color := Color("6b8295") if outer else Color("ff9e43")
		var size: Vector3 = [Vector3(.46,.27,.52),Vector3(.24,.44,.28),Vector3(.32,.18,.39),Vector3(.16,.29,.22)][i%4]
		var distance := _rng.randf_range(.25,.85)
		var speed := _rng.randf_range(3.6,6.0)
		var piece := _box(r,Vector3(cos(a)*distance,.12,sin(a)*distance),size,color,.78+float(i%3)*.065,0,false)
		piece.velocity = Vector3(cos(a)*speed,4.0+float(i%5)*.65,sin(a)*speed)
		piece.gravity = -16.0; piece.spin = Vector3(3.5+float(i%4),a,3.0+float(i%3))
		piece["scale_hold"] = .26; piece["fade_hold"] = .16
		piece.start_scale = Vector3.ONE; piece.end_scale = Vector3.ONE*.20
		piece.fade_power = .60
		if outer:
			piece.material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			piece.material.metallic = .6; piece.material.roughness = .34
	_particles(r,30,Color("ffb562"),6.8,.83,85,-14.0,Vector3.UP,Vector3(.11,.16,.11))


func _enemy_shatter(r: Dictionary) -> void:
	var c: Color = r.color
	var core := _box(r,Vector3(0,.45,0),Vector3(.34,.34,.34),Color("fff0c4"),.12)
	core.start_scale = Vector3.ONE*1.6; core.end_scale = Vector3.ONE*.08
	_disc(r,1.7,Color(c,.52),2,.48)
	var cut := _arc(r,1.15,.16,PI*1.35,Color("ffd19b"),.24)
	cut.pos.y = .5; cut.node.rotation.x = PI*.28
	for i in 16:
		var a := TAU*float(i)/16.0
		var hot := i%4 == 0
		var metal := Color("7298ae").lerp(c,.2)
		var p := _box(r,Vector3(cos(a)*.16,.45+float(i%3)*.12,sin(a)*.16),Vector3(.29,.25,.35) if not hot else Vector3(.15,.19,.15),Color("ffc784") if hot else metal,.60,0,false)
		p.velocity = Vector3(cos(a)*(3.8 if hot else 2.7),2.2+float(i%3)*.6,sin(a)*(3.8 if hot else 2.7))
		p.gravity = -11.0; p.spin = Vector3(4.5,a*2,3.0)
		p["scale_hold"] = .22; p["fade_hold"] = .12
		p.end_scale = Vector3.ONE*.12; p.fade_power = .4
		if not hot:
			p.material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			p.material.metallic = .5; p.material.roughness = .32
	_particles(r,18,Color("ffd195"),4.2,.56,120,-9.0,Vector3.UP,Vector3(.065,.075,.065))
