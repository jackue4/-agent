extends Node3D
## Cosmetic 3D engineer. All destinations are real object world coordinates.
var actor_id := "M"
var state := "paused"
var requested_state := "paused"
var action_time := 0.0
var typing_time := 0.0
var desk_open := 0.0
var typing := false
var left_key_presses := 0
var right_key_presses := 0
var _key_beat := -1
var module_name := ""
var module_file := ""
var module_step := ""
var module_flash := 0.0
var module_changes := 0
var _screen_blocks: Array[MeshInstance3D] = []
var destination := Vector3.ZERO
var work_target := Vector3.ZERO
var working := false
var walking := false
var elapsed := 0.0
var work_left := 0.0
var body: Node3D
var left_leg: Node3D
var right_leg: Node3D
var arm: Node3D
var left_arm: Node3D
var hammer: Node3D
var workbench: Node3D
var monitor_hinge: Node3D
var keyboard_left: MeshInstance3D
var keyboard_right: MeshInstance3D
var sparks: GPUParticles3D
var label: Label3D
var strokes := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	body = Node3D.new()
	add_child(body)
	var teal := Color("64d9c5")
	_piece(body, Vector3(0.55, 0.62, 0.34), Vector3(0, 0.98, 0), teal)
	_piece(body, Vector3(0.44, 0.42, 0.4), Vector3(0, 1.48, 0), Color("edbe91"))
	_piece(body, Vector3(0.54, 0.18, 0.5), Vector3(0, 1.72, 0), Color("f3c761"))
	_piece(body, Vector3(0.6, 0.06, 0.58), Vector3(0, 1.61, 0.02), Color("f3c761"))
	_piece(body, Vector3(0.34, 0.12, 0.06), Vector3(0, 1.48, 0.23), Color("244957"))
	left_leg = _limb(Vector3(-0.16, 0.68, 0), Vector3(0.22, 0.52, 0.24), Color("364e64"))
	right_leg = _limb(Vector3(0.16, 0.68, 0), Vector3(0.22, 0.52, 0.24), Color("364e64"))
	_piece(left_leg, Vector3(0.25, 0.16, 0.4), Vector3(0, -0.58, 0.08), Color("162b39"))
	_piece(right_leg, Vector3(0.25, 0.16, 0.4), Vector3(0, -0.58, 0.08), Color("162b39"))
	arm = _limb(Vector3(0.37, 1.24, 0), Vector3(0.18, 0.46, 0.18), teal)
	left_arm = _limb(Vector3(-0.37, 1.24, 0), Vector3(0.18, 0.46, 0.18), teal)
	for hand_arm in [arm, left_arm]:
		_piece(hand_arm, Vector3(0.19, 0.16, 0.22), Vector3(0, -0.49, 0.04), Color("edbe91"))
	hammer = Node3D.new()
	arm.add_child(hammer)
	_piece(hammer, Vector3(0.1, 0.44, 0.1), Vector3(0, -0.5, 0.15), Color("6c4b32"))
	_piece(hammer, Vector3(0.4, 0.18, 0.18), Vector3(0, -0.29, 0.15), Color("b4d8dc"))
	_build_workbench()
	sparks = GPUParticles3D.new()
	sparks.amount = 18
	sparks.lifetime = 0.35
	sparks.emitting = false
	var particle := ParticleProcessMaterial.new()
	particle.direction = Vector3(0, 1, 0)
	particle.spread = 60.0
	particle.initial_velocity_min = 1.2
	particle.initial_velocity_max = 3.0
	particle.gravity = Vector3(0, -6, 0)
	particle.scale_min = 0.035
	particle.scale_max = 0.07
	particle.color = Color("ffe0a0")
	sparks.process_material = particle
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 1.0
	spark_mesh.height = 2.0
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color("ffe0a0")
	spark_mesh.material = spark_mat
	sparks.draw_pass_1 = spark_mesh
	add_child(sparks)
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.15
	label.font_size = 28
	label.pixel_size = 0.012
	label.outline_size = 6
	if ResourceLoader.exists("res://addons/ugc/font.ttf"):
		label.font = load("res://addons/ugc/font.ttf")
	add_child(label)
	_update_label()

func _piece(parent: Node3D, size: Vector3, point: Vector3, color: Color) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	visual.material_override = mat
	visual.position = point
	parent.add_child(visual)
	return visual

func _build_workbench() -> void:
	workbench = Node3D.new()
	workbench.name = "PortableCodingDesk"
	add_child(workbench)
	for x in [-0.66, 0.66]:
		for z in [0.43, 1.07]:
			_piece(workbench, Vector3(0.09, 0.86, 0.09), Vector3(x, 0.43, z), Color("324d5b"))
	_piece(workbench, Vector3(1.64, 0.1, 0.9), Vector3(0, 0.91, 0.75), Color("466572"))
	_piece(workbench, Vector3(1.62, 0.035, 0.055), Vector3(0, 0.98, 0.31), Color("82dec9"))
	_piece(workbench, Vector3(1.06, 0.04, 0.32), Vector3(0, 0.98, 0.63), Color("182f40"))
	for row in 3:
		for column in 8:
			var key := _piece(workbench, Vector3(0.105, 0.025, 0.065), Vector3(-0.44 + column * 0.125, 1.012, 0.53 + row * 0.085), Color("a6c9ca"))
			if row == 1 and column == 1:
				keyboard_left = key
			elif row == 1 and column == 6:
				keyboard_right = key
	monitor_hinge = Node3D.new()
	monitor_hinge.position = Vector3(0, 1.0, 1.02)
	workbench.add_child(monitor_hinge)
	_piece(monitor_hinge, Vector3(1.16, 0.7, 0.08), Vector3(0, 0.35, 0), Color("233b4a"))
	var screen := _piece(monitor_hinge, Vector3(1.04, 0.55, 0.02), Vector3(0, 0.36, -0.051), Color("398a8c"))
	var screen_material := screen.material_override as StandardMaterial3D
	screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Non-text editor blocks show activity without source text, fake progress, or pass marks.
	for line in 4:
		_screen_blocks.append(_piece(monitor_hinge, Vector3(0.45 + (line % 2) * 0.3, 0.045, 0.015), Vector3(-0.06, 0.52 - line * 0.11, -0.07), Color("98dfcb")))
	workbench.visible = false

func _limb(point: Vector3, size: Vector3, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = point
	body.add_child(pivot)
	_piece(pivot, size, Vector3(0, -size.y * 0.5, 0), color)
	return pivot

func set_work(data: Dictionary) -> void:
	_update_module(data)
	var next := str(data.get("state", "paused"))
	if next not in ["thinking", "coding", "building", "testing", "fixing", "saved", "done", "gone", "paused"]:
		next = "paused"
	var changed := next != requested_state or next != state
	requested_state = next
	state = next
	if changed:
		action_time = 0.0
		_key_beat = -1
	if state != "building":
		working = false
		work_left = 0.0
		walking = false
		destination = position
		typing = false
		if is_instance_valid(sparks):
			sparks.emitting = false
	if state in ["paused", "done", "gone", "saved"]:
		typing = false
		if is_instance_valid(arm):
			arm.rotation = Vector3.ZERO
			left_arm.rotation = Vector3.ZERO
			body.position = Vector3.ZERO
			body.rotation = Vector3.ZERO
	_update_label()

func _update_label() -> void:
	if not is_instance_valid(label):
		return
	var short: String = {"thinking": "规划", "coding": "编写", "building": "搭建", "testing": "观察", "fixing": "修正", "saved": "已保存", "paused": "暂停", "done": "结束", "gone": ""}.get(state, "待命")
	label.text = module_name + "·" + short if not module_name.is_empty() else {"thinking": "规划", "coding": "编写逻辑", "building": "搭建", "testing": "观察试玩", "fixing": "修正逻辑", "saved": "已保存", "paused": "待命", "done": "完成", "gone": ""}.get(state, "待命")

static func _safe_module(value: Variant) -> String:
	var text := str(value).strip_edges().replace("\n", " ")
	if text.contains("{") or text.contains("func ") or text.contains("res://"):
		return ""
	return text.left(12)

func _update_module(data: Dictionary) -> void:
	var previous := module_name + "|" + module_file
	if data.has("file"):
		module_file = str(data.file).left(180)
	if data.has("step"):
		module_step = _safe_module(data.step)
	if data.has("module"):
		module_name = _safe_module(data.module)
	elif data.has("file") and not module_file.is_empty():
		module_name = _safe_module(module_file.replace("\\", "/").get_file().get_basename())
	elif module_name.is_empty() and data.has("step"):
		module_name = module_step
	if module_name + "|" + module_file == previous:
		return
	module_changes += 1
	module_flash = 1.2
	var key := absi((module_name + module_file).hash())
	for i in _screen_blocks.size():
		_screen_blocks[i].scale.x = 0.55 + float((key >> (i * 3)) % 6) * 0.1
		var material := _screen_blocks[i].material_override as StandardMaterial3D
		material.albedo_color = Color("b9e7ff") if key % 2 == 0 else Color("ffe0a2")

func work_at(bounds: AABB, seconds: float) -> void:
	# Stand beside the actual bounds; never reinterpret viewport coordinates as world points.
	var point := bounds.get_center()
	work_target = point
	destination = Vector3(point.x, maxf(0.0, bounds.position.y), bounds.end.z + 0.8)
	state = "building"
	typing = false
	desk_open = 0.0
	workbench.visible = false
	work_left = maxf(seconds, 0.6)
	working = false
	walking = true
	_update_label()

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	elapsed += delta
	action_time += delta
	module_flash = maxf(0.0, module_flash - delta)
	if not is_instance_valid(body):
		return
	label.modulate = Color("ffe2a1") if module_flash > 0.0 else Color.WHITE
	var before := position
	if walking:
		position = position.move_toward(destination, delta * 18.0)
		var move := position - before
		if move.length_squared() > 0.0001:
			rotation.y = atan2(move.x, move.z)
		if position.distance_to(destination) < 0.03:
			walking = false
			working = work_left > 0.0
			var face := work_target - position
			if Vector2(face.x, face.z).length_squared() > 0.0001:
				rotation.y = atan2(face.x, face.z)
	var desk_active := not walking and not working and state in ["coding", "fixing"]
	desk_open = move_toward(desk_open, 1.0 if desk_active else 0.0, delta * 3.5)
	workbench.visible = desk_open > 0.001
	workbench.scale.y = maxf(desk_open, 0.001)
	monitor_hinge.rotation.x = lerpf(PI * 0.5, 0.0, desk_open)
	typing = desk_active and desk_open >= 0.95
	hammer.visible = working or (state == "building" and walking)
	body.rotation.x = 0.0
	left_arm.rotation.x = 0.0
	keyboard_left.position.y = 1.012
	keyboard_right.position.y = 1.012
	if typing:
		typing_time += delta
		var tap := sin(typing_time * TAU * 4.0)
		# Opposed phases keep both hands visibly active instead of one welding/tool motion.
		left_arm.rotation.x = -1.08 + tap * 0.18
		arm.rotation.x = -1.08 - tap * 0.18
		body.rotation.x = 0.06
		body.position.y = sin(typing_time * TAU * 2.0) * 0.012
		keyboard_left.position.y -= maxf(0.0, tap) * 0.025
		keyboard_right.position.y -= maxf(0.0, -tap) * 0.025
		var beat := int(typing_time * 8.0)
		if beat != _key_beat:
			_key_beat = beat
			if beat % 2 == 0:
				left_key_presses += 1
			else:
				right_key_presses += 1
	elif working:
		var old := int(elapsed * 4.0)
		work_left -= delta
		arm.rotation.x = -1.1 + sin(elapsed * 24.0) * 0.65
		body.position.y = sin(elapsed * 24.0) * 0.035
		if int((elapsed + delta) * 4.0) != old:
			strokes += 1
		if work_left <= 0.0:
			working = false
			# Finishing a cosmetic stroke is not a save or a successful test.
			state = requested_state
			_update_label()
	elif state == "testing":
		arm.rotation.x = -0.8 + sin(action_time * 2.2) * 0.12
		left_arm.rotation.x = -0.45
		body.rotation.y = sin(action_time * 0.8) * 0.1
		body.position.y = 0.0
	else:
		arm.rotation.x = sin(elapsed * 13.0) * 0.4 if walking else 0.0
		left_arm.rotation.x = -arm.rotation.x
		body.position.y = absf(sin(elapsed * 13.0)) * 0.06 if walking else 0.0
		body.rotation.y = 0.0
	left_leg.rotation.x = sin(elapsed * 13.0) * 0.65 if walking else 0.0
	right_leg.rotation.x = -left_leg.rotation.x
	sparks.emitting = working
	sparks.position = Vector3(0.35, 1.0, 0.55)
