extends "res://workshop_root.gd"
var checks := 0
var failures: Array = []
var focused: Array = []

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func design() -> Dictionary:
	return {"title":"纸牌与筹码", "modules":[
		{"file":"scripts/deck.gd","role":"抽牌模块","owner":"gameplay","interface":"牌库与手牌的输入输出","kind":"deck"},
		{"file":"scripts/score.gd","role":"倍率模块","owner":"gameplay","interface":"牌型与倍率结算","kind":"score"},
		{"file":"scripts/shop.gd","role":"商店模块","owner":"scene","interface":"商品陈列与购买","kind":"shop"},
		{"file":"scripts/rules.gd","role":"牌型模块","owner":"gameplay","interface":"识别选中牌的组合","kind":"rules"}]}

func facts(state: String) -> Array:
	var rows: Array = []
	for row in design().modules:
		rows.append({"id":row.file,"file":row.file,"label":row.role,"kind":row.kind,"state":state,"detail":"真实文件已保存，规则仍待检查" if state == "saved" else "本轮源码已完成整体验收" if state == "verified" else "正在制作这一项模块", "sourceRevision":"revision-a", "evidenceRefs":["test-a"] if state == "verified" else []})
	return rows

func click(point: Vector2) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		get_viewport().push_input(event, true)

func tick_worker(actor: Node, seconds: float) -> void:
	actor.set_process(false)
	for i in ceili(seconds * 60):
		actor.advance(1.0/60.0)

func _ready() -> void:
	use_module_workshop = true
	super._ready()
	_run.call_deferred()

func _run() -> void:
	UGC.show_crew = true
	verify(not is_instance_valid(module_workshop),"missing design invents no modules")
	# Actual refresh wire order: clear, establish plan/phase, then restore real workers.
	UGC.clear_crew()
	UGC.workshop({"plan":design(),"phase":"build","restore":true})
	UGC.crew({"agent":"M","state":"building"})
	UGC.crew({"agent":"task:score","state":"coding","file":"scripts/score.gd"})
	verify(module_workshop.actors.size() == 2 and UGC._crew.is_empty(),"cold wire restore keeps both workers inside actual module world")
	verify(module_workshop.actors["task:score"].state == "coding","restored phase is applied before active crew")
	UGC.clear_crew()
	verify(is_instance_valid(module_workshop) and uses_world_crew(),"actual modules create Node2D workshop and actor route")
	var yard = module_workshop
	yard.set_process(false)
	yard.module_focused.connect(func(event):focused.append(event))
	verify(yard.modules.size() == 4 and yard.order.size() == 4,"only four supplied modules exist")
	verify(yard.modules.values().all(func(row):return row.state == "planned"),"accepted design is planning not implementation")
	verify(yard.modules["scripts/deck.gd"].interface == "牌库与手牌的输入输出","actual module interface is preserved")
	verify(yard.modules.values().map(func(row):return row.kind) == ["deck","score","shop","rules"],"module kinds change appearance only")
	verify(UGC._crew.is_empty(),"old overlay engineers removed before module route")
	await get_tree().process_frame
	for viewport in [Vector2(1280,720),Vector2(640,360)]:
		yard.layout(viewport)
		verify(yard.station_rects.size() == 4,"four desks remain available at " + str(viewport))
		var rects: Array = yard.station_rects.values()
		verify(rects.all(func(rect):return Rect2(Vector2.ZERO,viewport).encloses(rect)),"desks fit viewport " + str(viewport))
		verify(rects.all(func(rect):return rect.size.x >= 270 and rect.size.y >= 88),"desks retain readable minimum size " + str(viewport))
		verify(not rects[0].intersects(rects[1]) and not rects[0].intersects(rects[2]),"desks do not overlap " + str(viewport))
		verify(rects.all(func(rect):return rect.end.y < yard._detail_rect.position.y),"desks do not cover bottom action strip " + str(viewport))
		click(yard.station_rects["scripts/deck.gd"].get_center())
		verify(yard.selected_file == "scripts/deck.gd" and focused.back().file == "scripts/deck.gd","physical click emits actual file " + str(viewport))
	verify(focused.size() == 2 and focused.back().label == "抽牌模块","focus event uses actual module label")
	yard.focus_module("missing.gd")
	verify(focused.size() == 2,"unknown module cannot emit focus")
	var saved := facts("saved")
	on_workshop({"phase":"build","modules":saved})
	verify(yard.modules.values().all(func(row):return row.state == "saved"),"saved facts never become verified")
	var transitions: int = yard.transition_count
	on_workshop({"phase":"build","modules":saved,"restore":true})
	verify(yard.transition_count == transitions,"restoring identical snapshot does not replay transitions")
	UGC.crew({"agent":"M","state":"coding","file":"scripts/deck.gd","module":"抽牌模块"})
	verify(yard.actors.has("M") and UGC._crew.is_empty(),"existing engineer script is routed into module world")
	var actor = yard.actors.M
	tick_worker(actor, 5)
	verify(not actor.walking and actor.position.is_equal_approx(actor.destination),"engineer actually arrives at its module")
	verify(actor.typing and actor.left_key_presses > 0 and actor.right_key_presses > 0,"engineer types with both hands for real coding")
	verify(actor.external_station,"old generic station is disabled")
	UGC.crew({"agent":"task:shop","state":"testing","file":"scripts/shop.gd","module":"商店模块"})
	verify(yard.actors.size() == 2 and yard.actors["task:shop"].destination != actor.destination,"real parallel worker has separate module station")
	on_workshop({"phase":"build","modules":facts("writing")})
	on_workshop({"phase":"paused"})
	verify(yard.display_state(yard.modules["scripts/deck.gd"]) == "paused","global pause displays stopped work even before module refresh")
	on_workshop({"phase":"paused","modules":facts("paused")})
	var taps: int = actor.completed_strokes
	tick_worker(actor, 1)
	verify(not actor.typing and not actor.walking and actor.completed_strokes == taps,"paused immediately stops walking and typing")
	UGC.crew({"agent":"M","state":"coding","file":"scripts/deck.gd"})
	verify(actor.state == "paused","late active crew cannot restart paused workshop")
	UGC.workshop({"phase":"build"})
	UGC.crew({"agent":"M","state":"coding","file":"scripts/deck.gd"})
	tick_worker(actor, 5)
	verify(actor.state == "coding" and actor.typing,"wire resume phase before crew restarts actual typing")
	on_workshop({"phase":"verify","modules":facts("checking")})
	verify(yard.modules["scripts/deck.gd"].state == "checking","checking does not imply passed")
	on_workshop({"phase":"review","modules":facts("verified")})
	verify(yard.LABELS.verified == "本轮验收通过" and yard.modules["scripts/deck.gd"].sourceRevision == "revision-a","verified label remains whole-round evidence with revision")
	verify(yard.modules["scripts/deck.gd"].evidenceRefs == ["test-a"],"verification references preserved")
	var more := design()
	more.modules.append({"file":"world.gd","role":"地图模块","owner":"scene","kind":"world"})
	more.modules.append({"file":"audio.gd","role":"音效模块","owner":"scene"})
	set_plan(more)
	yard.layout(Vector2(640,360))
	yard.change_page(1)
	verify(yard.station_rects.size() == 2 and yard.page == 1,"extra modules paginate without shrinking desks")
	verify(actor.visible and not yard.actors["task:shop"].visible,"only main worker stays visible when its module belongs to another page")
	UGC.workshop({"phase":"build"})
	UGC.crew({"agent":"M","state":"coding","file":"scripts/deck.gd","module":"抽牌模块"})
	for viewport in [Vector2(1280,720),Vector2(640,360)]:
		yard.layout(viewport)
		tick_worker(actor, 8)
		verify(actor.visible and Rect2(Vector2.ZERO,viewport).has_point(actor.position) and actor.position.is_equal_approx(Vector2(48,viewport.y - 92)),"off-page main actually arrives at visible entrance " + str(viewport))
		verify(actor.typing and actor.left_key_presses > 0 and actor.right_key_presses > 0 and yard.page == 1,"off-page worker keeps real coding without taking over pagination " + str(viewport))
	verify(yard.main_work_label().contains("抽牌模块") and yard.main_work_label().contains("另一页") and actor.bubble.contains("另一页"),"entrance identifies real module and another page")
	verify(actor.file == "scripts/deck.gd" and yard._actor_data.M.file == "scripts/deck.gd","entrance never changes underlying task file")
	yard.change_page(-1)
	tick_worker(actor, 8)
	verify(actor.visible and actor.destination.x > 100 and yard.main_work_label().is_empty() and not actor.bubble.contains("另一页"),"returning to module page restores its real desk and removes elsewhere label")
	yard.change_page(1)
	UGC.workshop({"phase":"paused"})
	var stopped_taps: int = actor.completed_strokes
	tick_worker(actor, 1)
	verify(actor.visible and not actor.typing and actor.completed_strokes == stopped_taps and yard.main_work_label().contains("暂停"),"paused main remains visible without false work")
	UGC.crew({"agent":"M","state":"saved","file":"scripts/deck.gd"})
	tick_worker(actor, 1)
	verify(actor.visible and not actor.walking and not actor.typing and actor.completed_strokes == stopped_taps and yard.main_work_label().contains("已保存"),"saved main remains at entrance with tools stopped")
	verify(yard.modules["audio.gd"].kind == "generic" and yard.modules["audio.gd"].state == "planned","unclassified new module remains generic planning")
	verify(UGC.result == "" and UGC.score == 0,"workshop never fabricates gameplay outcomes")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			await capture_workshop(arg.trim_prefix("--capture="))
	set_dimension("3d")
	verify(not is_instance_valid(module_workshop) and is_instance_valid(construction_yard),"3d retains original yard without module desk overlap")
	print("MODULE_WORKSHOP_RESULT ",JSON.stringify({"checks":checks,"failed":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func capture_workshop(prefix: String) -> void:
	set_plan(design())
	var rows := facts("planned")
	rows[0].state = "writing"
	rows[1].state = "saved"
	rows[2].state = "checking"
	on_workshop({"phase":"build","modules":rows})
	module_workshop.change_page(-1)
	UGC.crew({"agent":"M","state":"coding","file":"scripts/deck.gd","module":"抽牌模块"})
	UGC.crew({"agent":"task:shop","state":"testing","file":"scripts/shop.gd","module":"商店模块"})
	for resolution in [Vector2i(1280,720),Vector2i(640,360)]:
		get_tree().root.size = resolution
		get_tree().root.content_scale_size = resolution
		module_workshop.layout(Vector2(resolution))
		module_workshop.focus_module("scripts/deck.gd")
		for actor in module_workshop.actors.values():
			tick_worker(actor, 8)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(prefix + "-" + str(resolution.x) + ".png")
