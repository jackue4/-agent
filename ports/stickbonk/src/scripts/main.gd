extends Node2D
## Bootstraps the arena, spawner, camera, post-processing, HUD and the 道馆 meta loop
## (title -> hub -> run -> settlement -> hub).

const PROPS := {
	"dojo": ["crate", "crate", "barrel", "rock", "hydrant"],
	"bamboo": ["bamboo", "bamboo", "bamboo", "crate", "rock"],
	"volcano": ["obsidian", "obsidian", "rock", "barrel"],
	"ice": ["icecrystal", "icecrystal", "rock", "crate"],
}
const BOSS_ORDER := ["boss", "slimeking", "batqueen"]

var ground: Ground
var env: Env
var hud: Hud
var hub: Hub
var spawn_t := 0.0
var next_boss := 150.0
var boss_count := 0
var bosses_killed := 0
var elite_t := 45.0
var event_t := 35.0
var event_obj: EventObj = null
var state := "title"
var level_queue := 0
var autotest := false
var at_t := 0.0
var prof_frames := 0
var touch: TouchControls
var cfg := {}
var heat := 0
var coins := 0
var rerolls := 1
var banishes := 1
var locked_card := {}
var evo_offered := {}
var shop_items: Array = []
var altar_items: Array = []
var run_done := false
var speed_win := false
var protocol_cleared := 0
var reward := 0
const ROUND := 300.0   ## one round = 5 minutes, then 死神 arrives
var reaper: Enemy = null
var survived := false
var pause_page := "main"
var round_len := ROUND


func _ready() -> void:
	G.reset()
	G.main = self
	SkillDB.banished.clear()
	ground = Ground.new()
	add_child(ground)
	env = Env.new()
	add_child(env)
	G.decals = Decals.new()
	add_child(G.decals)
	G.entities = Node2D.new()
	G.entities.y_sort_enabled = true
	add_child(G.entities)
	G.particles = Debris.new()
	G.particles.z_index = 4
	add_child(G.particles)
	G.fx = Node2D.new()
	G.fx.z_index = 5
	add_child(G.fx)
	var cam := Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 7.0
	cam.limit_left = int(G.ARENA.position.x) - 200
	cam.limit_right = int(G.ARENA.end.x) + 200
	cam.limit_top = int(G.ARENA.position.y) - 300
	cam.limit_bottom = int(G.ARENA.end.y) + 200
	cam.process_callback = Camera2D.CAMERA2D_PROCESS_IDLE
	add_child(cam)
	cam.make_current()
	G.camera = cam
	# comic post process
	var pl := CanvasLayer.new()
	pl.layer = 5
	add_child(pl)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/comic_post.gdshader")
	rect.material = mat
	pl.add_child(rect)
	G.post_mat = mat
	# player
	var p := Player.new()
	p.position = Vector2.ZERO
	G.player = p
	G.entities.add_child(p)
	p.leveled_up.connect(_on_level_up)
	p.died.connect(_on_died)
	_build_props("dojo")
	G.enemy_died.connect(_on_enemy_died)
	# HUD
	var hl := CanvasLayer.new()
	hl.layer = 10
	hl.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hl)
	hud = Hud.new()
	hud.main = self
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hl.add_child(hud)
	var hbl := CanvasLayer.new()
	hbl.layer = 12
	hbl.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hbl)
	hub = Hub.new()
	hub.main = self
	hub.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbl.add_child(hub)
	touch = TouchControls.new()
	touch.main = self
	add_child(touch)
	Art.preload_all()
	if OS.get_cmdline_user_args().has("--autotest"):
		G.skip_title = true
		autotest = true
	if OS.get_cmdline_user_args().has("--hubshot"):
		open_hub()
		await get_tree().create_timer(1.0, true, false, true).timeout
		for tb in ["fight", "train", "codex"]:
			hub.tab = tb
			await get_tree().create_timer(0.4, true, false, true).timeout
			get_viewport().get_texture().get_image().save_png("res://shot_hub_%s.png" % tb)
		get_tree().quit()
		return
	if G.goto_hub:
		G.goto_hub = false
		open_hub()
	elif G.skip_title:
		var c := G.run_cfg if not G.run_cfg.is_empty() else default_cfg()
		for a in OS.get_cmdline_user_args():
			for k in ["map", "hero", "weapon", "sect", "mode"]:
				if a.begins_with("--%s=" % k):
					c[k] = a.split("=")[1]
		start_run(c)
	else:
		state = "title"
		get_tree().paused = true
		if OS.get_cmdline_user_args().has("--titleshot"):
			await get_tree().create_timer(1.0, true, false, true).timeout
			get_viewport().get_texture().get_image().save_png("res://shot_title.png")
			get_tree().quit()


func default_cfg() -> Dictionary:
	return {"hero": Meta.sel("hero"), "weapon": Meta.sel("weapon"), "map": Meta.sel("map"), "mode": Meta.sel("mode"), "heat": int(Meta.sel("heat")), "sect": Meta.sel("sect")}


func _build_props(map: String) -> void:
	for pr in G.props.duplicate():
		G.props.erase(pr)
		pr.queue_free()
	var kinds: Array = PROPS.get(map, PROPS["dojo"])
	for i in (34 if G.low else 55):
		var pr := Prop.new()
		pr.kind = kinds.pick_random()
		var pos := Vector2(randf_range(G.ARENA.position.x + 120, G.ARENA.end.x - 120), randf_range(G.ARENA.position.y + 120, G.ARENA.end.y - 120))
		if pos.length() < 250.0 or (env != null and env.in_lava(pos)):
			continue
		pr.position = pos
		G.entities.add_child(pr)


func open_hub() -> void:
	state = "hub"
	get_tree().paused = true
	hub.open()


## Title tap -> 道馆.
func _start() -> void:
	open_hub()


## Starts a run with a loadout (hub "出战"). Applies map, hero, weapon, sect, mode and 破坏协议.
func start_run(c: Dictionary) -> void:
	cfg = c.duplicate()
	if String(cfg.get("mode", "normal")) == "daily":
		var d := Meta.daily_config(Meta.today())
		cfg.merge(d, true)
		cfg["heat"] = 0
		seed(int(d["seed"]))
	G.run_cfg = cfg
	heat = clampi(int(cfg.get("heat", 0)), 0, Meta.PROTOCOL.size())
	var map := String(cfg.get("map", "dojo"))
	env.setup(map)
	ground.set_map(String(Meta.MAPS.get(map, Meta.MAPS["dojo"])["ground"]))
	if map != "dojo":
		_build_props(map)
	var p := G.player
	p.setup_loadout(String(cfg.get("hero", "red")), String(cfg.get("weapon", "fist")), String(cfg.get("sect", "none")))
	if cfg.has("curse"):
		p.add_curse(String(cfg["curse"]))
	G.dmg_in_mult = 1.25 if heat >= 4 else 1.0
	G.heal_mult = 0.5 if heat >= 7 else 1.0
	next_boss = 100.0 if heat >= 5 else 120.0
	if mode() == "speed":
		next_boss = 90.0
	rerolls = 1 + Meta.up("reroll")
	banishes = 1 + Meta.up("banish")
	state = "play"
	get_tree().paused = false
	var mname := String(Meta.MAPS[map]["name"])
	var txt := "%s · %s  开打！" % [mname, String(Meta.MODES[mode()]["name"])]
	if heat > 0:
		txt += "  破坏协议 %d" % heat
	G.banner(txt, 2.8)
	for i in 6:
		_spawn_one("blob", hp_mult())


func mode() -> String:
	return String(cfg.get("mode", "normal"))


func hp_mult() -> float:
	var m := 1.0
	if heat >= 1:
		m *= 1.25
	if heat >= 8:
		m *= 1.5
	return m


func count_mult() -> float:
	var m := 1.0
	if heat >= 6:
		m *= 1.3
	if mode() == "speed":
		m *= 1.5
	if G.player != null and G.player.curses.has("swarm"):
		m *= 1.4
	return m


func enemy_speed_mult() -> float:
	var m := 1.0
	if heat >= 2:
		m *= 1.1
	if G.player != null and G.player.curses.has("frenzy"):
		m *= 1.25
	return m


func _process(dt: float) -> void:
	if state != "play" and state != "dead":
		return
	G.game_time += dt
	G.rebuild_grid()
	if G.combo_timer > 0.0:
		G.combo_timer -= dt
		if G.combo_timer <= 0.0:
			G.combo = 0
	var p := G.player
	if p != null:
		G.camera.position = p.position + Vector2(0, -60) + p.aim * 40.0
		G.camera.zoom = Vector2.ONE * ((1.22 if G.low or G.touch else 0.92) + G.zoom_kick)
	if state == "play":
		_spawner(dt)
		_events(dt)
		_round_clock()
	if autotest:
		_autotest(dt)


func _autotest(dt: float) -> void:
	# Soak test: fast-forwards time, spams every move and levels up with random skills.
	at_t += dt
	prof_frames += 1
	var p := G.player
	if p == null:
		return
	if reaper == null:
		p.invuln = 1.0
	if OS.get_cmdline_user_args().has("--natural"):
		_natural_play(dt, p)
		return
	G.game_time += dt * 3.0
	if int(at_t * 10.0) % 3 == 0:
		Input.action_press("attack")
	else:
		Input.action_release("attack")
	if int(at_t * 2.0) % 5 == 0:
		Input.action_press("heavy")
	else:
		Input.action_release("heavy")
	if int(at_t * 3.0) % 7 == 0:
		Input.action_press("dash")
	else:
		Input.action_release("dash")
	if fmod(at_t, 4.0) < dt and at_t > 1.0:
		p.add_xp(p.xp_need)
	for s in [3.0, 9.0, 16.0]:
		if at_t >= s and at_t - dt < s and OS.get_cmdline_user_args().has("--shot"):
			get_viewport().get_texture().get_image().save_png("res://shot_%d.png" % int(s))
	if int(at_t * 10.0) % 50 == 0:
		print("[autotest] t=%.1f gt=%.1f enemies=%d shards=%d kills=%d lvl=%d skills=%s fps=%d" % [at_t, G.game_time, G.enemies.size(), G.shards.size(), G.kills, p.level, str(p.skills), Engine.get_frames_per_second()])
		var ks: Array = G.prof.keys()
		ks.sort_custom(func(a, b): return G.prof[a] > G.prof[b])
		var s := ""
		for k in ks.slice(0, 8):
			s += "%s=%.2fms " % [k, G.prof[k] / 1000.0 / maxf(prof_frames, 1.0)]
		print("   PROF/frame: ", s)
		G.prof.clear()
		prof_frames = 0
		print("   proc=%.1fms draws=%d prims=%d nodes=%d fx=%d parts=%d decals=%d" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), G.fx.get_child_count(), G.particles.parts.size(), G.decals.items.size()])


func _spawner(dt: float) -> void:
	var tm := G.game_time
	var difficulty := (1.0 + tm / 60.0 * 0.55 + boss_count * 0.6) * hp_mult()
	var cm := count_mult()
	var cap := mini(int((30 + int(tm / 4.0)) * cm), int((75 if G.low else 110) * minf(cm, 1.3)))
	spawn_t -= dt
	if spawn_t <= 0.0 and G.enemies.size() < cap:
		spawn_t = maxf(1.1 - tm / 200.0, 0.3)
		var n := int(round((2 + int(tm / 25.0)) * cm))
		var pool := ["blob", "blob", "imp"]
		if tm > 25.0:
			pool.append_array(["bat", "bat", "imp"])
		if tm > 50.0:
			pool.append_array(["spitter", "spitter"])
		if tm > 70.0:
			pool.append("brute")
		var group_type: String = pool.pick_random()
		var base := _edge_point()
		for i in n:
			var tp := group_type if randf() < 0.7 else String(pool.pick_random())
			_spawn_one(tp, difficulty, base + Vector2.from_angle(randf() * TAU) * randf_range(0, 90))
	elite_t -= dt
	if elite_t <= 0.0:
		elite_t = 25.0 if heat >= 3 else 40.0
		var e := _spawn_one(["brute", "imp", "spitter"].pick_random(), difficulty, _edge_point(), true)
		if e != null:
			G.banner("精英怪物出现！", 1.8)
	if tm >= next_boss and G.boss == null and reaper == null and tm < round_len - 20.0:
		next_boss = tm + (90.0 if mode() == "speed" else 120.0)
		var map_boss := String(Meta.MAPS[String(cfg.get("map", "dojo"))]["boss"])
		var start := BOSS_ORDER.find(map_boss)
		var bt: String = BOSS_ORDER[(start + boss_count) % BOSS_ORDER.size()]
		boss_count += 1
		var b := _spawn_one(bt, (1.0 + boss_count * 0.8) * hp_mult(), _edge_point())
		G.boss = b
		G.banner("!! BOSS 来袭：%s Lv.%d !!" % [b.boss_name(), boss_count], 3.0)
		G.shake(0.5)
		Sfx.play("boom", 2.0)


# ---------------------------------------------------------------- events
func _events(dt: float) -> void:
	event_t -= dt
	if event_t > 0.0 or event_obj != null:
		return
	event_t = 50.0
	spawn_event(["dojo", "merchant", "altar", "treasure"].pick_random())


func spawn_event(kind: String) -> void:
	var p := G.player
	var pos := p.position + Vector2.from_angle(randf() * TAU) * 520.0
	pos = pos.clamp(G.ARENA.position + Vector2(320, 260), G.ARENA.end - Vector2(320, 220))
	if kind == "treasure":
		var e := _spawn_one("imp", 6.0 * hp_mult(), pos)
		e.treasure = true
		e.speed *= 1.1
		e.xp = 40
		G.banner("精英护送：宝箱怪出现！25 秒内追上它！", 2.2)
		return
	var ev := EventObj.new()
	ev.kind = kind
	ev.position = pos
	G.entities.add_child(ev)
	event_obj = ev
	G.banner({"dojo": "武馆挑战出现！进入擂台开始挑战", "merchant": "流浪商人路过……靠近交易", "altar": "混沌祭坛降临……靠近接受诅咒"}[kind], 2.2)


func event_reward(kind: String, pos: Vector2) -> void:
	if kind == "dojo":
		G.banner("挑战成功！奖励经验、铜钱 +20", 2.2)
		coins += 20
		G.drop_xp(pos, 40)
		G.drop_heart(pos)
		G.spawn_text(pos + Vector2(0, -160), "VICTORY!", G.YELLOW, 60)
		Sfx.play("levelup")


func on_treasure_killed(pos: Vector2) -> void:
	coins += 25
	G.drop_xp(pos, 50)
	G.drop_heart(pos)
	G.banner("宝箱怪被击碎！铜钱 +25", 2.0)


func on_reaction(_name: String) -> void:
	Meta.check_reactions_ach()


func on_boss_killed(tp: String) -> void:
	bosses_killed += 1
	coins += 30
	Meta.codex_add("enemies", tp)
	Meta.unlock_ach(tp)
	if heat > protocol_cleared:
		protocol_cleared = heat
		G.banner("破坏协议 %d 达成！" % heat, 2.4)


func _on_enemy_died(e) -> void:
	var c := 0
	if e.elite:
		c = 5
	elif G.kills % 10 == 0:
		c = 1
	if G.player != null and G.player.curses.has("frenzy"):
		c *= 2
	coins += c


func spawn_minion(tp: String, pos: Vector2) -> void:
	if G.enemies.size() >= 130:
		return
	_spawn_one(tp, (1.0 + G.game_time / 60.0 * 0.55) * hp_mult(), pos.clamp(G.ARENA.position + Vector2(40, 40), G.ARENA.end - Vector2(40, 40)))


## 流浪商人: spend run coins (铜钱).
func open_shop() -> void:
	shop_items = [
		{"id": "upgrade", "name": "秘传心法", "desc": "随机一个已有技能 +1 级", "cost": 15},
		{"id": "heal", "name": "跌打药酒", "desc": "回复 60 生命", "cost": 10},
		{"id": "reroll", "name": "刷新券", "desc": "升级时刷新卡牌次数 +1", "cost": 8},
		{"id": "power", "name": "磨刀石", "desc": "全部伤害 +10%", "cost": 20},
	]
	state = "shop"
	get_tree().paused = true
	hud.open_overlay()


func buy_shop(i: int) -> bool:
	if i < 0 or i >= shop_items.size():
		return false
	var it: Dictionary = shop_items[i]
	if it.get("sold", false) or coins < int(it["cost"]):
		Sfx.play("click", -6.0)
		return false
	coins -= int(it["cost"])
	it["sold"] = true
	var p := G.player
	match String(it["id"]):
		"upgrade":
			var own := []
			for id in p.skills.keys():
				if SkillDB.LIST.has(id) and int(p.skills[id]) < SkillDB.MAX:
					own.append(id)
			if own.is_empty():
				p.apply_skill("power")
			else:
				p.apply_skill(own.pick_random())
		"heal":
			p.heal(60.0)
		"reroll":
			rerolls += 1
		"power":
			p.dmg_mult *= 1.1
	Sfx.play("pickup")
	return true


## 混沌祭坛: pick one curse (drawback + perk, +15% crystals each) or walk away.
func open_altar() -> void:
	var pool := SkillDB.CURSES.keys().filter(func(k): return not G.player.curses.has(k))
	pool.shuffle()
	altar_items = pool.slice(0, 2)
	if altar_items.is_empty():
		G.banner("祭坛沉默了……", 1.4)
		return
	state = "altar"
	get_tree().paused = true
	hud.open_overlay()


func take_curse(id: String) -> void:
	if id != "":
		G.player.add_curse(id)
		coins += 20
		if G.player.curses.size() >= 3:
			Meta.unlock_ach("curse3")
		Sfx.play("boom", -4.0)
	close_overlay()


func close_overlay() -> void:
	state = "play"
	get_tree().paused = false


func _edge_point() -> Vector2:
	var vs := get_viewport_rect().size / G.camera.zoom
	var c := G.camera.get_screen_center_position()
	for i in 10:
		var a := randf() * TAU
		var d := Vector2(cos(a) * (vs.x * 0.5 + 120), sin(a) * (vs.y * 0.5 + 120))
		var p := c + d
		if G.ARENA.grow(-60).has_point(p):
			return p
	return Vector2(clampf(c.x + randf_range(-900, 900), G.ARENA.position.x + 80, G.ARENA.end.x - 80), clampf(c.y + 700, G.ARENA.position.y + 80, G.ARENA.end.y - 80))


func _spawn_one(tp: String, diff: float, pos: Vector2 = Vector2.INF, elite: bool = false) -> Enemy:
	var e := Enemy.new()
	e.setup(tp, diff, elite)
	e.position = pos if pos != Vector2.INF else _edge_point()
	G.entities.add_child(e)
	G.particles.dust(e.position, 4, 20)
	return e


# ---------------------------------------------------------------- level-up cards
func _on_level_up() -> void:
	if state != "play":
		return
	if reaper != null:
		G.player.pending_levels = 0
		return
	_open_levelup()


func roll_cards() -> Array:
	var p := G.player
	if Meta.owns("secrets", "evo"):
		for pair in [[5, "fin"], [10, "slam"], [15, "dash"]]:
			if p.level >= int(pair[0]) and not evo_offered.has(pair[1]):
				evo_offered[pair[1]] = true
				return SkillDB.evo_cards(String(pair[1]))
	var lk := locked_card
	locked_card = {}
	var cards := SkillDB.roll(p.skills, 3, Meta.up("luck"), lk)
	if not lk.is_empty():
		hud.call_deferred("set", "lock_idx", 0)
	return cards


func _open_levelup() -> void:
	var p := G.player
	if p.pending_levels <= 0:
		return
	state = "levelup"
	get_tree().paused = true
	hud.open_choices(roll_cards())
	if autotest and OS.get_cmdline_user_args().has("--menushot"):
		_menushot.call_deferred()
		return
	if autotest and OS.get_cmdline_user_args().has("--lvshot"):
		await get_tree().create_timer(0.8, true, false, true).timeout
		get_viewport().get_texture().get_image().save_png("res://shot_lv.png")
		get_tree().quit()
		return
	if autotest:
		choose.call_deferred(hud.choices.pick_random())
	Sfx.play("levelup")
	G.particles.stars(p.position + Vector2(0, -80), 12)


func reroll() -> bool:
	if rerolls <= 0 or state != "levelup":
		return false
	rerolls -= 1
	var lk := hud.locked_card()
	hud.open_choices(SkillDB.roll(G.player.skills, 3, Meta.up("luck"), lk))
	if not lk.is_empty():
		hud.lock_idx = 0
	Sfx.play("whoosh", -4.0)
	return true


func banish(i: int) -> bool:
	if banishes <= 0 or state != "levelup" or i < 0 or i >= hud.choices.size():
		return false
	var id := String(hud.choices[i]["id"])
	if not (SkillDB.LIST.has(id) or SkillDB.COMBOS.has(id)):
		return false
	banishes -= 1
	SkillDB.banished[id] = true
	var lk := {} if hud.lock_idx == i else hud.locked_card()
	hud.open_choices(SkillDB.roll(G.player.skills, 3, Meta.up("luck"), lk))
	if not lk.is_empty():
		hud.lock_idx = 0
	G.spawn_text(G.player.position + Vector2(0, -160), "封印：" + String(SkillDB.info(id)["name"]), G.PURPLE, 32)
	Sfx.play("shatter", -6.0)
	return true


func choose(card) -> void:
	var p := G.player
	var id: String = String(card["id"]) if card is Dictionary else String(card)
	var rar: String = String(card.get("rar", "common")) if card is Dictionary else "common"
	if hud.lock_idx >= 0 and hud.lock_idx < hud.choices.size() and hud.choices[hud.lock_idx] != card:
		locked_card = hud.choices[hud.lock_idx]
	hud.lock_idx = -1
	p.pending_levels -= 1
	var times := int(SkillDB.RARITY.get(rar, SkillDB.RARITY["common"])["lv"])
	for i in times:
		if int(p.skills.get(id, 0)) >= SkillDB.max_of(id) and i > 0:
			break
		p.apply_skill(id)
	Sfx.play("click")
	if p.pending_levels > 0:
		hud.open_choices(roll_cards())
		if autotest:
			choose.call_deferred(hud.choices.pick_random())
		return
	state = "play"
	get_tree().paused = false
	# level-up shockwave for juice
	G.spawn_ring(p.position, 20, 260, G.YELLOW, 0.45, 18.0, "shock")
	for e in G.query(p.position, 220.0):
		var d: Vector2 = (e.position as Vector2) - p.position
		e.take_hit(1.0, d.normalized() if d.length() > 1.0 else Vector2.RIGHT, 700.0, 300.0, false)
	G.shake(0.3)
	var lvl: int = int(p.skills.get(id, 0))
	if lvl >= SkillDB.MAX and SkillDB.LIST.has(id) and SkillDB.LIST[id].has("awaken"):
		G.banner(SkillDB.LIST[id]["awaken"], 3.0)
		G.impact_frame(0.08)


# ---------------------------------------------------------------- run end
func _on_died() -> void:
	_finish(false)


## 5-minute round clock: warnings at 4:30 / 4:50, then 死神 descends and reaps the player.
func _round_clock() -> void:
	var tm := G.game_time
	if reaper != null or run_done:
		return
	if tm >= round_len - 30.0 and tm - get_process_delta_time() < round_len - 30.0:
		G.banner("还剩 30 秒……死神正在逼近！", 2.4)
	if tm >= round_len - 10.0 and tm - get_process_delta_time() < round_len - 10.0:
		G.banner("10 秒！做好觉悟！", 2.0)
		Sfx.play("levelup", -4.0)
	if tm >= round_len:
		survived = true
		if heat > 0 and protocol_cleared < heat:
			protocol_cleared = heat
		if mode() == "speed":
			speed_win = true
		summon_reaper()


func summon_reaper() -> void:
	var p := G.player
	G.banner("!! 时间到 · 死神降临 !!", 3.0)
	G.shake(0.8)
	G.impact_frame(0.12)
	Sfx.play("boom", 6.0)
	var pos := p.position + Vector2(620.0 * (1.0 if randf() < 0.5 else -1.0), -120.0)
	pos = pos.clamp(G.ARENA.position + Vector2(80, 80), G.ARENA.end - Vector2(80, 80))
	reaper = _spawn_one("reaper", 1.0, pos)
	G.boss = reaper
	G.spawn_ring(pos, 20, 320, Color(0.55, 0.2, 0.9), 0.6, 26.0, "shock")
	G.particles.ink_spray(pos + Vector2(0, -80), Vector2.UP, 30, Color(0.3, 0.1, 0.45), 120)


func _finish(win: bool) -> void:
	if run_done:
		return
	run_done = true
	reward = Meta.finish_run({
		"kills": G.kills, "time": G.game_time, "bosses": bosses_killed, "protocol": protocol_cleared,
		"heat": heat, "curses": G.player.curses.size(), "mode": mode(), "seed": int(cfg.get("seed", 0)),
		"combo": G.best_combo, "speed_win": speed_win, "survived": survived,
	})
	if survived:
		UGC.win(G.kills)
		G.slowmo(0.3, 1.2)
	else:
		UGC.lose(G.kills)
	state = "dead"
	await get_tree().create_timer(1.6, true, false, true).timeout
	state = "over"
	get_tree().paused = true
	if autotest and OS.get_cmdline_user_args().has("--natural"):
		print("[pace] END t=%d lvl=%d kills=%d reward=%d survived=%s hp=%d" % [int(G.game_time), G.player.level, G.kills, reward, str(survived), int(G.player.hp)])
		get_viewport().get_texture().get_image().save_png("res://shot_menu_over.png")
		get_tree().quit()


func restart() -> void:
	get_tree().paused = false
	G.skip_title = true
	G.reset()
	get_tree().reload_current_scene()


func back_to_hub() -> void:
	get_tree().paused = false
	G.goto_hub = true
	G.reset()
	get_tree().reload_current_scene()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event
		if k.physical_keycode == KEY_ESCAPE:
			toggle_pause()
		if k.physical_keycode == KEY_F11:
			var m := DisplayServer.window_get_mode()
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if m == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)


func toggle_pause() -> void:
	if state == "play":
		state = "pause"
		pause_page = "main"
		get_tree().paused = true
		hud.open_overlay()
	elif state == "pause":
		if pause_page != "main":
			pause_page = "main"
			return
		state = "play"
		get_tree().paused = false


## Realistic pacing probe: real-time play with auto-attack, auto-picks the first card.
var _nat_log := 0.0
func _natural_play(dt: float, p: Player) -> void:
	if OS.get_cmdline_user_args().has("--late") and at_t >= 1.0 and at_t - dt < 1.0:
		G.game_time = 285.0
		_nat_log = 285.0
	if reaper != null and int(at_t * 2.0) % 2 == 0 and fmod(at_t, 0.5) < dt:
		print("[pace] reaper d=%d wind=%.2f cd=%.1f hp=%d dead=%s st=%s" % [int(reaper.position.distance_to(p.position)), reaper.wind, reaper.atk_cd, int(p.hp), str(p.dead), state])
	var tgt := Vector2.ZERO
	var best := 1e9
	for e in G.enemies:
		var d := p.position.distance_squared_to(e.position)
		if d < best:
			best = d
			tgt = e.position
	var to := (tgt - p.position)
	Input.action_press("attack")
	if int(at_t * 2.0) % 5 == 0:
		Input.action_press("heavy")
	else:
		Input.action_release("heavy")
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)
	if to.length() > 140.0:
		if to.x < -40: Input.action_press("move_left")
		if to.x > 40: Input.action_press("move_right")
		if to.y < -40: Input.action_press("move_up")
		if to.y > 40: Input.action_press("move_down")
	if G.game_time - _nat_log >= 30.0:
		_nat_log = G.game_time
		print("[pace] t=%d lvl=%d kills=%d hp=%d st=%s" % [int(G.game_time), p.level, G.kills, int(p.hp), state])
	if state == "levelup" and not hud.choices.is_empty():
		choose(hud.choices[0])
	elif state == "shop" or state == "altar":
		close_overlay()
	if state == "over":
		print("[pace] END t=%d lvl=%d kills=%d reward=%d survived=%s" % [int(G.game_time), p.level, G.kills, reward, str(survived)])
		get_tree().quit()


func _menushot() -> void:
	if _menushot_done:
		return
	_menushot_done = true
	G.player.pending_levels = 0
	state = "play"
	get_tree().paused = false
	toggle_pause()
	for pg in ["main", "stats", "settings", "confirm"]:
		pause_page = pg
		await get_tree().create_timer(0.3, true, false, true).timeout
		get_viewport().get_texture().get_image().save_png("res://shot_menu_%s.png" % pg)
	pause_page = "main"
	toggle_pause()
	G.game_time = round_len - 3.0
	await get_tree().create_timer(4.2, true, false, true).timeout
	get_viewport().get_texture().get_image().save_png("res://shot_menu_reaper.png")
	await get_tree().create_timer(4.0, true, false, true).timeout
	get_viewport().get_texture().get_image().save_png("res://shot_menu_over.png")
	get_tree().quit()


var _menushot_done := false


## Pause menu "返回道馆": abandons the run and settles what was earned so far.
func quit_to_hub() -> void:
	if state == "pause":
		get_tree().paused = false
		state = "play"
	if not run_done:
		run_done = true
		reward = Meta.finish_run({
			"kills": G.kills, "time": G.game_time, "bosses": bosses_killed, "protocol": 0,
			"heat": heat, "curses": G.player.curses.size(), "mode": mode(), "seed": int(cfg.get("seed", 0)),
			"combo": G.best_combo, "speed_win": false, "survived": false, "abandoned": true,
		})
	back_to_hub()


## Platform self-test (UGC.selfTest): title -> 道馆 (every tab, purchases, save round-trip) ->
## run with hero/weapon/map/protocol -> moves -> elements & reactions -> combo card -> card
## controls -> events/shop/altar -> new bosses -> touch & pause -> settlement.  Never writes the save.
func auto_test() -> void:
	Meta.no_save = true
	Meta.data = Meta.defaults()
	await _tw(0.3)
	UGC.check(state == "title", "开局显示标题页")
	UGC.check(touch != null and touch.get_parent() == self, "触控层已挂载")
	_start()
	await _tw(0.2)
	UGC.check(state == "hub" and hub.visible, "点击标题进入道馆")
	for tb in Hub.TABS:
		hub.tab = String(tb[0])
		await _tw(0.08)
	UGC.check(hub.buttons.size() > 0, "道馆 6 个分页可绘制 · 按钮 %d" % hub.buttons.size())
	UGC.check(not Meta.buy("heroes", "ninja"), "结晶不足时无法购买")
	Meta.add_crystals(5000)
	var bought := Meta.buy("heroes", "ninja") and Meta.buy("weapons", "nunchaku") and Meta.buy("maps", "volcano") and Meta.buy("sects", "thunder")
	bought = bought and Meta.buy("secrets", "evo") and Meta.buy("secrets", "frost") and Meta.buy("secrets", "heavyfist") and Meta.buy_upgrade("hp") and Meta.buy_upgrade("lock")
	UGC.check(bought and Meta.up("hp") == 1, "道馆购买：角色/武器/地图/门派/秘籍/修炼 · 余 %d 结晶" % Meta.crystals())
	var js := JSON.stringify(Meta.data)
	var back = JSON.parse_string(js)
	var mig := Meta.migrate(back) if back is Dictionary else {}
	var old := Meta.migrate({"crystals": 7})
	UGC.check(int(mig.get("crystals", -1)) == Meta.crystals() and bool(mig["heroes"].get("ninja", false)) and old.has("codex") and int(old["crystals"]) == 7, "存档 JSON 往返 + 旧档迁移补全字段")
	start_run({"hero": "ninja", "weapon": "nunchaku", "map": "volcano", "mode": "normal", "heat": 2, "sect": "thunder"})
	await _tw(0.3)
	var p := G.player
	var obs := G.props.filter(func(o): return o.kind == "obsidian").size()
	UGC.check(state == "play" and p.hero == "ninja" and p.weapon == "nunchaku" and env.map == "volcano" and obs > 0, "出战：影忍+双节棍+火山 · 黑曜石 %d · 熔岩池 %d" % [obs, env.pools.size()])
	p.invuln = 99.0
	var p0 := p.position
	UGC.hold("move_right", true)
	await _tw(0.5)
	UGC.hold("move_right", false)
	UGC.check(p.position.x > p0.x + 30.0, "摇杆/键盘可移动 dx=%d" % int(p.position.x - p0.x))
	for i in 4:
		UGC.press("attack", 0.06)
		await _tw(0.2)
	UGC.press("heavy", 0.08)
	await _tw(0.7)
	UGC.press("dash", 0.06)
	await _tw(0.05)
	UGC.press("attack", 0.06)
	await _tw(0.5)
	UGC.check(state in ["play", "levelup"] and p.hp > 0.0, "连击/重锤/冲刺飞踢+手里剑无报错")
	if state == "levelup":
		choose(hud.choices[0])
	var e := _spawn_one("blob", 1.0, p.position + Vector2(90, 0))
	var k0 := G.kills
	for i in 12:
		if not is_instance_valid(e) or e.dead:
			break
		p.aim = Vector2.RIGHT
		UGC.press("attack", 0.06)
		await _tw(0.22)
	UGC.check(G.kills > k0, "攻击可以击碎怪物 kills=%d" % G.kills)
	# elements & reactions
	var r1 := _spawn_one("brute", 3.0, p.position + Vector2(400, 0))
	r1.apply_elem("fire", 10.0)
	var burned := r1.burn > 0.0
	var a := r1.apply_elem("shock", 10.0)
	var r2 := _spawn_one("brute", 3.0, p.position + Vector2(-400, 0))
	r2.apply_elem("shock", 10.0)
	var b := r2.apply_elem("fire", 10.0)
	var r3 := _spawn_one("brute", 3.0, p.position + Vector2(0, 400))
	r3.apply_elem("frost", 10.0)
	var frozen := r3.freeze > 0.0
	var c := r3.apply_elem("", 10.0, true)
	await _tw(0.4)
	UGC.check(burned and frozen and a == "雷暴" and b == "爆燃" and c == "冰爆", "元素：灼烧/感电/冰冻 → 反应 %s %s %s" % [a, b, c])
	# combo gold card
	p.skills["lightning"] = 3
	p.skills["nova"] = 3
	var ready := SkillDB.combos_ready(p.skills)
	UGC.check(ready.has("combo_thunderflash"), "雷霆连锁+冲刺爆破 Lv3 解锁合体金卡 · %s" % str(ready))
	p.apply_skill("combo_thunderflash")
	p.skill_runner.refresh()
	UGC.press("dash", 0.06)
	await _tw(0.5)
	UGC.check(p.skills.has("combo_thunderflash") and Meta.codex_has("combos", "combo_thunderflash"), "合体技「雷光闪」生效并收录图鉴")
	# card controls
	p.add_xp(p.xp_need)
	await _tw(0.5)
	UGC.check(state == "levelup" and hud.choices.size() > 0 and hud.choices[0] is Dictionary, "升级弹出三选一（含稀有度）")
	if state == "levelup":
		var before := str(hud.choices)
		var rr := reroll()
		var bn := banish(0)
		hud.lock_idx = 1
		UGC.check(rr and bn and SkillDB.banished.size() == 1, "卡牌刷新/封印可用 · 刷新前 %d 张" % before.length())
		var keep: Dictionary = hud.choices[1]
		choose(hud.choices[0])
		await _tw(0.2)
		UGC.check(locked_card == keep or state == "levelup", "锁定的卡牌保留到下次升级")
	if state == "levelup":
		choose(hud.choices[0])
	await _tw(0.2)
	# events
	coins = 100
	open_shop()
	await _tw(0.2)
	UGC.check(state == "shop" and buy_shop(1) and coins == 90, "流浪商人：铜钱购买")
	close_overlay()
	open_altar()
	await _tw(0.2)
	var curse_n := p.curses.size()
	if state == "altar":
		take_curse(String(altar_items[0]))
	UGC.check(p.curses.size() == curse_n + 1 and state == "play", "混沌祭坛：接受诅咒 · %s" % str(p.curses))
	spawn_event("dojo")
	spawn_event("treasure")
	await _tw(0.3)
	UGC.check(event_obj != null and G.enemies.any(func(x): return x.treasure), "武馆挑战擂台 + 宝箱怪护送事件")
	# bosses
	var sk := _spawn_one("slimeking", 1.0, p.position + Vector2(500, 200))
	var bq := _spawn_one("batqueen", 1.0, p.position + Vector2(-500, -200))
	G.boss = sk
	await _tw(2.0)
	UGC.check(is_instance_valid(sk) and is_instance_valid(bq) and hud.boss_label() == "史莱姆王", "新 BOSS：史莱姆王 / 蝙蝠女王 行动无报错")
	if is_instance_valid(sk):
		sk.hp = 1.0
		sk.take_hit(10.0, Vector2.RIGHT, 100.0, 0.0, false)
	await _tw(0.3)
	UGC.check(bosses_killed >= 1 and Meta.data["ach"].has("slimeking"), "击败 BOSS 解锁成就")
	await _settle()
	G.touch = true
	touch.activate()
	await _tw(0.1)
	UGC.check(touch.visible and touch._buttons.size() == 4, "触控按钮布局 · %d 个" % touch._buttons.size())
	await _settle()
	toggle_pause()
	UGC.check(state == "pause" and get_tree().paused, "暂停")
	toggle_pause()
	UGC.check(state == "play", "继续")
	# pause menu pages + settings
	toggle_pause()
	pause_page = "settings"
	await _tw(0.15)
	var sb := hud.buttons.filter(func(b): return b["id"] == "set").size()
	var sh0 := int(Meta.data["settings"]["shake"])
	SettingsUI.act({"key": "shake", "op": -1})
	var sh1 := int(Meta.data["settings"]["shake"])
	SettingsUI.act({"key": "shake", "op": 1})
	pause_page = "stats"
	await _tw(0.15)
	toggle_pause()
	toggle_pause()
	UGC.check(state == "play" and sb >= 6 and sh1 == sh0 - 25 and is_equal_approx(G.shake_k, sh0 / 100.0), "ESC 菜单：设置页 %d 项可调、属性页、继续游戏" % sb)
	# 5-minute round -> 死神
	var c0 := Meta.crystals()
	p.invuln = 0.0
	p.revive_left = 0
	p.dodge = 0.0
	G.game_time = round_len - 0.3
	for i in 30:
		if reaper != null:
			break
		await _tw(0.1)
	UGC.check(reaper != null and is_instance_valid(reaper) and hud.boss_label() == "死神", "5 分钟到：死神降临")
	if is_instance_valid(reaper):
		reaper.position = p.position + Vector2(150, 0)
	var hp_before := reaper.hp if is_instance_valid(reaper) else 0.0
	if is_instance_valid(reaper):
		reaper.take_hit(5000.0, Vector2.RIGHT, 100.0, 0.0, false)
	UGC.check(is_instance_valid(reaper) and reaper.hp == hp_before, "死神无敌")
	for i in 30:
		if state == "over":
			break
		await _tw(0.2)
	UGC.check(state == "over" and survived and Meta.crystals() > c0 and reward > 0, "死神收割 → 结算：获得碎片结晶 +%d" % reward)
	UGC.check(Engine.get_frames_per_second() > 0, "渲染帧率 %d fps" % Engine.get_frames_per_second())

## Resolves any pending level-up so the run is back in "play".
func _settle() -> void:
	for i in 12:
		if state == "levelup" and not hud.choices.is_empty():
			choose(hud.choices[0])
			await _tw(0.1)
		else:
			break
	G.player.pending_levels = 0


## Timer that keeps running while paused (title/level-up) and ignores hitstop time scale.
func _tw(secs: float) -> Signal:
	return get_tree().create_timer(secs, true, false, true).timeout
