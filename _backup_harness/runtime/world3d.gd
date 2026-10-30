extends Node3D
## 3D world built from the JSON game spec: animated AI-build ops in edit mode and a
## third-person platformer in play mode. Lighting lives in env3d.gd, terrain meshes in
## terrain3d.gd, one-shot/ambient effects in fx3d.gd.
const U = preload("res://util.gd")
const FX = preload("res://fx.gd")
const FX3 = preload("res://fx3d.gd")
const Env = preload("res://env3d.gd")
const Terrain = preload("res://terrain3d.gd")
const Ent = preload("res://ent3d.gd")
const Player = preload("res://player3d.gd")
const Drone = preload("res://drone3d.gd")

# ---- camera tuning
const CAM_FOV := 58.0
const CAM_FAR := 900.0
const EDIT_PITCH := -0.48
const EDIT_YAW := 0.42
const EDIT_FOLLOW := 3.0
const EDIT_SPIN := 0.035
const PLAY_FOCUS_H := 10.0     # horizontal focus catch-up rate
const PLAY_FOCUS_V := 4.0      # vertical catch-up (lazier, so jumps don't yank the view)
const PLAY_AIR_FOLLOW := 0.35  # fraction of a jump's height followed while airborne
const PLAY_LOOK_AHEAD := 0.18  # seconds of horizontal velocity to lead the view by
const PLAY_EYE := 1.1          # focus height above the player's centre
const CAM_RADIUS := 0.35       # sphere-cast radius keeping the near plane out of walls
const CAM_PULL_IN := 18.0
const CAM_EASE_OUT := 3.0
const START_YAW_OFFSET := 0.35
# ---- level
const KILL_MARGIN := 15.0
const GROUND_KILL_DEPTH := 20.0
const FLOAT_GAP := 2.5         # platforms this high above the ground get rocky undersides

var main = null
var spec := {}
var topdown := false
var playing := false
var ents := {}
var player = null
var drone = null
var cam: Camera3D
var env: Env
var ground: Node3D
var ambient: CPUParticles3D
var kill_y := -30.0
# edit camera
var cam_focus := Vector3.ZERO
var cam_yaw := EDIT_YAW
var cam_pitch := EDIT_PITCH
var cam_dist := 30.0
var focus_target := Vector3.ZERO
var dist_target := 30.0
# play camera
var play_focus := Vector3.ZERO
var play_ground_y := 0.0
var play_dist := 0.0
var _cam_shape := SphereShape3D.new()
var _cam_query := PhysicsShapeQueryParameters3D.new()
# goal progress (0..1, monotonic within a run)
var goal_ent = null
var start_goal_dist := 0.0
var best_progress := 0.0
# edit interaction
var selected := ""
var dragging := ""
var drag_moved := false
var orbiting := false
var sel_mesh: MeshInstance3D

func setup(m, s: Dictionary) -> void:
	main = m
	spec = s
	cam = Camera3D.new()
	cam.fov = CAM_FOV
	cam.far = CAM_FAR
	cam.near = 0.1
	add_child(cam)
	cam.make_current()
	env = Env.new()
	add_child(env)
	_cam_shape.radius = CAM_RADIUS
	_cam_query.shape = _cam_shape
	_cam_query.collision_mask = 1
	sel_mesh = _make_selection_box()
	add_child(sel_mesh)
	rebuild()

func _make_selection_box() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 0.85, 0.2, 0.22)
	m.no_depth_test = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi

func world_dict() -> Dictionary:
	return U.dict_of(spec, "world")

func rebuild() -> void:
	for id in ents:
		if is_instance_valid(ents[id]):
			ents[id].queue_free()
	ents.clear()
	if player and is_instance_valid(player):
		player.queue_free()
	apply_world(false)
	var es = spec.get("entities", {})
	if typeof(es) == TYPE_DICTIONARY:
		for id in es:
			if typeof(es[id]) == TYPE_DICTIONARY:
				_spawn(str(id), es[id])
	player = Player.new()
	add_child(player)
	player.setup(self, U.dict_of(spec, "player"), U.dict_of(spec, "settings"))
	if drone == null:
		drone = Drone.new()
		add_child(drone)
	drone.visible = not playing
	frame_all(false)

func _spawn(id: String, d: Dictionary):
	var e = Ent.new()
	add_child(e)
	e.setup(self, id, d)
	ents[id] = e
	return e

func apply_world(animate: bool) -> void:
	var w := world_dict()
	env.apply(w, animate)
	_apply_ground(w)
	_apply_ambient(w)
	for id in ents:
		if is_instance_valid(ents[id]) and ents[id].kind == "platform":
			ents[id].refresh_terrain()

## Explicit world.theme ("grass"|"snow"|"sand"|"stone"|"candy"|"lava"|"ice"), else "".
func terrain_theme() -> String:
	return U.world_theme(spec)

func ground_size() -> float:
	return U.num(world_dict(), "ground_size", 0.0)

## Platforms hovering in open air get a rocky floating-island underside.
func is_floating(pos: Vector3, size: Vector3) -> bool:
	return ground_size() <= 0.0 or pos.y - size.y * 0.5 > FLOAT_GAP

func texture_asset(id: String) -> Texture2D:
	if id == "" or main.assets.state(id) != "ready":
		return null
	var t = main.assets.get_res(id)
	return t if t is Texture2D else null

func _apply_ground(w: Dictionary) -> void:
	if ground:
		ground.queue_free()
		ground = null
	var gsize := ground_size()
	if gsize <= 0.0:
		return
	var gcol := U.col(w.get("ground_color"), Color("#6ab04c"))
	ground = Node3D.new()
	ground.name = "Ground"
	add_child(ground)
	var tex := texture_asset(U.str_of(w, "ground_asset", ""))
	ground.add_child(Terrain.ground(gsize, gcol, Terrain.theme_for(gcol, terrain_theme()), tex))
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(gsize, 1, gsize)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	sb.add_child(cs)
	ground.add_child(sb)

## world.ambient particles around the camera; night skies default to twinkling stars.
func _apply_ambient(w: Dictionary) -> void:
	if ambient:
		ambient.queue_free()
		ambient = null
	var kind := U.str_of(w, "ambient", "stars" if env.preset_name == "night" else "none")
	ambient = FX3.ambient(kind, env.horizon_color)
	if ambient:
		add_child(ambient)

func _bounds() -> AABB:
	var a := AABB(Vector3(-5, -1, -5), Vector3(10, 4, 10))
	for id in ents:
		if is_instance_valid(ents[id]):
			a = a.merge(ents[id].world_aabb())
	if player:
		a = a.expand(player.position)
	return a

func frame_all(animate := true) -> void:
	var a := _bounds()
	kill_y = -GROUND_KILL_DEPTH if ground_size() > 0.0 else a.position.y - KILL_MARGIN
	var yaw := cam_yaw
	if not animate:
		yaw = EDIT_YAW if a.size.x >= a.size.z else PI * 0.5 + EDIT_YAW
		cam_yaw = yaw
		cam_pitch = EDIT_PITCH
	var fit := _fit_view(a.get_center(), yaw, cam_pitch)
	focus_target = fit[0]
	dist_target = clampf(fit[1], 10.0, 220.0)
	if not playing:
		env.fit_view(dist_target, maxf(a.size.x, a.size.z))
	if not animate:
		cam_focus = focus_target
		cam_dist = dist_target

## Orbit focus + distance that frame every entity box on screen. Perspective makes near
## content look bigger, so the focus is re-centred on the projected extents a few times.
func _fit_view(focus: Vector3, yaw: float, pitch: float) -> Array:
	const MARGIN := 1.1
	const ITERATIONS := 4
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var tan_v := tan(deg_to_rad(cam.fov) * 0.5)
	var vp := get_viewport().get_visible_rect().size
	var tan_h := tan_v * vp.x / maxf(vp.y, 1.0)
	var boxes := _frame_boxes()
	var dist := 10.0
	for _it in ITERATIONS:
		dist = 0.0
		for box in boxes:
			for i in 8:
				var o: Vector3 = box.get_endpoint(i) - focus
				var toward := o.dot(b.z)  # corners nearer the camera need more distance
				dist = maxf(dist, absf(o.dot(b.x)) * MARGIN / tan_h + toward)
				dist = maxf(dist, absf(o.dot(b.y)) * MARGIN / tan_v + toward)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for box in boxes:
			for i in 8:
				var o: Vector3 = box.get_endpoint(i) - focus
				var depth := maxf(dist - o.dot(b.z), 0.5)
				var s := Vector2(o.dot(b.x), o.dot(b.y)) / depth
				lo = lo.min(s)
				hi = hi.max(s)
		var mid := (lo + hi) * 0.5 * dist
		focus += b.x * mid.x + b.y * mid.y
	return [focus, dist]

func _frame_boxes() -> Array[AABB]:
	var out: Array[AABB] = []
	for id in ents:
		if is_instance_valid(ents[id]):
			out.append(ents[id].world_aabb())
	if player:
		out.append(AABB(player.position - player.size * 0.5, player.size))
	if out.is_empty():
		out.append(AABB(Vector3(-5, -1, -5), Vector3(10, 4, 10)))
	return out

func _process(delta: float) -> void:
	if playing and player and is_instance_valid(player):
		_update_play_camera(delta)
	else:
		_update_edit_camera(delta)
	if ambient:
		ambient.global_position = cam.global_position
	_update_selection()

func _update_edit_camera(delta: float) -> void:
	var k := minf(1.0, delta * EDIT_FOLLOW)
	cam_focus = cam_focus.lerp(focus_target, k)
	cam_dist = lerpf(cam_dist, dist_target, k)
	var dir := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch) * Vector3(0, 0, 1)
	cam.global_position = cam_focus + dir * cam_dist
	cam.look_at(cam_focus)
	if not orbiting and dragging == "" and not main.busy_building:
		cam_yaw += delta * EDIT_SPIN

## Lazy-follow focus point + sphere-cast boom so the camera never clips into terrain.
func _update_play_camera(delta: float) -> void:
	var p: Vector3 = player.global_position
	if player.is_on_floor() or p.y < play_ground_y:
		play_ground_y = p.y
	var lead: Vector3 = player.velocity * PLAY_LOOK_AHEAD
	var want := Vector3(p.x + lead.x, lerpf(play_ground_y, p.y, PLAY_AIR_FOLLOW) + PLAY_EYE, p.z + lead.z)
	var kh := 1.0 - exp(-delta * PLAY_FOCUS_H)
	var kv := 1.0 - exp(-delta * PLAY_FOCUS_V)
	play_focus = Vector3(lerpf(play_focus.x, want.x, kh), lerpf(play_focus.y, want.y, kv), lerpf(play_focus.z, want.z, kh))
	var dir: Vector3 = Basis(Vector3.UP, player.cam_yaw) * Basis(Vector3.RIGHT, player.cam_pitch) * Vector3(0, 0, 1)
	var free_dist: float = player.cam_dist * _boom_fraction(play_focus, dir * player.cam_dist)
	var rate := CAM_PULL_IN if free_dist < play_dist else CAM_EASE_OUT
	play_dist = lerpf(play_dist, free_dist, minf(1.0, delta * rate))
	cam.global_position = play_focus + dir * play_dist
	cam.look_at(play_focus)

func _boom_fraction(from: Vector3, motion: Vector3) -> float:
	_cam_query.transform = Transform3D(Basis.IDENTITY, from)
	_cam_query.motion = motion
	_cam_query.exclude = [player.get_rid()]
	var r := get_world_3d().direct_space_state.cast_motion(_cam_query)
	return clampf(r[0], 0.15, 1.0) if r.size() > 0 else 1.0

func _update_selection() -> void:
	sel_mesh.visible = false
	if selected == "" or playing:
		return
	if selected == "__player" and player:
		sel_mesh.visible = true
		sel_mesh.global_position = player.global_position
		sel_mesh.scale = player.size * 1.2
		return
	var e = ents.get(selected)
	if e and is_instance_valid(e):
		sel_mesh.visible = true
		sel_mesh.global_position = e.global_position
		sel_mesh.scale = e.size * 1.15

# ---------------------------------------------------------------- build ops

func op_entity(id: String, d: Dictionary, dur: float) -> void:
	var existed: bool = ents.has(id) and is_instance_valid(ents[id])
	var target := U.v3(d.get("position"), Vector3.ZERO)
	await _drone_go(target, dur)
	if existed:
		var e = ents[id]
		var old: Vector3 = e.position
		e.apply(d)
		var np: Vector3 = e.position
		e.position = old
		create_tween().tween_property(e, "position", np, dur * 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_wiggle(e.visual)
		main.sfx("whoosh", -6.0)
	else:
		var e2 = _spawn(id, d)
		e2.visual.scale = Vector3.ONE * 0.05
		e2.visual.position.y = 3.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(e2.visual, "scale", Vector3.ONE, dur * 1.1).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(e2.visual, "position:y", 0.0, dur * 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		var col: Color = e2.base_color()
		FX3.burst(self, target, col, 16, 5.0)
		FX3.ring(self, target - Vector3(0, e2.size.y * 0.5, 0), col, maxf(e2.size.x, 1.5))
		FX.float_text3d(self, target + Vector3(0, e2.size.y * 0.5 + 0.8, 0), "+ " + U.str_of(d, "name", e2.kind_label()), Color.WHITE)
		main.sfx("pop", -4.0)
	drone.shoot_beam(target, 1.2)
	await get_tree().create_timer(dur * 0.6).timeout

func op_remove(id: String, dur: float) -> void:
	if not ents.has(id):
		return
	var e = ents[id]
	ents.erase(id)
	if not is_instance_valid(e):
		return
	await _drone_go(e.position, dur)
	drone.shoot_beam(e.position, 1.2)
	FX3.burst(self, e.global_position, Color(0.85, 0.85, 0.9), 16, 4.0)
	main.sfx("whoosh", -4.0)
	var tw := create_tween()
	tw.tween_property(e.visual, "scale", Vector3.ONE * 0.01, dur * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(e.queue_free)
	await get_tree().create_timer(dur * 0.6).timeout

func op_player(d: Dictionary, dur: float) -> void:
	var p := U.v3(d.get("position"), Vector3(0, 2, 0))
	await _drone_go(p, dur)
	player.setup(self, d, U.dict_of(spec, "settings"))
	player.visual.scale = Vector3.ONE * 0.05
	create_tween().tween_property(player.visual, "scale", Vector3.ONE, dur).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	FX.float_text3d(self, p + Vector3(0, 2, 0), "主角", Color("#4cc9f0"))
	main.sfx("sparkle", -4.0)
	await get_tree().create_timer(dur * 0.5).timeout

func op_world(dur: float) -> void:
	apply_world(true)
	main.sfx("sparkle", -8.0)
	await get_tree().create_timer(dur * 0.5).timeout

func refresh_assets(asset_id: String) -> void:
	var w := world_dict()
	var platform_tex := U.str_of(w, "platform_asset", "") == asset_id
	for id in ents:
		var e = ents[id]
		if not is_instance_valid(e):
			continue
		if e.asset_id == asset_id:
			e.refresh_asset(not playing)
		elif platform_tex and e.kind == "platform":
			e.refresh_terrain()
	if player and U.str_of(player.data, "asset", "") == asset_id:
		player.refresh_asset(not playing)
	if U.str_of(w, "ground_asset", "") == asset_id:
		_apply_ground(w)

func focus(id: String) -> void:
	if ents.has(id) and is_instance_valid(ents[id]):
		await _drone_go(ents[id].position, 0.4)
		_wiggle(ents[id].visual)

func drone_say(text: String) -> void:
	if drone:
		drone.say(text)

func _drone_go(target: Vector3, dur: float) -> void:
	drone.visible = true
	focus_target = focus_target.lerp(target, 0.5)
	if focus_target.distance_to(target) > cam_dist * 0.5:
		focus_target = target
	var tw = drone.fly_to(target, dur * 0.6)
	await tw.finished

func _wiggle(n: Node3D) -> void:
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3(1.15, 0.85, 1.15), 0.08)
	tw.tween_property(n, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

# ---------------------------------------------------------------- gameplay

func start_play() -> void:
	playing = true
	drone.visible = false
	selected = ""
	if player == null:
		return
	goal_ent = _find_goal()
	best_progress = 0.0
	start_goal_dist = player.global_position.distance_to(goal_ent.global_position) if goal_ent else 0.0
	player.cam_yaw = _start_yaw()
	player.face_yaw = player.cam_yaw - START_YAW_OFFSET + PI  # face away from the camera, towards the goal
	play_focus = player.global_position + Vector3(0, PLAY_EYE, 0)
	play_ground_y = player.global_position.y
	play_dist = player.cam_dist
	env.fit_view(player.cam_dist * 2.5, _bounds().size.length())
	_update_play_camera(1.0)

## Look from behind the player towards the goal, slightly off-axis for depth.
func _start_yaw() -> float:
	var fwd := Vector3.ZERO
	if goal_ent:
		fwd = goal_ent.global_position - player.global_position
	fwd.y = 0.0
	if fwd.length() < 1.0:
		var face := deg_to_rad(U.num(player.data, "facing", 0.0))
		fwd = Vector3(sin(face), 0, cos(face))
	return atan2(-fwd.x, -fwd.z) + START_YAW_OFFSET

func _find_goal():
	for id in ents:
		var e = ents[id]
		if is_instance_valid(e) and e.kind == "goal":
			return e
	return null

## 0..1 progress from spawn towards the goal for the HUD; negative hides the bar.
func progress() -> float:
	if not playing or goal_ent == null or not is_instance_valid(goal_ent) or start_goal_dist < 1.0 or player == null:
		return -1.0
	var d: float = player.global_position.distance_to(goal_ent.global_position)
	best_progress = maxf(best_progress, clampf(1.0 - d / start_goal_dist, 0.0, 1.0))
	return best_progress

func hit_stop(secs: float) -> void:
	if main.has_method("hit_stop"):
		main.hit_stop(secs)

func collect(e, value: int) -> void:
	main.add_score(value)
	main.sfx("coin")
	FX.float_text3d(self, e.global_position + Vector3.UP, "+%d" % value, Color("#ffd23f"))
	main.on_collect()

func enemy_defeated(e, value: int, stomped: bool) -> void:
	main.add_score(value)
	if stomped:
		main.sfx("stomp")
		hit_stop(0.06)
		main.shake(4.0)
		FX3.ring(self, e.global_position - Vector3(0, e.size.y * 0.4, 0), Color.WHITE, maxf(e.size.x * 1.8, 1.5))
	else:
		main.sfx("pop")
	FX3.burst(self, e.global_position, e.base_color(), 20, 6.0)
	FX.float_text3d(self, e.global_position + Vector3.UP, "+%d" % value, Color("#ff8fab"))
	main.on_defeat()

func reach_goal(e) -> void:
	FX3.burst(self, e.global_position, Color("#ffe066"), 30, 8.0)
	main.on_goal()

## A checkpoint becomes the respawn point; the flag sits on top of the platform.
func reach_checkpoint(e) -> void:
	var foot: Vector3 = e.global_position - Vector3(0, e.size.y * 0.5, 0)
	player.spawn = foot + Vector3(0, player.size.y * 0.5 + 0.3, 0)
	FX3.ring(self, foot, e.base_color(), 2.5)
	FX3.burst(self, e.global_position + Vector3(0, e.size.y * 0.4, 0), e.base_color(), 24, 6.0)
	main.sfx("checkpoint")
	if main.has_method("on_checkpoint"):
		main.on_checkpoint()

func player_hurt() -> void:
	main.sfx("hurt")
	main.shake(8.0)
	main.lose_life()

## Player dropped below kill_y; returns true when a life remains and they should respawn.
func player_fell() -> bool:
	main.sfx("hurt")
	return main.lose_life()

func spawn_projectile(from: Vector3, vel: Vector3, col: Color, friendly := false) -> void:
	var a := Area3D.new()
	a.collision_layer = 8
	a.collision_mask = 4 if friendly else 2
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.25
	cs.shape = sp
	a.add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.5
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	a.add_child(mi)
	add_child(a)
	a.global_position = from
	var life := [0.0]
	var cb := func():
		if not is_instance_valid(a):
			return
		var dt := get_physics_process_delta_time()
		a.position += vel * dt
		life[0] += dt
		if life[0] > 3.0:
			a.queue_free()
	get_tree().physics_frame.connect(cb)
	a.tree_exiting.connect(func(): if get_tree().physics_frame.is_connected(cb): get_tree().physics_frame.disconnect(cb))
	if friendly:
		a.area_entered.connect(func(o):
			var en = o.get_meta("ent") if o.has_meta("ent") else null
			if en and en.kind == "enemy" and en.alive:
				en.defeat(false)
				a.queue_free())
	else:
		a.body_entered.connect(func(b):
			if b == player:
				player.hurt(a.global_position)
				a.queue_free())

# ---------------------------------------------------------------- edit-mode interaction

func _unhandled_input(ev: InputEvent) -> void:
	if playing:
		return
	if ev is InputEventMouseButton:
		_on_mouse_button(ev as InputEventMouseButton)
	elif ev is InputEventMouseMotion:
		_on_mouse_motion(ev as InputEventMouseMotion)

func _on_mouse_button(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		dist_target = maxf(4.0, dist_target * 0.9)
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		dist_target = minf(300.0, dist_target * 1.1)
	elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
		orbiting = mb.pressed
	elif mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			var hit := _pick(mb.position)
			selected = hit
			drag_moved = false
			dragging = hit if hit != "" else "__orbit"
			main.emit_event({"type": "select", "id": hit})
		else:
			if dragging != "" and dragging != "__orbit" and drag_moved:
				var pos: Vector3 = player.position if dragging == "__player" else ents[dragging].position
				main.on_dragged(dragging, [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1), snappedf(pos.z, 0.1)])
			dragging = ""

func _on_mouse_motion(mm: InputEventMouseMotion) -> void:
	if orbiting or dragging == "__orbit":
		cam_yaw -= mm.relative.x * 0.006
		cam_pitch = clampf(cam_pitch - mm.relative.y * 0.004, -1.45, -0.05)
		return
	if dragging == "":
		return
	drag_moved = true
	var node = player if dragging == "__player" else ents.get(dragging)
	if node == null:
		return
	var y: float = node.position.y
	var o := cam.project_ray_origin(mm.position)
	var d := cam.project_ray_normal(mm.position)
	if absf(d.y) < 0.001:
		return
	var tt := (y - o.y) / d.y
	if tt > 0.0:
		var p := o + d * tt
		node.position = Vector3(snappedf(p.x, 0.5), y, snappedf(p.z, 0.5))
		if node != player:
			node.home = node.position

func _pick(screen: Vector2) -> String:
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	var best := ""
	var best_t := INF
	if player:
		var r = AABB(player.global_position - player.size * 0.5, player.size).intersects_ray(o, d)
		if r != null:
			best = "__player"
			best_t = o.distance_to(r)
	for id in ents:
		var e = ents[id]
		if not is_instance_valid(e):
			continue
		var r2 = e.world_aabb().intersects_ray(o, d)
		if r2 != null and o.distance_to(r2) < best_t:
			best_t = o.distance_to(r2)
			best = id
	return best