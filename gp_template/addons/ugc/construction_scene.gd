extends Node3D
## The same constrained, committed scene description is used in the yard and the game.
## This node adds geometry only: no camera, input, gameplay rules, or construction actors.
signal construction_step(id: String, object: Dictionary)
signal snapshot_applied(result: Dictionary)

const PENCIL = preload("res://addons/ugc/pencil.gd")

@export var source_path := "res://scenes/construction.json"
@export var collisions_enabled := true
var objects: Dictionary = {}
var snapshot: Dictionary = {}
var last_errors: Array = []
var _generation := 0
var _accepted_revision := -1
var _run_id := ""
## Levels created since the pencil kit draw with it; older levels keep StandardMaterial3D.
var _pencil := false

func _ready() -> void:
	add_to_group("ugc_construction_scene")
	set_meta("construction_revision", -1)
	set_meta("objects_count", 0)
	if source_path.is_empty():
		return
	if not FileAccess.file_exists(source_path):
		last_errors = ["Scene description not found: " + source_path]
		return
	var value = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	if not value is Dictionary:
		last_errors = ["Scene description must be a JSON object"]
		return
	await apply_snapshot(value)

static func _vector(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for n in value:
		if not (n is float or n is int) or not is_finite(float(n)):
			return false
	return true

static func v3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func validate(value: Dictionary) -> Array:
	var errors: Array = []
	if value.get("schema") != 1 or value.get("dimension") != "3d":
		return ["Expected construction schema 1, dimension 3d"]
	var revision = value.get("revision")
	if not (revision is int or revision is float) or float(revision) < 0 or float(revision) != floorf(float(revision)):
		return ["Invalid construction revision"]
	if not value.get("runId", "") is String:
		return ["Invalid construction runId"]
	var rows = value.get("objects")
	if not rows is Array or rows.size() > 256:
		return ["Expected at most 256 construction objects"]
	var ids: Dictionary = {}
	var id_pattern := RegEx.create_from_string("^[A-Za-z0-9_-]{1,64}$")
	var color_pattern := RegEx.create_from_string("^#[0-9a-fA-F]{6}$")
	for row in rows:
		if not row is Dictionary:
			return ["Invalid construction object"]
		var id := str(row.get("id", ""))
		if id_pattern.search(id) == null or ids.has(id):
			return ["Invalid or duplicate object id: " + id.left(64)]
		ids[id] = true
		if row.get("kind") not in ["box", "sphere", "cylinder", "cone"]:
			return ["Unsupported primitive: " + id]
		for field in ["position", "size", "rotation"]:
			if not _vector(row.get(field)):
				return ["Invalid " + field + ": " + id]
			for n in row[field]:
				if absf(float(n)) > 10000 or (field == "size" and (float(n) <= 0 or float(n) > 1000)):
					return ["Out of range " + field + ": " + id]
		if color_pattern.search(str(row.get("color", ""))) == null or not row.get("solid") is bool:
			return ["Invalid color or solid flag: " + id]
	if value.has("camera"):
		var camera = value.camera
		if not camera is Dictionary or not _vector(camera.get("position")) or not _vector(camera.get("lookAt")):
			return ["Invalid camera"]
	if value.has("environment"):
		var environment = value.environment
		if not environment is Dictionary:
			return ["Invalid environment"]
		for key in ["background", "ambient"]:
			if environment.has(key) and color_pattern.search(str(environment[key])) == null:
				return ["Invalid environment color"]
	return errors

func apply_snapshot(value: Dictionary, animate := false) -> Dictionary:
	last_errors = validate(value)
	if not last_errors.is_empty():
		return _report(value, false, last_errors)
	var revision := int(value.revision)
	# Revision is project-monotonic, including across authoring runs.
	if revision < _accepted_revision:
		return {"loaded": false, "ignored": true, "reason": "stale", "revision": revision, "errors": []}
	if revision == _accepted_revision and value == snapshot:
		return _report(value, true, [])
	_generation += 1
	var generation := _generation
	_accepted_revision = revision
	_run_id = str(value.get("runId", ""))
	_pencil = str(value.get("style", "")) == "pencil"
	var incoming: Dictionary = {}
	var changed: Array = []
	for row in value.objects:
		incoming[row.id] = row
		if not objects.has(row.id) or objects[row.id].get_meta("construction_data", {}) != row:
			changed.append(row)
	for id in objects.keys():
		if not incoming.has(id):
			_discard(id)
	var delay := minf(0.38, 5.8 / maxf(1.0, changed.size())) if animate else 0.0
	for row in changed:
		if generation != _generation:
			return {"loaded": false, "ignored": true, "reason": "superseded", "errors": []}
		if animate:
			construction_step.emit(str(row.id), row)
			await get_tree().create_timer(delay, true, false, true).timeout
		if generation != _generation:
			return {"loaded": false, "ignored": true, "reason": "superseded", "errors": []}
		_upsert(row)
	snapshot = value.duplicate(true)
	set_meta("construction_revision", revision)
	set_meta("objects_count", objects.size())
	set_meta("construction_run_id", _run_id)
	var result := _report(value, true, [])
	snapshot_applied.emit(result)
	return result

func cancel_animation() -> void:
	_generation += 1

func _report(value: Dictionary, loaded: bool, errors: Array) -> Dictionary:
	return {"revision": int(value.get("revision", -1)), "runId": str(value.get("runId", "")), "loaded": loaded, "objectCount": objects.size(), "errors": errors}

func _discard(id: String) -> void:
	var node: Node3D = objects[id]
	objects.erase(id)
	remove_child(node)
	node.queue_free()

func _upsert(row: Dictionary) -> void:
	var id: String = row.id
	var node: Node3D = objects.get(id)
	if node == null:
		node = Node3D.new()
		node.name = id
		add_child(node)
		objects[id] = node
	else:
		for child in node.get_children():
			node.remove_child(child)
			child.queue_free()
	node.position = v3(row.position)
	node.rotation_degrees = v3(row.rotation)
	node.set_meta("construction_data", row.duplicate(true))
	node.set_meta("construction_id", id)
	var size := v3(row.size)
	var mesh: PrimitiveMesh
	match row.kind:
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			sphere.radial_segments = 24
			sphere.rings = 12
			mesh = sphere
		"cylinder", "cone":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.0 if row.kind == "cone" else 0.5
			cylinder.bottom_radius = 0.5
			cylinder.height = 1.0
			cylinder.radial_segments = 24
			mesh = cylinder
		_:
			var box := BoxMesh.new()
			box.size = Vector3.ONE
			mesh = box
	var mi := MeshInstance3D.new()
	mi.name = "Visual"
	mi.mesh = mesh
	mi.scale = size
	if _pencil:
		mi.material_override = PENCIL.material(Color(row.color), str(row.get("art", "")))
	else:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(row.color)
		material.roughness = 0.8
		mi.material_override = material
	node.add_child(mi)
	if bool(row.solid) and collisions_enabled:
		var body := StaticBody3D.new()
		body.name = "Solid"
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		# Bake exact non-uniform dimensions into a convex hull, never scale physics bodies.
		if row.kind == "box":
			var shape := BoxShape3D.new()
			shape.size = size
			collision.shape = shape
		else:
			var shape := ConvexPolygonShape3D.new()
			var points := PackedVector3Array()
			for point in mesh.get_faces():
				points.append(point * size)
			shape.points = points
			collision.shape = shape
		body.add_child(collision)
		node.add_child(body)

func object_aabb(row: Dictionary) -> AABB:
	var size := v3(row.size)
	var transform := Transform3D(Basis.from_euler(v3(row.rotation) * PI / 180.0), v3(row.position))
	return transform * AABB(-size * 0.5, size)
