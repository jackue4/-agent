extends Node3D
## Authoring-only interaction. Preview transforms never change the committed JSON/metadata.
signal event_emitted(event: Dictionary)
signal frame_requested

const ACTIONS := {
	"ugc_editor_left": KEY_LEFT, "ugc_editor_right": KEY_RIGHT,
	"ugc_editor_forward": KEY_UP, "ugc_editor_back": KEY_DOWN,
	"ugc_editor_raise": KEY_PAGEUP, "ugc_editor_lower": KEY_PAGEDOWN,
	"ugc_editor_cancel": KEY_ESCAPE, "ugc_editor_frame": KEY_HOME,
}
var yard: Node3D
var enabled := false
var busy := false
var applying := false
var camera_owned := false
var selected_id := ""
var pending := false
var dragging := false
var revision := -1
var _drag_from := Vector3.ZERO
var _drag_hit := Vector3.ZERO
var _drag_screen := Vector2.ZERO
var _drag_moved := false
var _drag_revision := -1
var _orbiting := false
var _panning := false
var _pivot := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.6
var _distance := 25.0
var _requests := 0
var _created_actions: Array[String] = []
var _outline: MeshInstance3D

func setup(value: Node3D) -> void:
	yard = value
	process_mode = Node.PROCESS_MODE_ALWAYS
	_outline = MeshInstance3D.new()
	_outline.name = "EditorSelectionOutline"
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("ffe28a")
	material.no_depth_test = true
	_outline.material_override = material
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_outline)
	_outline.hide()
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key := InputEventKey.new()
			key.physical_keycode = ACTIONS[action]
			InputMap.action_add_event(action, key)
			_created_actions.append(action)

func _exit_tree() -> void:
	for action in _created_actions:
		InputMap.erase_action(action)

func can_move() -> bool:
	return UGC.show_crew and enabled and not busy and not applying and not pending and revision >= 0

func set_busy(value: bool) -> void:
	busy = value
	if busy and dragging:
		cancel_preview()

func handle(message: Dictionary) -> void:
	if message.has("enabled"):
		enabled = bool(message.enabled)
		if not enabled and dragging:
			cancel_preview()
	match str(message.get("action", "")):
		"select": select_object(str(message.get("id", "")))
		"nudge":
			var delta = message.get("delta")
			if delta is Array and delta.size() == 3:
				for component in delta:
					if not (component is float or component is int) or not is_finite(float(component)) or absf(float(component)) > 10.0:
						return
				if message.has("id") and str(message.id) != selected_id:
					select_object(str(message.id))
				nudge(Vector3(float(delta[0]), float(delta[1]), float(delta[2])))
		"undo_preview": cancel_preview()
		"frame": frame_scene()

func before_snapshot(value: Dictionary, restore: bool) -> void:
	if int(value.get("revision", -1)) < revision:
		return
	if restore or int(value.get("revision", -1)) > revision:
		# Same-revision restore matters after a rejected move: the shared loader may early-return.
		_restore_canonical_position()
		pending = false
		dragging = false
		_drag_moved = false
	applying = true

func after_snapshot(result: Dictionary) -> void:
	applying = false
	if not bool(result.get("loaded", false)):
		return
	revision = int(result.get("revision", revision))
	if not yard.level.objects.has(selected_id):
		selected_id = ""
	_refresh_outline()
	_emit_selection()

func select_object(id: String) -> void:
	if pending or applying:
		return
	if dragging:
		cancel_preview()
	selected_id = id if yard.level.objects.has(id) else ""
	_refresh_outline()
	_emit_selection()

func pick_at(screen: Vector2) -> String:
	var camera: Camera3D = yard.camera
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var nearest := INF
	var picked := ""
	for id in yard.level.objects:
		var object: Node3D = yard.level.objects[id]
		var visual := object.get_node_or_null("Visual") as MeshInstance3D
		if visual == null or not visual.is_visible_in_tree():
			continue
		var inverse := visual.global_transform.affine_inverse()
		var local_origin: Vector3 = inverse * origin
		var local_direction: Vector3 = (inverse.basis * direction).normalized()
		if visual.mesh.get_aabb().intersects_ray(local_origin, local_direction) == null:
			continue
		# Test real primitive triangles after the cheap bounds filter; empty sphere/cone corners
		# must not intercept a click intended for an object behind them.
		var faces := visual.mesh.get_faces()
		for index in range(0, faces.size(), 3):
			var hit = Geometry3D.ray_intersects_triangle(local_origin, local_direction, faces[index], faces[index + 1], faces[index + 2])
			if hit == null:
				continue
			var distance: float = ((visual.global_transform * hit) - origin).dot(direction)
			if distance >= 0.0 and distance < nearest:
				nearest = distance
				picked = id
	return picked

func _plane_hit(screen: Vector2, height: float) -> Variant:
	var camera: Camera3D = yard.camera
	return Plane(Vector3.UP, height).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))

func begin_drag(screen: Vector2) -> void:
	if not can_move() or not yard.level.objects.has(selected_id):
		return
	_drag_from = yard.level.objects[selected_id].position
	var hit = _plane_hit(screen, _drag_from.y)
	if hit == null:
		return
	claim_camera()
	_drag_hit = hit
	_drag_screen = screen
	_drag_moved = false
	_drag_revision = revision
	dragging = true

func drag_to(screen: Vector2) -> void:
	if not dragging or not can_move() or _drag_revision != revision:
		return
	if not _drag_moved and screen.distance_to(_drag_screen) < 4.0:
		return
	var hit = _plane_hit(screen, _drag_from.y)
	if hit == null:
		return
	_drag_moved = true
	var destination: Vector3 = _drag_from + (hit as Vector3) - _drag_hit
	destination.y = _drag_from.y
	_preview(destination)

func end_drag() -> void:
	if not dragging:
		return
	dragging = false
	if _drag_moved and _drag_revision == revision:
		_commit_move()
	_drag_moved = false

func nudge(delta: Vector3) -> void:
	if not can_move() or not yard.level.objects.has(selected_id) or delta.is_zero_approx():
		return
	claim_camera()
	_preview(yard.level.objects[selected_id].position + delta)
	_commit_move()

func _preview(position: Vector3) -> void:
	if not yard.level.objects.has(selected_id):
		return
	var point := position.clamp(Vector3.ONE * -200.0, Vector3.ONE * 200.0)
	point = point.snapped(Vector3.ONE * 0.01)
	yard.level.objects[selected_id].position = point
	_refresh_outline()

func _commit_move() -> void:
	if not can_move() or not yard.level.objects.has(selected_id):
		return
	var object: Node3D = yard.level.objects[selected_id]
	var original: Array = object.get_meta("construction_data").position
	if object.position.is_equal_approx(Vector3(original[0], original[1], original[2])):
		return
	pending = true
	_requests += 1
	_emit_selection()
	_emit({"type":"editor_move", "id":selected_id, "position":_array(object.position), "baseRevision":revision, "requestId":"%d-%d-%d" % [get_instance_id(), Time.get_ticks_msec(), _requests]})

func cancel_preview() -> void:
	if pending:
		# A request already sent cannot be cancelled locally. Only a canonical response settles it.
		return
	_restore_canonical_position()
	dragging = false
	_drag_moved = false
	_refresh_outline()
	_emit_selection()

func _restore_canonical_position() -> void:
	if not yard.level.objects.has(selected_id):
		return
	var object: Node3D = yard.level.objects[selected_id]
	var row: Dictionary = object.get_meta("construction_data", {})
	if row.has("position"):
		object.position = Vector3(row.position[0], row.position[1], row.position[2])

func _refresh_outline() -> void:
	_outline.visible = yard.level.objects.has(selected_id)
	if not _outline.visible:
		return
	var object: Node3D = yard.level.objects[selected_id]
	var row: Dictionary = object.get_meta("construction_data", {})
	var size := Vector3(row.size[0], row.size[1], row.size[2])
	var bounds := AABB(-size * 0.5, size).grow(0.025)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for corner in 8:
		for bit in [1, 2, 4]:
			if (corner & bit) == 0:
				mesh.surface_add_vertex(bounds.get_endpoint(corner))
				mesh.surface_add_vertex(bounds.get_endpoint(corner ^ bit))
	mesh.surface_end()
	_outline.mesh = mesh
	_outline.global_transform = object.global_transform

func _emit_selection() -> void:
	var event := {"type":"editor_selection", "id":selected_id, "label":"", "position":[], "revision":revision, "pending":pending, "enabled":can_move()}
	if yard.level.objects.has(selected_id):
		var object: Node3D = yard.level.objects[selected_id]
		event.label = str(object.get_meta("construction_data", {}).get("label", selected_id))
		event.position = _array(object.position)
	_emit(event)

func _emit(event: Dictionary) -> void:
	event_emitted.emit(event)
	UGC.emit(event)

static func _array(point: Vector3) -> Array:
	return [point.x, point.y, point.z]

func claim_camera() -> void:
	if camera_owned:
		return
	camera_owned = true
	yard.camera_locked = true
	_pivot = Vector3.ZERO
	if yard.level.objects.has(selected_id):
		_pivot = yard.level.objects[selected_id].global_position
	elif not yard.level.objects.is_empty():
		var first := true
		var bounds := AABB()
		for object in yard.level.objects.values():
			var next: AABB = yard.level.object_aabb(object.get_meta("construction_data"))
			bounds = next if first else bounds.merge(next)
			first = false
		_pivot = bounds.get_center()
	var offset: Vector3 = yard.camera.global_position - _pivot
	_distance = maxf(offset.length(), 1.0)
	_yaw = atan2(offset.x, offset.z)
	_pitch = clampf(asin(offset.y / _distance), -1.3, 1.45)

func orbit(relative: Vector2) -> void:
	claim_camera()
	_yaw -= relative.x * 0.006
	_pitch = clampf(_pitch + relative.y * 0.006, -1.3, 1.45)
	_update_camera()

func pan(relative: Vector2) -> void:
	claim_camera()
	var camera: Camera3D = yard.camera
	var view := get_viewport().get_visible_rect().size
	var span := view.x if camera.keep_aspect == Camera3D.KEEP_WIDTH else view.y
	var units := _distance * tan(deg_to_rad(camera.fov) * 0.5) * 2.0 / maxf(1.0, span)
	_pivot += (-camera.global_basis.x * relative.x + camera.global_basis.y * relative.y) * units
	_update_camera()

func zoom(direction: float) -> void:
	claim_camera()
	_distance = clampf(_distance * exp(direction * 0.12), 2.0, 800.0)
	_update_camera()

func _update_camera() -> void:
	var offset := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _distance
	yard.camera.global_position = _pivot + offset
	yard.camera.look_at(_pivot, Vector3.UP)

func frame_scene() -> void:
	if dragging:
		cancel_preview()
	camera_owned = false
	yard.camera_locked = false
	_orbiting = false
	_panning = false
	frame_requested.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_orbiting = false
		_panning = false
		if dragging:
			cancel_preview()

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(yard) or not UGC.show_crew:
		return
	var handled := false
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = event.pressed
				handled = true
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
				handled = true
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					zoom(-1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0)
				handled = true
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					select_object(pick_at(event.position))
					begin_drag(event.position)
				else:
					end_drag()
				handled = true
	elif event is InputEventMouseMotion:
		if _orbiting:
			if event.shift_pressed:
				pan(event.relative)
			else:
				orbit(event.relative)
			handled = true
		elif _panning:
			pan(event.relative)
			handled = true
		elif dragging:
			drag_to(event.position)
			handled = true
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("ugc_editor_cancel"):
			cancel_preview()
			handled = true
		elif event.is_action_pressed("ugc_editor_frame"):
			frame_scene()
			handled = true
		else:
			var motions := {"ugc_editor_left":Vector3.LEFT, "ugc_editor_right":Vector3.RIGHT, "ugc_editor_forward":Vector3.FORWARD, "ugc_editor_back":Vector3.BACK, "ugc_editor_raise":Vector3.UP, "ugc_editor_lower":Vector3.DOWN}
			for action in motions:
				if event.is_action_pressed(action):
					nudge(motions[action] * (1.0 if event.shift_pressed else 0.25))
					handled = true
	if handled:
		get_viewport().set_input_as_handled()
