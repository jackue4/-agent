extends RefCounted
## 3D-only effects: soft billboard particle bursts, dust puffs, shock rings, sparkle
## emitters, ground blob shadows and camera-following ambient particles. Textures,
## meshes and materials are cached statically so effects allocate only the emitter node.

enum Tex { SOFT, STAR, RING, LEAF }

const AMBIENT_KINDS := ["leaves", "snow", "dust", "stars", "bubbles", "petals"]
const AMBIENT_BOX := Vector3(26, 12, 26)
const BURST_LIFETIME := 0.7
const DUST_LIFETIME := 0.55
const RING_SECS := 0.4

static var _tex := {}
static var _mats := {}

# ---------------------------------------------------------------- shared resources

static func _texture(kind: int) -> Texture2D:
	if _tex.has(kind):
		return _tex[kind]
	var g := Gradient.new()
	var t := GradientTexture2D.new()
	t.width = 64
	t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	match kind:
		Tex.SOFT:
			g.set_color(0, Color(1, 1, 1, 1))
			g.add_point(0.45, Color(1, 1, 1, 0.75))
			g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		Tex.STAR:
			g.set_color(0, Color(1, 1, 1, 1))
			g.add_point(0.12, Color(1, 1, 1, 0.9))
			g.add_point(0.3, Color(1, 1, 1, 0.18))
			g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		Tex.RING:
			g.set_color(0, Color(1, 1, 1, 0.08))
			g.add_point(0.7, Color(1, 1, 1, 0.25))
			g.add_point(0.86, Color(1, 1, 1, 1))
			g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		Tex.LEAF:
			t.fill_to = Vector2(0.5, 0.1)
			g.set_color(0, Color(1, 1, 1, 1))
			g.add_point(0.8, Color(1, 1, 1, 1))
			g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	t.gradient = g
	_tex[kind] = t
	return t

## Billboard particle material; additive for glowing sparkles, alpha otherwise.
static func particle_material(kind: int, additive: bool, billboard := true) -> StandardMaterial3D:
	var key := "%d_%s_%s" % [kind, additive, billboard]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_texture = _texture(kind)
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mats[key] = m
	return m

static func _quad(kind: int, size: float, additive: bool, billboard := true) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = particle_material(kind, additive, billboard)
	return q

static func _fade(col: Color, peak := 0.15) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(col, 0.0))
	g.add_point(peak, col)
	g.set_color(g.get_point_count() - 1, Color(col, 0.0))
	return g

static func _shrink() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(1, 0.1))
	return c

static func _grow() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(0.4, 1.0))
	c.add_point(Vector2(1, 1.2))
	return c

static func _one_shot(parent: Node, p: CPUParticles3D, pos: Vector3) -> void:
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)

# ---------------------------------------------------------------- one-shot effects

## Colourful sparkle burst (pickups, stomps, spawns).
static func burst(parent: Node, pos: Vector3, col: Color, amount := 18, speed := 5.0) -> void:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = BURST_LIFETIME
	p.mesh = _quad(Tex.STAR, 0.5, true)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -7, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.scale_amount_curve = _shrink()
	p.color_ramp = _fade(col.lightened(0.35), 0.05)
	_one_shot(parent, p, pos)

## Soft dust puffs at the feet (jump, land, run). ring=true spreads them horizontally.
static func dust(parent: Node, pos: Vector3, amount := 8, speed := 2.5, col := Color(1, 1, 1, 0.75)) -> void:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = DUST_LIFETIME
	p.mesh = _quad(Tex.SOFT, 0.45, false)
	p.direction = Vector3.UP
	p.spread = 85.0
	p.flatness = 0.8
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, 1.0, 0)
	p.damping_min = 5.0
	p.damping_max = 7.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.scale_amount_curve = _grow()
	p.color_ramp = _fade(col, 0.1)
	_one_shot(parent, p, pos)

## Expanding flat shock ring on the ground (landing on enemies, checkpoints, bouncers).
static func ring(parent: Node, pos: Vector3, col: Color, radius := 1.5) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var m: StandardMaterial3D = particle_material(Tex.RING, true, false).duplicate()
	m.vertex_color_use_as_albedo = false
	m.albedo_color = col
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.05, 0)
	mi.scale = Vector3.ONE * radius * 0.2
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, RING_SECS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, RING_SECS).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)

## Continuous twinkle around an object (collectibles, goal, powerups).
static func sparkles(col: Color, radius: float, amount := 6) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.1
	p.mesh = _quad(Tex.STAR, 0.35, true)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 30.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.6
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	p.color_ramp = _fade(col.lightened(0.5), 0.3)
	p.local_coords = false
	return p

## Soft dark disc that sits under a character so players can read where they will land.
static func blob_shadow(radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _texture(Tex.SOFT)
	m.albedo_color = Color(0.05, 0.04, 0.12, 0.5)
	m.render_priority = -1
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

# ---------------------------------------------------------------- ambient particles

## Lightweight weather/ambience emitter; keep it centred on the camera every frame.
static func ambient(kind: String, tint: Color) -> CPUParticles3D:
	if not kind in AMBIENT_KINDS:
		return null
	var p := CPUParticles3D.new()
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = AMBIENT_BOX * 0.5
	p.preprocess = 6.0
	p.spread = 25.0
	match kind:
		"snow":
			p.amount = 140
			p.lifetime = 7.0
			p.mesh = _quad(Tex.SOFT, 0.14, false)
			p.direction = Vector3.DOWN
			p.initial_velocity_min = 1.0
			p.initial_velocity_max = 1.8
			p.gravity = Vector3(0.3, -0.2, 0)
			p.color = Color(1, 1, 1, 0.9)
		"leaves", "petals":
			p.amount = 40
			p.lifetime = 8.0
			p.mesh = _quad(Tex.LEAF, 0.22, false)
			p.direction = Vector3(0.6, -1, 0.2)
			p.initial_velocity_min = 0.7
			p.initial_velocity_max = 1.3
			p.gravity = Vector3(0.25, -0.15, 0.1)
			p.angular_velocity_min = -160.0
			p.angular_velocity_max = 160.0
			p.angle_max = 360.0
			p.scale_amount_min = 0.6
			p.scale_amount_max = 1.2
			var g := Gradient.new()
			if kind == "leaves":
				g.set_color(0, Color("#9ad14b"))
				g.set_color(1, Color("#f2a33a"))
			else:
				g.set_color(0, Color("#ffc4dd"))
				g.set_color(1, Color("#ff8fbf"))
			p.color_initial_ramp = g
		"dust":
			p.amount = 50
			p.lifetime = 8.0
			p.mesh = _quad(Tex.SOFT, 0.08, true)
			p.direction = Vector3.UP
			p.spread = 180.0
			p.initial_velocity_min = 0.05
			p.initial_velocity_max = 0.25
			p.gravity = Vector3.ZERO
			p.color_ramp = _fade(tint.lightened(0.6) * Color(1, 1, 1, 0.55), 0.5)
		"stars":
			p.amount = 60
			p.lifetime = 4.0
			p.mesh = _quad(Tex.STAR, 0.35, true)
			p.direction = Vector3.UP
			p.initial_velocity_min = 0.0
			p.initial_velocity_max = 0.15
			p.gravity = Vector3.ZERO
			p.scale_amount_min = 0.3
			p.scale_amount_max = 1.0
			p.color_ramp = _fade(Color(1.0, 0.95, 0.7), 0.5)
		"bubbles":
			p.amount = 45
			p.lifetime = 6.0
			p.mesh = _quad(Tex.RING, 0.3, false)
			p.direction = Vector3.UP
			p.initial_velocity_min = 0.5
			p.initial_velocity_max = 1.1
			p.gravity = Vector3(0, 0.15, 0)
			p.scale_amount_min = 0.4
			p.scale_amount_max = 1.2
			p.color_ramp = _fade(Color(0.85, 0.95, 1.0, 0.8), 0.2)
	return p
