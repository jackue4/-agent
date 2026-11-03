class_name Prop
extends Node2D
## Breakable scenery (crates, barrels, rocks, hydrants) that shatters on hit.

var kind := "crate"
var hp := 30.0
var radius := 26.0
var dead := false
var flash := 0.0
var shake_t := 0.0
var col := Color(0.8, 0.55, 0.3)
var salt := 0
var t := 0.0
var type := "prop"
var mass := 99.0
var z := 0.0


func _ready() -> void:
	salt = randi() % 1000
	match kind:
		"crate":
			col = Color(0.85, 0.6, 0.32)
			hp = 25.0
			radius = 28.0
		"barrel":
			col = Color(0.9, 0.3, 0.25)
			hp = 18.0
			radius = 24.0
		"rock":
			col = Color(0.62, 0.6, 0.66)
			hp = 60.0
			radius = 34.0
		"hydrant":
			col = Color(0.95, 0.8, 0.2)
			hp = 30.0
			radius = 18.0
		"bamboo":
			col = Color(0.45, 0.75, 0.3)
			hp = 22.0
			radius = 22.0
		"obsidian":
			col = Color(0.25, 0.2, 0.3)
			hp = 70.0
			radius = 30.0
		"icecrystal":
			col = Color(0.6, 0.88, 1.0)
			hp = 26.0
			radius = 26.0
	G.props.append(self)


func _process(dt: float) -> void:
	t += dt
	flash -= dt
	shake_t -= dt
	if flash > -0.1 or shake_t > 0.0:
		queue_redraw()


func take_hit(amount: float, dir: Vector2, kb: float, _up: float, _crit: bool) -> bool:
	if dead:
		return false
	hp -= amount
	flash = 0.08
	shake_t = 0.15
	G.particles.sparks(position + Vector2(0, -radius), dir, 3, G.WHITE)
	if hp <= 0.0:
		dead = true
		G.props.erase(self)
		if Art.has("prop_" + kind):
			G.shatter_sprite("prop_" + kind, Transform2D(0.0, position), radius, 1.0, col, dir, clampf(kb, 500.0, 1000.0), position.y, 11)
		else:
			G.shatter(_poly_world(), col, dir, clampf(kb, 500.0, 1000.0), position.y, 9)
		G.particles.dust(position, 10, radius)
		Sfx.play("shatter", -2.0)
		G.shake(0.2)
		G.spawn_text(position + Vector2(0, -radius * 2.5), "KRAK!", G.WHITE, 30)
		if kind == "barrel" and G.player != null:
			G.player.skill_runner.explode(position, 150.0, 40.0, G.ORANGE)
			G.decals.crater(position, 50)
		if kind == "icecrystal" and G.player != null:
			G.player.skill_runner.explode(position, 160.0, 20.0, Color(0.6, 0.9, 1.0), "frost")
		if kind == "obsidian" and G.player != null:
			G.player.skill_runner.explode(position, 140.0, 30.0, G.ORANGE, "fire")
		if kind == "bamboo":
			for i in 5:
				G.particles.add(position + Vector2(0, -radius * 2.0), Vector2.from_angle(randf() * TAU) * randf_range(120, 320), "star", 0.6, 12, Color(0.4, 0.75, 0.3))
		if randf() < 0.35:
			if randf() < 0.3:
				G.drop_heart(position)
			else:
				G.drop_xp(position, 4)
		queue_free()
		return true
	return false


func _poly() -> PackedVector2Array:
	var r := radius
	match kind:
		"crate":
			return PackedVector2Array([Vector2(-r, 0), Vector2(r, 0), Vector2(r, -r * 1.7), Vector2(-r, -r * 1.7)])
		"barrel":
			var pts := PackedVector2Array()
			for i in 6:
				var f := float(i) / 5.0
				pts.append(Vector2(-r * (0.85 + 0.15 * sin(f * PI)), -f * r * 2.2))
			for i in 6:
				var f := 1.0 - float(i) / 5.0
				pts.append(Vector2(r * (0.85 + 0.15 * sin(f * PI)), -f * r * 2.2))
			return pts
		"rock":
			return PackedVector2Array([Vector2(-r * 1.1, 0), Vector2(-r * 0.9, -r * 0.8), Vector2(-r * 0.3, -r * 1.3), Vector2(r * 0.5, -r * 1.2), Vector2(r * 1.1, -r * 0.6), Vector2(r * 1.15, 0)])
		"bamboo":
			return PackedVector2Array([Vector2(-r * 0.6, 0), Vector2(-r * 0.6, -r * 2.8), Vector2(r * 0.6, -r * 2.8), Vector2(r * 0.6, 0)])
		"obsidian":
			return PackedVector2Array([Vector2(-r, 0), Vector2(-r * 0.8, -r * 1.1), Vector2(-r * 0.2, -r * 1.9), Vector2(r * 0.5, -r * 1.4), Vector2(r, 0)])
		"icecrystal":
			return PackedVector2Array([Vector2(-r * 0.9, 0), Vector2(-r * 0.6, -r * 1.4), Vector2(0, -r * 2.3), Vector2(r * 0.6, -r * 1.4), Vector2(r * 0.9, 0)])
		"hydrant":
			return PackedVector2Array([Vector2(-r * 0.8, 0), Vector2(-r * 0.8, -r * 1.6), Vector2(-r * 1.2, -r * 1.6), Vector2(-r * 1.2, -r * 2.0), Vector2(-r * 0.7, -r * 2.0), Vector2(-r * 0.5, -r * 2.7), Vector2(r * 0.5, -r * 2.7), Vector2(r * 0.7, -r * 2.0), Vector2(r * 1.2, -r * 2.0), Vector2(r * 1.2, -r * 1.6), Vector2(r * 0.8, -r * 1.6), Vector2(r * 0.8, 0)])
	return PackedVector2Array()


func _poly_world() -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in _poly():
		out.append(p + position)
	return out


func _draw() -> void:
	var off := Vector2(randf_range(-3, 3), 0) if shake_t > 0.0 else Vector2.ZERO
	Ink.shadow(self, Vector2.ZERO, radius * 1.2, radius * 0.4)
	if Art.has("prop_" + kind):
		set_meta("_xf", Transform2D(0.0, off))
		Art.draw(self, "prop_" + kind, radius, 1.0, Color.WHITE, 1.0 if flash > 0.0 else 0.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	draw_set_transform(off, 0.0, Vector2.ONE)
	var fill := Color.WHITE if flash > 0.0 else col
	var poly := _poly()
	Ink.shape(self, poly, fill, 5.0)
	var r := radius
	var ink := G.INK
	match kind:
		"crate":
			draw_line(Vector2(-r, 0), Vector2(r, -r * 1.7), ink, 4.0)
			draw_line(Vector2(-r, -r * 1.7), Vector2(r, 0), ink, 4.0)
			draw_rect(Rect2(-r + 5, -r * 1.7 + 5, r * 2 - 10, r * 1.7 - 10), ink, false, 3.0)
		"barrel":
			draw_line(Vector2(-r, -r * 0.6), Vector2(r, -r * 0.6), ink, 4.0)
			draw_line(Vector2(-r, -r * 1.6), Vector2(r, -r * 1.6), ink, 4.0)
			Ink.shape(self, Ink.star(Vector2(0, -r * 1.1), 12, 5, 5, -PI / 2), G.YELLOW, 2.5)
		"rock":
			Ink.hatch(self, Vector2(r * 0.4, -r * 0.45), r * 0.4, 4, Color(0, 0, 0, 0.3), 2.0)
		"hydrant":
			draw_circle(Vector2(0, -r * 1.8), r * 0.25, ink, true, -1.0, false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)