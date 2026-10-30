extends Node2D
const ACTOR_2D = preload("res://addons/ugc/crew_actor.gd")
const ACTOR_3D = preload("res://addons/ugc/construction_actor.gd")
const YARD = preload("res://addons/ugc/construction_yard.gd")
const WORKSHOP = preload("res://workshop_root.gd")
var checks := 0
var failures: Array = []

func verify(condition: bool, what: String) -> void:
	checks += 1
	if not condition:
		failures.append(what)

func tick(actor: Node, seconds: float) -> void:
	actor.set_process(false)
	for i in ceili(seconds * 60):
		actor.advance(1.0 / 60.0)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var painter = ACTOR_2D.new()
	add_child(painter)
	painter.setup("M", {"state":"coding", "name":"编写逻辑"}, Vector2(1280,720))
	painter.position = painter.destination
	painter.walking = false
	verify(painter.desk_open == 0.0, "2d desk initially folded")
	tick(painter, 0.1)
	verify(painter.desk_open > 0.0 and painter.desk_open < 1.0 and not painter.typing, "2d desk unfolds before typing")
	tick(painter, 1.5)
	verify(painter.typing and painter.desk_open == 1.0, "2d coding opens visible workstation")
	verify(painter.left_key_presses > 0 and painter.right_key_presses > 0, "2d both hands perform keyboard strokes")
	verify(painter.emitted_particles == 0, "2d code typing does not pretend to weld")
	painter.typing_time = 0.0
	painter.advance(1.0/32.0)
	verify(painter.left_hand.y < -29.0 and is_equal_approx(painter.right_hand.y, -31.0), "2d left-hand tap phase")
	painter.advance(0.125)
	verify(is_equal_approx(painter.left_hand.y, -29.0) and painter.right_hand.y < -31.0, "2d right-hand tap phase alternates")
	for terminal in ["saved", "paused", "cancelled", "failed", "interrupted"]:
		painter.set_work({"state":"coding"})
		painter.position = painter.destination
		painter.walking = false
		tick(painter, 0.6)
		painter.set_work({"state":terminal})
		var count: int = painter.left_key_presses + painter.right_key_presses
		var location: Vector2 = painter.position
		verify(not painter.typing and not painter.walking, "2d " + terminal + " immediately stops")
		tick(painter, 0.8)
		verify(count == painter.left_key_presses + painter.right_key_presses and painter.desk_open == 0 and painter.position == location, "2d " + terminal + " no late strokes and desk folded")
	painter.set_work({"state":"fixing"})
	painter.position = painter.destination
	painter.walking = false
	tick(painter, 1.0)
	verify(painter.typing and painter.state == "fixing", "2d fixing uses keyboard without declaring success")
	painter.set_work({"state":"testing"})
	tick(painter, 1.0)
	verify(not painter.typing and painter.state == "testing" and painter.desk_open == 0, "2d testing only observes")
	var yard = YARD.new()
	add_child(yard)
	var engineer = yard.actors.M
	engineer.set_work({"state":"coding"})
	verify(not engineer.workbench.visible, "3d desk initially folded")
	tick(engineer, 0.1)
	verify(engineer.workbench.visible and engineer.desk_open < 1.0 and not engineer.typing, "3d desk actually unfolds")
	tick(engineer, 1.5)
	verify(engineer.typing and engineer.desk_open == 1.0, "3d coding runs keyboard animation")
	verify(engineer.left_key_presses > 0 and engineer.right_key_presses > 0, "3d both hands type")
	verify(not engineer.hammer.visible and not engineer.sparks.emitting, "3d typing has no hammer or welding sparks")
	engineer.typing_time = 0.0
	engineer.advance(1.0/32.0)
	verify(engineer.left_arm.rotation.x > -1.08 and engineer.arm.rotation.x < -1.08, "3d arms animate in opposed phases")
	verify(engineer.keyboard_left.position.y < engineer.keyboard_right.position.y, "3d left key visibly depresses")
	engineer.advance(0.125)
	verify(engineer.left_arm.rotation.x < -1.08 and engineer.arm.rotation.x > -1.08, "3d arm phases reverse")
	verify(engineer.keyboard_right.position.y < engineer.keyboard_left.position.y, "3d right key visibly depresses")
	verify(engineer.workbench.find_children("*", "CollisionObject3D", true, false).is_empty(), "workbench cannot alter game collisions")
	for terminal in ["saved", "paused", "cancelled", "failed", "interrupted", "done", "gone"]:
		engineer.set_work({"state":"coding"})
		tick(engineer, 0.6)
		engineer.set_work({"state":terminal})
		var count: int = engineer.left_key_presses + engineer.right_key_presses
		verify(not engineer.typing and not engineer.working and not engineer.walking, "3d " + terminal + " immediately stops")
		tick(engineer, 1.0)
		verify(count == engineer.left_key_presses + engineer.right_key_presses and not engineer.workbench.visible and not engineer.sparks.emitting, "3d " + terminal + " remains stopped")
	engineer.set_work({"state":"fixing"})
	tick(engineer, 1.0)
	verify(engineer.typing and engineer.state == "fixing", "3d fixing types without claiming saved")
	engineer.work_at(AABB(Vector3(-1,0,-1), Vector3(2,2,2)), 0.5)
	verify(engineer.walking and not engineer.workbench.visible and not engineer.typing, "real construction folds desk before world movement")
	tick(engineer, 2.0)
	verify(engineer.strokes > 0, "real construction retains hammer action")
	verify(engineer.state == "fixing" and engineer.requested_state == "fixing" and engineer.typing, "finite hammer returns to most recent real task state")
	engineer.set_work({"state":"testing"})
	tick(engineer, 1.0)
	verify(engineer.state == "testing" and not engineer.typing and not engineer.working, "3d testing observes and never auto-passes")
	var pose: Vector3 = engineer.arm.rotation
	tick(engineer, 0.2)
	verify(engineer.arm.rotation != pose and engineer.label.text == "观察试玩", "testing has an observation gesture")
	var floor_data := {"id":"raised_floor","label":"raised floor","kind":"box","position":[0,2.5,0],"size":[12,1,12],"rotation":[0,0,0],"color":"#7fc8a9","solid":true}
	await yard.apply_construction({"snapshot":{"schema":1,"dimension":"3d","revision":1,"runId":"desk-test","objects":[floor_data]},"restore":true})
	engineer.position = Vector3(0,0,0)
	yard.set_actor({"agent":"M","state":"coding"})
	verify(is_equal_approx(engineer.position.y, 3.0), "engineer and desk stand on actual raised floor cap")
	verify(yard.level.objects.raised_floor.position == Vector3(0,2.5,0), "surface positioning never moves authored geometry")
	yard.set_actor({"agent":"M","state":"saved"})
	yard._construction_step("raised_floor",floor_data)
	verify(engineer.state == "saved" and not engineer.walking, "queued reveal cannot restart a saved worker")
	yard.apply_workshop({"phase":"cancelled"})
	yard._construction_step("raised_floor",floor_data)
	verify(engineer.state == "paused" and not engineer.working, "cancelled phase cannot restart construction")
	verify(UGC.result == "" and UGC.score == 0, "all animation leaves gameplay results unchanged")
	var workshop = WORKSHOP.new()
	add_child(workshop)
	await workshop.apply_construction({"snapshot":{"schema":1,"dimension":"3d","revision":1,"runId":"focus-test","objects":[floor_data]},"restore":true})
	workshop.set_process(false)
	var overview: Transform3D = workshop.construction_yard.camera.transform
	workshop.construction_yard.set_actor({"agent":"M","state":"coding"})
	var focus_actor = workshop.construction_yard.actors.M
	tick(focus_actor,0.6)
	workshop._update_work_camera(1.0)
	verify(workshop._work_focus == 1.0 and workshop.construction_yard.camera.position.distance_to(focus_actor.position) < 14.0, "real coding gives a readable world-space close view")
	verify(workshop.construction_yard.camera.basis.is_equal_approx(overview.basis), "coding attention preserves authored viewing direction")
	workshop.construction_yard.set_actor({"agent":"M","state":"saved"})
	workshop._update_work_camera(1.0)
	verify(workshop.construction_yard.camera.transform.is_equal_approx(overview), "saved returns to full-scene camera")
	workshop.construction_yard.set_actor({"agent":"M","state":"fixing"})
	tick(focus_actor,0.6)
	workshop._update_work_camera(1.0)
	workshop.on_workshop({"phase":"cancelled"})
	workshop._update_work_camera(1.0)
	verify(workshop.construction_yard.camera.transform.is_equal_approx(overview), "cancelled work returns to full-scene camera")
	verify(workshop.construction_yard.level.objects.raised_floor.position == Vector3(0,2.5,0), "close view changes only the workshop camera")
	remove_child(workshop)
	workshop.queue_free()
	yard.camera.make_current()
	print("WORKBENCH_NATIVE_RESULT ",JSON.stringify({"checks":checks,"failed":failures}))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			# A real 3D workstation, with a full-sized 2D worker beside it for visual inspection.
			engineer.position = Vector3(-1,3,0)
			engineer.rotation.y = PI
			engineer.set_work({"state":"coding"})
			tick(engineer,1.0)
			yard.camera.position = Vector3(6,7.5,8)
			yard.camera.look_at(Vector3(0,3.8,0))
			yard.world_environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
			yard.world_environment.environment.ambient_light_energy = 0.25
			for child in yard.get_children():
				if child is DirectionalLight3D:
					child.light_energy = 0.55
			painter.position = Vector2(200,600)
			painter.set_work({"state":"coding"})
			painter.position = Vector2(200,600)
			painter.walking = false
			tick(painter,1.0)
			for frame in 3:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--capture="))
	get_tree().quit(0 if failures.is_empty() else 1)
