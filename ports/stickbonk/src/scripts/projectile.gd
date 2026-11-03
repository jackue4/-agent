class_name Projectile
extends Node2D
## Fireballs, meteors, enemy spit.

var kind := "fireball"
var vel := Vector2.ZERO
var damage := 10.0
var radius := 80.0
var size := 14.0
var hostile := false
var t := 0.0
var fuse := 1.0
var trail: Array = []
var elem := ""
var hit_ids := {}


func _process(dt: float) -> void:
	t += dt
	match kind:
		"fireball":
			position += vel * dt
			trail.push_front(position)
			if trail.size() > 8:
				trail.pop_back()
			if not G.query(position, size).is_empty() or t > 1.6:
				_explode()
				return
		"spit":
			position += vel * dt
			var pl := G.player
			if pl != null and not pl.dead and position.distance_to(pl.position) < 22.0:
				pl.take_damage(damage, position - vel)
				G.particles.ink_spray(position, vel.normalized(), 6, Color(0.6, 0.9, 0.2), 30)
				queue_free()
				return
			if t > 3.0:
				queue_free()
				return
		"meteor":
			if t >= fuse:
				_meteor_hit()
				return
		"shuriken":
			position += vel * dt
			for e in G.query(position + Vector2(0, 40), 26.0):
				if hit_ids.has(e.get_instance_id()):
					continue
				hit_ids[e.get_instance_id()] = true
				if G.player != null:
					G.player.deal_skill(e, damage, vel.normalized(), 300.0, 0.0)
			if t > 0.7:
				queue_free()
				return
		"rock":
			if t >= fuse:
				_rock_hit()
				return
	queue_redraw()


## Volcano eruption debris: hurts the player AND monsters where it lands.
func _rock_hit() -> void:
	var pl := G.player
	if pl != null and pl.position.distance_to(position) < radius:
		pl.take_damage(damage, position)
	for e in G.query(position, radius):
		e.take_hit(damage * 2.0, ((e.position as Vector2) - position).normalized(), 600.0, 500.0, false)
	G.spawn_ring(position, 10, radius, G.ORANGE, 0.35, 14.0, "shock")
	G.decals.crater(position, radius * 0.35)
	G.particles.dust(position, 10, radius * 0.5)
	G.shake(0.2)
	Sfx.play("boom", -8.0)
	queue_free()


func _explode() -> void:
	if G.player != null and G.player.skill_runner != null:
		G.player.skill_runner.explode(position, radius, damage, Color(1, 0.5, 0.1), elem)
		if G.player.skills.has("combo_firemeteor") and randf() < 0.35:
			var m := Projectile.new()
			m.kind = "meteor"
			m.position = position
			m.damage = 70.0
			m.radius = 170.0
			m.fuse = 0.6
			m.elem = "fire"
			G.entities.add_child(m)
	G.decals.splat(position, radius * 0.35, Color(0.2, 0.12, 0.1))
	queue_free()


func _meteor_hit() -> void:
	var p := G.player
	if p != null:
		for e in G.hittables_in(position, radius):
			var d: Vector2 = (e.position as Vector2) - position
			var dir := d.normalized() if d.length() > 1.0 else Vector2.RIGHT
			p.deal_skill(e, damage, dir, 950.0, 750.0, elem)
	G.spawn_ring(position, 20, radius * 1.2, G.ORANGE, 0.5, 26.0, "shock")
	G.spawn_ring(position, 10, radius * 0.8, G.YELLOW, 0.35, 12.0)
	G.decals.crater(position, radius * 0.45)
	G.particles.dust(position, 20, radius * 0.6)
	G.particles.sparks(position, Vector2.UP, 16, G.ORANGE)
	G.push_shards(position, radius * 1.6, 900)
	G.spawn_text(position + Vector2(0, -90), "KA-BOOM!", G.ORANGE, 54)
	G.shake(0.6)
	G.kick_zoom(0.05)
	G.impact_frame(0.05)
	Sfx.play("boom", 0.0)
	queue_free()


func _draw() -> void:
	var ink := G.INK
	match kind:
		"fireball":
			for i in trail.size():
				var tp: Vector2 = (trail[i] as Vector2) - position
				draw_circle(tp, size * (1.0 - i / 9.0), Color(1, 0.4 + i * 0.05, 0.1, 0.6 - i * 0.07), true, -1.0, false)
			var fl := Ink.burst(Vector2.ZERO, size * 1.3, size * 1.3, 8, 0.35, int(t * 30.0))
			Ink.shape(self, fl, Color(1, 0.5, 0.1), 4.0, ink)
			draw_circle(Vector2.ZERO, size * 0.6, Color(1, 0.95, 0.5), true, -1.0, false)
		"spit":
			Ink.circle(self, Vector2(0, -20), 9.0, Color(0.6, 0.9, 0.2), 3.0, ink)
			draw_circle(Vector2(-3, -23), 3.0, Color(1, 1, 1, 0.7), true, -1.0, false)
		"shuriken":
			draw_set_transform(Vector2.ZERO, t * 30.0, Vector2.ONE)
			Ink.shape(self, Ink.star(Vector2.ZERO, 14, 5, 4, 0), Color(0.75, 0.75, 0.85), 3.0, ink)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"rock", "meteor":
			var k := t / fuse
			if kind == "rock":
				draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color(1, 0.3, 0.1, 0.4 + 0.4 * sin(t * 20.0)), 4.0)
				var hh := (1.0 - k) * 700.0
				var rk := Ink.burst(Vector2(0, -hh), 22, 20, 7, 0.2, 3)
				Ink.shape(self, rk, Color(0.3, 0.22, 0.2), 4.0, ink)
				draw_circle(Vector2(-5, -hh - 5), 5.0, G.ORANGE, true, -1.0, false)
				return
			# target marker
			var a := 0.5 + 0.4 * sin(t * 25.0)
			draw_arc(Vector2.ZERO, radius * (1.15 - 0.25 * k), 0, TAU, 40, Color(1, 0.2, 0.1, a), 5.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.55))
			draw_circle(Vector2.ZERO, radius * k, Color(1, 0.3, 0.1, 0.18), true, -1.0, false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var hgt := (1.0 - k) * 900.0
			var mp := Vector2(-hgt * 0.4, -hgt)
			for i in 4:
				draw_line(mp + Vector2(-20 + i * 12, -20), mp + Vector2(-20 + i * 12, -20) + Vector2(-0.4, -1).normalized() * 140, Color(1, 0.6, 0.2, 0.7), 8.0 - i)
			var rock := Ink.burst(mp, 36, 32, 7, 0.2, 5)
			Ink.shape(self, rock, Color(0.5, 0.4, 0.35), 5.0, ink)
			draw_circle(mp + Vector2(-8, -8), 8.0, Color(1, 0.7, 0.3), true, -1.0, false)
