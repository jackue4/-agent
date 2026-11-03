class_name FxBolt
extends Node2D
## Jagged comic lightning bolt between two points.

var a := Vector2.ZERO
var b := Vector2.ZERO
var col := Color.YELLOW
var t := 0.0
var life := 0.22
var pts := PackedVector2Array()
var regen := 0.0


func _ready() -> void:
	z_index = 2
	_build()


func _build() -> void:
	pts = PackedVector2Array()
	var n := maxi(int(a.distance_to(b) / 26.0), 3)
	var nrm := (b - a).normalized().orthogonal()
	for i in n + 1:
		var f := float(i) / float(n)
		var j := 0.0 if i == 0 or i == n else randf_range(-22, 22)
		pts.append(a.lerp(b, f) + nrm * j)


func _process(dt: float) -> void:
	t += dt
	regen -= dt
	if regen <= 0:
		regen = 0.035
		_build()
	if t >= life:
		queue_free()
	queue_redraw()


func _draw() -> void:
	if t >= life or pts.size() < 2:
		return
	var k := clampf(1.0 - t / life, 0.0, 1.0)
	draw_polyline(pts, Color(0.07, 0.05, 0.09), 14.0 * k + 4.0)
	draw_polyline(pts, col, 8.0 * k + 2.0)
	draw_polyline(pts, Color.WHITE, 3.0 * k + 1.0)
	draw_circle(b, 20.0 * k, Color(1, 1, 0.8, 0.8), true, -1.0, false)
