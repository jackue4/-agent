class_name ShadowClone
extends Node2D
## Shadow clone that teleport-slashes through enemies.

var hits := 5
var damage := 20.0
var player: Player
var t := 0.0
var next := 0.0
var facing := 1.0
var visited := {}
var fade := 1.0
var vamp := false


func _process(dt: float) -> void:
	t += dt
	next -= dt
	if hits <= 0:
		fade -= dt * 3.0
		if fade <= 0.0:
			queue_free()
		queue_redraw()
		return
	if next <= 0.0:
		next = 0.12
		var e = G.nearest_enemy(position, 600.0, visited)
		if e == null:
			visited.clear()
			e = G.nearest_enemy(position, 600.0)
		if e == null:
			hits = 0
			return
		var from := position
		var dir: Vector2 = ((e.position as Vector2) - from).normalized()
		position = (e.position as Vector2) + dir * 40.0
		facing = signf(dir.x) if absf(dir.x) > 0.1 else facing
		visited[e.get_instance_id()] = true
		G.spawn_slash(position + Vector2(0, -40), -dir, 70.0, 2.4, "big", Color(0.7, 0.5, 1.0))
		G.spawn_bolt(from + Vector2(0, -40), position + Vector2(0, -40), Color(0.6, 0.35, 0.95))
		if player != null:
			for o in G.hittables_in(e.position, 60.0):
				player.deal_skill(o, damage, dir, 500.0, 300.0)
				if vamp:
					player.heal(1.5, false)
		Sfx.play("whoosh", -4.0, 0.3)
		G.shake(0.08)
		hits -= 1
	queue_redraw()


func _draw() -> void:
	var c := Color(0.35, 0.15, 0.6, 0.85 * fade) if not vamp else Color(0.6, 0.08, 0.15, 0.85 * fade)
	Stick.draw(self, Player.P_FLYKICK, facing, Vector2.ZERO, c, c, Color(0.6, 0.4, 0.9, fade), 8.0, Color(1, 0.9, 0.3, fade))
