extends Node2D
## Procedural placeholder / default art for 2D entities. Shimmers while an AI asset is pending.
const U = preload("res://util.gd")

var kind := "decor"
var shape := ""
var size := Vector2(100, 100)
var color := Color.WHITE
var pending := false
var failed := false
var t := 0.0
var facing := 1.0
var raised := false
const OUTLINE := Color(0.13, 0.08, 0.16, 0.9)
var _raise_k := 0.0

func _process(delta: float) -> void:
	t += delta
	if raised and _raise_k < 1.0:
		_raise_k = minf(1.0, _raise_k + delta * 2.5)
	if pending or kind in ["collectible", "powerup", "goal", "player", "enemy", "checkpoint"]:
		queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	var r := Rect2(-size * 0.5, size)
	var dark := color.darkened(0.35)
	var light := color.lightened(0.3)
	match kind:
		"platform":
			if shape == "cloud":
				_cloud(r, color)
			else:
				draw_rect(r, dark)
				draw_rect(Rect2(r.position + Vector2(0, 0), Vector2(w, minf(14.0, h * 0.4))), light)
				var step := 26.0
				var x := r.position.x + 8.0
				while x < r.end.x - 6.0:
					draw_circle(Vector2(x, r.position.y + minf(14.0, h * 0.4)), 5.0, light)
					x += step
				draw_rect(r, color.darkened(0.55), false, 3.0)
		"collectible":
			var s := absf(cos(t * 3.0))
			var cw := maxf(w * 0.5 * s, 3.0)
			var c := Color("#ffd23f") if color == Color("#ffd23f") else color
			if shape == "gem":
				var pts := PackedVector2Array([Vector2(0, -h * 0.5), Vector2(cw, -h * 0.1), Vector2(0, h * 0.5), Vector2(-cw, -h * 0.1)])
				draw_colored_polygon(pts, c)
				draw_polyline(pts + PackedVector2Array([pts[0]]), c.darkened(0.4), 3.0)
			elif shape == "star":
				_star(Vector2.ZERO, minf(w, h) * 0.5, c, t * 2.0)
			else:
				draw_set_transform(Vector2.ZERO, 0.0, Vector2(maxf(s, 0.08), 1.0))
				draw_circle(Vector2.ZERO, minf(w, h) * 0.5, c.darkened(0.25))
				draw_circle(Vector2.ZERO, minf(w, h) * 0.38, c)
				draw_rect(Rect2(-3, -h * 0.2, 6, h * 0.4), c.lightened(0.5))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"enemy":
			var sq := 1.0 + sin(t * 8.0) * 0.06
			draw_set_transform(Vector2(0, h * 0.5 * (1.0 - sq)), 0.0, Vector2(2.0 - sq, sq))
			var body := Rect2(-w * 0.5, -h * 0.5, w, h)
			draw_rect(Rect2(body.position + Vector2(w * 0.1, 0), Vector2(w * 0.8, h)), color)
			draw_circle(Vector2(0, -h * 0.1), minf(w, h) * 0.45, color)
			_eyes(Vector2(0, -h * 0.12), w, true)
			for i in 3:
				var fx := -w * 0.35 + i * w * 0.35
				draw_circle(Vector2(fx, h * 0.45), w * 0.12, dark)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"hazard":
			# metal spikes on a base plate, outlined, with a lit and a shaded face each
			var n := maxi(1, int(round(w / 26.0)))
			var sw := w / n
			var base_h := minf(6.0, h * 0.25)
			var tip_h := h * 1.25
			for i in n:
				var x0 := r.position.x + i * sw
				var tip := Vector2(x0 + sw * 0.5, r.end.y - tip_h)
				var outline_pts := PackedVector2Array([Vector2(x0 - 2, r.end.y - base_h + 1), tip + Vector2(0, -3), Vector2(x0 + sw + 2, r.end.y - base_h + 1)])
				draw_colored_polygon(outline_pts, OUTLINE)
				draw_colored_polygon(PackedVector2Array([Vector2(x0, r.end.y - base_h), tip, Vector2(x0 + sw * 0.5, r.end.y - base_h)]), color.lightened(0.35))
				draw_colored_polygon(PackedVector2Array([Vector2(x0 + sw * 0.5, r.end.y - base_h), tip, Vector2(x0 + sw, r.end.y - base_h)]), color.darkened(0.25))
			draw_rect(Rect2(r.position.x - 3, r.end.y - base_h - 1, w + 6, base_h + 2), OUTLINE)
			draw_rect(Rect2(r.position.x, r.end.y - base_h, w, base_h), Color("#5c5f6e"))
		"goal":
			draw_rect(Rect2(-w * 0.45, -h * 0.5, 7, h), Color("#5c3d2e"))
			var wave := sin(t * 4.0) * 6.0
			var fl := PackedVector2Array([Vector2(-w * 0.45 + 7, -h * 0.5), Vector2(w * 0.5, -h * 0.35 + wave), Vector2(-w * 0.45 + 7, -h * 0.18)])
			draw_colored_polygon(fl, color)
			draw_circle(Vector2(-w * 0.45 + 3.5, -h * 0.5), 7, Color("#ffd23f"))
			var glow := Color(1, 1, 0.6, 0.25 + 0.15 * sin(t * 3.0))
			draw_circle(Vector2(0, h * 0.5), w * 0.6, glow)
		"checkpoint":
			var pole_h := h
			draw_rect(Rect2(-w * 0.32 - 2, -h * 0.5 - 2, 10, h + 4), Color(0.13, 0.08, 0.16, 0.9))
			draw_rect(Rect2(-w * 0.32, -h * 0.5, 6, h), Color("#e9ecef"))
			draw_circle(Vector2(-w * 0.32 + 3, -h * 0.5), 8, Color("#ffd23f"))
			var k := ease(_raise_k, -2.0)
			var fy := lerpf(h * 0.32, -h * 0.46, k)
			var wv := sin(t * 5.0) * 5.0 * (0.3 + k)
			var flag := PackedVector2Array([Vector2(-w * 0.32 + 6, fy), Vector2(w * 0.5, fy + pole_h * 0.12 + wv), Vector2(-w * 0.32 + 6, fy + pole_h * 0.26)])
			draw_colored_polygon(flag, color)
			draw_polyline(flag + PackedVector2Array([flag[0]]), color.darkened(0.45), 2.5)
			draw_rect(Rect2(-w * 0.5, h * 0.5 - 10, w, 10), Color("#6c757d"))
			if raised:
				draw_circle(Vector2(0, 0), w * (0.6 + 0.08 * sin(t * 4.0)), Color(1, 0.9, 0.4, 0.12))
		"powerup":
			var pulse := 1.0 + 0.1 * sin(t * 6.0)
			draw_circle(Vector2.ZERO, minf(w, h) * 0.55 * pulse, Color(color, 0.3))
			_star(Vector2.ZERO, minf(w, h) * 0.45, color, t)
		"bouncer":
			draw_rect(Rect2(-w * 0.4, 0, w * 0.8, h * 0.5), Color("#555b6e"))
			for i in 3:
				draw_line(Vector2(-w * 0.3, h * 0.1 + i * h * 0.12), Vector2(w * 0.3, h * 0.16 + i * h * 0.12), Color("#c0c0c0"), 3.0)
			draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h * 0.5), color)
		"sign":
			# wooden board on two posts; text is a child Label sized to the board
			var wood := Color("#c58b52") if color.s < 0.2 or color.h > 0.2 else color
			var post := Color("#7a4b2a")
			for sx in [-0.3, 0.3]:
				draw_rect(Rect2(w * sx - 6, -h * 0.1, 12, h * 0.6), OUTLINE)
				draw_rect(Rect2(w * sx - 4, -h * 0.1, 8, h * 0.6), post)
			var board := Rect2(-w * 0.5, -h * 0.5, w, h * 0.62)
			_round_rect_plain(board.grow(3), OUTLINE, 10)
			_round_rect_plain(board, wood, 8)
			for i in 3:
				var yy := board.position.y + board.size.y * (i + 1) / 4.0
				draw_line(Vector2(board.position.x + 6, yy), Vector2(board.end.x - 6, yy), wood.darkened(0.12), 2.0)
			draw_line(Vector2(board.position.x + 8, board.position.y + 4), Vector2(board.end.x - 8, board.position.y + 4), wood.lightened(0.25), 2.0)
		"player":
			var b := 1.0 + sin(t * 6.0) * 0.03
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(facing * (2.0 - b), b))
			_round_rect(Rect2(-w * 0.45, -h * 0.5, w * 0.9, h), color, w * 0.25)
			_eyes(Vector2(w * 0.1, -h * 0.15), w * 0.8, false)
			draw_rect(Rect2(-w * 0.45, h * 0.05, w * 0.9, h * 0.1), color.darkened(0.3))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"text":
			pass
		_:
			_decor(r)
	if pending:
		var a := 0.35 + 0.25 * sin(t * 5.0)
		draw_rect(r.grow(6), Color(1, 1, 1, a * 0.4))
		_dashed_rect(r.grow(8), Color(0.6, 0.4, 1.0, 0.9), t)
		var sx := r.position.x + fmod(t * 0.8, 1.0) * (w + 16) - 8
		draw_line(Vector2(sx, r.position.y - 8), Vector2(sx, r.end.y + 8), Color(1, 1, 1, 0.8), 4.0)
	if failed:
		draw_rect(r.grow(4), Color(1, 0.3, 0.3, 0.8), false, 2.0)

func _decor(r: Rect2) -> void:
	var w := r.size.x
	var h := r.size.y
	if color.is_equal_approx(U.default_color("decor")):
		color = DECOR_DEFAULTS.get(shape, color)
	match shape:
		"cloud":
			_cloud(r, color)
		"rock", "stone", "boulder":
			_rock(r)
		"bush":
			_bush(r)
		"flower":
			_flower(r)
		"box", "crate":
			_crate(r)
		"house", "building":
			_house(r)
		"pillar", "column", "tower":
			_pillar(r)
		"circle", "ball":
			draw_circle(Vector2.ZERO, minf(w, h) * 0.5, color)
		"tree", "":
			_tree(r)
		"pine":
			_pine(r)
		_:
			_tree(r)

## Storybook tree: outlined trunk + three-lobed canopy with highlight. Drawn bottom-anchored.
func _tree(r: Rect2) -> void:
	var w := r.size.x
	var h := r.size.y
	var leaf := color if color.g >= color.r else Color("#3d8b37")
	var trunk_w := w * 0.18
	var trunk := Rect2(-trunk_w * 0.5, -h * 0.05, trunk_w, h * 0.55)
	draw_rect(trunk.grow(3), OUTLINE)
	draw_rect(trunk, Color("#7a4b2a"))
	draw_rect(Rect2(trunk.position, Vector2(trunk_w * 0.35, trunk.size.y)), Color("#94603a"))
	var rad := minf(w * 0.42, h * 0.3)
	var lobes := [Vector2(-w * 0.22, -h * 0.12), Vector2(w * 0.22, -h * 0.12), Vector2(0, -h * 0.3)]
	for p in lobes:
		draw_circle(p, rad + 3.0, OUTLINE)
	for p in lobes:
		draw_circle(p, rad, leaf.darkened(0.12))
	draw_circle(Vector2(0, -h * 0.3), rad * 0.85, leaf)
	draw_circle(Vector2(-w * 0.12, -h * 0.36), rad * 0.35, leaf.lightened(0.25))

const DECOR_DEFAULTS := {"tree": Color("#5cae4a"), "": Color("#5cae4a"), "bush": Color("#5cae4a"), "pine": Color("#3f8f5a"), "house": Color("#f3e3c3"), "crate": Color("#c68b4e"), "box": Color("#c68b4e"), "pillar": Color("#ddd6c6"), "cloud": Color("#ffffff"), "rock": Color("#9aa0ac"), "flower": Color("#ff8fab")}

func _rock(r: Rect2) -> void:
	var w := r.size.x
	var h := r.size.y
	var c := color if color.s < 0.35 else Color("#9aa0ac")
	var pts := PackedVector2Array([Vector2(-w * 0.5, h * 0.5), Vector2(-w * 0.44, h * 0.0), Vector2(-w * 0.2, -h * 0.42), Vector2(w * 0.18, -h * 0.5), Vector2(w * 0.44, -h * 0.12), Vector2(w * 0.5, h * 0.5)])
	_outlined_poly(pts, c)
	# lit facet
	draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.2, -h * 0.42), Vector2(w * 0.18, -h * 0.5), Vector2(w * 0.05, -h * 0.05), Vector2(-w * 0.3, h * 0.05)]), c.lightened(0.18))
	draw_line(Vector2(w * 0.05, -h * 0.05), Vector2(w * 0.2, h * 0.5), c.darkened(0.25), 2.0)

func _bush(r: Rect2) -> void:
	var w := r.size.x
	var h := r.size.y
	var leaf := color if color.g >= color.r else Color("#4f9d3a")
	var lobes := [[Vector2(-w * 0.28, h * 0.12), w * 0.26], [Vector2(w * 0.28, h * 0.12), w * 0.26], [Vector2(0, -h * 0.08), w * 0.32]]
	for l in lobes:
		draw_circle(l[0], float(l[1]) + 3.0, OUTLINE)
	for l in lobes:
		draw_circle(l[0], l[1], leaf.darkened(0.1))
	draw_circle(Vector2(0, -h * 0.08), w * 0.27, leaf)
	draw_circle(Vector2(-w * 0.1, -h * 0.2), w * 0.09, leaf.lightened(0.25))
	draw_rect(Rect2(-w * 0.5, h * 0.3, w, h * 0.2), leaf.darkened(0.1))

func _flower(r: Rect2) -> void:
	var w := r.size.x
	var h := r.size.y
	var petal := color if color.s > 0.3 else Color("#ff8fab")
	var head := Vector2(0, -h * 0.15)
	draw_line(Vector2(0, h * 0.5), head, OUTLINE, 6.0)
	draw_line(Vector2(0, h * 0.5), head, Color("#4f9d3a"), 3.0)
	draw_circle(Vector2(w * 0.12, h * 0.22), w * 0.1, Color("#4f9d3a"))
	var pr := minf(w, h) * 0.16
	for i in 5:
		var p := head + Vector2.from_angle(TAU * i / 5.0 - PI / 2) * pr * 1.1
		draw_circle(p, pr + 2.0, OUTLINE)
	for i in 5:
		draw_circle(head + Vector2.from_angle(TAU * i / 5.0 - PI / 2) * pr * 1.1, pr, petal)
	draw_circle(head, pr * 0.7, Color("#ffd23f"))

func _crate(r: Rect2) -> void:
	var c := color if color.s < 0.7 else Color("#c68b4e")
	draw_rect(r.grow(3), OUTLINE)
	draw_rect(r, c)
	var t := minf(r.size.x, r.size.y) * 0.14
	var dk := c.darkened(0.3)
	draw_rect(Rect2(r.position, Vector2(r.size.x, t)), dk)
	draw_rect(Rect2(r.position + Vector2(0, r.size.y - t), Vector2(r.size.x, t)), dk)
	draw_rect(Rect2(r.position, Vector2(t, r.size.y)), dk)
	draw_rect(Rect2(r.position + Vector2(r.size.x - t, 0), Vector2(t, r.size.y)), dk)
	draw_line(r.position + Vector2(t, t), r.end - Vector2(t, t), dk, t * 0.8)
	draw_rect(Rect2(r.position + Vector2(t, t), Vector2(r.size.x - 2 * t, t * 0.4)), c.lightened(0.2))

func _house(r: Rect2) -> void:
	var w := r.size.x
	var h := r.size.y
	var wall := color if color.v > 0.5 else Color("#f3e3c3")
	var body := Rect2(-w * 0.4, -h * 0.05, w * 0.8, h * 0.55)
	draw_rect(body.grow(3), OUTLINE)
	draw_rect(body, wall)
	var roof := PackedVector2Array([Vector2(-w * 0.5, -h * 0.02), Vector2(0, -h * 0.5), Vector2(w * 0.5, -h * 0.02)])
	_outlined_poly(roof, Color("#e05a4f"))
	draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.5, -h * 0.02), Vector2(0, -h * 0.5), Vector2(-w * 0.05, -h * 0.02)]), Color("#ef7a6b"))
	var door := Rect2(-w * 0.09, h * 0.18, w * 0.18, h * 0.32)
	draw_rect(door.grow(2), OUTLINE)
	draw_rect(door, Color("#8a5a35"))
	var win := Rect2(w * 0.16, h * 0.06, w * 0.14, w * 0.14)
	draw_rect(win.grow(2), OUTLINE)
	draw_rect(win, Color("#ffe08a"))

func _pillar(r: Rect2) -> void:
	var c := color if color.s < 0.4 else Color("#d9d4c7")
	var w := r.size.x
	var body := Rect2(r.position.x + w * 0.15, r.position.y + r.size.y * 0.1, w * 0.7, r.size.y * 0.8)
	draw_rect(body.grow(3), OUTLINE)
	draw_rect(body, c)
	for i in 3:
		var x := body.position.x + body.size.x * (0.25 + i * 0.25)
		draw_line(Vector2(x, body.position.y + 4), Vector2(x, body.end.y - 4), c.darkened(0.15), 2.0)
	for y in [r.position.y, r.end.y - r.size.y * 0.1]:
		var cap := Rect2(r.position.x, y, w, r.size.y * 0.1)
		draw_rect(cap.grow(3), OUTLINE)
		draw_rect(cap, c.lightened(0.1))

func _outlined_poly(pts: PackedVector2Array, c: Color) -> void:
	var ctr := Vector2.ZERO
	for p in pts:
		ctr += p
	ctr /= pts.size()
	var grown := PackedVector2Array()
	for p in pts:
		grown.append(p + (p - ctr).normalized() * 3.0)
	draw_colored_polygon(grown, OUTLINE)
	draw_colored_polygon(pts, c)

func _pine(r: Rect2) -> void:
	var w := r.size.x
	var h := r.size.y
	var leaf := color if color.g >= color.r else Color("#2d6a4f")
	draw_rect(Rect2(-w * 0.08, h * 0.3, w * 0.16, h * 0.2), Color("#7a4b2a"))
	for i in 3:
		var y0 := h * 0.32 - i * h * 0.26
		var hw := w * (0.5 - i * 0.1)
		var tri := PackedVector2Array([Vector2(-hw, y0), Vector2(0, y0 - h * 0.4), Vector2(hw, y0)])
		draw_colored_polygon(PackedVector2Array([tri[0] + Vector2(-3, 2), tri[1] + Vector2(0, -3), tri[2] + Vector2(3, 2)]), OUTLINE)
		draw_colored_polygon(tri, leaf.darkened(0.08 * (2 - i)))

func _round_rect_plain(rr: Rect2, c: Color, rad: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(rad))
	sb.anti_aliasing = true
	draw_style_box(sb, rr)

func _cloud(r: Rect2, c: Color) -> void:
	var w := r.size.x
	var h := r.size.y
	draw_circle(Vector2(-w * 0.25, h * 0.1), h * 0.4, c)
	draw_circle(Vector2(w * 0.25, h * 0.1), h * 0.4, c)
	draw_circle(Vector2(0, -h * 0.1), h * 0.5, c)
	draw_rect(Rect2(-w * 0.25, h * 0.1, w * 0.5, h * 0.4), c)

func _star(c: Vector2, rad: float, col: Color, rot: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := rad if i % 2 == 0 else rad * 0.45
		pts.append(c + Vector2.from_angle(rot + TAU * i / 10.0 - PI / 2.0) * rr)
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, col.darkened(0.4), 2.0)

func _eyes(c: Vector2, w: float, angry: bool) -> void:
	var off := w * 0.17
	var er := w * 0.12
	for sx in [-1.0, 1.0]:
		var p := c + Vector2(sx * off, 0)
		draw_circle(p, er, Color.WHITE)
		draw_circle(p + Vector2(er * 0.3 * facing, er * 0.15), er * 0.5, Color.BLACK)
		if angry:
			draw_line(p + Vector2(-sx * er, -er * 1.4), p + Vector2(sx * er, -er * 0.8), Color.BLACK, 3.0)

func _round_rect(r: Rect2, c: Color, rad: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(rad))
	sb.border_color = c.darkened(0.45)
	sb.set_border_width_all(3)
	draw_style_box(sb, r)

func _dashed_rect(r: Rect2, c: Color, off: float) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var L := a.distance_to(b)
		var d := fmod(off * 30.0, 16.0)
		while d < L:
			draw_line(a.lerp(b, d / L), a.lerp(b, minf(d + 8.0, L) / L), c, 3.0)
			d += 16.0
