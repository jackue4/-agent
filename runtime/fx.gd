extends RefCounted
## One-shot visual effects (particles, floating text) shared by 2D and 3D worlds.

static func burst2d(parent: Node, pos: Vector2, col: Color, amount := 28, spread := 260.0) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = spread * 0.4
	p.initial_velocity_max = spread
	p.gravity = Vector2(0, 600)
	p.scale_amount_min = 4.0
	p.scale_amount_max = 9.0
	var g := Gradient.new()
	g.set_color(0, col.lightened(0.4))
	g.set_color(1, Color(col, 0.0))
	p.color_ramp = g
	p.position = pos
	p.z_index = 50
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

## Soft puffs of dust at the feet. dir_x biases the puffs backwards when running (-1/0/1).
static func dust2d(parent: Node, pos: Vector2, amount := 8, dir_x := 0.0) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = maxi(amount, 1)
	p.lifetime = 0.45
	p.explosiveness = 0.95
	p.direction = Vector2(dir_x, -0.4).normalized() if dir_x != 0.0 else Vector2.UP
	p.spread = 70.0 if dir_x != 0.0 else 85.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 140.0
	p.gravity = Vector2(0, -60)
	p.damping_min = 120.0
	p.damping_max = 200.0
	p.scale_amount_min = 5.0
	p.scale_amount_max = 11.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.6))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1, 0.0))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.75))
	g.set_color(1, Color(0.95, 0.92, 0.88, 0.0))
	p.color_ramp = g
	p.position = pos
	p.z_index = 15
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

## Expanding ring, used for stomps, checkpoints and pickups.
static func ring2d(parent: Node, pos: Vector2, col: Color, radius := 60.0, dur := 0.35) -> void:
	var n := Node2D.new()
	n.position = pos
	n.z_index = 55
	var k := [0.0]
	n.draw.connect(func():
		var kk: float = k[0]
		var a := 1.0 - kk
		n.draw_arc(Vector2.ZERO, radius * (0.3 + 0.7 * kk), 0.0, TAU, 40, Color(col, a), 6.0 * a + 1.0, true))
	parent.add_child(n)
	var tw := n.create_tween()
	tw.tween_method(func(v: float): k[0] = v; n.queue_redraw(), 0.0, 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(n.queue_free)

## Looping screen-space ambience particles. Returns null for "" / "none" / unknown kinds.
static func ambient2d(kind: String, vs: Vector2) -> CPUParticles2D:
	var cfg := {
		"leaves": {"col": Color("#f4a259"), "col2": Color("#8cb369"), "amount": 18, "vel": Vector2(-40, 70), "size": [7.0, 12.0], "spin": 90.0},
		"petals": {"col": Color("#ffc8dd"), "col2": Color("#ffafcc"), "amount": 22, "vel": Vector2(-50, 55), "size": [5.0, 9.0], "spin": 120.0},
		"snow": {"col": Color(1, 1, 1, 0.9), "col2": Color("#dfe9ff"), "amount": 70, "vel": Vector2(-15, 70), "size": [3.0, 7.0], "spin": 0.0},
		"dust": {"col": Color(1, 0.95, 0.8, 0.45), "col2": Color(1, 1, 1, 0.3), "amount": 30, "vel": Vector2(12, -8), "size": [2.0, 4.0], "spin": 0.0},
		"stars": {"col": Color(1, 1, 0.85, 0.9), "col2": Color("#c8b6ff"), "amount": 40, "vel": Vector2(0, -6), "size": [2.0, 4.5], "spin": 0.0},
		"bubbles": {"col": Color(0.85, 0.95, 1, 0.45), "col2": Color(1, 1, 1, 0.3), "amount": 26, "vel": Vector2(0, -60), "size": [5.0, 12.0], "spin": 0.0},
	}
	if not cfg.has(kind):
		return null
	var c: Dictionary = cfg[kind]
	var p := CPUParticles2D.new()
	p.amount = int(c["amount"])
	p.lifetime = 12.0
	p.preprocess = 12.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = vs * 0.6
	p.position = vs * 0.5
	var v: Vector2 = c["vel"]
	p.direction = v.normalized()
	p.spread = 25.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = v.length() * 0.6
	p.initial_velocity_max = v.length() * 1.2
	p.scale_amount_min = float(c["size"][0])
	p.scale_amount_max = float(c["size"][1])
	p.angular_velocity_min = -float(c["spin"])
	p.angular_velocity_max = float(c["spin"])
	var g := Gradient.new()
	g.set_color(0, Color(c["col"], 0.0))
	g.add_point(0.15, c["col"])
	g.add_point(0.85, c["col2"])
	g.set_color(g.get_point_count() - 1, Color(c["col2"], 0.0))
	p.color_ramp = g
	if kind == "stars":
		p.hue_variation_min = -0.05
		p.hue_variation_max = 0.05
	return p

static func sparkle2d(parent: Node, pos: Vector2, radius: float) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = 40
	p.lifetime = 0.9
	p.explosiveness = 0.85
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector2.UP
	p.spread = 60.0
	p.gravity = Vector2(0, -120)
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 90.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 7.0
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 0.7, 1))
	g.add_point(0.5, Color(0.7, 0.5, 1.0, 0.9))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	p.color_ramp = g
	p.position = pos
	p.z_index = 60
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

static func float_text2d(parent: Node, pos: Vector2, text: String, col: Color, size := 30) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	l.z_index = 80
	parent.add_child(l)
	l.position = pos - Vector2(l.get_minimum_size().x * 0.5, 20)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 70.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tw.chain().tween_callback(l.queue_free)

static func burst3d(parent: Node, pos: Vector3, col: Color, amount := 28, speed := 6.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.8
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var m := SphereMesh.new()
	m.radius = 0.08
	m.height = 0.16
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material = mat
	p.mesh = m
	var g := Gradient.new()
	g.set_color(0, col.lightened(0.4))
	g.set_color(1, Color(col, 0.0))
	p.color_ramp = g
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)

static func float_text3d(parent: Node, pos: Vector3, text: String, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 64
	l.pixel_size = 0.006
	l.modulate = col
	l.outline_size = 14
	l.no_depth_test = true
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 1.5, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tw.chain().tween_callback(l.queue_free)
