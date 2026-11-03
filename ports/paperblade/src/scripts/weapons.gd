extends Node3D
## All weapon behaviours. Levels stored in "lv".

const Data := preload("res://scripts/data.gd")
const SWORD_TEX := "res://assets/sword.png"

class Sword:
	var root: Node3D
	var spr: Sprite3D
	var ghosts: Array = []
	var hist: Array = []
	var state := 0 # 0 idle, 1 seek, 2 return
	var cd := 0.0
	var vel := Vector3.ZERO
	var target = null
	var hits: Dictionary = {}
	var pierce := 0
	var life := 0.0
	var dir := Vector3.UP

var lv: Dictionary = {}
var order: Array = []
var time := 0.0
var enemies = null

var swords: Array = []
var launch_gap := 0.0

var wheel_root: Node3D
var wheel_blades: Array = []
var wheel_on := 0.0
var wheel_cd := 0.0
var wheel_ang := 0.0
var wheel_hits: Dictionary = {}

var rain_cd := 1.0
var cres_cd := 0.5
var thunder_cd := 1.0
var aura_tick := 0.0
var aura_spr: Sprite3D

var dmg_dealt: Dictionary = {}


func level_of(w: String) -> int:
	return int(lv.get(w, 0))


func has(w: String) -> bool:
	return lv.has(w)


func add(w: String) -> void:
	if w.ends_with("_evo"):
		var base := w.trim_suffix("_evo")
		lv.erase(base)
		lv[w] = 1
		var i := order.find(base)
		if i >= 0:
			order[i] = w
		else:
			order.append(w)
		dmg_dealt[w] = float(dmg_dealt.get(base, 0.0))
	elif not lv.has(w):
		lv[w] = 1
		order.append(w)
		dmg_dealt[w] = 0.0
	else:
		lv[w] += 1
	_refresh()


func _refresh() -> void:
	if has("wheel") or has("wheel_evo"):
		_build_wheel()
	if has("aura") and aura_spr == null:
		aura_spr = Sprite3D.new()
		var t := G.tex("res://assets/fx/aura.png")
		aura_spr.texture = t
		aura_spr.material_override = G.mat(t, 2)
		G.init_inst(aura_spr)
		aura_spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(aura_spr)


func roll(base: float) -> Array:
	var p = G.player
	var d: float = base * p.might * randf_range(0.9, 1.1)
	var c = randf() < p.crit
	if c:
		d *= 2.0
	return [d, c]


func hit(e, base: float, w: String, kdir: Vector3, kforce: float, col: Color = Color.WHITE) -> bool:
	var r := roll(base)
	dmg_dealt[w] = float(dmg_dealt.get(w, 0.0)) + r[0]
	return enemies.damage(e, r[0], kdir, kforce, r[1], col)


func update(delta: float) -> void:
	time += delta
	if has("sword") or has("sword_evo"):
		_sword(delta)
	if has("wheel") or has("wheel_evo"):
		_wheel(delta)
	if has("rain"):
		_rain(delta)
	if has("crescent"):
		_crescent(delta)
	if has("thunder") or has("thunder_evo"):
		_thunder(delta)
	if has("aura"):
		_aura(delta)


# ---------------------------------------------------------------- flying swords
func _sword_stats() -> Dictionary:
	var p = G.player
	if has("sword_evo"):
		return {"n": 12 + p.amount * 2, "dmg": 30.0, "pierce": 999, "spd": 30.0 * p.proj, "cd": 0.35 * p.cd, "chain": true, "col": Color(0.9, 1.3, 1.8)}
	var l := level_of("sword")
	var n = 3 + int(l >= 2) + int(l >= 4) + int(l >= 6) + 2 * int(l >= 8) + p.amount
	var dmg := 10.0 + 6.0 * int(l >= 3) + 6.0 * int(l >= 5) + 8.0 * int(l >= 8)
	var pierce := 2 + int(l >= 4) + 2 * int(l >= 7)
	var spd = 21.0 * (1.2 if l >= 7 else 1.0) * p.proj
	var c = 0.9 * (0.9 if l >= 5 else 1.0) * p.cd
	return {"n": n, "dmg": dmg, "pierce": pierce, "spd": spd, "cd": c, "chain": true, "col": Color(0.8, 1.15, 1.5)}


func _make_sword() -> Sword:
	var s := Sword.new()
	s.root = Node3D.new()
	add_child(s.root)
	s.spr = G.sprite(SWORD_TEX, 1.5 / 300.0, 2, false)
	G.sp(s.spr, "energy", 1.4)
	s.root.add_child(s.spr)
	for i in 4:
		var g := G.sprite(SWORD_TEX, 1.5 / 300.0, 2, false)
		add_child(g)
		g.visible = false
		s.ghosts.append(g)
	s.root.position = G.player.position + Vector3(0, 1.3, 0)
	s.cd = randf() * 0.4
	return s


func _sword(delta: float) -> void:
	var st := _sword_stats()
	var n: int = st.n
	while swords.size() < n:
		swords.append(_make_sword())
	var p = G.player
	var pp: Vector3 = p.position
	launch_gap -= delta
	var col: Color = st.col
	var wname := "sword_evo" if has("sword_evo") else "sword"
	for i in swords.size():
		var s: Sword = swords[i]
		var ang := time * 1.6 + TAU * i / swords.size()
		var rad := 1.05 + 0.12 * sin(time * 2.0 + i)
		var slot := pp + Vector3(cos(ang) * rad, 1.25 + sin(time * 3.0 + i * 1.7) * 0.12, sin(ang) * rad * 0.55 - 0.2)
		var pos := s.root.position
		match s.state:
			0:
				s.root.position = pos.lerp(slot, 1.0 - exp(-12.0 * delta))
				s.dir = s.dir.lerp(Vector3(cos(ang) * 0.15, 1.0, 0.0).normalized(), 1.0 - exp(-10.0 * delta))
				s.cd -= delta
				if s.cd <= 0.0 and launch_gap <= 0.0:
					var t = _pick_target(pp, 12.5)
					if t != null:
						s.state = 1
						s.target = t
						s.hits.clear()
						s.pierce = st.pierce
						s.life = 0.0
						var to: Vector3 = (t.root.position + Vector3(0, 0.6, 0)) - pos
						s.vel = (to.normalized() + Vector3(0, 0.6, 0)).normalized() * st.spd * 0.6
						launch_gap = 0.06
						G.sfx.play("swing", -12.0, 0.2, 1.3)
			1, 2:
				s.life += delta
				var goal: Vector3
				var spd: float = st.spd
				if s.state == 1:
					if s.target == null or s.target.dead:
						s.target = _next_target(pos, s.hits, 7.0)
						if s.target == null:
							_sword_return(s)
					if s.state == 1:
						goal = s.target.root.position + Vector3(0, 0.6 * s.target.base_scale, 0)
				if s.state == 2:
					goal = slot
					spd *= 1.25
				var to := goal - pos
				var dist := to.length()
				var want := to / maxf(dist, 0.001) * spd
				s.vel = s.vel.lerp(want, 1.0 - exp(-(9.0 + s.life * 20.0) * delta))
				if s.vel.length() < spd * 0.7:
					s.vel = s.vel.normalized() * spd * 0.7
				var np := pos + s.vel * delta
				s.root.position = np
				s.dir = s.vel.normalized()
				# collisions along path
				var hitr := 0.55 if not has("sword_evo") else 0.75
				for e in enemies.query(np, hitr):
					if s.hits.has(e.id):
						continue
					s.hits[e.id] = true
					hit(e, st.dmg, wname, s.vel, 7.0, Color(0.85, 0.95, 1.0))
					G.fx.glow(np, Color(col.r, col.g, col.b, 0.9), 1.4, 0.16)
					if s.state == 1:
						s.pierce -= 1
						if s.pierce <= 0:
							_sword_return(s)
							break
						if e == s.target:
							s.target = _next_target(np, s.hits, 7.0)
							if s.target == null:
								_sword_return(s)
								break
				if s.state == 1 and s.life > 2.6:
					_sword_return(s)
				if s.state == 2 and (dist < 0.6 or s.life > 3.0):
					s.state = 0
					s.cd = st.cd * randf_range(0.85, 1.15)
					s.hits.clear()
		s.root.transform.basis = G.face_basis(s.dir)
		# afterimages
		s.hist.push_front(s.root.transform)
		if s.hist.size() > 9:
			s.hist.pop_back()
		var moving := s.state != 0
		for gi in s.ghosts.size():
			var g: Sprite3D = s.ghosts[gi]
			var hi: int = (gi + 1) * 2
			if moving and hi < s.hist.size():
				g.visible = true
				g.transform = s.hist[hi]
				G.sp(g, "tint", Color(col.r, col.g, col.b, 0.5 - gi * 0.11))
			else:
				g.visible = false
		G.sp(s.spr, "tint", Color(col.r, col.g, col.b, 1.0))


func _sword_return(s: Sword) -> void:
	s.state = 2
	s.target = null
	s.hits.clear()
	s.life = 0.0


func _pick_target(pos: Vector3, r: float):
	# prefer enemies not already being chased
	var taken: Dictionary = {}
	for s in swords:
		if s.state == 1 and s.target != null:
			taken[s.target.id] = true
	var t = enemies.nearest(pos, r, taken)
	if t == null:
		t = enemies.nearest(pos, r)
	return t


func _next_target(pos: Vector3, hits: Dictionary, r: float):
	return enemies.nearest(pos, r, hits)


# ---------------------------------------------------------------- blade wheel
func _wheel_stats() -> Dictionary:
	var p = G.player
	if has("wheel_evo"):
		return {"n": 9 + p.amount, "r": 3.1 * p.area, "spd": 4.4, "dmg": 24.0, "dur": 999.0, "cd": 0.0, "col": Color(1.8, 0.9, 0.25)}
	var l := level_of("wheel")
	return {
		"n": 3 + int(l >= 2) + int(l >= 5) + int(l >= 8) + p.amount,
		"r": 2.1 * (1.0 + 0.25 * int(l >= 3) + 0.25 * int(l >= 6)) * p.area,
		"spd": 3.4 * (1.3 if l >= 3 else 1.0),
		"dmg": 9.0 + 6.0 * int(l >= 4) + 6.0 * int(l >= 7),
		"dur": (3.0 + 0.5 * int(l >= 4) + 1.0 * int(l >= 7)) * p.dur,
		"cd": 3.0 * p.cd,
		"col": Color(1.7, 1.25, 0.35)}


func _build_wheel() -> void:
	if wheel_root == null:
		wheel_root = Node3D.new()
		add_child(wheel_root)
		wheel_on = 0.0
		wheel_cd = 0.0


func _wheel(delta: float) -> void:
	var st := _wheel_stats()
	var p = G.player
	wheel_root.position = p.position
	if wheel_on > 0.0:
		wheel_on -= delta
		if wheel_on <= 0.0 and st.dur < 900.0:
			wheel_cd = st.cd
			for b in wheel_blades:
				var tw: Tween = b.create_tween()
				tw.tween_property(b, "scale", Vector3.ONE * 0.001, 0.2)
	else:
		wheel_cd -= delta
		if wheel_cd <= 0.0:
			wheel_on = st.dur
			G.sfx.play("swing", -6.0, 0.0, 0.7)
			for b in wheel_blades:
				b.scale = Vector3.ONE * 0.001
				var tw: Tween = b.create_tween()
				tw.tween_property(b, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var n: int = st.n
	while wheel_blades.size() < n:
		var b := G.sprite(SWORD_TEX, 1.3 / 300.0, 2, false)
		G.sp(b, "energy", 1.3)
		wheel_root.add_child(b)
		wheel_blades.append(b)
	if wheel_on <= 0.0:
		var any := false
		for b in wheel_blades:
			if b.scale.x > 0.01:
				any = true
		if not any:
			for b in wheel_blades:
				b.visible = false
			return
	wheel_ang += st.spd * delta
	var rr: float = st.r
	var col: Color = st.col
	for i in wheel_blades.size():
		var b: Sprite3D = wheel_blades[i]
		b.visible = true
		var a := wheel_ang + TAU * i / wheel_blades.size()
		var out := Vector3(cos(a), 0, sin(a))
		var tang := Vector3(-sin(a), 0, cos(a))
		b.transform.basis = G.face_basis(tang + Vector3(0, 0.35, 0)).scaled(b.scale)
		b.position = out * rr + Vector3(0, 0.8, 0)
		G.sp(b, "tint", col)
		if wheel_on > 0.0:
			var wp = p.position + b.position
			for e in enemies.query(wp, 0.75):
				var last: float = wheel_hits.get(e.id, -9.0)
				if time - last < 0.4:
					continue
				wheel_hits[e.id] = time
				hit(e, st.dmg, "wheel_evo" if has("wheel_evo") else "wheel", out, 6.0, Color(1.0, 0.85, 0.4))
				G.fx.burst(wp, Color(1.0, 0.8, 0.3), 3, 6.0, 0.1, 0.3)
	if wheel_hits.size() > 600:
		wheel_hits.clear()


# ---------------------------------------------------------------- sword rain
func _rain(delta: float) -> void:
	rain_cd -= delta
	if rain_cd > 0.0:
		return
	var p = G.player
	var l := level_of("rain")
	var n = 1 + int(l >= 2) + int(l >= 5) + 2 * int(l >= 7) + p.amount
	var dmg := 25.0 + 10.0 * int(l >= 3) + 10.0 * int(l >= 6) + 10.0 * int(l >= 8)
	var rad = 1.8 * (1.0 + 0.25 * int(l >= 4) + 0.25 * int(l >= 8)) * p.area
	rain_cd = 2.6 * (0.9 if l >= 5 else 1.0) * p.cd
	var targets: Array = enemies.random_near(p.position, 12.0, n)
	for i in n:
		var pos: Vector3
		if i < targets.size():
			pos = targets[i].root.position
		else:
			pos = p.position + Vector3(randf_range(-7, 7), 0, randf_range(-5, 5))
		_drop_sword(Vector3(pos.x, 0, pos.z), dmg, rad, i * 0.09)


func _drop_sword(pos: Vector3, dmg: float, rad: float, delay: float) -> void:
	var s := G.sprite(SWORD_TEX, 3.4 / 300.0, 2, false)
	G.sp(s, "tint", Color(1.8, 1.4, 0.5, 1.0))
	G.sp(s, "energy", 1.3)
	add_child(s)
	s.transform = Transform3D(G.face_basis(Vector3(0.05, -1, 0)), pos + Vector3(0, 12, 0))
	s.visible = false
	var mark = G.fx.glow(pos + Vector3(0, 0.05, 0), Color(1.4, 1.0, 0.3, 0.5), rad * 2.0, 0.3 + delay, "res://assets/fx/ring.png", 1.0, 0.9, true)
	var tw := s.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void: s.visible = true)
	tw.tween_property(s, "position", pos + Vector3(0, 1.4, 0), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: _rain_impact(pos, dmg, rad))
	tw.tween_method(func(k: float) -> void: G.sp(s, "tint", Color(1.8, 1.4, 0.5, 1.0 - k)), 0.0, 1.0, 0.45)
	tw.tween_callback(s.queue_free)


func _rain_impact(pos: Vector3, dmg: float, rad: float) -> void:
	for e in enemies.query(pos, rad):
		var d: Vector3 = e.root.position - pos
		hit(e, dmg, "rain", d, 10.0, Color(1.0, 0.9, 0.5))
	G.fx.ring(pos, Color(1.6, 1.2, 0.4, 1.0), rad, 0.35)
	G.fx.glow(pos + Vector3(0, 0.5, 0), Color(1.7, 1.3, 0.5, 0.9), rad * 2.2, 0.25)
	G.fx.burst(pos + Vector3(0, 0.2, 0), Color(0.55, 0.45, 0.3), 8, 7.0, 0.14, 0.6)
	G.sfx.play("boom", -12.0, 0.15, 1.3)
	G.game.shake(0.12)


# ---------------------------------------------------------------- frost crescent
func _crescent(delta: float) -> void:
	cres_cd -= delta
	if cres_cd > 0.0:
		return
	var p = G.player
	var l := level_of("crescent")
	var dmg := 18.0 + 8.0 * int(l >= 3) + 8.0 * int(l >= 6) + 10.0 * int(l >= 8)
	var rad = 2.7 * (1.0 + 0.2 * int(l >= 4) + 0.2 * int(l >= 7)) * p.area
	cres_cd = 1.5 * (0.85 if l >= 5 else 1.0) * p.cd
	var f: Vector3 = p.facing
	var dirs: Array = [f]
	if l >= 2:
		dirs.append(-f)
	if l >= 8:
		dirs.append(Vector3(-f.z, 0, f.x))
		dirs.append(Vector3(f.z, 0, -f.x))
	for k in 1 + p.amount:
		var tw := create_tween()
		tw.tween_interval(k * 0.16)
		tw.tween_callback(func() -> void:
			for d in dirs:
				_slash(d, dmg, rad))


func _slash(dir: Vector3, dmg: float, rad: float) -> void:
	var p = G.player
	var c: Vector3 = p.position
	G.sfx.play("swing", -5.0, 0.1, 0.9)
	var s := Sprite3D.new()
	var t := G.tex("res://assets/fx/crescent.png")
	s.texture = t
	s.material_override = G.mat(t, 2)
	G.init_inst(s)
	s.pixel_size = rad * 2.2 / 128.0
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(s)
	var b := G.ground_basis(dir)
	s.transform = Transform3D(b, c + dir * rad * 0.25 + Vector3(0, 0.5, 0))
	s.scale = Vector3.ONE * 0.6
	var tw := s.create_tween()
	tw.tween_method(func(k: float) -> void:
		s.position = G.player.position + dir * rad * (0.25 + 0.3 * k) + Vector3(0, 0.5, 0)
		s.scale = Vector3.ONE * lerpf(0.6, 1.1, k)
		G.sp(s, "tint", Color(0.7, 1.2, 1.8, 1.0 - k * k))
	, 0.0, 1.0, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(s.queue_free)
	for e in enemies.query(c + dir * rad * 0.45, rad * 0.85):
		var to: Vector3 = e.root.position - c
		to.y = 0
		if to.length() > 0.5 and to.normalized().dot(dir) < -0.15:
			continue
		e.slow_t = 1.6
		hit(e, dmg, "crescent", dir + to.normalized() * 0.5, 10.0, Color(0.7, 0.9, 1.0))
		G.fx.burst(e.root.position + Vector3(0, 0.7, 0), Color(0.75, 0.9, 1.0), 2, 5.0, 0.1, 0.4)


# ---------------------------------------------------------------- palm thunder
func _thunder(delta: float) -> void:
	thunder_cd -= delta
	if thunder_cd > 0.0:
		return
	var p = G.player
	var evo := has("thunder_evo")
	var n: int
	var dmg: float
	var rad: float
	var col: Color
	if evo:
		n = 6 + p.amount
		dmg = 60.0
		rad = 2.0 * p.area
		thunder_cd = 1.1 * p.cd
		col = Color(1.3, 0.6, 2.0)
	else:
		var l := level_of("thunder")
		n = 2 + int(l >= 2) + int(l >= 5) + int(l >= 7) + p.amount
		dmg = 22.0 + 12.0 * int(l >= 4) + 15.0 * int(l >= 8)
		rad = 1.4 * (1.3 if l >= 3 else 1.0) * (1.2 if l >= 8 else 1.0) * p.area
		thunder_cd = 2.2 * (0.85 if l >= 6 else 1.0) * p.cd
		col = Color(1.8, 1.6, 0.6)
	var targets: Array = enemies.random_near(p.position, 13.0, n)
	for i in targets.size():
		var e = targets[i]
		var tw := create_tween()
		tw.tween_interval(i * 0.06)
		var pos: Vector3 = e.root.position
		tw.tween_callback(func() -> void: _strike(pos, dmg, rad, col, 3 if evo else 0, {}))


func _strike(pos: Vector3, dmg: float, rad: float, col: Color, chains: int, hitset: Dictionary) -> void:
	var b := G.sprite("res://assets/fx/bolt.png", 9.0 / 256.0, 2, true)
	G.sp(b, "tint", col)
	add_child(b)
	b.transform = Transform3D(G.face_basis(Vector3.UP), pos)
	var tw := b.create_tween()
	tw.tween_method(func(k: float) -> void:
		G.sp(b, "tint", Color(col.r, col.g, col.b, 1.0 - k))
		b.scale = Vector3(1.0 - k * 0.6, 1.0, 1.0)
	, 0.0, 1.0, 0.25)
	tw.tween_callback(b.queue_free)
	G.fx.glow(pos + Vector3(0, 0.4, 0), Color(col.r, col.g, col.b, 1.0), rad * 2.6, 0.25)
	G.fx.ring(pos, col, rad, 0.3)
	G.fx.burst(pos + Vector3(0, 0.3, 0), Color(1.0, 0.95, 0.6), 6, 8.0, 0.1, 0.4)
	G.sfx.play("thunder", -9.0, 0.2, 1.2)
	G.game.shake(0.1)
	var last = null
	for e in enemies.query(pos, rad):
		hitset[e.id] = true
		hit(e, dmg, "thunder_evo" if has("thunder_evo") else "thunder", e.root.position - pos, 6.0, Color(1.0, 1.0, 0.5))
		last = e
	if chains > 0:
		var nx = enemies.nearest(pos, 6.0, hitset)
		if nx != null:
			var np: Vector3 = nx.root.position
			_arc(pos + Vector3(0, 0.6, 0), np + Vector3(0, 0.6, 0), col)
			var tw2 := create_tween()
			tw2.tween_interval(0.08)
			tw2.tween_callback(func() -> void: _strike(np, dmg * 0.8, rad * 0.8, col, chains - 1, hitset))


func _arc(a: Vector3, b: Vector3, col: Color) -> void:
	var d := b - a
	var s := G.sprite("res://assets/fx/bolt.png", d.length() / 256.0, 2, false)
	G.sp(s, "tint", col)
	add_child(s)
	s.transform = Transform3D(G.face_basis(d), (a + b) * 0.5)
	var tw := s.create_tween()
	tw.tween_method(func(k: float) -> void: G.sp(s, "tint", Color(col.r, col.g, col.b, 1.0 - k)), 0.0, 1.0, 0.2)
	tw.tween_callback(s.queue_free)


# ---------------------------------------------------------------- spirit aura
func _aura(delta: float) -> void:
	var p = G.player
	var l := level_of("aura")
	var rad = 1.8 * (1.0 + 0.2 * (int(l >= 2) + int(l >= 4) + int(l >= 6) + int(l >= 8))) * p.area
	var dmg := 5.0 + 3.0 * int(l >= 3) + 3.0 * int(l >= 5) + 4.0 * int(l >= 7) + 4.0 * int(l >= 8)
	var tick := 0.4 if l >= 4 else 0.55
	aura_spr.pixel_size = rad * 2.0 / 128.0
	aura_spr.transform = Transform3D(G.flat_basis.rotated(Vector3.UP, time * 0.8), p.position + Vector3(0, 0.07, 0))
	G.sp(aura_spr, "tint", Color(0.4, 1.3, 0.6, 0.35 + sin(time * 4.0) * 0.06))
	aura_tick -= delta
	if aura_tick <= 0.0:
		aura_tick = tick
		var any := false
		for e in enemies.query(p.position, rad):
			hit(e, dmg, "aura", e.root.position - p.position, 3.5, Color(0.7, 1.0, 0.7))
			any = true
		if any:
			G.fx.ring(p.position, Color(0.5, 1.4, 0.7, 0.6), rad, 0.3)


# ---------------------------------------------------------------- level-up offers
func can_take(w: String) -> bool:
	return not w.ends_with("_evo")


func evolvable() -> Array:
	var out: Array = []
	for w in lv.keys():
		var d: Dictionary = Data.WEAPONS[w]
		if d.has("evo") and lv[w] >= d.max and G.player.passives.has(d.req):
			out.append(d.evo)
	return out
