extends CharacterBody2D
## Player controller for 2D: platformer (gravity, coyote time, jump buffer) or top-down (8-way).
const U = preload("res://util.gd")
const FX = preload("res://fx.gd")
const ShapeDraw = preload("res://shape2d.gd")

## Feel tuning (see server/engine.mjs reachability model — keep in sync).
const FALL_GRAVITY_MULT := 1.3
const MAX_FALL := 1500.0
const GROUND_ACCEL := 10.0
const AIR_ACCEL := 6.0
const COYOTE := 0.1
const JUMP_BUFFER := 0.12
const JUMP_CUT := 0.45
const STEP_INTERVAL := 0.26

var world = null
var data := {}
var size := Vector2(64, 64)
var speed := 360.0
var jump := 760.0
var gravity := 1900.0
var topdown := false
var spawn := Vector2.ZERO
var visual: Node2D
var shape_node: Node2D
var sprite: Sprite2D
var coyote := 0.0
var jump_buf := 0.0
var hurt_cd := 0.0
var power := ""
var power_t := 0.0
var air_jumps := 0
var max_air_jumps := 0
var facing := 1.0
var walk_t := 0.0
var was_on_floor := true
var shoot_cd := 0.0
var step_t := 0.0
var fall_peak := 0.0
var dying := false
var _squash_tw: Tween

func setup(w, d: Dictionary, settings: Dictionary) -> void:
	world = w
	data = d
	topdown = w.topdown
	size = U.v2(d.get("size"), Vector2(64, 64)).clamp(Vector2(16, 16), Vector2(400, 400))
	speed = U.num(d, "speed", 360.0)
	jump = U.num(d, "jump", 760.0)
	max_air_jumps = int(U.num(d, "air_jumps", 0))
	gravity = U.num(settings, "gravity", 1900.0)
	spawn = Vector2(U.v2(d.get("position"), Vector2(0, 80)).x, -U.v2(d.get("position"), Vector2(0, 80)).y)
	position = spawn
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 8.0
	floor_max_angle = deg_to_rad(50)
	if topdown:
		motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	for c in get_children():
		c.queue_free()
	var cs := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = size.x * 0.36
	cap.height = maxf(size.y * 0.95, cap.radius * 2.0)
	cs.shape = cap
	add_child(cs)
	visual = Node2D.new()
	add_child(visual)
	_add_shadow()
	shape_node = ShapeDraw.new()
	shape_node.kind = "player"
	shape_node.size = size
	shape_node.color = U.col(d.get("color"), U.default_color("player"))
	visual.add_child(shape_node)
	sprite = null
	refresh_asset(false)
	z_index = 10

func _add_shadow() -> void:
	var sh := Node2D.new()
	sh.z_index = -1
	sh.position = Vector2(0, size.y * 0.48)
	var w := size.x * 0.38
	sh.draw.connect(func():
		sh.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.3))
		sh.draw_circle(Vector2.ZERO, w, Color(0, 0, 0, 0.22)))
	add_child(sh)
	move_child(sh, 0)

func refresh_asset(animate: bool) -> void:
	var aid := U.str_of(data, "asset", "")
	var st: String = world.main.assets.state(aid) if aid != "" else "none"
	shape_node.pending = st == "pending" or st == "loading"
	shape_node.failed = st == "failed"
	if st == "ready":
		var tex = world.main.assets.get_res(aid)
		if tex is Texture2D:
			if sprite == null:
				sprite = Sprite2D.new()
				visual.add_child(sprite)
			sprite.texture = tex
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if world.main.style_filter() == "pixel" else CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			var k: float = size.y * 1.15 / tex.get_size().y
			sprite.scale = Vector2(k, k)
			sprite.position.y = size.y * 0.5 - tex.get_size().y * k * 0.5
			shape_node.visible = false
			if animate:
				sprite.scale = Vector2(k, k) * 0.2
				create_tween().tween_property(sprite, "scale", Vector2(k, k), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				FX.sparkle2d(world, global_position, size.x)

func invincible() -> bool:
	return power == "invincible" or power == "star"

func apply_powerup(effect: String, dur: float) -> void:
	power = effect
	power_t = dur
	if effect == "double_jump":
		max_air_jumps = maxi(max_air_jumps, 1)

func bounce(strength: float) -> void:
	velocity.y = -jump * strength
	air_jumps = 0

func hurt(from: Vector2) -> void:
	if hurt_cd > 0.0 or invincible() or world == null or not world.playing:
		return
	hurt_cd = 1.2
	velocity = (global_position - from).normalized() * 500.0
	if not topdown:
		velocity.y = -500.0
	world.player_hurt()

func set_checkpoint(p: Vector2) -> void:
	spawn = p

## Fell out of the world: pop out, then reappear at the last checkpoint with a sparkle.
func respawn() -> void:
	dying = true
	velocity = Vector2.ZERO
	visual.visible = false
	await get_tree().create_timer(0.45).timeout
	if not is_instance_valid(self):
		return
	position = spawn
	velocity = Vector2.ZERO
	hurt_cd = 1.0
	visual.visible = true
	visual.scale = Vector2(0.2, 0.2)
	create_tween().tween_property(visual, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	FX.sparkle2d(world, global_position, size.x * 0.6)
	dying = false

func _physics_process(delta: float) -> void:
	if world == null:
		return
	if not world.playing or dying:
		velocity = Vector2.ZERO
		_animate(delta, false)
		return
	hurt_cd = maxf(0.0, hurt_cd - delta)
	shoot_cd = maxf(0.0, shoot_cd - delta)
	if power_t > 0.0:
		power_t -= delta
		if power_t <= 0.0:
			power = ""
	var spd := speed * (1.6 if power == "speed" else 1.0)
	var jmp := jump * (1.3 if power == "high_jump" else 1.0)
	var ix := Input.get_axis("move_left", "move_right")
	if topdown:
		var iv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		velocity = velocity.move_toward(iv * spd, spd * 10.0 * delta)
		if absf(iv.x) > 0.1:
			facing = signf(iv.x)
		move_and_slide()
	else:
		var on_floor := is_on_floor()
		if on_floor:
			coyote = COYOTE
			air_jumps = 0
			if not was_on_floor:
				_on_land(fall_peak)
			fall_peak = 0.0
		else:
			coyote -= delta
			fall_peak = maxf(fall_peak, velocity.y)
		was_on_floor = on_floor
		var g := gravity * (FALL_GRAVITY_MULT if velocity.y > 0.0 else 1.0)
		velocity.y = minf(velocity.y + g * delta, MAX_FALL)
		var accel := spd * (GROUND_ACCEL if on_floor else AIR_ACCEL)
		velocity.x = move_toward(velocity.x, ix * spd, accel * delta)
		if absf(ix) > 0.1:
			facing = signf(ix)
		if Input.is_action_just_pressed("jump"):
			jump_buf = JUMP_BUFFER
		else:
			jump_buf -= delta
		if jump_buf > 0.0:
			if coyote > 0.0:
				velocity.y = -jmp
				coyote = 0.0
				jump_buf = 0.0
				world.main.sfx("jump")
				_squash(Vector2(0.72, 1.32))
				FX.dust2d(world, _feet(), 6, 0.0)
			elif air_jumps < max_air_jumps:
				air_jumps += 1
				velocity.y = -jmp * 0.9
				jump_buf = 0.0
				world.main.sfx("jump", 0.0)
				_squash(Vector2(0.8, 1.2))
				FX.burst2d(world, _feet(), Color.WHITE, 10, 140)
		if Input.is_action_just_released("jump") and velocity.y < -jmp * JUMP_CUT:
			velocity.y = -jmp * JUMP_CUT
		move_and_slide()
		if on_floor and absf(velocity.x) > spd * 0.5:
			step_t -= delta
			if step_t <= 0.0:
				step_t = STEP_INTERVAL
				world.main.sfx("step")
				FX.dust2d(world, _feet() - Vector2(facing * size.x * 0.2, 0), 3, -facing)
		if global_position.y > world.kill_y:
			world.player_fell()
	if Input.is_action_just_pressed("action") and bool(data.get("can_shoot", false)) and shoot_cd <= 0.0:
		shoot_cd = 0.35
		var dirv := Vector2(facing, 0)
		world.spawn_projectile(global_position, dirv * 700.0, Color("#ffd23f"), true)
	_animate(delta, velocity.length() > 20.0)

func _feet() -> Vector2:
	return global_position + Vector2(0, size.y * 0.47)

## Landing feedback scales with impact speed so small hops stay subtle.
func _on_land(impact: float) -> void:
	var k := clampf(impact / 1200.0, 0.0, 1.0)
	if k < 0.15:
		return
	_squash(Vector2(1.0 + 0.35 * k, 1.0 - 0.28 * k))
	FX.dust2d(world, _feet(), int(4 + 8 * k), 0.0)
	world.main.sfx("land", -6.0 + 6.0 * k)
	if k > 0.85:
		world.main.shake(4.0)

func _squash(s: Vector2) -> void:
	if visual == null:
		return
	if _squash_tw and _squash_tw.is_valid():
		_squash_tw.kill()
	visual.scale = s
	_squash_tw = create_tween()
	_squash_tw.tween_property(visual, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _animate(delta: float, moving: bool) -> void:
	if visual == null:
		return
	if sprite:
		sprite.flip_h = facing < 0 if not bool(data.get("faces_left", false)) else facing > 0
	shape_node.facing = facing
	# keep the feet planted while squashing: scale pivots at the bottom of the body
	visual.position.y = size.y * 0.5 * (1.0 - visual.scale.y)
	var grounded := topdown or is_on_floor()
	var target_rot := 0.0
	if moving and grounded:
		walk_t += delta * 13.0
		target_rot = sin(walk_t) * 0.09
		visual.position.y -= absf(sin(walk_t)) * size.y * 0.05
	elif not grounded:
		target_rot = clampf(velocity.x / maxf(speed, 1.0), -1.0, 1.0) * 0.12
	visual.rotation = lerpf(visual.rotation, target_rot, minf(1.0, delta * 14.0))
	if hurt_cd > 0.0:
		visual.modulate.a = 0.35 if int(hurt_cd * 12.0) % 2 == 0 else 1.0
	elif invincible():
		visual.modulate = Color.from_hsv(fmod(Time.get_ticks_msec() / 400.0, 1.0), 0.5, 1.0)
	else:
		visual.modulate = Color.WHITE
