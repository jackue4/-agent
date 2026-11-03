extends Node3D
## Deterministic, batched architecture below/outside the playable platforms.
## No colliders, RNG side effects, or gameplay state.
var _hulls: Array[Transform3D] = []
var _plates: Array[Transform3D] = []
var _lights: Array[Transform3D] = []

func build(bounds: Rect2, walkable: Array, accent: Color, mist: Color) -> void:
	name = "DistantIndustrialCity"
	var rng := RandomNumberGenerator.new()
	rng.seed = 71943
	var region := bounds.grow(65)
	for x in range(int(region.position.x),int(region.end.x),9):
		for z in range(int(region.position.y),int(region.end.y),11):
			var p := Vector2(x+rng.randf_range(-3,3),z+rng.randf_range(-3,3))
			var clear := true
			var nearest := 1000.0
			for rect: Rect2 in walkable:
				if rect.grow(7).has_point(p): clear = false; break
				var d := p-Vector2(clampf(p.x,rect.position.x,rect.end.x),clampf(p.y,rect.position.y,rect.end.y))
				nearest = minf(nearest,d.length())
			if not clear: continue
			var top := rng.randf_range(-10,-3) if nearest < 20 else rng.randf_range(-6,13)
			var width := rng.randf_range(2.4,4.0)
			var height := rng.randf_range(18,35)
			var center := Vector3(p.x,top-height*.5,p.y)
			_put(_hulls,center,Vector3(width,height,width*.8))
			_put(_plates,Vector3(p.x,top+.18,p.y),Vector3(width+.18,.36,width*.8+.2))
			_put(_hulls,Vector3(p.x+.3,top+.42,p.y-.2),Vector3(width*.58,.16,width*.5))
			for tier in range(3):
				var y := top-1.0-tier*6.0
				_put(_plates,Vector3(p.x,y,p.y),Vector3(width+.2,.6,width*.8+.3))
				_put(_plates,Vector3(p.x-width*.42,y-2,p.y+width*.42),Vector3(.32,4.5,.25))
				_put(_lights,Vector3(p.x+width*.24,y-2,p.y+width*.405),Vector3(.15,3.4,.05))
				# Recessed service bays, asymmetric armor and staggered window slots.
				_put(_hulls,Vector3(p.x-width*.1,y-2.7,p.y+width*.41),Vector3(width*.54,3.8,.18))
				_put(_plates,Vector3(p.x-width*.38,y-1.4,p.y+width*.44),Vector3(.48,1.9,.5))
				for slot in 3:
					_put(_lights,Vector3(p.x-width*.15,y-1.2-slot*.7,p.y+width*.445),Vector3(width*.26,.06,.04))
			if rng.randf() > .5:
				_put(_hulls,Vector3(p.x+width*.7,top-5,p.y),Vector3(width*.55,2,1.3))
	_batch(_hulls,Color("3b4654"),0.0)
	_batch(_plates,Color("586472"),0.0)
	_batch(_lights,accent,1.7)
	# An opaque cloud sea sits far below the deck; depth testing hides it indoors.
	var cloud := MeshInstance3D.new()
	var plane := PlaneMesh.new(); plane.size = bounds.size+Vector2(260,260)
	cloud.mesh = plane
	cloud.position = Vector3(bounds.get_center().x,-26,bounds.get_center().y)
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/cloud_sea.gdshader")
	material.set_shader_parameter("mist_color",mist)
	cloud.material_override = material
	cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cloud)

func _put(list: Array[Transform3D], pos: Vector3, size: Vector3) -> void:
	list.append(Transform3D(Basis.from_scale(size),pos))

func _batch(transforms: Array[Transform3D], color: Color, emission: float) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = BoxMesh.new()
	multi.instance_count = transforms.size()
	for i in transforms.size(): multi.set_instance_transform(i,transforms[i])
	var draw := MultiMeshInstance3D.new(); draw.multimesh = multi
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color; mat.metallic = .38; mat.roughness = .42
	mat.emission_enabled = emission > 0; mat.emission = color; mat.emission_energy_multiplier = emission
	draw.material_override = mat
	draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(draw)
