class_name FxSlash
extends Node2D
## Crescent swipe arc with ink outline.

var dir := Vector2.RIGHT
var radius := 90.0
var arc := 2.0
var kind := ""
var col := Color.WHITE
var t := 0.0
var life := 0.16


func _ready() -> void:
	if kind == "big":
		life = 0.22


func _process(dt: float) -> void:
	t += dt
	if t >= life:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var k := t / life
	var sweep := minf(k / 0.3, 1.0)
	if sweep < 0.08:
		return
	var fade := 1.0 - maxf(k - 0.3, 0.0) / 0.7
	var thick := radius * (0.42 if kind == "big" else 0.3) * fade
	var a0 := dir.angle() - arc * 0.5
	var n := 18
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in n + 1:
		var f := float(i) / float(n)
		var ang := a0 + arc * f * sweep
		var taper := maxf(sin(f * PI), 0.1)
		outer.append(Vector2.from_angle(ang) * radius)
		inner.append(Vector2.from_angle(ang) * (radius - thick * taper))
	inner.reverse()
	var poly := outer.duplicate()
	poly.append_array(inner)
	var c := Color(col.r, col.g, col.b, 0.95)
	if thick < 2.0 or Geometry2D.triangulate_polygon(poly).is_empty():
		draw_polyline(outer, Color(0.07, 0.05, 0.09, fade), 4.0)
		return
	Ink.shape(self, poly, c, 4.0)
	for i in 4:
		var ang := a0 + arc * sweep * (0.15 + 0.23 * i)
		var p0 := Vector2.from_angle(ang) * radius * 1.06
		var p1 := Vector2.from_angle(ang) * radius * (1.25 + 0.1 * (i % 2))
		draw_line(p0, p1, Color(0.07, 0.05, 0.09, fade), 3.0)
