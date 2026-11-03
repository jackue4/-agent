class_name Hub
extends Control
## 道馆 — the between-runs meta hub over the hand-painted dojo backdrop.
## Tabs: 出战 (loadout / mode / 破坏协议) · 修炼 · 秘籍 · 门派 · 图鉴 · 成就. Everything is tap-sized.

const TABS := [["fight", "出战"], ["train", "修炼"], ["secret", "秘籍"], ["sect", "门派"], ["codex", "图鉴"], ["ach", "成就"]]
const ENEMY_NAMES := {"blob": "果冻怪", "imp": "小恶魔", "bat": "蝙蝠", "spitter": "喷吐怪", "brute": "蛮牛", "treasure": "宝箱怪", "boss": "巨拳魔王", "slimeking": "史莱姆王", "batqueen": "蝙蝠女王"}
const REACT_DESC := {"爆燃": "感电的敌人再受火焰 → 原地爆炸", "雷暴": "灼烧的敌人再受雷击 → 连锁雷暴", "冰爆": "重锤砸中冰冻的敌人 → 冰爆碎裂", "空中追击": "把敌人连续挑飞 3 次 → 空中暴击"}

var main
var tab := "fight"
var buttons: Array = []
var t := 0.0
var open_t := 0.0
var msg := ""
var msg_t := 0.0
var codex_page := "enemies"
var view := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func open() -> void:
	visible = true
	open_t = 0.0
	tab = "fight"
	for g in ["hero", "weapon", "map", "sect"]:
		view[g] = Meta.sel(g)


func _process(dt: float) -> void:
	t += dt
	open_t += dt
	msg_t -= dt
	if visible:
		queue_redraw()


func toast(s: String) -> void:
	msg = s
	msg_t = 1.6


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in range(buttons.size() - 1, -1, -1):
			var b: Dictionary = buttons[i]
			if (b["r"] as Rect2).has_point(event.position):
				accept_event()
				_act(b)
				return
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_6:
			tab = String(TABS[k - KEY_1][0])
			Sfx.play("click")
		elif k in [KEY_ENTER, KEY_J, KEY_SPACE]:
			_act({"id": "go"})


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey:
		_gui_input(event)


# ---------------------------------------------------------------- actions
func _group_table(g: String) -> Dictionary:
	return {"hero": Meta.HEROES, "weapon": Meta.WEAPONS, "map": Meta.MAPS, "sect": Meta.SECTS}[g]


func _owned_key(g: String) -> String:
	return {"hero": "heroes", "weapon": "weapons", "map": "maps", "sect": "sects"}[g]


func _act(b: Dictionary) -> void:
	Sfx.play("click")
	match String(b["id"]):
		"tab":
			tab = String(b["arg"])
		"cycle":
			var g := String(b["arg"])
			var keys := _group_table(g).keys()
			var i := keys.find(view.get(g, keys[0]))
			view[g] = keys[(i + int(b["dir"]) + keys.size()) % keys.size()]
			if Meta.owns(_owned_key(g), view[g]):
				Meta.set_sel(g, view[g])
		"buy":
			var g := String(b["arg"])
			if Meta.buy(_owned_key(g), String(b["key"])):
				if _group_table(g).has(String(b["key"])) and g != "secret":
					Meta.set_sel(g, String(b["key"]))
				toast("解锁成功！")
				Sfx.play("levelup")
			else:
				toast("碎片结晶不足！")
		"secret":
			if Meta.buy("secrets", String(b["key"])):
				toast("秘籍习得！")
				Sfx.play("levelup")
			else:
				toast("碎片结晶不足！")
		"up":
			if Meta.buy_upgrade(String(b["key"])):
				toast("修炼成功！")
				Sfx.play("levelup")
			else:
				toast("碎片结晶不足！" if Meta.up(String(b["key"])) < int(Meta.UPGRADES[b["key"]]["max"]) else "已满级")
		"sect":
			var s := String(b["key"])
			if Meta.owns("sects", s):
				Meta.set_sel("sect", s)
				view["sect"] = s
				toast("已拜入 " + String(Meta.SECTS[s]["name"]))
			elif Meta.buy("sects", s):
				Meta.set_sel("sect", s)
				view["sect"] = s
				toast("拜师成功！")
				Sfx.play("levelup")
			else:
				toast("碎片结晶不足！")
		"mode":
			Meta.set_sel("mode", String(b["arg"]))
		"heat":
			var h := clampi(int(Meta.sel("heat")) + int(b["dir"]), 0, mini(int(Meta.data["max_heat"]) + 1, Meta.PROTOCOL.size()))
			Meta.set_sel("heat", h)
		"codex":
			codex_page = String(b["arg"])
		"go":
			visible = false
			main.start_run(main.default_cfg())


# ---------------------------------------------------------------- drawing helpers
func _txt(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 8, f: Font = null) -> void:
	var fnt: Font = f if f != null else G.font_cn
	if outline > 0:
		draw_string_outline(fnt, pos, s, align, width, size, outline, G.INK)
	draw_string(fnt, pos, s, align, width, size, col)


func _panel(r: Rect2, fill: Color, w := 5.0, shadow := 8.0) -> void:
	draw_rect(Rect2(r.position + Vector2(shadow, shadow), r.size), G.INK)
	draw_rect(r, fill)
	draw_rect(r, G.INK, false, w)


func _btn(r: Rect2, label: String, b: Dictionary, fill: Color, enabled := true, fs := 26) -> void:
	var pressed := enabled and get_global_mouse_position().distance_to(r.get_center()) < 0.0
	_panel(r, fill if enabled else Color(0.5, 0.47, 0.5), 4.0, 3.0 if pressed else 6.0)
	_txt(Vector2(r.position.x, r.position.y + r.size.y * 0.5 + fs * 0.36), label, fs, G.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 6)
	if enabled:
		b["r"] = r
		buttons.append(b)


func _fit(tex: Texture2D, box: Rect2, mod := Color.WHITE) -> void:
	if tex == null:
		return
	var s := minf(box.size.x / tex.get_width(), box.size.y / tex.get_height())
	var sz := tex.get_size() * s
	draw_texture_rect(tex, Rect2(box.position + (box.size - sz) * 0.5, sz), false, mod)


func _multi(pos: Vector2, s: String, width: float, size: int, col: Color, lines := -1) -> void:
	draw_multiline_string(G.font_cn, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, lines, col)


func _crystal(c: Vector2, r: float) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.75, -r * 0.2), c + Vector2(0, r), c + Vector2(-r * 0.75, -r * 0.2)])
	Ink.shape(self, pts, Color(1.0, 0.55, 0.95), 3.0)
	draw_line(c + Vector2(-r * 0.3, -r * 0.3), c + Vector2(0, -r * 0.75), Color(1, 1, 1, 0.8), 2.5)


# ---------------------------------------------------------------- main draw
func _draw() -> void:
	buttons.clear()
	var vs := size
	var bg := Art.tex("dojo_bg")
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.16, 0.12, 0.2))
	if bg != null:
		var k := maxf(vs.x / bg.get_width(), vs.y / bg.get_height()) * (1.03 + 0.01 * sin(t * 0.3))
		var sz := bg.get_size() * k
		draw_texture_rect(bg, Rect2((vs - sz) * 0.5, sz), false)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.07, 0.05, 0.09, 0.35))
	# header
	var hb := Ink.burst(Vector2(150, 64), 140, 50, 10, 0.2, int(t * 4.0))
	Ink.shape(self, hb, G.RED, 6.0)
	_txt(Vector2(10, 82), "道 馆", 52, G.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, 280, 12)
	var cr := Rect2(vs.x - 330, 22, 300, 70)
	_panel(cr, Color(0.2, 0.12, 0.28, 0.95), 4.0, 6.0)
	_crystal(cr.position + Vector2(40, 35), 22)
	_txt(Vector2(cr.position.x + 74, cr.position.y + 48), str(Meta.crystals()), 36, Color(1, 0.7, 1.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, G.font)
	_txt(Vector2(cr.position.x + 74, cr.position.y + 66), "碎片结晶", 16, G.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
	var st: Dictionary = Meta.data["stats"]
	_txt(Vector2(320, 70), "出战 %d 次 · 累计击碎 %d · 最久存活 %d:%02d · 最高协议 %d" % [int(st["runs"]), int(st["kills"]), int(st["best_time"]) / 60, int(st["best_time"]) % 60, int(Meta.data["max_heat"])], 22, G.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 6)
	# tabs
	for i in TABS.size():
		var tr := Rect2(24, 140 + i * 100, 220, 84)
		var on := tab == String(TABS[i][0])
		if on:
			tr = Rect2(tr.position + Vector2(10, 0), tr.size)
		_btn(tr, String(TABS[i][1]), {"id": "tab", "arg": TABS[i][0]}, G.RED if on else Color(0.3, 0.22, 0.34), true, 32)
	var C := Rect2(276, 120, vs.x - 300, vs.y - 144)
	_panel(C, Color(G.PAPER, 0.93), 5.0, 10.0)
	match tab:
		"fight":
			_draw_fight(C)
		"train":
			_draw_train(C)
		"secret":
			_draw_secret(C)
		"sect":
			_draw_sect(C)
		"codex":
			_draw_codex(C)
		"ach":
			_draw_ach(C)
	if msg_t > 0.0:
		var mr := Rect2(vs.x * 0.5 - 220, vs.y - 120, 440, 64)
		_panel(mr, G.INK, 3.0, 0.0)
		_txt(Vector2(mr.position.x, mr.position.y + 43), msg, 30, G.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, mr.size.x, 0)


# ---------------------------------------------------------------- 出战
func _item_art(g: String, key: String, box: Rect2, owned: bool) -> void:
	var mod := Color.WHITE if owned else Color(0.2, 0.18, 0.24)
	match g:
		"hero":
			_fit(Art.tex("hero_" + key), box, mod)
		"weapon":
			if key == "fist":
				Ink.circle(self, box.get_center(), box.size.y * 0.3, Color(1, 0.9, 0.8) if owned else mod, 5.0)
				draw_line(box.get_center() + Vector2(-14, -6), box.get_center() + Vector2(14, -6), G.INK, 4.0)
			else:
				_fit(Art.tex("weapon_" + key), box, mod)
		"map":
			var gid := String(Meta.MAPS[key]["ground"])
			draw_rect(box, Ground.FLOOR if gid == "" else Color(0.5, 0.5, 0.5))
			if gid != "":
				draw_texture_rect(Art.tex(gid), box, false, mod)
			else:
				draw_arc(box.get_center(), box.size.y * 0.32, 0.4, TAU - 0.2, 24, Color(0.5, 0.32, 0.18), 7.0)
			draw_rect(box, G.INK, false, 4.0)
			if not owned:
				draw_rect(box, Color(0, 0, 0, 0.6))
		"sect":
			var sc: Color = Meta.SECTS[key]["col"]
			Ink.circle(self, box.get_center(), box.size.y * 0.42, sc if owned else mod, 5.0)
			_txt(Vector2(box.position.x, box.get_center().y + 18), String(Meta.SECTS[key]["name"]).substr(0, 1), 48, G.WHITE, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 8)
	if not owned:
		_txt(Vector2(box.position.x, box.get_center().y + 12), "未解锁", 26, G.WHITE, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 7)


func _selector(r: Rect2, g: String, label: String) -> void:
	var tbl := _group_table(g)
	var key := String(view.get(g, tbl.keys()[0]))
	var d: Dictionary = tbl[key]
	var owned := Meta.owns(_owned_key(g), key)
	_panel(r, Color(1, 0.97, 0.9), 4.0, 6.0)
	_item_art(g, key, Rect2(r.position + Vector2(12, 12), Vector2(r.size.y - 24, r.size.y - 24)), owned)
	var x := r.position.x + r.size.y + 4
	_txt(Vector2(x, r.position.y + 36), label, 20, Color(0.5, 0.3, 0.2), HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
	_txt(Vector2(x + 70, r.position.y + 38), String(d["name"]), 32, G.RED if owned else Color(0.4, 0.4, 0.4), HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
	_multi(Vector2(x, r.position.y + 74), String(d["desc"]), r.end.x - x - 360, 24, G.INK, 3)
	_btn(Rect2(r.end.x - 166, r.position.y + (r.size.y - 70) * 0.5, 70, 70), "<", {"id": "cycle", "arg": g, "dir": -1}, G.BLUE, true, 36)
	_btn(Rect2(r.end.x - 86, r.position.y + (r.size.y - 70) * 0.5, 70, 70), ">", {"id": "cycle", "arg": g, "dir": 1}, G.BLUE, true, 36)
	if not owned:
		var cost := int(d["cost"])
		_btn(Rect2(r.end.x - 350, r.position.y + (r.size.y - 70) * 0.5, 170, 70), "解锁 %d" % cost, {"id": "buy", "arg": g, "key": key}, G.ORANGE, Meta.crystals() >= cost, 24)
	elif Meta.sel(g) == key:
		_txt(Vector2(r.end.x - 350, r.position.y + r.size.y * 0.5 + 10), "已选择", 26, G.GREEN, HORIZONTAL_ALIGNMENT_CENTER, 170, 6)


func _draw_fight(C: Rect2) -> void:
	var mode := String(Meta.sel("mode"))
	# hero showcase
	var hr := Rect2(C.position.x + 22, C.position.y + 22, 330, C.size.y - 44)
	var hk := String(view.get("hero", "red"))
	var hd: Dictionary = Meta.HEROES[hk]
	var hown := Meta.owns("heroes", hk)
	_panel(hr, Color(0.98, 0.9, 0.72), 5.0, 8.0)
	var rays := Ink.burst(Vector2(hr.get_center().x, hr.position.y + 220), 170, 190, 14, 0.22, 7)
	draw_colored_polygon(rays, Color(G.YELLOW, 0.5))
	var bob := sin(t * 2.0) * 4.0
	_item_art("hero", hk, Rect2(hr.position + Vector2(20, 20 + bob), Vector2(hr.size.x - 40, 400)), hown)
	_txt(Vector2(hr.position.x, hr.position.y + 460), String(hd["name"]), 40, G.RED if hown else Color(0.4, 0.4, 0.4), HORIZONTAL_ALIGNMENT_CENTER, hr.size.x, 8)
	_multi(Vector2(hr.position.x + 18, hr.position.y + 498), String(hd["desc"]), hr.size.x - 36, 23, G.INK, 3)
	var ay := hr.end.y - 90
	_btn(Rect2(hr.position.x + 16, ay, 74, 74), "<", {"id": "cycle", "arg": "hero", "dir": -1}, G.BLUE, true, 38)
	_btn(Rect2(hr.end.x - 90, ay, 74, 74), ">", {"id": "cycle", "arg": "hero", "dir": 1}, G.BLUE, true, 38)
	if not hown:
		_btn(Rect2(hr.position.x + 100, ay, hr.size.x - 200, 74), "解锁 %d" % int(hd["cost"]), {"id": "buy", "arg": "hero", "key": hk}, G.ORANGE, Meta.crystals() >= int(hd["cost"]), 26)
	elif Meta.sel("hero") == hk:
		_txt(Vector2(hr.position.x + 100, ay + 48), "出战中", 28, G.GREEN, HORIZONTAL_ALIGNMENT_CENTER, hr.size.x - 200, 6)
	# right column
	var x := hr.end.x + 26
	var w := C.end.x - x - 22
	var y := C.position.y + 22
	if mode == "daily":
		var dc := Meta.daily_config(Meta.today())
		var dr := Rect2(x, y, w, 440)
		_panel(dr, Color(1, 0.95, 0.8), 4.0, 6.0)
		_txt(Vector2(x, y + 60), "今日挑战  #%d" % Meta.today(), 40, G.RED, HORIZONTAL_ALIGNMENT_CENTER, w, 8)
		var lines := ["角色：" + String(Meta.HEROES[dc["hero"]]["name"]), "武器：" + String(Meta.WEAPONS[dc["weapon"]]["name"]), "地图：" + String(Meta.MAPS[dc["map"]]["name"]), "诅咒：" + String(SkillDB.CURSES[dc["curse"]]["name"]) + " — " + String(SkillDB.CURSES[dc["curse"]]["desc"])]
		for i in lines.size():
			_txt(Vector2(x + 40, y + 130 + i * 56), lines[i], 28, G.INK, HORIZONTAL_ALIGNMENT_LEFT, w - 80, 0)
		_txt(Vector2(x, y + 380), "所有人同一种子 · 结晶 ×1.5 · 今日最佳 %d 击碎" % int(Meta.data["daily"].get(str(Meta.today()), 0)), 24, Color(0.6, 0.3, 0.1), HORIZONTAL_ALIGNMENT_CENTER, w, 0)
	else:
		var rh := 140.0
		_selector(Rect2(x, y, w, rh), "weapon", "武器")
		_selector(Rect2(x, y + rh + 14, w, rh), "map", "地图")
		_selector(Rect2(x, y + (rh + 14) * 2, w, rh), "sect", "门派")
	# modes
	var my := C.position.y + 22 + 3 * 154 + 6
	var mw := (w - 40) / 3.0
	var mi := 0
	for m in Meta.MODES.keys():
		var on: bool = mode == m
		_btn(Rect2(x + mi * (mw + 20), my, mw, 66), String(Meta.MODES[m]["name"]), {"id": "mode", "arg": m}, G.RED if on else Color(0.35, 0.3, 0.4), true, 28)
		mi += 1
	_txt(Vector2(x, my + 98), String(Meta.MODES[mode]["desc"]), 21, G.INK, HORIZONTAL_ALIGNMENT_LEFT, w, 0)
	# 破坏协议 + go
	var gy := C.end.y - 130
	if mode == "normal":
		var heat := int(Meta.sel("heat"))
		var cap := mini(int(Meta.data["max_heat"]) + 1, Meta.PROTOCOL.size())
		_txt(Vector2(x, gy + 26), "破坏协议", 26, Color(0.6, 0.15, 0.15), HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
		_btn(Rect2(x + 120, gy, 64, 64), "-", {"id": "heat", "dir": -1}, G.BLUE, heat > 0, 36)
		_txt(Vector2(x + 190, gy + 48), str(heat), 44, G.RED if heat > 0 else G.INK, HORIZONTAL_ALIGNMENT_CENTER, 60, 0, G.font)
		_btn(Rect2(x + 256, gy, 64, 64), "+", {"id": "heat", "dir": 1}, G.BLUE, heat < cap, 36)
		var mods := "无额外难度" if heat == 0 else "、".join(Meta.PROTOCOL.slice(0, heat))
		_multi(Vector2(x, gy + 92), mods + ("  · 结晶 +%d%%" % (25 * heat) if heat > 0 else ""), w - 380, 19, Color(0.4, 0.15, 0.15), 2)
	var go := Rect2(C.end.x - 340, C.end.y - 126, 318, 104)
	var pulse := 1.0 + 0.03 * sin(t * 6.0)
	var gr := Rect2(go.get_center() - go.size * pulse * 0.5, go.size * pulse)
	_btn(gr, "出 战 !", {"id": "go"}, G.RED, true, 46)


# ---------------------------------------------------------------- 修炼
func _draw_train(C: Rect2) -> void:
	_txt(Vector2(C.position.x + 30, C.position.y + 56), "修炼 — 永久提升，每局生效", 34, G.RED, HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
	var keys := Meta.UPGRADES.keys()
	var cols := 2
	var cw := (C.size.x - 60 - 20) / cols
	var ch := 128.0
	for i in keys.size():
		var id := String(keys[i])
		var u: Dictionary = Meta.UPGRADES[id]
		var r := Rect2(C.position.x + 30 + (i % cols) * (cw + 20), C.position.y + 84 + int(i / cols) * (ch + 10), cw, ch)
		_panel(r, Color(1, 0.97, 0.9), 4.0, 5.0)
		var lv := Meta.up(id)
		var mx := int(u["max"])
		_txt(Vector2(r.position.x + 20, r.position.y + 42), String(u["name"]), 30, G.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
		_txt(Vector2(r.position.x + 130, r.position.y + 40), String(u["desc"]), 21, Color(0.35, 0.3, 0.3), HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
		for k in mx:
			var pc := Vector2(r.position.x + 32 + k * 40, r.position.y + 90)
			Ink.circle(self, pc, 13, G.YELLOW if k < lv else Color(0.8, 0.78, 0.72), 3.0)
		var full := lv >= mx
		var cost := Meta.up_cost(id)
		_btn(Rect2(r.end.x - 200, r.position.y + 54, 180, 62), "已满级" if full else "%d 结晶" % cost, {"id": "up", "key": id}, G.GREEN, not full and Meta.crystals() >= cost, 24)


# ---------------------------------------------------------------- 秘籍
func _draw_secret(C: Rect2) -> void:
	_txt(Vector2(C.position.x + 30, C.position.y + 56), "秘籍 — 解锁新的技能与招式进化", 34, G.RED, HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
	var keys := Meta.SECRETS.keys()
	var cw := (C.size.x - 60 - 40) / 3.0
	for i in keys.size():
		var id := String(keys[i])
		var d: Dictionary = Meta.SECRETS[id]
		var r := Rect2(C.position.x + 30 + i * (cw + 20), C.position.y + 100, cw, C.size.y - 140)
		var own := Meta.owns("secrets", id)
		_panel(r, Color(0.98, 0.9, 0.72) if own else Color(0.9, 0.87, 0.82), 5.0, 8.0)
		var scroll := Rect2(r.position.x + 30, r.position.y + 30, r.size.x - 60, 220)
		draw_rect(scroll, Color(0.95, 0.85, 0.6))
		draw_rect(scroll, G.INK, false, 4.0)
		var icon: String = {"frost": "frost", "heavyfist": "heavyfist", "evo": "fireball"}[id]
		SkillDB.draw_icon(self, icon, scroll.get_center(), 70)
		_txt(Vector2(r.position.x, r.position.y + 300), String(d["name"]), 40, G.RED, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 8)
		_multi(Vector2(r.position.x + 30, r.position.y + 350), String(d["desc"]), r.size.x - 60, 23, G.INK, 5)
		if own:
			_txt(Vector2(r.position.x, r.end.y - 50), "已习得", 32, G.GREEN, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 6)
		else:
			_btn(Rect2(r.position.x + 40, r.end.y - 100, r.size.x - 80, 74), "习得 %d 结晶" % int(d["cost"]), {"id": "secret", "key": id}, G.ORANGE, Meta.crystals() >= int(d["cost"]), 28)


# ---------------------------------------------------------------- 门派
func _draw_sect(C: Rect2) -> void:
	_txt(Vector2(C.position.x + 30, C.position.y + 56), "门派 — 拜入一派，获得元素加持", 34, G.RED, HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
	var keys := Meta.SECTS.keys()
	var cw := (C.size.x - 60 - 4 * 16) / 5.0
	for i in keys.size():
		var id := String(keys[i])
		var d: Dictionary = Meta.SECTS[id]
		var r := Rect2(C.position.x + 30 + i * (cw + 16), C.position.y + 100, cw, C.size.y - 140)
		var own := Meta.owns("sects", id)
		var on: bool = Meta.sel("sect") == id
		_panel(r, Color(1, 0.96, 0.85) if on else Color(0.93, 0.9, 0.85), 6.0 if on else 4.0, 8.0)
		var sc: Color = d["col"]
		draw_rect(Rect2(r.position + Vector2(6, 6), Vector2(r.size.x - 12, 40)), sc)
		_item_art("sect", id, Rect2(r.position.x + 20, r.position.y + 60, r.size.x - 40, 200), own)
		_txt(Vector2(r.position.x, r.position.y + 310), String(d["name"]), 32, sc.darkened(0.3), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 0)
		_multi(Vector2(r.position.x + 18, r.position.y + 356), String(d["desc"]), r.size.x - 36, 21, G.INK, 6)
		var lab := "当前门派" if on else ("拜入" if own else "拜师 %d" % int(d["cost"]))
		_btn(Rect2(r.position.x + 16, r.end.y - 92, r.size.x - 32, 72), lab, {"id": "sect", "key": id}, G.GREEN if own else G.ORANGE, not on and (own or Meta.crystals() >= int(d["cost"])), 26)


# ---------------------------------------------------------------- 图鉴
func _draw_codex(C: Rect2) -> void:
	var pages := [["enemies", "怪物"], ["skills", "技能"], ["combos", "合体技"], ["reactions", "元素反应"]]
	for i in pages.size():
		var on := codex_page == String(pages[i][0])
		_btn(Rect2(C.position.x + 30 + i * 190, C.position.y + 22, 176, 62), String(pages[i][1]), {"id": "codex", "arg": pages[i][0]}, G.RED if on else Color(0.35, 0.3, 0.4), true, 26)
	var top := C.position.y + 110
	match codex_page:
		"enemies":
			var keys := ENEMY_NAMES.keys()
			var cw := (C.size.x - 60 - 4 * 16) / 5.0
			var ch := (C.size.y - 140) / 2.0 - 10
			var seen := 0
			for i in keys.size():
				var id := String(keys[i])
				var n := int(Meta.data["codex"]["enemies"].get(id, 0))
				if n > 0:
					seen += 1
				var r := Rect2(C.position.x + 30 + (i % 5) * (cw + 16), top + int(i / 5) * (ch + 16), cw, ch)
				_panel(r, Color(1, 0.97, 0.9), 4.0, 5.0)
				var sid := "enemy_imp" if id == "treasure" else "enemy_" + id
				var mod := Color.WHITE if n > 0 else Color(0, 0, 0)
				if id == "treasure" and n > 0:
					mod = Color(1, 0.85, 0.4)
				_fit(Art.tex(sid), Rect2(r.position + Vector2(16, 14), Vector2(r.size.x - 32, r.size.y - 100)), mod)
				_txt(Vector2(r.position.x, r.end.y - 48), String(ENEMY_NAMES[id]) if n > 0 else "？？？", 26, G.INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 0)
				_txt(Vector2(r.position.x, r.end.y - 16), "击碎 %d" % n if n > 0 else "未遭遇", 19, Color(0.5, 0.35, 0.3), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 0)
			_txt(Vector2(C.end.x - 330, C.position.y + 62), "收集 %d / %d" % [seen, keys.size()], 26, G.RED, HORIZONTAL_ALIGNMENT_RIGHT, 300, 0)
		"skills":
			var keys := SkillDB.LIST.keys()
			var cols := 6
			var cw := (C.size.x - 60 - (cols - 1) * 12) / cols
			var seen := 0
			for i in keys.size():
				var id := String(keys[i])
				var n := int(Meta.data["codex"]["skills"].get(id, 0))
				if n > 0:
					seen += 1
				var r := Rect2(C.position.x + 30 + (i % cols) * (cw + 12), top + int(i / cols) * 200, cw, 186)
				_panel(r, Color(1, 0.97, 0.9), 4.0, 4.0)
				if n > 0:
					SkillDB.draw_icon(self, id, Vector2(r.get_center().x, r.position.y + 66), 44)
				else:
					Ink.circle(self, Vector2(r.get_center().x, r.position.y + 66), 44, Color(0.3, 0.28, 0.32), 4.0)
					_txt(Vector2(r.position.x, r.position.y + 82), "?", 44, G.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 6, G.font)
				var info: Dictionary = SkillDB.LIST[id]
				_txt(Vector2(r.position.x, r.position.y + 146), String(info["name"]) if n > 0 else "？？？", 24, G.INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 0)
				_txt(Vector2(r.position.x, r.position.y + 174), String(info["kind"]), 18, Color(0.5, 0.35, 0.3), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 0)
			_txt(Vector2(C.end.x - 330, C.position.y + 62), "收集 %d / %d" % [seen, keys.size()], 26, G.RED, HORIZONTAL_ALIGNMENT_RIGHT, 300, 0)
		"combos":
			var keys := SkillDB.COMBOS.keys()
			var cw := (C.size.x - 60 - 2 * 16) / 3.0
			var ch := (C.size.y - 140) / 2.0 - 8
			for i in keys.size():
				var id := String(keys[i])
				var d: Dictionary = SkillDB.COMBOS[id]
				var got := Meta.codex_has("combos", id)
				var r := Rect2(C.position.x + 30 + (i % 3) * (cw + 16), top + int(i / 3) * (ch + 16), cw, ch)
				_panel(r, Color(1, 0.93, 0.6) if got else Color(0.85, 0.82, 0.78), 5.0, 6.0)
				_fit(Art.icon(id), Rect2(r.position.x + 14, r.position.y + 14, 130, 130), Color.WHITE if got else Color(0.12, 0.1, 0.14))
				_txt(Vector2(r.position.x + 160, r.position.y + 54), String(d["name"]) if got else "？？？", 32, G.RED, HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
				var bname := String(SkillDB.LIST[d["b"]]["name"])
				_txt(Vector2(r.position.x + 160, r.position.y + 92), String(SkillDB.LIST[d["a"]]["name"]) + " + " + bname, 21, Color(0.5, 0.3, 0.1), HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
				_txt(Vector2(r.position.x + 160, r.position.y + 122), "两者 Lv3 解锁", 18, Color(0.45, 0.4, 0.4), HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
				_multi(Vector2(r.position.x + 18, r.position.y + 180), String(d["desc"]) if got else "尚未领悟……", r.size.x - 36, 21, G.INK, 4)
		"reactions":
			var keys := REACT_DESC.keys()
			var cw := (C.size.x - 60 - 16) / 2.0
			for i in keys.size():
				var id := String(keys[i])
				var n := int(Meta.data["codex"]["reactions"].get(id, 0))
				var r := Rect2(C.position.x + 30 + (i % 2) * (cw + 16), top + int(i / 2) * 230, cw, 210)
				var cols := {"爆燃": G.ORANGE, "雷暴": G.YELLOW, "冰爆": Color(0.55, 0.85, 1.0), "空中追击": Color(0.5, 0.9, 1.0)}
				_panel(r, Color(1, 0.97, 0.9), 4.0, 6.0)
				var b := Ink.burst(Vector2(r.position.x + 100, r.get_center().y), 80, 70, 10, 0.25, i * 7)
				Ink.shape(self, b, cols[id] if n > 0 else Color(0.6, 0.58, 0.6), 4.0)
				_txt(Vector2(r.position.x + 20, r.get_center().y + 14), id if n > 0 else "?", 30, G.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 160, 8)
				_txt(Vector2(r.position.x + 210, r.position.y + 70), String(REACT_DESC[id]), 24, G.INK, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 230, 0)
				_txt(Vector2(r.position.x + 210, r.position.y + 130), "已触发 %d 次" % n if n > 0 else "尚未触发", 22, Color(0.5, 0.35, 0.3), HORIZONTAL_ALIGNMENT_LEFT, -1, 0)


# ---------------------------------------------------------------- 成就
func _draw_ach(C: Rect2) -> void:
	var keys := Meta.ACHIEVEMENTS.keys()
	var got := 0
	for k in keys:
		if bool(Meta.data["ach"].get(k, false)):
			got += 1
	_txt(Vector2(C.position.x + 30, C.position.y + 56), "成就  %d / %d" % [got, keys.size()], 34, G.RED, HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
	var cw := (C.size.x - 60 - 16) / 2.0
	var ch := minf(96.0, (C.size.y - 110) / 7.0 - 8)
	for i in keys.size():
		var id := String(keys[i])
		var d: Dictionary = Meta.ACHIEVEMENTS[id]
		var on := bool(Meta.data["ach"].get(id, false))
		var r := Rect2(C.position.x + 30 + (i % 2) * (cw + 16), C.position.y + 84 + int(i / 2) * (ch + 8), cw, ch)
		_panel(r, Color(1, 0.94, 0.7) if on else Color(0.9, 0.88, 0.84), 3.0, 4.0)
		var sc := Vector2(r.position.x + 44, r.get_center().y)
		Ink.shape(self, Ink.star(sc, 28, 12, 5, -PI / 2), G.YELLOW if on else Color(0.7, 0.68, 0.7), 3.0)
		_txt(Vector2(r.position.x + 86, r.position.y + 38), String(d["name"]), 26, G.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
		_txt(Vector2(r.position.x + 86, r.position.y + 70), String(d["desc"]), 19, Color(0.4, 0.35, 0.35), HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
		_txt(Vector2(r.end.x - 170, r.position.y + 50), ("已领 " if on else "+") + str(d["reward"]) + " 结晶", 22, G.GREEN if on else Color(0.6, 0.3, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, 150, 0)