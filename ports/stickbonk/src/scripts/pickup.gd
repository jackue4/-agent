class_name Pickup
extends Node2D
## XP gems & hearts with a pop-out arc, then magnet into the player.

var kind := "xp"
var value := 1
var vel := Vector2.ZERO
var z := 0.0
var vz := 0.0
var t := 0.0
var magnet := false


func _ready() -> void:
	G.pickup_count += 1


func _exit_tree() -> void:
	G.pickup_count -= 1


func _process(dt: float) -> void:
	t += dt
	var pl := G.player
	if z > 0.0 or vz > 0.0:
		vz -= 1500.0 * dt
		z = maxf(z + vz * dt, 0.0)
		if z == 0.0:
			vz = 0.0
	position += vel * dt
	vel *= exp(-5.0 * dt)
	if pl != null and not pl.dead and t > 0.35:
		var d := pl.position - position
		var l := d.length()
		if l < pl.pickup_r or magnet:
			magnet = true
			vel = d.normalized() * (500.0 + t * 400.0)
		if l < 26.0:
			if kind == "xp":
				pl.add_xp(value)
				Sfx.play("pickup", -10.0, 0.3)
			else:
				pl.heal(value)
				Sfx.play("levelup", -8.0)
			queue_free()
			return
	if G.on_screen(position) and (z > 0.0 or Engine.get_process_frames() % 3 == get_instance_id() % 3):
		queue_redraw()


func _draw() -> void:
	var y := -z - 10.0 - sin(t * 5.0) * 3.0
	draw_rect(Rect2(-7, -2, 14, 4), Color(0.12, 0.05, 0.14, 0.25))
	var tid := "pickup_gem" if kind == "xp" else "pickup_heart"
	var tx := Art.tex(tid)
	if tx != null:
		var sz := 22.0
		if kind == "xp":
			sz = 16.0 if value == 1 else (22.0 if value == 3 else (30.0 if value <= 10 else 38.0))
			var hue := Color(0.75, 0.95, 1.0) if value == 1 else (Color(0.6, 1.0, 0.6) if value == 3 else Color(1.0, 0.6, 1.0))
			draw_texture_rect(tx, Rect2(-sz * 0.5, y - sz * 0.6, sz, sz), false, hue)
		else:
			sz = 34.0
			var pulse := 1.0 + 0.08 * sin(t * 8.0)
			draw_texture_rect(tx, Rect2(-sz * 0.5 * pulse, y - sz * 0.75 * pulse, sz * pulse, sz * pulse), false)
		return
	if kind == "xp":
		var s := 6.0 if value == 1 else (9.0 if value == 3 else (13.0 if value <= 10 else 17.0))
		var c := Color(0.3, 0.75, 1.0) if value == 1 else (Color(0.4, 1.0, 0.5) if value == 3 else Color(1.0, 0.45, 0.9))
		var o := s + 3.0
		draw_colored_polygon(PackedVector2Array([Vector2(0, y - o * 1.3), Vector2(o, y), Vector2(0, y + o * 1.1), Vector2(-o, y)]), G.INK)
		draw_colored_polygon(PackedVector2Array([Vector2(0, y - s * 1.3), Vector2(s, y), Vector2(0, y + s * 1.1), Vector2(-s, y)]), c)
		draw_line(Vector2(-s * 0.4, y - s * 0.2), Vector2(0, y - s * 0.9), Color(1, 1, 1, 0.8), 2.0)
	else:
		var h := PackedVector2Array()
		for i in 20:
			var a := TAU * i / 20.0
			var x := 16.0 * pow(sin(a), 3)
			var yy := -(13.0 * cos(a) - 5.0 * cos(2 * a) - 2.0 * cos(3 * a) - cos(4 * a))
			h.append(Vector2(x, yy) * 0.8 + Vector2(0, y - 4))
		Ink.shape(self, h, G.RED, 3.0)