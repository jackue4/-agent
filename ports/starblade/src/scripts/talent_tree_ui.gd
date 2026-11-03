extends Control

signal selected(id: String)
signal unlock_requested(id: String)
const WHITE := Color("e6f0ed")
const MUTED := Color("829ba9")
var tint := Color("73eceb")
var hero_id := "chrono"
var selected_id := "vitality"
var reduced_motion := false
var entries: Array = []
var buttons: Dictionary = {}
var labels: Dictionary = {}
var unlock_button: Button
var detail_title: Label
var detail_desc: Label
var detail_cost: Label
var detail_reason: Label
var progress_label: Label
var pulse_id := ""
var pulse := 0.0
var line_progress := 0.0
var celebration_count := 0
var _animation: Tween

class TalentButton extends Button:
	var tint := Color("73eceb")
	var unlocked := false
	var available := false
	var chosen := false
	var burst := 0.0
	var mark := 0
	func _draw() -> void:
		var c := size*.5
		var lit := tint if unlocked or available else Color("47606d")
		draw_circle(c,31,Color(lit,.18 if unlocked else .045))
		draw_arc(c,31,0,TAU,48,lit,2 if unlocked else 1,true)
		if chosen or has_focus(): draw_arc(c,37,-PI*.44,PI*1.44,48,Color.WHITE,1.5,true)
		elif is_hovered(): draw_arc(c,35,0,TAU,48,Color(tint,.55),1.2,true)
		if burst > 0: draw_arc(c,37+(1-burst)*19,0,TAU,48,Color(tint,burst*.7),2,true)
		if mark == 0:
			draw_polyline(PackedVector2Array([c+Vector2(0,-15),c+Vector2(12,-9),c+Vector2(9,9),c+Vector2(0,16),c+Vector2(-9,9),c+Vector2(-12,-9),c+Vector2(0,-15)]),lit,2,true)
		elif mark == 1:
			draw_line(c+Vector2(-11,13),c+Vector2(12,-13),lit,3,true)
			draw_polyline(PackedVector2Array([c+Vector2(3,-14),c+Vector2(14,-15),c+Vector2(13,-4)]),lit,2,true)
		else:
			draw_arc(c,14,-2.7,2.7,32,lit,2,true)
			draw_line(c+Vector2(-4,-6),c+Vector2(5,0),lit,2,true)
			draw_line(c+Vector2(5,0),c+Vector2(-4,9),lit,2,true)
		if unlocked: draw_circle(c+Vector2(25,-23),4,tint)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

func _text(text: String,rect: Rect2,font_size: int,color: Color = WHITE) -> Label:
	var label := Label.new()
	label.text = text; label.position = rect.position; label.size = rect.size
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label)
	return label

func _build() -> void:
	var ids := [["vitality","mobility","survival"],["force","precision","mastery"],["efficiency","recovery","signature"]]
	for row in range(3):
		_text(["生存","战斗","技能 · F / L"][row],Rect2(3,5+row*164,480,25),12,MUTED)
		for col in range(3):
			var id: String = ids[row][col]
			var button := TalentButton.new()
			button.position = Vector2(25+col*156,38+row*164)
			button.size = Vector2(78,78)
			button.tint = tint; button.mark = row
			button.focus_mode = Control.FOCUS_ALL
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			for style in ["normal","hover","pressed","focus"]: button.add_theme_stylebox_override(style,StyleBoxEmpty.new())
			button.pressed.connect(func(): select_node(id))
			button.focus_entered.connect(func(): select_node(id))
			button.mouse_entered.connect(func(): button.queue_redraw())
			button.mouse_exited.connect(func(): button.queue_redraw())
			add_child(button)
			buttons[id] = button
			var name_label := _text("",Rect2(col*156,116+row*164,128,25),14)
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var status := _text("",Rect2(col*156,144+row*164,128,20),10,MUTED)
			status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			labels[id] = [name_label,status]
	for row in range(3):
		for col in range(3):
			var button: Button = buttons[ids[row][col]]
			button.focus_neighbor_left = button.get_path_to(buttons[ids[row][maxi(0,col-1)]])
			button.focus_neighbor_right = button.get_path_to(buttons[ids[row][mini(2,col+1)]])
			button.focus_neighbor_top = button.get_path_to(buttons[ids[maxi(0,row-1)][col]])
			button.focus_neighbor_bottom = button.get_path_to(buttons[ids[mini(2,row+1)][col]])
	progress_label = _text("",Rect2(510,12,274,26),12,tint)
	detail_title = _text("",Rect2(510,54,274,42),27)
	detail_desc = _text("",Rect2(510,120,274,132),17)
	detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	detail_cost = _text("",Rect2(510,286,274,40),26,tint)
	detail_reason = _text("",Rect2(510,341,274,60),13,MUTED)
	detail_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_reason.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	unlock_button = Button.new()
	unlock_button.position = Vector2(510,427); unlock_button.size = Vector2(274,48)
	unlock_button.add_theme_font_size_override("font_size",16)
	unlock_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for name in ["normal","hover","pressed","focus","disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = tint if name != "disabled" else Color("172b35")
		if name == "hover": style.bg_color = tint.lightened(.15)
		style.border_color = WHITE if name == "focus" else tint.darkened(.5)
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		unlock_button.add_theme_stylebox_override(name,style)
	unlock_button.add_theme_color_override("font_color",Color("08141f"))
	unlock_button.add_theme_color_override("font_disabled_color",MUTED)
	unlock_button.pressed.connect(func():
		if not unlock_button.disabled and is_visible_in_tree(): unlock_requested.emit(selected_id)
	)
	add_child(unlock_button)
	_text("永久生效 · 战败保留",Rect2(510,487,274,24),12,MUTED)
	refresh(entries)

func select_node(id: String) -> void:
	if not buttons.has(id): return
	selected_id = id
	selected.emit(id)
	refresh(entries)

func refresh(value: Array) -> void:
	entries = value
	if buttons.is_empty(): return
	var total := 0
	for entry in entries:
		var id: String = str(entry.get("id",""))
		if not buttons.has(id): continue
		var node: TalentButton = buttons[id]
		node.unlocked = bool(entry.get("unlocked",false))
		node.available = bool(entry.get("available",false))
		node.chosen = selected_id == id
		node.tint = tint
		node.queue_redraw()
		node.tooltip_text = str(entry.get("name",id))+" · "+str(entry.get("desc",""))
		labels[id][0].text = str(entry.get("name",id))
		labels[id][0].add_theme_color_override("font_color",WHITE if node.available or node.unlocked else MUTED)
		labels[id][1].text = "已点亮" if node.unlocked else (str(entry.get("price",entry.get("cost",0)))+" CR" if node.available else "前置未解锁")
		labels[id][1].add_theme_color_override("font_color",tint if node.unlocked else MUTED)
		if node.unlocked: total += 1
		if id == selected_id:
			detail_title.text = str(entry.get("name",id))
			detail_desc.text = str(entry.get("desc",""))
			detail_cost.text = "已点亮" if node.unlocked else str(entry.get("price",entry.get("cost",0)))+" CR"
			detail_reason.text = "此天赋已永久生效" if node.unlocked else ("解锁后永久强化当前英雄" if bool(entry.get("can_buy",false)) else str(entry.get("reason","暂不可解锁")))
			var parent_id: String = str(entry.get("parent",""))
			if not node.unlocked and not node.available and not parent_id.is_empty():
				for prerequisite in entries:
					if str(prerequisite.get("id","")) == parent_id:
						detail_reason.text = "先点亮「"+str(prerequisite.get("name",parent_id))+"」"
						break
			unlock_button.text = "已解锁" if node.unlocked else "点亮天赋"
			unlock_button.disabled = not bool(entry.get("can_buy",false)) or node.unlocked
	progress_label.text = "%d / 9  已点亮" % total
	queue_redraw()

func celebrate(id: String) -> void:
	if not buttons.has(id) or not buttons[id].unlocked: return
	celebration_count += 1
	pulse_id = id; pulse = 1; line_progress = 0
	if _animation != null and _animation.is_valid(): _animation.kill()
	_animation = create_tween().set_parallel(true)
	_animation.tween_property(self,"line_progress",1.0,.18 if reduced_motion else .38).set_trans(Tween.TRANS_CUBIC)
	_animation.tween_property(self,"pulse",0.0,.3 if reduced_motion else .7).set_delay(.1)

func _process(_delta: float) -> void:
	if pulse > 0:
		if buttons.has(pulse_id):
			buttons[pulse_id].burst = 0 if reduced_motion else pulse
			buttons[pulse_id].queue_redraw()
		queue_redraw()
	elif not pulse_id.is_empty():
		if buttons.has(pulse_id): buttons[pulse_id].burst = 0; buttons[pulse_id].queue_redraw()
		pulse_id = ""; queue_redraw()

func _draw() -> void:
	draw_line(Vector2(483,10),Vector2(483,520),Color("29414e"),1,true)
	for entry in entries:
		var id: String = str(entry.get("id",""))
		var parent: String = str(entry.get("parent",""))
		if parent.is_empty() or not buttons.has(parent) or not buttons.has(id): continue
		var from: Vector2 = buttons[parent].position+Vector2(78,39)
		var to: Vector2 = buttons[id].position+Vector2(0,39)
		draw_line(from,to,Color("29414e"),2,true)
		if bool(entry.get("unlocked",false)):
			var fill := line_progress if id == pulse_id else 1.0
			draw_line(from,from.lerp(to,fill),tint,2.2,true)
			if id == pulse_id and not reduced_motion: draw_circle(from.lerp(to,fill),3,Color.WHITE)
