class_name FxGhost
extends Node2D
## After-image of a stick pose (dash trails).

var pose := {}
var facing := 1.0
var t := 0.0
var life := 0.22
var col := Color(0.3, 0.8, 1.0)


func _process(dt: float) -> void:
	t += dt
	if t >= life:
		queue_free()
	queue_redraw()


func _draw() -> void:
	if pose.is_empty():
		return
	var a := (1.0 - t / life) * 0.55
	var c := Color(col.r, col.g, col.b, a)
	Stick.draw(self, pose, facing, Vector2.ZERO, c, c, Color(col.r, col.g, col.b, a * 0.5), 8.0, Color(0, 0, 0, 0))
