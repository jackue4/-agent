class_name Enemy
extends Node2D
## Comic monsters. Hand-drawn procedural bodies; on death the body polygon shatters into physics shards.

const TYPES := {
	"blob": {"hp": 22.0, "speed": 120.0, "r": 22.0, "dmg": 8.0, "xp": 1, "col": Color(0.4, 0.85, 0.35), "mass": 1.0},
	"imp": {"hp": 16.0, "speed": 205.0, "r": 18.0, "dmg": 7.0, "xp": 1, "col": Color(0.95, 0.35, 0.3), "mass": 0.8},
	"bat": {"hp": 12.0, "speed": 260.0, "r": 16.0, "dmg": 6.0, "xp": 1, "col": Color(0.55, 0.4, 0.85), "mass": 0.6},
	"spitter": {"hp": 30.0, "speed": 95.0, "r": 22.0, "dmg": 9.0, "xp": 3, "col": Color(0.95, 0.75, 0.2), "mass": 1.1},
	"brute": {"hp": 110.0, "speed": 85.0, "r": 38.0, "dmg": 18.0, "xp": 8, "col": Color(0.35, 0.6, 0.95), "mass": 3.0},
	"boss": {"hp": 1400.0, "speed": 100.0, "r": 70.0, "dmg": 28.0, "xp": 150, "col": Color(0.85, 0.2, 0.35), "mass": 9.0},
	"slimeking": {"hp": 1600.0, "speed": 90.0, "r": 78.0, "dmg": 26.0, "xp": 160, "col": Color(0.35, 0.85, 0.3), "mass": 9.0},
	"batqueen": {"hp": 1250.0, "speed": 170.0, "r": 64.0, "dmg": 24.0, "xp": 160, "col": Color(0.55, 0.3, 0.8), "mass": 7.0},
	"reaper": {"hp": 999999.0, "speed": 260.0, "r": 60.0, "dmg": 9999.0, "xp": 0, "col": Color(0.25, 0.15, 0.35), "mass": 99.0},
}
const BOSS_NAMES := {"boss": "巨拳魔王", "slimeking": "史莱姆王", "batqueen": "蝙蝠女王", "reaper": "死神"}

var type := "blob"
var hp := 20.0
var max_hp := 20.0
var speed := 100.0
var radius := 20.0
var dmg := 8.0
var xp := 2
var col := Color.GREEN
var mass := 1.0
var dead := false
var vel := Vector2.ZERO
var z := 0.0
var vz := 0.0
var stun := 0.0
var flash := 0.0
var squash := Vector2.ONE
var atk_cd := 0.0
var wind := 0.0
var t := 0.0
var facing := 1.0
var salt := 0
var spin := 0.0
var spin_v := 0.0
var elite := false
var boss_phase := 0
var boss_timer := 2.0
var boss_charge := Vector2.ZERO
var charging := 0.0
var hp_scale := 1.0
# element statuses
var burn := 0.0
var burn_dps := 0.0
var burn_tick := 0.0
var shock := 0.0
var freeze := 0.0
var treasure := false
var life := 0.0
var air_hop := false
var air_combo := 0
var summon_t := 4.0


func setup(tp: String, scale_hp: float, is_elite: bool = false) -> void:
	type = tp
	var d: Dictionary = TYPES[tp]
	elite = is_elite
	hp_scale = scale_hp
	max_hp = float(d["hp"]) * scale_hp * (3.5 if elite else 1.0)
	hp = max_hp
	speed = float(d["speed"]) * randf_range(0.9, 1.1)
	radius = float(d["r"]) * (1.45 if elite else 1.0)
	dmg = float(d["dmg"]) * (1.0 + (scale_hp - 1.0) * 0.4) * (1.5 if elite else 1.0)
	xp = int(d["xp"]) * (5 if elite else 1)
	col = d["col"]
	if elite:
		col = col.lerp(Color(1, 0.85, 0.2), 0.35)
	mass = float(d["mass"]) * (2.0 if elite else 1.0)
	salt = randi() % 1000
	t = randf() * 10.0
	atk_cd = randf_range(0.5, 2.0)
	if G.main != null and G.main.has_method("enemy_speed_mult"):
		speed *= G.main.enemy_speed_mult()


func is_boss() -> bool:
	return BOSS_NAMES.has(type)


func boss_name() -> String:
	return String(BOSS_NAMES.get(type, "BOSS"))


## Elements: fire -> burn DoT, shock -> +20% damage taken & chain fuel, frost -> frozen solid.
## Reactions: fire on shocked = 爆燃 explosion, shock on burning = 雷暴 chain storm,
## heavy hit on frozen = 冰爆 shatter.  Returns the reaction name ("" if none).
func apply_elem(elem: String, dmg: float, heavy: bool = false) -> String:
	if dead or type == "reaper":
		return ""
	var pl := G.player
	var boost := 1.0
	match elem:
		"fire":
			if shock > 0.0:
				shock = 0.0
				_react("爆燃", G.ORANGE)
				if pl != null:
					pl.skill_runner.explode(position, 140.0, (20.0 + dmg * 0.8) * boost, G.ORANGE)
				return "爆燃"
			burn = 3.0
			burn_dps = maxf(burn_dps, (4.0 + dmg * 0.25) * (1.5 if pl != null and pl.sect == "flame" else 1.0))
		"shock":
			if burn > 0.0:
				burn = 0.0
				boost = 1.5 if pl != null and pl.sect == "thunder" else 1.0
				_react("雷暴", G.YELLOW)
				if pl != null:
					pl.skill_runner.storm(position, (16.0 + dmg * 0.6) * boost)
				return "雷暴"
			shock = 3.0
		"frost":
			if is_boss():
				freeze = maxf(freeze, 0.6)
			else:
				freeze = maxf(freeze, 2.2 if pl == null or pl.sect != "frost" else 3.0)
			vel = Vector2.ZERO
	if heavy and freeze > 0.0 and elem != "frost":
		freeze = 0.0
		boost = 1.5 if pl != null and pl.sect == "frost" else 1.0
		_react("冰爆", Color(0.55, 0.9, 1.0))
		if pl != null:
			pl.skill_runner.ice_burst(position, (30.0 + dmg) * boost)
		return "冰爆"
	return ""


func _react(name: String, c: Color) -> void:
	G.spawn_text(position + Vector2(0, -radius * 2.6 - z - 30), name + "!", c, 44, true, 0.9)
	Meta.codex_add("reactions", name)
	if G.main != null:
		G.main.on_reaction(name)


func _status_damage(amount: float, c: Color) -> void:
	if dead:
		return
	hp -= amount
	flash = 0.05
	if Engine.get_process_frames() % 2 == 0:
		G.damage_number(position + Vector2(randf_range(-10, 10), -radius * 2.0 - z - 10.0), amount, false)
	if hp <= 0.0:
		_die(Vector2.RIGHT.rotated(randf() * TAU), 500.0)


func _ready() -> void:
	G.enemies.append(self)
	squash = Vector2(0.3, 1.6)


func _process(dt: float) -> void:
	if dead:
		return
	t += dt
	life += dt
	flash -= dt
	stun -= dt
	atk_cd -= dt
	if burn > 0.0:
		burn -= dt
		burn_tick -= dt
		if burn_tick <= 0.0:
			burn_tick = 0.5
			_status_damage(burn_dps * 0.5, G.ORANGE)
			if dead:
				return
			if randf() < 0.5:
				G.particles.add(position + Vector2(randf_range(-radius, radius) * 0.6, -radius - z), Vector2(0, -90), "spark", 0.3, 14, G.ORANGE)
	shock -= dt
	if freeze > 0.0:
		freeze -= dt
		stun = maxf(stun, 0.05)
	if treasure and life > 25.0:
		G.banner("宝箱怪逃走了……", 1.8)
		dead = true
		G.enemies.erase(self)
		G.particles.dust(position, 10, radius)
		queue_free()
		return
	squash = squash.lerp(Vector2.ONE, 1.0 - exp(-10.0 * dt))
	var pl := G.player
	# airborne juggle physics
	if z > 0.0 or vz > 0.0:
		vz -= 2200.0 * dt
		z += vz * dt
		spin += spin_v * dt
		if z <= 0.0:
			z = 0.0
			if vz < -500.0:
				vz = -vz * 0.25
				squash = Vector2(1.4, 0.65)
				G.particles.dust(position, 5, radius)
				if type == "brute" or is_boss():
					G.shake(0.15)
				if air_hop:
					air_hop = false
					_slime_land()
			else:
				vz = 0.0
				spin = 0.0
	else:
		spin = lerpf(spin, 0.0, 1.0 - exp(-12.0 * dt))
	var friction := 2.5 if z > 0.0 else 7.0
	if freeze > 0.0:
		vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-14.0 * dt))
	elif air_hop and z > 0.0:
		pass
	elif stun > 0.0 or pl == null or pl.dead:
		vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-friction * dt))
	else:
		_ai(pl, dt)
	position += (vel + G.wind * mass_wind()) * dt
	if not G.ARENA.grow(-20).has_point(position):
		position.x = clampf(position.x, G.ARENA.position.x + 20, G.ARENA.end.x - 20)
		position.y = clampf(position.y, G.ARENA.position.y + 20, G.ARENA.end.y - 20)
		vel *= -0.5
	# separation
	if type != "bat" and type != "batqueen":
		for o in G.query(position, radius + 10.0):
			if o == self or o.type == "bat" or o.type == "batqueen":
				continue
			var d: Vector2 = position - o.position
			var l := d.length()
			var mind: float = radius + float(o.radius)
			if l < mind and l > 0.01:
				position += d / l * (mind - l) * 0.5 * (float(o.mass) / (mass + float(o.mass)))
	# touch damage
	if pl != null and not pl.dead and z < 30.0 and stun <= 0.0 and not treasure and type != "reaper":
		if position.distance_to(pl.position) < radius + Player.RADIUS and atk_cd <= 0.0 and type != "spitter":
			pl.take_damage(dmg, position)
			atk_cd = 1.0
			squash = Vector2(1.3, 0.75)
	# redraw at ~30Hz (staggered); the transform still moves every frame
	if G.on_screen(position) and (flash > -0.05 or (Engine.get_process_frames() + salt) % 2 == 0):
		queue_redraw()


func _ai(pl: Player, dt: float) -> void:
	var to := pl.position - position
	var dist := to.length()
	var dir := to / maxf(dist, 0.01)
	if absf(dir.x) > 0.2:
		facing = signf(dir.x)
	var want := dir * speed * G.env_slow
	if treasure:
		want = (-dir + dir.orthogonal() * sin(t * 1.3) * 0.6).normalized() * speed * 1.05
		vel = vel.lerp(want, 1.0 - exp(-5.0 * dt))
		return
	match type:
		"blob":
			var hop := fposmod(t * 1.6, 1.0)
			want *= 1.6 if hop < 0.45 else 0.15
		"bat":
			want = (dir + dir.orthogonal() * sin(t * 4.0 + salt) * 0.8).normalized() * speed
		"spitter":
			if dist < 300.0:
				want = -dir * speed
			elif dist < 460.0:
				want = dir.orthogonal() * speed * 0.6 * signf(sin(t * 0.7 + salt))
			if atk_cd <= 0.0 and dist < 620.0:
				atk_cd = 2.6
				wind = 0.4
			if wind > 0.0:
				wind -= dt
				want *= 0.0
				if wind <= 0.0:
					var pr := Projectile.new()
					pr.kind = "spit"
					pr.position = position + dir * 20.0
					pr.vel = dir * 360.0
					pr.damage = dmg
					pr.hostile = true
					G.entities.add_child(pr)
					squash = Vector2(1.3, 0.7)
		"brute":
			if dist < 170.0 and atk_cd <= 0.0 and wind <= 0.0:
				wind = 0.55
				atk_cd = 2.2
			if wind > 0.0:
				wind -= dt
				want = Vector2.ZERO
				squash = Vector2(0.9, 1.15)
				if wind <= 0.0:
					_brute_slam(pl)
		"boss":
			_boss_ai(pl, dir, dist, dt)
			return
		"slimeking":
			_slime_ai(pl, dir, dist, dt)
			return
		"reaper":
			_reaper_ai(pl, dir, dist, dt)
			return
		"batqueen":
			_bat_ai(pl, dir, dist, dt)
			return
	vel = vel.lerp(want, 1.0 - exp(-5.0 * dt))


func _brute_slam(pl: Player) -> void:
	G.spawn_ring(position, 10, 150, G.ORANGE, 0.3, 12.0, "shock")
	G.decals.crack(position, 70)
	G.shake(0.25)
	Sfx.play("heavy", -4.0)
	squash = Vector2(1.4, 0.6)
	if pl.position.distance_to(position) < 150.0:
		pl.take_damage(dmg, position)


func _boss_ai(pl: Player, dir: Vector2, dist: float, dt: float) -> void:
	boss_timer -= dt
	_phase_check()
	if charging > 0.0:
		charging -= dt
		vel = boss_charge * 900.0
		if int(charging * 40.0) % 2 == 0:
			G.particles.dust(position, 1, radius)
		if charging <= 0.0:
			G.shake(0.3)
		return
	if wind > 0.0:
		wind -= dt
		vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-10.0 * dt))
		squash = Vector2(1.0 + sin(t * 40.0) * 0.06, 1.0)
		if wind <= 0.0:
			if boss_phase >= 0 and randf() < 0.5:
				boss_charge = dir
				charging = 0.6
				Sfx.play("dash", 2.0)
				G.spawn_text(position + Vector2(0, -170), "RAAARGH!", G.RED, 48)
			else:
				for i in 3:
					get_tree().create_timer(i * 0.25, false).timeout.connect(_boss_stomp)
		return
	if boss_timer <= 0.0:
		boss_timer = 3.2 if boss_phase == 0 else 2.2
		wind = 0.6
		return
	if boss_phase == 1 and atk_cd <= 0.0:
		atk_cd = 1.4
		for i in 10:
			var pr := Projectile.new()
			pr.kind = "spit"
			pr.position = position + Vector2(0, -20)
			pr.vel = Vector2.from_angle(TAU * i / 10.0 + t) * 300.0
			pr.damage = dmg * 0.5
			pr.hostile = true
			G.entities.add_child(pr)
	vel = vel.lerp(dir * speed, 1.0 - exp(-3.0 * dt))


## 死神: unstoppable; drifts in, telegraphs, then a scythe swing that ends the run.
func _reaper_ai(pl: Player, dir: Vector2, dist: float, dt: float) -> void:
	stun = 0.0
	freeze = 0.0
	burn = 0.0
	shock = 0.0
	if wind > 0.0:
		wind -= dt
		vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-10.0 * dt))
		if wind <= 0.0:
			G.spawn_slash(position + Vector2(0, -60), dir, 220.0, 3.2, "big", Color(0.6, 0.2, 0.9))
			G.shake(0.9)
			G.impact_frame(0.15)
			Sfx.play("boom", 6.0)
			if pl.position.distance_to(position) < 260.0:
				pl.reaped()
			else:
				atk_cd = 0.0
		return
	var spd := 260.0 + life * 40.0
	vel = vel.lerp(dir * spd, 1.0 - exp(-4.0 * dt))
	if dist < 180.0 and atk_cd <= 0.0:
		atk_cd = 99.0
		wind = 0.55
		G.spawn_text(position + Vector2(0, -230), "时辰已到……", Color(0.75, 0.4, 1.0), 52, true, 1.2)


func mass_wind() -> float:
	return 0.0 if is_boss() else 1.0 / sqrt(mass)


func _phase_check() -> void:
	if hp < max_hp * 0.5 and boss_phase == 0:
		boss_phase = 1
		G.banner(boss_name() + " 狂暴化!", 2.0)
		G.shake(0.6)
		speed *= 1.25


## 史莱姆王: hops at the player, every landing is a shockwave; spawns slime kids.
func _slime_ai(pl: Player, dir: Vector2, dist: float, dt: float) -> void:
	_phase_check()
	boss_timer -= dt
	if z > 0.0:
		return
	if wind > 0.0:
		wind -= dt
		vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-10.0 * dt))
		squash = Vector2(1.25, 0.8)
		if wind <= 0.0:
			air_hop = true
			z = 1.0
			vz = 1050.0
			vel = dir * minf(dist, 520.0) * 1.15
			Sfx.play("whoosh", 2.0)
		return
	if boss_timer <= 0.0:
		boss_timer = 2.4 if boss_phase == 0 else 1.6
		wind = 0.45
		return
	vel = vel.lerp(dir * speed * 0.4, 1.0 - exp(-3.0 * dt))


func _slime_land() -> void:
	var r := 230.0
	G.spawn_ring(position, 20, r, Color(0.4, 0.9, 0.3), 0.4, 20.0, "shock")
	G.decals.splat(position, 70.0, Color(0.35, 0.8, 0.3, 0.7))
	G.shake(0.45)
	Sfx.play("heavy", 2.0)
	squash = Vector2(1.5, 0.6)
	if G.player != null and G.player.position.distance_to(position) < r:
		G.player.take_damage(dmg, position)
	summon_t -= 1.0
	if summon_t <= 0.0 and G.enemies.size() < 120:
		summon_t = 3.0 if boss_phase == 0 else 2.0
		for i in (2 if boss_phase == 0 else 4):
			G.main.spawn_minion("blob", position + Vector2.from_angle(randf() * TAU) * 90.0)


## 蝙蝠女王: circles the player, dives through, summons bats, phase-2 sonic rings.
func _bat_ai(pl: Player, dir: Vector2, dist: float, dt: float) -> void:
	_phase_check()
	boss_timer -= dt
	summon_t -= dt
	if charging > 0.0:
		charging -= dt
		vel = boss_charge * 1000.0
		if int(charging * 40.0) % 3 == 0:
			G.particles.add(position + Vector2(randf_range(-30, 30), -radius), -boss_charge * 120.0, "dust", 0.4, 22, Color(0.55, 0.35, 0.8, 0.8))
		return
	if wind > 0.0:
		wind -= dt
		vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-8.0 * dt))
		if wind <= 0.0:
			boss_charge = dir
			charging = 0.55
			Sfx.play("dash", 2.0)
			G.spawn_text(position + Vector2(0, -170), "SKREEEE!", G.PURPLE, 46)
		return
	if boss_timer <= 0.0:
		boss_timer = 3.0 if boss_phase == 0 else 2.0
		wind = 0.55
		return
	if summon_t <= 0.0 and G.enemies.size() < 120:
		summon_t = 6.0
		for i in 4:
			G.main.spawn_minion("bat", position + Vector2.from_angle(TAU * i / 4.0) * 80.0)
	if boss_phase == 1 and atk_cd <= 0.0:
		atk_cd = 1.8
		for i in 12:
			var pr := Projectile.new()
			pr.kind = "spit"
			pr.position = position + Vector2(0, -30)
			pr.vel = Vector2.from_angle(TAU * i / 12.0 + t) * 280.0
			pr.damage = dmg * 0.45
			pr.hostile = true
			G.entities.add_child(pr)
	var orbit := dir.orthogonal() * (1.0 if sin(t * 0.3) > 0.0 else -1.0)
	var want := (orbit + dir * clampf((dist - 300.0) / 200.0, -1.0, 1.0)).normalized() * speed * G.env_slow
	vel = vel.lerp(want, 1.0 - exp(-3.0 * dt))


func _boss_stomp() -> void:
	if dead:
		return
	var r := 260.0
	G.spawn_ring(position, 20, r, G.RED, 0.4, 20.0, "shock")
	G.decals.crack(position, 120)
	G.shake(0.45)
	Sfx.play("heavy", 2.0)
	squash = Vector2(1.35, 0.65)
	if G.player != null and G.player.position.distance_to(position) < r:
		G.player.take_damage(dmg, position)


func take_hit(amount: float, dir: Vector2, kb: float, up: float, crit: bool) -> bool:
	if dead:
		return false
	if type == "reaper":
		flash = 0.05
		if randf() < 0.3:
			G.spawn_text(position + Vector2(randf_range(-30, 30), -radius * 3.0), "无效", Color(0.7, 0.6, 0.85), 26, false, 0.5)
		return false
	if shock > 0.0:
		amount *= 1.2
	hp -= amount
	flash = 0.09
	var res := 1.0 / sqrt(mass)
	if is_boss():
		res *= 0.35
	if z > 30.0 and up > 0.0 and not is_boss():
		air_combo += 1
		if air_combo == 3:
			_react("空中追击", Color(0.4, 0.9, 1.0))
			hp -= amount * 0.8
			G.damage_number(position + Vector2(0, -radius * 2.0 - z - 40.0), amount * 0.8, true)
	elif z <= 0.0:
		air_combo = 0
	vel = dir * kb * res
	if up > 0.0:
		vz = maxf(vz, up * res) if z > 0.0 else up * res
		z = maxf(z, 1.0)
		spin_v = randf_range(-14, 14) * res
	elif z > 0.0:
		vz = maxf(vz, 260.0)
	stun = 0.3 if not is_boss() else 0.05
	if wind > 0.0 and type == "brute":
		wind = 0.0
	squash = Vector2(1.4, 0.65) if absf(dir.y) > 0.6 else Vector2(0.65, 1.35)
	G.register_hit()
	G.damage_number(position + Vector2(randf_range(-14, 14), -radius * 2.0 - z - 20.0), amount, crit)
	G.particles.sparks(position + Vector2(0, -radius - z), dir, 6 if crit else 4, G.YELLOW if crit else G.WHITE)
	if randf() < 0.5:
		G.particles.ink_spray(position, dir, 2, col.darkened(0.3), radius + z)
	if hp <= 0.0:
		_die(dir, kb)
		return true
	return false


func body_poly() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var r := radius
	match type:
		"blob":
			var wob := sin(t * 10.0) * 0.08
			for i in 18:
				var a := TAU * i / 18.0
				var rr := r * (1.0 + 0.07 * sin(a * 3.0 + t * 4.0))
				var p := Vector2(cos(a) * rr * (1.08 + wob), sin(a) * rr * (0.92 - wob))
				if p.y > 0:
					p.y *= 0.7
				pts.append(p + Vector2(0, -r * 0.8))
		"imp":
			pts = PackedVector2Array([Vector2(-r, -r * 0.4), Vector2(-r * 1.05, -r * 1.85), Vector2(-r * 0.45, -r * 1.35), Vector2(0, -r * 1.6), Vector2(r * 0.45, -r * 1.35), Vector2(r * 1.05, -r * 1.85), Vector2(r, -r * 0.4), Vector2(r * 0.6, 0), Vector2(-r * 0.6, 0)])
		"bat":
			var f := sin(t * 22.0) * r * 0.6
			pts = PackedVector2Array([Vector2(-r * 0.5, -r * 1.9), Vector2(-r * 1.9, -r * 2.4 + f), Vector2(-r * 1.4, -r * 1.7), Vector2(-r * 1.8, -r * 1.3 + f * 0.5), Vector2(-r * 0.6, -r * 1.2), Vector2(0, -r * 0.9), Vector2(r * 0.6, -r * 1.2), Vector2(r * 1.8, -r * 1.3 + f * 0.5), Vector2(r * 1.4, -r * 1.7), Vector2(r * 1.9, -r * 2.4 + f), Vector2(r * 0.5, -r * 1.9), Vector2(0, -r * 2.3)])
		"spitter":
			for i in 14:
				var a := TAU * i / 14.0
				var p := Vector2(cos(a) * r, sin(a) * r * 1.1)
				pts.append(p + Vector2(0, -r * 1.1))
		"brute", "boss":
			pts = PackedVector2Array([Vector2(-r * 0.9, 0), Vector2(-r * 1.15, -r * 0.8), Vector2(-r * 1.0, -r * 1.55), Vector2(-r * 0.55, -r * 1.9), Vector2(-r * 0.2, -r * 2.25), Vector2(r * 0.2, -r * 2.25), Vector2(r * 0.55, -r * 1.9), Vector2(r * 1.0, -r * 1.55), Vector2(r * 1.15, -r * 0.8), Vector2(r * 0.9, 0)])
	return pts


func _die(dir: Vector2, kb: float) -> void:
	dead = true
	G.enemies.erase(self)
	G.kills += 1
	var force := clampf(kb, 500.0, 1200.0) + (200.0 if is_boss() else 0.0)
	Meta.codex_add("enemies", "treasure" if treasure else type)
	var poly := body_poly()
	var xf := Transform2D(spin, squash, 0.0, position + Vector2(0, -z))
	var world := PackedVector2Array()
	for p in poly:
		var q := p
		q.x *= facing
		world.append(xf * q)
	var pieces := 7
	if type == "brute":
		pieces = 11
	elif is_boss():
		pieces = 18
	elif elite:
		pieces = 10
	var sid := "enemy_" + type
	if Art.has(sid):
		var exf := Transform2D(spin, squash, 0.0, position + Vector2(0, -z + _bob()))
		G.shatter_sprite(sid, exf, radius, facing, col, dir, force, position.y, pieces + 3)
	else:
		G.shatter(world, col, dir, force, position.y, pieces)
	G.particles.ink_spray(position, dir, 10 if not is_boss() else 40, col.darkened(0.35), radius + z)
	G.particles.stars(position + Vector2(0, -radius - z), 4)
	G.particles.sparks(position + Vector2(0, -radius - z), dir, 8, G.WHITE)
	G.decals.splat(position + dir * radius * 0.8, radius * (1.1 if not is_boss() else 2.0), col)
	G.drop_xp(position, int(xp * G.xp_mult))
	if (randf() < (0.015 if not elite else 0.6) or is_boss()) and not G.no_hearts:
		G.drop_heart(position)
	if treasure and G.main != null:
		G.main.on_treasure_killed(position)
	Sfx.play("shatter", -3.0 if not is_boss() else 4.0)
	if type == "brute" or elite:
		G.hitstop(0.08)
		G.shake(0.35)
		G.spawn_text(position + Vector2(0, -radius * 2.5), "SMASH!", G.ORANGE, 44)
	if is_boss():
		if G.main != null:
			G.main.on_boss_killed(type)
		G.slowmo(0.15, 1.5)
		G.impact_frame(0.15)
		G.shake(1.0)
		G.spawn_text(position + Vector2(0, -200), "K.O.!!!", G.RED, 90, true, 2.5)
		Sfx.play("boom", 6.0)
		for i in 3:
			G.shatter(Ink.ellipse(position + Vector2(randf_range(-60, 60), -80 + randf_range(-40, 40)), 50, 40, 10), col.lightened(0.15 * i), Vector2.from_angle(randf() * TAU), 900, position.y, 6)
		G.boss = null
	G.enemy_died.emit(self)
	queue_free()


func _draw() -> void:
	var ink := G.INK
	var fill := col
	if flash > 0.0:
		fill = Color.WHITE
		ink = G.RED
	var sh_r := radius * (1.1 if type != "bat" else 0.8)
	Ink.shadow(self, Vector2.ZERO, sh_r - z * 0.05, sh_r * 0.35)
	var up := -z
	if type == "bat":
		up -= 10.0 + sin(t * 6.0) * 6.0
	draw_set_transform(Vector2(0, up), spin, Vector2(squash.x * facing, squash.y))
	var w := 4.0 if radius < 30.0 else 6.0
	if type == "reaper":
		draw_colored_polygon(Ink.burst(Vector2(0, -radius * 1.4), radius * 2.0, radius * 1.8, 14, 0.3, salt + int(t * 10.0)), Color(0.35, 0.1, 0.55, 0.35))
	if elite or is_boss() or treasure:
		var glow := Ink.burst(Vector2(0, -radius), radius * 1.6, radius * 1.6, 12, 0.25, salt + int(t * 8.0))
		draw_colored_polygon(glow, Color(1, 0.85, 0.2, 0.35))
	var sid := "enemy_" + type
	if Art.has(sid):
		_draw_sprite(sid, up)
		return
	var poly := Ink.wobble(body_poly(), 0.9, salt)
	Ink.shape(self, poly, fill, w, ink)
	var r := radius
	# halftone shade on the lower right
	var shade := Color(0, 0, 0, 0.18)
	match type:
		"blob":
			draw_circle(Vector2(r * 0.35, -r * 0.45), r * 0.45, shade, true, -1.0, false)
			draw_circle(Vector2(-r * 0.35, -r * 1.25), r * 0.22, Color(1, 1, 1, 0.75), true, -1.0, false)
			_eyes(Vector2(r * 0.25, -r * 0.95), r * 0.28, ink)
			draw_arc(Vector2(r * 0.3, -r * 0.55), r * 0.25, 0.2, PI - 0.2, 8, ink, 3.0)
		"imp":
			_eyes(Vector2(r * 0.25, -r * 0.95), r * 0.27, ink, true)
			var teeth := PackedVector2Array([Vector2(-r * 0.2, -r * 0.45), Vector2(r * 0.7, -r * 0.45), Vector2(r * 0.5, -r * 0.2), Vector2(r * 0.25, -r * 0.4), Vector2(0, -r * 0.2)])
			Ink.shape(self, teeth, Color.WHITE, 2.5, ink)
			Ink.limb(self, Vector2(-r * 0.4, -r * 0.05), Vector2(-r * 0.5, r * 0.15), Vector2(-r * 0.7, r * 0.1), ink, 4.0)
			Ink.limb(self, Vector2(r * 0.4, -r * 0.05), Vector2(r * 0.5, r * 0.15), Vector2(r * 0.7, r * 0.1), ink, 4.0)
		"bat":
			_eyes(Vector2(0, -r * 1.6), r * 0.3, ink, true)
			draw_line(Vector2(-r * 0.2, -r * 1.2), Vector2(-r * 0.15, -r * 0.95), Color.WHITE, 3.0)
			draw_line(Vector2(r * 0.2, -r * 1.2), Vector2(r * 0.15, -r * 0.95), Color.WHITE, 3.0)
		"spitter":
			draw_circle(Vector2(r * 0.3, -r * 0.7), r * 0.5, shade, true, -1.0, false)
			var mouth := r * (0.35 + (0.25 if wind > 0.0 else 0.0))
			Ink.circle(self, Vector2(r * 0.55, -r * 0.95), mouth, Color(0.3, 0.05, 0.1), 3.0, ink)
			Ink.circle(self, Vector2(-r * 0.15, -r * 1.55), r * 0.38, Color.WHITE, 3.0, ink)
			draw_circle(Vector2(-r * 0.05, -r * 1.55), r * 0.16, ink, true, -1.0, false)
			for i in 3:
				draw_line(Vector2(-r * 0.6 + i * r * 0.4, -r * 2.2), Vector2(-r * 0.7 + i * r * 0.45, -r * 2.55), ink, 3.0)
		"brute", "boss":
			Ink.hatch(self, Vector2(r * 0.5, -r * 0.8), r * 0.45, 5, Color(0, 0, 0, 0.25), 2.0)
			var belly := Ink.ellipse(Vector2(r * 0.1, -r * 0.65), r * 0.6, r * 0.45, 16)
			Ink.shape(self, belly, fill.lightened(0.3), 3.0, ink)
			# angry brow + eyes
			_eyes(Vector2(r * 0.25, -r * 1.65), r * 0.2, ink, true)
			var jaw := PackedVector2Array([Vector2(-r * 0.25, -r * 1.3), Vector2(r * 0.75, -r * 1.3), Vector2(r * 0.65, -r * 1.08), Vector2(-r * 0.15, -r * 1.08)])
			Ink.shape(self, jaw, Color.WHITE, 3.0, ink)
			for i in 3:
				draw_line(Vector2(-r * 0.05 + i * r * 0.25, -r * 1.3), Vector2(-r * 0.05 + i * r * 0.25, -r * 1.08), ink, 2.0)
			# fists
			var lift := -r * 0.8 if wind > 0.0 else 0.0
			Ink.circle(self, Vector2(r * 1.25, -r * 0.6 + lift), r * 0.36, fill.darkened(0.1), w, ink)
			Ink.circle(self, Vector2(-r * 1.2, -r * 0.55 + lift), r * 0.32, fill.darkened(0.25), w, ink)
			if type == "boss":
				var crown := PackedVector2Array([Vector2(-r * 0.45, -r * 2.15), Vector2(-r * 0.5, -r * 2.65), Vector2(-r * 0.2, -r * 2.4), Vector2(0, -r * 2.8), Vector2(r * 0.2, -r * 2.4), Vector2(r * 0.5, -r * 2.65), Vector2(r * 0.45, -r * 2.15)])
				Ink.shape(self, crown, G.YELLOW, 4.0, ink)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# windup warning
	if wind > 0.0 and (type == "brute" or type == "boss"):
		var a := 0.4 + 0.4 * sin(t * 30.0)
		draw_arc(Vector2.ZERO, 150.0 if type == "brute" else 260.0, 0, TAU, 48, Color(1, 0.2, 0.1, a), 4.0)
		draw_string_outline(G.font, Vector2(-20, -radius * 2.6 - z), "!", HORIZONTAL_ALIGNMENT_CENTER, 40, 48, 8, ink)
		draw_string(G.font, Vector2(-20, -radius * 2.6 - z), "!", HORIZONTAL_ALIGNMENT_CENTER, 40, 48, G.RED)
	# health bar for tough ones
	if (type == "brute" or elite) and hp < max_hp:
		var bw := radius * 2.0
		var by := -radius * 2.4 - z - 14.0
		draw_rect(Rect2(-bw * 0.5 - 2, by - 2, bw + 4, 10), ink)
		draw_rect(Rect2(-bw * 0.5, by, bw * hp / max_hp, 6), G.RED)


func _bob() -> float:
	return -(10.0 + sin(t * 6.0) * 6.0) if type == "bat" else 0.0


func _draw_sprite(sid: String, up: float) -> void:
	# windup: brute/boss rear back & swell
	var sq := squash
	if wind > 0.0:
		sq *= Vector2(0.92, 1.1)
	set_meta("_xf", Transform2D(spin, sq, 0.0, Vector2(0, up)))
	var mod := Color.WHITE
	if treasure:
		mod = Color(1.0, 0.9, 0.45)
	if burn > 0.0:
		mod = mod * Color(1.0, 0.75, 0.55)
	if shock > 0.0 and int(t * 16.0) % 2 == 0:
		mod = mod * Color(1.0, 1.0, 0.6)
	if freeze > 0.0:
		mod = Color(0.6, 0.85, 1.0)
	if wind > 0.0 and int(t * 20.0) % 2 == 0:
		mod = Color(1.0, 0.6, 0.6)
	Art.draw(self, sid, radius, facing, mod, 1.0 if flash > 0.0 else 0.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_overlay()


func _draw_overlay() -> void:
	var ink := G.INK
	_draw_status()
	if wind > 0.0 and (type == "brute" or is_boss()):
		var a := 0.4 + 0.4 * sin(t * 30.0)
		if type == "batqueen" and G.player != null:
			draw_line(Vector2(0, -20), Vector2(0, -20) + (G.player.position - position).normalized() * 520.0, Color(1, 0.2, 0.1, a), 10.0)
		else:
			draw_arc(Vector2.ZERO, 150.0 if type == "brute" else (230.0 if type == "slimeking" else 260.0), 0, TAU, 48, Color(1, 0.2, 0.1, a), 4.0)
		draw_string_outline(G.font, Vector2(-20, -radius * 3.4 - z), "!", HORIZONTAL_ALIGNMENT_CENTER, 40, 48, 8, ink)
		draw_string(G.font, Vector2(-20, -radius * 3.4 - z), "!", HORIZONTAL_ALIGNMENT_CENTER, 40, 48, G.RED)
	if (type == "brute" or elite) and hp < max_hp:
		var bw := radius * 2.0
		var by := -radius * 3.3 - z - 14.0
		draw_rect(Rect2(-bw * 0.5 - 2, by - 2, bw + 4, 10), ink)
		draw_rect(Rect2(-bw * 0.5, by, bw * hp / max_hp, 6), G.RED)


func _draw_status() -> void:
	var top := Vector2(0, -radius * 2.6 - z)
	if freeze > 0.0:
		var ice := Ink.burst(Vector2(0, -radius * 0.9 - z), radius * 1.15, radius * 1.05, 7, 0.18, salt)
		draw_colored_polygon(ice, Color(0.7, 0.92, 1.0, 0.45))
		Ink.outline(self, ice, 3.0, Color(0.2, 0.45, 0.7))
	if burn > 0.0:
		for i in 3:
			var fp := Vector2((i - 1) * radius * 0.5, -radius * 1.6 - z - absf(sin(t * 9.0 + i * 2.0)) * 10.0)
			var fl := PackedVector2Array([fp + Vector2(-7, 6), fp + Vector2(0, -14), fp + Vector2(7, 6)])
			Ink.shape(self, fl, G.ORANGE, 2.0)
	if shock > 0.0:
		var zz := top + Vector2(radius * 0.6, 8)
		draw_polyline(PackedVector2Array([zz, zz + Vector2(-8, 10), zz + Vector2(2, 12), zz + Vector2(-6, 24)]), G.YELLOW, 4.0)
	if treasure:
		draw_string_outline(G.font_cn, top + Vector2(-60, -20), "宝箱怪", HORIZONTAL_ALIGNMENT_CENTER, 120, 24, 6, G.INK)
		draw_string(G.font_cn, top + Vector2(-60, -20), "宝箱怪", HORIZONTAL_ALIGNMENT_CENTER, 120, 24, G.YELLOW)


func _eyes(c: Vector2, r: float, ink: Color, angry: bool = false) -> void:
	Ink.circle(self, c + Vector2(-r * 0.9, 0), r, Color.WHITE, 2.5, ink)
	Ink.circle(self, c + Vector2(r * 0.9, 0), r, Color.WHITE, 2.5, ink)
	draw_circle(c + Vector2(-r * 0.6, r * 0.15), r * 0.45, ink, true, -1.0, false)
	draw_circle(c + Vector2(r * 1.2, r * 0.15), r * 0.45, ink, true, -1.0, false)
	if angry:
		draw_line(c + Vector2(-r * 1.9, -r * 1.2), c + Vector2(-r * 0.1, -r * 0.5), ink, 3.5)
		draw_line(c + Vector2(r * 1.9, -r * 1.2), c + Vector2(r * 0.1, -r * 0.5), ink, 3.5)