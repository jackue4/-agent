extends CharacterBody3D
## Third-person 3D player with platformer feel: acceleration curves, air control, coyote
## time, jump buffer, variable jump height, squash & stretch, dust, blob shadow, hurt
## flash/knockback and a fall-off respawn animation. The world owns the camera; this node
## only stores the orbit parameters (cam_yaw / cam_pitch / cam_dist) the input changes.
const U = preload("res://util.gd")
const FX3 = preload("res://fx3d.gd")
const Mat = preload("res://mat3d.gd")

# ---- movement
const GROUND_ACCEL := 9.0       # x speed per second to reach top speed on ground
const GROUND_DECEL := 12.0
const AIR_ACCEL := 4.5
const AIR_DECEL := 1.5
const TURN_ACCEL_BOOST := 1.8   # extra accel when reversing direction (snappy turns)
const COYOTE := 0.12
const JUMP_BUFFER := 0.14
const JUMP_CUT := 0.45          # velocity kept when jump is released early
const FALL_GRAVITY := 1.35      # heavier gravity on the way down (less floaty)
const MAX_FALL := 30.0
const FACE_RATE := 14.0
# ---- feel
const LAND_SQUASH_SPEED := 6.0  # landing speed that produces a full squash
const RUN_DUST_EVERY := 0.22
const STEP_SFX_DB := -14.0
const HURT_TIME := 1.2
const KNOCKBACK := 7.0
const RESPAWN_SECS := 0.55
const SHADOW_RAY := 30.0
# ---- camera
const CAM_PITCH_MIN := -1.2
const CAM_PITCH_MAX := 0.25
const CAM_KEY_SPEED := 2.2
const CAM_DIST_MIN := 3.0
const CAM_DIST_MAX := 25.0

var world = null
var data := {}
var size := Vector3(0.9, 1.7, 0.9)
var speed := 7.0
var jump := 9.0
var gravity := 24.0
var spawn := Vector3.ZERO
var visual: Node3D      # yaw + squash pivot at the feet
var model: Node3D
var shadow: MeshInstance3D
var coyote := 0.0
var jump_buf := 0.0
var jump_held := false
var hurt_cd := 0.0
var power := ""
var power_t := 0.0
var air_jumps := 0
var max_air_jumps := 0
var walk_t := 0.0
var dust_t := 0.0
var cam_yaw := 0.0
var cam_pitch := -0.38
var cam_dist := 9.0
var shoot_cd := 0.0
var face_yaw := 0.0
var respawning := false
var _was_on_floor := true
var _fall_speed := 0.0
var _squash := Vector3.ONE
var _flash_mats: Array[StandardMaterial3D] = []
var _shadow_query := PhysicsRayQueryParameters3D.new()

func setup(w, d: Dictionary, settings: Dictionary) -> void:
	world = w
	data = d
	size = U.v3(d.get("size"), Vector3(0.9, 1.7, 0.9)).clamp(Vector3(0.2, 0.2, 0.2), Vector3(6, 6, 6))
	speed = U.num(d, "speed", 7.0)
	jump = U.num(d, "jump", 9.0)
	max_air_jumps = int(U.num(d, "air_jumps", 0))
	gravity = U.num(settings, "gravity", 24.0)
	spawn = U.v3(d.get("position"), Vector3(0, 2, 0))
	position = spawn
	velocity = Vector3.ZERO
	face_yaw = deg_to_rad(U.num(d, "facing", 0.0))
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50.0)
	cam_dist = clampf(7.0 + size.y * 1.4, 6.0, 14.0)
	for c in get_children():
		c.queue_free()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = size.x * 0.45
	cap.height = maxf(size.y, cap.radius * 2.0)
	cs.shape = cap
	add_child(cs)
	visual = Node3D.new()
	visual.position.y = -size.y * 0.5
	add_child(visual)
	shadow = FX3.blob_shadow(size.x * 0.65)
	shadow.top_level = true
	add_child(shadow)
	_shadow_query.collision_mask = 1
	_default_visual()
	refresh_asset(false)

## Placeholder toy character: rounded body, belly, eyes, little feet. Built at the feet origin.
func _default_visual() -> void:
	_clear_visual()
	var col := U.col(data.get("color"), U.default_color("player"))
	var r := size.x * 0.45
	var h := size.y
	_part(_capsule(r, h * 0.92), Mat.toy(col), Vector3(0, h * 0.48, 0))
	_part(_sphere(r * 0.7, h * 0.5), Mat.toy(col.lightened(0.55)), Vector3(0, h * 0.4, r * 0.4))
	for sx in [-1.0, 1.0]:
		var eye := Vector3(sx * r * 0.38, h * 0.7, r * 0.82)
		_part(_sphere(r * 0.24, r * 0.5), Mat.flat(Color.WHITE), eye)
		_part(_sphere(r * 0.13, r * 0.27), Mat.flat(Color("#1a1530")), eye + Vector3(0, 0, r * 0.15))
		_part(_sphere(r * 0.05, r * 0.1), Mat.flat(Color.WHITE), eye + Vector3(r * 0.04, r * 0.06, r * 0.26))
		_part(_sphere(r * 0.32, r * 0.36), Mat.toy(col.darkened(0.35)), Vector3(sx * r * 0.45, r * 0.15, r * 0.15))
	_cache_flash_materials()

func _capsule(r: float, h: float) -> CapsuleMesh:
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	return cm

func _sphere(r: float, h: float) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = h
	return sm

func _part(mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	visual.add_child(mi)

func _clear_visual() -> void:
	for c in visual.get_children():
		c.queue_free()
	model = null

func refresh_asset(animate: bool) -> void:
	var aid := U.str_of(data, "asset", "")
	if aid == "" or world.main.assets.state(aid) != "ready":
		return
	var res = world.main.assets.get_res(aid)
	var inst: Node3D = null
	if res is Node3D:
		inst = world.main.assets.instance_model(aid, Vector3(size.x * 1.6, size.y, size.z * 1.6))
		if inst:
			inst.position.y = size.y * 0.5  # instance_model centres on y; our pivot is at the feet
	elif res is Texture2D:
		var spr := Sprite3D.new()
		spr.texture = res
		spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		spr.pixel_size = size.y / maxf(res.get_size().y, 1.0)
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		spr.shaded = false
		spr.position.y = size.y * 0.5
		inst = spr
	if inst == null:
		return
	_clear_visual()
	model = inst
	visual.add_child(inst)
	_cache_flash_materials()
	if animate:
		inst.scale = Vector3.ONE * 0.05
		create_tween().tween_property(inst, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Collect the GeometryInstance3Ds so the hurt flash can overlay a white material on them.
func _cache_flash_materials() -> void:
	_flash_mats.clear()

func _set_flash(on: bool) -> void:
	_apply_overlay(visual, _hurt_overlay() if on else null)

static var _overlay: StandardMaterial3D
static func _hurt_overlay() -> StandardMaterial3D:
	if _overlay == null:
		_overlay = StandardMaterial3D.new()
		_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_overlay.albedo_color = Color(1, 0.35, 0.35, 0.6)
		_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return _overlay

func _apply_overlay(n: Node, m: Material) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).material_overlay = m
	for c in n.get_children():
		_apply_overlay(c, m)

# ---------------------------------------------------------------- gameplay API

func invincible() -> bool:
	return power == "invincible" or power == "star"

func apply_powerup(effect: String, dur: float) -> void:
	power = effect
	power_t = dur
	if effect == "double_jump":
		max_air_jumps = maxi(max_air_jumps, 1)

## Bouncer launch: strength is a multiple of the jump velocity.
func bounce(strength: float) -> void:
	velocity.y = jump * strength
	air_jumps = 0
	coyote = 0.0
	jump_held = false
	_stretch()

## Hop off a stomped enemy; holding jump gives a higher bounce.
func stomp_bounce(k: float) -> void:
	velocity.y = jump * (k + (0.35 if Input.is_action_pressed("jump") else 0.0))
	air_jumps = 0
	jump_held = false
	_stretch()

func hurt(from: Vector3) -> void:
	if hurt_cd > 0.0 or invincible() or respawning or not world.playing:
		return
	hurt_cd = HURT_TIME
	var d := global_position - from
	d.y = 0.0
	if d.length() < 0.01:
		d = -Vector3(sin(face_yaw), 0, cos(face_yaw))
	velocity = d.normalized() * KNOCKBACK + Vector3.UP * jump * 0.6
	world.player_hurt()

## Fell off the world: shrink out, then pop back in at the last checkpoint.
func _fall_out() -> void:
	respawning = true
	velocity = Vector3.ZERO
	if not world.player_fell():
		return
	var tw := create_tween()
	tw.tween_property(visual, "scale", Vector3.ONE * 0.01, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		position = spawn
		velocity = Vector3.ZERO
		FX3.ring(world, spawn - Vector3(0, size.y * 0.5, 0), Color.WHITE, 2.0)
		FX3.burst(world, spawn, Color("#fff3b0"), 14, 4.0))
	tw.tween_property(visual, "scale", Vector3.ONE, RESPAWN_SECS).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		respawning = false
		hurt_cd = 1.0)

func respawn() -> void:
	position = spawn
	velocity = Vector3.ZERO
	hurt_cd = 1.0

# ---------------------------------------------------------------- input & physics

func _unhandled_input(ev: InputEvent) -> void:
	if world == null or not world.playing:
		return
	var orbit_held := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if ev is InputEventMouseMotion and orbit_held:
		var mm := ev as InputEventMouseMotion
		cam_yaw -= mm.relative.x * 0.006
		cam_pitch = clampf(cam_pitch - mm.relative.y * 0.004, CAM_PITCH_MIN, CAM_PITCH_MAX)
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_dist = maxf(CAM_DIST_MIN, cam_dist - 0.8)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_dist = minf(CAM_DIST_MAX, cam_dist + 0.8)

func _physics_process(delta: float) -> void:
	if world == null:
		return
	if not world.playing or respawning:
		velocity = Vector3.ZERO
		_update_shadow()
		return
	_tick_timers(delta)
	if Input.is_action_pressed("cam_left"):
		cam_yaw += delta * CAM_KEY_SPEED
	if Input.is_action_pressed("cam_right"):
		cam_yaw -= delta * CAM_KEY_SPEED
	var iv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var wish := Basis(Vector3.UP, cam_yaw) * Vector3(iv.x, 0, iv.y)
	var on_floor := is_on_floor()
	if on_floor:
		coyote = COYOTE
		air_jumps = 0
	_apply_gravity(delta)
	_apply_horizontal(wish, on_floor, delta)
	_handle_jump()
	_fall_speed = -velocity.y
	move_and_slide()
	_after_move(wish, delta)

func _tick_timers(delta: float) -> void:
	hurt_cd = maxf(0.0, hurt_cd - delta)
	shoot_cd = maxf(0.0, shoot_cd - delta)
	coyote -= delta
	jump_buf -= delta
	if power_t > 0.0:
		power_t -= delta
		if power_t <= 0.0:
			power = ""

func _apply_gravity(delta: float) -> void:
	var g := gravity * (FALL_GRAVITY if velocity.y < 0.0 else 1.0)
	velocity.y = maxf(velocity.y - g * delta, -MAX_FALL)
	# Variable jump height: releasing jump while rising cuts the ascent.
	if jump_held and not Input.is_action_pressed("jump") and velocity.y > 0.0:
		velocity.y *= JUMP_CUT
		jump_held = false

func _apply_horizontal(wish: Vector3, on_floor: bool, delta: float) -> void:
	var top := speed * (1.6 if power == "speed" else 1.0)
	var hv := Vector2(velocity.x, velocity.z)
	var target := Vector2(wish.x, wish.z) * top
	var rate: float
	if target.length() > 0.01:
		rate = GROUND_ACCEL if on_floor else AIR_ACCEL
		if hv.dot(target) < 0.0:
			rate *= TURN_ACCEL_BOOST
	else:
		rate = GROUND_DECEL if on_floor else AIR_DECEL
	hv = hv.move_toward(target, rate * top * delta)
	velocity.x = hv.x
	velocity.z = hv.y

func _handle_jump() -> void:
	if Input.is_action_just_pressed("jump"):
		jump_buf = JUMP_BUFFER
	if jump_buf <= 0.0:
		return
	var jmp := jump * (1.3 if power == "high_jump" else 1.0)
	var feet := global_position - Vector3(0, size.y * 0.5, 0)
	if coyote > 0.0:
		velocity.y = jmp
		FX3.dust(world, feet, 6, 2.0)
	elif air_jumps < max_air_jumps:
		air_jumps += 1
		velocity.y = jmp * 0.9
		FX3.ring(world, feet, Color.WHITE, 1.2)
	else:
		return
	coyote = 0.0
	jump_buf = 0.0
	jump_held = true
	world.main.sfx("jump")
	_stretch()

func _after_move(wish: Vector3, delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		_land(_fall_speed)
	_was_on_floor = on_floor
	if global_position.y < world.kill_y:
		_fall_out()
		return
	if wish.length() > 0.1:
		face_yaw = lerp_angle(face_yaw, atan2(wish.x, wish.z), minf(1.0, delta * FACE_RATE))
	visual.rotation.y = face_yaw
	_animate(on_floor, delta)
	_update_shadow()
	if Input.is_action_just_pressed("action") and bool(data.get("can_shoot", false)) and shoot_cd <= 0.0:
		shoot_cd = 0.3
		world.spawn_projectile(global_position + Vector3(0, size.y * 0.2, 0), Vector3(sin(face_yaw), 0, cos(face_yaw)) * 18.0, Color("#ffd23f"), true)

func _land(impact: float) -> void:
	var k := clampf(impact / LAND_SQUASH_SPEED, 0.0, 1.0)
	if k < 0.25:
		return
	_squash = Vector3(1.0 + 0.3 * k, 1.0 - 0.35 * k, 1.0 + 0.3 * k)
	FX3.dust(world, global_position - Vector3(0, size.y * 0.5, 0), int(4 + 6 * k), 2.0 + 2.0 * k)
	world.main.sfx("land", -6.0 + 4.0 * k)

func _stretch() -> void:
	_squash = Vector3(0.75, 1.3, 0.75)

## Squash/stretch springs back to 1; running adds a waddle and periodic dust/step sounds.
func _animate(on_floor: bool, delta: float) -> void:
	_squash = _squash.lerp(Vector3.ONE, minf(1.0, delta * 10.0))
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var run := on_floor and hspeed > 0.8
	var bob := 0.0
	var lean := 0.0
	if run:
		walk_t += delta * (6.0 + hspeed * 1.3)
		bob = absf(sin(walk_t)) * 0.08 * size.y
		lean = sin(walk_t) * 0.12
		dust_t -= delta
		if dust_t <= 0.0:
			dust_t = RUN_DUST_EVERY
			FX3.dust(world, global_position - Vector3(0, size.y * 0.5, 0), 2, 1.0, Color(1, 1, 1, 0.55))
			world.main.sfx("step", STEP_SFX_DB)
	elif not on_floor:
		_squash = _squash.lerp(Vector3(0.92, 1.1, 0.92) if velocity.y > 0.0 else Vector3(1.04, 0.96, 1.04), minf(1.0, delta * 6.0))
	visual.position.y = -size.y * 0.5 + bob
	visual.rotation.z = lerpf(visual.rotation.z, lean, minf(1.0, delta * 12.0))
	visual.scale = _squash
	var blink := hurt_cd > 0.0 and int(hurt_cd * 14.0) % 2 == 0
	_set_flash(blink)

## Blob shadow on whatever is directly below the player, shrinking with height.
func _update_shadow() -> void:
	if shadow == null:
		return
	_shadow_query.from = global_position
	_shadow_query.to = global_position + Vector3.DOWN * SHADOW_RAY
	_shadow_query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(_shadow_query)
	if hit.is_empty():
		shadow.visible = false
		return
	shadow.visible = true
	var h: float = global_position.y - size.y * 0.5 - hit.position.y
	var k := clampf(1.0 - h / 10.0, 0.35, 1.0)
	shadow.global_position = hit.position + Vector3(0, 0.03, 0)
	shadow.scale = Vector3(k, 1, k)
	shadow.transparency = 1.0 - k
