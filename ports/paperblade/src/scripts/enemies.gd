extends Node3D
## Enemy crowd: spawning, steering, spatial hash, damage & death.

const Data := preload("res://scripts/data.gd")
const CELL := 2.0

class E:
	var id := 0
	var kind := ""
	var root: Node3D
	var paper: Node3D
	var spr: Sprite3D
	var hp := 1.0
	var max_hp := 1.0
	var spd := 1.0
	var dmg := 1.0
	var xp := 1.0
	var r := 0.4
	var mass := 1.0
	var col := Color.WHITE
	var kb := Vector3.ZERO
	var flash := 0.0
	var slow_t := 0.0
	var dead := false
	var elite := false
	var boss := false
	var prop := false
	var face := 1.0
	var ph := 0.0
	var h := 1.0
	var base_scale := 1.0
	var touch_t := 0.0
	var anim := "walk"

var list: Array = []
var grid: Dictionary = {}
var next_id := 1
var kills := 0
var spawn_t := 0.0
var elite_t := 50.0
var swarm_times := [150.0, 330.0, 510.0, 690.0]
var boss_times := [300.0, 600.0, 840.0]
var time := 0.0
var alive_foes := 0
var on_kill: Callable


func _key(x: float, z: float) -> int:
	return (int(floor(x / CELL)) + 4096) * 8192 + int(floor(z / CELL)) + 4096


func _role(kind: String) -> String:
	if G.game == null:
		return kind
	return String(G.game.map.roles.get(kind, kind))


func spawn(kind: String, pos: Vector3, elite: bool = false, boss: bool = false) -> E:
	kind = _role(kind)
	var d: Dictionary = Data.ENEMIES[kind]
	var mp: Dictionary = G.game.map
	var e := E.new()
	e.id = next_id
	next_id += 1
	e.kind = kind
	e.prop = bool(d.get("prop", false))
	e.anim = String(d.get("anim", "walk"))
	var tm := time / 60.0
	var hpm := 1.0 + tm * 0.22 + tm * tm * 0.018
	e.max_hp = d.hp * (1.0 if e.prop else hpm * float(mp.hp))
	e.spd = d.spd * randf_range(0.9, 1.1) * (1.0 + minf(tm, 12.0) * 0.015) * float(mp.spd)
	e.dmg = d.dmg * (1.0 + tm * 0.06) * float(mp.dmg)
	e.xp = d.xp
	e.r = d.r
	e.mass = d.mass
	e.col = d.col
	e.h = d.h
	e.base_scale = 1.0
	e.elite = elite
	e.boss = boss
	if elite:
		e.max_hp *= 14.0
		e.base_scale = 1.7
		e.r *= 1.6
		e.mass *= 6.0
		e.xp = 25.0
		e.dmg *= 1.4
	if boss:
		e.max_hp *= 70.0
		e.base_scale = 2.8
		e.r *= 2.5
		e.mass *= 30.0
		e.xp = 120.0
		e.dmg *= 2.0
		e.spd *= 1.15
	e.hp = e.max_hp
	e.ph = randf() * TAU
	var root := Node3D.new()
	add_child(root)
	root.position = Vector3(pos.x, 0, pos.z)
	var paper := Node3D.new()
	paper.rotation.x = -deg_to_rad(18)
	root.add_child(paper)
	var spr := G.sprite(d.tex, d.ps, 1 if e.prop else 0)
	paper.add_child(spr)
	root.add_child(G.shadow(e.r * 2.6 * e.base_scale / maxf(e.base_scale, 1.0)))
	if elite or boss:
		G.sp(spr, "tint", Color(1.25, 0.85, 0.85) if boss else Color(1.15, 1.0, 0.75))
		var ring := Sprite3D.new()
		var rt := G.tex("res://assets/fx/aura.png")
		ring.texture = rt
		ring.material_override = G.mat(rt, 2)
		G.init_inst(ring)
		ring.pixel_size = (e.r * 3.0) / 128.0
		ring.transform = Transform3D(G.flat_basis, Vector3(0, 0.05, 0))
		G.sp(ring, "tint", Color(1.5, 0.3, 0.2, 0.7) if boss else Color(1.4, 1.0, 0.2, 0.6))
		root.add_child(ring)
	e.root = root
	e.paper = paper
	e.spr = spr
	root.scale = Vector3.ONE * 0.01
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector3.ONE * e.base_scale, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	list.append(e)
	return e


func _pick(mix: Dictionary) -> String:
	var tot := 0.0
	for k in mix:
		tot += mix[k]
	var r := randf() * tot
	for k in mix:
		r -= mix[k]
		if r <= 0.0:
			return k
	return mix.keys()[0]


func _edge_pos(center: Vector3) -> Vector3:
	var a := randf() * TAU
	var vp := get_viewport().get_visible_rect().size
	var asp := vp.x / maxf(vp.y, 1.0)
	var rx := 7.6 * asp + 3.0
	var rz := 13.5 if sin(a) < 0.0 else 10.5
	return center + Vector3(cos(a) * rx, 0, sin(a) * rz) * randf_range(1.0, 1.15)


func update_spawns(delta: float) -> void:
	time += delta
	var p = G.player
	var w: Array = Data.WAVES[mini(int(time / 60.0), Data.WAVES.size() - 1)]
	var mix: Dictionary = w[0]
	var minimum: int = w[1]
	spawn_t -= delta
	if spawn_t <= 0.0:
		spawn_t = w[2]
		var need := maxi(minimum - alive_foes, 0)
		var batch := clampi(need, 2 + int(time / 50.0), 40)
		if alive_foes > (260 if G.low else 420):
			batch = 0
		for i in batch:
			spawn(_pick(mix), _edge_pos(p.position))
	elite_t -= delta
	if elite_t <= 0.0:
		elite_t = 60.0
		var ek := "knight" if time > 200.0 else ("goblin" if time > 80.0 else "slime")
		spawn(ek, _edge_pos(p.position), true)
		G.hud.banner("精英来袭", Color(1.0, 0.75, 0.25))
	if swarm_times.size() > 0 and time >= swarm_times[0]:
		swarm_times.pop_front()
		_swarm(p.position)
	if boss_times.size() > 0 and time >= boss_times[0]:
		boss_times.pop_front()
		spawn("knight", _edge_pos(p.position), false, true)
		G.hud.banner("首领现身：" + String(G.game.map.boss), Color(1.0, 0.3, 0.25))
		G.sfx.play("thunder", 0.0, 0.0, 0.6)
		G.game.shake(0.6)


func _swarm(c: Vector3) -> void:
	G.hud.banner("妖潮合围！", Color(0.9, 0.5, 1.0))
	var kind := "bat" if randf() < 0.5 else "slime"
	var n := 46
	for i in n:
		var a := TAU * i / n
		var e := spawn(kind, c + Vector3(cos(a), 0, sin(a)) * 13.0)
		e.spd *= 0.9
		e.max_hp *= 0.6
		e.hp = e.max_hp


func spawn_lantern(pos: Vector3) -> void:
	spawn("lantern", pos)


func rebuild_grid() -> void:
	grid.clear()
	for e in list:
		if e.dead:
			continue
		var k := _key(e.root.position.x, e.root.position.z)
		if grid.has(k):
			grid[k].append(e)
		else:
			grid[k] = [e]


## All enemies whose body overlaps a circle.
func query(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	var r := radius + 1.6
	var x0 := int(floor((pos.x - r) / CELL))
	var x1 := int(floor((pos.x + r) / CELL))
	var z0 := int(floor((pos.z - r) / CELL))
	var z1 := int(floor((pos.z + r) / CELL))
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var k := (cx + 4096) * 8192 + cz + 4096
			if not grid.has(k):
				continue
			for e in grid[k]:
				if e.dead:
					continue
				var dx: float = e.root.position.x - pos.x
				var dz: float = e.root.position.z - pos.z
				var rr: float = radius + e.r * e.base_scale * 0.7
				if dx * dx + dz * dz <= rr * rr:
					out.append(e)
	return out


func nearest(pos: Vector3, maxr: float, exclude: Dictionary = {}) -> E:
	var best: E = null
	var bd := maxr * maxr
	for e in list:
		if e.dead or e.prop or exclude.has(e.id):
			continue
		var dx: float = e.root.position.x - pos.x
		var dz: float = e.root.position.z - pos.z
		var d := dx * dx + dz * dz
		if d < bd:
			bd = d
			best = e
	return best


func random_near(pos: Vector3, maxr: float, n: int) -> Array:
	var c: Array = []
	var m2 := maxr * maxr
	for e in list:
		if e.dead or e.prop:
			continue
		var dx: float = e.root.position.x - pos.x
		var dz: float = e.root.position.z - pos.z
		if dx * dx + dz * dz < m2:
			c.append(e)
	c.shuffle()
	return c.slice(0, n)


## Returns true if this killed the enemy.
func damage(e: E, amount: float, kdir: Vector3 = Vector3.ZERO, kforce: float = 0.0, crit: bool = false, num_col: Color = Color.WHITE) -> bool:
	if e.dead:
		return false
	e.hp -= amount
	e.flash = 1.0
	if kforce > 0.0 and not e.prop:
		var kd := Vector3(kdir.x, 0, kdir.z)
		if kd.length_squared() > 0.0001:
			e.kb += kd.normalized() * kforce / sqrt(e.mass)
	var top: Vector3 = e.root.position + Vector3(0, e.h * e.base_scale + 0.2, 0)
	G.fx.number(top, amount, crit, num_col)
	G.fx.burst(e.root.position + Vector3(0, e.h * 0.5 * e.base_scale, 0), e.col, 2, 4.0, 0.12, 0.35)
	G.sfx.play("hit", -10.0, 0.15)
	if e.hp <= 0.0:
		_kill(e)
		return true
	return false


func _kill(e: E) -> void:
	e.dead = true
	var pos: Vector3 = e.root.position
	var mid := pos + Vector3(0, e.h * 0.5 * e.base_scale, 0)
	if e.prop:
		G.fx.burst(mid, Color(0.75, 0.75, 0.65), 14, 6.0, 0.16, 0.7)
		G.fx.glow(mid, Color(1.6, 1.2, 0.5, 0.9), 2.5, 0.3)
		G.sfx.play("boom", -8.0)
		var r := randf()
		var kind := "chicken"
		if r < 0.16:
			kind = "magnet"
		elif r < 0.32:
			kind = "bomb"
		elif r < 0.40:
			kind = "chest"
		elif r < 0.62:
			kind = "coin"
		elif r < 0.7:
			kind = "coins"
		G.game.pickups.drop_item(kind, pos)
	else:
		kills += 1
		G.fx.burst(mid, e.col, 7 if not e.elite else 26, 6.5, 0.15, 0.65)
		G.fx.burst(mid, Color(1, 1, 0.95), 4, 5.0, 0.1, 0.5)
		G.sfx.play("kill", -7.0, 0.2)
		var v: float = e.xp
		if randf() < 0.012 * G.player.luck:
			G.game.pickups.drop_item(["chicken", "magnet", "bomb"][randi() % 3], pos)
		elif randf() < 0.012 * G.player.luck:
			G.game.pickups.drop_item("coin", pos)
		if e.elite or e.boss:
			G.game.pickups.drop_item("chest", pos)
			for i in (3 if e.boss else 1):
				G.game.pickups.drop_item("coins", pos + Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2)))
			G.fx.glow(mid, Color(1.8, 1.4, 0.6, 1.0), 6.0, 0.5)
			G.fx.ring(pos, Color(1.6, 1.2, 0.5, 1.0), 5.0, 0.5)
			G.game.shake(0.5)
			G.game.hitstop(0.09)
			G.sfx.play("boom", 0.0)
			for i in 8:
				G.game.pickups.drop_gem(pos + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)), v / 8.0)
		else:
			G.game.pickups.drop_gem(pos, v)
		if on_kill.is_valid():
			on_kill.call(e)
	# paper death: flatten, spin and fade
	var tw := e.root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(e.paper, "rotation:x", -PI * 0.5, 0.22).set_ease(Tween.EASE_IN)
	tw.tween_property(e.root, "scale", Vector3(e.base_scale * 1.25, e.base_scale * 0.1, e.base_scale * 1.25), 0.22)
	tw.chain().tween_callback(e.root.queue_free)


func process_enemies(delta: float) -> void:
	var p = G.player
	var pp: Vector3 = p.position
	var cnt := 0
	var far2 := 34.0 * 34.0
	for i in range(list.size() - 1, -1, -1):
		var e: E = list[i]
		if e.dead:
			list[i] = list.back()
			list.pop_back()
			continue
		var pos := e.root.position
		var to := Vector3(pp.x - pos.x, 0, pp.z - pos.z)
		var d2 := to.length_squared()
		if e.prop:
			if d2 > 60.0 * 60.0:
				e.dead = true
				e.root.queue_free()
			_visual(e, delta)
			continue
		cnt += 1
		if d2 > far2 and not e.boss:
			# recycle stragglers in front of the player
			e.root.position = _edge_pos(pp + p.vel.normalized() * 6.0)
			continue
		var d := sqrt(d2)
		var dir := to / maxf(d, 0.001)
		var s := e.spd
		if e.slow_t > 0.0:
			e.slow_t -= delta
			s *= 0.45
		var mv := dir * s
		# separation from neighbours in own cell
		var k := _key(pos.x, pos.z)
		if grid.has(k):
			var cell: Array = grid[k]
			var checks := 0
			for o in cell:
				if o == e:
					continue
				checks += 1
				if checks > 7:
					break
				var ox: float = pos.x - o.root.position.x
				var oz: float = pos.z - o.root.position.z
				var od := ox * ox + oz * oz
				var rr: float = (e.r * e.base_scale + o.r * o.base_scale) * 0.75
				if od < rr * rr and od > 0.0001:
					var odd := sqrt(od)
					mv += Vector3(ox / odd, 0, oz / odd) * (rr - odd) * 6.0 * (o.mass / (o.mass + e.mass)) * 2.0
		e.kb = e.kb.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))
		e.root.position = pos + (mv + e.kb) * delta
		if absf(dir.x) > 0.2:
			var f := 1.0 if dir.x > 0.0 else -1.0
			if f != e.face:
				e.face = f
		# contact damage
		var reach: float = e.r * e.base_scale * 0.8 + 0.35
		if d < reach and not p.dead:
			p.hurt(e.dmg)
		_visual(e, delta)
	alive_foes = cnt


func _visual(e: E, delta: float) -> void:
	if e.flash > 0.0:
		e.flash = maxf(0.0, e.flash - delta * 7.0)
		G.sp(e.spr, "flash", e.flash)
	e.ph += delta * (9.0 if e.anim == "fly" else 6.0) * (e.spd / 2.0 + 0.5)
	# paper flip toward facing (squash scale.x)
	var sx: float = e.paper.scale.x
	sx = move_toward(sx, e.face, delta * 9.0)
	e.paper.scale.x = sx
	match e.anim:
		"fly":
			e.spr.position.y = 0.6 + sin(e.ph * 0.5) * 0.25
			e.paper.scale.y = 1.0 + sin(e.ph * 2.0) * 0.08
		"bounce":
			var b := sin(e.ph)
			e.paper.scale.y = 1.0 + b * 0.12
			e.paper.scale.z = 1.0
			e.paper.scale.x = sx * (1.0 - b * 0.08)
		"float":
			e.spr.position.y = 0.35 + sin(e.ph * 0.6) * 0.18
			e.paper.rotation.z = sin(e.ph * 0.4) * 0.12
			e.paper.scale.y = 1.0 + sin(e.ph * 1.2) * 0.06
		"hop":
			var hp_ := absf(sin(e.ph * 0.75))
			e.spr.position.y = hp_ * 0.45
			e.paper.scale.y = 1.0 + (hp_ - 0.3) * 0.1
		"none":
			pass
		_:
			e.paper.rotation.z = sin(e.ph) * 0.09
			e.spr.position.y = absf(sin(e.ph)) * 0.08
