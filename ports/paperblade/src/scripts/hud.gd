extends CanvasLayer
## All 2D UI: HUD, level-up cards, chest, pause, title and results.

const Data := preload("res://scripts/data.gd")
const VIGNETTE := preload("res://shaders/vignette.gdshader")

signal chosen(opt: Dictionary)
signal reroll
signal start_pressed
signal restart_pressed
signal resume_pressed
signal chest_done
signal map_chosen(i: int)
signal meta_buy(id: String)
signal meta_refund
signal title_pressed

var root: Control
var hud: Control
var xp_bar: ProgressBar
var lv_label: Label
var time_label: Label
var kill_label: Label
var hp_bar: ProgressBar
var w_row: HBoxContainer
var p_row: HBoxContainer
var banner_box: VBoxContainer
var hurt_rect: ColorRect
var white_rect: ColorRect
var menu: Control
var menu_kind := ""
var cards: Array = []
var _last_icons := ""
var gold_label: Label
# gacha state
var gacha: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = VIGNETTE
	vm.set_shader_parameter("col", Color(0.04, 0.02, 0.08))
	vm.set_shader_parameter("strength", 0.55)
	vig.material = vm
	root.add_child(vig)
	hurt_rect = ColorRect.new()
	hurt_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hm := ShaderMaterial.new()
	hm.shader = VIGNETTE
	hm.set_shader_parameter("col", Color(0.9, 0.05, 0.05))
	hm.set_shader_parameter("strength", 0.9)
	hm.set_shader_parameter("inner", 0.2)
	hurt_rect.material = hm
	hurt_rect.modulate.a = 0.0
	root.add_child(hurt_rect)
	_build_hud()
	white_rect = ColorRect.new()
	white_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	white_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	white_rect.color = Color(1, 1, 0.95, 0)
	root.add_child(white_rect)
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.visible = false
	root.add_child(menu)


# ------------------------------------------------------------------ helpers
func _sb(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 10, bw: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s


func _lbl(text: String, size: int, col: Color = Color.WHITE, outline: int = 8) -> Label:
	var l := Label.new()
	l.text = text
	# phones show the 1280x720 canvas at ~half size: lift the small print so it stays readable
	if G.low and size < 24:
		size += 3
	l.add_theme_font_override("font", G.font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.1))
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(fill: Color, bg: Color, h: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_stylebox_override("background", _sb(bg, Color(0.05, 0.03, 0.08), 4, 2))
	b.add_theme_stylebox_override("fill", _sb(fill, Color(0, 0, 0, 0), 3, 0))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _btn(text: String, size: int = 30, w: float = 280) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 64)
	b.add_theme_font_override("font", G.font)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Color(1, 0.96, 0.85))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_focus_color", Color(1, 1, 1))
	b.add_theme_stylebox_override("normal", _sb(Color(0.2, 0.13, 0.3, 0.95), Color(0.75, 0.6, 0.35), 12, 3))
	b.add_theme_stylebox_override("hover", _sb(Color(0.35, 0.22, 0.45, 1.0), Color(1.0, 0.85, 0.45), 12, 3))
	b.add_theme_stylebox_override("focus", _sb(Color(0.35, 0.22, 0.45, 1.0), Color(1.0, 0.9, 0.5), 12, 4))
	b.add_theme_stylebox_override("pressed", _sb(Color(0.5, 0.3, 0.55, 1.0), Color(1.0, 0.9, 0.5), 12, 4))
	b.add_theme_stylebox_override("disabled", _sb(Color(0.15, 0.12, 0.18, 0.8), Color(0.35, 0.3, 0.3), 12, 2))
	b.pressed.connect(func() -> void: G.sfx.play("click", -4.0))
	return b


func icon_path(id: String) -> String:
	if Data.WEAPONS.has(id):
		return "res://assets/skill_%d.png" % Data.WEAPONS[id].icon
	if Data.PASSIVES.has(id):
		return "res://assets/item_%d.png" % Data.PASSIVES[id].icon
	return "res://assets/item_12.png"


func _tex_rect(path: String, h: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = G.tex(path)
	t.custom_minimum_size = Vector2(h, h)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


# ------------------------------------------------------------------ HUD
func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	xp_bar = _bar(Color(0.35, 0.65, 1.0), Color(0.08, 0.06, 0.16, 0.85), 22)
	xp_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	xp_bar.offset_left = 6
	xp_bar.offset_right = -6
	xp_bar.offset_top = 6
	xp_bar.offset_bottom = 28
	hud.add_child(xp_bar)
	lv_label = _lbl("Lv 1", 22, Color(1, 0.95, 0.7), 8)
	lv_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	lv_label.offset_left = -160
	lv_label.offset_right = -16
	lv_label.offset_top = 2
	lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(lv_label)
	time_label = _lbl("00:00", 40, Color.WHITE, 10)
	time_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	time_label.offset_left = -120
	time_label.offset_right = 120
	time_label.offset_top = 32
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(time_label)
	kill_label = _lbl("击杀 0", 26, Color(1, 0.85, 0.85), 8)
	kill_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	kill_label.offset_left = -260
	kill_label.offset_right = -18
	kill_label.offset_top = 36
	kill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(kill_label)
	gold_label = _lbl("0", 24, Color(1.0, 0.85, 0.35), 8)
	gold_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	gold_label.offset_left = -260
	gold_label.offset_right = -50
	gold_label.offset_top = 70
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(gold_label)
	var ci := _tex_rect("res://assets/coin.png", 26)
	ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ci.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ci.offset_left = -44
	ci.offset_right = -18
	ci.offset_top = 74
	ci.offset_bottom = 100
	hud.add_child(ci)
	var box := VBoxContainer.new()
	box.position = Vector2(10, 34)
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(box)
	w_row = HBoxContainer.new()
	p_row = HBoxContainer.new()
	for r in [w_row, p_row]:
		r.add_theme_constant_override("separation", 4)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(r)
	hp_bar = _bar(Color(0.9, 0.18, 0.2), Color(0.12, 0.03, 0.05, 0.85), 9)
	hp_bar.custom_minimum_size = Vector2(70, 9)
	hp_bar.size = Vector2(70, 9)
	hud.add_child(hp_bar)
	banner_box = VBoxContainer.new()
	banner_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_box.offset_left = -400
	banner_box.offset_right = 400
	banner_box.offset_top = 96
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(banner_box)


func _icon_slot(id: String, lvl: int, weapon: bool) -> Control:
	var p := PanelContainer.new()
	var evo := id.ends_with("_evo")
	var border := Color(1.0, 0.75, 0.25) if evo else (Color(0.5, 0.7, 1.0) if weapon else Color(0.6, 0.55, 0.45))
	p.add_theme_stylebox_override("panel", _sb(Color(0.08, 0.05, 0.12, 0.8), border, 6, 2))
	p.custom_minimum_size = Vector2(42, 42) if weapon else Vector2(32, 32)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(_tex_rect(icon_path(id), 28))
	var l := _lbl("★" if evo else str(lvl), 14, Color(1, 1, 0.7), 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	p.add_child(l)
	return p


func refresh(p, wpn, time: float, kills: int) -> void:
	xp_bar.max_value = p.xp_next
	xp_bar.value = p.xp
	lv_label.text = "Lv %d" % p.level
	var s := int(time)
	time_label.text = "%02d:%02d" % [s / 60, s % 60]
	kill_label.text = "击杀 %d" % kills
	if G.game != null:
		gold_label.text = str(int(round(G.game.gold)))
	hp_bar.max_value = p.max_hp
	hp_bar.value = p.hp
	if G.cam != null:
		var sp := G.cam.unproject_position(p.position + Vector3(0, -0.05, 0.3))
		hp_bar.position = sp + Vector2(-35, 4)
	var sig := str(wpn.lv) + str(p.passives)
	if sig != _last_icons:
		_last_icons = sig
		for c in w_row.get_children():
			c.queue_free()
		for c in p_row.get_children():
			c.queue_free()
		for id in wpn.order:
			w_row.add_child(_icon_slot(id, wpn.level_of(id), true))
		for id in p.passives:
			p_row.add_child(_icon_slot(id, p.passives[id], false))


func banner(text: String, col: Color) -> void:
	var l := _lbl(text, 40, col, 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(800, 52)
	banner_box.add_child(l)
	l.pivot_offset = Vector2(400, 26)
	l.scale = Vector2(1.6, 1.6)
	l.modulate.a = 0.0
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


func hurt_flash() -> void:
	hurt_rect.modulate.a = 0.85
	var tw := hurt_rect.create_tween()
	tw.tween_property(hurt_rect, "modulate:a", 0.0, 0.4)


func white_flash(a: float = 0.85) -> void:
	white_rect.color.a = a
	var tw := white_rect.create_tween()
	tw.tween_property(white_rect, "color:a", 0.0, 0.5)


# ------------------------------------------------------------------ menus
func _open(kind: String, dim: float = 0.6) -> VBoxContainer:
	for c in menu.get_children():
		c.queue_free()
	cards.clear()
	menu_kind = kind
	menu.visible = true
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.01, 0.07, dim)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(c)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	c.add_child(v)
	menu.modulate.a = 0.0
	var tw := menu.create_tween()
	tw.tween_property(menu, "modulate:a", 1.0, 0.15)
	return v


func close_menu() -> void:
	gacha = {}
	menu.visible = false
	menu_kind = ""
	cards.clear()
	for c in menu.get_children():
		c.queue_free()


func _center(v: VBoxContainer, l: Label) -> void:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)


func _card(opt: Dictionary, idx: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(250, 370)
	b.focus_mode = Control.FOCUS_ALL
	var evo: bool = opt.type == "evo"
	var nb := Color(1.0, 0.75, 0.25) if evo else (Color(0.55, 0.75, 1.0) if opt.type == "weapon" else Color(0.75, 0.65, 0.5))
	var bgc := Color(0.25, 0.15, 0.08, 0.97) if evo else Color(0.13, 0.09, 0.2, 0.97)
	b.add_theme_stylebox_override("normal", _sb(bgc, nb, 16, 3))
	b.add_theme_stylebox_override("hover", _sb(bgc.lightened(0.12), Color(1, 0.92, 0.55), 16, 5))
	b.add_theme_stylebox_override("focus", _sb(bgc.lightened(0.12), Color(1, 0.92, 0.55), 16, 5))
	b.add_theme_stylebox_override("pressed", _sb(bgc.lightened(0.25), Color(1, 1, 0.7), 16, 5))
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	if not G.touch:
		v.add_child(_lbl("[%d]" % (idx + 1), 16, Color(0.7, 0.65, 0.8), 4))
	var ip := icon_path(opt.id) if opt.type != "heal" else "res://assets/item_12.png"
	if opt.type == "gold":
		ip = "res://assets/fx/gem_gold.png"
	var t := _tex_rect(ip, 120)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if opt.type == "gold" else CanvasItem.TEXTURE_FILTER_LINEAR
	v.add_child(t)
	_center(v, _lbl(opt.name, 30, Color(1.0, 0.85, 0.4) if evo else Color(1, 0.97, 0.88), 8))
	_center(v, _lbl(opt.tag, 20, Color(0.55, 1.0, 0.6) if opt.tag == "新！" else Color(0.75, 0.85, 1.0), 6))
	var d := _lbl(opt.desc, 19, Color(0.92, 0.9, 0.95), 4)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(220, 0)
	_center(v, d)
	b.pressed.connect(func() -> void:
		if menu_kind == "level":
			chosen.emit(opt))
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	b.focus_entered.connect(func() -> void:
		b.pivot_offset = b.size * 0.5
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(1.05, 1.05), 0.08))
	b.focus_exited.connect(func() -> void:
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2.ONE, 0.08))
	return b


func show_levelup(opts: Array, level: int, rerolls: int) -> void:
	var v := _open("level", 0.55)
	_center(v, _lbl("境界突破！  Lv %d" % level, 54, Color(1.0, 0.88, 0.4), 14))
	_center(v, _lbl("点击卡片选择一项功法强化" if G.touch else "选择一项功法强化（数字键 1-4 快速选择）", 22, Color(0.85, 0.82, 0.95), 6))
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 18)
	v.add_child(h)
	for i in opts.size():
		var c := _card(opts[i], i)
		h.add_child(c)
		cards.append(c)
		c.modulate.a = 0.0
		var tw := c.create_tween()
		tw.tween_interval(0.05 + i * 0.07)
		tw.tween_property(c, "modulate:a", 1.0, 0.18)
	var rb := _btn("重新推演（剩余 %d）" % rerolls, 22, 300)
	rb.disabled = rerolls <= 0
	rb.pressed.connect(func() -> void: reroll.emit())
	var rc := CenterContainer.new()
	rc.add_child(rb)
	v.add_child(rc)
	if cards.size() > 0:
		cards[0].call_deferred("grab_focus")


# ------------------------------------------------------------------ gacha chest
func _particles(col: Color, amount: int, spread: float, speed: float, life: float, one_shot: bool, size: float = 6.0) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 0.95 if one_shot else 0.0
	p.spread = spread
	p.direction = Vector2(0, -1)
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 260 if one_shot else -40)
	p.damping_min = 40.0
	p.damping_max = 120.0
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	var g := Gradient.new()
	g.set_color(0, Color(col.r * 1.3, col.g * 1.3, col.b * 1.3, 1.0))
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = g
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	p.texture = G.tex("res://assets/fx/softglow.png")
	p.scale_amount_min = size * 0.5 / 256.0 * 8.0
	p.scale_amount_max = size / 256.0 * 8.0
	p.emitting = true
	if one_shot:
		p.finished.connect(p.queue_free)
	return p


func _add_sprite(parent: Control, path: String, size: float, col: Color, add: bool) -> TextureRect:
	var t := TextureRect.new()
	t.texture = G.tex(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.size = Vector2(size, size)
	t.pivot_offset = Vector2(size, size) * 0.5
	t.modulate = col
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if add:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		t.material = m
	parent.add_child(t)
	return t


func _opt_icon(o: Dictionary) -> String:
	if o.type == "heal":
		return "res://assets/item_12.png"
	return icon_path(o.id)


func show_chest(got: Array, decoys: Array, tier: int, bonus: int) -> void:
	for c in menu.get_children():
		c.queue_free()
	cards.clear()
	menu_kind = "chest"
	menu.visible = true
	menu.modulate.a = 1.0
	var vp := get_viewport().get_visible_rect().size
	var center := vp * 0.5
	var tcol: Color = G.game.CHEST_TIERS[tier][2]
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.05, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)
	bg.create_tween().tween_property(bg, "color:a", 0.78, 0.25)
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(stage)
	# rotating god-rays + glow behind the chest
	var rays := _add_sprite(stage, "res://assets/fx/rays.png", 760, Color(tcol.r, tcol.g, tcol.b, 0.0), true)
	rays.position = center - Vector2(380, 380) + Vector2(0, -40)
	var rays2 := _add_sprite(stage, "res://assets/fx/rays.png", 560, Color(1, 1, 1, 0.0), true)
	rays2.position = center - Vector2(280, 280) + Vector2(0, -40)
	var glow := _add_sprite(stage, "res://assets/fx/softglow.png", 420, Color(tcol.r, tcol.g, tcol.b, 0.0), true)
	glow.position = center - Vector2(210, 210) + Vector2(0, -40)
	var chest := _add_sprite(stage, "res://assets/item_15.png", 200, Color.WHITE, false)
	chest.position = center - Vector2(100, 100) + Vector2(0, -40)
	chest.scale = Vector2(0.2, 0.2)
	var ambient := _particles(tcol, 40, 180.0, 60.0, 1.6, false, 5.0)
	ambient.position = center + Vector2(0, -40)
	ambient.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	ambient.emission_sphere_radius = 160.0
	stage.add_child(ambient)
	var title := _lbl(String(G.game.CHEST_TIERS[tier][0]), 64, tcol.lightened(0.3), 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(vp.x, 80)
	title.position = Vector2(0, 40)
	title.pivot_offset = Vector2(vp.x * 0.5, 40)
	title.modulate.a = 0.0
	stage.add_child(title)
	var hint := _lbl("点击 / 空格 跳过", 18, Color(0.8, 0.78, 0.9, 0.7), 4)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size = Vector2(vp.x, 30)
	hint.position = Vector2(0, vp.y - 40)
	stage.add_child(hint)
	# slot reels
	var n := got.size()
	var sw := 190.0
	var gap := 18.0
	var total := n * sw + (n - 1) * gap
	var slots: Array = []
	for i in n:
		var s := {}
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", _sb(Color(0.1, 0.07, 0.16, 0.96), Color(0.5, 0.45, 0.6), 14, 3))
		p.size = Vector2(sw, 250)
		p.position = Vector2(center.x - total * 0.5 + i * (sw + gap), center.y - 70)
		p.pivot_offset = Vector2(sw, 250) * 0.5
		p.modulate.a = 0.0
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(p)
		var vb := VBoxContainer.new()
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 4)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(vb)
		var icon := _tex_rect(_opt_icon(decoys[randi() % decoys.size()]), 96)
		vb.add_child(icon)
		var nm := _lbl("", 24, Color(1, 0.95, 0.8), 6)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(nm)
		var tg := _lbl("", 17, Color(0.7, 0.9, 1.0), 4)
		tg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(tg)
		var ds := _lbl("", 15, Color(0.9, 0.88, 0.95), 3)
		ds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ds.custom_minimum_size = Vector2(sw - 20, 0)
		ds.modulate.a = 0.0
		vb.add_child(ds)
		var beam := _add_sprite(stage, "res://assets/fx/softglow.png", 260, Color(tcol.r, tcol.g, tcol.b, 0.0), true)
		beam.position = p.position + Vector2(sw * 0.5 - 130, -10)
		beam.scale = Vector2(0.7, 1.6)
		stage.move_child(beam, stage.get_children().find(p))
		s.panel = p
		s.icon = icon
		s.name = nm
		s.tag = tg
		s.desc = ds
		s.beam = beam
		s.opt = got[i]
		s.stop_at = 1.6 + i * 0.55 + (0.5 if i == n - 1 and n > 1 else 0.0)
		s.next = 0.0
		s.done = false
		s.cnt = 0
		slots.append(s)
	var take := _btn("收下", 30, 240)
	take.position = Vector2(center.x - 120, center.y + 210)
	take.modulate.a = 0.0
	take.disabled = true
	take.pressed.connect(func() -> void: chest_done.emit())
	stage.add_child(take)
	var gl := _lbl("", 26, Color(1.0, 0.85, 0.35), 8)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gl.size = Vector2(vp.x, 36)
	gl.position = Vector2(0, center.y + 170)
	stage.add_child(gl)
	gacha = {"t": 0.0, "phase": 0, "stage": stage, "chest": chest, "rays": rays, "rays2": rays2, "glow": glow,
		"title": title, "slots": slots, "decoys": decoys, "take": take, "tier": tier, "tcol": tcol,
		"center": center, "bonus": bonus, "gold_lbl": gl, "hint": hint, "speed": 1.0}
	G.sfx.play("charge", -4.0, 0.0, 0.9 + tier * 0.05)


func _gacha_skip() -> void:
	if gacha.is_empty():
		return
	if gacha.phase < 3:
		gacha.speed = 6.0
	elif not gacha.take.disabled:
		chest_done.emit()


func _gacha_update(delta: float) -> void:
	var gs := gacha
	gs.t += delta * gs.speed
	var t: float = gs.t
	var c: Vector2 = gs.center
	var tcol: Color = gs.tcol
	gs.rays.rotation += delta * 0.35
	gs.rays2.rotation -= delta * 0.6
	var chest: TextureRect = gs.chest
	if gs.phase == 0:
		# chest appears, then rattles harder and harder while light gathers
		var k := clampf(t / 1.0, 0.0, 1.0)
		chest.scale = Vector2.ONE * lerpf(0.2, 1.0, ease(minf(t / 0.3, 1.0), 0.3)) * (1.0 + k * 0.15)
		var amp := k * k * 14.0
		chest.position = c - Vector2(100, 100) + Vector2(randf_range(-amp, amp), -40 + randf_range(-amp, amp) * 0.5)
		chest.rotation = sin(t * 40.0) * k * 0.12
		gs.glow.modulate.a = k * 0.9
		gs.glow.scale = Vector2.ONE * (0.6 + k * 0.6)
		gs.rays.modulate.a = k * 0.5
		if t >= 1.0:
			gs.phase = 1
			gs.t = 0.0
			G.sfx.play("reveal", -1.0, 0.0, 1.0)
			white_flash(0.9 if gs.tier > 0 else 0.6)
			var burst := _particles(tcol, 70 + gs.tier * 40, 180.0, 900.0, 1.4, true, 9.0)
			burst.position = c + Vector2(0, -40)
			gs.stage.add_child(burst)
			var burst2 := _particles(Color(1, 0.95, 0.7), 40, 180.0, 600.0, 1.0, true, 6.0)
			burst2.position = c + Vector2(0, -40)
			gs.stage.add_child(burst2)
			var tw := chest.create_tween().set_parallel(true)
			tw.tween_property(chest, "scale", Vector2(2.4, 2.4), 0.35).set_ease(Tween.EASE_OUT)
			tw.tween_property(chest, "modulate:a", 0.0, 0.35)
			var ttl: Label = gs.title
			ttl.scale = Vector2(2.2, 2.2)
			var tw2 := ttl.create_tween().set_parallel(true)
			tw2.tween_property(ttl, "modulate:a", 1.0, 0.2)
			tw2.tween_property(ttl, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			for s in gs.slots:
				var p: PanelContainer = s.panel
				p.scale = Vector2(0.4, 0.4)
				var tw3 := p.create_tween().set_parallel(true)
				tw3.tween_property(p, "modulate:a", 1.0, 0.2)
				tw3.tween_property(p, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			gs.rays.create_tween().tween_property(gs.rays, "modulate:a", 0.75, 0.3)
			gs.rays2.create_tween().tween_property(gs.rays2, "modulate:a", 0.35, 0.3)
			gs.glow.create_tween().tween_property(gs.glow, "modulate:a", 0.45, 0.6)
		return
	if gs.phase == 1:
		var all_done := true
		for s in gs.slots:
			if s.done:
				continue
			all_done = false
			var remain: float = s.stop_at - t
			if remain <= 0.0:
				_slot_stop(s, s == gs.slots.back())
				continue
			# interval grows as the reel slows: ~0.04s fast, ~0.35s right before stopping
			if t >= s.next:
				var iv := lerpf(0.035, 0.32, pow(clampf(1.0 - remain / 1.4, 0.0, 1.0), 2.2))
				s.next = t + iv
				var d: Dictionary = gs.decoys[randi() % gs.decoys.size()]
				s.icon.texture = G.tex(_opt_icon(d))
				s.name.text = String(d.name)
				s.icon.scale = Vector2(1.15, 0.85)
				s.icon.pivot_offset = Vector2(48, 48)
				s.icon.create_tween().tween_property(s.icon, "scale", Vector2.ONE, iv * 0.9)
				s.cnt += 1
				if s.cnt % 2 == 0 or iv > 0.1:
					G.sfx.play("tick", -10.0, 0.0, 0.9 + randf() * 0.25 + (0.3 if iv > 0.15 else 0.0))
				var pn: PanelContainer = s.panel
				var hue := fmod(t * 1.7 + float(gs.slots.find(s)) * 0.13, 1.0)
				pn.add_theme_stylebox_override("panel", _sb(Color(0.1, 0.07, 0.16, 0.96), Color.from_hsv(hue, 0.55, 1.0), 14, 3))
		if all_done:
			gs.phase = 2
			gs.t = 0.0
		return
	if gs.phase == 2 and t > 0.35:
		gs.phase = 3
		var gl: Label = gs.gold_lbl
		gl.text = "额外获得  %d  金币" % int(gs.bonus)
		gl.modulate.a = 0.0
		gl.create_tween().tween_property(gl, "modulate:a", 1.0, 0.25)
		G.sfx.play("coin", -2.0)
		var tk: Button = gs.take
		tk.disabled = false
		tk.create_tween().tween_property(tk, "modulate:a", 1.0, 0.25)
		tk.call_deferred("grab_focus")
		gs.hint.text = "点击 / 空格 收下"
		gs.speed = 1.0


func _slot_stop(s: Dictionary, last: bool) -> void:
	s.done = true
	var o: Dictionary = s.opt
	var evo: bool = o.type == "evo"
	var col := Color(1.0, 0.75, 0.25) if evo else (Color(0.55, 0.8, 1.0) if o.type == "weapon" else Color(0.85, 0.75, 0.55))
	if o.type == "heal":
		col = Color(0.5, 1.0, 0.6)
	s.icon.texture = G.tex(_opt_icon(o))
	s.name.text = String(o.name)
	s.name.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if evo else Color(1, 0.97, 0.88))
	s.tag.text = String(o.get("tag", ""))
	s.tag.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6) if o.get("tag", "") == "新！" else Color(0.75, 0.85, 1.0))
	s.desc.text = String(o.get("desc", ""))
	s.desc.create_tween().tween_property(s.desc, "modulate:a", 1.0, 0.25)
	var pn: PanelContainer = s.panel
	pn.add_theme_stylebox_override("panel", _sb(Color(0.25, 0.15, 0.08, 0.97) if evo else Color(0.13, 0.09, 0.2, 0.97), col, 14, 5))
	pn.scale = Vector2(1.25, 1.25)
	pn.create_tween().tween_property(pn, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	s.icon.scale = Vector2(1.5, 1.5)
	s.icon.create_tween().tween_property(s.icon, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var bm: TextureRect = s.beam
	bm.modulate = Color(col.r, col.g, col.b, 1.0)
	bm.create_tween().tween_property(bm, "modulate:a", 0.35, 0.6)
	var pc := pn.position + pn.size * 0.5
	var b := _particles(col, 36 if not evo else 80, 180.0, 520.0 if not evo else 800.0, 1.0, true, 7.0)
	b.position = pc
	gacha.stage.add_child(b)
	var ring := _add_sprite(gacha.stage, "res://assets/fx/ring.png", 200, Color(col.r, col.g, col.b, 1.0), true)
	ring.position = pc - Vector2(100, 100)
	ring.scale = Vector2(0.3, 0.3)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(2.2, 2.2), 0.45).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(ring.queue_free)
	G.sfx.play("ding", -3.0, 0.0, 0.85 + gacha.slots.find(s) * 0.08)
	if last:
		G.sfx.play("jackpot", -3.0 if gacha.tier > 0 or evo else -8.0)
		white_flash(0.35)
	_shake_ui(10.0 if (last or evo) else 5.0)


func _shake_ui(amp: float) -> void:
	var st: Control = gacha.stage
	var tw := st.create_tween()
	for i in 6:
		var a := amp * (1.0 - i / 6.0)
		tw.tween_property(st, "position", Vector2(randf_range(-a, a), randf_range(-a, a)), 0.03)
	tw.tween_property(st, "position", Vector2.ZERO, 0.03)


func _process(delta: float) -> void:
	if not gacha.is_empty():
		_gacha_update(delta)
		if G.bot and gacha.phase == 3 and gacha.t > 1.2:
			chest_done.emit()


func show_title() -> void:
	hud.visible = false
	var v := _open("title", 0.35)
	_center(v, _lbl("纸 剑 幸 存 者", 92, Color(1.0, 0.9, 0.55), 18))
	_center(v, _lbl("PaperBlade Survivors", 28, Color(0.75, 0.85, 1.0), 8))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 20)
	v.add_child(gap)
	_center(v, _lbl(("按住屏幕任意处拖动 移动" if G.touch else "WASD / 方向键 / 手柄摇杆 移动") + "\n飞剑自动索敌 · 拾取灵晶升级 · 存活 15 分钟\n武器满级 + 持有对应被动 → 击杀精英开宝箱进化", 22, Color(0.9, 0.88, 0.95), 6))
	_center(v, _gold_row())
	var first: Button = null
	for pair in [["开始修行", func() -> void: start_pressed.emit()], ["洞府修炼", func() -> void: show_meta(G.game)]]:
		var b := _btn(pair[0], 32, 300)
		b.pressed.connect(pair[1])
		var bc := CenterContainer.new()
		bc.add_child(b)
		v.add_child(bc)
		if first == null:
			first = b
	first.call_deferred("grab_focus")


func _gold_row() -> Label:
	return _lbl("灵石金币  %d" % int(G.save.gold), 26, Color(1.0, 0.85, 0.35), 8)


func show_maps(game) -> void:
	var v := _open("maps", 0.6)
	_center(v, _lbl("选择历练之地", 56, Color(1.0, 0.88, 0.45), 14))
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 20)
	v.add_child(hb)
	var first: Button = null
	for i in Data.MAPS.size():
		var m: Dictionary = Data.MAPS[i]
		var ok := G.map_unlocked(i)
		var b := Button.new()
		b.custom_minimum_size = Vector2(380, 420)
		var bc := Color(0.12, 0.09, 0.18, 0.97)
		b.add_theme_stylebox_override("normal", _sb(bc, Color(0.55, 0.5, 0.65), 16, 3))
		b.add_theme_stylebox_override("hover", _sb(bc.lightened(0.1), Color(1, 0.9, 0.5), 16, 5))
		b.add_theme_stylebox_override("focus", _sb(bc.lightened(0.1), Color(1, 0.9, 0.5), 16, 5))
		b.add_theme_stylebox_override("pressed", _sb(bc.lightened(0.2), Color(1, 1, 0.7), 16, 5))
		b.add_theme_stylebox_override("disabled", _sb(Color(0.08, 0.07, 0.1, 0.95), Color(0.3, 0.28, 0.32), 16, 3))
		b.disabled = not ok
		var mc := MarginContainer.new()
		mc.set_anchors_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]:
			mc.add_theme_constant_override("margin_" + side, 10)
		mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(mc)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 6)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mc.add_child(vb)
		var pv := TextureRect.new()
		pv.texture = G.tex(m.preview)
		pv.custom_minimum_size = Vector2(360, 200)
		pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pv.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not ok:
			pv.modulate = Color(0.25, 0.25, 0.3)
		vb.add_child(pv)
		_center(vb, _lbl(String(m.name), 34, Color(1, 0.95, 0.8) if ok else Color(0.5, 0.5, 0.55), 8))
		_center(vb, _lbl("难度 " + "★".repeat(int(m.stars)) + "☆".repeat(3 - int(m.stars)) + "   金币 ×%.1f" % float(m.gold), 20, Color(1.0, 0.8, 0.4) if ok else Color(0.45, 0.45, 0.5), 5))
		var ds := _lbl(String(m.desc) if ok else "需在「%s」存活 %d 分钟解锁" % [Data.MAPS[m.unlock].name, int(Data.UNLOCK_TIME / 60.0)], 18, Color(0.85, 0.85, 0.92) if ok else Color(0.95, 0.5, 0.45), 4)
		ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ds.custom_minimum_size = Vector2(350, 0)
		_center(vb, ds)
		var bt := G.best_time(i)
		_center(vb, _lbl("最佳存活 %02d:%02d" % [int(bt) / 60, int(bt) % 60] if bt > 0.0 else "尚未挑战", 18, Color(0.7, 0.85, 1.0), 4))
		var idx := i
		b.pressed.connect(func() -> void: map_chosen.emit(idx))
		b.mouse_entered.connect(func() -> void:
			if not b.disabled:
				b.grab_focus())
		hb.add_child(b)
		if ok and first == null:
			first = b
	var back := _btn("返回", 26, 220)
	back.pressed.connect(show_title)
	var bc2 := CenterContainer.new()
	bc2.add_child(back)
	v.add_child(bc2)
	if first != null:
		first.call_deferred("grab_focus")


func show_meta(game) -> void:
	var v := _open("meta", 0.7)
	_center(v, _lbl("洞府修炼", 56, Color(1.0, 0.88, 0.45), 14))
	_center(v, _lbl("消耗历练所得金币，永久提升根骨（每次购买会使其他项目略微涨价）", 18, Color(0.85, 0.82, 0.95), 4))
	_center(v, _gold_row())
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var gc := CenterContainer.new()
	gc.add_child(grid)
	v.add_child(gc)
	var bought: int = game._meta_bought()
	var first: Button = null
	for id in Data.META:
		var d: Dictionary = Data.META[id]
		var lv := G.meta(id)
		var mx: int = d.max
		var cost := Data.meta_cost(id, lv, bought)
		var maxed := lv >= mx
		var afford := int(G.save.gold) >= cost
		var b := Button.new()
		b.custom_minimum_size = Vector2(158, 196)
		var bc := Color(0.14, 0.1, 0.2, 0.97) if not maxed else Color(0.2, 0.15, 0.06, 0.97)
		var bdr := Color(1.0, 0.75, 0.3) if maxed else (Color(0.55, 0.75, 1.0) if afford else Color(0.4, 0.35, 0.45))
		b.add_theme_stylebox_override("normal", _sb(bc, bdr, 12, 3))
		b.add_theme_stylebox_override("hover", _sb(bc.lightened(0.1), Color(1, 0.9, 0.5), 12, 4))
		b.add_theme_stylebox_override("focus", _sb(bc.lightened(0.1), Color(1, 0.9, 0.5), 12, 4))
		b.add_theme_stylebox_override("pressed", _sb(bc.lightened(0.2), Color(1, 1, 0.7), 12, 4))
		var vb := VBoxContainer.new()
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 2)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(vb)
		var ic := _tex_rect(d.icon, 60)
		if String(d.icon).contains("coin"):
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		vb.add_child(ic)
		_center(vb, _lbl(String(d.name), 22, Color(1, 0.95, 0.8), 6))
		var pips := ""
		for k in mx:
			pips += "●" if k < lv else "○"
		_center(vb, _lbl(pips, 14, Color(1.0, 0.8, 0.35), 3))
		var ds := _lbl(String(d.desc), 14, Color(0.85, 0.85, 0.92), 3)
		ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ds.custom_minimum_size = Vector2(146, 0)
		_center(vb, ds)
		_center(vb, _lbl("已圆满" if maxed else "%d 金" % cost, 17, Color(1.0, 0.75, 0.3) if maxed else (Color(1.0, 0.9, 0.4) if afford else Color(0.75, 0.45, 0.45)), 4))
		var pid: String = id
		b.pressed.connect(func() -> void: meta_buy.emit(pid))
		b.mouse_entered.connect(func() -> void: b.grab_focus())
		grid.add_child(b)
		if first == null:
			first = b
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 20)
	var rf := _btn("散功重修（全额返还）", 22, 300)
	rf.disabled = int(G.save.get("spent", 0)) <= 0
	rf.pressed.connect(func() -> void: meta_refund.emit())
	hb.add_child(rf)
	var back := _btn("返回", 26, 220)
	back.pressed.connect(show_title)
	hb.add_child(back)
	v.add_child(hb)
	if first != null:
		first.call_deferred("grab_focus")


func show_pause(p, wpn) -> void:
	var v := _open("pause", 0.6)
	_center(v, _lbl("暂停", 64, Color(1, 0.9, 0.6), 14))
	_center(v, _lbl("生命 %d/%d   移速 %d%%   伤害 %d%%   冷却 -%d%%\n范围 +%d%%   持续 +%d%%   数量 +%d   暴击 %d%%   护甲 %d" % [
		int(p.hp), int(p.max_hp), int(p.speed / 5.0 * 100.0), int(p.might * 100.0), int(round((1.0 - p.cd) * 100.0)),
		int(round((p.area - 1.0) * 100.0)), int(round((p.dur - 1.0) * 100.0)), p.amount, int(round(p.crit * 100.0)), int(p.armor)], 22, Color(0.9, 0.9, 1.0), 6))
	_center(v, _lbl("进化配方：御剑术+剑典 · 剑轮+流沙漏 · 掌心雷+祥云", 20, Color(1.0, 0.8, 0.45), 5))
	var first: Button = null
	for pair in [["继续", resume_pressed], ["重新开始", restart_pressed], ["返回主界面", title_pressed]]:
		var b := _btn(pair[0], 30, 280)
		var sig: Signal = pair[1]
		b.pressed.connect(func() -> void: sig.emit())
		var bc := CenterContainer.new()
		bc.add_child(b)
		v.add_child(bc)
		if first == null:
			first = b
	first.call_deferred("grab_focus")


func show_end(win: bool, p, wpn, time: float, kills: int, gold_got: int = 0) -> void:
	var v := _open("end", 0.75)
	_center(v, _lbl("飞升成功！" if win else "身陨道消", 80, Color(1.0, 0.85, 0.35) if win else Color(1.0, 0.4, 0.4), 16))
	var s := int(time)
	_center(v, _lbl("存活 %02d:%02d    等级 %d    击杀 %d" % [s / 60, s % 60, p.level, kills], 30, Color.WHITE, 8))
	_center(v, _lbl("本局获得金币 %d    （总计 %d）" % [gold_got, int(G.save.gold)], 26, Color(1.0, 0.85, 0.35), 8))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	var gc := CenterContainer.new()
	gc.add_child(grid)
	v.add_child(gc)
	for id in wpn.order:
		grid.add_child(_tex_rect(icon_path(id), 40))
		grid.add_child(_lbl(Data.WEAPONS[id].name, 24, Color(1, 0.95, 0.8), 6))
		grid.add_child(_lbl("总伤害 %d" % int(wpn.dmg_dealt.get(id, 0.0)), 24, Color(0.8, 0.9, 1.0), 6))
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 20)
	var b := _btn("再来一局", 30, 260)
	b.pressed.connect(func() -> void: restart_pressed.emit())
	hb.add_child(b)
	var b2 := _btn("返回主界面", 30, 260)
	b2.pressed.connect(func() -> void: title_pressed.emit())
	hb.add_child(b2)
	v.add_child(hb)
	b.call_deferred("grab_focus")


func _unhandled_input(ev: InputEvent) -> void:
	if menu_kind == "chest" and not gacha.is_empty():
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE]) or (ev is InputEventJoypadButton and ev.pressed):
			_gacha_skip()
			get_viewport().set_input_as_handled()
			return
	if menu_kind == "level" and ev is InputEventKey and ev.pressed and not ev.echo:
		var k: int = ev.keycode - KEY_1
		if k >= 0 and k < cards.size():
			cards[k].emit_signal("pressed")
			get_viewport().set_input_as_handled()
