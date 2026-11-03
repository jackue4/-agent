extends RefCounted
## Authored sandstone courtyard kit. All raised paths share world.ground_height.
const STONE = preload("res://assets/desert_stone.gdshader")
const SAND = preload("res://assets/desert_sand.gdshader")
const ROCK := Color("8c7657")
const FACE := Color("b8a079")
const CAP := Color("c5ae86")
const DARK := Color("66543e")
var w
var rng := RandomNumberGenerator.new()

func _init(world) -> void:
	w = world
	rng.seed = 92017

func stone(color: Color) -> ShaderMaterial:
	var key := "sandstone_"+color.to_html()
	if w._materials.has(key): return w._materials[key]
	var mat := ShaderMaterial.new(); mat.shader = STONE
	mat.set_shader_parameter("stone_color",color)
	w._materials[key] = mat
	return mat

func block(pos: Vector3, size: Vector3, color: Color = FACE, parent: Node3D = null) -> MeshInstance3D:
	var target: Node3D=w._room if parent == null else parent
	var node: MeshInstance3D
	if minf(size.x,minf(size.y,size.z))>.18 and maxf(size.x,maxf(size.y,size.z))<5.0:
		var key: String="sand_bevel_%s" % size
		if w._boxes.has(key):
			node=MeshInstance3D.new(); node.mesh=w._boxes[key]; node.position=pos; target.add_child(node)
		else:
			node=w._beveled_box(target,pos,size,.055,color); w._boxes[key]=node.mesh
	else: node=w.box(target,pos,size,color)
	node.material_override = stone(color)
	return node

func build(layout: Dictionary) -> void:
	for room in layout.rooms:
		_paving(room.rect)
		_walls(room,layout.rooms)
		for cover in room.covers:
			block(cover.pos+Vector3(0,.42,0),Vector3(cover.size.x,.84,cover.size.z),ROCK)
			block(cover.pos+Vector3(0,.95,0),Vector3(cover.size.x+.12,.22,cover.size.z+.12),CAP)
			w._solid(cover.pos,cover.size)
		_dress(room)
		_marker(room)
	for link in layout.links:
		_paving(link.corridor,link)
		var r: Rect2 = link.corridor
		for sign_value in [-1.0,1.0]:
			for i in int(link.steps):
				var t := (i+.5)/float(link.steps)
				var p := Vector3(r.get_center().x+sign_value*4.25,0,lerpf(r.position.y,r.end.y,t)) if link.vertical else Vector3(lerpf(r.position.x,r.end.x,t),0,r.get_center().y+sign_value*4.25)
				p.y = lerpf(float(link.height_start),float(link.height_end),float(i)/float(link.steps-1))
				block(p+Vector3(0,.35,0),Vector3(.5,.7,r.size.y/6.0) if link.vertical else Vector3(r.size.x/6.0,.7,.5),ROCK)
				w._solid(p,Vector3(.5,.7,r.size.y/6.0) if link.vertical else Vector3(r.size.x/6.0,.7,.5))
		_door(layout.rooms[link.a],layout.rooms[link.b])
		_door(layout.rooms[link.b],layout.rooms[link.a])
	_backdrop(layout)

func _paving(rect: Rect2, stairs: Dictionary = {}) -> void:
	var nx := ceili(rect.size.x/2.0); var nz := ceili(rect.size.y/2.0)
	if not stairs.is_empty():
		if stairs.vertical: nz = int(stairs.steps)
		else: nx = int(stairs.steps)
	var size := Vector2(rect.size.x/nx,rect.size.y/nz)
	var multi := MultiMesh.new(); multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true; multi.instance_count = nx*nz
	var tile := BoxMesh.new(); tile.size = Vector3(size.x-.025,.26,size.y-.025)
	multi.mesh = tile
	if w._floor_material == null:
		w._floor_material = ShaderMaterial.new(); w._floor_material.shader = w.FLOOR_SHADER
		w._floor_material.set_shader_parameter("base_color",w.theme.floor)
		w._floor_material.set_shader_parameter("accent_color",Color("beab83"))
		w._floor_material.set_shader_parameter("path_accent",Color("69d5df"))
		w._floor_material.set_shader_parameter("stone_style",1.0)
		w._floor_material.set_shader_parameter("freeze_amount",w._freeze_amount)
	for x in nx:
		for z in nz:
			var pos := Vector3(rect.position.x+(x+.5)*size.x,0,rect.position.y+(z+.5)*size.y)
			pos.y = w.ground_height(pos)-.13
			multi.set_instance_transform(x*nz+z,Transform3D(Basis.IDENTITY,pos))
			var shade := rng.randf_range(.84,1.08)
			multi.set_instance_color(x*nz+z,Color(shade,shade,shade,1))
	var draw := MultiMeshInstance3D.new(); draw.multimesh = multi
	draw.material_override = w._floor_material; draw.extra_cull_margin = 1.1
	w._room.add_child(draw)
	# Bedrock foundations stop raised stairs and terraces reading as floating sheets.
	var h: float = w.ground_height(Vector3(rect.get_center().x,0,rect.get_center().y))
	if not stairs.is_empty(): h = minf(stairs.height_start,stairs.height_end)
	block(Vector3(rect.get_center().x,(h-3.0)*.5-.15,rect.get_center().y),Vector3(rect.size.x,h+3.0,rect.size.y),ROCK)
	if stairs.is_empty():
		for tier in 3:
			block(Vector3(rect.get_center().x,h-.55-tier*.9,rect.get_center().y),Vector3(rect.size.x+.18+tier*.13,.22,rect.size.y+.18+tier*.13),ROCK if tier%2 else DARK)

func _walls(room: Dictionary, rooms: Array) -> void:
	var r: Rect2 = room.rect; var c: Vector3 = room.center
	var gaps := {"n":false,"s":false,"w":false,"e":false}
	for id in room.neighbors:
		var d: Vector3 = rooms[id].center-c
		gaps["e" if d.x>.1 else ("w" if d.x<-.1 else ("s" if d.z>0 else "n"))] = true
	for side in ["n","s","w","e"]:
		var along_x: bool = side in ["n","s"]
		var length := r.size.x if along_x else r.size.y
		var p := Vector3(c.x,c.y,r.position.y if side=="n" else r.end.y) if along_x else Vector3(r.position.x if side=="w" else r.end.x,c.y,c.z)
		var axis := Vector3.RIGHT if along_x else Vector3.BACK
		if gaps[side]:
			var segment := length*.5-4.5
			for sign_value in [-1.0,1.0]: _wall(p+axis*sign_value*(4.5+segment*.5),segment,along_x,1.5 if side=="n" else .95)
		else: _wall(p,length,along_x,1.5 if side=="n" else .95)
	for x in [-1.0,1.0]:
		for z in [-1.0,1.0]:
			_column(c+Vector3(x*r.size.x*.5,0,z*r.size.y*.5),2.7 if z<0 else 1.8)

func _wall(pos: Vector3, length: float, along_x: bool, height: float) -> void:
	var count := maxi(1,ceili(length/2.0))
	var unit := length/count
	for i in count:
		var offset := -length*.5+(i+.5)*unit
		var p := pos+(Vector3(offset,0,0) if along_x else Vector3(0,0,offset))
		for row in 2:
			block(p+Vector3(0,(row+.5)*height*.5,0),Vector3(unit-.035,height*.5-.035,.8) if along_x else Vector3(.8,height*.5-.035,unit-.035),FACE if (i+row)%3 else ROCK)
		block(p+Vector3(0,height+.08,0),Vector3(unit-.04,.18,1.0) if along_x else Vector3(1.0,.18,unit-.04),CAP)
	w._solid(pos,Vector3(length,height,.8) if along_x else Vector3(.8,height,length))

func _column(pos: Vector3, height: float = 2.6) -> void:
	block(pos+Vector3(0,.15,0),Vector3(1.4,.3,1.4),ROCK)
	var count := maxi(2,ceili(height/.55))
	for i in count:
		block(pos+Vector3(0,.3+(i+.5)*(height-.4)/count,0),Vector3(1.05,(height-.4)/count-.025,1.05),FACE if i%3 else ROCK)
	block(pos+Vector3(0,height+.02,0),Vector3(1.4,.24,1.4),CAP)
	block(pos+Vector3(.24,height+.19,-.17),Vector3(.42,.16,.46),ROCK)

func _door(room: Dictionary, neighbor: Dictionary) -> void:
	var dir: Vector3 = neighbor.center-room.center; dir.y = 0; dir = dir.normalized()
	var vertical := absf(dir.z)>.5
	var reach: float = room.rect.size.y*.5 if vertical else room.rect.size.x*.5
	var at: Vector3 = room.center+dir*reach
	var axis := Vector3.RIGHT if vertical else Vector3.BACK
	for sign_value in [-1.0,1.0]:
		var p: Vector3 = at+axis*sign_value*4.5
		_column(p,3.05)
		w._solid(p,Vector3(1.15,3,1.15))
		# Broken entablatures frame each opening without a roof hiding the player.
		block(p-axis*sign_value*.62+Vector3(0,2.95,0),Vector3(2.1,.35,1.3) if vertical else Vector3(1.3,.35,2.1),CAP)
		var lamp := OmniLight3D.new(); lamp.visible = not preload("res://scripts/quality.gd").low(); lamp.position=p-dir*.55+Vector3(0,1.8,0)
		lamp.light_color=Color("ffc16d"); lamp.light_energy=.32; lamp.omni_range=3.8
		w._room.add_child(lamp)
		w.box(w._room,lamp.position,Vector3(.14,.28,.14),Color("ffd49a"),1.2)
	var gate := Node3D.new(); w._room.add_child(gate); gate.position=at
	for i in 12:
		var offset := -3.7+i*.67
		block(Vector3(offset,1.0,0) if vertical else Vector3(0,1.0,offset),Vector3(.14,2.0,.14),DARK,gate)
	block(Vector3(0,1.9,0),Vector3(8,.16,.18) if vertical else Vector3(.18,.16,8),ROCK,gate)
	gate.visible=false
	var rect := Rect2(Vector2(at.x,at.z)-Vector2(4,.22),Vector2(8,.44)) if vertical else Rect2(Vector2(at.x,at.z)-Vector2(.22,4),Vector2(.44,8))
	w._doors.append({"room_id":int(room.id),"neighbor":int(neighbor.id),"rect":rect,"node":gate,"locked":false})

func _marker(room: Dictionary) -> void:
	var color := Color("b5d7d5") if room.kind=="entry" else Color("d6bd8c")
	var label := Label3D.new(); label.text="%02d  %s" % [room.id+1,room.name]
	label.font_size=40; label.pixel_size=.008; label.outline_size=0
	label.rotation_degrees.x=-90; label.modulate=color
	label.position=room.center+Vector3(0,.035,room.rect.size.y*.5-2.0)
	w._room.add_child(label)
	var rail: MeshInstance3D=w.box(w._room,label.position+Vector3(0,-.01,.65),Vector3(5,.035,.08),color,.15)
	var pool := OmniLight3D.new(); pool.visible = not preload("res://scripts/quality.gd").low(); pool.position=label.position+Vector3.UP*2
	pool.light_color=color; pool.light_energy=.4; pool.omni_range=5
	w._room.add_child(pool)
	w._room_markers[room.id]={"label":label,"rail":rail,"light":pool,"color":color}

func _dress(room: Dictionary) -> void:
	var c: Vector3=room.center; var r: Rect2=room.rect
	# Recessed wall niches and ragged, sand-filled outer margins.
	for sign_value in [-1.0,1.0]:
		var p := c+Vector3(sign_value*(r.size.x*.5-3),0,-r.size.y*.5+1.3)
		block(p+Vector3(0,.1,0),Vector3(3,.2,1.1),ROCK)
		_column(p+Vector3(-1.2,0,0),2.4); _column(p+Vector3(1.2,0,0),2.4)
		block(p+Vector3(0,2.45,0),Vector3(3.8,.3,1.6),CAP)
		w._solid(p,Vector3(3.7,2.5,1.6))
		for i in 6:
			var q:=c+Vector3(sign_value*(r.size.x*.5-.7),.03,-r.size.y*.5+3+i*2.3)
			var b:=block(q,Vector3(rng.randf_range(.2,.65),.08,rng.randf_range(.35,.9)),CAP)
			b.rotation.y=rng.randf_range(-.5,.5)
		for z in [-1.0,1.0]:
			var drift:=MeshInstance3D.new(); var plane:=PlaneMesh.new(); plane.size=Vector2(6,8)
			drift.mesh=plane; drift.position=c+Vector3(sign_value*(r.size.x*.5-2.3),.025,z*(r.size.y*.5-3))
			var material:=ShaderMaterial.new(); material.shader=preload("res://assets/desert_drift.gdshader")
			drift.material_override=material; drift.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; w._room.add_child(drift)
			for i in 4:
				var rubble:=block(drift.position+Vector3(rng.randf_range(-1.4,1.4),.06,rng.randf_range(-2,2)),Vector3(.22+i*.08,.16,.3+i*.1),ROCK)
				rubble.rotation.y=rng.randf()*TAU
	# Flush concentric paving medallion: no decorative collider in the combat cross.
	for i in 16:
		var a:=TAU*i/16.0
		var b:=block(c+Vector3(cos(a)*3.3,.025,sin(a)*3.3),Vector3(.9,.045,.24),ROCK)
		b.rotation.y=-a+PI*.5
	if room.kind in ["entry","rest"] or int(room.id)==2:
		var shrine:=c+Vector3(5.5,0,-4.0)
		for tier in 3:
			var radius:=1.65-tier*.28
			var mesh:=CylinderMesh.new(); mesh.top_radius=radius; mesh.bottom_radius=radius+.08; mesh.height=.24; mesh.radial_segments=12
			var node:=MeshInstance3D.new(); node.mesh=mesh; node.material_override=stone(CAP if tier==2 else ROCK)
			node.position=shrine+Vector3.UP*(.12+tier*.24); w._room.add_child(node)
		w._solid(shrine,Vector3(3.5,.75,3.5))
		var crystal: MeshInstance3D=w._hero_crystal(w._room,shrine+Vector3.UP*1.2,Vector3(.24,.85,.24),Color("80dce5"))
		var light:=OmniLight3D.new(); light.visible = not preload("res://scripts/quality.gd").low(); light.position=shrine+Vector3.UP*1.4; light.light_color=Color("71cfdc"); light.light_energy=.65; light.omni_range=5
		w._room.add_child(light)

func make_urn() -> Node3D:
	var root:=Node3D.new(); root.name="DesertUrn"
	for spec in [Vector3(.34,.48,.0),Vector3(.48,.45,.38),Vector3(.31,.20,.70)]:
		var mesh:=CylinderMesh.new(); mesh.bottom_radius=spec.x; mesh.top_radius=spec.x*.82; mesh.height=spec.y; mesh.radial_segments=10
		var node:=MeshInstance3D.new(); node.mesh=mesh; node.material_override=stone(Color("a47e57")); node.position.y=spec.z+spec.y*.5
		root.add_child(node)
	block(Vector3(0,.91,0),Vector3(.55,.08,.55),CAP,root)
	return root

func _backdrop(layout: Dictionary) -> void:
	var plane:=PlaneMesh.new(); plane.size=layout.bounds.size+Vector2(160,160); plane.subdivide_width=80; plane.subdivide_depth=100
	var sand:=MeshInstance3D.new(); sand.mesh=plane; sand.position=Vector3(layout.bounds.get_center().x,-7,layout.bounds.get_center().y)
	var mat:=ShaderMaterial.new(); mat.shader=SAND; sand.material_override=mat; w._room.add_child(sand)
	for room in layout.rooms:
		var r: Rect2=room.rect
		for sign_value in [-1.0,1.0]:
			var p: Vector3=room.center+Vector3(sign_value*(r.size.x*.5+5),-2,r.size.y*.5+3)
			var clear:=true
			for rect: Rect2 in layout.walkable:
				if rect.grow(2).has_point(Vector2(p.x,p.z)): clear=false
			if not clear: continue
			for tier in 3:
				var rock:=block(p+Vector3(0,-tier*1.1,0),Vector3(4+tier*1.5,1.2,3.8+tier*1.3),ROCK if tier%2==0 else FACE)
				rock.rotation.y=.15*sign_value
			_palm(p+Vector3(1,1.0,0))

func _palm(pos: Vector3) -> void:
	for i in 7:
		var trunk:=block(pos+Vector3(sin(i*.15)*.45,i*.48,0),Vector3(.28,.52,.30),DARK)
		trunk.rotation.z=-.06
	var leaf_mat:=StandardMaterial3D.new(); leaf_mat.albedo_color=Color("70764a"); leaf_mat.roughness=1; leaf_mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	for i in 7:
		var a:=i*TAU/7.0; var dir:=Vector3(cos(a),0,sin(a)); var side:=Vector3(-sin(a),0,cos(a))
		var center:=pos+Vector3(.35,3.3,0)
		var vertices:=PackedVector3Array([center,center+dir*1.1+side*.36+Vector3.UP*.35,center+dir*2.7-Vector3.UP*.5,center,center+dir*2.7-Vector3.UP*.5,center+dir*1.1-side*.36+Vector3.UP*.35])
		var arrays:=[]; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=vertices
		arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP])
		var mesh:=ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var leaf:=MeshInstance3D.new(); leaf.mesh=mesh; leaf.material_override=leaf_mat; w._room.add_child(leaf)
