class_name SkillRunner
extends Node2D
## Runs the player's active roguelike skills.

var player: Player
var timers := {}
var orbit_angle := 0.0
var orbit_hit := {}


func _ready() -> void:
	z_index = 3
	top_level = true


var gravity_wells: Array = []
var palms: Array = []


func refresh() -> void:
	for id in player.skills.keys():
		if not timers.has(id):
			timers[id] = 0.5


func lv(id: String) -> int:
	return int(player.skills.get(id, 0))


func _process(dt: float) -> void:
	if player == null or player.dead:
		return
	position = Vector2.ZERO
	for id in timers.keys():
		if id == "_blood" or id == "orbit" or id == "nova" or not (SkillDB.ACTIVE.has(id) or id == "combo_thousand" or id == "combo_gravity"):
			continue
		timers[id] = float(timers[id]) - dt * player.atk_speed
		if float(timers[id]) <= 0.0:
			var cd := _fire(id)
			timers[id] = cd
	if lv("orbit") > 0:
		_orbit(dt)
	_update_wells(dt)
	_update_palms(dt)
	queue_redraw()


func _fire(id: String) -> float:
	var l := lv(id)
	var awake := l >= SkillDB.MAX
	var p := player.position
	match id:
		"shockwave":
			_shockwave(p, 170.0 + 28.0 * l, 18.0 + 9.0 * l)
			if awake:
				get_tree().create_timer(0.3, false).timeout.connect(func(): _shockwave(player.position, 330.0, 40.0))
			return 4.2 - 0.35 * l
		"lightning":
			if G.nearest_enemy(p, 520.0) == null:
				return 0.3
			_lightning(p, 2 + l, 18.0 + 8.0 * l)
			if awake:
				get_tree().create_timer(0.15, false).timeout.connect(func(): _lightning(player.position, 2 + l, 18.0 + 8.0 * l))
			return 2.6 - 0.22 * l
		"fireball":
			var e = G.nearest_enemy(p, 650.0)
			if e == null:
				return 0.3
			var dir: Vector2 = ((e.position as Vector2) - p).normalized()
			var n := 3 if awake else 1
			for i in n:
				var pr := Projectile.new()
				pr.kind = "fireball"
				pr.position = p + Vector2(0, -2)
				pr.vel = dir.rotated((i - (n - 1) * 0.5) * 0.35) * 620.0
				pr.damage = 20.0 + 10.0 * l
				pr.radius = 75.0 + 14.0 * l + (30.0 if awake else 0.0)
				pr.size = 15.0 + l * 1.5 + (8.0 if awake else 0.0)
				pr.elem = "fire"
				G.entities.add_child(pr)
			Sfx.play("fire", -4.0)
			return 1.9 - 0.15 * l
		"meteor":
			var n := 3 if awake else 1
			var first = G.densest_point(p, 700.0)
			if first == null:
				return 0.4
			for i in n:
				var tgt: Vector2 = first
				if i > 0:
					var other = G.densest_point(p, 800.0)
					tgt = (other if other != null else first) + Vector2.from_angle(randf() * TAU) * randf_range(60, 200)
				var m := Projectile.new()
				m.kind = "meteor"
				m.position = tgt
				m.damage = 60.0 + 25.0 * l
				m.radius = 150.0 + 18.0 * l
				m.fuse = 0.85 + i * 0.25
				G.entities.add_child(m)
			return 6.5 - 0.5 * l
		"clone":
			for k in (2 if lv("combo_thousand") > 0 else 1):
				var c := ShadowClone.new()
				c.position = p + Vector2(k * 40.0, 0)
				c.hits = (4 + l) * (2 if awake else 1)
				c.damage = 16.0 + 7.0 * l
				c.player = player
				c.vamp = lv("combo_bloodshadow") > 0
				G.entities.add_child(c)
			Sfx.play("dash", 0.0)
			return 7.5 - 0.6 * l
		"frost":
			var r := (150.0 + 20.0 * l) * (2.0 if awake else 1.0)
			for e in G.hittables_in(p, r):
				var d: Vector2 = (e.position as Vector2) - p
				player.deal_skill(e, 10.0 + 6.0 * l, d.normalized() if d.length() > 1.0 else Vector2.RIGHT, 200.0, 0.0, "frost")
				if awake and e is Enemy:
					(e as Enemy).freeze += 1.0
			G.spawn_ring(p, 20, r, Color(0.55, 0.9, 1.0), 0.45, 24.0, "shock")
			G.spawn_ring(p, 10, r * 0.7, G.WHITE, 0.3, 10.0)
			for i in 10:
				G.particles.add(p + Vector2.from_angle(TAU * i / 10.0) * r * 0.6, Vector2.from_angle(TAU * i / 10.0) * 200.0, "star", 0.5, 12, Color(0.75, 0.95, 1.0))
			Sfx.play("zap", -6.0, 0.4)
			return 5.0 - 0.4 * l
		"combo_thousand":
			var e = G.nearest_enemy(p, 600.0)
			if e == null:
				return 0.5
			for i in 12:
				palms.append({"t": -i * 0.06, "a": TAU * i / 12.0})
			G.spawn_text(p + Vector2(0, -170), "千手观音!", G.YELLOW, 48)
			Sfx.play("whoosh", 0.0)
			return 6.0
		"combo_gravity":
			var c2 = G.densest_point(p, 650.0)
			if c2 == null:
				return 0.5
			gravity_wells.append({"p": c2, "t": 0.0})
			G.spawn_text(c2 + Vector2(0, -120), "引力奇点!", G.PURPLE, 40)
			return 5.0
	return 3.0


func _shockwave(p: Vector2, r: float, dmg: float) -> void:
	for e in G.hittables_in(p, r):
		var d: Vector2 = (e.position as Vector2) - p
		var dir := d.normalized() if d.length() > 1.0 else Vector2.RIGHT
		player.deal_skill(e, dmg, dir, 820.0, 380.0)
	G.spawn_ring(p, 30, r, Color(0.4, 0.8, 1.0), 0.42, 20.0, "shock")
	G.spawn_ring(p, 10, r * 0.75, G.WHITE, 0.3, 8.0)
	G.particles.dust(p, 14, r * 0.5)
	G.push_shards(p, r * 1.3, 700)
	G.shake(0.3)
	Sfx.play("heavy", -2.0)


func _lightning(p: Vector2, chains: int, dmg: float) -> void:
	var hit := {}
	var from := p + Vector2(0, -900)
	var cur = G.nearest_enemy(p, 520.0)
	var first := true
	while cur != null and chains > 0:
		var to: Vector2 = (cur.position as Vector2) + Vector2(0, -20)
		G.spawn_bolt(from, to, G.YELLOW)
		G.particles.sparks(to, Vector2.UP, 6, G.YELLOW)
		hit[cur.get_instance_id()] = true
		player.deal_skill(cur, dmg, (to - from).normalized(), 260.0, 120.0, "shock")
		if first:
			G.decals.crack(cur.position, 40.0)
			first = false
		from = to
		chains -= 1
		cur = G.nearest_enemy(to, 260.0, hit)
	G.shake(0.15)
	Sfx.play("zap", -3.0)


func _orbit(dt: float) -> void:
	var l := lv("orbit")
	var n := 6 if l >= SkillDB.MAX else 2 + int(l / 2)
	var r := 105.0 + 8.0 * l
	orbit_angle += dt * (3.6 + 0.3 * l)
	var now := G.game_time
	for i in n:
		var a := orbit_angle + TAU * i / float(n)
		var fp := player.position + Vector2(cos(a), sin(a) * 0.6) * r + Vector2(0, -36)
		for e in G.hittables_in(fp + Vector2(0, 36), 22.0):
			var id: int = e.get_instance_id()
			if float(orbit_hit.get(id, -10.0)) + 0.45 > now:
				continue
			orbit_hit[id] = now
			var dir := Vector2(-sin(a), cos(a)).normalized()
			player.deal_skill(e, 10.0 + 6.0 * l, dir, 520.0, 160.0, "fire" if randf() < 0.35 else "")
			G.particles.sparks(fp, dir, 4, Color(1, 0.5, 0.6))
			Sfx.play("hit", -8.0)
	if orbit_hit.size() > 400:
		orbit_hit.clear()


func on_dash_end(path: Array) -> void:
	if lv("combo_thunderflash") > 0 and not path.is_empty():
		_thunderflash(path)
	var l := lv("nova")
	if l <= 0 or path.is_empty():
		return
	var r := 110.0 + 16.0 * l
	var dmg := 24.0 + 12.0 * l
	if l >= SkillDB.MAX:
		var step := maxi(int(path.size() / 3), 1)
		var idx := 0
		var delay := 0.0
		while idx < path.size():
			var pp: Vector2 = path[idx]
			get_tree().create_timer(delay, false).timeout.connect(func(): explode(pp, r * 0.8, dmg, Color(0.3, 0.95, 0.6)))
			idx += step
			delay += 0.06
	explode(path[path.size() - 1], r, dmg, Color(0.3, 0.95, 0.6))


func explode(p: Vector2, r: float, dmg: float, col: Color, elem: String = "") -> void:
	for e in G.hittables_in(p, r):
		var d: Vector2 = (e.position as Vector2) - p
		var dir := d.normalized() if d.length() > 1.0 else Vector2.RIGHT
		player.deal_skill(e, dmg, dir, 700.0, 420.0, elem)
	G.spawn_ring(p, 10, r, col, 0.3, 16.0)
	G.spawn_text(p + Vector2(0, -60), "BOOM!", col, 32)
	G.particles.sparks(p, Vector2.UP, 10, col)
	G.particles.dust(p, 8, r * 0.4)
	G.push_shards(p, r * 1.2, 500)
	G.shake(0.25)
	Sfx.play("boom", -8.0, 0.25)


# ---------------------------------------------------------------- reactions & combos
## 雷暴: lightning jumps from the burning target to everything nearby.
func storm(p: Vector2, dmg: float) -> void:
	var n := 0
	for e in G.query(p, 260.0):
		if n >= 6:
			break
		var to: Vector2 = (e.position as Vector2) + Vector2(0, -20)
		G.spawn_bolt(p + Vector2(0, -30), to, G.YELLOW)
		player.deal_skill(e, dmg, (to - p).normalized(), 300.0, 160.0)
		n += 1
	G.spawn_ring(p, 10, 260.0, G.YELLOW, 0.3, 10.0)
	G.shake(0.2)
	Sfx.play("zap", -2.0)


## 冰爆: a frozen enemy shatters, icy shards hit everything around.
func ice_burst(p: Vector2, dmg: float) -> void:
	for e in G.hittables_in(p, 170.0):
		var d: Vector2 = (e.position as Vector2) - p
		player.deal_skill(e, dmg, d.normalized() if d.length() > 1.0 else Vector2.RIGHT, 650.0, 380.0)
	G.spawn_ring(p, 10, 180.0, Color(0.6, 0.92, 1.0), 0.35, 18.0, "shock")
	for i in 12:
		G.particles.add(p + Vector2(0, -30), Vector2.from_angle(TAU * i / 12.0) * randf_range(250, 520), "spark", 0.35, 18, Color(0.7, 0.95, 1.0))
	G.shake(0.3)
	Sfx.play("shatter", 0.0)


## 天崩地裂: three aftershocks rolling outwards from the slam.
func quake(p: Vector2, r: float) -> void:
	for i in 3:
		var rr := r * (1.4 + i * 0.45)
		get_tree().create_timer(0.18 * (i + 1), false).timeout.connect(_aftershock.bind(p, rr))
	G.spawn_text(p + Vector2(0, -180), "天崩地裂!", G.ORANGE, 52)


func _aftershock(p: Vector2, rr: float) -> void:
	if player == null or player.dead:
		return
	for e in G.hittables_in(p, rr):
		var d: Vector2 = (e.position as Vector2) - p
		player.deal_skill(e, 22.0, d.normalized() if d.length() > 1.0 else Vector2.RIGHT, 500.0, 820.0)
	G.spawn_ring(p, rr * 0.6, rr, G.ORANGE, 0.35, 20.0, "shock")
	G.decals.crack(p + Vector2.from_angle(randf() * TAU) * rr * 0.5, rr * 0.35)
	G.shake(0.35)
	Sfx.play("heavy", -2.0)


## 雷光闪: every enemy along the dash path is struck by lightning.
func _thunderflash(path: Array) -> void:
	var hit := {}
	for i in range(0, path.size(), 2):
		for e in G.query(path[i], 70.0):
			if hit.has(e.get_instance_id()):
				continue
			hit[e.get_instance_id()] = true
			G.spawn_bolt((e.position as Vector2) + Vector2(0, -600), (e.position as Vector2) + Vector2(0, -20), G.YELLOW)
			player.deal_skill(e, 30.0, Vector2.UP, 200.0, 300.0, "shock")
	explode(path[path.size() - 1], 150.0, 30.0, G.YELLOW, "shock")


func _update_palms(dt: float) -> void:
	var i := palms.size() - 1
	while i >= 0:
		var pm: Dictionary = palms[i]
		pm["t"] = float(pm["t"]) + dt
		if float(pm["t"]) >= 0.0 and not pm.has("done"):
			pm["done"] = true
			var tgt := player.position + Vector2.from_angle(float(pm["a"])) * 170.0
			for e in G.hittables_in(tgt, 90.0):
				var d: Vector2 = (e.position as Vector2) - player.position
				player.deal_skill(e, 18.0 + 2.0 * lv("orbit"), d.normalized() if d.length() > 1.0 else Vector2.RIGHT, 600.0, 220.0)
			G.spawn_ring(tgt, 10, 90.0, G.YELLOW, 0.25, 10.0)
			Sfx.play("hit", -8.0, 0.3)
		if float(pm["t"]) > 0.3:
			palms.remove_at(i)
		i -= 1


func _update_wells(dt: float) -> void:
	var i := gravity_wells.size() - 1
	while i >= 0:
		var w: Dictionary = gravity_wells[i]
		w["t"] = float(w["t"]) + dt
		var c: Vector2 = w["p"]
		for e in G.query(c, 300.0):
			if not e.is_boss():
				var d: Vector2 = c - (e.position as Vector2)
				e.position += d.normalized() * minf(d.length(), 420.0 * dt)
		if float(w["t"]) >= 1.3:
			explode(c, 220.0, 45.0, G.PURPLE)
			for e in G.query(c, 220.0):
				e.vz = maxf(e.vz, 700.0)
				e.z = maxf(e.z, 1.0)
			gravity_wells.remove_at(i)
		i -= 1


## 血影: taking damage spawns a short blood clone that heals on hit.
func blood_clone() -> void:
	if float(timers.get("_blood", 0.0)) > G.game_time:
		return
	timers["_blood"] = G.game_time + 2.0
	var c := ShadowClone.new()
	c.position = player.position
	c.hits = 4
	c.damage = 20.0
	c.player = player
	c.vamp = true
	G.entities.add_child(c)


## 影忍 passive: three shuriken fan out after every dash.
func shuriken(p: Vector2, dir: Vector2) -> void:
	for i in 3:
		var pr := Projectile.new()
		pr.kind = "shuriken"
		pr.position = p + Vector2(0, -50)
		pr.vel = dir.rotated((i - 1) * 0.3) * 900.0
		pr.damage = 12.0 * player.dmg_mult
		G.entities.add_child(pr)


func _draw() -> void:
	for w in gravity_wells:
		var c: Vector2 = w["p"]
		var k := float(w["t"]) / 1.3
		for j in 3:
			draw_arc(c, 260.0 * (1.0 - fmod(k * 2.0 + j / 3.0, 1.0)), 0, TAU, 40, Color(0.55, 0.4, 1.0, 0.6), 5.0)
		Ink.circle(self, c, 20.0 + 10.0 * k, Color(0.15, 0.05, 0.3), 4.0)
	for pm in palms:
		if float(pm["t"]) < 0.0:
			continue
		var tgt := player.position + Vector2.from_angle(float(pm["a"])) * 170.0 + Vector2(0, -40)
		var a := 1.0 - float(pm["t"]) / 0.3
		var palm := Ink.ellipse(tgt, 26, 32, 12)
		draw_colored_polygon(palm, Color(1, 0.85, 0.2, a))
		Ink.outline(self, palm, 4.0, Color(G.INK, a))
	var l := lv("orbit")
	if l <= 0 or player == null:
		return
	var n := 6 if l >= SkillDB.MAX else 2 + int(l / 2)
	var r := 105.0 + 8.0 * l
	for i in n:
		var a := orbit_angle + TAU * i / float(n)
		var fp := player.position + Vector2(cos(a), sin(a) * 0.6) * r + Vector2(0, -36)
		for j in 3:
			var ta := a - 0.12 * (j + 1)
			var tp := player.position + Vector2(cos(ta), sin(ta) * 0.6) * r + Vector2(0, -36)
			draw_circle(tp, 14.0 - j * 3.0, Color(1, 0.45, 0.2, 0.5 - j * 0.14), true, -1.0, false)
		Ink.circle(self, fp, 16.0, Color(0.95, 0.3, 0.45), 4.0)
		draw_line(fp + Vector2(-8, -3), fp + Vector2(8, -3), G.INK, 2.5)
		draw_line(fp + Vector2(-8, 3), fp + Vector2(8, 3), G.INK, 2.5)
		draw_circle(fp + Vector2(-5, -8), 4.0, Color(1, 1, 1, 0.6), true, -1.0, false)