extends Node
## Run orchestrator: world, camera, game loop, level-ups, chests.

const Data := preload("res://scripts/data.gd")
const FxS := preload("res://scripts/fx.gd")
const SfxS := preload("res://scripts/sfx.gd")
const HudS := preload("res://scripts/hud.gd")
const PlayerS := preload("res://scripts/player.gd")
const EnemiesS := preload("res://scripts/enemies.gd")
const WeaponsS := preload("res://scripts/weapons.gd")
const PickupsS := preload("res://scripts/pickups.gd")
const TouchS := preload("res://scripts/touch_controls.gd")
const GROUND := preload("res://shaders/ground.gdshader")
const CH := 14.0
const CAM_DIST := 21.0

var world: Node3D
var cam: Camera3D
var player
var enemies
var weapons
var pickups
var fx
var hud
var ground: MeshInstance3D
var props_root: Node3D
var chunks: Dictionary = {}

var state := "title"
var time := 0.0
var shake_amt := 0.0
var stop_t := 0.0
var rerolls := 3
var lantern_t := 18.0
var cam_pos := Vector3.ZERO
var map: Dictionary = {}
var gold := 0.0
var weather: GPUParticles3D
var touch_controls


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	G.game = self
	randomize()
	map = Data.MAPS[clampi(G.map_id, 0, Data.MAPS.size() - 1)]
	rerolls = 3 + G.meta("reroll")
	world = Node3D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	var sfx := SfxS.new()
	add_child(sfx)
	G.sfx = sfx
	hud = HudS.new()
	add_child(hud)
	G.hud = hud
	touch_controls = TouchS.new()
	touch_controls.game = self
	add_child(touch_controls)
	_build_env()
	ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(140, 140)
	ground.mesh = pm
	var gm := ShaderMaterial.new()
	gm.shader = GROUND
	gm.set_shader_parameter("tex", load("res://assets/floor.png"))
	gm.set_shader_parameter("tile", 8.0)
	var ft: Color = map.floor
	gm.set_shader_parameter("tint", Vector3(ft.r, ft.g, ft.b))
	ground.material_override = gm
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(ground)
	props_root = Node3D.new()
	world.add_child(props_root)
	pickups = PickupsS.new()
	world.add_child(pickups)
	enemies = EnemiesS.new()
	world.add_child(enemies)
	player = PlayerS.new()
	world.add_child(player)
	G.player = player
	weapons = WeaponsS.new()
	weapons.enemies = enemies
	world.add_child(weapons)
	fx = FxS.new()
	world.add_child(fx)
	G.fx = fx
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.5
	cam.far = 120.0
	world.add_child(cam)
	G.cam = cam
	cam_pos = player.position
	_place_cam(0.0)
	_update_chunks()
	_build_weather()
	hud.chosen.connect(_on_chosen)
	hud.reroll.connect(_on_reroll)
	hud.start_pressed.connect(_on_start_pressed)
	hud.map_chosen.connect(_on_map_chosen)
	hud.meta_buy.connect(_on_meta_buy)
	hud.meta_refund.connect(_on_meta_refund)
	hud.title_pressed.connect(_to_title)
	hud.restart_pressed.connect(restart)
	hud.resume_pressed.connect(_resume)
	hud.chest_done.connect(_resume)
	if G.bot:
		Engine.time_scale = G.bot_speed
		Engine.max_physics_steps_per_frame = 64
	if G.ui_shot != "":
		hud.show_title()
		if G.ui_shot == "maps":
			hud.show_maps(self)
		elif G.ui_shot == "meta":
			hud.show_meta(self)
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png("user://shot_ui_%s.png" % G.ui_shot)
		get_tree().quit()
		return
	if G.autostart:
		start_run()
	else:
		hud.show_title()
		G.sfx.play_music("title", 0.5)


func _build_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = map.bg
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = not G.low
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.6)
	env.set_glow_level(4, 0.3)
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	we.environment = env
	add_child(we)


func start_run() -> void:
	G.autostart = false
	hud.close_menu()
	hud.hud.visible = true
	state = "play"
	get_tree().paused = false
	weapons.add("sword")
	if G.all_weapons:
		for id in ["wheel", "rain", "crescent", "thunder", "aura"]:
			for i in 5:
				weapons.add(id)
		for i in 7:
			weapons.add("sword")
		player.passives["book"] = 1
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			open_chest()
			print("[BOT] after chest: ", weapons.lv, " order=", weapons.order))
		player.passives["armor"] = 5
		player.recalc()
	G.sfx.start_music()
	hud.banner(String(map.name) + " · 存活 15 分钟", Color(0.7, 0.9, 1.0))


func _on_start_pressed() -> void:
	hud.show_maps(self)


func _on_map_chosen(i: int) -> void:
	if not G.map_unlocked(i):
		return
	G.map_id = i
	G.autostart = true
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_meta_buy(id: String) -> void:
	var lv := G.meta(id)
	var d: Dictionary = Data.META[id]
	if lv >= int(d.max):
		return
	var cost := Data.meta_cost(id, lv, _meta_bought())
	if int(G.save.gold) < cost:
		G.sfx.play("hurt", -8.0, 0.0, 1.4)
		return
	G.save.gold = int(G.save.gold) - cost
	G.save.spent = int(G.save.get("spent", 0)) + cost
	G.save.meta[id] = lv + 1
	G.write_save()
	G.sfx.play("coin", -2.0, 0.0, 0.9)
	G.sfx.play("levelup", -8.0, 0.0, 1.3)
	hud.show_meta(self)


func _on_meta_refund() -> void:
	G.save.gold = int(G.save.gold) + int(G.save.get("spent", 0))
	G.save.spent = 0
	G.save.meta = {}
	G.write_save()
	G.sfx.play("chest", -4.0)
	hud.show_meta(self)


func _meta_bought() -> int:
	var n := 0
	for k in G.save.meta:
		n += int(G.save.meta[k])
	return n


func _to_title() -> void:
	G.autostart = false
	get_tree().paused = false
	get_tree().reload_current_scene()


func add_gold(v: float, pos: Vector3) -> void:
	v *= 1.0 + 0.1 * G.meta("greed")
	v *= float(map.gold)
	gold += v
	G.sfx.play("coin", -6.0, 0.15)
	fx.text(pos + Vector3(0, 1.6, 0), "+%d" % int(round(v)), Color(1.0, 0.85, 0.3), 46)


func bank_gold() -> int:
	var g := int(round(gold))
	gold = 0.0
	G.save.gold = int(G.save.gold) + g
	var key := str(G.map_id)
	if time > float(G.save.best.get(key, 0.0)):
		G.save.best[key] = time
	G.write_save()
	return g


func restart() -> void:
	G.autostart = true
	get_tree().paused = false
	get_tree().reload_current_scene()


# ------------------------------------------------------------------ loop
func _physics_process(delta: float) -> void:
	if state != "play" or get_tree().paused:
		return
	if stop_t > 0.0:
		stop_t -= delta
		return
	time += delta
	enemies.time = time
	player.update(delta)
	enemies.rebuild_grid()
	enemies.update_spawns(delta)
	enemies.process_enemies(delta)
	enemies.rebuild_grid()
	weapons.update(delta)
	lantern_t -= delta
	if lantern_t <= 0.0:
		lantern_t = 22.0
		var a := randf() * TAU
		enemies.spawn_lantern(player.position + Vector3(cos(a), 0, sin(a)) * randf_range(7.0, 11.0))
	_update_chunks()
	if weather != null:
		weather.position = Vector3(player.position.x, weather.position.y, player.position.z - 2.0)
	if state == "play" and player.pending_levels > 0 and not player.dead:
		_open_levelup(true)
	if state == "play" and time >= Data.RUN_LENGTH:
		game_over(true)


var bot_log_t := 0.0
var bot_hold := 0


func _process(delta: float) -> void:
	_place_cam(delta)
	if G.bot:
		_bot(delta)
	if G.shots:
		_shots()
	if state != "title":
		hud.refresh(player, weapons, time, enemies.kills)


func _place_cam(delta: float) -> void:
	var tgt: Vector3 = player.position + player.vel * 0.12
	cam_pos = cam_pos.lerp(tgt, 1.0 - exp(-8.0 * delta)) if delta > 0.0 else tgt
	shake_amt = maxf(0.0, shake_amt - delta * 2.2)
	var sh := shake_amt * shake_amt
	var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * sh * 0.7
	cam.position = cam_pos + G.to_cam * CAM_DIST + off
	cam.look_at(cam_pos + off * 0.5 + Vector3(0, 0.6, 0), Vector3.UP)
	ground.position = Vector3(snappedf(player.position.x, 1.0), 0, snappedf(player.position.z, 1.0))


func shake(a: float) -> void:
	shake_amt = clampf(maxf(shake_amt, a), 0.0, 1.0)


func hitstop(t: float) -> void:
	stop_t = maxf(stop_t, t)


var shot_times := [4.0, 25.0, 70.0, 120.0]
var shot_lv := false


var shot_chest := false


func _shots() -> void:
	if state == "chest" and not shot_chest and not hud.gacha.is_empty() and hud.gacha.phase == 1 and hud.gacha.t > 0.9:
		shot_chest = true
		get_viewport().get_texture().get_image().save_png("user://shot_chest.png")
	if state == "level" and not shot_lv and hud.cards.size() > 0 and time > 15.0:
		shot_lv = true
		await get_tree().create_timer(0.6, true, false, true).timeout
		get_viewport().get_texture().get_image().save_png("user://shot_levelup.png")
	if shot_times.size() > 0 and time >= shot_times[0]:
		var t: float = shot_times.pop_front()
		get_viewport().get_texture().get_image().save_png("user://shot_%d.png" % int(t))
		if shot_times.is_empty():
			get_tree().quit()


func _bot(delta: float) -> void:
	if state == "level" and hud.cards.size() > 0 and (not G.shots or time <= 15.0 or shot_lv and Time.get_ticks_msec() - bot_hold > 1500):
		_on_chosen(_options()[0])
	if state != "level":
		bot_hold = Time.get_ticks_msec()
	if state == "chest":
		pass
	elif state == "end":
		print("[BOT] END t=%.1f lv=%d kills=%d hp=%.0f weapons=%s" % [time, player.level, enemies.kills, player.hp, str(weapons.lv)])
		get_tree().quit()
	elif false:
		_resume()
	elif state == "end":
		print("[BOT] END t=%.1f lv=%d kills=%d hp=%.0f weapons=%s" % [time, player.level, enemies.kills, player.hp, str(weapons.lv)])
		get_tree().quit()
	bot_log_t -= delta
	if bot_log_t < -10.0:
		bot_log_t = 0.0
		print("[BOT] stuck state=", state, " menu=", hud.menu_kind, " gacha=", {} if hud.gacha.is_empty() else {"phase": hud.gacha.phase, "t": hud.gacha.t})
	if bot_log_t <= 0.0 and state == "play":
		bot_log_t = 5.0
		print("[BOT] t=%.0f lv=%d kills=%d hp=%.0f/%.0f foes=%d gems=%d fps=%d w=%s p=%s" % [time, player.level, enemies.kills, player.hp, player.max_hp, enemies.alive_foes, pickups.gems.size(), Engine.get_frames_per_second(), str(weapons.lv), str(player.passives)])


func _build_weather() -> void:
	var kind: String = map.weather
	if kind == "":
		return
	weather = GPUParticles3D.new()
	weather.amount = (260 if kind == "snow" else 90) / (2 if G.low else 1)
	weather.lifetime = 6.0
	weather.preprocess = 6.0
	weather.visibility_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 30, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(26, 0.5, 20)
	if kind == "snow":
		pm.direction = Vector3(0.3, -1, 0.1)
		pm.spread = 15.0
		pm.initial_velocity_min = 1.5
		pm.initial_velocity_max = 2.6
		pm.gravity = Vector3(0.25, -0.3, 0)
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.6
		pm.scale_min = 0.6
		pm.scale_max = 1.3
	else:
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 30.0
		pm.initial_velocity_min = 0.4
		pm.initial_velocity_max = 1.0
		pm.gravity = Vector3(0, 0.15, 0)
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 1.2
		pm.scale_min = 0.5
		pm.scale_max = 1.1
	weather.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.16) if kind == "snow" else Vector2(0.13, 0.13)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if kind != "snow" else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = G.tex("res://assets/fx/softglow.png")
	m.albedo_color = Color(1, 1, 1, 0.85) if kind == "snow" else Color(1.6, 0.5, 0.9, 0.8)
	q.material = m
	weather.draw_pass_1 = q
	weather.position = Vector3(0, 9 if kind == "snow" else 0.2, 0)
	world.add_child(weather)


# ------------------------------------------------------------------ props
func _update_chunks() -> void:
	var cx := floori(player.position.x / CH)
	var cz := floori(player.position.z / CH)
	var want: Dictionary = {}
	for x in range(cx - 2, cx + 3):
		for z in range(cz - 2, cz + 3):
			var k := Vector2i(x, z)
			want[k] = true
			if not chunks.has(k):
				chunks[k] = _make_chunk(k)
	for k in chunks.keys():
		if not want.has(k):
			chunks[k].queue_free()
			chunks.erase(k)


const DECALS := [
	["res://assets/fx/deco_bagua.png", 7.5, 0.10],
	["res://assets/fx/deco_array.png", 6.0, 0.10],
	["res://assets/fx/deco_taiji.png", 3.2, 0.12],
	["res://assets/fx/deco_cloud.png", 3.6, 0.13],
	["res://assets/fx/deco_glyph_0.png", 2.6, 0.10],
	["res://assets/fx/deco_glyph_1.png", 2.6, 0.10],
	["res://assets/fx/deco_glyph_2.png", 2.6, 0.10],
	["res://assets/fx/deco_glyph_3.png", 2.6, 0.10],
]


func _decal(parent: Node3D, path: String, size: float, alpha: float, pos: Vector3, rot: float, col: Color) -> void:
	var s := Sprite3D.new()
	var t: Texture2D = G.tex(path)
	s.texture = t
	s.material_override = G.mat(t, 2)
	G.init_inst(s)
	s.pixel_size = size / float(t.get_width())
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.transform = Transform3D(G.flat_basis.rotated(Vector3.UP, rot), pos + Vector3(0, 0.02, 0))
	G.sp(s, "tint", Color(col.r, col.g, col.b, alpha))
	parent.add_child(s)


func _make_chunk(k: Vector2i) -> Node3D:
	var n := Node3D.new()
	props_root.add_child(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(k) + 1337
	var deco_a: float = map.deco_a
	var jade: Color = map.deco[0]
	var gold: Color = map.deco[1]
	# one large motif (bagua / array) in roughly every third chunk
	var cpos := Vector3((k.x + rng.randf_range(0.3, 0.7)) * CH, 0, (k.y + rng.randf_range(0.3, 0.7)) * CH)
	var roll := rng.randf()
	if roll < 0.35:
		var d: Array = DECALS[rng.randi_range(0, 1)]
		_decal(n, d[0], d[1] * rng.randf_range(0.9, 1.15), d[2] * deco_a, cpos, rng.randf() * TAU, jade if rng.randf() < 0.7 else gold)
	# a few small motifs: clouds, taiji, glyphs
	for i in rng.randi_range(1, 3):
		var p := Vector3((k.x + rng.randf()) * CH, 0, (k.y + rng.randf()) * CH)
		if roll < 0.35 and p.distance_to(cpos) < 5.0:
			continue
		var d: Array = DECALS[rng.randi_range(2, DECALS.size() - 1)]
		var rot := rng.randf_range(-0.3, 0.3) if String(d[0]).contains("cloud") else rng.randf() * TAU
		_decal(n, d[0], d[1] * rng.randf_range(0.85, 1.2), d[2] * deco_a, p, rot, jade)
	# sparse scenery so the floor stays calm and readable
	for i in rng.randi_range(0, 2):
		var pos := Vector3((k.x + rng.randf()) * CH, 0, (k.y + rng.randf()) * CH)
		if pos.length() < 5.0:
			continue
		var r := rng.randf()
		var pr: Array = map.props[2]
		var acc := 0.0
		for cand in map.props:
			acc += float(cand[3])
			if r < acc:
				pr = cand
				break
		var path: String = pr[0]
		var h: float = pr[1]
		var sh: float = pr[2]
		var t: Texture2D = G.tex(path)
		h *= rng.randf_range(0.85, 1.15)
		var root := Node3D.new()
		root.position = pos
		n.add_child(root)
		var paper := Node3D.new()
		paper.rotation.x = -deg_to_rad(16)
		root.add_child(paper)
		var s := G.sprite(path, h / float(t.get_height()), 1)
		G.sp(s, "tint", map.prop_tint)
		if rng.randf() < 0.5:
			G.sp(s, "flip", 1.0)
		paper.add_child(s)
		root.add_child(G.shadow(sh))
	return n


# ------------------------------------------------------------------ level up
func _pool() -> Array:
	var pool: Array = []
	var wcount: int = weapons.order.size()
	for id in Data.BASE_WEAPONS:
		if weapons.has(id + "_evo"):
			continue
		var d: Dictionary = Data.WEAPONS[id]
		if weapons.has(id):
			var l: int = weapons.level_of(id)
			if l < d.max:
				pool.append({"type": "weapon", "id": id, "name": d.name, "tag": "Lv %d → %d" % [l, l + 1], "desc": d.desc[l], "w": 1.2})
		elif wcount < 6:
			pool.append({"type": "weapon", "id": id, "name": d.name, "tag": "新！", "desc": d.desc[0], "w": 1.0})
	var pcount: int = player.passives.size()
	for id in Data.PASSIVES:
		var d: Dictionary = Data.PASSIVES[id]
		var l: int = player.passives.get(id, 0)
		if l > 0 and l < d.max:
			pool.append({"type": "passive", "id": id, "name": d.name, "tag": "Lv %d → %d" % [l, l + 1], "desc": d.desc, "w": 0.9})
		elif l == 0 and pcount < 6:
			pool.append({"type": "passive", "id": id, "name": d.name, "tag": "新！", "desc": d.desc, "w": 0.75})
	return pool


func _pick(pool: Array, n: int) -> Array:
	var out: Array = []
	var p := pool.duplicate()
	while out.size() < n and p.size() > 0:
		var tot := 0.0
		for o in p:
			tot += o.w
		var r := randf() * tot
		for i in p.size():
			r -= p[i].w
			if r <= 0.0 or i == p.size() - 1:
				out.append(p[i])
				p.remove_at(i)
				break
	return out


func _heal_opt() -> Dictionary:
	return {"type": "heal", "id": "chicken", "name": "烤鸡腿", "tag": "回复", "desc": "回复 30 点生命", "w": 1.0}


func _options() -> Array:
	var n := 4 if player.luck >= 1.25 else 3
	var o := _pick(_pool(), n)
	if o.is_empty():
		o.append(_heal_opt())
	return o


func _open_levelup(juice: bool) -> void:
	state = "level"
	if juice:
		G.sfx.play("levelup", -3.0, 0.0)
		var pp: Vector3 = player.position
		fx.ring(pp, Color(1.4, 1.3, 0.6, 1.0), 5.0, 0.5)
		fx.glow(pp + Vector3(0, 1, 0), Color(1.6, 1.4, 0.7, 0.9), 5.0, 0.5)
		fx.burst(pp + Vector3(0, 1, 0), Color(1.0, 0.95, 0.5), 22, 8.0, 0.14, 0.9, 6.0)
		for e in enemies.query(pp, 5.0):
			var d: Vector3 = e.root.position - pp
			e.kb += Vector3(d.x, 0, d.z).normalized() * 16.0 / sqrt(e.mass)
	get_tree().paused = true
	G.sfx.muffle(true)
	hud.show_levelup(_options(), player.level - player.pending_levels + 1, rerolls)


func _apply(opt: Dictionary) -> void:
	match opt.type:
		"weapon", "evo":
			weapons.add(opt.id)
		"passive":
			player.passives[opt.id] = int(player.passives.get(opt.id, 0)) + 1
			player.recalc()
		"heal":
			player.heal(30.0)


func _on_chosen(opt: Dictionary) -> void:
	if state != "level":
		return
	_apply(opt)
	player.pending_levels -= 1
	if player.pending_levels > 0:
		hud.show_levelup(_options(), player.level - player.pending_levels + 1, rerolls)
	else:
		_resume()


func _on_reroll() -> void:
	if state != "level" or rerolls <= 0:
		return
	rerolls -= 1
	hud.show_levelup(_options(), player.level - player.pending_levels + 1, rerolls)


func _resume() -> void:
	G.sfx.muffle(false)
	hud.close_menu()
	state = "play"
	get_tree().paused = false


## Chest tiers: [name, picks, colour]
const CHEST_TIERS := [
	["凡品宝箱", 1, Color(0.6, 0.85, 1.0)],
	["灵品宝箱", 3, Color(0.75, 0.5, 1.0)],
	["仙品宝箱", 5, Color(1.0, 0.75, 0.25)],
]


func open_chest() -> void:
	var got: Array = []
	var evos: Array = weapons.evolvable()
	var tier := 0
	var r := randf()
	if r < 0.08 * player.luck:
		tier = 2
	elif r < 0.35 * player.luck:
		tier = 1
	if evos.size() > 0:
		var id: String = evos[0]
		var d: Dictionary = Data.WEAPONS[id]
		var o := {"type": "evo", "id": id, "name": d.name, "tag": "武器进化！", "desc": d.desc[0], "w": 1.0}
		_apply(o)
		got.append(o)
		tier = maxi(tier, 1)
	var n: int = CHEST_TIERS[tier][1] - got.size()
	for i in maxi(n, 0):
		var pk := _pick(_pool(), 1)
		var o: Dictionary = pk[0] if pk.size() > 0 else _heal_opt()
		_apply(o)
		got.append(o)
	var bonus := float([20, 60, 150][tier]) * (1.0 + 0.1 * G.meta("greed")) * float(map.gold)
	gold += bonus
	# decoys for the slot reels: everything the player could plausibly roll
	var decoys: Array = []
	for o in _pool():
		decoys.append(o)
	for id in Data.BASE_WEAPONS:
		decoys.append({"type": "weapon", "id": id, "name": Data.WEAPONS[id].name})
	for id in Data.PASSIVES:
		decoys.append({"type": "passive", "id": id, "name": Data.PASSIVES[id].name})
	G.sfx.play("chest", -2.0)
	state = "chest"
	get_tree().paused = true
	G.sfx.muffle(true)
	hud.show_chest(got, decoys, tier, int(bonus))


func bomb() -> void:
	var pp: Vector3 = player.position
	G.sfx.play("boom", 2.0, 0.0, 0.8)
	hud.white_flash(0.9)
	shake(0.8)
	fx.ring(pp, Color(1.8, 1.2, 0.6, 1.0), 16.0, 0.6)
	for e in enemies.query(pp, 18.0):
		if e.prop:
			continue
		var dmg: float = e.hp + 1.0 if not (e.elite or e.boss) else 150.0 * player.might
		enemies.damage(e, dmg, e.root.position - pp, 20.0, false, Color(1.0, 0.7, 0.4))


func game_over(win: bool) -> void:
	if state == "end":
		return
	state = "end"
	if win:
		G.sfx.play("levelup", 0.0, 0.0, 0.8)
		hud.white_flash(1.0)
		for e in enemies.list:
			if not e.dead and not e.prop:
				enemies.damage(e, e.hp + 1.0)
		G.sfx.play_music("title", 2.0)
		hud.show_end(true, player, weapons, time, enemies.kills, bank_gold())
		return
	G.sfx.play("boom", 0.0, 0.0, 0.6)
	shake(0.7)
	var tw: Tween = player.create_tween()
	tw.tween_property(player.paper, "rotation:x", -PI * 0.5, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.6)
	tw.tween_callback(func() -> void:
		G.sfx.play_music("title", 2.0)
		hud.show_end(false, player, weapons, time, enemies.kills, bank_gold()))


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("pause"):
		toggle_pause()


func toggle_pause() -> void:
	if state == "play":
		state = "pause"
		get_tree().paused = true
		G.sfx.muffle(true)
		hud.show_pause(player, weapons)
	elif state == "pause":
		_resume()


## Browsers pause the tab when it is hidden; pause the run too so the player isn't killed meanwhile.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "play" and not G.test_mode:
		toggle_pause()


## Platform self-test (UGC.selfTest): title -> map select -> run, joystick movement, enemies,
## level-up card pick and pause, all on a throwaway save.
func auto_test() -> void:
	G.test_mode = true
	G.save = {"gold": 0, "meta": {}, "best": {}, "spent": 0}
	await _tw(0.4)
	UGC.check(state == "title" and hud.menu_kind == "title", "开局显示标题界面")
	UGC.check(touch_controls != null and touch_controls.get_parent() == self, "触控层已挂载")
	_on_start_pressed()
	await _tw(0.2)
	UGC.check(hud.menu_kind == "maps", "开始修行 → 选择地图")
	start_run()
	await _tw(0.5)
	UGC.check(state == "play" and weapons.lv.has("sword"), "进入战斗并持有御剑术")
	var p0: Vector3 = player.position
	UGC.hold("move_right", true)
	await _tw(0.8)
	UGC.hold("move_right", false)
	UGC.check(player.position.x > p0.x + 1.0, "向右移动 %.1f 米" % (player.position.x - p0.x))
	touch_controls._set_vec(Vector2(0, -1))
	var z0: float = player.position.z
	await _tw(0.6)
	touch_controls._release()
	UGC.check(player.position.z < z0 - 0.8, "虚拟摇杆驱动移动")
	await _tw(2.5)
	UGC.check(enemies.alive_foes > 0, "刷出妖怪 %d 只" % enemies.alive_foes)
	player.pending_levels += 1
	await _tw(0.3)
	UGC.check(state == "level" and hud.cards.size() > 0, "升级弹出功法卡 %d 张" % hud.cards.size())
	if hud.cards.size() > 0:
		hud.cards[0].emit_signal("pressed")
	await _tw(0.3)
	UGC.check(state == "play", "选卡后继续战斗")
	toggle_pause()
	UGC.check(state == "pause" and get_tree().paused, "暂停")
	toggle_pause()
	UGC.check(state == "play" and not get_tree().paused, "继续")
	UGC.check(enemies.kills > 0 or time > 3.0, "战斗进行中 · 击杀 %d" % enemies.kills)


func _tw(s: float) -> Signal:
	return get_tree().create_timer(s, true).timeout
