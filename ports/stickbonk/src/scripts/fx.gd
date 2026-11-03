class_name FxText
extends Node2D
## Comic "POW!" bursts and damage numbers.

var text := ""
var col := Color.YELLOW
var size := 32
var burst := true
var life := 0.75
var t := 0.0
var vel := Vector2(0, -50)
var rot := 0.0
var pts := PackedVector2Array()
var salt := 0


func _ready() -> void:
	salt = randi() % 1000
	if burst:
		rot = randf_range(-0.28, 0.28)
		var w := G.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		pts = Ink.burst(Vector2(0, -size * 0.32), w * 0.5 + size * 0.75, size * 1.05, 9, 0.32, salt)


func _process(dt: float) -> void:
	t += dt
	position += vel * dt
	if not burst:
		vel.y += 420.0 * dt
	if t >= life:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var k := t / life
	var s := 1.0
	if k < 0.12:
		s = lerpf(0.2, 1.3, k / 0.12)
	elif k < 0.26:
		s = lerpf(1.3, 1.0, (k - 0.12) / 0.14)
	var a := 1.0 if k < 0.7 else 1.0 - (k - 0.7) / 0.3
	draw_set_transform(Vector2.ZERO, rot, Vector2(s, s))
	if burst:
		var back := Color(1, 1, 1, a) if col != Color.WHITE else Color(0.95, 0.2, 0.2, a)
		var shadow := pts.duplicate()
		for i in shadow.size():
			shadow[i] += Vector2(6, 6)
		draw_colored_polygon(shadow, Color(0.07, 0.05, 0.09, a * 0.8))
		Ink.shape(self, pts, back, 4.0, Color(0.07, 0.05, 0.09, a))
	var c := Color(col.r, col.g, col.b, a)
	var ol := 10 if burst else 6
	draw_string_outline(G.font, Vector2(-1000, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 2000, size, ol, Color(0.07, 0.05, 0.09, a))
	draw_string(G.font, Vector2(-1000, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 2000, size, c)