extends Node2D

var assertions := 0
var failures: Array[String] = []
var received_plan: Dictionary = {}
var saved_files: Array[String] = []
var received_workshop := 0
var health := 77

func expect(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
		push_error(label)

func set_plan(value: Dictionary) -> void:
	received_plan = value

func mark_saved(_agent: String, file: String) -> void:
	saved_files.append(file)

func on_workshop(_data: Dictionary) -> void:
	received_workshop += 1

func main_scale_ok() -> bool:
	var fairy = UGC._assembly._fairy
	var size := get_viewport().get_visible_rect().size
	return is_equal_approx(fairy.scale.x, clampf(minf(size.x, size.y) / 420.0, 1.0, 2.4))

func tick_actor(actor: Node, count: int) -> void:
	actor.set_process(false)
	for i in count:
		if is_instance_valid(actor) and not actor.is_queued_for_deletion():
			actor.advance(0.1)

func _ready() -> void:
	await get_tree().process_frame
	var baseline := transform
	UGC.crew({"agent":"hidden", "state":"building"})
	expect(UGC._crew.is_empty() and not is_instance_valid(UGC._crew_canvas), "play mode creates no crew canvas or actors")
	UGC.show_crew = true
	UGC.crew({"agent":"M", "name":"主制作", "state":"paused"})
	var main = UGC._crew.M
	expect(main is Node2D and not main is Control, "fairy is a Node2D actor, not a panel")
	expect(main.is_in_group("ugc_crew_actor") and main.has_method("assist"), "crew messages create the build fairy")
	expect(not main.walking, "paused fairy does not fly")
	expect(not main.is_processing_input() and not main.is_processing_unhandled_input(), "actor receives no gameplay input")
	UGC.crew({"agent":"M", "state":"coding", "file":"main.gd"})
	var start: Vector2 = main.position
	tick_actor(main, 6)
	expect(main.position.distance_to(start) > 20, "work event makes the fairy fly over the screen")
	expect(not main.particles.is_empty(), "flight leaves a sparkle trail")
	var canvas_before: Vector2 = main.get_global_transform_with_canvas().origin
	var camera := Camera2D.new()
	add_child(camera)
	camera.position = Vector2(500, 300)
	camera.zoom = Vector2(2,2)
	camera.make_current()
	camera.force_update_scroll()
	await get_tree().process_frame
	expect(main.get_global_transform_with_canvas().origin.is_equal_approx(canvas_before), "Camera2D cannot displace viewport creation actors")
	camera.queue_free()
	UGC.crew({"agent":"M", "state":"paused", "file":"main.gd"})
	var paused_position: Vector2 = main.position
	tick_actor(main, 30)
	expect(main.position == paused_position and main.particles.is_empty(), "pause stops flight and all effects")
	UGC.crew({"agent":"M", "state":"coding", "code":"PRIVATE_SOURCE_DO_NOT_DISPLAY", "text":"PRIVATE_REASONING_DO_NOT_DISPLAY"})
	tick_actor(main, 15)
	expect(main.bubble.length() <= 16 and not main.bubble.contains("PRIVATE"), "code and internal text are not rendered")
	UGC.crew({"agent":"M", "state":"saved", "file":"main.gd"})
	expect(saved_files.is_empty(), "ordinary game root with matching method is never mutated")
	set_meta("creation_yard", true)
	UGC.workshop({"phase":"build", "plan":{"title":"test yard"}, "actors":[{"agent":"M", "state":"testing"}], "savedFiles":["scene.gd"]})
	expect(received_plan.get("title") == "test yard" and received_workshop == 1, "marked creation yard receives plan and workshop hooks")
	UGC.crew({"agent":"M", "state":"saved", "file":"main.gd"})
	expect(saved_files == ["main.gd"], "saved hook represents exactly the real file event")
	UGC.crew({"agent":"task:scene", "taskId":"scene", "name":"场景工人", "state":"fixing", "file":"scene.gd"})
	var worker = UGC._crew["task:scene"]
	UGC.workshop({"actors":[{"agent":"M","state":"paused"}]})
	expect(worker.leaving, "actors absent from a restored snapshot leave")
	tick_actor(worker, 120)
	await get_tree().process_frame
	expect(not UGC._crew.has("task:scene"), "departed task actor is removed from registry")
	UGC.crew({"agent":"M", "state":"done"})
	tick_actor(main, 120)
	await get_tree().process_frame
	expect(UGC._crew.is_empty(), "completed fairy flies away")
	remove_meta("creation_yard")
	# Assembly: the real screen is scanned, new pieces are veiled and revealed, nothing is mutated.
	var hud := Control.new()
	hud.name = "Hud"
	add_child(hud)
	var panel := Panel.new()
	panel.name = "Panel"
	panel.position = Vector2(40, 40)
	panel.size = Vector2(300, 120)
	hud.add_child(panel)
	var label := Label.new()
	label.name = "Score"
	label.text = "分数 0"
	label.position = Vector2(60, 60)
	label.size = Vector2(120, 30)
	hud.add_child(label)
	var unnamed := Label.new()
	unnamed.text = "生命 3"
	unnamed.position = Vector2(60, 100)
	unnamed.size = Vector2(120, 30)
	hud.add_child(unnamed)
	await get_tree().process_frame
	var first: Dictionary = UGC.assemble({}, true)
	expect(first.has("Hud/Panel:Panel") and first.has("Hud/Score:Label") and first.has(".:Node2D"), "baseline lists the visible scene and UI pieces")
	expect(str(unnamed.name).contains("@") and first.has("Hud/Label#0:Label"), "code-built nodes with generated names get a stable structural key")
	var pass_node = UGC._assembly
	var bands: int = pass_node.pieces.filter(func(row): return str(row.label).begins_with("场景")).size() if is_instance_valid(pass_node) else 0
	expect(bands >= 3 and pass_node.pieces.size() == bands + 3 and str(pass_node.pieces[0].label).begins_with("场景 1/"), "first build paints the drawn scene in bands, then assembles each node")
	expect(pass_node.pieces.any(func(row): return row.label == "文字「分数 0」"), "pieces carry human labels")
	var panel_before := panel.position
	for i in 200:
		if not is_instance_valid(pass_node) or pass_node._done:
			break
		pass_node._process(0.1)
		pass_node._fairy.advance(0.1)
	expect(is_instance_valid(pass_node) and pass_node._done and pass_node.revealed == pass_node.pieces.size(), "assembly reveals each piece and finishes")
	expect(panel.position == panel_before and panel.visible and label.text == "分数 0", "assembly never mutates game nodes")
	expect(main_scale_ok(), "fairy scales with the viewport")
	var button := Button.new()
	button.name = "Start"
	button.text = "开始"
	button.position = Vector2(400, 300)
	button.size = Vector2(120, 40)
	hud.add_child(button)
	await get_tree().process_frame
	UGC.assemble(first, true)
	expect(UGC._assembly.pieces.size() == 1 and UGC._assembly.pieces[0].key == "Hud/Start:Button", "a later build only assembles what is new")
	var quiet: Dictionary = UGC.assemble(UGC.assemble(first, false), false)
	expect(quiet.has("Hud/Start:Button"), "baseline-only pass updates without animating")
	hud.queue_free()
	UGC.crew({"agent":"M", "state":"building"})
	UGC.show_crew = false
	expect(UGC._crew.is_empty() and not is_instance_valid(UGC._crew_canvas) and UGC._assembly == null, "disabling creation mode clears actors and assembly immediately")
	await get_tree().process_frame
	expect(get_tree().get_nodes_in_group("ugc_crew_actor").is_empty(), "play mode leaves no crew nodes in the tree")
	expect(transform == baseline and health == 77 and UGC.score == 0 and UGC.result == "", "crew does not modify game transforms or gameplay state")
	UGC.show_crew = true
	for i in 3:
		var status: String = ["coding","building","testing"][i]
		UGC.crew({"agent":"shot"+str(i),"name":["逻辑","场景","试玩"][i],"state":status})
		tick_actor(UGC._crew["shot"+str(i)], 12)
	queue_redraw()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture=") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture="))
	print("CREW_NATIVE_RESULT ", JSON.stringify({"checks":assertions,"failed":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _draw() -> void:
	draw_rect(Rect2(-1000,-1000,3000,2400), Color("#172e3c"))
	for x in range(-1000, 2000, 40):
		draw_line(Vector2(x,-1000), Vector2(x,1400), Color(0.2,0.4,0.48,0.18))
	for y in range(-1000,1400,40):
		draw_line(Vector2(-1000,y), Vector2(2000,y), Color(0.2,0.4,0.48,0.18))
