class_name Ink
extends RefCounted
## Hand-drawn comic ink helpers: thick outlines, line boil, shadows.

const INK := Color(0.07, 0.05, 0.09)


static func seed_now() -> int:
	return int(Time.get_ticks_msec() / 120)


static func rnd(i: int, s: int) -> float:
	return fposmod(sin(float(i) * 12.9898 + float(s) * 78.233) * 43758.5453, 1.0) * 2.0 - 1.0


static func wobble(pts: PackedVector2Array, amt: float, salt: int = 0) -> PackedVector2Array:
	var s := seed_now() + salt
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = pts[i] + Vector2(rnd(i, s), rnd(i + 97, s)) * amt
	return out


static func shape(ci: CanvasItem, pts: PackedVector2Array, fill: Color, w: float = 4.0, ink: Color = INK) -> void:
	if pts.size() < 3:
		return
	ci.draw_colored_polygon(pts, fill)
	outline(ci, pts, w, ink)


static func outline(ci: CanvasItem, pts: PackedVector2Array, w: float, ink: Color = INK) -> void:
	if pts.size() < 2:
		return
	var c := pts.duplicate()
	c.append(pts[0])
	if pts.size() > 2:
		c.append(pts[1])
	ci.draw_polyline(c, ink, w)


static func circle(ci: CanvasItem, c: Vector2, r: float, fill: Color, w: float = 4.0, ink: Color = INK) -> void:
	ci.draw_circle(c, r + w * 0.5, ink, true, -1.0, false)
	ci.draw_circle(c, maxf(r - w * 0.5, 0.5), fill, true, -1.0, false)


static func shadow(ci: CanvasItem, c: Vector2, rx: float, ry: float, a: float = 0.28) -> void:
	if rx <= 0.5:
		return
	ci.draw_set_transform(c, 0.0, Vector2(1.0, ry / rx))
	ci.draw_circle(Vector2.ZERO, rx, Color(0.12, 0.05, 0.14, a), true, -1.0, false)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func ellipse(c: Vector2, rx: float, ry: float, n: int = 20) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out


static func star(c: Vector2, r_out: float, r_in: float, n: int, rot: float = 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n * 2:
		var a := rot + PI * float(i) / float(n)
		var r := r_out if i % 2 == 0 else r_in
		out.append(c + Vector2.from_angle(a) * r)
	return out


static func burst(c: Vector2, rx: float, ry: float, n: int, jag: float, salt: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n * 2:
		var a := PI * float(i) / float(n)
		var k := 1.0 if i % 2 == 0 else (1.0 - jag)
		k *= 1.0 + 0.12 * rnd(i, salt)
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry) * k)
	return out


static func limb(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, col: Color, w: float) -> void:
	ci.draw_polyline(PackedVector2Array([a, b, c]), col, w)
	ci.draw_circle(a, w * 0.5, col, true, -1.0, false)
	ci.draw_circle(b, w * 0.5, col, true, -1.0, false)
	ci.draw_circle(c, w * 0.5, col, true, -1.0, false)


static func hatch(ci: CanvasItem, c: Vector2, r: float, n: int, col: Color, w: float = 2.0) -> void:
	for i in n:
		var f := (float(i) + 0.5) / float(n) * 2.0 - 1.0
		var o := Vector2(f * r, 0).rotated(-0.8)
		var d := Vector2(0, r * sqrt(maxf(1.0 - f * f, 0.0)) * 0.8).rotated(-0.8)
		ci.draw_line(c + o - d, c + o + d, col, w)
