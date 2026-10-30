extends Node3D
## AI builder in a 3D scene. The generated pixel character is a camera-facing Sprite3D icon,
## while its flight and construction beam remain in world space.
const ROBOT_TEXTURE: Texture2D = preload("res://art/ai-robot.png")
var t := 0.0
var beam: MeshInstance3D
var beam_t := 0.0
var label: Label3D
var robot: Sprite3D

func _ready() -> void:
	robot = Sprite3D.new()
	robot.name = "RobotIcon"
	robot.texture = ROBOT_TEXTURE
	robot.pixel_size = 1.8 / float(ROBOT_TEXTURE.get_width())
	robot.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	robot.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	robot.shaded = false
	robot.double_sided = true
	robot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(robot)
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
	robot.position.y = sin(t * 4.0) * 0.08
	beam_t -= delta
	if beam_t <= 0.0:
		beam.visible = false
	else:
		(beam.material_override as StandardMaterial3D).albedo_color.a = 0.3 * beam_t / 0.5
