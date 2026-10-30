extends "res://workshop_root.gd"
const WORKER_2D = preload("res://addons/ugc/crew_actor.gd")
var checks := 0
var failures: Array = []
var editor_events: Array = []
var animated_result: Dictionary = {}

func verify(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func scene_data(revision: int) -> Dictionary:
	return {"schema":1,"dimension":"3d","revision":revision,"runId":"editor-fixture","step":"真实测试关卡",
		"objects":[
			{"id":"floor","label":"地台","kind":"box","position":[0,-0.5,0],"size":[16,1,12],"rotation":[0,0,0],"color":"#7fc8a9","solid":true},
			{"id":"block","label":"测试方块","kind":"box","position":[0,1,0],"size":[2,2,2],"rotation":[0,20,0],"color":"#e9be70","solid":true},
			{"id":"sphere","label":"球形装饰","kind":"sphere","position":[-4,1,0],"size":[2,2,2],"rotation":[0,0,0],"color":"#a993db","solid":false}],
		"camera":{"position":[16,13,18],"lookAt":[0,0,0]},"environment":{"background":"#172334","ambient":"#b9d1dc"}}

func mouse_button(button: MouseButton, down: bool, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = down
	event.position = point
	event.global_position = point
	get_viewport().push_input(event,true)

func mouse_move(point: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.relative = relative
	get_viewport().push_input(event,true)

func key(code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		get_viewport().push_input(event,true)

func move_count() -> int:
	return editor_events.filter(func(event):return event.type == "editor_move").size()

func last_move() -> Dictionary:
	var events := editor_events.filter(func(event):return event.type == "editor_move")
	return events.back() if not events.is_empty() else {}

func point(id: String) -> Vector2:
	return construction_yard.camera.unproject_position(construction_yard.level.objects[id].global_position)

func begin_object_drag() -> Vector2:
	var screen := point("block")
	mouse_button(MOUSE_BUTTON_LEFT,true,screen)
	var target: Vector2 = construction_yard.camera.unproject_position(construction_yard.level.objects.block.global_position + Vector3.RIGHT)
	mouse_move(target,target-screen)
	return target

func _ready() -> void:
	super._ready()
	_run.call_deferred()

func apply_animated(value: Dictionary) -> void:
	animated_result = await apply_construction({"snapshot":value,"restore":false})

func _run() -> void:
	UGC.show_crew = true
	var original := scene_data(1)
	await apply_construction({"snapshot":original,"restore":true})
	set_process(false)
	construction_editor.event_emitted.connect(func(event):editor_events.append(event.duplicate(true)))
	await get_tree().process_frame
	verify(not construction_editor.can_move(),"movement disabled until explicit safe-idle control")
	handle_editor({"enabled":true})
	verify(construction_editor.can_move(),"explicit idle edit enables movement")
	var screen := point("block")
	verify(construction_editor.pick_at(screen) == "block","ray hits actual rotated primitive")
	mouse_button(MOUSE_BUTTON_LEFT,true,screen)
	mouse_button(MOUSE_BUTTON_LEFT,false,screen)
	verify(construction_editor.selected_id == "block","real mouse input selects actual object")
	verify(construction_editor._outline.visible,"selection outline is visible")
	verify(move_count() == 0,"click without drag never submits move")
	verify(editor_events.back().position == [0.0,1.0,0.0] and editor_events.back().revision == 1,"selection reports canonical position and revision")
	var destination := begin_object_drag()
	verify(construction_editor.dragging,"real input begins drag")
	verify(construction_yard.level.objects.block.position.distance_to(Vector3(1,1,0)) < 0.03,"drag previews on XZ plane")
	verify(move_count() == 0,"mouse motion sends no save request")
	verify(construction_yard.level.snapshot.objects[1].position == [0,1,0],"preview never mutates snapshot")
	verify(construction_yard.level.objects.block.get_meta("construction_data").position == [0,1,0],"preview never mutates canonical object metadata")
	mouse_button(MOUSE_BUTTON_LEFT,false,destination)
	verify(move_count() == 1 and construction_editor.pending,"release emits exactly one pending request")
	verify(last_move().id == "block" and last_move().baseRevision == 1 and not last_move().requestId.is_empty(),"move binds stable object ID, revision and request ID")
	handle_editor({"action":"nudge","delta":[1,0,0]})
	verify(move_count() == 1,"pending request blocks a second movement")
	await apply_construction({"snapshot":original,"restore":true})
	verify(not construction_editor.pending and construction_yard.level.objects.block.position == Vector3(0,1,0),"same-revision failure restore actually reverts preview")
	verify(construction_editor.can_move(),"canonical response releases pending lock")
	handle_editor({"action":"nudge","id":"block","delta":[0,0.25,0]})
	verify(move_count() == 2 and last_move().position == [0.0,1.25,0.0],"frontend XYZ nudge submits requested movement")
	var accepted := scene_data(2)
	accepted.objects[1].position = [0,1.25,0]
	await apply_construction({"snapshot":accepted,"restore":true})
	verify(construction_editor.revision == 2 and not construction_editor.pending,"accepted canonical revision confirms the edit")
	verify(construction_yard.level.objects.block.position == Vector3(0,1.25,0),"confirmed transform comes from canonical snapshot")
	var before_moves := move_count()
	destination = begin_object_drag()
	key(KEY_ESCAPE)
	verify(not construction_editor.dragging and construction_yard.level.objects.block.position == Vector3(0,1.25,0),"Esc cancels unsubmitted drag")
	mouse_button(MOUSE_BUTTON_LEFT,false,destination)
	verify(move_count() == before_moves,"release after Escape cannot save cancelled drag")
	destination = begin_object_drag()
	var newer := scene_data(3)
	newer.objects[1].position = [3,1,0]
	await apply_construction({"snapshot":newer,"restore":true})
	mouse_button(MOUSE_BUTTON_LEFT,false,destination)
	verify(not construction_editor.dragging and construction_yard.level.objects.block.position == Vector3(3,1,0),"new revision cancels and replaces old drag")
	verify(move_count() == before_moves,"new revision prevents stale release submission")
	destination = begin_object_drag()
	construction_editor._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	verify(not construction_editor.dragging and construction_yard.level.objects.block.position == Vector3(3,1,0),"focus loss cancels transient drag")
	on_crew({"agent":"M","state":"coding","module":"移动模块","file":"movement.gd","step":"处理输入"})
	verify(construction_editor.busy and not construction_editor.can_move(),"real active work blocks object edits")
	handle_editor({"enabled":true,"action":"nudge","delta":[1,0,0]})
	verify(move_count() == before_moves,"enabled flag cannot bypass local busy guard")
	var camera_before: Transform3D = construction_yard.camera.transform
	mouse_button(MOUSE_BUTTON_RIGHT,true,Vector2(600,350))
	mouse_move(Vector2(650,370),Vector2(50,20))
	mouse_button(MOUSE_BUTTON_RIGHT,false,Vector2(650,370))
	verify(construction_editor.camera_owned and not construction_yard.camera.transform.is_equal_approx(camera_before),"right drag orbits while AI is working")
	var manual: Transform3D = construction_yard.camera.transform
	_update_work_camera(1.0)
	verify(construction_yard.camera.transform.is_equal_approx(manual),"manual camera takes priority over AI close view")
	mouse_button(MOUSE_BUTTON_WHEEL_UP,true,Vector2(600,350))
	verify(construction_yard.camera.position.distance_to(manual.origin) > 0.01,"scroll wheel really zooms")
	manual = construction_yard.camera.transform
	mouse_button(MOUSE_BUTTON_MIDDLE,true,Vector2(600,350))
	mouse_move(Vector2(630,370),Vector2(30,20))
	mouse_button(MOUSE_BUTTON_MIDDLE,false,Vector2(630,370))
	verify(construction_yard.camera.position.distance_to(manual.origin) > 0.01,"middle drag really pans")
	handle_editor({"enabled":false,"action":"frame"})
	verify(not construction_editor.camera_owned and construction_yard.camera.transform.is_equal_approx(_overview_camera),"frame works when editing disabled and releases manual view")
	var actor = construction_yard.actors.M
	verify(actor.module_name == "移动模块" and actor.label.text == "移动模块·编写","3d head label uses actual supplied module")
	var changes: int = actor.module_changes
	var blocks: Array = actor._screen_blocks.map(func(block):return block.scale.x)
	on_crew({"agent":"M","state":"fixing","module":"计分模块","file":"score.gd","step":"修正分数"})
	verify(actor.module_changes == changes + 1 and actor.module_flash > 0,"real module switch triggers short feedback")
	verify(actor.label.text == "计分模块·修正" and actor._screen_blocks.map(func(block):return block.scale.x) != blocks,"workbench screen changes with actual module")
	on_crew({"agent":"M","state":"saved"})
	verify(actor.label.text == "计分模块·已保存" and not actor.typing,"real saved event retains module and stops work")
	on_crew({"agent":"M","state":"paused"})
	handle_editor({"enabled":true,"action":"select","id":"block"})
	key(KEY_PAGEUP)
	verify(last_move().position == [3.0,1.25,0.0],"named keyboard action provides Y-axis adjustment")
	await apply_construction({"snapshot":newer,"restore":true})
	var no_block := scene_data(4)
	no_block.objects.remove_at(1)
	await apply_construction({"snapshot":no_block,"restore":true})
	verify(construction_editor.selected_id.is_empty() and not construction_editor._outline.visible,"canonical removal clears stale selection safely")
	construction_editor.orbit(Vector2(12,0))
	var before_animation: Transform3D = construction_yard.camera.transform
	var animated := scene_data(5)
	apply_animated.call_deferred(animated)
	await get_tree().create_timer(0.05).timeout
	verify(construction_editor.applying and construction_yard.camera.transform.is_equal_approx(before_animation),"incoming construction preserves manual camera during animation")
	construction_editor.orbit(Vector2(30,0))
	var during_animation: Transform3D = construction_yard.camera.transform
	await get_tree().create_timer(1.5).timeout
	verify(bool(animated_result.get("loaded",false)),"animated snapshot completed")
	verify(construction_yard.camera.transform.is_equal_approx(during_animation),"snapshot completion preserves latest user camera input")
	on_crew({"agent":"M","state":"coding"})
	clear_world_crew()
	verify(not construction_editor.busy,"clearing actual workers releases local busy state")
	var artist = WORKER_2D.new()
	add_child(artist)
	artist.setup("writer",{"state":"coding","module":"移动模块","file":"movement.gd"},Vector2(1280,720))
	artist.set_process(false)
	artist.position = artist.destination
	artist.walking = false
	for i in 60:
		artist.advance(1.0/60.0)
	verify(artist.bubble == "移动模块·编写" and artist.typing,"2d actual module label accompanies typing")
	artist.set_work({"state":"saved"})
	verify(artist.bubble == "移动模块·已保存" and not artist.typing,"2d saved label is event driven")
	artist.set_work({"state":"coding","file":"scripts/player.gd"})
	verify(artist.module_name == "player","missing module falls back to supplied filename only")
	artist.set_work({"module":"func secret { PRIVATE"})
	verify(not artist.bubble.contains("PRIVATE"),"invalid source-like module text is never rendered")
	verify(UGC.result == "" and UGC.score == 0,"editing and module feedback never invent gameplay outcomes")
	print("CONSTRUCTION_EDITOR_RESULT ",JSON.stringify({"checks":checks,"failed":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
