extends Node2D
## One authored 2D entity: visual (procedural or AI sprite) + physics + behavior.
const U = preload("res://util.gd")
const FX = preload("res://fx.gd")
const ShapeDraw = preload("res://shape2d.gd")
const PlatformDraw = preload("res://platform2d.gd")

var id := ""
var data := {}
var kind := "decor"
var size := Vector2(100, 100)
var world = null
var visual: Node2D
var shape_node: Node2D
var plat_node: Node2D
var shadow: Node2D
var reached := false
var sprite: Sprite2D
var label: Label
var body: CollisionObject2D
var home := Vector2.ZERO
var t := 0.0
var alive := true
var dir := 1.0
var shoot_cd := 0.0
var asset_id := ""

static func to_godot(v: Vector2) -> Vector2:
	return Vector2(v.x, -v.y)

func setup(w, eid: String, d: Dictionary) -> void:
	world = w
	id = eid
	apply(d)

func apply(d: Dictionary) -> void:
	data = d
	kind = U.str_of(d, "kind", "decor")
	size = U.v2(d.get("size"), U.default_size_2d(kind)).clamp(Vector2(4, 4), Vector2(30000, 6000))
	home = to_godot(U.v2(d.get("position"), Vector2.ZERO))
	position = home
	rotation_degrees = -U.num(d, "rotation", 0.0)
	asset_id = U.str_of(d, "asset", "")
	t = randf() * 10.0
	z_index = -5 if kind == "decor" else (2 if kind in ["enemy", "collectible", "powerup"] else (-3 if kind in ["sign", "text", "checkpoint"] else 0))
	if U.str_of(d, "layer", "") == "front":
		z_index = 20
	_build()

func spec_position() -> Array:
	return [snappedf(position.x, 1.0), snappedf(-position.y, 1.0)]

func _build() -> void:
	for c in get_children():
		c.queue_free()
	visual = Node2D.new()
	add_child(visual)
	shape_node = ShapeDraw.new()
	shape_node.kind = kind
	shape_node.shape = U.str_of(data, "shape", "")
	shape_node.size = size
	shape_node.color = U.col(data.get("color"), U.default_color(kind))
	visual.add_child(shape_node)
	sprite = null
	plat_node = null
	if kind == "platform" and asset_id == "":
		plat_node = PlatformDraw.new()
		visual.add_child(plat_node)
		shape_node.visible = false
		_refresh_platform_look()
	if kind in ["enemy", "collectible", "powerup", "goal", "checkpoint"] and not world.topdown:
		_add_ground_shadow()
	if kind == "text" or kind == "sign":
		label = Label.new()
		label.text = U.clean_text(U.str_of(data, "text", U.str_of(data, "name", "")))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var fs := int(U.num(data, "font_size", 30 if kind == "text" else 20))
		if kind == "sign":
			fs = _fit_font(label.get_theme_font("font"), label.text, Vector2(size.x - 16, size.y * 0.62 - 6), fs)
		label.add_theme_font_size_override("font_size", fs)
		label.add_theme_color_override("font_color", U.col(data.get("color"), Color.WHITE) if kind == "text" else Color("#3b2414"))
		if kind == "text":
			label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
			label.add_theme_constant_override("outline_size", 8)
		if kind == "sign":
			label.size = Vector2(size.x - 16, size.y * 0.62 - 6)
			label.position = Vector2(-size.x * 0.5 + 8, -size.y * 0.5 + 3)
		else:
			label.size = size
			label.position = -size * 0.5
		label.z_index = 3
		visual.add_child(label)
	_build_body()
	refresh_asset(false)

## Largest font size (<= preferred) whose word-wrapped text fits the box, measured with the real font.
static func _fit_font(font: Font, text: String, box: Vector2, preferred: int) -> int:
	var fs := preferred
	while fs > 10:
		var sz := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, box.x, fs, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND)
		# 1.15: Label adds line spacing / outline that the raw measurement omits
		if sz.y * 1.15 <= box.y and sz.x <= box.x + 1.0:
			break
		fs -= 1
	return fs

func _build_body() -> void:
	var topdown: bool = world.topdown
	var rs := RectangleShape2D.new()
	match kind:
		"platform":
			var b := AnimatableBody2D.new()
			b.sync_to_physics = true
			b.collision_layer = 1
			b.collision_mask = 0
			var cs := CollisionShape2D.new()
			rs.size = size
			cs.shape = rs
			if not topdown and size.y <= 48.0 and not bool(data.get("solid", false)):
				cs.one_way_collision = true
				cs.one_way_collision_margin = 12.0
			b.add_child(cs)
			body = b
		"decor", "text", "sign":
			if bool(data.get("solid", false)):
				var sb := StaticBody2D.new()
				sb.collision_layer = 1
				var cs2 := CollisionShape2D.new()
				rs.size = size * 0.8
				cs2.shape = rs
				sb.add_child(cs2)
				body = sb
			else:
				body = null
		_:
			var a := Area2D.new()
			a.collision_layer = 4
			a.collision_mask = 2
			a.monitorable = false
			var cs3 := CollisionShape2D.new()
			rs.size = size * (0.8 if kind in ["enemy", "hazard"] else 1.0)
			if kind == "hazard":
				rs.size = Vector2(size.x * 0.9, size.y * 0.6)
				cs3.position = Vector2(0, size.y * 0.15)
			cs3.shape = rs
			a.add_child(cs3)
			a.body_entered.connect(_on_body_entered)
			body = a
	if body:
		body.set_meta("ent", self)
		add_child(body)

## Platforms without their own asset share the world-wide platform texture (world.platform_asset).
func _refresh_platform_look() -> void:
	if plat_node == null:
		return
	var wtex = null
	var pa := U.str_of(world.spec.get("world", {}), "platform_asset", "")
	if pa != "" and world.main.assets.state(pa) == "ready":
		wtex = world.main.assets.get_res(pa)
	var style := U.str_of(data, "style", U.str_of(data, "shape", ""))
	if style == "" :
		style = U.world_theme(world.spec)
	plat_node.setup(size, U.col(data.get("color"), U.default_color("platform")), style, wtex if wtex is Texture2D else null, hash(id))

func _add_ground_shadow() -> void:
	shadow = Node2D.new()
	shadow.z_index = -1
	shadow.position = Vector2(0, size.y * 0.5 - 2)
	var w := size.x * 0.42
	shadow.draw.connect(func():
		shadow.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.28))
		shadow.draw_circle(Vector2.ZERO, w, Color(0, 0, 0, 0.18)))
	add_child(shadow)

func refresh_asset(animate: bool) -> void:
	if not is_instance_valid(shape_node):
		return
	if plat_node:
		_refresh_platform_look()
		return
	var st: String = world.main.assets.state(asset_id) if asset_id != "" else "none"
	shape_node.pending = st == "pending" or st == "loading"
	shape_node.failed = st == "failed"
	if st == "ready":
		var tex = world.main.assets.get_res(asset_id)
		if tex is Texture2D:
			_apply_texture(tex, animate)
	elif sprite:
		sprite.queue_free()
		sprite = null
		shape_node.visible = true

func _apply_texture(tex: Texture2D, animate: bool) -> void:
	if sprite == null:
		sprite = Sprite2D.new()
		visual.add_child(sprite)
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if String(data.get("filter", world.main.style_filter())) == "pixel":
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var ts := tex.get_size()
	if kind == "platform":
		var s := size.y / ts.y
		sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0, 0, size.x / s, ts.y)
		sprite.scale = Vector2(s, s)
	else:
		var k := minf(size.x / ts.x, size.y / ts.y)
		if kind in ["enemy", "player", "goal"]:
			k = size.y / ts.y
		sprite.scale = Vector2(k, k)
		sprite.region_enabled = false
		if kind in ["enemy", "goal", "decor"]:
			sprite.position.y = size.y * 0.5 - ts.y * k * 0.5
	shape_node.visible = kind == "sign"
	if kind == "sign":
		sprite.visible = false
		shape_node.visible = true
	if animate:
		var target := sprite.scale
		sprite.scale = target * 0.2
		sprite.modulate = Color(3, 3, 3, 0.3)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(sprite, "scale", target, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(sprite, "modulate", Color.WHITE, 0.6)
		FX.sparkle2d(world, global_position, maxf(size.x, size.y) * 0.5)

func set_facing(f: float) -> void:
	if sprite:
		sprite.flip_h = f < 0
	if shape_node:
		shape_node.facing = f

func _physics_process(delta: float) -> void:
	if world == null or not world.playing or not alive:
		return
	t += delta
	var beh = data.get("behavior", {})
	var btype := ""
	if typeof(beh) == TYPE_STRING:
		btype = beh
		beh = {}
	elif typeof(beh) == TYPE_DICTIONARY:
		btype = U.str_of(beh, "type", "")
	if btype == "" and kind == "collectible":
		btype = "float"
	if btype == "":
		return
	var speed := U.num(beh, "speed", 120.0 if kind != "platform" else 100.0)
	var rng := U.num(beh, "range", 200.0)
	var axis := U.str_of(beh, "axis", "x")
	match btype:
		"patrol", "move":
			var ax := Vector2.RIGHT if axis == "x" else Vector2.DOWN
			position += ax * dir * speed * delta
			var off := (position - home).dot(ax)
			if off > rng:
				dir = -1.0
			elif off < -rng:
				dir = 1.0
			if axis == "x":
				set_facing(dir)
		"chase":
			var p = world.player
			if p and is_instance_valid(p):
				var d: Vector2 = p.global_position - global_position
				var radius := U.num(beh, "radius", 450.0)
				if d.length() < radius:
					if world.topdown:
						position += d.normalized() * speed * delta
					else:
						position.x += signf(d.x) * speed * delta
					set_facing(signf(d.x))
				else:
					position = position.move_toward(home, speed * 0.5 * delta)
		"float":
			position.y = home.y + sin(t * maxf(speed, 1.0) / 60.0) * minf(rng, 14.0 if kind == "collectible" else rng)
		"fly":
			position.y = home.y + sin(t * 2.0) * rng * 0.5
			position.x += dir * speed * delta
			if absf(position.x - home.x) > rng:
				dir = -signf(position.x - home.x)
			set_facing(dir)
		"spin":
			visual.rotation += delta * speed / 40.0
		"shoot":
			shoot_cd -= delta
			var p2 = world.player
			if p2 and is_instance_valid(p2) and shoot_cd <= 0.0:
				var dd: Vector2 = p2.global_position - global_position
				if dd.length() < U.num(beh, "radius", 600.0):
					shoot_cd = U.num(beh, "interval", 2.0)
					world.spawn_projectile(global_position, dd.normalized() * U.num(beh, "bullet_speed", 320.0), U.col(data.get("color"), Color("#ff595e")))
					set_facing(signf(dd.x))

func _on_body_entered(b: Node) -> void:
	if not alive or world == null or not world.playing:
		return
	if b != world.player:
		return
	var p = world.player
	match kind:
		"collectible":
			alive = false
			world.collect(self, int(U.num(data, "value", 1)))
			fly_to_player()
		"hazard":
			p.hurt(global_position)
		"enemy":
			var stompable := bool(data.get("stompable", true))
			if not world.topdown and stompable and p.velocity.y > 50.0 and p.global_position.y < global_position.y - size.y * 0.2:
				alive = false
				p.bounce(0.7)
				world.enemy_stomped(self, int(U.num(data, "value", 5)))
				if shadow:
					shadow.visible = false
				visual.position.y = size.y * 0.4
				var tw := create_tween()
				tw.tween_property(visual, "scale", Vector2(1.5, 0.15), 0.08)
				tw.tween_interval(0.25)
				tw.tween_property(visual, "modulate:a", 0.0, 0.2)
				tw.tween_callback(queue_free)
			elif p.invincible():
				alive = false
				world.enemy_defeated(self, int(U.num(data, "value", 5)))
				_pop_away()
			else:
				p.hurt(global_position)
		"goal":
			world.reach_goal(self)
		"checkpoint":
			if not reached:
				reached = true
				shape_node.pending = false
				shape_node.raised = true
				shape_node.color = Color("#ffd23f")
				_wiggle_up()
				world.reach_checkpoint(self)
		"powerup":
			alive = false
			p.apply_powerup(U.str_of(data, "effect", "speed"), U.num(data, "duration", 8.0))
			world.main.sfx("sparkle")
			FX.float_text2d(world, global_position, U.str_of(data, "name", "道具"), Color("#c77dff"))
			_pop_away()
		"bouncer":
			p.bounce(U.num(data, "strength", 1.5))
			world.main.sfx("jump")
			var tw2 := create_tween()
			tw2.tween_property(visual, "scale", Vector2(1.2, 0.6), 0.08)
			tw2.tween_property(visual, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _wiggle_up() -> void:
	var tw := create_tween()
	tw.tween_property(visual, "scale", Vector2(1.25, 0.8), 0.07)
	tw.tween_property(visual, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## Collectibles fly into the player and shrink, instead of just vanishing.
func fly_to_player() -> void:
	if shadow:
		shadow.visible = false
	var p = world.player
	var tw := create_tween().set_parallel(true)
	tw.tween_property(visual, "scale", Vector2(1.5, 1.5), 0.08)
	tw.chain().tween_method(func(k: float):
		if is_instance_valid(p):
			global_position = global_position.lerp(p.global_position + Vector2(0, -p.size.y * 0.3), k)
		visual.scale = Vector2.ONE * lerpf(1.5, 0.2, k), 0.0, 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)

func _pop_away() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(visual, "scale", Vector2(1.6, 1.6), 0.2)
	tw.tween_property(visual, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(queue_free)

func world_rect() -> Rect2:
	return Rect2(global_position - size * 0.5, size)
