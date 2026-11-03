extends RefCounted
## Hades-style room-clear reward.
## 1. Clearing a room triggers a short world freeze (no CRT): actors, projectiles
##    and VFX hold still while the colour grade cools.
## 2. A blessing may then drop (chance per room kind, with pity). It falls from
##    the sky inside a rainbow light column, hangs just above the floor for a
##    beat of time stop, then slams down with a shockwave.
## 3. The player walks up and presses E. The blessing is absorbed, a full-screen
##    space wave ripples out and the floor slabs ripple with it, then the normal
##    three-choice blessing screen opens.

const BEAM_SHADER = preload("res://assets/boon_beam.gdshader")
const RING_SHADER = preload("res://assets/boon_ring.gdshader")
const CORE_SHADER = preload("res://assets/boon_core.gdshader")

const CLEAR_FREEZE := .42
const CLEAR_FREEZE_REDUCED := .24
const DROP_DELAY := .16
const FALL_HEIGHT := 16.0
const SKY_TOP := 24.0
const HANG_HEIGHT := 2.35
const HANG_DIP := .4
const HANG_TIME := .3
const SLAM_FLOOR := .82
const REST_HEIGHT := 1.25
const LAND_TIME := .36
const PICKUP_RADIUS := 2.1
const ABSORB_TIME := .42
const OPEN_DELAY := .62
const STAND_HEIGHT := 6.5
## Base drop chance per cleared room kind. Every room without a drop adds PITY.
const CHANCE := {"combat":.55,"elite":1.0,"boss":1.0,"stage":1.0}
const PITY := .3

var g
var freeze_left := 0.0
var drops: Array = []
var bursts: Array = []
var pending_open := -1.0
var dry_rooms := 0
var collected := 0
var _queued: Array = []
var _hang_amount := 0.0
var _core_mesh: BoxMesh
var _shard_mesh: BoxMesh
var _beam_mesh: CylinderMesh
var _spark_mesh: BoxMesh

func _init(controller) -> void:
	g = controller
	_core_mesh = BoxMesh.new(); _core_mesh.size = Vector3.ONE*.52
	_shard_mesh = BoxMesh.new(); _shard_mesh.size = Vector3(.1,.22,.1)
	_beam_mesh = CylinderMesh.new()
	_beam_mesh.height = 1.0; _beam_mesh.top_radius = .3; _beam_mesh.bottom_radius = .42
	_beam_mesh.radial_segments = 20; _beam_mesh.cap_top = false; _beam_mesh.cap_bottom = false
	_spark_mesh = BoxMesh.new(); _spark_mesh.size = Vector3.ONE*.12
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.vertex_color_use_as_albedo = true
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spark_mesh.material = spark_mat

## Per-floor cleanup (actors are freed by the controller).
func reset() -> void:
	for d in drops:
		if is_instance_valid(d.root): d.root.queue_free()
	for b in bursts:
		if is_instance_valid(b.node): b.node.queue_free()
	drops.clear(); bursts.clear(); _queued.clear()
	freeze_left = 0.0; pending_open = -1.0; _hang_amount = 0.0

## Per-expedition cleanup.
func reset_run() -> void:
	reset()
	dry_rooms = 0; collected = 0

func is_freezing() -> bool:
	return freeze_left > 0.0

## 0..1 visual time-stop strength for the world tint and colour grade.
func stop_amount() -> float:
	return 1.0 if freeze_left > 0.0 else _hang_amount

func on_room_cleared(center: Vector3, kind: String) -> void:
	if not center.is_finite(): return
	var hold := CLEAR_FREEZE_REDUCED if g.motion_reduced else CLEAR_FREEZE
	freeze_left = maxf(freeze_left,hold)
	_queued.append({"pos":center,"kind":kind,"wait":hold+DROP_DELAY})
	g.sound.play("tick",-14,.55)
	g.sound.play("bass",-15,.8)

func tick(delta: float) -> void:
	freeze_left = maxf(0.0,freeze_left-delta)
	for i in range(_queued.size()-1,-1,-1):
		var q: Dictionary = _queued[i]
		q.wait -= delta
		if q.wait <= 0.0:
			_queued.remove_at(i)
			_roll(q)
	_hang_amount = 0.0
	for i in range(drops.size()-1,-1,-1):
		_tick_drop(drops[i],delta)
	for i in range(bursts.size()-1,-1,-1):
		var b: Dictionary = bursts[i]
		b.life += delta
		var u: float = b.life/b.duration
		if u >= 1.0 or not is_instance_valid(b.node):
			if is_instance_valid(b.node): b.node.queue_free()
			bursts.remove_at(i)
		else: b.mat.set_shader_parameter("progress",u)
	if pending_open >= 0.0:
		pending_open -= delta
		if pending_open <= 0.0 and g.mode == "raid":
			pending_open = -1.0
			g.choice_queue.append("boon")
			g._open_next_choice()

func pickup_radius() -> float:
	return PICKUP_RADIUS + int(g.taken.get("magnet",0))*.8

func nearby_drop() -> Dictionary:
	if not is_instance_valid(g.player): return {}
	for d in drops:
		if d.phase != "idle": continue
		var a: Vector3 = d.root.position; var b: Vector3 = g.player.position
		if Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z)) < pickup_radius(): return d
	return {}

func prompt() -> String:
	return "" if nearby_drop().is_empty() else "[E] 拾取诸神祝福"

func try_pickup() -> bool:
	if g.mode != "raid" or pending_open >= 0.0: return false
	var d := nearby_drop()
	if d.is_empty(): return false
	d.phase = "absorb"; d.t = 0.0
	d["start"] = d.core.global_position
	d["last"] = d.core.global_position
	d.label.visible = false
	g.sound.play("loot",-12,1.35)
	return true

func pending_count() -> int:
	return drops.size() + _queued.size()

func _roll(q: Dictionary) -> void:
	var chance: float = float(CHANCE.get(str(q.kind),CHANCE.combat)) + dry_rooms*PITY
	if g.rng.randf() >= chance:
		dry_rooms += 1
		return
	dry_rooms = 0
	spawn_drop(_drop_point(q.pos))

func _drop_point(center: Vector3) -> Vector3:
	var p := Vector3(center.x,0,center.z)
	var player: Vector3 = g.player.position if is_instance_valid(g.player) else p
	player.y = 0
	if p.distance_to(player) < 3.0:
		var away := p-player
		if away.length() < .1: away = Vector3(0,0,-1)
		p = player + away.normalized()*3.2
	for e in g.extracts:
		var gate: Vector3 = e.pos; gate.y = 0
		if p.distance_to(gate) < 3.4:
			var dir := p-gate
			if dir.length() < .1: dir = Vector3.RIGHT
			p = gate + dir.normalized()*3.8
	if not g.world.blocked(p,.7): return p
	for ring in [2.5,4.0,1.2]:
		for i in 8:
			var a := TAU*i/8.0
			var c: Vector3 = Vector3(center.x,0,center.z)+Vector3(cos(a),0,sin(a))*ring
			if not g.world.blocked(c,.7) and c.distance_to(player) > 1.5: return c
	return player + Vector3(0,0,-2)

func spawn_drop(pos: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.name = "BlessingDrop"
	g.actors.add_child(root)
	root.position = g.world.ground_position(pos)
	var core := MeshInstance3D.new()
	core.mesh = _core_mesh
	var core_mat := ShaderMaterial.new(); core_mat.shader = CORE_SHADER
	core.material_override = core_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.rotation = Vector3(PI*.25,0,PI*.25)
	root.add_child(core)
	var beam := MeshInstance3D.new()
	beam.mesh = _beam_mesh
	var beam_mat := ShaderMaterial.new(); beam_mat.shader = BEAM_SHADER
	beam.material_override = beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam)
	var marker := _plane(root,5.0,.06)
	var marker_mat: ShaderMaterial = marker.material_override
	marker_mat.set_shader_parameter("fill",.35)
	marker_mat.set_shader_parameter("width",.06)
	var shards: Array = []
	for i in 6:
		var shard := MeshInstance3D.new()
		shard.mesh = _shard_mesh
		var mat := ShaderMaterial.new(); mat.shader = CORE_SHADER
		mat.set_shader_parameter("hue_offset",i/6.0)
		shard.material_override = mat
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shard.visible = false
		root.add_child(shard)
		shards.append(shard)
	var label := Label3D.new()
	label.text = "诸神祝福"
	label.font_size = 30; label.pixel_size = .012; label.outline_size = 6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("fff4dc")
	label.position = Vector3(0,2.5,0)
	label.visible = false
	root.add_child(label)
	var d := {"root":root,"core":core,"core_mat":core_mat,"beam":beam,"beam_mat":beam_mat,"marker":marker,"marker_mat":marker_mat,"shards":shards,"label":label,"phase":"fall","y":FALL_HEIGHT,"vy":-9.0,"t":0.0,"spin":0.0,"last":Vector3.ZERO}
	drops.append(d)
	_pose(d)
	d.last = core.global_position
	g.sound.play("pickup_rare",-19,.7)
	return d

func _plane(parent: Node3D, size: float, height: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var plane := PlaneMesh.new(); plane.size = Vector2.ONE*size
	node.mesh = plane
	var mat := ShaderMaterial.new(); mat.shader = RING_SHADER
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	node.position.y = height
	return node

func _tick_drop(d: Dictionary, delta: float) -> void:
	if not is_instance_valid(d.root):
		drops.erase(d); return
	d.t += delta
	match d.phase:
		"fall":
			d.vy -= 72.0*delta
			d.y += d.vy*delta
			if d.y <= HANG_HEIGHT:
				d.y = HANG_HEIGHT; d.phase = "hang"; d.t = 0.0
				# Beat of time stop just before impact: everything else holds.
				g.hit_pause = maxf(g.hit_pause,HANG_TIME)
				g.sound.play("tick",-11,1.6)
				g.sound.play("spin_charge",-16,1.25)
		"hang":
			var u: float = clampf(d.t/HANG_TIME,0,1)
			d.y = HANG_HEIGHT-HANG_DIP*(1.0-pow(1.0-u,3.0))
			_hang_amount = maxf(_hang_amount,.75*sin(PI*minf(u*1.15,1.0)) if not g.motion_reduced else .3)
			if d.t >= HANG_TIME: d.phase = "slam"; d.t = 0.0; d.vy = -26.0
		"slam":
			d.vy -= 140.0*delta
			d.y += d.vy*delta
			if d.y <= SLAM_FLOOR:
				d.y = SLAM_FLOOR; d.phase = "land"; d.t = 0.0
				_boom(d)
		"land":
			var u: float = clampf(d.t/LAND_TIME,0,1)
			var c1 := 1.70158; var c3 := c1+1.0
			d.y = lerpf(SLAM_FLOOR,REST_HEIGHT,1.0+c3*pow(u-1.0,3.0)+c1*pow(u-1.0,2.0))
			if u >= 1.0:
				d.phase = "idle"; d.t = 0.0
				d.label.visible = true
				for s in d.shards: s.visible = true
		"idle":
			d.y = REST_HEIGHT+sin(d.t*2.4)*.12
		"absorb":
			# Lift, then dive along an arc into the hero's chest, shrinking and spinning.
			var u: float = clampf(d.t/ABSORB_TIME,0,1)
			var target: Vector3 = g.player.position+Vector3(0,1.05,0) if is_instance_valid(g.player) else d.start
			var lift := clampf(u/.28,0,1)
			var dive := clampf((u-.28)/.72,0,1)
			var raised: Vector3 = d.start+Vector3(0,.9,0)
			var e := dive*dive*dive
			var p: Vector3 = d.start.lerp(raised,1.0-pow(1.0-lift,3.0))
			if dive > 0.0:
				var control: Vector3 = (raised+target)*.5+Vector3(0,1.6,0)
				p = raised.lerp(control,e).lerp(control.lerp(target,e),e)
			d.core.global_position = p
			d.core.rotation.y += delta*(10.0+dive*30.0)
			d.core.scale = Vector3.ONE*(lerpf(1.0,1.25,lift) if dive <= 0.0 else lerpf(1.25,.12,e))
			d.core_mat.set_shader_parameter("glow",1.6+dive*1.6)
			d.beam_mat.set_shader_parameter("strength",.55*(1.0-u))
			d.marker_mat.set_shader_parameter("strength",1.0-u)
			for s in d.shards:
				s.global_position = s.global_position.lerp(p,minf(1.0,delta*(6.0+dive*20.0)))
				s.scale = Vector3.ONE*maxf(.05,1.0-dive)
			if dive > 0.0:
				var now: Vector3 = d.core.global_position
				g._sword_trail(d.last,now,Color.from_hsv(fposmod(d.t*3.0,1.0),.6,1.0))
				d.last = now
			if u >= 1.0:
				_absorbed(d)
				return
			return
	_pose(d)
	if d.phase in ["fall","slam"]:
		var now: Vector3 = d.core.global_position
		g._sword_trail(d.last,now,Color.from_hsv(fposmod(d.t*2.5,1.0),.55,1.0))
		d.last = now

func _pose(d: Dictionary) -> void:
	var y: float = d.y
	var falling: bool = d.phase in ["fall","hang","slam"]
	d.spin += .016*(1.5 if d.phase == "hang" else (2.4 if falling else 1.6))
	d.core.position = Vector3(0,y,0)
	if d.phase == "hang": d.core.position.x = sin(d.t*95.0)*.035
	d.core.rotation.y = d.spin*2.0
	d.core_mat.set_shader_parameter("glow",2.0 if d.phase == "hang" else 1.15)
	if falling:
		var height := SKY_TOP-y
		d.beam.position.y = y+height*.5
		d.beam.scale = Vector3(1.5,height,1.5)
		d.beam_mat.set_shader_parameter("strength",2.4 if d.phase == "hang" else 1.8)
		d.beam_mat.set_shader_parameter("bottom_weight",2.6)
		# The ground telegraph tightens as the blessing approaches.
		var k := clampf((y-HANG_HEIGHT)/(FALL_HEIGHT-HANG_HEIGHT),0,1)
		d.marker_mat.set_shader_parameter("radius",lerpf(.3,.92,k))
		d.marker_mat.set_shader_parameter("strength",1.4 if d.phase == "hang" else .9)
	else:
		d.beam.position.y = STAND_HEIGHT*.5
		d.beam.scale = Vector3(1.0,STAND_HEIGHT,1.0)
		if d.phase != "absorb":
			d.beam_mat.set_shader_parameter("strength",.55)
			d.beam_mat.set_shader_parameter("bottom_weight",1.2)
			d.marker_mat.set_shader_parameter("radius",.3)
			d.marker_mat.set_shader_parameter("strength",.8)
		for i in d.shards.size():
			var a: float = d.spin*1.4+TAU*i/d.shards.size()
			var s: MeshInstance3D = d.shards[i]
			s.position = Vector3(cos(a)*.85,y+sin(d.spin*3.0+i)*.18,sin(a)*.85)
			s.rotation.y = -a

func _screen_uv(pos: Vector3) -> Vector2:
	var size: Vector2 = g.get_viewport().get_visible_rect().size
	if size.x <= 0 or size.y <= 0: return Vector2(.5,.5)
	return g.camera.unproject_position(pos)/size

func _boom(d: Dictionary) -> void:
	var pos: Vector3 = d.root.position
	var reduced: bool = g.motion_reduced
	g.hit_pause = maxf(g.hit_pause,.075)
	g.shake = maxf(g.shake,.1 if reduced else .34)
	g.art_direction.flash(.12 if reduced else .26,.18,Color("fff6e8"))
	g.art_direction.trigger_slam(_screen_uv(pos),reduced)
	g.world.pulse_floor(pos,1.3,7.5)
	_ring_burst(pos,7.0,.6)
	_ring_burst(pos,3.4,.32)
	_rainbow_sparks(pos+Vector3(0,.35,0),44,7.5)
	g.play_combat_fx("loot_burst",pos,Color("ffe6a8"),Vector3.FORWARD,1.1)
	g.sound.play("impact",-9,.62)
	g.sound.play("bass",-10,1.0)
	g.sound.play("break",-15,.9)
	g.sound.play("pickup_rare",-13,1.15)

func _absorbed(d: Dictionary) -> void:
	var pos: Vector3 = g.player.position if is_instance_valid(g.player) else d.root.position
	var reduced: bool = g.motion_reduced
	if is_instance_valid(d.root): d.root.queue_free()
	drops.erase(d)
	collected += 1
	g.level = 1+collected
	g.art_direction.trigger_warp(_screen_uv(pos+Vector3(0,.9,0)),reduced)
	g.world.pulse_floor_wave(pos,1.4,24.0,.8)
	g.shake = maxf(g.shake,.06 if reduced else .2)
	g.hit_pause = maxf(g.hit_pause,.05)
	g.art_direction.flash(.1 if reduced else .16,.22,Color("f3e8ff"))
	_ring_burst(pos,10.0,.75)
	_rainbow_sparks(pos+Vector3(0,.9,0),30,5.0)
	g.sound.play("pickup_rare",-10,1.3)
	g.sound.play("level",-12,1.1)
	if g.has_method("start_blessing_glow"): g.start_blessing_glow()
	pending_open = OPEN_DELAY

func _ring_burst(pos: Vector3, radius: float, duration: float) -> void:
	var node := _plane(g.actors,radius*2.0,0.0)
	node.position = Vector3(pos.x,.09,pos.z)
	var mat: ShaderMaterial = node.material_override
	mat.set_shader_parameter("burst",1.0)
	mat.set_shader_parameter("width",.075)
	mat.set_shader_parameter("strength",1.2)
	bursts.append({"node":node,"mat":mat,"life":0.0,"duration":duration})

func _rainbow_sparks(pos: Vector3, count: int, speed: float) -> void:
	if g.effects.size() > 200: return
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = mini(count,14) if preload("res://scripts/quality.gd").low() else count
	p.lifetime = .8
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 85.0
	p.gravity = Vector3(0,-9,0)
	p.initial_velocity_min = speed*.45
	p.initial_velocity_max = speed
	p.scale_amount_min = .6
	p.scale_amount_max = 1.7
	p.angular_velocity_min = -300
	p.angular_velocity_max = 300
	p.mesh = _spark_mesh
	p.color = Color(1.0,.35,.35)
	p.hue_variation_min = -1.0
	p.hue_variation_max = 1.0
	var fade := Gradient.new()
	fade.set_color(0,Color.WHITE)
	fade.set_color(1,Color(1,1,1,0))
	p.color_ramp = fade
	g.actors.add_child(p)
	p.position = pos
	p.emitting = true
	g.effects.append({"node":p,"life":1.0,"max":1.0,"vel":Vector3.ZERO,"grow":0.0,"particles":true})
