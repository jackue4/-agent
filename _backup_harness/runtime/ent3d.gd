extends Node3D
## One authored 3D entity: procedural toy-like visual (or an AI model/sprite asset), its
## physics body, behaviour and juice. Node layout:
##   self (spec position, moved by behaviours) -> visual (spawn/edit tweens) -> anim
##   (per-frame procedural animation: bob, spin, breathe, squash) -> meshes / asset model.
const U = preload("res://util.gd")
const FX = preload("res://fx.gd")
const FX3 = preload("res://fx3d.gd")
const Mat = preload("res://mat3d.gd")
const Mesh3D = preload("res://mesh3d.gd")
const Terrain = preload("res://terrain3d.gd")

## Kinds introduced by the 3D runtime that util.gd doesn't know about yet.
const EXTRA_DEFAULTS := {"checkpoint": {"size": Vector3(1, 2.2, 1), "color": Color("#4cc9f0"), "label": "检查点"}}
const SPIN_SPEED := 2.2
const BOB_HEIGHT := 0.14
const BOB_SPEED := 2.6
const BREATHE := 0.06
const TURN_RATE := 8.0
const PICKUP_SECS := 0.32
const STOMP_BOUNCE := 0.75
const BEAM_HEIGHT := 9.0
const SNAP_RAY := 8.0
const WOOD := Color("#9a6a3f")
const SPIKE_MAX := 8

var id := ""
var data := {}
var kind := "decor"
var size := Vector3(2, 2, 2)
var world = null
var visual: Node3D
var anim: Node3D
var model: Node3D
var body: CollisionObject3D
var home := Vector3.ZERO
var t := 0.0
var alive := true
var dir := 1.0
var shoot_cd := 0.0
var asset_id := ""
var pending_fx: MeshInstance3D
var _flag: Node3D          # goal / checkpoint flag
var _pad: Node3D           # bouncer top
var _ground_fx: Node3D     # goal ring + beam, snapped to the floor below
var _snapped := false
var _reached := false      # checkpoint raised
var _squashed := false

func setup(w, eid: String, d: Dictionary) -> void:
	world = w
	id = eid
	apply(d)

func apply(d: Dictionary) -> void:
	data = d
	kind = U.str_of(d, "kind", "decor")
	size = U.v3(d.get("size"), default_size()).clamp(Vector3(0.1, 0.1, 0.1), Vector3(500, 200, 500))
	home = U.v3(d.get("position"), Vector3.ZERO)
	position = home
	rotation_degrees = Vector3(0, U.num(d, "rotation", 0.0), 0)
	asset_id = U.str_of(d, "asset", "")
	t = randf() * 10.0
	_build()

func default_size() -> Vector3:
	return EXTRA_DEFAULTS[kind].size if EXTRA_DEFAULTS.has(kind) else U.default_size_3d(kind)

func default_color() -> Color:
	return EXTRA_DEFAULTS[kind].color if EXTRA_DEFAULTS.has(kind) else U.default_color(kind)

func base_color() -> Color:
	return U.col(data.get("color"), default_color())

func kind_label() -> String:
	return EXTRA_DEFAULTS[kind].label if EXTRA_DEFAULTS.has(kind) else U.kind_label(kind)

func uses_asset(aid: String) -> bool:
	return asset_id == aid

func world_aabb() -> AABB:
	return AABB(global_position - size * 0.5, size)

# ---------------------------------------------------------------- building

func _mesh(mesh: Mesh, mat: Material, pos := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	(parent if parent else anim).add_child(mi)
	return mi

func _sphere(r: float, h: float, mat: Material, pos := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = h
	sm.radial_segments = 24
	sm.rings = 12
	return _mesh(sm, mat, pos, parent)

func _cyl(top: float, bottom: float, h: float, mat: Material, pos := Vector3.ZERO, segs := 20) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	return _mesh(cm, mat, pos)

func _build() -> void:
	for c in get_children():
		c.queue_free()
	visual = Node3D.new()
	add_child(visual)
	anim = Node3D.new()
	visual.add_child(anim)
	model = null
	_flag = null
	_pad = null
	_ground_fx = null
	_snapped = false
	_reached = false
	_build_visual()
	_build_body()
	refresh_asset(false)

func _build_visual() -> void:
	var col := base_color()
	match kind:
		"platform": refresh_terrain()
		"collectible": _build_collectible(col)
		"enemy": _build_enemy(col)
		"hazard": _build_spikes(col)
		"goal": _build_goal(col)
		"checkpoint": _build_checkpoint(col)
		"powerup": _build_powerup(col)
		"bouncer": _build_bouncer(col)
		"sign": _build_sign(col)
		"text": _build_text(col)
		_: _build_decor(U.str_of(data, "shape", ""), col)

## Platform terrain mesh; texture from its own texture asset or world.platform_asset.
func refresh_terrain() -> void:
	if kind != "platform" or model != null:
		return
	for c in anim.get_children():
		c.queue_free()
	var tex: Texture2D = world.texture_asset(asset_id)
	if tex == null:
		tex = world.texture_asset(U.str_of(world.world_dict(), "platform_asset", ""))
	var col := base_color()
	var theme := Terrain.theme_for(col, world.terrain_theme())
	anim.add_child(Terrain.platform(size, col, theme, world.is_floating(home, size), tex))

func _build_collectible(col: Color) -> void:
	var s := size
	match U.str_of(data, "shape", ""):
		"gem", "diamond", "crystal":
			_mesh(Mesh3D.gem(s * Vector3(0.8, 1.0, 0.8)), Mat.toy(col, 0.6, 0.2))
		"star":
			_mesh(Mesh3D.star(Vector3(s.x, s.y, s.z * 0.35)), Mat.toy(col, 0.7))
		"heart", "fruit", "apple", "orb", "sphere":
			_sphere(s.x * 0.45, s.y * 0.9, Mat.toy(col, 0.5))
		_:
			var coin := _cyl(s.x * 0.5, s.x * 0.5, s.y * 0.16, Mat.toy(col, 0.6, 0.6), Vector3.ZERO, 24)
			coin.rotation_degrees = Vector3(90, 0, 0)
			var inner := _cyl(s.x * 0.3, s.x * 0.3, s.y * 0.2, Mat.toy(col.lightened(0.25), 0.8, 0.6), Vector3.ZERO, 24)
			inner.rotation_degrees = Vector3(90, 0, 0)
	add_child(FX3.sparkles(col, maxf(s.x, 0.4) * 0.8, 4))

func _build_enemy(col: Color) -> void:
	var s := size
	var body_mi := _sphere(s.x * 0.5, s.y * 0.92, Mat.toy(col), Vector3(0, -s.y * 0.04, 0))
	body_mi.name = "Body"
	_sphere(s.x * 0.34, s.y * 0.5, Mat.toy(col.lightened(0.35)), Vector3(0, -s.y * 0.14, s.z * 0.2))
	for sx in [-1.0, 1.0]:
		var eye := Vector3(sx * s.x * 0.17, s.y * 0.1, s.z * 0.4)
		_sphere(s.x * 0.13, s.x * 0.3, Mat.flat(Color.WHITE), eye)
		_sphere(s.x * 0.07, s.x * 0.16, Mat.flat(Color("#1a1530")), eye + Vector3(0, -0.01, s.x * 0.08))
		_sphere(s.x * 0.025, s.x * 0.05, Mat.flat(Color.WHITE), eye + Vector3(s.x * 0.02, s.x * 0.03, s.x * 0.14))
		var brow := _mesh(_box(Vector3(s.x * 0.22, s.x * 0.05, s.x * 0.05)), Mat.flat(Color("#1a1530")), eye + Vector3(0, s.x * 0.17, 0.02))
		brow.rotation.z = -sx * 0.4
		_sphere(s.x * 0.14, s.y * 0.14, Mat.toy(col.darkened(0.45)), Vector3(sx * s.x * 0.22, -s.y * 0.47, s.z * 0.08))

func _box(v: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = v
	return b

## Metal spikes on a dark plate, drawn as one MultiMesh.
func _build_spikes(col: Color) -> void:
	var s := size
	var plate_h := s.y * 0.22
	_mesh(_box(Vector3(s.x, plate_h, s.z)), Mat.toy(Color("#4a4458")), Vector3(0, -s.y * 0.5 + plate_h * 0.5, 0))
	var nx := clampi(int(s.x / 0.55), 1, SPIKE_MAX)
	var nz := clampi(int(s.z / 0.55), 1, SPIKE_MAX)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = minf(s.x / nx, s.z / nz) * 0.42
	cone.height = s.y - plate_h
	cone.radial_segments = 8
	cone.rings = 1
	cone.material = Mat.toy(col.lightened(0.2), 0.0, 0.7)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cone
	mm.instance_count = nx * nz
	var y := -s.y * 0.5 + plate_h + cone.height * 0.5
	for ix in nx:
		for iz in nz:
			var p := Vector3(-s.x * 0.5 + (ix + 0.5) * s.x / nx, y, -s.z * 0.5 + (iz + 0.5) * s.z / nz)
			mm.set_instance_transform(ix * nz + iz, Transform3D(Basis.IDENTITY, p))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	anim.add_child(mmi)

func _build_goal(col: Color) -> void:
	var s := size
	if U.str_of(data, "shape", "") in ["star", "crown", "trophy"]:
		_mesh(Mesh3D.star(Vector3(s.x, s.y, s.z * 0.35)), Mat.toy(col, 0.8))
	else:
		var foot := -s.y * 0.5
		_cyl(0.07, 0.07, s.y, Mat.toy(Color("#f4f1ea"), 0.0, 0.3))
		_sphere(0.14, 0.28, Mat.toy(Color("#ffd23f"), 0.6, 0.6), Vector3(0, s.y * 0.5 + 0.1, 0))
		_flag = Node3D.new()
		_flag.position = Vector3(0, s.y * 0.5 - s.y * 0.17, 0)
		anim.add_child(_flag)
		_mesh(_box(Vector3(s.x * 0.9, s.y * 0.26, 0.05)), Mat.toy(col, 0.3), Vector3(s.x * 0.45 + 0.05, 0, 0), _flag)
		_cyl(s.x * 0.4, s.x * 0.5, 0.18, Mat.toy(Color("#f4f1ea")), Vector3(0, foot + 0.09, 0))
	_ground_fx = Node3D.new()
	add_child(_ground_fx)
	var ring := TorusMesh.new()
	ring.inner_radius = maxf(s.x, 1.0) * 0.85
	ring.outer_radius = maxf(s.x, 1.0) * 1.0
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring
	ring_mi.material_override = Mat.toy(Color("#ffe066"), 1.2, 0.5)
	ring_mi.position.y = 0.06
	_ground_fx.add_child(ring_mi)
	var beam := CylinderMesh.new()
	beam.top_radius = maxf(s.x, 1.0) * 0.75
	beam.bottom_radius = maxf(s.x, 1.0) * 0.85
	beam.height = 1.0
	beam.cap_top = false
	beam.cap_bottom = false
	var beam_mi := MeshInstance3D.new()
	beam_mi.mesh = beam
	beam_mi.material_override = Mat.beam(Color(1.0, 0.85, 0.35))
	beam_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam_mi.scale = Vector3(1, BEAM_HEIGHT, 1)
	beam_mi.position.y = BEAM_HEIGHT * 0.5
	_ground_fx.add_child(beam_mi)
	_ground_fx.position.y = -s.y * 0.5
	add_child(FX3.sparkles(Color("#ffe066"), maxf(s.x, 1.0), 10))

## Pole with a pennant that starts lowered (white) and is raised in colour when reached.
func _build_checkpoint(col: Color) -> void:
	var s := size
	_cyl(0.06, 0.06, s.y, Mat.toy(Color("#f4f1ea"), 0.0, 0.3))
	_sphere(0.12, 0.24, Mat.toy(col, 0.5), Vector3(0, s.y * 0.5 + 0.08, 0))
	_cyl(s.x * 0.45, s.x * 0.55, 0.16, Mat.toy(Color("#8d909a")), Vector3(0, -s.y * 0.5 + 0.08, 0))
	_flag = Node3D.new()
	_flag.position = Vector3(0, _flag_low_y(), 0)
	anim.add_child(_flag)
	var w := maxf(s.x, 0.8) * 1.1
	var pennant := _mesh(_pennant_mesh(w, s.y * 0.3), Mat.toy(Color("#e6e6ee")), Vector3(w * 0.5 + 0.04, 0, 0), _flag)
	pennant.name = "Pennant"

func _flag_low_y() -> float:
	return -size.y * 0.5 + 0.45

func _flag_high_y() -> float:
	return size.y * 0.5 - size.y * 0.14

## Triangular pennant (w long, h tall) whose tip points along +X.
func _pennant_mesh(w: float, h: float) -> ArrayMesh:
	var pm := PrismMesh.new()
	pm.size = Vector3(h, w, 0.06)
	pm.left_to_right = 0.5
	var am := ArrayMesh.new()
	var arrays := pm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var rot := Basis(Vector3.BACK, -PI * 0.5)  # prism apex (+Y) -> +X
	for i in verts.size():
		verts[i] = rot * verts[i]
		norms[i] = rot * norms[i]
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TANGENT] = null
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am

func _build_powerup(col: Color) -> void:
	var s := size
	_mesh(Mesh3D.star(Vector3(s.x * 0.6, s.y * 0.6, s.z * 0.25)), Mat.toy(col.lightened(0.2), 1.0))
	var shell := _sphere(s.x * 0.5, s.y, Mat.glass(col, 0.28, 1.0))
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(FX3.sparkles(col, s.x * 0.6, 5))

func _build_bouncer(col: Color) -> void:
	var s := size
	var r := s.x * 0.5
	_cyl(r * 0.9, r, s.y * 0.3, Mat.toy(Color("#4a4458")), Vector3(0, -s.y * 0.35, 0))
	for i in 3:
		var coil := TorusMesh.new()
		coil.inner_radius = r * 0.32
		coil.outer_radius = r * 0.45
		_mesh(coil, Mat.toy(Color("#d9d9e3"), 0.0, 0.8), Vector3(0, -s.y * 0.18 + i * s.y * 0.14, 0))
	_pad = Node3D.new()
	_pad.position = Vector3(0, s.y * 0.32, 0)
	anim.add_child(_pad)
	_sphere(r, s.y * 0.5, Mat.toy(col), Vector3.ZERO, _pad)
	_sphere(r * 0.45, s.y * 0.2, Mat.toy(col.lightened(0.4)), Vector3(0, s.y * 0.17, 0), _pad)

func _build_sign(col: Color) -> void:
	var s := size
	var wood := col if data.has("color") else WOOD
	_mesh(_box(Vector3(0.14, s.y, 0.14)), Mat.toy(WOOD.darkened(0.3)), Vector3(0, -s.y * 0.3, 0))
	_mesh(_box(s), Mat.toy(wood), Vector3(0, s.y * 0.2, 0))
	_mesh(_box(Vector3(s.x * 0.9, s.y * 0.82, s.z * 0.2)), Mat.toy(wood.lightened(0.45)), Vector3(0, s.y * 0.2, s.z * 0.5))
	var l := Label3D.new()
	l.text = U.str_of(data, "text", U.str_of(data, "name", ""))
	_fit_label(l, Vector2(s.x * 0.8, s.y * 0.7))
	l.modulate = Color("#3b2414")
	l.outline_size = 0
	l.shaded = false
	l.position = Vector3(0, s.y * 0.2, s.z * 0.62)
	anim.add_child(l)

## Pick a glyph size so the wrapped text fills (but stays inside) the board.
func _fit_label(l: Label3D, area: Vector2) -> void:
	const FONT_PX := 64
	var chars := maxf(1.0, float(l.text.length()))
	var glyph := clampf(sqrt(area.x * area.y / (chars * 1.3)), 0.1, area.y * 0.45)
	l.font_size = FONT_PX
	l.pixel_size = glyph / FONT_PX
	l.width = area.x / l.pixel_size
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_text(col: Color) -> void:
	var l := Label3D.new()
	l.text = U.str_of(data, "text", "")
	l.font_size = int(U.num(data, "font_size", 64))
	l.pixel_size = 0.01
	l.modulate = col
	l.outline_size = 12
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	anim.add_child(l)

## Natural default colours per decor shape (the generic kind colour is teal, which reads as
## plastic on trees and houses); an explicit spec colour always wins.
static func decor_color(shape: String) -> Color:
	match shape:
		"tree", "", "bush": return Color("#5cae4a")
		"pine": return Color("#3f8f5a")
		"house", "building": return Color("#f3e3c3")
		"box", "crate": return Color("#c68b4e")
		"pillar", "cylinder", "tower": return Color("#ddd6c6")
		"cloud": return Color("#ffffff")
	return Color("#9aa0ac")

func _build_decor(shape: String, col: Color) -> void:
	var s := size
	if not data.has("color"):
		col = decor_color(shape)
	match shape:
		"rock", "stone", "boulder":
			var sm := SphereMesh.new()
			sm.radius = s.x * 0.5
			sm.height = s.y
			sm.radial_segments = 7
			sm.rings = 4
			_mesh(sm, Mat.toy(col if data.has("color") else Color("#9aa0ac")))
		"box", "crate", "house", "building":
			_mesh(_box(s), Mat.toy(col))
			if shape == "house":
				var roof := PrismMesh.new()
				roof.size = Vector3(s.x * 1.15, s.y * 0.55, s.z * 1.1)
				_mesh(roof, Mat.toy(Color("#e05a4f")), Vector3(0, s.y * 0.77, 0))
		"cylinder", "pillar", "tower":
			_cyl(s.x * 0.5, s.x * 0.5, s.y, Mat.toy(col))
		"cloud":
			_build_cloud(col)
		"flower":
			_cyl(s.x * 0.05, s.x * 0.05, s.y * 0.6, Mat.toy(Color("#4f9d3a")), Vector3(0, -s.y * 0.2, 0))
			var petal := col if data.has("color") else Color("#ff8fab")
			for i in 5:
				var a := TAU * i / 5.0
				_sphere(s.x * 0.17, s.x * 0.17, Mat.toy(petal), Vector3(cos(a) * s.x * 0.2, s.y * 0.15, sin(a) * s.x * 0.2))
			_sphere(s.x * 0.13, s.x * 0.13, Mat.toy(Color("#ffd23f")), Vector3(0, s.y * 0.17, 0))
		"sphere", "ball", "bush":
			_sphere(s.x * 0.5, s.y, Mat.toy(col))
		"pine":
			_cyl(s.x * 0.08, s.x * 0.11, s.y * 0.3, Mat.toy(WOOD.darkened(0.2)), Vector3(0, -s.y * 0.35, 0))
			for i in 3:
				var k := 1.0 - i * 0.25
				_cyl(0.0, s.x * 0.5 * k, s.y * 0.4, Mat.toy(col.lightened(i * 0.06)), Vector3(0, -s.y * 0.1 + i * s.y * 0.2, 0), 10)
		_:
			_cyl(s.x * 0.08, s.x * 0.12, s.y * 0.5, Mat.toy(WOOD.darkened(0.2)), Vector3(0, -s.y * 0.25, 0))
			_sphere(s.x * 0.42, s.y * 0.48, Mat.toy(col), Vector3(0, s.y * 0.15, 0))
			_sphere(s.x * 0.3, s.y * 0.36, Mat.toy(col.lightened(0.08)), Vector3(s.x * 0.18, s.y * 0.3, s.z * 0.08))
			_sphere(s.x * 0.28, s.y * 0.32, Mat.toy(col.darkened(0.05)), Vector3(-s.x * 0.2, s.y * 0.26, -s.z * 0.06))

## Puffy cloud from overlapping spheres; bright and shadowless so it reads as sky decor.
func _build_cloud(col: Color) -> void:
	var s := size
	var m := Mat.toy(col, 0.25)
	var puffs := [Vector4(0, 0, 0, 0.5), Vector4(-0.3, -0.08, 0.05, 0.36), Vector4(0.32, -0.1, -0.04, 0.38), Vector4(0.1, 0.18, 0, 0.34), Vector4(-0.12, 0.1, -0.1, 0.3)]
	for p in puffs:
		var r: float = p.w * minf(s.x, s.y * 2.0)
		var mi := _sphere(r, r * 1.6, m, Vector3(p.x * s.x, p.y * s.y, p.z * s.z))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_body() -> void:
	body = null
	match kind:
		"platform":
			var b := AnimatableBody3D.new()
			b.sync_to_physics = true
			b.collision_layer = 1
			b.collision_mask = 0
			b.add_child(_box_shape(size))
			body = b
		"decor", "text", "sign":
			var shape := U.str_of(data, "shape", "")
			var solid_default := kind == "decor" and shape in ["rock", "stone", "boulder", "box", "crate", "house", "building", "pillar", "tower", "cylinder", "", "pine", "tree"]
			if bool(data.get("solid", solid_default)) and shape != "cloud":
				var sb := StaticBody3D.new()
				sb.collision_layer = 1
				var thin := shape in ["", "pine", "tree"]
				sb.add_child(_box_shape(Vector3(size.x * 0.2, size.y, size.z * 0.2) if thin else size * 0.9))
				body = sb
		_:
			var a := Area3D.new()
			a.collision_layer = 4
			a.collision_mask = 2
			a.monitorable = kind == "enemy"
			var k := 1.0
			if kind == "enemy":
				k = 0.85
			elif kind in ["collectible", "powerup"]:
				k = 1.5
			a.add_child(_box_shape(size * k))
			a.body_entered.connect(_on_body_entered)
			body = a
	if body:
		body.set_meta("ent", self)
		add_child(body)

func _box_shape(v: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = v
	cs.shape = bs
	return cs

# ---------------------------------------------------------------- AI assets

func refresh_asset(animate: bool) -> void:
	var st: String = world.main.assets.state(asset_id) if asset_id != "" else "none"
	if is_instance_valid(pending_fx):
		pending_fx.queue_free()
	pending_fx = null
	if st == "pending" or st == "loading":
		_show_pending()
		return
	if st != "ready" or model != null:
		return
	var res = world.main.assets.get_res(asset_id)
	if kind == "platform" and res is Texture2D:
		refresh_terrain()
		return
	var inst: Node3D = null
	if res is Node3D:
		inst = world.main.assets.instance_model(asset_id, size)
	elif res is Texture2D:
		inst = _make_sprite(res)
	if inst == null:
		return
	for c in anim.get_children():
		if not (c is Label3D):
			c.queue_free()
	model = inst
	anim.add_child(inst)
	if animate:
		inst.scale = Vector3.ONE * 0.05
		create_tween().tween_property(inst, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		FX3.burst(world, global_position, Color(0.8, 0.6, 1.0), 20, 4.0)

func _make_sprite(tex: Texture2D) -> Sprite3D:
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	var ts := tex.get_size()
	spr.pixel_size = minf(size.y / maxf(ts.y, 1.0), maxf(size.x, size.z) / maxf(ts.x, 1.0))
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.shaded = false
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return spr

func _show_pending() -> void:
	pending_fx = MeshInstance3D.new()
	pending_fx.mesh = _box(size * 1.15)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.6, 0.4, 1.0, 0.25)
	pending_fx.material_override = m
	pending_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pending_fx)

# ---------------------------------------------------------------- per-frame animation

func _process(delta: float) -> void:
	t += delta
	if is_instance_valid(pending_fx):
		pending_fx.rotate_y(delta * 1.5)
		(pending_fx.material_override as StandardMaterial3D).albedo_color.a = 0.15 + 0.12 * sin(t * 6.0)
	if not alive:
		return
	match kind:
		"collectible", "powerup":
			anim.rotation.y += delta * SPIN_SPEED
			anim.position.y = sin(t * BOB_SPEED) * BOB_HEIGHT * maxf(size.y, 0.5)
		"enemy":
			if not _squashed:
				var b := sin(t * 5.0) * BREATHE
				anim.scale = Vector3(1.0 - b * 0.5, 1.0 + b, 1.0 - b * 0.5)
		"goal":
			if _flag:
				_flag.rotation.y = sin(t * 3.0) * 0.18
			else:
				anim.rotation.y += delta * SPIN_SPEED * 0.6
				anim.position.y = sin(t * 2.0) * 0.15
		"checkpoint":
			if _flag:
				_flag.rotation.y = sin(t * 3.5) * (0.25 if _reached else 0.08)

## Goal decorations sit on the floor below the goal, found once via a short raycast.
func _snap_ground_fx() -> void:
	_snapped = true
	if _ground_fx == null:
		return
	var from := global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * SNAP_RAY, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		_ground_fx.global_position.y = hit.position.y

# ---------------------------------------------------------------- behaviour

func _physics_process(delta: float) -> void:
	if not _snapped:
		_snap_ground_fx()
	if world == null or not world.playing or not alive:
		return
	var beh = data.get("behavior", {})
	var btype := ""
	if typeof(beh) == TYPE_STRING:
		btype = beh
		beh = {}
	elif typeof(beh) == TYPE_DICTIONARY:
		btype = U.str_of(beh, "type", "")
	if btype == "":
		return
	var speed := U.num(beh, "speed", 3.0)
	var rng := U.num(beh, "range", 4.0)
	match btype:
		"patrol", "move": _patrol(delta, U.str_of(beh, "axis", "x"), speed, rng)
		"chase": _chase(delta, speed, U.num(beh, "radius", 10.0))
		"float": position.y = home.y + sin(t * 2.0) * rng * 0.15
		"fly":
			position.y = home.y + sin(t * 2.0) * rng * 0.3
			position.x = home.x + sin(t * speed * 0.3) * rng
		"spin": anim.rotate_y(delta * speed)
		"shoot": _shoot(delta, beh)

func _patrol(delta: float, axis: String, speed: float, rng: float) -> void:
	var ax := Vector3.RIGHT
	if axis == "z":
		ax = Vector3.BACK
	elif axis == "y":
		ax = Vector3.UP
	position += ax * dir * speed * delta
	var off := (position - home).dot(ax)
	if off > rng:
		dir = -1.0
	elif off < -rng:
		dir = 1.0
	if kind == "enemy":
		if axis != "y":
			_face(ax * dir, delta)
		anim.position.y = absf(sin(t * speed * 2.5)) * 0.12 * size.y

func _chase(delta: float, speed: float, radius: float) -> void:
	var p = world.player
	if p == null or not is_instance_valid(p):
		return
	var d: Vector3 = p.global_position - global_position
	d.y = 0
	if d.length() < radius:
		position += d.normalized() * speed * delta
		_face(d, delta)
		anim.position.y = absf(sin(t * speed * 3.0)) * 0.15 * size.y
	else:
		position = position.move_toward(home, speed * 0.5 * delta)

func _shoot(delta: float, beh: Dictionary) -> void:
	shoot_cd -= delta
	var p = world.player
	if p == null or not is_instance_valid(p):
		return
	var dd: Vector3 = p.global_position - global_position
	if dd.length() > U.num(beh, "radius", 14.0):
		return
	_face(dd, delta)
	if shoot_cd <= 0.0:
		shoot_cd = U.num(beh, "interval", 2.0)
		world.spawn_projectile(global_position + Vector3(0, size.y * 0.3, 0), dd.normalized() * U.num(beh, "bullet_speed", 8.0), base_color())
		_punch(Vector3(1.25, 0.8, 1.25))

## Smoothly turn the visual towards a world direction.
func _face(d: Vector3, delta: float) -> void:
	if Vector2(d.x, d.z).length() < 0.01:
		return
	var target := atan2(d.x, d.z) - rotation.y
	anim.rotation.y = lerp_angle(anim.rotation.y, target, minf(1.0, delta * TURN_RATE))

func _punch(s: Vector3) -> void:
	var tw := create_tween()
	tw.tween_property(visual, "scale", s, 0.07)
	tw.tween_property(visual, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

# ---------------------------------------------------------------- interactions

func _on_body_entered(b: Node) -> void:
	if not alive or world == null or not world.playing or b != world.player:
		return
	var p = world.player
	match kind:
		"collectible":
			alive = false
			world.collect(self, int(U.num(data, "value", 1)))
			_fly_to_player()
		"hazard":
			p.hurt(global_position)
		"enemy":
			_touch_enemy(p)
		"goal":
			world.reach_goal(self)
		"checkpoint":
			_raise_flag()
		"powerup":
			alive = false
			p.apply_powerup(U.str_of(data, "effect", "speed"), U.num(data, "duration", 8.0))
			world.main.sfx("sparkle")
			FX.float_text3d(world, global_position + Vector3.UP, U.str_of(data, "name", "道具"), Color("#c77dff"))
			_fly_to_player()
		"bouncer":
			_spring(p)

func _touch_enemy(p) -> void:
	var falling: bool = p.velocity.y < -0.5 or p.global_position.y > global_position.y + size.y * 0.45
	if bool(data.get("stompable", true)) and falling and p.global_position.y > global_position.y + size.y * 0.2:
		p.stomp_bounce(STOMP_BOUNCE)
		defeat(true)
	elif p.invincible():
		defeat(false)
	else:
		p.hurt(global_position)

## Kill the enemy: stomp squashes it flat, other deaths pop it away.
func defeat(stomped: bool) -> void:
	if not alive:
		return
	alive = false
	world.enemy_defeated(self, int(U.num(data, "value", 5)), stomped)
	if body:
		body.set_deferred("monitoring", false)
	if not stomped:
		_pop_away()
		return
	_squashed = true
	var tw := create_tween()
	tw.tween_property(anim, "scale", Vector3(1.5, 0.18, 1.5), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(anim, "position:y", -size.y * 0.42, 0.08)
	tw.tween_interval(0.35)
	tw.tween_property(anim, "scale", Vector3(0.01, 0.01, 0.01), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)

## Pickups zip into the player while shrinking, then burst.
func _fly_to_player() -> void:
	if body:
		body.set_deferred("monitoring", false)
	var start := global_position
	var col := base_color()
	var tw := create_tween()
	tw.tween_property(visual, "scale", Vector3.ONE * 1.35, 0.06)
	tw.tween_method(func(k: float):
		var p = world.player
		var target: Vector3 = p.global_position + Vector3(0, p.size.y * 0.2, 0) if p and is_instance_valid(p) else start
		global_position = start.lerp(target, k * k)
		visual.scale = Vector3.ONE * lerpf(1.35, 0.2, k), 0.0, 1.0, PICKUP_SECS)
	tw.tween_callback(func():
		FX3.burst(world, global_position, col, 12, 3.5)
		queue_free())

func _pop_away() -> void:
	var tw := create_tween()
	tw.tween_property(visual, "scale", Vector3.ONE * 1.5, 0.1)
	tw.tween_property(visual, "scale", Vector3.ONE * 0.01, 0.15)
	tw.tween_callback(queue_free)

func _raise_flag() -> void:
	if _reached:
		return
	_reached = true
	world.reach_checkpoint(self)
	if _flag == null:
		_punch(Vector3(1.3, 0.8, 1.3))
		return
	var pennant: MeshInstance3D = _flag.get_node("Pennant")
	pennant.material_override = Mat.toy(base_color(), 0.5)
	var tw := create_tween()
	tw.tween_property(_flag, "position:y", _flag_high_y(), 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_punch(Vector3(0.85, 1.2, 0.85))

func _spring(p) -> void:
	p.bounce(U.num(data, "strength", 1.6))
	world.main.sfx("jump")
	FX3.ring(world, global_position + Vector3(0, size.y * 0.3, 0), base_color().lightened(0.4), maxf(size.x, 1.2) * 1.4)
	var target: Node3D = _pad if _pad else visual
	var rest := target.position
	var tw := create_tween()
	tw.tween_property(target, "position:y", rest.y - size.y * 0.35, 0.05)
	tw.tween_property(target, "position:y", rest.y, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var tw2 := create_tween()
	tw2.tween_property(anim, "scale", Vector3(1.25, 0.6, 1.25), 0.05)
	tw2.tween_property(anim, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)