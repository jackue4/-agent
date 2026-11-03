class_name Hud
extends Control
## All screen-space UI, drawn in comic style: bars, combo, banner, skill cards (rarity / reroll /
## banish / lock), merchant & altar panels, title and the crystal settlement screen.

var main
var choices: Array = []
var sel := 0
var card_rects: Array = []
var open_t := 0.0
var t := 0.0
var lock_idx := -1
var _last_state := ""
var buttons: Array = []   ## [{r: Rect2, id: String, i: int}] built every draw for tap/click


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	process_mode = Node.PROCESS_MODE_ALWAYS


func open_choices(list: Array) -> void:
	choices = list
	sel = 0
	open_t = 0.0
	# a carried-over locked card always sits in slot 0
	lock_idx = -1
	if not main.locked_card.is_empty():
		pass


func open_overlay() -> void:
	open_t = 0.0
	sel = 0


func locked_card() -> Dictionary:
	if lock_idx >= 0 and lock_idx < choices.size():
		return choices[lock_idx]
	return {}


func boss_label() -> String:
	if G.boss != null and is_instance_valid(G.boss):
		return G.boss.boss_name()
	return ""


func _process(dt: float) -> void:
	t += dt
	open_t += dt
	if main != null and main.state != "hub":
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	_handle(event)


func _unhandled_input(event: InputEvent) -> void:
	_handle(event)


func _press(event: InputEvent) -> bool:
	return (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)


func _hit_button(pos: Vector2) -> Dictionary:
	for b in buttons:
		if (b["r"] as Rect2).has_point(pos):
			return b
	return {}


func _handle(event: InputEvent) -> void:
	if main == null:
		return
	var st: String = main.state
	if st == "title":
		if (event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode in [KEY_J, KEY_ENTER, KEY_SPACE]) or (event is InputEventMouseButton and event.pressed):
			get_viewport().set_input_as_handled()
			main._start()
	elif st == "over":
		if open_t < 0.6:
			return
		if _press(event):
			var b := _hit_button(event.position)
			if not b.is_empty():
				get_viewport().set_input_as_handled()
				Sfx.play("click")
				if b["id"] == "hub":
					main.back_to_hub()
				else:
					main.restart()
		elif event is InputEventKey and event.pressed and not event.echo:
			var k := (event as InputEventKey).physical_keycode
			if k in [KEY_R]:
				main.restart()
			elif k in [KEY_ENTER, KEY_J, KEY_H]:
				main.back_to_hub()
	elif st == "pause":
		if _press(event):
			var b := _hit_button(event.position)
			if b.is_empty():
				return
			get_viewport().set_input_as_handled()
			_pause_action(b)
	elif st == "shop" or st == "altar":
		if open_t < 0.3:
			return
		if _press(event):
			var b := _hit_button(event.position)
			if b.is_empty():
				return
			get_viewport().set_input_as_handled()
			_overlay_action(st, b)
		elif event is InputEventKey and event.pressed and not event.echo:
			var k := (event as InputEventKey).physical_keycode
			if k == KEY_ESCAPE or k == KEY_ENTER:
				main.close_overlay() if st == "shop" else main.take_curse("")
			elif k >= KEY_1 and k <= KEY_4:
				_overlay_action(st, {"id": "item", "i": k - KEY_1})
	elif st == "levelup" and open_t > 0.35:
		if event is InputEventMouseMotion:
			for i in card_rects.size():
				if (card_rects[i] as Rect2).has_point(event.position):
					sel = i
		elif _press(event):
			var b := _hit_button(event.position)
			if not b.is_empty():
				get_viewport().set_input_as_handled()
				_card_action(b)
				return
			for i in card_rects.size():
				if (card_rects[i] as Rect2).has_point(event.position):
					get_viewport().set_input_as_handled()
					main.choose(choices[i])
					return
		elif event is InputEventKey and event.pressed and not event.echo:
			var k := (event as InputEventKey).physical_keycode
			if k in [KEY_A, KEY_LEFT]:
				sel = (sel - 1 + choices.size()) % choices.size()
				Sfx.play("click")
			elif k in [KEY_D, KEY_RIGHT]:
				sel = (sel + 1) % choices.size()
				Sfx.play("click")
			elif k >= KEY_1 and k <= KEY_3 and k - KEY_1 < choices.size():
				get_viewport().set_input_as_handled()
				main.choose(choices[k - KEY_1])
			elif k == KEY_R:
				main.reroll()
			elif k == KEY_X:
				main.banish(sel)
			elif k == KEY_L:
				_card_action({"id": "lock", "i": sel})
			elif k in [KEY_J, KEY_ENTER, KEY_SPACE]:
				get_viewport().set_input_as_handled()
				main.choose(choices[sel])


func _pause_action(b: Dictionary) -> void:
	match String(b["id"]):
		"resume":
			Sfx.play("click")
			main.pause_page = "main"
			main.toggle_pause()
		"page":
			Sfx.play("click")
			main.pause_page = String(b["arg"])
		"hub":
			Sfx.play("click")
			if main.pause_page == "confirm":
				main.quit_to_hub()
			else:
				main.pause_page = "confirm"
		"set":
			SettingsUI.act(b)


func _card_action(b: Dictionary) -> void:
	match String(b["id"]):
		"reroll":
			main.reroll()
		"banish":
			main.banish(int(b["i"]))
		"lock":
			if Meta.up("lock") > 0:
				lock_idx = -1 if lock_idx == int(b["i"]) else int(b["i"])
				Sfx.play("click")


func _overlay_action(st: String, b: Dictionary) -> void:
	if b["id"] == "close":
		Sfx.play("click")
		if st == "shop":
			main.close_overlay()
		else:
			main.take_curse("")
		return
	var i := int(b["i"])
	if st == "shop":
		main.buy_shop(i)
	elif i < main.altar_items.size():
		main.take_curse(String(main.altar_items[i]))


func _txt(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 8, f: Font = null) -> void:
	var fnt: Font = f if f != null else G.font_cn
	draw_string_outline(fnt, pos, s, align, width, size, outline, G.INK)
	draw_string(fnt, pos, s, align, width, size, col)


func _panel(r: Rect2, fill: Color, w := 5.0, shadow := 8.0) -> void:
	draw_rect(Rect2(r.position + Vector2(shadow, shadow), r.size), G.INK)
	draw_rect(r, fill)
	draw_rect(r, G.INK, false, w)




func _draw() -> void:
	var vs := size
	if main == null:
		return
	var st: String = main.state
	if st != _last_state:
		_last_state = st
		open_t = 0.0
	if st == "hub":
		return
	if st == "title":
		_draw_title(vs)
		return
	var p: Player = G.player
	if p == null:
		return
	# XP bar top
	var xr := Rect2(16, 12, vs.x - 32, 26)
	_panel(xr, Color(0.2, 0.17, 0.25), 4.0, 5.0)
	draw_rect(Rect2(xr.position + Vector2(3, 3), Vector2((xr.size.x - 6) * float(p.xp) / float(p.xp_need), xr.size.y - 6)), G.BLUE)
	_txt(Vector2(xr.position.x + 10, xr.position.y + 21), "LV " + str(p.level), 22, G.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, G.font)
	# HP
	var hr := Rect2(20, 52, 360, 34)
	_panel(hr, Color(0.25, 0.1, 0.12), 4.0, 6.0)
	var hk := p.hp / p.max_hp
	draw_rect(Rect2(hr.position + Vector2(4, 4), Vector2((hr.size.x - 8) * hk, hr.size.y - 8)), G.RED if hk > 0.3 or int(t * 6) % 2 == 0 else G.YELLOW)
	draw_rect(Rect2(hr.position + Vector2(4, 4), Vector2((hr.size.x - 8) * hk, 6)), Color(1, 1, 1, 0.35))
	_txt(Vector2(hr.position.x + 12, hr.position.y + 26), "HP " + str(int(ceil(p.hp))) + " / " + str(int(p.max_hp)), 20, G.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, G.font)
	# time & kills
	var secs := int(G.game_time)
	var left := maxi(int(ceil(main.round_len - G.game_time)), 0)
	var urgent := left <= 30
	var tc := G.WHITE if not urgent else (G.RED if int(t * 4.0) % 2 == 0 else G.YELLOW)
	var tsz := 42 if not urgent else 52
	_txt(Vector2(0, 84 + (6 if urgent else 0)), ("%d:%02d" % [left / 60, left % 60]) if main.reaper == null else "死神降临", tsz, tc, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 10, G.font if main.reaper == null else null)
	_txt(Vector2(vs.x - 260, 82), "击碎 " + str(G.kills), 30, G.YELLOW, HORIZONTAL_ALIGNMENT_RIGHT, 240, 8)
	_txt(Vector2(vs.x - 260, 118), "铜钱 " + str(main.coins), 24, Color(1, 0.8, 0.35), HORIZONTAL_ALIGNMENT_RIGHT, 240, 6)
	var tag := String(Meta.MODES[main.mode()]["name"])
	if main.heat > 0:
		tag += " · 协议%d" % main.heat
	_txt(Vector2(0, 122), tag, 22, G.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 6)
	if not p.curses.is_empty():
		var cx := 400.0
		for cid in p.curses:
			SkillDB.draw_icon(self, cid, Vector2(cx, 69), 16)
			cx += 38.0
	# combo
	if G.combo >= 3:
		var cs := 1.0 + 0.25 * clampf(G.combo_timer - 1.9, 0.0, 0.3) / 0.3
		var cc := G.YELLOW if G.combo < 30 else (G.ORANGE if G.combo < 80 else G.RED)
		var cp := Vector2(vs.x - 60, 190)
		draw_set_transform(cp, -0.12, Vector2(cs, cs))
		var burst := Ink.burst(Vector2(-110, -20), 150, 70, 10, 0.25, int(t * 6.0))
		draw_colored_polygon(burst, Color(0.07, 0.05, 0.09, 0.8))
		_txt(Vector2(-300, 0), str(G.combo), 74, cc, HORIZONTAL_ALIGNMENT_RIGHT, 220, 12, G.font)
		_txt(Vector2(-75, 0), "HITS!", 30, G.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, G.font)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(Rect2(vs.x - 290, 225, 230 * clampf(G.combo_timer / 2.2, 0, 1), 6), cc)
	# boss bar
	if G.boss != null and is_instance_valid(G.boss) and not G.boss.dead:
		var b: Enemy = G.boss
		var br := Rect2(vs.x * 0.2, vs.y - 70, vs.x * 0.6, 30)
		_panel(br, Color(0.2, 0.08, 0.1), 5.0, 6.0)
		draw_rect(Rect2(br.position + Vector2(4, 4), Vector2((br.size.x - 8) * b.hp / b.max_hp, br.size.y - 8)), Color(0.85, 0.15, 0.3))
		_txt(Vector2(br.position.x, br.position.y - 10), b.boss_name(), 28, G.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 8)
	# skills row
	var ix := 30.0
	for id in p.skills.keys():
		var c := Vector2(ix + 26, vs.y - 50)
		if SkillDB.COMBOS.has(id):
			draw_circle(c, 30, Color(1, 0.8, 0.15), true, -1.0, false)
		SkillDB.draw_icon(self, id, c, 24)
		var lv: int = p.skills[id]
		var mx := lv >= SkillDB.max_of(id)
		_txt(c + Vector2(-26, 40), ("合体" if SkillDB.COMBOS.has(id) else ("MAX" if mx else "Lv" + str(lv))), 16, G.YELLOW if mx else G.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 52, 5)
		ix += 62.0
	# controls hint
	if G.game_time < 25.0 and st == "play":
		_txt(Vector2(0, 140) if G.touch else Vector2(20, vs.y - 100 if not p.skills.is_empty() else vs.y - 30), ("左侧摇杆移动 · 「攻击」连击 · 「重锤」砸地 · 「冲刺」中按攻击=飞踢 · 自动瞄准最近的怪" if G.touch else "WASD 移动 · J/左键 连击 · K/右键 重锤砸地 · 空格 冲刺(冲刺中按攻击=飞踢) · 鼠标瞄准"), 26 if G.touch else 20, G.WHITE, HORIZONTAL_ALIGNMENT_CENTER if G.touch else HORIZONTAL_ALIGNMENT_LEFT, vs.x if G.touch else -1.0, 6)
	# banner
	if G.banner_t > 0.0:
		var k := clampf(G.banner_t, 0.0, 0.3) / 0.3
		var by := 180.0
		var bh := 70.0 * k
		draw_colored_polygon(PackedVector2Array([Vector2(0, by - bh * 0.5 + 10), Vector2(vs.x, by - bh * 0.5 - 10), Vector2(vs.x, by + bh * 0.5 - 10), Vector2(0, by + bh * 0.5 + 10)]), Color(0.07, 0.05, 0.09, 0.85))
		if k > 0.6:
			_txt(Vector2(0, by + 14), G.banner_text, 36, G.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 10)
	if st == "levelup":
		_draw_levelup(vs)
	elif st == "shop" or st == "altar":
		_draw_overlay(vs, st)
	elif st == "pause":
		_draw_pause(vs)
	if G.show_fps:
		_txt(Vector2(vs.x - 160, vs.y - 16), "FPS %d" % Engine.get_frames_per_second(), 20, G.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 140, 5, G.font)
	elif st == "over":
		_draw_over(vs)



func _draw_title(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.07, 0.05, 0.09, 0.55))
	var sp := Art.tex("title_splash_tex")
	if sp != null:
		# cover-fit the splash art with a slow ken-burns push
		var k := maxf(vs.x / sp.get_width(), vs.y / sp.get_height()) * (1.04 + 0.02 * sin(t * 0.4))
		var sz := sp.get_size() * k
		draw_texture_rect(sp, Rect2((vs - sz) * 0.5, sz), false)
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.07, 0.05, 0.09, 0.25))
	var c := vs * 0.5 + Vector2(0, -90)
	var rays := 24 if sp == null else 0
	for i in rays:
		var a := TAU * i / rays + t * 0.1
		var b := a + TAU / rays * 0.5
		draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a) * 2000, c + Vector2.from_angle(b) * 2000]), Color(1, 0.85, 0.15, 0.12))
	if sp != null:
		c = Vector2(vs.x * 0.5, 150)
	var burst := Ink.burst(c, 520, 170, 14, 0.22, int(t * 5.0))
	var sh := burst.duplicate()
	for i in sh.size():
		sh[i] += Vector2(12, 12)
	draw_colored_polygon(sh, G.INK)
	Ink.shape(self, burst, G.RED, 7.0)
	draw_set_transform(c, -0.06, Vector2.ONE * (1.0 + sin(t * 3.0) * 0.03))
	_txt(Vector2(-600, 10), "STICK BONK!", 120, G.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, 1200, 18, G.font)
	_txt(Vector2(-600, 80), "火柴人 · 大乱斗", 54, G.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 1200, 12)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var pr := Rect2(vs.x * 0.5 - 430, vs.y - 290, 860, 200)
	_panel(pr, Color(G.PAPER, 0.94), 5.0, 10.0)
	var lines := ["WASD 移动    鼠标 瞄准", "J / 左键  四段连击（最后一击挑飞！）", "K / 右键  跃起重锤砸地    空格 冲刺 (冲刺中攻击=飞踢)",
		"元素反应 · 合体金卡 · 道馆养成 · 四大门派 · 三张地图 · 破坏协议"]
	if G.touch or G.low:
		lines = ["左半屏拖动 = 摇杆移动    攻击自动瞄准最近怪物", "「攻击」四段连击（最后一击挑飞！）", "「重锤」跃起砸地    「冲刺」突进 (冲刺中攻击=飞踢)", "元素反应 · 合体金卡 · 道馆养成 · 四大门派 · 三张地图 · 破坏协议"]
	for i in lines.size():
		draw_string(G.font_cn, Vector2(pr.position.x + 30, pr.position.y + 48 + i * 42), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, G.INK)
	if int(t * 2.0) % 2 == 0:
		_txt(Vector2(0, vs.y - 60), ("点击屏幕 进入道馆！" if G.touch or G.low else "按 J / 回车 / 鼠标左键 进入道馆！"), 40, G.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 10)


func _btn(r: Rect2, label: String, id: String, i: int, fill: Color, enabled := true, fs := 26) -> void:
	_panel(r, fill if enabled else Color(0.45, 0.42, 0.45), 4.0, 6.0)
	_txt(Vector2(r.position.x, r.position.y + r.size.y * 0.5 + fs * 0.36), label, fs, G.WHITE if enabled else Color(0.8, 0.8, 0.8), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 6)
	if enabled:
		buttons.append({"r": r, "id": id, "i": i})


func _draw_levelup(vs: Vector2) -> void:
	buttons.clear()
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.07, 0.05, 0.09, 0.6))
	var c := Vector2(vs.x * 0.5, 110)
	var evo := not choices.is_empty() and String(choices[0].get("rar", "")) == "evo"
	draw_set_transform(c, -0.04, Vector2.ONE * (1.0 + 0.05 * sin(t * 6.0)))
	var b := Ink.burst(Vector2.ZERO, 300, 70, 12, 0.25, int(t * 6.0))
	Ink.shape(self, b, G.GREEN if evo else G.YELLOW, 6.0)
	_txt(Vector2(-400, 18), "招式进化！二选一" if evo else "LEVEL UP!  选择一个技能", 46, G.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 800, 12)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	card_rects.clear()
	var n := choices.size()
	var cw := 340.0
	var ch := 430.0
	var gap := 50.0
	var total := n * cw + (n - 1) * gap
	var x0 := (vs.x - total) * 0.5
	var y0 := clampf((vs.y - ch - 110.0) * 0.5 + 40.0, 180.0, 230.0)
	var p: Player = G.player
	for i in n:
		var card: Dictionary = choices[i]
		var id := String(card["id"])
		var rar := String(card.get("rar", "common"))
		var rinfo: Dictionary = SkillDB.RARITY.get(rar, SkillDB.RARITY["common"])
		var appear := clampf((open_t - i * 0.08) / 0.25, 0.0, 1.0)
		var ease := 1.0 - pow(1.0 - appear, 3.0)
		var r := Rect2(x0 + i * (cw + gap), y0 + (1.0 - ease) * 400.0, cw, ch)
		var hov := i == sel
		if hov:
			r = r.grow(10)
		card_rects.append(r)
		var info := SkillDB.info(id)
		var col: Color = info["col"]
		var tilt := (-0.03 + 0.03 * i) if not hov else 0.0
		draw_set_transform(r.get_center(), tilt, Vector2.ONE)
		var lr := Rect2(-r.size * 0.5, r.size)
		var frame: Color = rinfo["col"]
		if rar != "common":
			var glow := lr.grow(10.0 + 4.0 * sin(t * 5.0))
			draw_rect(glow, Color(frame, 0.55))
		_panel(lr, G.PAPER if rar != "combo" else Color(1.0, 0.93, 0.6), 6.0 if hov else 5.0, 12.0 if hov else 8.0)
		if rar != "common":
			draw_rect(lr.grow(-6), frame, false, 6.0)
		draw_rect(Rect2(lr.position + Vector2(10, 10), Vector2(lr.size.x - 20, 150)), col.lightened(0.15))
		for k in 10:
			var yy := lr.position.y + 14 + k * 15
			draw_line(Vector2(lr.position.x + 10, yy), Vector2(lr.end.x - 10, yy - 30), Color(1, 1, 1, 0.2), 4.0)
		var itex := Art.icon(id)
		if SkillDB.COMBOS.has(id) and itex != null:
			draw_texture_rect(itex, Rect2(Vector2(-62, lr.position.y + 20), Vector2(124, 124)), false)
		else:
			SkillDB.draw_icon(self, id, Vector2(0, lr.position.y + 86), 52)
		var cur: int = int(p.skills.get(id, 0))
		var tag := String(info["kind"])
		var add := int(rinfo["lv"]) if SkillDB.LIST.has(id) else 1
		var nxt := mini(cur + add, SkillDB.max_of(id))
		var lvtxt := "新技能!" if cur == 0 else "Lv %d > %d" % [cur, nxt]
		if SkillDB.COMBOS.has(id):
			lvtxt = "合体金卡"
		elif not SkillDB.LIST.has(id):
			lvtxt = String(rinfo["name"])
		elif nxt >= SkillDB.MAX and SkillDB.ACTIVE.has(id):
			lvtxt = "【觉醒】"
		_txt(Vector2(lr.position.x + 18, lr.position.y + 40), tag, 20, G.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 6)
		if rar == "rare" or rar == "epic":
			_txt(Vector2(lr.position.x, lr.position.y + 40), String(rinfo["name"]) + " +%d " % add, 22, frame.lightened(0.3), HORIZONTAL_ALIGNMENT_RIGHT, lr.size.x - 18, 6)
		_txt(Vector2(lr.position.x, lr.position.y + 200), String(info["name"]), 38, col.lightened(0.1), HORIZONTAL_ALIGNMENT_CENTER, lr.size.x, 10)
		_txt(Vector2(lr.position.x, lr.position.y + 238), lvtxt, 24, G.YELLOW if nxt >= SkillDB.MAX or rar == "combo" else G.WHITE, HORIZONTAL_ALIGNMENT_CENTER, lr.size.x, 6)
		var desc := String(info["desc"])
		if nxt >= SkillDB.MAX and info.has("awaken"):
			desc = String(info["awaken"])
		if SkillDB.COMBOS.has(id):
			desc = SkillDB.LIST[info["a"]]["name"] + " + " + (SkillDB.LIST[info["b"]]["name"] if SkillDB.LIST.has(info["b"]) else "") + "\n" + desc
		draw_multiline_string(G.font_cn, Vector2(lr.position.x + 24, lr.position.y + 290), desc, HORIZONTAL_ALIGNMENT_LEFT, lr.size.x - 48, 22, 5, G.INK)
		if lock_idx == i:
			var lk := Rect2(Vector2(lr.end.x - 64, lr.position.y - 18), Vector2(76, 40))
			_panel(lk, G.BLUE, 3.0, 4.0)
			_txt(Vector2(lk.position.x, lk.position.y + 29), "已锁", 22, G.WHITE, HORIZONTAL_ALIGNMENT_CENTER, lk.size.x, 5)
		_txt(Vector2(lr.position.x, lr.end.y - 18), "[" + str(i + 1) + "]", 24, G.WHITE if not hov else G.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, lr.size.x, 6, G.font)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# per-card buttons under the card (big enough for thumbs)
		if not evo and open_t > 0.3:
			var by := r.end.y + 16.0
			var can_ban := SkillDB.LIST.has(id) or SkillDB.COMBOS.has(id)
			_btn(Rect2(r.position.x, by, r.size.x * 0.48, 56), "封印", "banish", i, G.PURPLE, main.banishes > 0 and can_ban, 24)
			if Meta.up("lock") > 0:
				_btn(Rect2(r.position.x + r.size.x * 0.52, by, r.size.x * 0.48, 56), "取消锁定" if lock_idx == i else "锁定", "lock", i, G.BLUE, true, 24)
	if not evo:
		var rr := Rect2(vs.x - 250, 40, 220, 70)
		_btn(rr, "刷新 ×%d" % main.rerolls, "reroll", 0, G.ORANGE, main.rerolls > 0, 28)
		_txt(Vector2(vs.x - 250, 140), "封印剩余 %d" % main.banishes, 22, G.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 220, 6)
	_txt(Vector2(0, vs.y - 24), ("点击卡片 选择技能" if G.touch else "A/D 选择 · J/回车/点击 确认 · R 刷新 · X 封印 · L 锁定"), 22, G.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 6)


func _draw_overlay(vs: Vector2, st: String) -> void:
	buttons.clear()
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.07, 0.05, 0.09, 0.65))
	var shop := st == "shop"
	var c := Vector2(vs.x * 0.5, 110)
	var bu := Ink.burst(c, 330, 70, 12, 0.25, int(t * 6.0))
	Ink.shape(self, bu, Color(1, 0.75, 0.3) if shop else Color(0.55, 0.2, 0.8), 6.0)
	_txt(Vector2(0, c.y + 16), "流浪商人" if shop else "混沌祭坛 · 接受诅咒？", 46, G.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 12)
	var items: Array = main.shop_items if shop else main.altar_items
	var n := items.size()
	var cw := 300.0 if shop else 380.0
	var gap := 30.0
	var x0 := (vs.x - (n * cw + (n - 1) * gap)) * 0.5
	for i in n:
		var r := Rect2(x0 + i * (cw + gap), 220, cw, 380)
		var name := ""
		var desc := ""
		var cost := 0
		var sold := false
		if shop:
			var it: Dictionary = items[i]
			name = String(it["name"])
			desc = String(it["desc"])
			cost = int(it["cost"])
			sold = bool(it.get("sold", false))
		else:
			var cd: Dictionary = SkillDB.CURSES[items[i]]
			name = String(cd["name"])
			desc = String(cd["desc"]) + "\n\n接受后：铜钱 +20，结算结晶 +15%"
		_panel(r, G.PAPER if shop else Color(0.92, 0.85, 0.95), 5.0, 10.0)
		var ic := Vector2(r.get_center().x, r.position.y + 90)
		if shop:
			Ink.circle(self, ic, 50, Color(1, 0.8, 0.35), 5.0)
			_txt(Vector2(r.position.x, ic.y + 18), "¥", 56, G.INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 0, G.font)
		else:
			SkillDB.draw_icon(self, String(items[i]), ic, 50)
		_txt(Vector2(r.position.x, r.position.y + 190), name, 34, G.YELLOW if shop else Color(0.85, 0.3, 0.45), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 9)
		draw_multiline_string(G.font_cn, Vector2(r.position.x + 22, r.position.y + 236), desc, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 44, 22, 4, G.INK)
		var br := Rect2(r.position.x + 20, r.end.y - 76, r.size.x - 40, 60)
		if shop:
			_btn(br, "已购" if sold else "%d 铜钱" % cost, "item", i, G.GREEN, not sold and main.coins >= cost, 26)
		else:
			_btn(br, "接受诅咒", "item", i, Color(0.6, 0.12, 0.25), true, 26)
	if shop:
		_txt(Vector2(0, 660), "持有铜钱：%d" % main.coins, 30, Color(1, 0.8, 0.35), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 8)
	_btn(Rect2(vs.x * 0.5 - 140, 700, 280, 70), "离开" if shop else "拒绝诅咒", "close", 0, G.BLUE, true, 30)


# ---------------------------------------------------------------- ESC menu
func _draw_pause(vs: Vector2) -> void:
	buttons.clear()
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.07, 0.05, 0.09, 0.72))
	var page: String = main.pause_page
	var c := Vector2(vs.x * 0.5, 96)
	Ink.shape(self, Ink.burst(c, 250, 60, 12, 0.22, 5), G.RED, 6.0)
	_txt(Vector2(0, c.y + 18), {"main": "暂 停", "settings": "设 置", "stats": "角色属性", "confirm": "返回道馆？"}.get(page, ""), 50, G.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 12)
	match page:
		"main":
			var w := 460.0
			var x := vs.x * 0.5 - w * 0.5
			var items := [["继续游戏", {"id": "resume"}, G.GREEN], ["角色属性", {"id": "page", "arg": "stats"}, G.BLUE], ["设  置", {"id": "page", "arg": "settings"}, G.ORANGE], ["返回道馆", {"id": "hub"}, Color(0.6, 0.15, 0.2)]]
			for i in items.size():
				_btn(Rect2(x, 190 + i * 116, w, 92), String(items[i][0]), String(items[i][1]["id"]), 0, items[i][2], true, 38)
				buttons[buttons.size() - 1]["arg"] = items[i][1].get("arg", "")
			_txt(Vector2(0, vs.y - 34), "" if G.touch else "ESC 继续游戏", 22, G.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 6)
		"settings":
			var r := Rect2(vs.x * 0.5 - 560, 170, 1120, vs.y - 300)
			SettingsUI.draw(self, r, buttons)
			_back(vs)
		"stats":
			_draw_stats(vs)
			_back(vs)
		"confirm":
			var pr := Rect2(vs.x * 0.5 - 420, 210, 840, 220)
			_panel(pr, G.PAPER, 5.0, 10.0)
			draw_multiline_string(G.font_cn, Vector2(pr.position.x + 40, pr.position.y + 70), "放弃本局并返回道馆？
已获得的击碎、BOSS 会按比例结算碎片结晶（无存活奖励）。", HORIZONTAL_ALIGNMENT_LEFT, pr.size.x - 80, 30, -1, G.INK)
			_btn(Rect2(vs.x * 0.5 - 330, 480, 300, 90), "确认返回", "hub", 0, Color(0.6, 0.15, 0.2), true, 34)
			_btn(Rect2(vs.x * 0.5 + 30, 480, 300, 90), "继续战斗", "resume", 0, G.GREEN, true, 34)


func _back(vs: Vector2) -> void:
	_btn(Rect2(vs.x * 0.5 - 150, vs.y - 116, 300, 84), "返  回", "page", 0, G.BLUE, true, 34)
	buttons[buttons.size() - 1]["arg"] = "main"


func _draw_stats(vs: Vector2) -> void:
	var p: Player = G.player
	var hd: Dictionary = Meta.HEROES[p.hero]
	var pr := Rect2(vs.x * 0.5 - 600, 160, 1200, vs.y - 300)
	_panel(pr, G.PAPER, 5.0, 10.0)
	var art := Art.tex("hero_" + p.hero)
	if art != null:
		var s := minf(260.0 / art.get_width(), 330.0 / art.get_height())
		draw_texture_rect(art, Rect2(pr.position + Vector2(30, 30), art.get_size() * s), false)
	var lx := pr.position.x + 40
	_txt(Vector2(lx, pr.position.y + 400), String(hd["name"]), 34, G.RED, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
	var sub := "%s · %s · Lv %d" % [String(Meta.WEAPONS[p.weapon]["name"]), String(Meta.SECTS[p.sect]["name"]), p.level]
	_txt(Vector2(lx, pr.position.y + 440), sub, 22, G.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
	var rows := [
		["生命", "%d / %d" % [int(ceil(p.hp)), int(p.max_hp)]], ["伤害倍率", "x%.2f" % (p.dmg_mult * p.atk_mult)],
		["攻击速度", "x%.2f" % p.atk_speed], ["暴击率", "%d%%" % int(round(p.crit * 100.0))],
		["暴击伤害", "x%.2f" % p.crit_mult], ["移动速度", "%d" % int(p.speed)],
		["攻击范围", "x%.2f" % p.reach], ["击退", "x%.2f" % p.kb_mult],
		["拾取范围", "%d" % int(p.pickup_r)], ["冲刺冷却", "%.2f 秒" % p.dash_cd_max],
		["吸血", "%.1f / 击" % p.vamp], ["受到伤害", "x%.2f" % (p.dmg_taken * G.dmg_in_mult)],
		["闪避", "%d%%" % int(round(p.dodge * 100.0))], ["复活", "%d 次" % p.revive_left],
	]
	var x0 := pr.position.x + 340
	var cw := (pr.end.x - x0 - 30) / 2.0
	for i in rows.size():
		var rx := x0 + (i % 2) * cw
		var ry := pr.position.y + 50 + int(i / 2) * 46
		draw_string(G.font_cn, Vector2(rx, ry), String(rows[i][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.45, 0.3, 0.25))
		draw_string(G.font, Vector2(rx + 150, ry), String(rows[i][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, G.INK)
	var sy := pr.position.y + 50 + 7 * 46 + 10
	draw_string(G.font_cn, Vector2(x0, sy), "技能", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.45, 0.3, 0.25))
	var ix := x0 + 90
	for id in p.skills.keys():
		SkillDB.draw_icon(self, id, Vector2(ix, sy - 8), 22)
		draw_string(G.font, Vector2(ix - 20, sy + 36), "Lv%d" % int(p.skills[id]), HORIZONTAL_ALIGNMENT_CENTER, 40, 16, G.INK)
		ix += 56
		if ix > pr.end.x - 40:
			break
	var extra := []
	for slot in p.evo.keys():
		extra.append(String(SkillDB.EVO[p.evo[slot]]["name"]))
	for cid in p.curses:
		extra.append("诅咒·" + String(SkillDB.CURSES[cid]["name"]))
	if not extra.is_empty():
		draw_string(G.font_cn, Vector2(x0, sy + 80), "  ".join(extra), HORIZONTAL_ALIGNMENT_LEFT, pr.end.x - x0 - 30, 22, Color(0.5, 0.2, 0.3))


func _draw_over(vs: Vector2) -> void:
	buttons.clear()
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.07, 0.05, 0.09, 0.7))
	var win: bool = main.survived
	var c := Vector2(vs.x * 0.5, 150)
	var b := Ink.burst(c, 380, 120, 12, 0.25, 3)
	Ink.shape(self, b, G.GREEN if win else G.RED, 7.0)
	_txt(Vector2(0, c.y + 34), "时辰已到" if win else "K.O.", 100 if not win else 84, G.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 16, G.font)
	var p: Player = G.player
	var pr := Rect2(vs.x * 0.5 - 420, 270, 840, 330)
	_panel(pr, G.PAPER, 5.0, 10.0)
	var secs := int(G.game_time)
	var lines := ["存活时间  %02d:%02d" % [secs / 60, secs % 60], "击碎怪物  %d" % G.kills, "最高连击  %d" % G.best_combo, "达到等级  Lv %d" % p.level, "击败 BOSS  %d" % main.bosses_killed]
	if main.heat > 0:
		lines.append("破坏协议  %d%s" % [main.heat, "  已达成" if main.protocol_cleared >= main.heat else ""])
	for i in lines.size():
		draw_string(G.font_cn, Vector2(pr.position.x + 40, pr.position.y + 50 + i * 44), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, G.INK)
	# crystal reward (counts up)
	var k := clampf((open_t - 0.4) / 1.0, 0.0, 1.0)
	var shown := int(main.reward * k)
	var cr := Vector2(pr.position.x + 640, pr.position.y + 120)
	var gem := Art.tex("pickup_gem")
	if gem != null:
		draw_texture_rect(gem, Rect2(cr - Vector2(50, 70), Vector2(100, 100)), false, Color(1.0, 0.6, 1.0))
	_txt(Vector2(cr.x - 160, cr.y + 80), "+%d" % shown, 64, Color(1, 0.6, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 320, 12, G.font)
	_txt(Vector2(cr.x - 160, cr.y + 124), "碎片结晶（共 %d）" % Meta.crystals(), 24, G.INK, HORIZONTAL_ALIGNMENT_CENTER, 320, 0)
	var ay := pr.position.y + 260
	for aid in Meta.last_new_ach.slice(0, 2):
		_txt(Vector2(cr.x - 200, ay), "★ " + String(Meta.ACHIEVEMENTS[aid]["name"]), 22, Color(0.9, 0.5, 0.1), HORIZONTAL_ALIGNMENT_CENTER, 400, 0)
		ay += 30
	if open_t > 0.6:
		_btn(Rect2(vs.x * 0.5 - 330, vs.y - 150, 300, 84), "回道馆", "hub", 0, G.ORANGE, true, 34)
		_btn(Rect2(vs.x * 0.5 + 30, vs.y - 150, 300, 84), "再来一局", "retry", 0, G.GREEN, true, 34)
	_txt(Vector2(0, vs.y - 30), ("" if G.touch else "回车 = 回道馆 · R = 再来一局"), 22, G.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 6)