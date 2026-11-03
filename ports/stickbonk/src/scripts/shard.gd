class_name Shard
extends Node2D
## A broken chunk of a monster/prop. Fake-3D physics: ground plane + height (z), bounces, spins, settles, fades.

var poly := PackedVector2Array()
var uvs := PackedVector2Array()
var texture: Texture2D = null
var col := Color.WHITE
var linear_velocity := Vector2.ZERO
var angular_velocity := 0.0
var z := 0.0
var vz := 0.0
var t := 0.0
var life := 0.0
var settled := false


func _ready() -> void:
	life = randf_range(5.0, 8.0)


func _process(dt: float) -> void:
	t += dt
	if not settled:
		vz -= 2000.0 * dt
		z += vz * dt
		position += linear_velocity * dt
		rotation += angular_velocity * dt
		if z <= 0.0:
			z = 0.0
			if absf(vz) > 160.0:
				vz = -vz * 0.42
				linear_velocity *= 0.6
				angular_velocity *= 0.6
				if G.particles != null and randf() < 0.3:
					G.particles.dust(position, 1, 6)
			else:
				vz = 0.0
				linear_velocity *= exp(-7.0 * dt)
				angular_velocity *= exp(-7.0 * dt)
				if linear_velocity.length() < 8.0:
					settled = true
		else:
			linear_velocity *= exp(-0.6 * dt)
		if not G.ARENA.has_point(position):
			linear_velocity = -linear_velocity * 0.5
			position.x = clampf(position.x, G.ARENA.position.x, G.ARENA.end.x)
			position.y = clampf(position.y, G.ARENA.position.y, G.ARENA.end.y)
	elif linear_velocity.length() > 10.0 or vz > 0.0:
		settled = false
	if t > life:
		modulate.a = 1.0 - (t - life) / 0.6
		if t > life + 0.6:
			G.shards.erase(self)
			queue_free()
	if (not settled or t > life) and G.on_screen(position):
		queue_redraw()


func _draw() -> void:
	var rot := rotation
	draw_set_transform(Vector2.ZERO, -rot, Vector2.ONE)
	var sr := 8.0 + absf(z) * 0.0
	if z < 300.0:
		Ink.shadow(self, Vector2.ZERO, sr * (1.0 - z / 600.0), sr * 0.35 * (1.0 - z / 600.0), 0.22)
	draw_set_transform(Vector2(0, -z), rot, Vector2.ONE)
	if texture != null and uvs.size() == poly.size():
		# the real hand-drawn art, broken along the cut, with a fresh ink edge on the break
		var cols := PackedColorArray()
		cols.resize(poly.size())
		cols.fill(Color.WHITE)
		draw_polygon(poly, cols, uvs, texture)
		var closed := poly.duplicate()
		closed.append(poly[0])
		draw_polyline(closed, G.INK, 3.0)
		return
	Ink.shape(self, poly, col, 3.0)
	if poly.size() > 2:
		draw_line(poly[0] * 0.6, poly[1] * 0.6, Color(1, 1, 1, 0.35), 2.0)