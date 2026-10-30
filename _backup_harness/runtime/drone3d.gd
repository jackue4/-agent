extends Node3D
## 3D AI builder drone.
var t := 0.0
var beam: MeshInstance3D
var beam_t := 0.0
var label: Label3D
var prop: MeshInstance3D

func _ready() -> void:
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.45
	sm.height = 0.9
	body.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#8b5cf6")
	m.emission_enabled = true
	m.emission = Color("#6d28d9")
	m.emission_energy_multiplier = 0.4
	body.material_override = m
	add_child(body)
	var face := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.55, 0.3, 0.1)
	face.mesh = bm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("#1b1b3a")
	face.material_override = fm
	face.position = Vector3(0, 0.02, 0.4)
	add_child(face)
	for sx in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = Vector3(0.09, 0.14, 0.02)
		eye.mesh = em
		var emat := StandardMaterial3D.new()
		emat.albedo_color = Color("#7df9ff")
		emat.emission_enabled = true
		emat.emission = Color("#7df9ff")
		emat.emission_energy_multiplier = 2.0
		eye.material_override = emat
		eye.position = Vector3(sx * 0.12, 0.02, 0.46)
		add_child(eye)
	prop = MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(1.2, 0.04, 0.12)
	prop.mesh = pm
	prop.position = Vector3(0, 0.6, 0)
	add_child(prop)
	beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.1
	cm.bottom_radius = 1.0
	cm.height = 1.0
	beam.mesh = cm
	var bmat := StandardMaterial3D.new()
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color(0.55, 0.9, 1.0, 0.3)
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = bmat
	beam.visible = false
	add_child(beam)
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.008
	label.outline_size = 10
	label.no_depth_test = true
	label.position = Vector3(0, 1.1, 0)
	add_child(label)

func say(text: String) -> void:
	label.text = text

func fly_to(target: Vector3, dur := 0.35) -> Tween:
	var tw := create_tween()
	tw.tween_property(self, "position", target + Vector3(0, 3.5, 0), dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tw

func shoot_beam(target: Vector3, radius: float) -> void:
	var h := maxf(global_position.y - target.y, 0.5)
	beam.scale = Vector3(maxf(radius, 0.5), h, maxf(radius, 0.5))
	beam.position = Vector3(0, -h * 0.5, 0)
	beam.visible = true
	beam_t = 0.5

func _process(delta: float) -> void:
	t += delta
	prop.rotate_y(delta * 30.0)
	get_child(0).position.y = sin(t * 4.0) * 0.08
	beam_t -= delta
	if beam_t <= 0.0:
		beam.visible = false
	else:
		(beam.material_override as StandardMaterial3D).albedo_color.a = 0.3 * beam_t / 0.5
