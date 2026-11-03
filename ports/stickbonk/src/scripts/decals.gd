class_name Decals
extends Node2D
## Persistent ground marks: ink splats, cracks, craters.

var items: Array = []


func _ready() -> void:
	z_index = -5


func splat(pos: Vector2, size: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var n := 14
	var salt := randi() % 1000
	for i in n:
		var a := TAU * i / float(n)
		var r := size * (0.6 + 0.35 * absf(Ink.rnd(i, salt)))
		if i % 3 == 0:
			r *= 1.5
		pts.append(pos + Vector2(cos(a) * r, sin(a) * r * 0.55))
	items.append({"t": "poly", "pts": pts, "col": Color(col.darkened(0.25), 0.85)})
	for i in 5:
		var a := randf() * TAU
		var d := size * randf_range(1.0, 2.0)
		dot(pos + Vector2(cos(a) * d, sin(a) * d * 0.55), size * randf_range(0.08, 0.2), col.darkened(0.25))
	_trim()


func dot(pos: Vector2, r: float, col: Color) -> void:
	items.append({"t": "dot", "p": pos, "r": r, "col": Color(col, 0.85)})
	_trim()


func crack(pos: Vector2, r: float) -> void:
	var lines := []
	var n := randi_range(5, 8)
	for i in n:
		var a := TAU * i / float(n) + randf_range(-0.3, 0.3)
		var pl := PackedVector2Array([pos])
		var p := pos
		var segs := randi_range(3, 5)
		for s in segs:
			a += randf_range(-0.5, 0.5)
			p += Vector2(cos(a), sin(a) * 0.6) * r / float(segs) * randf_range(0.7, 1.3)
			pl.append(p)
		lines.append(pl)
	items.append({"t": "crack", "lines": lines})
	_trim()


func crater(pos: Vector2, r: float) -> void:
	items.append({"t": "crater", "p": pos, "r": r})
	crack(pos, r * 1.4)


var dirty := false
var redraw_t := 0.0


func _trim() -> void:
	while items.size() > (120 if G.low else 220):
		items.pop_front()
	dirty = true


func _process(dt: float) -> void:
	redraw_t -= dt
	if dirty and redraw_t <= 0.0:
		dirty = false
		redraw_t = 0.15
		queue_redraw()


func _draw() -> void:
	var ink := Color(0.07, 0.05, 0.09)
	for it in items:
		match it["t"]:
			"poly":
				var pts: PackedVector2Array = it["pts"]
				draw_colored_polygon(pts, it["col"])
				Ink.outline(self, pts, 2.0, Color(ink, 0.7))
			"dot":
				draw_circle(it["p"], it["r"], it["col"], true, -1.0, false)
			"crack":
				for pl in it["lines"]:
					draw_polyline(pl, Color(ink, 0.75), 3.0)
			"crater":
				var p: Vector2 = it["p"]
				var r: float = it["r"]
				var e := Ink.ellipse(p, r, r * 0.55, 24)
				draw_colored_polygon(e, Color(0.35, 0.27, 0.22, 0.7))
				Ink.outline(self, e, 4.0, Color(ink, 0.8))
				var e2 := Ink.ellipse(p + Vector2(0, r * 0.08), r * 0.7, r * 0.36, 20)
				draw_colored_polygon(e2, Color(0.2, 0.14, 0.12, 0.7))