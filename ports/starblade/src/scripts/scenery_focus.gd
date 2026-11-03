extends MeshInstance3D
## Selective background defocus, before transparent combat VFX and the HUD.
const SHADER = preload("res://assets/scenery_focus.gdshader")
var _world: Node3D
var _generation := 0

func configure(world: Node3D) -> void:
	_world = world
	name = "SceneryDefocus"
	var quad := QuadMesh.new(); quad.size = Vector2(2,2)
	mesh = quad
	var mat := ShaderMaterial.new(); mat.shader = SHADER
	mat.render_priority = -128
	material_override = mat
	position.z = -1.0
	extra_cull_margin = 16384.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sync_level()

func _process(_delta: float) -> void:
	_sync_level()

func _sync_level() -> void:
	if not is_instance_valid(_world) or not is_instance_valid(_world._room): return
	var generation: int = _world._room.get_instance_id()
	if generation == _generation: return
	_generation = generation
	var rects: Array = _world._walkable if _world._dungeon else [_world._bounds]
	var regions := PackedVector4Array(); regions.resize(32)
	# Explicitly disable for unsupported future layouts rather than blurring rooms.
	var count := rects.size() if rects.size() <= 32 else 0
	for i in count:
		var rect: Rect2 = rects[i].grow(1.0)
		regions[i] = Vector4(rect.position.x,rect.position.y,rect.end.x,rect.end.y)
	material_override.set_shader_parameter("level_rects",regions)
	material_override.set_shader_parameter("level_rect_count",count)
