class_name FxRing
extends Node2D
## Expanding shockwave ring.

var r0 := 10.0
var r1 := 120.0
var col := Color.WHITE
var life := 0.3
var width := 12.0
var kind := ""
var t := 0.0


func _process(dt: float) -> void:
	t += dt
	if t >= life:
		queue_free()
	queue_redraw()


func _draw() -> void:
	if t >= life:
		return
	var k := clampf(t / life, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	var r := lerpf(r0, r1, e)
	var w := width * (1.0 - k) + 2.0
	var ink := Color(0.07, 0.05, 0.09, 1.0 - k * 0.5)
	draw_arc(Vector2.ZERO, r, 0, TAU, 72, ink, w + 7.0)
	draw_arc(Vector2.ZERO, r, 0, TAU, 72, Color(col.r, col.g, col.b, 1.0 - k * 0.3), w)
	if kind == "shock":
		for i in 14:
			var a := TAU * i / 14.0 + r * 0.004
			draw_line(Vector2.from_angle(a) * (r * 0.72), Vector2.from_angle(a) * (r * 0.9), ink, 3.0)
