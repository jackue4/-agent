class_name SettingsUI
extends RefCounted
## Shared settings page (pause menu + 道馆). Values live in Meta.data["settings"] and are applied
## immediately (audio bus, shake strength, damage numbers, quality tier, FPS counter).

const ROWS := [
	["sfx", "音效音量", "num", 0, 100, 10],
	["shake", "屏幕震动", "num", 0, 100, 25],
	["dmg_num", "伤害数字", "bool"],
	["hitstop", "打击顿帧", "bool"],
	["quality", "画质", "enum", ["auto", "high", "low"], ["自动", "高", "低（省电）"]],
	["fps", "显示帧率", "bool"],
]


static func value(k: String):
	return Meta.data["settings"].get(k)


static func _panel(ci: CanvasItem, r: Rect2, fill: Color, w := 4.0, sh := 6.0) -> void:
	ci.draw_rect(Rect2(r.position + Vector2(sh, sh), r.size), G.INK)
	ci.draw_rect(r, fill)
	ci.draw_rect(r, G.INK, false, w)


static func _txt(ci: CanvasItem, p: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 6) -> void:
	if outline > 0:
		ci.draw_string_outline(G.font_cn, p, s, align, width, size, outline, G.INK)
	ci.draw_string(G.font_cn, p, s, align, width, size, col)


static func _btn(ci: CanvasItem, buttons: Array, r: Rect2, label: String, b: Dictionary, fill: Color, enabled := true) -> void:
	_panel(ci, r, fill if enabled else Color(0.5, 0.47, 0.5), 4.0, 5.0)
	_txt(ci, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 11), label, 30, G.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if enabled:
		b["r"] = r
		buttons.append(b)


## Draws the settings rows inside r and appends tap targets {id:"set", key, op} to buttons.
static func draw(ci: CanvasItem, r: Rect2, buttons: Array) -> void:
	var rh := minf(96.0, (r.size.y - 20.0) / ROWS.size())
	for i in ROWS.size():
		var row: Array = ROWS[i]
		var k := String(row[0])
		var rr := Rect2(r.position.x, r.position.y + i * rh, r.size.x, rh - 12)
		_panel(ci, rr, Color(1, 0.97, 0.9), 3.0, 4.0)
		_txt(ci, Vector2(rr.position.x + 26, rr.position.y + rr.size.y * 0.5 + 12), String(row[1]), 32, G.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
		var v = value(k)
		var bx := rr.end.x - 20
		var bh := rr.size.y - 16
		var by := rr.position.y + 8
		match String(row[2]):
			"num":
				var n := int(v)
				_btn(ci, buttons, Rect2(bx - bh, by, bh, bh), "+", {"id": "set", "key": k, "op": 1}, G.BLUE, n < int(row[4]))
				_txt(ci, Vector2(bx - bh - 150, by + bh * 0.5 + 13), "%d%%" % n, 36, G.RED, HORIZONTAL_ALIGNMENT_CENTER, 140, 0)
				_btn(ci, buttons, Rect2(bx - bh * 2 - 160, by, bh, bh), "-", {"id": "set", "key": k, "op": -1}, G.BLUE, n > int(row[3]))
				var bar := Rect2(rr.position.x + 220, rr.get_center().y - 9, maxf(bx - bh * 2 - 190 - (rr.position.x + 220), 40), 18)
				ci.draw_rect(bar, Color(0.8, 0.76, 0.7))
				ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * n / float(row[4]), bar.size.y)), G.ORANGE)
				ci.draw_rect(bar, G.INK, false, 3.0)
			"bool":
				var on := bool(v)
				_btn(ci, buttons, Rect2(bx - 200, by, 200, bh), "开" if on else "关", {"id": "set", "key": k, "op": 0}, G.GREEN if on else Color(0.45, 0.4, 0.48))
			"enum":
				var opts: Array = row[3]
				var labels: Array = row[4]
				var w := 190.0
				for j in opts.size():
					var on: bool = String(v) == String(opts[j])
					_btn(ci, buttons, Rect2(bx - (opts.size() - j) * (w + 12), by, w, bh), String(labels[j]), {"id": "set", "key": k, "val": opts[j]}, G.RED if on else Color(0.45, 0.4, 0.48))


static func act(b: Dictionary) -> void:
	var k := String(b["key"])
	var st: Dictionary = Meta.data["settings"]
	for row in ROWS:
		if row[0] != k:
			continue
		match String(row[2]):
			"num":
				st[k] = clampi(int(st[k]) + int(b["op"]) * int(row[5]), int(row[3]), int(row[4]))
			"bool":
				st[k] = not bool(st[k])
			"enum":
				st[k] = b["val"]
	Meta.apply_settings()
	Meta.save()
	Sfx.play("click")
