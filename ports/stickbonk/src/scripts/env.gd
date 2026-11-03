class_name Env
extends Node2D
## Per-map environment mechanics: 竹林 wind gusts, 火山 lava pools + eruptions, 冰原 slippery ice + blizzards.

var map := "dojo"
var t := 0.0
var gust_t := 12.0
var gust := 0.0
var gust_dir := Vector2.RIGHT
var pools: Array = []
var erupt_t := 9.0
var bliz_t := 15.0
var bliz := 0.0
var lava_tick := 0.0
var over: Node2D
var flakes: Array = []


func _ready() -> void:
	z_index = -9
	over = Node2D.new()
	over.z_as_relative = false
	over.z_index = 6
	over.draw.connect(_draw_over)
	add_child(over)


func setup(m: String) -> void:
	map = m
	G.ice_floor = map == "ice"
	pools.clear()
	if map == "volcano":
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		var tries := 0
		while pools.size() < 6 and tries < 60:
			tries += 1
			var p := Vector2(rng.randf_range(G.ARENA.position.x + 250, G.ARENA.end.x - 250), rng.randf_range(G.ARENA.position.y + 250, G.ARENA.end.y - 250))
			if p.length() < 420.0:
				continue
			var ok := true
			for q in pools:
				if (q["p"] as Vector2).distance_to(p) < 420.0:
					ok = false
			if ok:
				pools.append({"p": p, "r": rng.randf_range(110, 165), "s": rng.randi() % 100})
	queue_redraw()


func in_lava(p: Vector2) -> bool:
	for q in pools:
		if (q["p"] as Vector2).distance_to(p) < float(q["r"]) * 0.85:
			return true
	return false


func _process(dt: float) -> void:
	t += dt
	var pl := G.player
	match map:
		"bamboo":
			gust_t -= dt
			if gust_t <= 0.0 and gust <= 0.0:
				gust = 3.6
				gust_t = 14.0
				gust_dir = Vector2.from_angle(randf() * TAU)
				G.banner("竹林狂风！站稳脚跟！", 1.6)
				Sfx.play("whoosh", 2.0)
			if gust > 0.0:
				gust -= dt
				var k := clampf(minf(gust, 3.6 - gust) / 0.6, 0.0, 1.0)
				G.wind = gust_dir * 300.0 * k
			else:
				G.wind = Vector2.ZERO
		"volcano":
			erupt_t -= dt
			if erupt_t <= 0.0 and pl != null:
				erupt_t = 7.5
				G.shake(0.25)
				G.banner("火山喷发！小心落石！", 1.4)
				for i in (4 if G.low else 6):
					var r := Projectile.new()
					r.kind = "rock"
					r.hostile = true
					r.position = pl.position + Vector2.from_angle(randf() * TAU) * randf_range(60, 520)
					r.position = r.position.clamp(G.ARENA.position + Vector2(60, 60), G.ARENA.end - Vector2(60, 60))
					r.fuse = 1.1 + i * 0.12
					r.radius = 85.0
					r.damage = 12.0
					G.entities.add_child(r)
			lava_tick -= dt
			if lava_tick <= 0.0:
				lava_tick = 0.6
				if pl != null and not pl.dead and pl.z < 10.0 and in_lava(pl.position):
					pl.take_damage(7.0, pl.position + Vector2(0, -1))
					G.spawn_text(pl.position + Vector2(0, -150), "好烫!", G.ORANGE, 28)
				for q in pools:
					for e in G.query(q["p"], float(q["r"]) * 0.8):
						if not e.is_boss():
							e.apply_elem("fire", 6.0)
		"ice":
			bliz_t -= dt
			if bliz_t <= 0.0 and bliz <= 0.0:
				bliz = 6.0
				bliz_t = 16.0
				G.banner("暴风雪！怪物减速，攻击可冰冻！", 1.8)
			if bliz > 0.0:
				bliz -= dt
				G.env_slow = 0.6
				G.blizzard = true
			else:
				G.env_slow = 1.0
				G.blizzard = false
	if map != "dojo" and map != "volcano":
		over.queue_redraw()
	elif map == "volcano" and Engine.get_process_frames() % 3 == 0:
		queue_redraw()


func _draw() -> void:
	if map != "volcano":
		return
	for q in pools:
		var c: Vector2 = q["p"]
		var r: float = q["r"]
		var crust := Ink.burst(c, r * 1.12, r * 0.72, 14, 0.12, int(q["s"]))
		Ink.shape(self, crust, Color(0.25, 0.14, 0.12), 6.0)
		var lava := Ink.burst(c, r * 0.95, r * 0.6, 12, 0.1, int(q["s"]) + int(t * 2.0))
		draw_colored_polygon(lava, Color(1.0, 0.38, 0.08))
		draw_colored_polygon(Ink.ellipse(c + Vector2(-r * 0.15, -r * 0.08), r * 0.5, r * 0.28, 14), Color(1.0, 0.72, 0.2))
		for i in 3:
			var bp := c + Vector2(cos(t * 0.7 + i * 2.1) * r * 0.5, sin(t * 0.9 + i * 1.7) * r * 0.3)
			var br := 6.0 + 5.0 * absf(sin(t * 3.0 + i))
			draw_arc(bp, br, 0, TAU, 12, Color(1, 0.9, 0.5), 3.0)


func _draw_over() -> void:
	var vr := G.view_rect
	if vr.size == Vector2.ZERO:
		return
	match map:
		"bamboo":
			if gust > 0.0:
				var a := clampf(minf(gust, 3.6 - gust) / 0.6, 0.0, 1.0)
				for i in (14 if G.low else 26):
					var s := float(i) * 97.0
					var p := vr.position + Vector2(fposmod(s * 13.0 + t * 900.0 * gust_dir.x, vr.size.x), fposmod(s * 7.0 + t * 900.0 * gust_dir.y, vr.size.y))
					over.draw_line(p, p - gust_dir * 90.0, Color(1, 1, 1, 0.55 * a), 4.0)
					if i % 3 == 0:
						var lf := PackedVector2Array([p, p + gust_dir.rotated(0.5) * 16.0, p + gust_dir * 26.0, p + gust_dir.rotated(-0.5) * 16.0])
						over.draw_colored_polygon(lf, Color(0.35, 0.65, 0.25, 0.9 * a))
		"ice":
			var n := (30 if G.low else 60) if bliz > 0.0 else (8 if G.low else 16)
			for i in n:
				var s := float(i) * 53.0
				var fall := Vector2(-160.0 if bliz > 0.0 else -30.0, 220.0)
				var p := vr.position + Vector2(fposmod(s * 17.0 + t * fall.x, vr.size.x), fposmod(s * 11.0 + t * fall.y, vr.size.y))
				over.draw_circle(p, 3.0 + float(i % 3), Color(1, 1, 1, 0.85), true, -1.0, false)
			if bliz > 0.0:
				over.draw_rect(vr, Color(0.8, 0.9, 1.0, 0.12))
