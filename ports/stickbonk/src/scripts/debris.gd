class_name Debris
extends Node2D
## Lightweight comic particles: sparks, dust puffs, ink drops, stars.

var parts: Array = []


func add(p: Vector2, v: Vector2, kind: String, life: float, size: float, col: Color, z: float = 0.0, vz: float = 0.0) -> void:
	if parts.size() > (320 if G.low else 700):
		return
	parts.append({"p": p, "v": v, "kind": kind, "life": life, "max": life, "size": size, "col": col, "z": z, "vz": vz, "rot": randf() * TAU})


func sparks(pos: Vector2, dir: Vector2, n: int, col: Color) -> void:
	for i in n:
		var v := dir.rotated(randf_range(-1.0, 1.0)) * randf_range(350, 1000)
		add(pos, v, "spark", randf_range(0.1, 0.24), randf_range(12, 26), col)


func dust(pos: Vector2, n: int, spread: float = 30.0) -> void:
	for i in n:
		var a := randf() * TAU
		var p := pos + Vector2.from_angle(a) * randf() * spread
		add(p, Vector2.from_angle(a) * randf_range(40, 160), "dust", randf_range(0.35, 0.7), randf_range(9, 20), Color(0.97, 0.94, 0.86))


func ink_spray(pos: Vector2, dir: Vector2, n: int, col: Color, height: float) -> void:
	for i in n:
		var v := (dir * randf_range(80, 420)).rotated(randf_range(-1.2, 1.2)) + Vector2.from_angle(randf() * TAU) * 80.0
		add(pos, v, "drop", 2.0, randf_range(3, 8), col, height, randf_range(150, 500))


func stars(pos: Vector2, n: int) -> void:
	for i in n:
		add(pos, Vector2.from_angle(randf() * TAU) * randf_range(120, 300), "star", randf_range(0.35, 0.6), randf_range(8, 14), Color(1, 0.9, 0.2))


func _process(dt: float) -> void:
	var i := parts.size() - 1
	while i >= 0:
		var p: Dictionary = parts[i]
		p["life"] = float(p["life"]) - dt
		var kind: String = p["kind"]
		var v: Vector2 = p["v"]
		p["p"] = (p["p"] as Vector2) + v * dt
		match kind:
			"spark":
				p["v"] = v * exp(-6.0 * dt)
			"dust":
				p["v"] = v * exp(-5.0 * dt)
			"star":
				p["v"] = v * exp(-3.0 * dt)
				p["rot"] = float(p["rot"]) + dt * 8.0
			"drop":
				var vz: float = float(p["vz"]) - 1500.0 * dt
				var z: float = float(p["z"]) + vz * dt
				p["vz"] = vz
				p["z"] = z
				if z <= 0.0:
					if G.decals != null and randf() < 0.5:
						G.decals.dot(p["p"], float(p["size"]) * randf_range(0.8, 1.6), p["col"])
					p["life"] = -1.0
		if float(p["life"]) <= 0.0:
			parts[i] = parts[parts.size() - 1]
			parts.pop_back()
		i -= 1
	queue_redraw()


func _draw() -> void:
	var ink := Color(0.07, 0.05, 0.09)
	for p in parts:
		var k: float = float(p["life"]) / float(p["max"])
		var pos: Vector2 = p["p"]
		var col: Color = p["col"]
		var size: float = p["size"]
		match p["kind"]:
			"spark":
				var v: Vector2 = p["v"]
				var tail := pos - v.normalized() * size * (0.5 + k)
				draw_line(tail, pos, ink, 8.0 * k + 2.0)
				draw_line(tail, pos, col, 4.0 * k + 1.0)
			"dust":
				var r := size * (1.0 + (1.0 - k) * 1.2)
				draw_circle(pos, r + 2.0, Color(ink.r, ink.g, ink.b, k * 0.6), true, -1.0, false)
				draw_circle(pos, r, Color(col.r, col.g, col.b, k), true, -1.0, false)
			"drop":
				var z: float = p["z"]
				draw_circle(pos + Vector2(0, -z), size, col, true, -1.0, false)
			"star":
				Ink.shape(self, Ink.star(pos, size, size * 0.4, 4, float(p["rot"])), Color(col.r, col.g, col.b, k), 2.5, Color(ink.r, ink.g, ink.b, k))