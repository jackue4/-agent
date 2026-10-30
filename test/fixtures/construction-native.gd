extends "res://yard_root.gd"
const LEVEL = preload("res://addons/ugc/construction_scene.gd")
signal animation_finished
var failures: Array = []
var check_count := 0
var applied_steps: Array = []
var animated_result: Dictionary = {}
var superseding_result: Dictionary = {}

func _ready() -> void:
	super._ready()
	_run.call_deferred()

func verify(value: bool, title: String) -> void:
	check_count += 1
	if not value:
		failures.append(title)

func description(revision: int) -> Dictionary:
	return {"schema": 1, "dimension": "3d", "revision": revision, "runId": "native-real-scene", "step": "地台与障碍", "objects": [
		{"id": "floor", "label": "地台", "kind": "box", "position": [0, -0.4, 0], "size": [18, 0.8, 12], "rotation": [0, 0, 0], "color": "#477970", "solid": true},
		{"id": "block", "label": "障碍", "kind": "box", "position": [-3, 1, 0], "size": [2, 2, 2], "rotation": [0, 30, 0], "color": "#edbf6c", "solid": true},
		{"id": "orb", "label": "球", "kind": "sphere", "position": [0, 1, 1], "size": [1.6, 2, 1.6], "rotation": [0, 0, 0], "color": "#b49ae3", "solid": false},
		{"id": "tower", "label": "柱", "kind": "cylinder", "position": [4, 1.5, -2], "size": [2, 3, 2], "rotation": [0, 0, 0], "color": "#77bbd6", "solid": true},
		{"id": "tip", "label": "锥", "kind": "cone", "position": [4, 3.8, -2], "size": [2.5, 1.6, 2.5], "rotation": [0, 0, 0], "color": "#db8d79", "solid": true}],
		"camera": {"position": [17, 15, 21], "lookAt": [0, 1, 0]}, "environment": {"background": "#172334", "ambient": "#b9d1dc"}}

func _run() -> void:
	UGC.show_crew = true
	set_dimension("3d")
	verify(uses_world_crew(), "3d dimension creates actual Node3D stage")
	verify(construction_yard.level.objects.is_empty(), "empty stage invents no game objects")
	var snap := description(1)
	var result: Dictionary = await apply_construction({"snapshot": snap, "restore": true})
	verify(result.loaded and result.objectCount == 5, "restored committed snapshot creates five objects")
	verify(construction_yard.level.objects.floor.position == Vector3(0, -0.4, 0), "world position exact")
	verify(construction_yard.level.objects.block.rotation_degrees.is_equal_approx(Vector3(0, 30, 0)), "rotation degrees exact")
	verify(construction_yard.level.objects.orb.get_node("Visual").scale == Vector3(1.6, 2, 1.6), "nonuniform primitive dimensions exact")
	verify(construction_yard.level.objects.block.get_node("Visual").material_override.albedo_color == Color("edbf6c"), "committed color exact")
	verify(not construction_yard.level.objects.floor.has_node("Solid"), "yard never creates game collisions")
	var stable_id: int = construction_yard.level.objects.block.get_instance_id()
	var updated := description(2)
	updated.objects[1].position = [-2, 1.5, 1]
	updated.objects.remove_at(2)
	result = await apply_construction({"snapshot": updated, "restore": true})
	verify(result.objectCount == 4 and not construction_yard.level.objects.has("orb"), "removed object truly removed")
	verify(construction_yard.level.objects.block.get_instance_id() == stable_id, "upsert preserves stable object node")
	verify(construction_yard.level.objects.block.position == Vector3(-2, 1.5, 1), "upsert moves existing object")
	result = await apply_construction({"snapshot": snap, "restore": true})
	verify(bool(result.get("ignored", false)) and construction_yard.level.objects.size() == 4, "stale snapshot cannot roll back scene")
	var bad := description(3)
	bad.objects[0].kind = "script"
	result = await apply_construction({"snapshot": bad, "restore": true})
	verify(not result.loaded and construction_yard.level.objects.size() == 4, "invalid kind rejected atomically")
	bad = description(3)
	bad.objects[1].id = "floor"
	verify(not LEVEL.validate(bad).is_empty(), "duplicate stable IDs rejected")
	bad = description(3)
	bad.objects[0].size = [0, 2, 2]
	verify(not LEVEL.validate(bad).is_empty(), "zero dimension rejected")
	# Real final game scene loads the exact same JSON through its exported source_path.
	DirAccess.make_dir_recursive_absolute("user://construction-test")
	var json_path := "user://construction-test/construction.json"
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(updated))
	file.close()
	var final_level = LEVEL.new()
	final_level.source_path = json_path
	final_level.name = "FinalGameLevel"
	add_child(final_level)
	verify(final_level.objects.size() == 4, "final loader reads same JSON at ready")
	verify(final_level.objects.floor.has_node("Solid"), "final game creates requested static collision")
	verify(final_level.objects.tower.get_node("Solid/CollisionShape3D").shape is ConvexPolygonShape3D, "nonuniform cylinder uses baked convex collision")
	verify(final_level.objects.block.transform.is_equal_approx(construction_yard.level.objects.block.transform), "final and construction transforms identical")
	verify(final_level.objects.block.get_node("Visual").mesh.get_faces() == construction_yard.level.objects.block.get_node("Visual").mesh.get_faces(), "final and construction geometry identical")
	verify(final_level.get_meta("construction_revision") == 2 and final_level.get_meta("objects_count") == 4, "final revision/count metadata bound")
	verify(final_level.is_in_group("ugc_construction_scene"), "actual loader discoverable for verification")
	var reports: Array = UGC.construction_report()
	verify(reports.any(func(row): return row.source_path == json_path and row.revision == 2 and row.objectCount == 4), "check report includes actual loaded JSON source")
	final_level.hide()
	# Cosmetic 3D engineer movement and work happen beside a committed object's AABB.
	construction_yard.set_actor({"agent": "M", "state": "building"})
	var engineer = construction_yard.actors.M
	engineer.set_process(false)
	var start: Vector3 = engineer.position
	engineer.work_at(construction_yard.level.object_aabb(updated.objects[1]), 0.5)
	engineer.advance(0.05)
	verify(engineer.position.distance_to(start) > 0.01, "engineer really walks in world space")
	for i in 40:
		engineer.advance(0.05)
	verify(engineer.position.is_equal_approx(engineer.destination), "engineer arrives beside actual object")
	verify(engineer.strokes > 0, "engineer performs physical hammer motion after arrival")
	verify(not engineer.working, "finite construction animation stops")
	engineer.work_at(construction_yard.level.object_aabb(updated.objects[1]), 3)
	engineer.advance(0.01)
	engineer.set_work({"state": "paused"})
	var paused: Vector3 = engineer.position
	engineer.advance(2)
	verify(not engineer.working and not engineer.walking and engineer.position == paused, "paused halts walking and construction immediately")
	# A newer snapshot cancels pending reveals instead of allowing late old objects to return.
	construction_yard.level.construction_step.connect(func(id, _row): applied_steps.append(id))
	# Supersede at the first actual reveal boundary. Timer delays do not guarantee callback
	# ordering when several native engines compete for a frame in the parallel Node suite.
	construction_yard.level.construction_step.connect(_supersede_first_step, CONNECT_ONE_SHOT)
	_animate(description(3))
	await animation_finished
	verify(bool(superseding_result.get("loaded", false)) and construction_yard.level.objects.size() == 1, "restore supersedes animated older snapshot")
	verify(bool(animated_result.get("ignored", false)), "superseded animation cannot acknowledge old revision")
	verify(applied_steps.size() == 1, "newer restore stops remaining old reveals")
	await apply_construction({"snapshot": description(5), "restore": true})
	UGC.show_crew = false
	verify(construction_yard.actors.is_empty(), "show_crew false removes all world engineers")
	verify(construction_yard.level.objects.size() == 5, "hide crew never removes committed game geometry")
	print("CONSTRUCTION_NATIVE_RESULT ", JSON.stringify({"checks": check_count, "failed": failures}))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			UGC.show_crew = true
			construction_yard.set_actor({"agent": "M", "state": "building"})
			construction_yard.actors.M.position = Vector3(-2, 0, 2)
			construction_yard.actors.M.work_at(construction_yard.level.object_aabb(description(5).objects[1]), 2)
			await get_tree().create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture="))
	get_tree().quit(0 if failures.is_empty() else 1)

func _animate(value: Dictionary) -> void:
	animated_result = await apply_construction({"snapshot": value, "restore": false})
	animation_finished.emit()

func _supersede_first_step(_id: String, _row: Dictionary) -> void:
	var newest := description(4)
	newest.objects = [newest.objects[0]]
	superseding_result = await apply_construction({"snapshot": newest, "restore": true})
