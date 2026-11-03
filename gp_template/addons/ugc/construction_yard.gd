extends Node3D
## Authoring-only stage. The level child is the same loader used by the shipped game.
const SCENE = preload("res://addons/ugc/construction_scene.gd")
const ACTOR = preload("res://addons/ugc/construction_actor.gd")
var level: Node3D
var camera: Camera3D
var world_environment: WorldEnvironment
var actors: Dictionary = {}
var phase := "scope"
var camera_locked := false
var _worker_index := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	level = SCENE.new()
	level.name = "CommittedLevel"
	level.source_path = ""
	level.collisions_enabled = false
	add_child(level)
	level.construction_step.connect(_construction_step)
	camera = Camera3D.new()
	camera.name = "ConstructionCamera"
	camera.position = Vector3(18, 16, 22)
	camera.fov = 48
	camera.near = 0.1
	camera.far = 3000
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	get_viewport().size_changed.connect(_fit_aspect)
	_fit_aspect()
	world_environment = WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("172334")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b9d1dc")
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -32, 0)
	light.light_color = Color("fff0d6")
	light.light_energy = 1.1
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 100
	add_child(light)
	_build_grid()
	set_actor({"agent": "M", "state": "paused"})

func _fit_aspect() -> void:
	# fov always spans the short side, so a portrait phone is not cropped to a sliver.
	var size := get_viewport().get_visible_rect().size
	camera.keep_aspect = Camera3D.KEEP_WIDTH if size.y > size.x else Camera3D.KEEP_HEIGHT

func _build_grid() -> void:
	# This is a non-colliding editor measuring grid, never counted as authored geometry.
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for n in range(-40, 41, 2):
		lines.surface_add_vertex(Vector3(n, -0.035, -40))
		lines.surface_add_vertex(Vector3(n, -0.035, 40))
		lines.surface_add_vertex(Vector3(-40, -0.035, n))
		lines.surface_add_vertex(Vector3(40, -0.035, n))
	lines.surface_end()
	var grid := MeshInstance3D.new()
	grid.name = "AuthoringGrid"
	grid.mesh = lines
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("365367")
	grid.material_override = mat
	add_child(grid)

func apply_construction(message: Dictionary) -> Dictionary:
	var value = message.get("snapshot")
	if not value is Dictionary:
		return {"loaded": false, "errors": ["Missing construction snapshot"]}
	var errors: Array = SCENE.validate(value)
	if not errors.is_empty():
		return {"loaded": false, "revision": int(value.get("revision", -1)), "runId": str(value.get("runId", "")), "errors": errors}
	if int(value.revision) < int(level._accepted_revision):
		return {"loaded": false, "ignored": true, "reason": "stale", "errors": []}
	var restore := bool(message.get("restore", false))
	if restore:
		stop_workers()
	if not camera_locked:
		configure_camera(value.get("camera", {}))
	var env: Dictionary = value.get("environment", {})
	if env.has("background"):
		world_environment.environment.background_color = Color(env.background)
	if env.has("ambient"):
		world_environment.environment.ambient_light_color = Color(env.ambient)
	var result: Dictionary = await level.apply_snapshot(value, not restore)
	if bool(result.get("loaded", false)):
		for actor in actors.values():
			if not actor.walking:
				_place_on_surface(actor)
	return result

func configure_camera(camera_data: Dictionary) -> void:
	if camera_data.is_empty():
		return
	camera.position = SCENE.v3(camera_data.position)
	var target := SCENE.v3(camera_data.lookAt)
	if camera.position.distance_squared_to(target) > 0.001:
		var up := Vector3.FORWARD if absf((target - camera.position).normalized().dot(Vector3.UP)) > 0.999 else Vector3.UP
		camera.look_at(target, up)

func _construction_step(_id: String, row: Dictionary) -> void:
	if phase in ["paused", "cancelled", "interrupted", "partial", "failed"]:
		return
	if actors.is_empty():
		set_actor({"agent": "M", "state": "building"})
	var available: Array = []
	for actor in actors.values():
		if actor.requested_state in ["thinking", "coding", "building", "testing", "fixing"]:
			available.append(actor)
	if available.is_empty():
		return
	var worker = available[_worker_index % available.size()]
	_worker_index += 1
	worker.work_at(level.object_aabb(row), 0.42)

func set_actor(data: Dictionary) -> void:
	var id := str(data.get("agent", ""))
	if id.is_empty():
		return
	var state := str(data.get("state", "paused"))
	if state in ["gone", "done"]:
		if actors.has(id):
			actors[id].queue_free()
			actors.erase(id)
		return
	if not actors.has(id):
		if actors.size() >= 4:
			return
		var actor = ACTOR.new()
		actor.actor_id = id
		actor.position = Vector3(-4 + actors.size() * 1.4, 0, 5)
		# Face into the scene so the observer can see the folding screen and both hands.
		actor.rotation.y = atan2(actor.position.x - camera.position.x, actor.position.z - camera.position.z)
		add_child(actor)
		actors[id] = actor
	actors[id].set_work(data)
	if not actors[id].walking:
		_place_on_surface(actors[id])

func _place_on_surface(actor: Node3D) -> void:
	# A folding desk must stand on a committed floor, not inside a raised island.
	# Only broad, thin solid box/cylinder caps are supports; tall props/roofs are not guessed.
	var best_height := 0.0
	var best_distance := INF
	for object in level.objects.values():
		var row: Dictionary = object.get_meta("construction_data", {})
		if not bool(row.get("solid", false)) or row.get("kind") not in ["box", "cylinder"]:
			continue
		var size := SCENE.v3(row.size)
		if size.y > 1.5 or minf(size.x, size.z) < 3.0:
			continue
		var normal: Vector3 = object.basis.y.normalized()
		if normal.y < 0.4:
			continue
		var top: Vector3 = object.transform * Vector3(0, size.y * 0.5, 0)
		var height := top.y - (normal.x * (actor.position.x - top.x) + normal.z * (actor.position.z - top.z)) / normal.y
		var local: Vector3 = object.transform.affine_inverse() * Vector3(actor.position.x, height, actor.position.z)
		if absf(local.x) > size.x * 0.5 or absf(local.z) > size.z * 0.5:
			continue
		if row.kind == "cylinder" and pow(local.x / (size.x * 0.5), 2) + pow(local.z / (size.z * 0.5), 2) > 1.0:
			continue
		var distance := absf(height - actor.position.y)
		if distance < best_distance:
			best_distance = distance
			best_height = height
	actor.position.y = best_height

func apply_workshop(message: Dictionary) -> void:
	phase = str(message.get("phase", phase))
	if message.get("actors") is Array:
		var present: Dictionary = {}
		for row in message.actors.slice(0, 4):
			if row is Dictionary:
				present[str(row.get("agent", ""))] = true
				set_actor(row)
		for id in actors.keys():
			if not present.has(id):
				set_actor({"agent": id, "state": "gone"})
	if phase in ["paused", "cancelled", "interrupted", "partial", "failed"]:
		stop_workers()

func stop_workers() -> void:
	for actor in actors.values():
		actor.set_work({"state": "paused"})

func clear_workers() -> void:
	for actor in actors.values():
		actor.queue_free()
	actors.clear()
