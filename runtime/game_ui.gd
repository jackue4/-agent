extends CanvasLayer
## In-game UI: HUD (lives / collectibles / score / timer / level progress), start card,
## pause card, result card with star rating, and toasts. Pure presentation: game rules live in
## main.gd, which feeds this layer through the small public API below.
const Icon = preload("res://hud_icon.gd")
const TouchControls = preload("res://touch_controls.gd")

signal start_requested
signal restart_requested
signal resume_requested
signal pause_requested

const BRAND := Color("#8b5cf6")
const CARD_BG := Color(0.08, 0.05, 0.17, 0.94)
const PILL_BG := Color(0.07, 0.04, 0.15, 0.62)
const GOLD := Color("#ffd23f")
const MAX_HEART_ICONS := 5

var hud_root: Control
var hearts_box: HBoxContainer
var hearts_lbl: Label
var collect_pill: PanelContainer
var collect_icon: Control
var collect_lbl: Label
var score_lbl: Label
var timer_pill: PanelContainer
var timer_lbl: Label
var title_lbl: Label
var hint_lbl: Label
var hint_pill: PanelContainer
var progress: Control
var progress_value := -1.0
var dim: ColorRect
var card: PanelContainer
var card_box: VBoxContainer
var toast_panel: PanelContainer
var toast_lbl: Label
var _toast_tw: Tween
var _fading_hint := false
var _last_lives := -1
var _last_score := -1
var _last_collected := -1
var touch: Control
var pause_btn: Button
var _minimal := false

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hud()
	_build_touch()
	_build_overlay()
	_build_toast()

# ------------------------------------------------------------------ public API

func show_hud(v: bool) -> void:
	hud_root.visible = v
	if not v and touch:
		touch.release_all()

## Touch UI is enabled on touchscreen devices (mobile web) or with the --touch flag.
static func wants_touch() -> bool:
	return DisplayServer.is_touchscreen_available() or "--touch" in OS.get_cmdline_user_args()

## mode "none" (AI code games handle their own pointer input): no stick, no buttons.
func configure_touch(mode: String, can_shoot: bool) -> void:
	if touch:
		touch.visible = mode != "none"
		if mode != "none":
			touch.configure(mode, can_shoot)

## Code games draw their own HUD; the platform keeps only the hint and the pause button.
func set_minimal_hud(v: bool) -> void:
	for n in [hearts_box.get_parent(), collect_pill, score_lbl.get_parent().get_parent(), timer_pill, title_lbl]:
		(n as CanvasItem).visible = not v
	if v:
		progress.visible = false
	_minimal = v

func set_title(t: String) -> void:
	title_lbl.text = t

## Objective hint, bottom-centre. Shown at the start of a run and faded after a few seconds.
func set_hint(t: String, v: bool) -> void:
	hint_lbl.text = t
	hint_pill.visible = v and t != ""
	hint_pill.modulate.a = 1.0
	_fading_hint = false
	if hint_pill.visible:
		hint_pill.reset_size()
		var vs := get_viewport().get_visible_rect().size
		hint_pill.position = Vector2((vs.x - hint_pill.size.x) * 0.5, vs.y - hint_pill.size.y - 26)

func fade_hint() -> void:
	if hint_pill.visible and not _fading_hint:
		_fading_hint = true
		var tw := create_tween()
		tw.tween_property(hint_pill, "modulate:a", 0.0, 0.8)
		tw.tween_callback(func(): hint_pill.visible = false)

## stats: lives, collected, total_collect, defeated, total_enemies, score, time (seconds left or
## elapsed), timer_mode ("none"|"down"|"up"), objective ("goal"|"collect_all"|"defeat_all"|"score"|"survive"), target_score
func update_stats(s: Dictionary) -> void:
	if _minimal:
		return
	var lives := int(s.get("lives", 0))
	_set_hearts(lives)
	if _last_lives >= 0 and lives < _last_lives:
		_shake_ctl(hearts_box.get_parent())
	_last_lives = lives
	var obj := str(s.get("objective", "goal"))
	var total_c := int(s.get("total_collect", 0))
	var total_e := int(s.get("total_enemies", 0))
	var collected := int(s.get("collected", 0))
	if obj == "defeat_all" and total_e > 0:
		collect_pill.visible = true
		(collect_icon as Icon).kind = "skull"
		collect_lbl.text = "%d/%d" % [int(s.get("defeated", 0)), total_e]
	elif total_c > 0:
		collect_pill.visible = true
		(collect_icon as Icon).kind = "coin"
		collect_lbl.text = "%d/%d" % [collected, total_c]
		if collected != _last_collected and _last_collected >= 0:
			_pop_ctl(collect_pill)
	else:
		collect_pill.visible = false
	collect_icon.queue_redraw()
	_last_collected = collected
	var score := int(s.get("score", 0))
	score_lbl.text = str(score) if obj != "score" else "%d / %d" % [score, int(s.get("target_score", 0))]
	if score != _last_score and _last_score >= 0:
		_pop_ctl(score_lbl.get_parent())
	_last_score = score
	var tm := str(s.get("timer_mode", "none"))
	timer_pill.visible = tm != "none"
	if tm != "none":
		var secs := maxf(float(s.get("time", 0.0)), 0.0)
		timer_lbl.text = fmt_time(secs)
		var urgent := tm == "down" and secs <= 10.0
		timer_lbl.add_theme_color_override("font_color", Color("#ff6b6b") if urgent else Color.WHITE)

func set_progress(v: float) -> void:
	progress_value = v
	progress.visible = v >= 0.0
	progress.queue_redraw()

func toast(text: String, col := Color.WHITE, dur := 1.4) -> void:
	toast_lbl.text = text
	toast_lbl.add_theme_color_override("font_color", col)
	toast_panel.visible = true
	toast_panel.reset_size()
	var vs := get_viewport().get_visible_rect().size
	toast_panel.position = Vector2((vs.x - toast_panel.size.x) * 0.5, vs.y * 0.2)
	toast_panel.pivot_offset = toast_panel.size * 0.5
	if _toast_tw and _toast_tw.is_valid():
		_toast_tw.kill()
	toast_panel.scale = Vector2(0.6, 0.6)
	toast_panel.modulate.a = 0.0
	_toast_tw = create_tween()
	_toast_tw.set_parallel(true)
	_toast_tw.tween_property(toast_panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tw.tween_property(toast_panel, "modulate:a", 1.0, 0.15)
	_toast_tw.chain().tween_property(toast_panel, "modulate:a", 0.0, 0.3).set_delay(dur)
	_toast_tw.chain().tween_callback(func(): toast_panel.visible = false)

func show_start(title: String, goal_text: String, controls: Array) -> void:
	_open_card()
	card_box.add_child(_label(title, 54, Color.WHITE, true))
	if goal_text != "":
		card_box.add_child(_wrap(_label(goal_text, 24, Color("#d9ccff"), true)))
	card_box.add_child(_spacer(6))
	card_box.add_child(_controls_row(controls))
	card_box.add_child(_spacer(10))
	var b := _button("▶  开始游戏", true)
	b.pressed.connect(func(): start_requested.emit())
	card_box.add_child(b)
	card_box.add_child(_label("点击按钮开始" if wants_touch() else "点击按钮或按 空格 / 回车 开始", 17, Color(1, 1, 1, 0.55), true))
	_pulse_forever(b)
	b.call_deferred("grab_focus")

func show_pause() -> void:
	_open_card()
	card_box.add_child(_label("已暂停", 48, Color.WHITE, true))
	card_box.add_child(_spacer(8))
	var b1 := _button("继续", true)
	b1.pressed.connect(func(): resume_requested.emit())
	card_box.add_child(b1)
	var b2 := _button("重新开始", false)
	b2.pressed.connect(func(): restart_requested.emit())
	card_box.add_child(b2)
	card_box.add_child(_label("Esc / P 继续", 17, Color(1, 1, 1, 0.55), true))
	b1.call_deferred("grab_focus")

## r: win(bool), title, stars(0-3, win only), score, time, par_time, collected, total_collect,
## defeated, total_enemies, tip
func show_result(r: Dictionary, on_star: Callable) -> void:
	_open_card()
	var win := bool(r.get("win", false))
	card_box.add_child(_label(str(r.get("title", "")), 56, GOLD if win else Color("#ff8fa3"), true))
	if win:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 14)
		var icons: Array[Control] = []
		for i in 3:
			var st := Icon.new("star", 76.0 if i == 1 else 62.0)
			st.filled = false
			st.pivot_offset = st.custom_minimum_size * 0.5
			row.add_child(st)
			icons.append(st)
		card_box.add_child(row)
		_reveal_stars(icons, int(r.get("stars", 1)), on_star)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 6)
	var score_val := _label("0", 26, Color.WHITE, false)
	_stat(grid, "得分", score_val)
	_count_up(score_val, int(r.get("score", 0)))
	var tline := fmt_time(float(r.get("time", 0.0)))
	if float(r.get("par_time", 0.0)) > 0.0:
		tline += "  (挑战 %s)" % fmt_time(float(r["par_time"]))
	_stat(grid, "用时", _label(tline, 26, Color.WHITE, false))
	if int(r.get("total_collect", 0)) > 0:
		_stat(grid, "收集", _label("%d / %d" % [int(r.get("collected", 0)), int(r["total_collect"])], 26, Color.WHITE, false))
	if int(r.get("total_enemies", 0)) > 0 and int(r.get("defeated", 0)) > 0:
		_stat(grid, "击败", _label("%d / %d" % [int(r.get("defeated", 0)), int(r["total_enemies"])], 26, Color.WHITE, false))
	var center := CenterContainer.new()
	center.add_child(grid)
	card_box.add_child(center)
	var tip := str(r.get("tip", ""))
	if tip != "":
		card_box.add_child(_wrap(_label(tip, 19, Color("#d9ccff"), true)))
	card_box.add_child(_spacer(6))
	var b := _button("再玩一次" if win else "再试一次", true)
	b.pressed.connect(func(): restart_requested.emit())
	card_box.add_child(b)
	card_box.add_child(_label("按 R 快速重来", 17, Color(1, 1, 1, 0.55), true))
	b.call_deferred("grab_focus")

func close_card() -> void:
	if not card.visible:
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(card, "modulate:a", 0.0, 0.15)
	tw.tween_property(dim, "color:a", 0.0, 0.2)
	tw.chain().tween_callback(func():
		card.visible = false
		dim.visible = false)

func card_open() -> bool:
	return card.visible

static func fmt_time(secs: float) -> String:
	var s := int(floor(secs))
	return "%d:%02d" % [s / 60, s % 60]

# ------------------------------------------------------------------ construction

func _build_touch() -> void:
	if not wants_touch():
		return
	touch = TouchControls.new()
	hud_root.add_child(touch)
	# pause button (top-right, under the title) since there is no Esc key on phones
	pause_btn = _button("II", false)
	pause_btn.custom_minimum_size = Vector2(64, 56)
	pause_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause_btn.position = Vector2(-84, 64)
	pause_btn.pressed.connect(func(): pause_requested.emit())
	hud_root.add_child(pause_btn)

func _build_hud() -> void:
	hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud_root)
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 18
	top.offset_right = -18
	top.offset_top = 14
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(top)
	# lives
	var hp := _pill()
	hearts_box = HBoxContainer.new()
	hearts_box.add_theme_constant_override("separation", 2)
	hp.add_child(hearts_box)
	hearts_lbl = _label("", 24, Color.WHITE, false)
	hearts_box.add_child(hearts_lbl)
	top.add_child(hp)
	# collectibles / enemies
	collect_pill = _pill()
	var cb := HBoxContainer.new()
	cb.add_theme_constant_override("separation", 8)
	collect_icon = Icon.new("coin", 28.0)
	cb.add_child(collect_icon)
	collect_lbl = _label("0/0", 24, Color.WHITE, false)
	cb.add_child(collect_lbl)
	collect_pill.add_child(cb)
	top.add_child(collect_pill)
	# score
	var sp := _pill()
	var sb := HBoxContainer.new()
	sb.add_theme_constant_override("separation", 8)
	sb.add_child(Icon.new("star", 28.0))
	score_lbl = _label("0", 24, Color.WHITE, false)
	sb.add_child(score_lbl)
	sp.add_child(sb)
	top.add_child(sp)
	# timer
	timer_pill = _pill()
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 8)
	tb.add_child(Icon.new("clock", 26.0))
	timer_lbl = _label("0:00", 24, Color.WHITE, false)
	tb.add_child(timer_lbl)
	timer_pill.add_child(tb)
	top.add_child(timer_pill)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(fill)
	title_lbl = _label("", 20, Color(1, 1, 1, 0.85), false)
	top.add_child(title_lbl)
	# level progress (top-centre)
	progress = Control.new()
	progress.set_anchors_preset(Control.PRESET_CENTER_TOP)
	progress.custom_minimum_size = Vector2(300, 26)
	progress.size = Vector2(300, 26)
	progress.position = Vector2(-150, 70)
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.draw.connect(_draw_progress)
	progress.visible = false
	hud_root.add_child(progress)
	hint_pill = _pill()
	hint_lbl = _label("", 22, Color.WHITE, true)
	hint_pill.add_child(hint_lbl)
	hint_pill.visible = false
	hud_root.add_child(hint_pill)

func _build_overlay() -> void:
	dim = ColorRect.new()
	dim.color = Color(0.03, 0.01, 0.08, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.visible = false
	add_child(dim)
	card = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = CARD_BG
	st.set_corner_radius_all(30)
	st.border_color = BRAND
	st.set_border_width_all(3)
	st.shadow_color = Color(BRAND, 0.35)
	st.shadow_size = 26
	st.content_margin_left = 56
	st.content_margin_right = 56
	st.content_margin_top = 34
	st.content_margin_bottom = 30
	card.add_theme_stylebox_override("panel", st)
	card.visible = false
	add_child(card)
	card_box = VBoxContainer.new()
	card_box.alignment = BoxContainer.ALIGNMENT_CENTER
	card_box.add_theme_constant_override("separation", 12)
	card.add_child(card_box)
	get_viewport().size_changed.connect(_center_card)

func _build_toast() -> void:
	toast_panel = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.05, 0.17, 0.85)
	st.set_corner_radius_all(40)
	st.content_margin_left = 30
	st.content_margin_right = 30
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	toast_panel.add_theme_stylebox_override("panel", st)
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_lbl = _label("", 34, Color.WHITE, true)
	toast_panel.add_child(toast_lbl)
	toast_panel.visible = false
	add_child(toast_panel)

func _open_card() -> void:
	for c in card_box.get_children():
		c.queue_free()
		card_box.remove_child(c)
	dim.visible = true
	card.visible = true
	card.modulate.a = 0.0
	card.scale = Vector2(0.85, 0.85)
	call_deferred("_center_card")
	var tw := create_tween().set_parallel(true)
	tw.tween_property(dim, "color:a", 0.55, 0.25)
	tw.tween_property(card, "modulate:a", 1.0, 0.2)
	tw.tween_property(card, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _center_card() -> void:
	if not card.visible:
		return
	card.reset_size()
	var vs := get_viewport().get_visible_rect().size
	card.position = (vs - card.size) * 0.5
	card.pivot_offset = card.size * 0.5

# ------------------------------------------------------------------ widgets

func _pill() -> PanelContainer:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = PILL_BG
	st.set_corner_radius_all(22)
	st.content_margin_left = 14
	st.content_margin_right = 16
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func _label(t: String, fs: int, col: Color, centered: bool) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.02, 0.14, 0.95))
	l.add_theme_constant_override("outline_size", maxi(4, fs / 4))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

## Widest content a card may have on this screen (narrow on portrait phones).
func _card_w() -> float:
	return minf(560.0, get_viewport().get_visible_rect().size.x - 120.0)

func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(_card_w(), 0)
	return l

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _button(t: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", 28)
	b.custom_minimum_size = Vector2(300, 64)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for state in ["normal", "hover", "pressed", "focus"]:
		var st := StyleBoxFlat.new()
		var base := BRAND if primary else Color(1, 1, 1, 0.1)
		st.bg_color = base.lightened(0.12) if state == "hover" or state == "focus" else (base.darkened(0.15) if state == "pressed" else base)
		st.set_corner_radius_all(32)
		if state == "focus":
			st.border_color = Color(1, 1, 1, 0.85)
			st.set_border_width_all(3)
		b.add_theme_stylebox_override(state, st)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.focus_mode = Control.FOCUS_ALL
	return b

func _controls_row(controls: Array) -> Control:
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 22)
	row.add_theme_constant_override("v_separation", 10)
	row.custom_minimum_size = Vector2(_card_w(), 0)
	for c in controls:
		if typeof(c) != TYPE_ARRAY or c.size() < 2:
			continue
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 6)
		for k in str(c[0]).split(" "):
			item.add_child(_keycap(k))
		item.add_child(_label(str(c[1]), 20, Color(1, 1, 1, 0.85), false))
		row.add_child(item)
	return row

func _keycap(k: String) -> PanelContainer:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(1, 1, 1, 0.12)
	st.border_color = Color(1, 1, 1, 0.35)
	st.set_border_width_all(2)
	st.border_width_bottom = 4
	st.set_corner_radius_all(8)
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", st)
	p.add_child(_label(k, 18, Color.WHITE, true))
	return p

func _stat(grid: GridContainer, name_text: String, val: Label) -> void:
	grid.add_child(_label(name_text, 22, Color(1, 1, 1, 0.6), false))
	grid.add_child(val)

func _set_hearts(lives: int) -> void:
	var icons := hearts_box.get_children().filter(func(c): return c is Icon)
	var want := mini(maxi(lives, 0), MAX_HEART_ICONS)
	var show_n := maxi(want, 1)
	while icons.size() < show_n:
		var h := Icon.new("heart", 30.0)
		hearts_box.add_child(h)
		hearts_box.move_child(h, icons.size())
		icons.append(h)
	for i in icons.size():
		var ic: Icon = icons[i]
		ic.visible = i < show_n
		ic.set_filled(i < want)
	hearts_lbl.visible = lives > MAX_HEART_ICONS
	hearts_lbl.text = "×%d" % lives

func _draw_progress() -> void:
	if progress_value < 0.0:
		return
	var w := progress.size.x
	var y := progress.size.y * 0.5
	progress.draw_line(Vector2(0, y), Vector2(w, y), Color(0.07, 0.04, 0.15, 0.6), 10.0, true)
	progress.draw_line(Vector2(0, y), Vector2(w * progress_value, y), Color("#4cc9f0"), 6.0, true)
	var flag_x := w
	progress.draw_rect(Rect2(flag_x - 2, y - 13, 3, 18), Color.WHITE)
	progress.draw_colored_polygon(PackedVector2Array([Vector2(flag_x + 1, y - 13), Vector2(flag_x + 15, y - 8), Vector2(flag_x + 1, y - 3)]), Color("#ff6b6b"))
	var px := w * progress_value
	progress.draw_circle(Vector2(px, y), 9.0, Color(0.07, 0.04, 0.15))
	progress.draw_circle(Vector2(px, y), 6.5, Color.WHITE)

# ------------------------------------------------------------------ motion helpers

func _pop_ctl(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	var tw := create_tween()
	tw.tween_property(c, "scale", Vector2(1.18, 1.18), 0.06)
	tw.tween_property(c, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _shake_ctl(c: Control) -> void:
	var x0 := c.position.x
	var tw := create_tween()
	for i in 4:
		tw.tween_property(c, "position:x", x0 + (8.0 if i % 2 == 0 else -8.0), 0.04)
	tw.tween_property(c, "position:x", x0, 0.05)
	c.modulate = Color(1, 0.4, 0.4)
	create_tween().tween_property(c, "modulate", Color.WHITE, 0.4)

func _pulse_forever(c: Control) -> void:
	await get_tree().process_frame
	if not is_instance_valid(c):
		return
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween().set_loops()
	tw.tween_property(c, "scale", Vector2(1.05, 1.05), 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(c, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)

func _reveal_stars(icons: Array[Control], n: int, on_star: Callable) -> void:
	await get_tree().create_timer(0.45, true, false, true).timeout
	for i in mini(n, icons.size()):
		var ic: Icon = icons[i]
		if not is_instance_valid(ic):
			return
		ic.pivot_offset = ic.size * 0.5
		ic.set_filled(true)
		ic.scale = Vector2(1.8, 1.8)
		var tw := ic.create_tween()
		tw.tween_property(ic, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if on_star.is_valid():
			on_star.call(i)
		await get_tree().create_timer(0.32, true, false, true).timeout

func _count_up(l: Label, target: int) -> void:
	var tw := l.create_tween()
	tw.tween_method(func(v: float): l.text = str(int(v)), 0.0, float(target), clampf(target / 60.0, 0.3, 1.0)).set_delay(0.2)
