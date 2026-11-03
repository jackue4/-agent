extends Node3D

const Data = preload("res://scripts/data.gd")
const World = preload("res://scripts/world.gd")
const Interface = preload("res://scripts/ui.gd")
const Sound = preload("res://scripts/audio.gd")
const Spear = preload("res://scripts/spear_combat.gd")
const Boons = preload("res://scripts/boons.gd")
const BoonRuntime = preload("res://scripts/boon_runtime.gd")
const CombatVFX = preload("res://scripts/combat_vfx.gd")
const CombatArts = preload("res://scripts/combat_arts.gd")
const DamageNumbers = preload("res://scripts/damage_numbers.gd")
const ArtDirection = preload("res://scripts/art_direction.gd")
const Heroes = preload("res://scripts/heroes.gd")
const HeroCombat = preload("res://scripts/hero_combat.gd")
const DungeonRun = preload("res://scripts/dungeon_run.gd")
const DungeonBoss = preload("res://scripts/dungeon_boss.gd")
const RoomReward = preload("res://scripts/room_reward.gd")
const FlyingBlades = preload("res://scripts/flying_blades.gd")
const Quality = preload("res://scripts/quality.gd")
const TouchControls = preload("res://scripts/touch_controls.gd")
var touch_controls
const CYAN := Color("62e5eb")
const ORANGE := Color("ff9e50")
const RED := Color("ff5c52")

var data
var world
var ui
var sound
var actors: Node3D
var camera: Camera3D
var player: Node3D
var player_visual: Node3D
var player_ring: Node3D
var map_data: Dictionary = {}
var mode := "hub"
var enemies: Array = []
var bullets: Array = []
var swords: Array = []
var containers: Array = []
var extracts: Array = []
var effects: Array = []
var floating: Array = []
var terminal: Node3D
var terminal_on := false
var boss_dead := false
var active_loot := -1
var choices: Array = []
var taken: Dictionary = {}
var run_result: Dictionary = {}
var hp := 100.0
var max_hp := 100.0
var shield := 0.0
## Blessings collected this expedition (the run's power level shown on HUD/result).
var level := 1
var kills := 0
var run_time := 0.0
var visual_time := 0.0
var attack_timer := 0.0
var spawn_timer := 42.0
var dash_cd := 0.0
var dash_time := 0.0
var invuln := 0.0
var hurt_timer := 0.0
var regen_timer := 0.0
var extract_progress := 0.0
var extract_name := ""
var prompt := ""
var toast := ""
var toast_time := 0.0
var shake := 0.0
var direction := Vector3(0, 0, -1)
var dash_direction := Vector3.ZERO
var moving := false
var ui_tick := 0.0
var rng := RandomNumberGenerator.new()
var testing := false
var camera_target := Vector3.ZERO
var stage := 1
var stage_cleared := false
var clear_timer := 0.0
var reward_spawned := false
var gear_bonus: Dictionary = {}
var talent_bonus: Dictionary = {}
var talent_receipt: Dictionary = {}
var _talent_receipt_serial := 0
var _run_hero_id := ""
var trail_tick := 0.0
var transition := 0.0
var gate_armed := false
var hit_pause := 0.0
var hand_sword: Node3D
var melee_active := false
var melee_time := 0.0
var melee_duration := 0.38
var melee_windup := 0.055
var melee_buffer := 0.0
var combo := 0
var combo_window := 0.0
var melee_direction := Vector3.FORWARD
var melee_hits: Dictionary = {}
var melee_fx := false
var squash := 0.0
var squash_velocity := 0.0
var hit_flash := 0.0
var motion_reduced := false
var pickup_feed: Array = []
var impact_material: StandardMaterial3D
var spear
var hub_station := ""
var nearby_station := ""
var hub_marker: Node3D
var mouse_aim := false
var aim_pointer := Vector2.ZERO
var dash_charges := 2
var dash_recharge := 0.0
var dash_lock := 0.0
var mana := 100.0
var max_mana := 100.0
## Every weapon strike has an innate chance to crit; gear, talents and boons add to it.
var base_crit := 0.1
const COMBO_WINDOW := 2.4
var hit_combo := 0
var hit_combo_timer := 0.0
var hit_combo_best := 0
const BLESS_TIME := 1.25
var bless_glow := 0.0
var rainbow_material: ShaderMaterial
var _rainbow_on := false
var crit_material: StandardMaterial3D
var breakables: Array = []
var supply_pickups: Array = []
var boon_owned: Dictionary = {}
var choice_queue: Array = []
var boon_runtime
var vfx
var arts
var damage_numbers
var art_direction
var hero_combat
var dungeon
var dungeon_boss
var room_reward
var blades
## Player-triggered attacks snap toward the best nearby enemy (aim assist).
## Numeric suites keep raw facing unless they opt in.
var aim_assist := true
var env: Environment
var key_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var flashlight: SpotLight3D
var stage_theme: Dictionary = {}
var base_camera_size := 26.0
## Rush cinematics (presentation only): entry dip/hold, then wide fast follow.
var _rush_dip := 0.0
var _rush_cam := 0.0

func _ready() -> void:
	rng.randomize()
	data = Data.new()
	data.load_profile()
	_setup_inputs()
	_setup_scene()
	show_hub()
	if Quality.low(): _warmup_fx.call_deferred()

func _setup_inputs() -> void:
	var mapping := {"left":[KEY_A,KEY_LEFT], "right":[KEY_D,KEY_RIGHT], "up":[KEY_W,KEY_UP], "down":[KEY_S,KEY_DOWN], "dash":[KEY_SPACE,KEY_SHIFT], "interact":[KEY_E], "bag":[KEY_TAB,KEY_B], "melee":[KEY_J], "special":[KEY_K], "hero_primary":[KEY_F], "hero_secondary":[KEY_L], "time_stop":[], "rush":[], "pause":[KEY_ESCAPE]}
	for act in mapping:
		if not InputMap.has_action(act): InputMap.add_action(act)
		for key in mapping[act]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(act, ev)
	for act in ["melee","special"]:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT if act == "melee" else MOUSE_BUTTON_RIGHT
		if not InputMap.action_has_event(act,mouse): InputMap.action_add_event(act,mouse)

func _setup_scene() -> void:
	world = World.new()
	add_child(world)
	actors = Node3D.new()
	add_child(actors)
	var env_node := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("080e1c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("99b8d0")
	env.ambient_light_energy = 0.28
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Sky radiance provides actual view-dependent metal reflections in both renderers.
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("667b91")
	sky_material.sky_horizon_color = Color("b7c0cd")
	sky_material.ground_bottom_color = Color("4f5966")
	sky_material.ground_horizon_color = Color("9ba8b8")
	sky_material.sky_energy_multiplier = .30
	env.sky = Sky.new(); env.sky.sky_material = sky_material
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED if Quality.low() else Environment.REFLECTION_SOURCE_SKY
	if Quality.low(): env.sky = null; env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = not Quality.low()
	env.glow_intensity = .32
	env.glow_bloom = .02
	env.glow_hdr_threshold = 1.3
	env_node.environment = env
	add_child(env_node)
	var key := DirectionalLight3D.new(); key_light = key
	key.rotation_degrees = Vector3(-48, -32, 0)
	key.light_color = Color("b8c9d4")
	key.light_energy = 0.72
	key.shadow_enabled = not Quality.low()
	key.shadow_blur = 1.4
	key.shadow_bias = .035
	key.shadow_normal_bias = .6
	key.directional_shadow_max_distance = 80
	add_child(key)
	var fill := DirectionalLight3D.new(); fill_light = fill
	fill.rotation_degrees = Vector3(-25, 140, 0)
	fill.light_color = Color("517cb2")
	fill.light_energy = 0.22
	add_child(fill)
	flashlight = SpotLight3D.new()
	flashlight.light_color = Color("fff1d2"); flashlight.light_energy = 0.0
	flashlight.spot_range = 17.0; flashlight.spot_angle = 34.0; flashlight.spot_attenuation = .8
	flashlight.shadow_enabled = false; flashlight.visible = false
	add_child(flashlight)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 26
	camera.near = 0.1
	camera.far = 180
	add_child(camera)
	camera.current = true
	if not Quality.low():
		var scenery_focus := preload("res://scripts/scenery_focus.gd").new()
		camera.add_child(scenery_focus)
		scenery_focus.configure(world)
	ui = Interface.new()
	add_child(ui)
	ui.action.connect(_on_action)
	ui.card_landed.connect(func(quality: int):
		if sound != null:
			sound.play("impact",-31,1.35)
			if quality >= 2: sound.play("tick",-33,1.0)
	)
	sound = Sound.new()
	add_child(sound)
	impact_material = StandardMaterial3D.new()
	impact_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Struck enemies flash hot red; crits burn a brighter orange-red.
	impact_material.albedo_color = Color(1.0,.12,.10,.72)
	impact_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	crit_material = StandardMaterial3D.new()
	crit_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	crit_material.albedo_color = Color(1.0,.36,.16,.88)
	crit_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rainbow_material = ShaderMaterial.new()
	rainbow_material.shader = preload("res://assets/player_rainbow.gdshader")
	vfx = CombatVFX.new()
	add_child(vfx)
	boon_runtime = BoonRuntime.new(self)
	arts = CombatArts.new(self)
	hero_combat = HeroCombat.new(self)
	dungeon = DungeonRun.new(self)
	dungeon_boss = DungeonBoss.new(self)
	room_reward = RoomReward.new(self)
	blades = FlyingBlades.new(self)
	damage_numbers = DamageNumbers.new()
	add_child(damage_numbers)
	damage_numbers.configure(camera)
	art_direction = ArtDirection.new()
	add_child(art_direction)
	art_direction.configure(camera,env_node)
	if Quality.low():
		art_direction.set_enabled(false)
		art_direction.set_process(false)
		vfx.max_effects = 14
	touch_controls = TouchControls.new()
	add_child(touch_controls)
	touch_controls.bind(self)

func _clear_actors() -> void:
	if dungeon_boss != null: dungeon_boss.reset()
	if dungeon != null: dungeon.reset()
	if room_reward != null: room_reward.reset()
	if hero_combat != null: hero_combat.reset()
	if vfx != null: vfx.clear_all()
	if arts != null: arts.reset()
	if damage_numbers != null: damage_numbers.clear_all()
	if art_direction != null: art_direction.reset()
	world.set_time_frozen(0)
	if spear != null: spear.dispose(); spear = null
	for child in actors.get_children():
		actors.remove_child(child)
		child.queue_free()
	enemies.clear(); bullets.clear(); swords.clear(); containers.clear()
	extracts.clear(); effects.clear(); floating.clear()
	melee_active = false; melee_time = 0; melee_buffer = 0; combo = 0; combo_window = 0
	squash = 0; squash_velocity = 0; hit_pause = 0; hit_flash = 0
	hit_combo = 0; hit_combo_timer = 0; bless_glow = 0; _rainbow_on = false
	dash_time = 0; direction = Vector3.FORWARD
	breakables.clear(); supply_pickups.clear()
	mouse_aim = false; hub_marker = null

func show_hub() -> void:
	mode = "hub"
	_run_hero_id = ""
	_refresh_progression()
	boon_owned.clear(); taken.clear(); choice_queue.clear(); choices.clear()
	hub_station = ""; nearby_station = ""
	_clear_actors()
	map_data = world.build("hub")
	_spawn_player(map_data.get("spawn", Vector3.ZERO))
	player.rotation.y = 0
	player.scale = Vector3.ONE
	dash_cd = 0; dash_charges = 2; dash_lock = 0; dash_recharge = 0
	hp = max_hp; mana = max_mana; invuln = 0
	base_camera_size = 22.0; camera.size = 22.0
	_apply_theme(world.THEMES[0])
	camera_target = player.position + Vector3(0, 0, -1)
	_camera_update(1.0)
	_refresh_swords()
	_tick_hub(0)
	sound.combat = false
	push_ui()

func _spawn_player(pos: Vector3) -> void:
	player = Node3D.new()
	actors.add_child(player)
	player.position = pos
	hero_combat.set_hero(hero_id())
	hero_combat.set_talents(talent_bonus)
	player_visual = world.make_hero(hero_id())
	player.add_child(player_visual)
	hand_sword = world.make_sword(Color("fff0c9"))
	hand_sword.name = "HandSword"
	actors.add_child(hand_sword)
	hand_sword.scale = Vector3.ONE * 1.35
	hand_sword.position = pos + Vector3(.7,.85,0)
	var glow := OmniLight3D.new()
	glow.visible = not Quality.low()
	glow.name = "HeroLight"
	glow.light_color = Color(str(Heroes.get_hero(hero_id()).color))
	glow.light_energy = .65
	glow.omni_range = 3.5
	player.add_child(glow)
	glow.position.y = 1.4
	player_ring = _ring(player.position + Vector3(0, 0.045, 0), 0.7, Color(str(Heroes.get_hero(hero_id()).color)), actors)
	_sync_weapon()

func hero_id() -> String:
	return _run_hero_id if mode != "hub" and not _run_hero_id.is_empty() else str(data.hero().id)

func _refresh_progression() -> void:
	# This is a run snapshot, refreshed only in the safe hub or at deployment.
	talent_bonus = data.talent_bonuses(hero_id()).duplicate(true) if data.has_method("talent_bonuses") else {}
	gear_bonus = data.equipment_bonuses().duplicate(true)
	max_hp = 100.0+int(data.profile.upgrades.armor)*20+float(gear_bonus.get("hp",0))+float(talent_bonus.get("hp",0))
	if mode == "hub": hp = max_hp

func talent_crit_chance() -> float:
	return maxf(0,float(talent_bonus.get("crit",0)))

func talent_damage_multiplier() -> float:
	return 1.0+maxf(0,float(talent_bonus.get("damage",0)))

func _sync_hero() -> void:
	_refresh_progression()
	hero_combat.set_hero(hero_id())
	hero_combat.set_talents(talent_bonus)
	art_direction.reset()
	world.set_time_frozen(0)
	var old_rotation: Vector3 = player_visual.rotation
	player.remove_child(player_visual)
	player_visual.queue_free()
	player_visual = world.make_hero(hero_id())
	player.add_child(player_visual)
	player_visual.rotation = old_rotation
	var color := Color(str(data.hero().color))
	var light := player.get_node_or_null("HeroLight") as OmniLight3D
	if light != null: light.light_color = color
	if is_instance_valid(player_ring): player_ring.queue_free()
	player_ring = _ring(player.position+Vector3.UP*.045,.7,color,actors)

func weapon_family() -> String:
	return str(data.weapon().get("family","flying"))

func _sync_weapon() -> void:
	if spear != null: spear.dispose(); spear = null
	hand_sword.visible = false
	if weapon_family() == "spear":
		spear = Spear.new(self)
		spear.reset()
		spear.set_build(boon_owned)
	_refresh_swords()

func start_raid() -> void:
	if mode != "hub": return
	if not data.start_run():
		notify("无法开始行动：" + data.last_error)
		return
	mode = "raid"
	_run_hero_id = str(data.hero().id)
	hub_station = ""; nearby_station = ""
	_refresh_progression()
	hp = max_hp
	mana = max_mana
	shield = 0; level = 1; kills = 0
	if room_reward != null: room_reward.reset_run()
	run_time = 0; attack_timer = 0.2; dash_cd = 0
	hit_combo = 0; hit_combo_timer = 0; hit_combo_best = 0
	dash_charges = 2; dash_recharge = 0; dash_lock = 0
	invuln = 1.5; hurt_timer = 0; extract_progress = 0; spawn_timer = 42
	terminal_on = false; boss_dead = false; taken.clear(); choices.clear()
	boon_owned.clear(); choice_queue.clear()
	data.save_profile()
	stage = 1
	pickup_feed.clear()
	_load_stage()
	# Blessings now come only from room-clear drops; the run opens with one free pick.
	choice_queue = ["hammer","boon"]
	_open_next_choice()
	notify("第 1 层 · %s · 探索房间，击败首领，开启升降梯" % str(stage_theme.get("name","")), 4)
	push_ui()

## Per-floor mood: sky, ambient, key/fill lights, fog and the flashlight mode.
func _apply_theme(t: Dictionary) -> void:
	stage_theme = t
	if env != null:
		env.background_color = t.get("background",Color("080e1c"))
		env.ambient_light_color = t.get("ambient",Color("99b8d0"))
		env.ambient_light_energy = float(t.get("ambient_energy",.28))
		var density := float(t.get("fog_density",0.0))
		env.fog_enabled = density > 0.0 and not Quality.low()
		env.fog_light_color = t.get("fog",Color.BLACK)
		env.fog_density = density
		env.fog_sky_affect = .65
		env.fog_aerial_perspective = .35
		env.fog_height = -7.0
		env.fog_height_density = 0.0
	if key_light != null:
		key_light.light_color = t.get("key",Color("b8c9d4")); key_light.light_energy = float(t.get("key_energy",.72))
	if fill_light != null:
		fill_light.light_color = t.get("fill",Color("517cb2")); fill_light.light_energy = float(t.get("fill_energy",.22))
	var dark: bool = t.get("flashlight",false) and mode != "hub"
	if flashlight != null:
		flashlight.visible = dark; flashlight.light_energy = 3.2 if dark else 0.0
	if art_direction != null:
		art_direction.set_flashlight(dark)
		art_direction.set_sand_weather(t.get("id","") == "desert" and mode != "hub",motion_reduced)

func _tick_flashlight() -> void:
	if not stage_theme.get("flashlight",false) or not is_instance_valid(player) or mode == "hub": return
	var aim := Vector3(direction.x,0,direction.z)
	if aim.length_squared() < .001: aim = Vector3.FORWARD
	aim = aim.normalized()
	flashlight.position = player.position+Vector3.UP*2.6-aim*.6
	flashlight.look_at(player.position+aim*7.0+Vector3.UP*.2)
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0: return
	var at: Vector2 = camera.unproject_position(player.position+Vector3.UP*.8)
	var ahead: Vector2 = camera.unproject_position(player.position+Vector3.UP*.8+aim*4.0)
	art_direction.set_light(at/viewport_size,ahead-at)

func _load_stage() -> void:
	_clear_actors()
	# The old arena remains an explicit regression fixture, never the default.
	map_data = world.build("dungeon_%d" % stage)
	_spawn_player(map_data.spawn)
	for prop in map_data.get("breakables",[]): _spawn_breakable(prop.pos,prop.kind)
	stage_cleared = false; clear_timer = 0; reward_spawned = false
	boss_dead = false
	gate_armed = false; active_loot = -1; extract_progress = 0
	mode = "raid"
	transition = 1.0
	invuln = 1.5
	for e in map_data.enemies:
		var enemy := spawn_enemy(e.pos,e.kind)
		var multiplier := 1.0 + (stage-1)*.16
		enemy.hp *= multiplier; enemy.max_hp *= multiplier
		if e.kind in ["elite","boss"]:
			enemy["armor"] = enemy.hp*(.3 if e.kind == "elite" else .2)
			enemy.hp -= enemy.armor
	for e in map_data.extracts:
		var record: Dictionary = e.duplicate()
		record.locked = true
		record.node = _extraction_marker(e.pos,true)
		extracts.append(record)
	_restore_corpse()
	dungeon.begin(map_data)
	base_camera_size = 28.0 if world.theme.id == "desert" else 26.0; camera.size = base_camera_size
	_apply_theme(world.theme)
	_rush_dip = 0.0; _rush_cam = 0.0
	camera_target = player.position
	_camera_update(1)
	_refresh_swords()
	sound.combat = true
	push_ui()

func next_stage() -> void:
	if mode != "gate" or not stage_cleared: return
	stage += 1
	# The expedition continues: inventory, health and chosen powers remain at risk.
	_load_stage()
	if stage == 3:
		choice_queue.append("hammer")
		_open_next_choice()
	notify("第 %d 层 · %s%s" % [stage,str(stage_theme.get("name","")),"  ·  断电区域，手电筒照明" if stage_theme.get("flashlight",false) else " · 更强敌人与增援波次"], 3)

func clear_stage() -> void:
	if stage_cleared: return
	if dungeon != null and dungeon.enabled and not dungeon.can_finish_floor(): return
	stage_cleared = true
	clear_timer = .75
	reward_spawned = false
	data.profile["best_stage"] = maxi(int(data.profile.get("best_stage",0)),stage)
	data.save_profile()
	for b in bullets: b.life = 0
	sound.combat = false
	sound.play("level", -8, .8)
	sound.play("extract", -15, 1.25)
	shake = .18
	world.pulse_floor(player.position,.85)
	art_direction.flash(.12 if motion_reduced else .2,.14,Color("fff0d8"))
	play_combat_fx("clear_burst",player.position,ORANGE,direction,1.0)
	room_reward.on_room_cleared(player.position,"stage")
	mana = minf(max_mana,mana+35)
	_ring_effect(player.position, CYAN, .6, 12, 1.3)
	_ring_effect(player.position, ORANGE, .4, 8, .9)
	for i in 8:
		var a := TAU*i/8
		_burst(player.position+Vector3(cos(a)*3,.2,sin(a)*3), CYAN if i%2==0 else ORANGE, 8)
	_spawn_stage_rewards()

func _spawn_stage_rewards() -> void:
	if reward_spawned: return
	reward_spawned = true
	var rewards := 3 + mini(stage/2,3)
	for i in rewards:
		var rarity := _roll_rarity()
		var candidates: Array = []
		for id in Data.ITEMS:
			var def: Dictionary = Data.ITEMS[id]
			if int(def.get("rarity",-1)) == rarity and def.has("slot"): candidates.append(id)
		if candidates.is_empty(): candidates = ["cache","relic","circuit"]
		var id: String = candidates[rng.randi_range(0,candidates.size()-1)]
		var pos: Vector3 = player.position
		pos.y = world.ground_height(pos)
		_spawn_equipment(pos,id)
	var supply := spawn_container(player.position, ["circuit","scrap","cell"] if stage%2==0 else ["scrap","circuit","medkit"], "补给奖励 / SUPPLY", 0)
	_begin_loot_toss(supply)
	if stage % 5 == 0 or (dungeon != null and dungeon.enabled):
		var core := spawn_container(player.position,["core","cache"],"守卫核心 / MISSION",4)
		_begin_loot_toss(core)
	for e in extracts:
		e.locked = false
		if is_instance_valid(e.node): e.node.queue_free()
		e.node = _extraction_marker(e.pos,false)
	notify("首领已击败 · 升降梯开放，继续深入或撤离" if dungeon.enabled else "肃清完成 · 战利品自动回收 · 北侧出口继续 / 撤离", 2.5)

func spawn_room_rewards(pos: Vector3, count: int, premium: bool = false) -> void:
	for i in count:
		var rarity := _roll_rarity()
		if premium: rarity = mini(4,maxi(1,rarity))
		var candidates: Array[String] = []
		for id in Data.ITEMS:
			var item: Dictionary = Data.ITEMS[id]
			if item.has("slot") and int(item.get("rarity",-1)) == rarity: candidates.append(str(id))
		if not candidates.is_empty(): _spawn_equipment(pos,candidates[rng.randi_range(0,candidates.size()-1)])

func _roll_rarity() -> int:
	var roll := rng.randf()*100
	var bonus := minf(26,(stage-1)*5)
	if roll < 3+bonus*.22: return 4
	if roll < 13+bonus*.7: return 3
	if roll < 35+bonus: return 2
	if roll < 70+bonus*.6: return 1
	return 0

func _alive_count() -> int:
	var count := 0
	for e in enemies:
		if e.hp > 0: count += 1
	return count

func _spawn_equipment(pos: Vector3, id: String) -> void:
	var def: Dictionary = Data.ITEMS[id]
	var rarity := int(def.get("rarity",0))
	var color := Color(str(def.color))
	var record := spawn_container(pos,[id],str(def.get("rarity_name","装备")) + " / " + str(def.name),rarity)
	var root: Node3D = record.node
	record["delay"] = 1.15 + rarity * .035
	record.beacon.visible = false
	record["equipment"] = true
	# Cuboid item floats inside a softly animated rarity column.
	var model: Node3D
	if def.get("slot","") == "blade":
		model = world.make_sword(color)
		root.add_child(model)
		model.position = Vector3(0,1.15,0)
		model.rotation.z = -.45
	else:
		model = Node3D.new()
		root.add_child(model)
		world.box(model,Vector3.ZERO,Vector3(.48,.62,.32),color,.7)
		world.box(model,Vector3(0,0,-.19),Vector3(.18,.28,.06),Color.WHITE,1.2)
		model.position.y = 1.1
	record["model"] = model
	var beam := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.height = 4.6 + rarity*.4
	mesh.top_radius = .35 + rarity*.03
	mesh.bottom_radius = .45 + rarity*.04
	mesh.radial_segments = 16
	mesh.cap_top = false
	mesh.cap_bottom = false
	beam.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/loot_beam.gdshader")
	mat.set_shader_parameter("beam_color",color)
	mat.set_shader_parameter("strength",1.0+rarity*.2)
	beam.material_override = mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam)
	beam.position.y = mesh.height*.5
	record["column"] = beam
	var column_mat := ShaderMaterial.new()
	column_mat.shader = preload("res://assets/loot_column.gdshader")
	column_mat.set_shader_parameter("beam_color",color)
	for i in 2:
		var curtain := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1.35+rarity*.15,5.5+rarity*.35)
		curtain.mesh = quad
		curtain.material_override = column_mat
		curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(curtain)
		curtain.position.y = quad.size.y*.5
		curtain.rotation.y = .64 + i*PI*.5
	# A bright, narrow core makes rarity identifiable even without post-process bloom.
	world.box(root,Vector3(0,2.0+rarity*.1,0),Vector3(.035,3.8+rarity*.2,.035),color,1.5)
	for i in 6+rarity:
		var a := i*2.4
		world.box(root,Vector3(cos(a)*.35,.6+i*.38,sin(a)*.35),Vector3(.055,.11,.055),color,1.4)
	var halo := _ring(Vector3(0,.06,0),.7+rarity*.08,color,root)
	record["halo"] = halo
	_label_3d(root,str(def.name),Vector3(0,2.0,0),color,26)
	_burst(pos+Vector3(0,.5,0),color,22+rarity*8)
	_ring_effect(pos,color,.2,2.0+rarity*.25,.75)
	_ring_effect(pos,Color.WHITE,.1,1.1,.28)
	root.scale = Vector3.ONE
	_begin_loot_toss(record)
	if rarity >= 3: sound.play("pickup_rare", -18, 1.0+rarity*.05)

func _sword_trail(from: Vector3, to: Vector3, color: Color) -> void:
	if from.distance_to(to) < .02 or effects.size() > 220: return
	var node := _beam(from,to,color,.065)
	effects.append({"node":node,"life":.16,"max":.16,"vel":Vector3.ZERO,"grow":-2.0})

func _process(delta: float) -> void:
	var clear_freeze: bool = room_reward != null and room_reward.is_freezing()
	if vfx != null: vfx.set_frozen(mode not in ["hub","raid"] or clear_freeze)
	if damage_numbers != null:
		damage_numbers.set_frozen(mode not in ["hub","raid"])
		damage_numbers.reduced_motion = motion_reduced
	if art_direction != null:
		art_direction.set_frozen(mode in ["pause","inventory","skills","gate"])
		# Room-clear stop reuses only the cool grade; the CRT pass stays reserved for the time-stop art.
		art_direction.set_time_stop(maxf(1.0 if arts.frozen_enemies else 0.0,room_reward.stop_amount() if room_reward != null else 0.0))
		art_direction.set_rush(.4 if motion_reduced and arts.rushing else (1.0 if arts.rushing else 0.0))
	var rush_hold := clampf((_rush_dip-.45)/.55,0,1)*(.5 if motion_reduced else .85)
	if art_direction != null and rush_hold > 0: art_direction.set_time_stop(maxf(art_direction._target_stop,rush_hold))
	world.set_time_frozen(maxf(maxf(1.0 if arts != null and arts.frozen_enemies else 0.0,room_reward.stop_amount() if room_reward != null else 0.0),rush_hold))
	if art_direction != null and is_instance_valid(player) and camera != null:
		var vs := get_viewport().get_visible_rect().size
		if vs.x > 0: art_direction.set_rush_center(camera.unproject_position(player.position+Vector3.UP*.8)/vs)
		var heat := clampf((float(hit_combo)-4.0)/40.0,0,1)*(.35 if motion_reduced else .8) if mode == "raid" else 0.0
		art_direction.set_combo_heat(heat,Color("ff6bd6") if hit_combo >= 50 else (Color("ffc15a") if hit_combo >= 25 else Color("7ff4ff")))
	if mode == "raid": _tick_flashlight()
	world.set_process(mode in ["hub","raid"])
	if mode in ["hub","raid"]: visual_time += delta
	hit_flash = maxf(0,hit_flash-delta*3.5)
	for i in range(pickup_feed.size()-1,-1,-1):
		pickup_feed[i].age += delta
		if pickup_feed[i].age > 5.0: pickup_feed.remove_at(i)
	transition = maxf(0,transition-delta*1.5)
	toast_time = maxf(0, toast_time - delta)
	if toast_time <= 0: toast = ""
	if is_instance_valid(player):
		_camera_update(delta)
		if mode == "hub":
			_tick_swords(delta, false)
	for e in effects:
		if e.get("particles",false): e.node.speed_scale = 1.0 if mode in ["hub","raid"] and not clear_freeze else 0.0
	if mode in ["hub", "raid"] and not clear_freeze:
		_tick_effects(delta)
		_tick_enemy_feedback(delta)
	ui_tick -= delta
	if ui_tick <= 0:
		ui_tick = 0.1
		push_ui()

func _physics_process(delta: float) -> void:
	if mode == "hub":
		if hub_station.is_empty():
			_tick_dash_recharge(delta)
			invuln = maxf(0,invuln-delta)
			_tick_player(delta)
			_tick_melee(delta)
		_tick_hub(delta)
		return
	if mode != "raid": return
	# Blessing drops animate in their own time domain so they keep moving
	# through the room-clear freeze and their own pre-impact hang.
	room_reward.tick(delta)
	if mode != "raid": return
	if room_reward.is_freezing():
		hit_pause = maxf(0,hit_pause-delta)
		return
	if hit_pause > 0:
		hit_pause -= delta
		return
	run_time += delta
	_tick_dash_recharge(delta)
	if hit_combo > 0:
		hit_combo_timer -= delta
		if hit_combo_timer <= 0: hit_combo = 0; hit_combo_timer = 0
	invuln = maxf(0, invuln - delta); hurt_timer = maxf(0, hurt_timer - delta)
	# Local time domains: players and their attacks advance while hostile actors freeze.
	arts.tick(delta)
	hero_combat.tick(delta)
	var enemy_delta: float = delta*arts.enemy_time_scale
	_tick_player(delta)
	_tick_melee(delta)
	boon_runtime.tick(delta,enemy_delta)
	if enemy_delta > 0: _tick_enemies(enemy_delta)
	_tick_bullets(delta,arts.enemy_time_scale)
	if mode != "raid": return
	_tick_swords(delta, true)
	if dungeon.enabled: dungeon.tick(enemy_delta)
	elif not stage_cleared and _alive_count() == 0: clear_stage()
	_tick_interactions(delta)
	_tick_supplies(delta)
	if stage_cleared:
		clear_timer = maxf(0,clear_timer-delta)
		if clear_timer <= 0 and not reward_spawned: _spawn_stage_rewards()
	elif not dungeon.enabled and _alive_count() == 0:
		clear_stage()
	if taken.has("shield") and hurt_timer <= 0:
		shield = minf(25.0 * int(taken.shield), shield + delta * 5)
	if taken.has("repair"):
		hp = minf(max_hp, hp + delta * int(taken.repair) * 0.8)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo: return
	# Global gameplay shortcut runs before Control tooltips consume Escape.
	if event.is_action_pressed("pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if mode == "skills" and event is InputEventKey and event.pressed:
		var index: int = int(event.physical_keycode)-KEY_1
		if index >= 0 and index < choices.size():
			ui.request_skill_choice(str(choices[index].id))
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion: aim_pointer = event.position
	if event.is_action_released("melee") and spear != null: spear.release_attack()
	if event.is_action_released("melee") and blades != null: blades.release()
	if event.is_action_released("special") and spear != null: spear.release_special()
	# Tab is a gameplay shortcut here; consume it before Control focus traversal.
	if event.is_action_pressed("bag") and mode in ["raid","inventory"]:
		mode = "inventory" if mode == "raid" else "raid"
		push_ui()
		get_viewport().set_input_as_handled()

func _toggle_pause() -> void:
	if mode == "hub": hub_station = ""
	elif mode == "raid": mode = "pause"
	elif mode in ["pause", "inventory", "loot", "gate"]: mode = "raid"
	push_ui()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo: return
	if event.is_action_pressed("pause"):
		_toggle_pause()
		return
	if mode == "hub":
		if event.is_action_pressed("interact"): interact()
		if event.is_action_pressed("dash") and hub_station.is_empty(): try_dash()
		return
	if mode != "raid": return
	if event.is_action_pressed("dash"): try_dash()
	if event.is_action_pressed("hero_primary"): use_hero_skill("primary")
	if event.is_action_pressed("hero_secondary"): use_hero_skill("secondary")
	if event.is_action_pressed("time_stop"): use_time_stop()
	if event.is_action_pressed("rush"): use_rush()
	if event.is_action_pressed("melee") or event.is_action_pressed("special"):
		_refresh_attack_facing()
	if event.is_action_pressed("melee"): try_melee()
	if event.is_action_pressed("special") and spear != null: spear.press_special()
	if event.is_action_pressed("interact"): interact()

func _tick_player(delta: float) -> void:
	var input := Input.get_vector("left", "right", "up", "down")
	var move := _movement_vector()
	moving = move.length() > 0.01
	var is_rushing: bool = arts != null and arts.rushing
	var is_airborne: bool = hero_combat != null and hero_combat.controls_movement
	if not is_rushing and not is_airborne:
		if moving: direction = move.normalized()
	else: moving = true
	var speed := 5.5
	speed *= 1.0 + float(gear_bonus.get("speed",0)) + float(talent_bonus.get("speed",0))
	if spear != null: speed *= spear.move_multiplier
	if dash_time > 0:
		dash_time -= delta
		move = dash_direction
		speed = 25.0 * (.75 if boon_owned.has("serrated_point") else 1.0)
	if not is_rushing and not is_airborne: _move_actor(player, move * speed * delta, 0.42)
	_sync_player_heading()
	var bounce := absf(sin(visual_time*13)) if moving else sin(visual_time*3)*.12
	# Under-damped spring: impulses overshoot and wobble back for a jelly feel.
	squash_velocity += (-squash*230.0-squash_velocity*11.0)*delta
	squash = clampf(squash+squash_velocity*delta,-.42,.38)
	# Each stride squats on contact and stretches at the top of the hop.
	var stretch := squash + ((bounce-.35)*.14 if moving else 0.0)
	player_visual.scale = Vector3(1.0-stretch*.5,1.0+stretch,1.0-stretch*.5)
	player_visual.position.y = bounce * .21 - minf(0,stretch)*.45 + _tick_blessing_glow(delta)
	if is_airborne:
		player_visual.position.y = hero_combat.visual_height
		player_visual.scale = Vector3(.87,1.22,.87) if hero_combat.visual_height > .1 else Vector3(1.18,.72,1.18)
	player_visual.rotation.z = lerpf(player_visual.rotation.z,-input.x*.10 if moving else 0.0,delta*12)
	player_visual.rotation.x = lerpf(player_visual.rotation.x,.10 if moving else 0.0,delta*12)
	player_visual.visible = true
	player_ring.position = player.position + Vector3(0,.045,0)
	player_ring.scale = Vector3.ONE * (1.0+sin(visual_time*12)*.08 if invuln > 0 else 1.0)
	player_ring.rotation.y += delta * 0.4
	if dash_time > 0 and int(visual_time * 60) % 3 == 0:
		_burst(player.position + Vector3(0,.45,0), CYAN, 2)

func _tick_hub(_delta: float) -> void:
	var selected: Dictionary = {}
	var distance := 2.55
	for station in map_data.get("stations",[]):
		var d: float = player.position.distance_to(station.pos)
		if d < distance:
			selected = station; distance = d
	var next: String = selected.get("kind","")
	if next != nearby_station:
		nearby_station = next
		if is_instance_valid(hub_marker): hub_marker.queue_free()
		hub_marker = null
		if not selected.is_empty(): hub_marker = _ring(selected.pos+Vector3(0,.045,0),1.1,CYAN,actors)
	prompt = ("摇杆移动 · 走近设施点「交互」 · 「冲刺」闪避" if preload("res://scripts/quality.gd").touch_active else "WASD 移动 · 走近设施按 E 使用 · Space 闪避") if selected.is_empty() else ("「交互」 " if preload("res://scripts/quality.gd").touch_active else "[E] ") + str(selected.name)
	if not hub_station.is_empty(): prompt = "[E / Esc] 关闭终端，回到大厅"

func _spawn_breakable(pos: Vector3, kind: String) -> Dictionary:
	pos = world.ground_position(pos)
	var node: Node3D = world.make_breakable(kind)
	actors.add_child(node)
	node.position = pos
	var record := {"node":node,"pos":pos,"kind":kind,"hp":35.0 if kind == "crate" else 25.0,"radius":.58 if kind == "crate" else .43}
	breakables.append(record)
	return record

func damage_breakables_segment(from: Vector3, to: Vector3, radius: float, damage: float, hit_set: Dictionary = {}) -> void:
	# Melee uses planar hit geometry; lift it to the local terrace, not world zero.
	from.y = world.ground_height(from)+.65
	to.y = world.ground_height(to)+.65
	for prop in breakables:
		if prop.hp <= 0: continue
		var key := "prop_%d" % prop.node.get_instance_id()
		if hit_set.has(key): continue
		var center: Vector3 = prop.pos+Vector3(0,.65,0)
		var closest := Geometry3D.get_closest_point_to_segment(center,from,to)
		if closest.distance_to(center) <= radius+float(prop.radius) and not world.line_blocked(from,prop.pos):
			hit_set[key] = true
			_damage_breakable(prop,damage)

func damage_breakables_radius(center: Vector3, radius: float, damage: float, hit_set: Dictionary = {}) -> void:
	for prop in breakables:
		if prop.hp <= 0: continue
		var key := "prop_%d" % prop.node.get_instance_id()
		if hit_set.has(key): continue
		if center.distance_to(prop.pos) <= radius+float(prop.radius) and not world.line_blocked(center,prop.pos):
			hit_set[key] = true
			_damage_breakable(prop,damage)

func _damage_breakable(prop: Dictionary, damage: float) -> void:
	if prop.hp <= 0: return
	prop.hp -= damage*talent_damage_multiplier()
	var color := ORANGE if prop.kind == "crate" else CYAN
	_burst(prop.pos+Vector3(0,.6,0),color,8)
	sound.play("hit",-25,1.3)
	if prop.hp <= 0: _break_prop(prop)
	else:
		prop.node.scale = Vector3(1.12,.84,1.12)
		var tw: Tween = prop.node.create_tween()
		tw.tween_property(prop.node,"scale",Vector3.ONE,.16).set_trans(Tween.TRANS_BACK)

func _break_prop(prop: Dictionary, forced_drop: String = "") -> void:
	if prop.get("destroyed",false): return
	prop["destroyed"] = true; prop.hp = 0
	prop.node.visible = false
	var pos: Vector3 = prop.pos
	_burst(pos+Vector3(0,.7,0),ORANGE if prop.kind == "crate" else CYAN,40)
	play_combat_fx("break",pos,ORANGE if prop.kind == "crate" else CYAN,direction,.9)
	_ring_effect(pos,ORANGE if prop.kind == "crate" else CYAN,.15,1.7,.3)
	shake = maxf(shake,.06)
	sound.play("break",-18,.95 if prop.kind == "crate" else 1.2)
	var drop := forced_drop
	if drop.is_empty():
		var roll := rng.randf()
		drop = "equipment" if roll < .20 else _supply_drop_from_roll(roll,.28,.36)
	match drop:
		"equipment":
			var rarity := _roll_rarity()
			var candidates: Array = []
			for id in Data.ITEMS:
				if Data.ITEMS[id].has("slot") and int(Data.ITEMS[id].get("rarity",-1)) == rarity: candidates.append(id)
			if not candidates.is_empty(): _spawn_equipment(pos,candidates[rng.randi_range(0,candidates.size()-1)])
		"health", "mana": _spawn_supply(pos,drop)

func _supply_drop_from_roll(roll: float, health_limit: float, mana_limit: float) -> String:
	if roll < health_limit: return "health"
	if roll < mana_limit: return "mana"
	return "none"

func _spawn_supply(pos: Vector3, kind: String) -> void:
	var color := Color("ff6e82") if kind == "health" else Color("5ea7ff")
	var node := Node3D.new()
	actors.add_child(node)
	node.position = pos+Vector3(0,.65,0)
	if kind == "health":
		world.box(node,Vector3.ZERO,Vector3(.2,.65,.2),color,1.3)
		world.box(node,Vector3.ZERO,Vector3(.65,.2,.2),color,1.3)
	else:
		var crystal: Node3D = world.box(node,Vector3.ZERO,Vector3(.43,.43,.43),color,1.4)
		crystal.rotation = Vector3(.6,.2,.7)
	var halo := _ring(Vector3(0,-.5,0),.55,color,node)
	_label_3d(node,"生命 +25" if kind == "health" else "能量 +35",Vector3(0,.75,0),color,22)
	supply_pickups.append({"node":node,"pos":pos,"kind":kind,"amount":25.0 if kind == "health" else 35.0,"age":0.0,"halo":halo})
	_ring_effect(pos,color,.1,1.3,.4)

func _tick_supplies(delta: float) -> void:
	for i in range(supply_pickups.size()-1,-1,-1):
		var p: Dictionary = supply_pickups[i]
		p.age += delta
		p.node.rotation.y += delta*1.2
		p.halo.rotation.y -= delta*.5
		var needed: bool = hp < max_hp if p.kind == "health" else mana < max_mana
		var target := player.position+Vector3(0,.65,0)
		if p.age > .35 and needed and p.node.position.distance_to(target) < 3.5 and not world.line_blocked(p.node.position,target):
			p.node.position = p.node.position.move_toward(target,delta*9)
			if p.node.position.distance_to(target) < .6:
				var gained: float
				if p.kind == "health":
					gained = minf(p.amount,max_hp-hp); hp += gained
				else:
					gained = minf(p.amount,max_mana-mana); mana += gained
				var color := Color("ff7c8c") if p.kind == "health" else Color("72baff")
				_float_text(target+Vector3.UP,"+%d" % gained,color)
				_ring_effect(player.position,color,.2,1.3,.3)
				sound.play("heal_pickup" if p.kind == "health" else "energy_pickup",-17)
				p.node.queue_free(); supply_pickups.remove_at(i)
		else: p.node.position.y = world.ground_height(p.pos)+.65+sin(visual_time*3+p.age)*.12

func try_melee() -> void:
	if mode == "raid" and spear != null:
		_refresh_attack_facing()
		spear.press_attack()
		_sync_player_heading()
	elif mode == "raid" and weapon_family() == "flying" and blades != null:
		_refresh_attack_facing()
		blades.press()
		_sync_player_heading()

## Aim assist: when the player attacks, pick the enemy nearest the hero
## within reach (with line of sight), favouring ones roughly ahead, and turn
## to face it. Returns the chosen target or an empty Dictionary.
func assist_target(reach: float) -> Dictionary:
	if not aim_assist or mode != "raid" or not is_instance_valid(player): return {}
	var aim := Vector3(direction.x,0,direction.z)
	aim = aim.normalized() if aim.length_squared() > .001 else Vector3.FORWARD
	var best: Dictionary = {}
	var best_score := INF
	for e in enemies:
		if float(e.get("hp",0)) <= 0 or not is_instance_valid(e.get("node")): continue
		var to: Vector3 = e.node.position-player.position; to.y = 0
		var d := to.length()
		if d > reach: continue
		if world.line_blocked(player.position,e.node.position): continue
		var facing := aim.dot(to/d) if d > .01 else 1.0
		var score := d+(1.0-facing)*1.6
		if score < best_score: best_score = score; best = e
	return best

func assist_aim(reach: float) -> bool:
	var target := assist_target(reach)
	if target.is_empty(): return false
	_face_toward(target.node.position)
	return true

func _face_toward(pos: Vector3) -> void:
	var to := pos-player.position; to.y = 0
	if to.length_squared() < .01: return
	direction = to.normalized()
	_sync_player_heading()

func _tick_melee(delta: float) -> void:
	if spear == null: return
	spear.tick(delta)
	if hero_combat != null and hero_combat.controls_movement and is_instance_valid(spear.visual):
		spear.visual.position = player.position + direction.rotated(Vector3.UP,-PI*.5)*.43 + Vector3.UP*(hero_combat.visual_height+.9)
		spear.visual.rotation.x = -1.15 if hero_combat.visual_height > .1 else -.08
	_sync_player_heading()
	melee_active = spear.state not in ["idle"]
	combo = spear.combo
func _slash_effect(pos: Vector3, facing: Vector3, step: int) -> void:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius := 3.25 if step == 3 else 2.65
	for i in 28:
		for corner in [Vector2(i,0),Vector2(i+1,0),Vector2(i+1,1),Vector2(i,0),Vector2(i+1,1),Vector2(i,1)]:
			var t: float = corner.x/28.0
			var angle := lerpf(-1.35,1.35,t)
			var r: float = radius - (1.0-corner.y)*(.12+sin(t*PI)*.8)
			var point: Vector3 = facing.rotated(Vector3.UP,angle)*r
			point.y = sin(t*PI)*.16
			mesh.set_uv(Vector2(t,corner.y))
			mesh.add_vertex(point)
	var node := MeshInstance3D.new()
	node.mesh = mesh.commit()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/slash.gdshader")
	mat.set_shader_parameter("slash_color",ORANGE if step == 3 else CYAN)
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	actors.add_child(node)
	node.position = pos+Vector3(0,.85,0)
	effects.append({"node":node,"life":.24,"max":.24,"vel":Vector3.ZERO,"grow":.2,"ring_mat":mat})
	if step == 3: _ring_effect(pos+facing,ORANGE,.2,2.6,.35)

func _move_actor(actor: Node3D, displacement: Vector3, radius: float) -> void:
	# Substeps prevent a dash or low framerate from crossing thin cover.
	var steps := maxi(1, ceili(displacement.length() / 0.22))
	var step := displacement / float(steps)
	for i in steps:
		var p := actor.position
		if not _position_blocked(p + Vector3(step.x,0,0), radius): actor.position.x += step.x
		p = actor.position
		if not _position_blocked(p + Vector3(0,0,step.z), radius): actor.position.z += step.z
	actor.position.y = world.ground_height(actor.position)

func _position_blocked(pos: Vector3, radius: float) -> bool:
	if world.blocked(pos,radius): return true
	for prop in breakables:
		if prop.hp <= 0: continue
		var offset: Vector3 = pos-prop.pos
		offset.y = 0
		if offset.length() < radius+float(prop.radius): return true
	return false

func _movement_vector() -> Vector3:
	var input := Input.get_vector("left","right","up","down")
	return Vector3(.8087,0,-.5882)*input.x + Vector3(.5882,0,.8087)*input.y

func _refresh_attack_facing() -> void:
	# Read the held keys on the input edge too, before the next physics tick.
	# Standing attacks retain the last movement heading; mouse clicks never
	# silently rotate the weapon away from the character's visible front.
	mouse_aim = false
	if (arts != null and arts.rushing) or (hero_combat != null and hero_combat.controls_movement): return
	var move := _movement_vector()
	if move.length_squared() > .0001: direction = move.normalized()
	_sync_player_heading()

func _sync_player_heading() -> void:
	if not is_instance_valid(player_visual): return
	var facing := direction
	if spear != null and spear.is_direction_locked(): facing = spear.facing_direction()
	if facing.length_squared() > .0001: player_visual.rotation.y = atan2(-facing.x,-facing.z)

func _update_aim() -> void:
	_refresh_attack_facing()

func _tick_dash_recharge(delta: float) -> void:
	dash_lock = maxf(0,dash_lock-delta)
	if dash_charges < 2:
		dash_recharge -= delta
		if dash_recharge <= 0:
			dash_charges = 2
			dash_recharge = 0
	dash_cd = maxf(0,dash_recharge) if dash_charges <= 0 else 0.0

func try_dash() -> void:
	if mode not in ["raid","hub"] or (mode == "hub" and not hub_station.is_empty()): return
	if arts != null and arts.rushing: return
	if hero_combat != null and hero_combat.controls_movement: return
	if dash_charges <= 0 or dash_lock > 0: return
	if mode == "raid" and spear != null and not spear.dash_request(): return
	squash_velocity = 4.0
	var input := Input.get_vector("left","right","up","down")
	var move := Vector3(.8087,0,-.5882)*input.x + Vector3(.5882,0,.8087)*input.y
	dash_direction = move.normalized() if move.length() > .1 else direction
	dash_time = .18
	invuln = maxf(invuln,.18)
	dash_recharge = maxf(.3,.58-int(taken.get("dash",0))*.08)
	dash_charges -= 1
	dash_lock = .14
	dash_cd = dash_recharge if dash_charges <= 0 else 0
	sound.play("dash", -16)
	_ring_effect(player.position, CYAN, 0.5, 1.8, 0.22)
	if mode == "raid": boon_runtime.dash()

func use_time_stop() -> void:
	if hero_id() == "chrono": use_hero_skill("primary")

func use_rush() -> void:
	if hero_id() == "chrono": use_hero_skill("secondary")

func use_hero_skill(slot: String) -> void:
	if mode != "raid": return
	_refresh_attack_facing()
	var skill: Dictionary = hero_combat.state(slot)
	if skill.is_empty(): return
	if not hero_combat.trigger(slot):
		notify(str(skill.name)+" · "+hero_combat.error,1.8)
		return
	match str(skill.id):
		"time_stop":
			world.pulse_floor(player.position,1.0)
			art_direction.trigger_time_stop_crt(motion_reduced)
			shake = maxf(shake,.12)
			notify("时裂领域 · 敌人与弹幕冻结 %s 秒" % String.num(float(skill.duration),1),2.0)
		"rush":
			dash_time = 0
			if spear != null: spear.reset()
			art_direction.flash(.05 if motion_reduced else .12,.1,Color("b5efff"))
			# Cinematic entry: camera dips low and the frame holds for a beat
			# (presentation only — the rush clock and damage timing are untouched).
			art_direction.trigger_rush_freeze(.16,motion_reduced)
			_rush_dip = 1.0
			play_combat_fx("speed_lines",player.position,Color("bdf4ff"),direction,1.2)
			_ring_effect(player.position,Color("bdf4ff"),.3,2.4,.25)
			sound.play("dash",-14,.72)
			squash_velocity = 4.0
		"sky_slam":
			dash_time = 0
			if spear != null: spear.reset()
			sound.play("dash",-19,.68)
		"rewind_step":
			dash_time = 0
			art_direction.flash(.04 if motion_reduced else .09,.1)
		"flame_spin":
			world.pulse_floor(player.position,.55)
			shake = maxf(shake,.1)
		"gravity_well":
			world.pulse_floor(hero_combat.gravity_position,.6)
		"prism_guard":
			art_direction.flash(.04 if motion_reduced else .09,.12,Color("d4bcff"))
	push_ui()

func on_rush_step(step: int,from: Vector3,to: Vector3) -> void:
	shake = maxf(shake,.04 if motion_reduced else .09)
	_ring_effect(from,Color("bdf4ff"),.12,1.4,.16)
	if arts != null and step >= int(arts.tuning.rush_steps):
		shake = maxf(shake,.06 if motion_reduced else .2)
		art_direction.flash(.04 if motion_reduced else .1,.1,Color("dff8ff"))
		world.pulse_floor(to,.8,4.2)

func on_slam_impact(pos: Vector3, radius: float) -> void:
	world.pulse_floor(pos,1.0,radius)
	var viewport_size := get_viewport().get_visible_rect().size
	var screen_uv: Vector2 = camera.unproject_position(pos)/viewport_size
	art_direction.trigger_slam(screen_uv,motion_reduced)
	shake = maxf(shake,.08 if motion_reduced else .28)
	hit_pause = maxf(hit_pause,.045 if motion_reduced else .065)
	squash_velocity = -5.5
	sound.play("melee_heavy",-12,.7)
	sound.play("impact",-15,.58)
	sound.play("break",-19,.78)

## Base crit chance shown to the player and folded into every weapon roll.
func crit_chance_display() -> float:
	return clampf(base_crit+float(gear_bonus.get("crit",0))+talent_crit_chance(),0,1)

## Punchy, readable hit reaction: overlay flash (in hit_enemy), a squash pop,
## and a small extra shove on crits. Bosses only pop, they never get shoved.
func _enemy_hit_reaction(e: Dictionary,crit: bool) -> void:
	if not is_instance_valid(e.node): return
	if not e.has("base_scale"): e["base_scale"] = e.node.scale
	var amplitude := .34 if crit else .2
	if motion_reduced: amplitude *= .5
	e["pop_k"] = maxf(float(e.get("pop_k",0.0)) if float(e.get("pop_t",1.0)) < .08 else 0.0,amplitude)
	e["pop_t"] = 0.0
	if crit and e.kind != "boss":
		var away: Vector3 = e.node.position-player.position
		away.y = 0
		away = away.normalized() if away.length() > .01 else direction
		var push: Vector3 = e.get("knockback",Vector3.ZERO)
		e["knockback"] = push+away*6.0 if push.length() < 14.0 else push
		e["stagger"] = maxf(float(e.get("stagger",0.0)),.22)

func _tick_enemy_pop(e: Dictionary,delta: float) -> void:
	var node: Node3D = e.node
	e.pop_t = float(e.pop_t)+delta
	var base: Vector3 = e.get("base_scale",Vector3.ONE)
	if e.pop_t >= .5:
		e.pop_k = 0.0
		node.scale = base
		return
	# Damped wobble: squash flat on impact, rebound tall, settle.
	var s: float = float(e.pop_k)*exp(-float(e.pop_t)*8.5)*cos(float(e.pop_t)*31.0)
	node.scale = base*Vector3(1.0+s*.55,1.0-s,1.0+s*.55)

func _crit_feedback(e: Dictionary,pos: Vector3) -> void:
	var boss: bool = e.kind == "boss"
	shake = maxf(shake,(.05 if motion_reduced else (.2 if boss else .16)))
	hit_pause = maxf(hit_pause,.03 if motion_reduced else .06)
	if art_direction != null: art_direction.flash(.05 if motion_reduced else .1,.09,Color("fff1c4"))
	var center: Vector3 = pos+Vector3.UP*(1.6 if boss else .9)
	_burst(center,Color("ffd16a"),10)
	_ring_effect(center,Color("ffe8a8"),.2,1.7 if boss else 1.35,.22)
	play_combat_fx("impact",center,Color("ffd16a"),(pos-player.position).normalized(),1.25)
	sound.play("impact",-13,1.35)
	sound.play("break",-24,1.6)

func _count_combo(crit: bool) -> void:
	hit_combo += 1
	hit_combo_timer = COMBO_WINDOW
	hit_combo_best = maxi(hit_combo_best,hit_combo)
	if hit_combo in [10,25,50,100] or (hit_combo > 100 and hit_combo % 50 == 0):
		sound.play("pickup_rare",-17,1.0+minf(hit_combo,100)*.004)
		if not crit and art_direction != null and not motion_reduced: art_direction.flash(.05,.1,Color("ffd9a0"))

## Blessing absorbed: the body flashes a rolling rainbow and does a big jelly bounce.
func start_blessing_glow() -> void:
	bless_glow = BLESS_TIME
	squash_velocity = -9.5 if not motion_reduced else -5.0

func _tick_blessing_glow(delta: float) -> float:
	if bless_glow <= 0.0:
		if _rainbow_on and is_instance_valid(player_visual):
			_rainbow_on = false
			for part in player_visual.find_children("*","MeshInstance3D",true,false): part.material_overlay = null
		return 0.0
	bless_glow = maxf(0.0,bless_glow-delta)
	var u := 1.0-bless_glow/BLESS_TIME
	rainbow_material.set_shader_parameter("amount",(1.0-u*u)*(.6 if motion_reduced else 1.0))
	rainbow_material.set_shader_parameter("phase",u*3.0)
	if is_instance_valid(player_visual):
		_rainbow_on = true
		for part in player_visual.find_children("*","MeshInstance3D",true,false): part.material_overlay = rainbow_material
	# Tiny hop at the start of the bounce.
	return sin(clampf(u*3.2,0,1)*PI)*(.18 if not motion_reduced else .06)

func spawn_enemy(pos: Vector3, kind: String) -> Dictionary:
	pos = world.ground_position(pos)
	var node: Node3D = world.make_actor(kind)
	actors.add_child(node)
	node.position = pos
	var health := {"scout":40.0,"gunner":65.0,"sniper":55.0,"elite":160.0,"boss":650.0}
	var bar_root := Node3D.new()
	node.add_child(bar_root)
	bar_root.position.y = 2.2 if kind != "boss" else 3.8
	var bar: MeshInstance3D = world.box(bar_root, Vector3.ZERO, Vector3(1.0,.075,.08), RED, .6)
	var e := {"node":node,"kind":kind,"hp":health.get(kind,50.0),"max_hp":health.get(kind,50.0),"cooldown":rng.randf_range(1,2),"windup":0.0,"aim":Vector3.ZERO,"slow":0.0,"bar":bar,"telegraph":null,"phase":0,"seen":false}
	enemies.append(e)
	return e

func _tick_enemy_feedback(delta: float) -> void:
	# Health/impact feedback stays responsive while the hostile simulation is stopped.
	for e in enemies:
		if e.hp <= 0: continue
		var node: Node3D = e.node
		if e.get("flash",0.0) > 0:
			e.flash = maxf(0,e.flash-delta)
			if e.flash <= 0:
				for part in node.find_children("*","MeshInstance3D",true,false): part.material_overlay = null
		if float(e.get("pop_k",0.0)) > 0: _tick_enemy_pop(e,delta)
		e.bar.scale.x = maxf(.01,(e.hp+float(e.get("armor",0)))/e.max_hp)
		e.bar.visible = e.hp < e.max_hp or node.position.distance_to(player.position) < 10

func _tick_enemies(delta: float) -> void:
	for e in enemies:
		if e.hp <= 0: continue
		var node: Node3D = e.node
		var offset: Vector3 = player.position - node.position
		var distance: float = offset.length()
		e.slow = maxf(0, e.slow - delta)
		if e.get("stagger",0.0) > 0:
			e.stagger = maxf(0,e.stagger-delta)
			_move_actor(node,e.get("knockback",Vector3.ZERO)*delta,.42)
			e.knockback = e.get("knockback",Vector3.ZERO).move_toward(Vector3.ZERO,delta*32)
			continue
		if e.kind == "boss" and e.has("_boss"):
			e.seen = true
			dungeon_boss.tick(e,delta)
			continue
		if distance > 28: continue
		e.seen = true
		var aim := offset.normalized()
		node.rotation.y = lerp_angle(node.rotation.y, atan2(-aim.x,-aim.z), delta * 5)
		if e.windup > 0:
			e.windup -= delta*boon_runtime.move_multiplier(e)
			if e.windup <= 0:
				_enemy_fire(e)
				if is_instance_valid(e.telegraph): e.telegraph.queue_free()
				e.telegraph = null
			continue
		e.cooldown -= delta*boon_runtime.move_multiplier(e)
		var sight: bool = not world.line_blocked(node.position, player.position)
		var preferred := 5.0 if e.kind in ["scout","elite"] else 8.0
		if e.kind == "boss": preferred = 7.0
		if distance > preferred or not sight:
			var speed := (1.7 if e.kind != "scout" else 2.35)*(1.0+minf((stage-1)*.04,.25))
			if e.kind == "boss": speed = 1.2
			if e.slow > 0: speed *= .38
			speed *= boon_runtime.move_multiplier(e)
			# Repulsion keeps groups readable and gives space to evade.
			var separation := Vector3.ZERO
			for other in enemies:
				if other == e or other.hp <= 0: continue
				var diff: Vector3 = node.position - other.node.position
				if diff.length() < 1.3 and diff.length() > .01: separation += diff.normalized() * .65
			var motion := (aim + separation).normalized() * speed * delta
			var before := node.position
			_move_actor(node, motion, .42)
			if node.position.distance_to(before) < .005:
				_move_actor(node, aim.rotated(Vector3.UP, PI * .5) * speed * delta, .42)
		if e.cooldown <= 0 and sight and distance < 13:
			e.windup = 0.85 if e.kind != "sniper" else 1.2
			e.aim = player.position + Vector3(0,.7,0)
			e.telegraph = _beam(node.position + Vector3(0,.075,0), world.ground_position(e.aim)+Vector3.UP*.075, RED.darkened(.28), .045)
		if distance < 1.0: damage_player(8*boon_runtime.outgoing_multiplier(e))

func _enemy_fire(e: Dictionary) -> void:
	boon_runtime.before_fire(e)
	if e.hp <= 0: return
	var origin: Vector3 = e.node.position + Vector3(0,.7,0)
	var aim: Vector3 = (e.aim - origin).normalized()
	var speed := 5.5 + minf((stage-1)*.35, 2.5)
	var damage := 10.0
	var spread := 1
	match e.kind:
		"gunner": spread = 3
		"sniper": speed = 13.0; damage = 22
		"elite": spread = 5; damage = 13
		"boss": spread = 7; damage = 15
	damage *= boon_runtime.outgoing_multiplier(e)
	if dungeon.enabled: damage *= 1.0+minf((stage-1)*.08,.8)
	for i in spread:
		var angle := (float(i) - (spread - 1) * .5) * .17
		spawn_bullet(origin, aim.rotated(Vector3.UP, angle) * speed, damage)
	if e.kind == "boss":
		e.phase += 1
		for i in 16:
			var angle: float = TAU * i / 16.0 + e.phase * .22
			spawn_bullet(origin, Vector3(cos(angle),0,sin(angle)) * 4.5, 11*boon_runtime.outgoing_multiplier(e))
	e.cooldown = {"scout":2.4,"gunner":3.0,"sniper":3.6,"elite":2.6,"boss":2.9}.get(e.kind, 2.5)
	if dungeon.enabled: e.cooldown *= maxf(.72,1.0-(stage-1)*.035)
	sound.play("shot", -25, rng.randf_range(.8,1.1))

func spawn_bullet(pos: Vector3, velocity: Vector3, damage: float) -> void:
	var node: MeshInstance3D = world.box(actors, pos, Vector3(.16,.16,.43), ORANGE, 1.8)
	node.rotation.y = atan2(-velocity.x, -velocity.z)
	bullets.append({"node":node,"vel":velocity,"damage":damage,"life":5.0})

func _tick_bullets(delta: float, enemy_scale: float = 1.0) -> void:
	for i in range(bullets.size()-1,-1,-1):
		var b: Dictionary = bullets[i]
		var bullet_delta := delta*(1.0 if b.get("reflected",false) else enemy_scale)
		b.life -= bullet_delta
		if b.life <= 0:
			b.node.queue_free(); bullets.remove_at(i)
			continue
		# Stationary hostile bullets cannot hurt a player walking through stopped time.
		if bullet_delta <= 0: continue
		var from: Vector3 = b.node.position
		var next: Vector3 = from + b.vel * bullet_delta
		b.node.position = next
		if b.get("reflected",false):
			if world.line_blocked(from,next): b.life = 0
			else:
				for enemy in enemies.duplicate():
					if enemy.hp <= 0: continue
					var near: Vector3 = Geometry3D.get_closest_point_to_segment(enemy.node.position+Vector3.UP*.7,from,next)
					if near.distance_to(enemy.node.position+Vector3.UP*.7) < .6:
						hit_enemy(enemy,b.damage,false); b.life = 0
						break
			continue
		var close := Geometry3D.get_closest_point_to_segment(player.position + Vector3(0,.7,0), from, next)
		if world.line_blocked(from, close):
			b.life = 0
		elif close.distance_to(player.position + Vector3(0,.7,0)) < .53:
			damage_player(b.damage)
			b.life = 0
		if world.line_blocked(from, next): b.life = 0
		if b.life <= 0:
			b.node.queue_free()
			bullets.remove_at(i)

func damage_player(amount: float) -> void:
	if invuln > 0 or mode != "raid": return
	if arts != null and arts.rush_invulnerable: return
	if hero_combat != null and hero_combat.phase_invulnerable: return
	if spear != null and spear.sturdy: amount *= .7
	var incoming := amount
	if hero_combat != null: amount = hero_combat.absorb_damage(amount)
	var absorbed := minf(shield, amount)
	shield -= absorbed
	var health_damage := amount-absorbed
	hp -= health_damage
	invuln = .55; hurt_timer = 4; shake = .22
	hit_flash = .6; squash_velocity = -4.5
	hit_combo = 0; hit_combo_timer = 0
	extract_progress = 0
	sound.play("hurt", -13)
	_float_text(player.position + Vector3(0,2,0), "−%d" % health_damage if health_damage > 0 else "护盾 −%d" % incoming, RED if health_damage > 0 else Color("c5a1ff"))
	if hp <= 0:
		hp = 0
		finish_raid(false)

func _refresh_swords() -> void:
	if blades == null: blades = FlyingBlades.new(self)
	blades.refresh()

func _tick_swords(delta: float, combat: bool) -> void:
	if blades == null: return
	blades.tick(delta, combat)

func _bezier(a: Vector3,b: Vector3,c: Vector3,d: Vector3,t: float) -> Vector3:
	var inv := 1.0-t
	return a*inv*inv*inv + b*3.0*inv*inv*t + c*3.0*inv*t*t + d*t*t*t

func _nearest_enemy(pos: Vector3, radius: float, exclude: Dictionary = {}) -> Dictionary:
	var best: Dictionary = {}
	for e in enemies:
		if e.hp <= 0 or e == exclude: continue
		var distance: float = pos.distance_to(e.node.position)
		if distance < radius and not world.line_blocked(pos,e.node.position):
			best = e; radius = distance
	return best

func _chain_hit(source: Dictionary, damage: float) -> void:
	var target: Dictionary = _nearest_enemy(source.node.position, 5, source)
	if target.is_empty(): return
	var a: Vector3 = source.node.position + Vector3(0,1,0)
	var b: Vector3 = target.node.position + Vector3(0,1,0)
	var last := a
	for i in 6:
		var point := a.lerp(b,(i+1)/6.0)
		if i < 5: point += Vector3(rng.randf_range(-.3,.3),rng.randf_range(-.22,.22),rng.randf_range(-.3,.3))
		var beam := _beam(last,point,Color("c2a5ff"),.055)
		effects.append({"node":beam,"life":.22,"max":.22,"vel":Vector3.ZERO,"grow":0.0})
		last = point
	_burst(b,Color("b394ff"),5)
	hit_enemy(target, damage, false)

func hit_enemy(e: Dictionary, damage: float, crit: bool, allow_global_crit: bool = true, damage_kind: String = "normal") -> void:
	if e.hp <= 0: return
	# The only permanent damage multiplier: callers keep raw weapon/boon damage,
	# so chains, reflected projectiles and delayed statuses each receive it once.
	damage *= talent_damage_multiplier()
	if allow_global_crit and not crit and rng.randf() < float(boon_runtime.effect("pressure_points").get("global_crit",0))+talent_crit_chance()+base_crit:
		crit = true; damage *= 3
	var absorbed := minf(float(e.get("armor",0)),damage)
	e["armor"] = maxf(0,float(e.get("armor",0))-absorbed)
	e.hp -= damage-absorbed
	if e.hp > 0:
		e["flash"] = .13 if crit else .1
		var overlay: Material = crit_material if crit else impact_material
		for part in e.node.find_children("*","MeshInstance3D",true,false): part.material_overlay = overlay
	var pos: Vector3 = e.node.position
	if damage_numbers != null:
		var style := "armor" if absorbed >= damage and not crit else damage_kind
		damage_numbers.popup(pos+Vector3.UP*(3.9 if e.kind == "boss" else 2.15),damage,crit,style)
	_burst(pos + Vector3(0,.8,0), ORANGE, 4)
	_ring_effect(pos + Vector3(0,.9,0), ORANGE if crit else CYAN,.14,.85,.18)
	# Cross-cut flash on the struck body, rate-limited per enemy.
	if damage_kind != "dot" and visual_time-float(e.get("cross_at",-1.0)) > .07:
		e["cross_at"] = visual_time
		var aim_dir: Vector3 = pos-player.position if is_instance_valid(player) else Vector3.FORWARD
		play_combat_fx("cross_slash",pos+Vector3.UP*(2.0 if e.kind == "boss" else 1.0),Color("ff4a3a") if not crit else Color("ffb347"),aim_dir,1.6 if e.kind == "boss" else (1.25 if crit else 1.0))
	sound.play("hit", -23, rng.randf_range(.8,1.2))
	_enemy_hit_reaction(e,crit)
	if crit: _crit_feedback(e,pos)
	if damage_kind != "dot" and mode == "raid": _count_combo(crit)
	if e.hp <= 0:
		kills += 1
		var kill_tier := 2 if e.kind == "boss" else (1 if e.kind == "elite" else 0)
		hit_pause = maxf(hit_pause,.065 if kill_tier == 2 else .045)
		shake = maxf(shake,(.16 if kill_tier == 2 else (.09 if kill_tier == 1 else .035))*(.35 if motion_reduced else 1.0))
		art_direction.trigger_kill(kill_tier,motion_reduced)
		if taken.has("leech"): hp = minf(max_hp,hp + 4.0 * int(taken.leech))
		e.node.visible = false
		if is_instance_valid(e.telegraph): e.telegraph.queue_free()
		e.telegraph = null
		_burst(pos + Vector3(0,.8,0), RED, 10)
		play_combat_fx("enemy_shatter",pos,ORANGE if kill_tier > 0 else RED,direction,1.7 if kill_tier == 2 else (1.15 if kill_tier == 1 else .8))
		sound.play("break",-21 if kill_tier == 0 else -16,rng.randf_range(.78,1.02))
		if kill_tier == 0:
			var supply_kind := _supply_drop_from_roll(rng.randf(),.04,.08)
			if supply_kind != "none": _spawn_supply(pos,supply_kind)
		if e.kind == "boss":
			boss_dead = true
			if dungeon_boss != null: dungeon_boss.reset()
		# Equipment rains down only after the arena is clear; blessings drop per cleared room.

func _open_next_choice() -> void:
	if choice_queue.is_empty(): return
	var kind: String = str(choice_queue.pop_front())
	var hammer: bool = kind == "hammer" and weapon_family() == "spear"
	choices = Boons.offers(boon_owned,weapon_family(),rng,3,hammer)
	if weapon_family() == "flying":
		var pool: Array = Data.SKILLS.duplicate(true)
		for i in range(pool.size()-1,0,-1):
			var at := rng.randi_range(0,i)
			var swap: Variant = pool[i]; pool[i] = pool[at]; pool[at] = swap
		var amount: int = 3 if kind == "hammer" else 1
		for i in amount:
			var entry: Dictionary = pool[i].duplicate(true)
			entry.merge({"type":"flying","god":"剑阵协议","slot":"","rarity":0,"level":int(taken.get(entry.id,0))+1})
			if choices.size() > i: choices[i] = entry
			else: choices.append(entry)
	if choices.is_empty():
		_open_next_choice()
		return
	mode = "skills"
	sound.play("level", -13)
	push_ui()

func choose_skill(id: String) -> void:
	if mode != "skills": return
	var selected: Dictionary = {}
	for choice in choices:
		if choice.id == id: selected = choice
	if selected.is_empty(): return
	if Boons.lookup(id).is_empty():
		taken[id] = int(taken.get(id,0)) + 1
		if id == "shield": shield += 25
		if id == "repair": max_hp += 15; hp = minf(max_hp,hp + 35)
		if id == "extra": _refresh_swords()
	else:
		boon_owned = Boons.acquire(boon_owned,selected)
		if spear != null: spear.set_build(boon_owned)
		play_combat_fx("deflect",player.position,Color(str(selected.get("color","ffd18b"))),direction,1.1)
	choices.clear(); mode = "raid"
	if not choice_queue.is_empty(): _open_next_choice()
	push_ui()

func boon_entries() -> Array:
	return boon_runtime.entries() if boon_runtime != null else []
func combat_hit(enemy: Dictionary,damage: float,kind: String,origin: Vector3,aim: Vector3) -> void:
	boon_runtime.hit(enemy,damage,kind,origin,aim)

func _static_impact(hit: Dictionary, hit_set: Dictionary) -> void:
	if hit.is_empty(): return
	var key := "static_%d" % int(hit.index)
	if hit_set.has(key): return
	hit_set[key] = true
	world.react_static_hit(hit)
	play_combat_fx("static_shard",hit.point,Color("8fb5c2"),hit.normal,.9)
	sound.play("hit",-31,1.45)
	hit_pause = maxf(hit_pause,.012)
	shake = maxf(shake,.018*(.35 if motion_reduced else 1.0))

func combat_sweep(from: Vector3,to: Vector3,radius: float,kind: String,_hit_set: Dictionary = {}) -> void:
	boon_runtime.deflect_segment(from,to,radius,kind)
	_static_impact(world.static_hit_segment(from,to,radius),_hit_set)

func combat_burst(center: Vector3,radius: float,kind: String,_hit_set: Dictionary = {}) -> void:
	boon_runtime.deflect_segment(center,center,radius,kind)
	for hit in world.static_hits_radius(center,radius): _static_impact(hit,_hit_set)

func play_combat_fx(kind: String,pos: Vector3,color: Color = CYAN,aim: Vector3 = Vector3.FORWARD,size: float = 1.0) -> Node3D:
	if vfx != null:
		# A range indicator must match combat geometry even in reduced-motion mode.
		var shows_range := kind in ["flame_spin","gravity_well","gravity_burst","prism_guard","slam_mark","sky_slam"]
		var presentation_scale := .85 if motion_reduced and not shows_range else 1.0
		var node: Node3D = vfx.play(kind,pos,color,aim,size*presentation_scale)
		if kind == "time_stop" and node != null and vfx.has_method("set_effect_duration"):
			vfx.set_effect_duration(node,float(arts.tuning.time_duration)+.05)
		return node
	return null

func _begin_loot_toss(c: Dictionary) -> void:
	var angle: float = rng.randf()*TAU
	var speed: float = rng.randf_range(2.8,5.0)
	c["airborne"] = true
	c["velocity"] = Vector3(cos(angle)*speed,rng.randf_range(4.2,6.0),sin(angle)*speed)
	c["bounces"] = 0
	c["spin_velocity"] = Vector3(rng.randf_range(-5,5),rng.randf_range(-7,7),rng.randf_range(-4,4))
	c["base"] = c.node.position
	c["delay"] = 1.15 + int(c.tier)*.035
	if c.get("equipment",false):
		for child in c.node.get_children():
			if child != c.model: child.visible = false
	else: c.beacon.visible = false
	c.node.position.y = world.ground_height(c.node.position)+.2
	play_combat_fx("loot_burst",c.node.position,Color(str(Data.ITEMS[c.items[0]].color)),Vector3.UP,.65+int(c.tier)*.12)

func _tick_loot_toss(c: Dictionary,delta: float) -> void:
	var node: Node3D = c.node
	c.velocity.y -= 18.0*delta
	var next: Vector3 = node.position + c.velocity*delta
	if world.blocked(Vector3(next.x,0,node.position.z),.25):
		c.velocity.x *= -.5; next.x = node.position.x
	if world.blocked(Vector3(next.x,0,next.z),.25):
		c.velocity.z *= -.5; next.z = node.position.z
	if c.get("equipment",false): c.model.rotation += c.spin_velocity*delta
	var floor_y: float = world.ground_height(next)
	if next.y <= floor_y:
		next.y = floor_y
		c.bounces += 1
		c.velocity = Vector3(c.velocity.x*.45,absf(c.velocity.y)*.25,c.velocity.z*.45)
		if c.bounces >= 2 or c.age > .95:
			c.airborne = false; c.base = next
			if c.get("equipment",false):
				c.model.rotation = Vector3(0,rng.randf()*TAU,-.35)
				for child in node.get_children(): child.visible = true
				c.beacon.visible = false
			else: c.beacon.visible = true
			play_combat_fx("loot_land",next,Color(str(Data.ITEMS[c.items[0]].color)),Vector3.UP,.7+int(c.tier)*.12)
			_ring_effect(next,Color(str(Data.ITEMS[c.items[0]].color)),.15,1.25,.3)
			sound.play("loot",-25,1.25)
	node.position = next

func _roll_loot(tier: int) -> Array:
	var table := ["scrap","scrap","circuit","cell","medkit"]
	if tier >= 1: table.append_array(["circuit","cache","relic"])
	if tier >= 2: table.append_array(["cache","relic","key","core"])
	var result: Array = []
	for i in 1 + tier + (1 if rng.randf() < .55 else 0): result.append(table[rng.randi_range(0,table.size()-1)])
	return result

func spawn_container(pos: Vector3, items: Array, title: String, tier: int = 0) -> Dictionary:
	var root := Node3D.new()
	actors.add_child(root)
	root.position = pos
	var color := ORANGE if tier < 2 else Color("bd91fa")
	world.box(root, Vector3(0,.32,0), Vector3(.8,.58,.6), Color("283543"))
	world.box(root, Vector3(0,.64,0), Vector3(.84,.12,.64), color, .55)
	world.box(root, Vector3(0,.38,-.32), Vector3(.15,.32,.04), color, 1.2)
	var beacon: MeshInstance3D = world.box(root, Vector3(0,1.3,0), Vector3(.07,.8,.07), color, 1.2)
	var c := {"node":root,"items":items.duplicate(),"title":title,"tier":tier,"beacon":beacon,"corpse":false,"age":0.0,"delay":2.8,"collecting":false,"flight":0.0,"base":pos}
	containers.append(c)
	return c

func interact() -> void:
	if mode == "hub":
		if not hub_station.is_empty():
			hub_station = ""
		elif not nearby_station.is_empty():
			hub_station = nearby_station
			sound.play("ui",-18)
		push_ui()
		return
	if mode == "raid" and room_reward.try_pickup(): return
	for e in extracts:
		if player.position.distance_to(e.pos) < 2.2:
			if stage_cleared and reward_spawned:
				if _pending_rewards() > 0:
					notify("正在自动回收装备，请稍候",2)
					return
				mode = "gate"
				push_ui()
			return

func _pending_rewards() -> int:
	var remaining := 0
	for c in containers:
		if not c.corpse: remaining += c.items.size()
	return remaining

func _collect_container(c: Dictionary) -> void:
	var bag_before: Array = data.bag.duplicate(true) if c.corpse else []
	var profile_before: Dictionary = data.profile.duplicate(true) if c.corpse else {}
	var items_before: Array = c.items.duplicate()
	var collected: Array = []
	for i in range(c.items.size()-1,-1,-1):
		var id: String = c.items[i]
		if not data.add_loot(id): continue
		c.items.remove_at(i)
		collected.append(id)
	if c.corpse and not _sync_corpse(c):
		data.bag = bag_before; data.profile = profile_before
		c.items = items_before; c.collecting = false; c.flight = 0; c.age = c.delay-2.0
		c.node.position = c.base; c.node.scale = Vector3.ONE
		notify("遗失物资回收尚未保存，将自动重试",4)
		return
	for id in collected:
		var item: Dictionary = Data.ITEMS[id].duplicate(true)
		item["id"] = id; item["age"] = 0.0
		pickup_feed.push_front(item)
		if pickup_feed.size() > 5: pickup_feed.pop_back()
	if c.items.is_empty():
		c.node.visible = false
		_burst(player.position+Vector3(0,.65,0),CYAN,8)
		sound.play("loot",-20,1.0+minf(.3,c.tier*.06))
		push_ui()

func _tick_interactions(delta: float) -> void:
	prompt = ""
	extract_name = ""
	for c in containers:
		if c.items.is_empty():
			c.node.visible = false
			continue
		c.age += delta
		if c.get("airborne",false):
			_tick_loot_toss(c,delta)
			continue
		if c.collecting:
			c.flight = minf(1,c.flight+delta/0.32)
			var target := player.position+Vector3(0,.5,0)
			var u: float = c.flight*c.flight
			var old: Vector3 = c.node.position
			c.node.position = _bezier(c.base,c.base+Vector3(0,4,0),target+Vector3(0,2,0),target,u)
			c.node.scale = Vector3.ONE*lerpf(.45,.06,c.flight)
			_sword_trail(old,c.node.position,Color(Data.ITEMS[c.items[0]].color))
			if c.flight >= 1: _collect_container(c)
			continue
		c.node.scale = c.node.scale.lerp(Vector3.ONE,minf(1,delta*9))
		if c.get("equipment",false):
			c.model.rotation.y += delta * .8
			c.model.position.y = 1.15 + sin(visual_time*2)*.12
			c.halo.rotation.y += delta*.7
		else: c.beacon.position.y = 1.25 + sin(visual_time * 2) * .1
		var near_recovery: bool = not c.corpse or player.position.distance_to(c.node.position) < 3.0
		if c.age >= c.delay and near_recovery:
			c.collecting = true
			c.base = c.node.position
	var in_extract := false
	for e in extracts:
		if player.position.distance_to(e.pos) < 2.2:
			in_extract = true
			extract_name = e.name
			if e.locked:
				prompt = "击败本层首领后，升降梯解锁" if dungeon.enabled else "肃清本关敌人后，出口将解锁"
				extract_progress = 0
			else:
				extract_progress = 0
				prompt = "装备自动回收中…" if _pending_rewards() > 0 else "[E] 升降梯 · 深入下一层 / 撤离"
	if not in_extract: extract_progress = 0
	var blessing_prompt: String = room_reward.prompt()
	if not blessing_prompt.is_empty(): prompt = blessing_prompt

func _tick_pressure(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer <= 0:
		spawn_timer = maxf(20,42-run_time/20)
		var alive := 0
		for e in enemies:
			if e.hp > 0: alive += 1
		if alive < 35:
			for i in mini(4,1+int(run_time/90)):
				var pos := player.position + Vector3(rng.randf_range(-12,12),0,-13)
				if not world.blocked(pos,.5): spawn_enemy(pos, "gunner" if run_time > 120 else "scout")
		if run_time > 85: notify("警戒升级 · 增援正在进入中继站", 3)
	# Soft pressure: no hard countdown; armor damage increases after long expeditions.
	if run_time > 300:
		regen_timer += delta
		if regen_timer > 8: regen_timer = 0; damage_player(3)

func take_loot(index: int) -> bool:
	# Legacy callers cannot bypass the automatic collection lifecycle.
	return false

func finish_raid(success: bool) -> void:
	if mode not in ["raid","pause","gate"]: return
	if success and _pending_rewards() > 0: return
	if success and dungeon.enabled and not dungeon.can_finish_floor(): return
	var before: Dictionary = data.profile.duplicate(true)
	if not success:
		var lost_ids: Array = []
		for item in data.bag: lost_ids.append(item.id)
		data.profile["corpse"] = {"pos":[player.position.x,player.position.z],"items":lost_ids,"stage":stage}
	run_result = data.finish_run(success,kills)
	if run_result.get("save_failed",false):
		data.profile = before
		mode = "gate" if success else "pause"
		notify("结算尚未保存，请重试：" + str(run_result.get("error","")),8)
		push_ui()
		return
	run_result["time"] = run_time
	run_result["level"] = level
	run_result["stage"] = stage
	mode = "result"
	if dungeon_boss != null: dungeon_boss.reset()
	hero_combat.reset()
	arts.reset()
	art_direction.reset()
	world.set_time_frozen(0)
	vfx.clear_all()
	damage_numbers.clear_all()
	sound.combat = false
	sound.play("extract" if success else "hurt", -12, 1 if success else .7)
	push_ui()

func _restore_corpse() -> void:
	var corpse: Dictionary = data.profile.get("corpse",{})
	if corpse.is_empty() or corpse.get("items",[]).is_empty() or int(corpse.get("stage",1)) != stage: return
	var p: Array = corpse.pos
	var c := spawn_container(Vector3(float(p[0]),0,float(p[1])),corpse.items.duplicate(),"遗失物资 / RECOVERY",2)
	c.corpse = true
	_label_3d(c.node,"靠近自动回收",Vector3(0,2,0),Color("bb98ef"),30)

func _sync_corpse(c: Dictionary) -> bool:
	if data.profile.has("corpse"):
		data.profile.corpse.items = c.items.duplicate()
		return data.save_profile()
	return true

func _on_action(action: String, value: Variant = null) -> void:
	var station_permissions := {"select_hero":"heroes","unlock_talent":"heroes","buy_equipment":"shop","select_weapon":"workbench","upgrade":"workbench","equip":"warehouse","unequip":"warehouse","sell_item":"warehouse","open_caches":"warehouse","buy_med":"shop","sell":"shop","claim_quest":"shop","start":"deploy"}
	if station_permissions.has(action) and (mode != "hub" or hub_station != station_permissions[action]): return
	sound.play("ui", -23)
	match action:
		"melee":
			try_melee()
			if spear != null: spear.release_attack()
			if blades != null: blades.release()
		"special":
			if mode == "raid" and spear != null:
				spear.press_special()
				spear.release_special()
		"station_close": hub_station = ""
		"dash": try_dash()
		"time_stop": use_time_stop()
		"rush": use_rush()
		"hero_primary": use_hero_skill("primary")
		"hero_secondary": use_hero_skill("secondary")
		"select_hero":
			if data.select_hero(str(value)):
				_sync_hero()
				notify("已部署 · "+str(data.hero().name),2.0)
			else: notify("英雄选择未保存 · "+data.last_error,3.0)
		"unlock_talent":
			if value is Dictionary and value.has("hero") and value.has("node"):
				if data.unlock_talent(str(value.hero),str(value.node)):
					_refresh_progression(); hero_combat.set_talents(talent_bonus)
					_talent_receipt_serial += 1
					talent_receipt = {"hero":str(value.hero),"node":str(value.node),"serial":_talent_receipt_serial}
					notify("天赋已点亮 · 永久成长已保存",2.5)
				else: notify("天赋未解锁 · "+data.last_error,3.0)
		"buy_equipment":
			if data.buy_equipment(str(value)): notify("装备已购入仓库 · 可前往仓库装配",2.5)
			else: notify("购买未完成 · "+data.last_error,3.0)
		"motion_reduced":
			motion_reduced = bool(value)
			art_direction.set_sand_weather(stage_theme.get("id","") == "desert" and mode != "hub",motion_reduced)
		"start": start_raid()
		"next_stage": next_stage()
		"extract":
			if mode == "gate" and stage_cleared: finish_raid(true)
		"equip":
			if mode == "hub" and data.has_method("equip_stash"):
				notify("装备已整备 · 下一次出击生效" if data.equip_stash(int(value)) else "无法装备该物品")
		"unequip":
			if mode == "hub": notify("装备已放回仓库" if data.unequip_slot(str(value)) else "该栏位没有装备")
		"sell_item":
			if mode == "hub": notify("装备兑换 +%d 信用点" % data.sell_item(int(value)))
		"map":
			if mode in ["raid","inventory"]: mode = "inventory" if mode == "raid" else "raid"
		"select_weapon":
			if mode == "hub":
				if data.select_weapon(str(value)): _sync_weapon()
				else: notify("信用点不足，先带回物资兑换")
		"upgrade":
			if mode == "hub": notify("设施升级完成" if data.upgrade(str(value)) else "材料或信用点不足，详情见设施卡片")
		"sell":
			if mode == "hub": notify("物资兑换 +%d 信用点" % data.sell_stash())
		"buy_med":
			if mode == "hub": notify("修复剂已入库" if data.buy_med() else "信用点不足")
		"claim_quest":
			if mode == "hub": notify("回收委托已完成 · +900 信用点" if data.claim_quest() else "需要将 1 枚中继核心带回仓库")
		"open_caches":
			if mode == "hub": notify("已开启 %d 个封装宝箱" % data.open_caches())
		"close", "resume":
			if mode in ["loot","inventory","pause","gate"]: mode = "raid"
		"skill": choose_skill(str(value))
		"hub":
			if mode == "result": show_hub()
		"abandon":
			if mode == "pause": finish_raid(false)
		"quit":
			if not OS.has_feature("web"): get_tree().quit()
		"volume": AudioServer.set_bus_volume_db(0,linear_to_db(maxf(.001,float(value))))
	if mode == "hub" and action in ["equip","unequip","upgrade"]: _refresh_progression()
	push_ui()

func notify(message: String, duration: float = 3.5) -> void:
	toast = message; toast_time = duration

func push_ui() -> void:
	if not is_instance_valid(ui): return
	var weapons: Array = []
	for id in Data.WEAPONS:
		var w: Dictionary = Data.WEAPONS[id].duplicate()
		w.id = id; w.owned = id in data.profile.owned
		weapons.append(w)
	var bag: Array = []
	for entry in data.bag:
		var item: Dictionary = Data.ITEMS[entry.id].duplicate()
		item.merge(entry,true); bag.append(item)
	var stash: Array = []
	for id in data.profile.stash:
		if Data.ITEMS.has(id):
			var item: Dictionary = Data.ITEMS[id].duplicate()
			item.id = id; stash.append(item)
	var loot: Array = []
	var loot_title := ""
	if active_loot >= 0 and active_loot < containers.size():
		loot_title = containers[active_loot].title
		for id in containers[active_loot].items:
			var item: Dictionary = Data.ITEMS[id].duplicate()
			item.id = id; loot.append(item)
	var secure: Dictionary = {}
	if not data.secure.is_empty(): secure = Data.ITEMS[data.secure].duplicate(); secure.id = data.secure
	var costs: Dictionary = {}
	for id in ["pack","reactor","armor"]: costs[id] = data.upgrade_cost(id)
	var mini := {"player":Vector2.ZERO,"enemies":[],"extracts":[],"containers":[],"terminal":Vector2.ZERO,"bounds":map_data.get("bounds",Rect2(-24,-28,48,52))}
	if is_instance_valid(player): mini.player = Vector2(player.position.x,player.position.z)
	for e in enemies:
		if e.hp > 0 and e.seen and dungeon.visited_position(e.node.position): mini.enemies.append(Vector2(e.node.position.x,e.node.position.z))
	for e in extracts:
		if dungeon.visited_position(e.pos): mini.extracts.append({"pos":Vector2(e.pos.x,e.pos.z),"locked":e.locked})
	for c in containers:
		if not c.items.is_empty() and dungeon.visited_position(c.node.position): mini.containers.append(Vector2(c.node.position.x,c.node.position.z))
	var tp: Vector3 = map_data.get("terminal",Vector3.ZERO)
	mini.terminal = Vector2(tp.x,tp.z)
	if dungeon.enabled:
		mini.merge(dungeon.minimap(),true)
		mini.erase("terminal")
	var skills_taken: Array = []
	for id in taken:
		for skill in Data.SKILLS:
			if skill.id == id: skills_taken.append(skill.name + (" ×%d" % taken[id] if taken[id] > 1 else ""))
	var zone: String = ["装卸平台","熔芯车间","棱镜中枢","禁卫机库","核心熔炉"][(stage-1)%5]
	var equipped := {}
	for slot in data.profile.get("equipped",{}):
		var id: String = str(data.profile.equipped[slot])
		equipped[slot] = data.item(id) if not id.is_empty() else {}
	var state := {"mode":mode,"credits":data.profile.credits,"weapon":data.profile.weapon,"weapons":weapons,"upgrades":data.profile.upgrades,"upgrade_costs":costs,"stash":stash,"meds":data.profile.meds,"hp":hp,"max_hp":max_hp,"shield":shield,"level":level,"kills":kills,"time":run_time,"threat":1+int(run_time/90),"bag":bag,"bag_cols":data.bag_cols,"bag_rows":data.bag_rows(),"bag_value":data.bag_value(),"used_cells":data.used_cells(),"secure":secure,"dash_cd":dash_cd,"extract_progress":extract_progress,"extract_name":extract_name,"prompt":prompt,"toast":toast,"zone":zone,"quest":"击败守卫，带回 1 枚中继核心","quest_claimed":data.profile.quest_claimed,"skills_taken":skills_taken,"loot":loot,"loot_title":loot_title,"choices":choices,"result":run_result,"minimap":mini}
	state["stage"] = stage
	state["dungeon"] = dungeon.state()
	state["stage_cleared"] = stage_cleared
	state["clear_fx"] = clear_timer/.75
	state["boon_drops"] = room_reward.collected if room_reward != null else 0
	state["alive"] = _alive_count()
	state["best_stage"] = data.profile.get("best_stage",0)
	state["equipped"] = equipped
	state["gear_bonus"] = data.equipment_bonuses() if mode == "hub" and data.has_method("equipment_bonuses") else gear_bonus
	state["volume"] = db_to_linear(AudioServer.get_bus_volume_db(0))
	state["quest"] = "探索连通房间 · 击败本层首领开启下一层"
	state["transition"] = transition
	state["threat"] = stage
	state["melee_cd"] = spear.recovery_remaining if spear != null else 0.0
	if blades != null and spear == null:
		state["blades_ready"] = blades.ready_count()
		state["blades_total"] = blades.total()
		state["blades_state"] = blades.state_name()
	state["combo"] = combo
	state["melee_progress"] = spear.attack_progress if spear != null else 0.0
	state["hit_flash"] = hit_flash
	state["motion_reduced"] = motion_reduced
	state["pickup_feed"] = pickup_feed.duplicate(true)
	state["loot_count"] = data.bag.size()
	state["hub_station"] = hub_station
	state["nearby_station"] = nearby_station
	state["mana"] = mana
	state["heroes"] = Heroes.all()
	state["hero_id"] = hero_id()
	state["hero"] = Heroes.get_hero(hero_id())
	state["talent_tree"] = data.talent_tree(hero_id()) if data.has_method("talent_tree") else []
	state["talent_bonus"] = talent_bonus.duplicate(true)
	state["talents"] = data.profile.get("talents",{}).duplicate(true)
	state["talent_receipt"] = talent_receipt.duplicate(true)
	state["shop_offers"] = data.shop_offers() if data.has_method("shop_offers") else []
	state["hero_skills"] = {"primary":hero_combat.state("primary"),"secondary":hero_combat.state("secondary")}
	state["hero_shield"] = hero_combat.shield_amount
	state["shield"] = shield+hero_combat.shield_amount
	state["max_mana"] = max_mana
	state["combo"] = hit_combo
	state["combo_left"] = clampf(hit_combo_timer/COMBO_WINDOW,0,1)
	state["combo_best"] = hit_combo_best
	state["crit_chance"] = crit_chance_display()
	state["time_stop_left"] = arts.time_left
	state["time_stop_cd"] = arts.time_cd
	state["time_stop_duration"] = arts.tuning.time_duration
	state["time_stop_cost"] = arts.tuning.time_cost
	state["time_stop_cooldown"] = arts.tuning.time_cooldown
	state["rush_cd"] = arts.rush_cd
	state["rushing"] = arts.rushing
	state["rush_hits"] = arts.rush_hits.size()
	state["rush_cost"] = arts.tuning.rush_cost
	state["rush_cooldown"] = arts.tuning.rush_cooldown
	state["dash_charges"] = dash_charges
	state["spear_state"] = spear.state if spear != null else "idle"
	state["charge_ratio"] = spear.charge_ratio if spear != null else 0.0
	state["special_state"] = spear.special_state if spear != null else "idle"
	state["weapon_family"] = weapon_family()
	state["boons"] = boon_entries().duplicate(true)
	for entry in Data.SKILLS:
		if taken.has(entry.id):
			var row: Dictionary = entry.duplicate(true)
			row.merge({"type":"flying","slot":"passive","god":"剑阵协议","level":int(taken[entry.id]),"rarity_name":"共鸣","active":true},true)
			state.boons.append(row)
	state["boon_slots"] = boon_runtime.slots()
	state["hammer_count"] = boon_runtime.hammer_count()
	ui.update_view(state)

func _camera_update(delta: float) -> void:
	var desired: Vector3 = player.position * .66 + Vector3(0,.5,0)
	if dungeon != null and dungeon.enabled: desired = player.position + Vector3(0,.5,0)
	if mode == "hub":
		desired = player.position + Vector3(0,.5,-1)
		if not hub_station.is_empty(): desired += Vector3(.8087,0,-.5882)*(5.5 if hub_station == "heroes" else 3.5)
	var rushing: bool = arts != null and arts.rushing and mode == "raid"
	_rush_dip = move_toward(_rush_dip,0.0,delta*3.2)
	_rush_cam = move_toward(_rush_cam,1.0 if rushing else 0.0,delta*(5.0 if rushing else 2.0))
	var cine := .4 if motion_reduced else 1.0
	var dip := _rush_dip*_rush_dip*cine
	var wide := _rush_cam*cine
	# Rush follows tightly so the hero never leaves frame on 40 m/s steps.
	camera_target = camera_target.lerp(desired, minf(1,delta*lerpf(7.0,22.0,_rush_cam)))
	var offset := Vector3(16,22,22).lerp(Vector3(19,11,26),dip*.75)
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		camera.size = base_camera_size*(1.0-.16*dip+.2*wide)
	var lead: Vector3 = blades.camera_offset() if blades != null and weapon_family() == "flying" else Vector3.ZERO
	camera.position = camera_target + lead + offset
	if shake > 0:
		shake = maxf(0,shake-delta)
		if not motion_reduced: camera.position += Vector3(sin(visual_time*61)*shake,sin(visual_time*79)*shake*.5,0)
	camera.look_at(camera_target + lead)

func _ring(pos: Vector3, radius: float, color: Color, parent: Node3D) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.position = pos
	for i in 32:
		if i % 8 >= 6: continue
		var a := TAU*i/32.0
		var mesh: MeshInstance3D = world.box(root,Vector3(cos(a)*radius,0,sin(a)*radius),Vector3(.055,.025,radius*.2),color,1)
		mesh.rotation.y = -a
	return root

func _extraction_marker(pos: Vector3, locked: bool) -> Node3D:
	var color := Color("7df2ac") if not locked else Color("a18b71")
	var root := _ring(pos + Vector3(0,.05,0),2.0,color,actors)
	for i in 4:
		var a := TAU*i/4.0 + PI*.25
		world.box(root,Vector3(cos(a)*1.85,.32,sin(a)*1.85),Vector3(.2,.65,.2),color,1.2)
	_label_3d(root,"跃迁 / EXIT" if not locked else "肃清后解锁",Vector3(0,.35,0),color,30)
	return root

func _beam(from: Vector3, to: Vector3, color: Color, width: float) -> MeshInstance3D:
	var length := from.distance_to(to)
	# Thousands of moving trails share a unit mesh/material; continuous lengths
	# must not become permanent keys in the world's animated material cache.
	var node: MeshInstance3D = world.box(actors,(from+to)*.5,Vector3.ONE,color,1.2)
	node.scale = Vector3(width,width,maxf(length,.01))
	if length > .01: node.look_at(to,Vector3.RIGHT if absf((to-from).normalized().dot(Vector3.UP)) > .98 else Vector3.UP)
	return node

func _label_3d(parent: Node3D, text: String, pos: Vector3, color: Color, font_size: int) -> Label3D:
	var label := Label3D.new()
	parent.add_child(label)
	label.text = text
	label.position = pos
	label.font_size = font_size
	label.pixel_size = .012
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.outline_size = 5
	return label

func _float_text(pos: Vector3, text: String, color: Color) -> void:
	var label := _label_3d(actors,text,pos,color,36)
	floating.append({"node":label,"life":.75})

func _burst(pos: Vector3, color: Color, count: int) -> void:
	if effects.size() > (40 if Quality.low() else 180): return
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.amount = mini(16 if Quality.low() else 64,count)
	particles.lifetime = .55
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.direction = Vector3.UP
	particles.spread = 75.0
	particles.gravity = Vector3(0,-11,0)
	particles.initial_velocity_min = 2.0
	particles.initial_velocity_max = 5.5
	particles.scale_amount_min = .55
	particles.scale_amount_max = 1.8
	particles.angular_velocity_min = -240
	particles.angular_velocity_max = 240
	var mesh := BoxMesh.new()
	mesh.size = Vector3(.11,.11,.11)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	particles.mesh = mesh
	var gradient := Gradient.new()
	gradient.set_color(0,color.lightened(.5))
	gradient.set_color(1,Color(color,0))
	gradient.add_point(.35,color)
	particles.color_ramp = gradient
	actors.add_child(particles)
	particles.position = pos
	particles.emitting = true
	effects.append({"node":particles,"life":.8,"max":.8,"vel":Vector3.ZERO,"grow":0.0,"particles":true})

func _spear_sweep_fx(pos: Vector3, radius: float, tier: int) -> void:
	var node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE*radius*2.15
	node.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/spear_sweep.gdshader")
	mat.set_shader_parameter("sweep_color",Color("ffc37b") if tier == 3 else Color("7cecff"))
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	actors.add_child(node)
	node.position = pos+Vector3(0,.85,0)
	effects.append({"node":node,"life":.24,"max":.24,"vel":Vector3.ZERO,"grow":0.0,"ring_mat":mat,"follow_player":true})

func _ring_effect(pos: Vector3, color: Color, start: float, finish: float, duration: float) -> void:
	var node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * finish * 2.1
	node.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shockwave.gdshader")
	mat.set_shader_parameter("wave_color",color)
	mat.set_shader_parameter("start_ratio",start/finish)
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	actors.add_child(node)
	node.position = pos + Vector3(0,.09,0)
	effects.append({"node":node,"life":duration,"max":duration,"vel":Vector3.ZERO,"grow":0.0,"ring_mat":mat})

func _tick_effects(delta: float) -> void:
	for i in range(effects.size()-1,-1,-1):
		var e: Dictionary = effects[i]
		e.life -= delta
		if e.has("ring_mat"): e.ring_mat.set_shader_parameter("progress",1.0-e.life/e.max)
		e.node.position += e.vel * delta
		if e.get("follow_player",false) and is_instance_valid(player): e.node.position = player.position+Vector3(0,.85,0)
		if e.vel.length() > 0: e.vel.y -= delta * 10
		e.node.scale += Vector3.ONE * e.grow * delta
		if e.life <= 0:
			e.node.queue_free(); effects.remove_at(i)
	for i in range(floating.size()-1,-1,-1):
		var f: Dictionary = floating[i]
		f.life -= delta
		f.node.position.y += delta * 1.15
		f.node.modulate.a = minf(1,f.life*2)
		if f.life <= 0: f.node.queue_free(); floating.remove_at(i)

## Platform self-test (UGC.selfTest). Uses an isolated profile, so real saves stay intact.
func auto_test() -> void:
	data = Data.new("user://ugc_selftest.json")
	data.load_profile()
	show_hub()
	await UGC.wait(.3)
	UGC.check(mode == "hub", "开局进入基地")
	UGC.check(touch_controls != null and touch_controls.get_parent() == self, "触控层已挂载")
	var p0 := player.position
	UGC.hold("right", true)
	await UGC.wait(.6)
	UGC.hold("right", false)
	UGC.check(player.position.x > p0.x + .5, "基地内可移动")
	start_raid()
	await UGC.wait(.4)
	UGC.check(mode in ["skills","raid"], "出击开始 · 模式=" + mode)
	var guard := 0
	while mode == "skills" and guard < 4:
		choose_skill(str(choices[0].id)); guard += 1
		await UGC.wait(.2)
	UGC.check(mode == "raid", "首次祝福选择完成")
	UGC.check(is_instance_valid(player), "房间生成并放置玩家")
	invuln = 99.0
	var p1 := player.position
	UGC.hold("up", true)
	await UGC.wait(.5)
	UGC.hold("up", false)
	UGC.check(player.position.distance_to(p1) > .4, "地下城内可移动")
	await UGC.press("dash", .1)
	await UGC.wait(.2)
	for i in 4:
		await UGC.press("melee", .08)
		await UGC.wait(.15)
	UGC.check(mode == "raid" and hp > 0, "连续攻击无报错 · hp=%d" % int(hp))
	touch_controls.activate()
	touch_controls.release_all()
	await UGC.wait(.2)
	UGC.check(touch_controls.visible and touch_controls._buttons.size() >= 6, "触控按钮布局 · %d 个" % touch_controls._buttons.size())
	UGC.check(Engine.get_frames_per_second() > 0, "渲染帧率 %d fps" % Engine.get_frames_per_second())
	invuln = 0.0

## Mobile/Web: compile every effect shader and particle material once behind a cover,
## so the first attack, skill or blessing does not stall for seconds.
var _warming := false
func _warmup_fx() -> void:
	if _warming or not is_instance_valid(player): return
	_warming = true
	var cover := CanvasLayer.new(); cover.layer = 50; add_child(cover)
	var bg := ColorRect.new(); bg.color = Color("080e1c"); bg.set_anchors_preset(Control.PRESET_FULL_RECT); cover.add_child(bg)
	var tip := Label.new(); tip.text = "正在准备特效…"; tip.set_anchors_preset(Control.PRESET_CENTER); tip.add_theme_font_override("font",Quality.font()); tip.add_theme_font_size_override("font_size",28); cover.add_child(tip)
	var at := player.position + Vector3(0,0,2)
	var temp: Array[Node] = []
	for kind in vfx.KINDS: vfx.play(kind,at,CYAN,Vector3.FORWARD,.6)
	_ring_effect(at,CYAN,.2,1.5,.3)
	_spear_sweep_fx(at,1.5,1)
	_slash_effect(at,Vector3.FORWARD,1)
	_burst(at,ORANGE,8)
	_sword_trail(at,at+Vector3.RIGHT,CYAN)
	_float_text(at,"0",CYAN)
	if damage_numbers != null: damage_numbers.popup(at+Vector3.UP,1.0,true); damage_numbers.popup(at+Vector3.UP,1.0,false)
	for sh in [preload("res://assets/loot_beam.gdshader"),preload("res://assets/loot_column.gdshader"),preload("res://assets/player_rainbow.gdshader"),RoomReward.BEAM_SHADER,RoomReward.RING_SHADER,RoomReward.CORE_SHADER]:
		var m := MeshInstance3D.new(); m.mesh = QuadMesh.new()
		var mat := ShaderMaterial.new(); mat.shader = sh; m.material_override = mat
		actors.add_child(m); m.position = at + Vector3(0,1,0); temp.append(m)
	for mat in [impact_material,crit_material]:
		var m := MeshInstance3D.new(); m.mesh = BoxMesh.new(); m.material_override = mat
		actors.add_child(m); m.position = at; temp.append(m)
	for i in 4: await get_tree().process_frame
	for n in temp: if is_instance_valid(n): n.queue_free()
	vfx.clear_all()
	if damage_numbers != null: damage_numbers.clear_all()
	for e in effects: if is_instance_valid(e.node): e.node.queue_free()
	effects.clear()
	for f in floating: if is_instance_valid(f.node): f.node.queue_free()
	floating.clear()
	await get_tree().process_frame
	cover.queue_free()
	_warming = false