extends Node2D
## 2D world built from the JSON game spec. Supports animated "AI is building" ops in edit mode
## and a full play mode (platformer or top-down).
const U = preload("res://util.gd")
const FX = preload("res://fx.gd")
const Ent = preload("res://ent2d.gd")
const Player = preload("res://player2d.gd")
const Drone = preload("res://drone2d.gd")

var main = null
var spec := {}
var topdown := false
var playing := false
var ents := {}
var player = null
var drone = null
var cam: Camera2D
var bg_layer: CanvasLayer
var bg_color: ColorRect
var bg_tex: TextureRect
var kill_y := 2000.0
var bounds := Rect2(-600, -800, 1800, 1200)
var selected := ""
var dragging := ""
var drag_off := Vector2.ZERO
var drag_moved := false
var sel_box: Node2D
var cam_target := Vector2.ZERO
var cam_zoom_target := 1.0
var user_cam := false
var ambient: CPUParticles2D
var ambient_kind := ""
var bg_far: TextureRect
var look_x := 0.0
var cam_y := 0.0
var goal_x := NAN
var start_x := 0.0

const CAM_LOOK_AHEAD := 0.22
const CAM_LOOK_SMOOTH := 2.5
const CAM_Y_DEADZONE := 90.0
const CAM_Y_SMOOTH := 5.0
const PARALLAX := 0.06

func setup(m, s: Dictionary) -> void:
	main = m
	spec = s
	cam = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	add_child(cam)
	cam.make_current()
	bg_layer = CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	bg_color = ColorRect.new()
	bg_color.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_color.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(bg_color)
	bg_tex = TextureRect.new()
	bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(bg_tex)
	# a gentle vignette keeps busy AI backgrounds from competing with gameplay
	var vig := TextureRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 1.05)
	var gg := Gradient.new()
	gg.set_color(0, Color(0, 0, 0, 0))
	gg.set_color(1, Color(0.05, 0.02, 0.12, 0.35))
	gt.gradient = gg
	vig.texture = gt
	bg_layer.add_child(vig)
	sel_box = Node2D.new()
	sel_box.z_index = 90
	sel_box.draw.connect(_draw_sel)
	add_child(sel_box)
	rebuild()

func rebuild() -> void:
	for id in ents:
		if is_instance_valid(ents[id]):
			ents[id].queue_free()
	ents.clear()
	if player and is_instance_valid(player):
		player.queue_free()
	player = null
	topdown = U.str_of(spec.get("meta", {}), "genre", "platformer") in ["topdown", "top-down", "shooter", "maze", "rpg"]
	apply_world(false)
	var es = spec.get("entities", {})
	if typeof(es) == TYPE_DICTIONARY:
		for id in es:
			if typeof(es[id]) == TYPE_DICTIONARY:
				_spawn(str(id), es[id])
	_spawn_player()
	if drone == null:
		drone = Drone.new()
		add_child(drone)
	drone.visible = not playing
	_recalc_bounds()
	if not playing:
		frame_all(false)

func _spawn(id: String, d: Dictionary):
	var e = Ent.new()
	add_child(e)
	e.setup(self, id, d)
	ents[id] = e
	return e

func _spawn_player() -> void:
	var pd = spec.get("player", {})
	if typeof(pd) != TYPE_DICTIONARY:
		pd = {}
	player = Player.new()
	add_child(player)
	player.setup(self, pd, spec.get("settings", {}) if typeof(spec.get("settings")) == TYPE_DICTIONARY else {})

func apply_world(animate: bool) -> void:
	var w = spec.get("world", {})
	if typeof(w) != TYPE_DICTIONARY:
		w = {}
	var c := U.col(w.get("background_color"), Color("#87ceeb"))
	if animate:
		create_tween().tween_property(bg_color, "color", c, 0.6)
	else:
		bg_color.color = c
	var aid := U.str_of(w, "background_asset", "")
	var tex = main.assets.get_res(aid) if aid != "" else null
	if tex is Texture2D:
		if bg_tex.texture != tex:
			bg_tex.texture = tex
			if animate:
				bg_tex.modulate.a = 0.0
				create_tween().tween_property(bg_tex, "modulate:a", 1.0, 0.8)
	else:
		bg_tex.texture = null
	# slightly desaturate/dim the backdrop so foreground reads clearly
	bg_tex.self_modulate = Color(0.92, 0.92, 0.96)
	_apply_ambient(U.str_of(w, "ambient", ""))
	for id in ents:
		if is_instance_valid(ents[id]) and ents[id].kind == "platform":
			ents[id].refresh_asset(false)

## Screen-space ambient particles (leaves, snow, …) drawn between background and level.
func _apply_ambient(k: String) -> void:
	if k == ambient_kind:
		return
	ambient_kind = k
	if ambient and is_instance_valid(ambient):
		ambient.queue_free()
	ambient = FX.ambient2d(k, get_viewport_rect().size)
	if ambient:
		bg_layer.add_child(ambient)

func _recalc_bounds() -> void:
	var r := Rect2()
	var first := true
	for id in ents:
		var e = ents[id]
		if not is_instance_valid(e):
			continue
		var er: Rect2 = e.world_rect()
		if first:
			r = er
			first = false
		else:
			r = r.merge(er)
	if player:
		var pr := Rect2(player.position - player.size * 0.5, player.size)
		r = pr if first else r.merge(pr)
	bounds = r.grow(160)
	kill_y = bounds.end.y + 500.0
	goal_x = NAN
	for id in ents:
		var e = ents[id]
		if is_instance_valid(e) and e.kind == "goal":
			goal_x = e.position.x
	if player:
		start_x = player.spawn.x

## 0..1 horizontal progress from spawn to goal, or -1 when there is no goal / top-down.
func progress() -> float:
	if topdown or is_nan(goal_x) or player == null or absf(goal_x - start_x) < 300.0:
		return -1.0
	return clampf((player.global_position.x - start_x) / (goal_x - start_x), 0.0, 1.0)

func frame_all(animate := true) -> void:
	_recalc_bounds()
	var vs := get_viewport_rect().size
	var z := minf(vs.x / maxf(bounds.size.x, 400.0), vs.y / maxf(bounds.size.y, 300.0))
	z = clampf(z, 0.25, 1.2)
	cam_target = bounds.get_center()
	cam_zoom_target = z
	if not animate:
		cam.position = cam_target
		cam.zoom = Vector2(z, z)
		cam.reset_smoothing()

func _process(delta: float) -> void:
	if playing and player and is_instance_valid(player):
		var vs := get_viewport_rect().size
		var z := float(U.num(spec.get("settings", {}), "camera_zoom", 1.0))
		cam.zoom = cam.zoom.lerp(Vector2(z, z), 0.1)
		var target: Vector2
		if topdown:
			target = player.global_position + player.velocity * 0.15
		else:
			# smoothed horizontal look-ahead + vertical deadzone (only follow big height changes,
			# and always when falling) so jumping doesn't make the camera bob
			look_x = lerpf(look_x, player.velocity.x * CAM_LOOK_AHEAD, minf(1.0, delta * CAM_LOOK_SMOOTH))
			var py: float = player.global_position.y
			if player.is_on_floor() or py > cam_y + CAM_Y_DEADZONE or py < cam_y - CAM_Y_DEADZONE * 2.0:
				cam_y = lerpf(cam_y, py - 40.0, minf(1.0, delta * CAM_Y_SMOOTH))
			target = Vector2(player.global_position.x + look_x, cam_y)
		var half := vs / cam.zoom * 0.5
		if bounds.size.x > half.x * 2.0:
			target.x = clampf(target.x, bounds.position.x + half.x, bounds.end.x - half.x)
		if bounds.size.y > half.y * 2.0:
			target.y = clampf(target.y, bounds.position.y + half.y, bounds.end.y + 200.0 - half.y)
		cam.position = target
		_parallax(cam.get_screen_center_position())
	elif not playing:
		cam.position = cam.position.lerp(cam_target, minf(1.0, delta * 4.0))
		cam.zoom = cam.zoom.lerp(Vector2(cam_zoom_target, cam_zoom_target), minf(1.0, delta * 4.0))
	sel_box.queue_redraw()

func _parallax(center: Vector2) -> void:
	if bg_tex.texture == null:
		return
	var vs := get_viewport_rect().size
	var span := maxf(bounds.size.x, 1.0)
	var k := clampf((center.x - bounds.position.x) / span, 0.0, 1.0) - 0.5
	bg_tex.position = Vector2(-k * vs.x * PARALLAX * 2.0 - vs.x * PARALLAX, -vs.y * PARALLAX * 0.5)
	bg_tex.size = vs * (1.0 + PARALLAX * 2.0)

# ---------- build ops (edit mode, animated) ----------

func op_entity(id: String, d: Dictionary, dur: float) -> void:
	var existed: bool = ents.has(id) and is_instance_valid(ents[id])
	var target := Ent.to_godot(U.v2(d.get("position"), Vector2.ZERO))
	await _drone_go(target, dur)
	if existed:
		var e = ents[id]
		var old_pos: Vector2 = e.position
		var old_size: Vector2 = e.size
		e.apply(d)
		var new_pos: Vector2 = e.position
		e.position = old_pos
		var tw := create_tween()
		tw.tween_property(e, "position", new_pos, dur * 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		if old_size != e.size:
			e.visual.scale = old_size / e.size
			create_tween().tween_property(e.visual, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			_wiggle(e.visual)
		drone.beam(e.world_rect())
		main.sfx("whoosh", -6.0)
	else:
		var e2 = _spawn(id, d)
		drone.beam(e2.world_rect())
		e2.visual.scale = Vector2(0.05, 0.05)
		var tw2 := create_tween()
		tw2.tween_property(e2.visual, "scale", Vector2.ONE, dur * 1.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		FX.burst2d(self, target, U.col(d.get("color"), U.default_color(e2.kind)), 16, 220)
		FX.float_text2d(self, target - Vector2(0, e2.size.y * 0.5), "+ " + U.str_of(d, "name", U.kind_label(e2.kind)), Color("#ffffff"), 22)
		main.sfx("pop", -4.0)
	_recalc_bounds()
	await get_tree().create_timer(dur * 0.6).timeout

func op_remove(id: String, dur: float) -> void:
	if not ents.has(id):
		return
	var e = ents[id]
	ents.erase(id)
	if not is_instance_valid(e):
		return
	await _drone_go(e.position, dur)
	drone.beam(e.world_rect())
	FX.burst2d(self, e.position, Color(0.8, 0.8, 0.8), 18, 160)
	main.sfx("whoosh", -4.0)
	var tw := create_tween()
	tw.tween_property(e.visual, "scale", Vector2(0.01, 0.01), dur * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(e.queue_free)
	if selected == id:
		selected = ""
	await get_tree().create_timer(dur * 0.6).timeout

func op_player(d: Dictionary, dur: float) -> void:
	var p := Ent.to_godot(U.v2(d.get("position"), Vector2(0, 80)))
	await _drone_go(p, dur)
	if player and is_instance_valid(player):
		player.setup(self, d, spec.get("settings", {}) if typeof(spec.get("settings")) == TYPE_DICTIONARY else {})
		drone.beam(Rect2(player.position - player.size * 0.5, player.size))
		player.visual.scale = Vector2(0.05, 0.05)
		create_tween().tween_property(player.visual, "scale", Vector2.ONE, dur * 1.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		FX.float_text2d(self, p - Vector2(0, 60), "主角", Color("#4cc9f0"), 24)
		main.sfx("sparkle", -4.0)
	await get_tree().create_timer(dur * 0.5).timeout

func op_world(dur: float) -> void:
	apply_world(true)
	main.sfx("sparkle", -8.0)
	await get_tree().create_timer(dur * 0.5).timeout

func refresh_assets(asset_id: String) -> void:
	for id in ents:
		var e = ents[id]
		if is_instance_valid(e) and e.asset_id == asset_id:
			e.refresh_asset(not playing)
	if player and is_instance_valid(player) and U.str_of(player.data, "asset", "") == asset_id:
		player.refresh_asset(not playing)
	var w = spec.get("world", {})
	if typeof(w) == TYPE_DICTIONARY and U.str_of(w, "background_asset", "") == asset_id:
		apply_world(true)

func focus(id: String) -> void:
	if ents.has(id) and is_instance_valid(ents[id]):
		var e = ents[id]
		await _drone_go(e.position, 0.4)
		_wiggle(e.visual)

func drone_say(text: String) -> void:
	if drone:
		drone.say(text)

func _drone_go(target: Vector2, dur: float) -> void:
	if drone == null:
		return
	drone.visible = true
	cam_target = cam_target.lerp(target, 0.6)
	var vs := get_viewport_rect().size
	var half := vs / maxf(cam_zoom_target, 0.1) * 0.5
	if absf(target.x - cam_target.x) > half.x * 0.8 or absf(target.y - cam_target.y) > half.y * 0.8:
		cam_target = target
	var tw = drone.fly_to(target, dur * 0.6)
	await tw.finished

func _wiggle(n: Node2D) -> void:
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector2(1.15, 0.9), 0.08)
	tw.tween_property(n, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

# ---------- gameplay ----------

func start_play() -> void:
	playing = true
	if drone:
		drone.visible = false
		drone.say("")
	selected = ""
	cam.position_smoothing_speed = 7.0
	if player:
		cam_y = player.global_position.y - 40.0
		look_x = 0.0
		cam.position = Vector2(player.global_position.x, cam_y)
		cam.reset_smoothing()

func collect(e, value: int) -> void:
	main.add_score(value)
	main.sfx("coin")
	FX.ring2d(self, e.global_position, U.col(e.data.get("color"), Color("#ffd23f")).lightened(0.3), e.size.x * 0.9, 0.25)
	FX.burst2d(self, e.global_position, U.col(e.data.get("color"), Color("#ffd23f")), 10, 200)
	FX.float_text2d(self, e.global_position, "+%d" % value, Color("#ffd23f"))
	main.on_collect()

func enemy_stomped(e, value: int) -> void:
	main.sfx("stomp")
	main.hit_stop(0.06)
	main.shake(5.0)
	FX.ring2d(self, e.global_position + Vector2(0, e.size.y * 0.3), Color.WHITE, e.size.x * 0.9)
	main.add_score(value)
	FX.burst2d(self, e.global_position, U.col(e.data.get("color"), Color("#ef476f")), 16, 240)
	FX.float_text2d(self, e.global_position - Vector2(0, e.size.y * 0.5), "+%d" % value, Color("#ff8fab"))
	main.on_defeat()

func reach_checkpoint(e) -> void:
	if player:
		player.set_checkpoint(e.global_position + Vector2(0, e.size.y * 0.5 - player.size.y * 0.5 - 4.0))
	FX.ring2d(self, e.global_position, Color("#4cc9f0"), 90.0, 0.5)
	FX.sparkle2d(self, e.global_position, e.size.x)
	main.on_checkpoint()

func enemy_defeated(e, value: int) -> void:
	main.add_score(value)
	main.sfx("pop")
	FX.burst2d(self, e.global_position, U.col(e.data.get("color"), Color("#ef476f")), 20, 260)
	FX.float_text2d(self, e.global_position, "+%d" % value, Color("#ff8fab"))
	main.on_defeat()

func reach_goal(_e) -> void:
	main.on_goal()

func player_hurt() -> void:
	main.sfx("hurt")
	main.shake(12.0)
	FX.burst2d(self, player.global_position, Color("#ff4d6d"), 14, 260)
	main.lose_life()

func player_fell() -> void:
	main.sfx("hurt")
	main.shake(8.0)
	if main.lose_life():
		player.respawn()

func spawn_projectile(from: Vector2, vel: Vector2, col: Color, friendly := false) -> void:
	var a := Area2D.new()
	a.collision_layer = 8
	a.collision_mask = 2 if not friendly else 4
	a.monitorable = true
	a.monitoring = true
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 9
	cs.shape = c
	a.add_child(cs)
	var dot := Node2D.new()
	dot.draw.connect(func(): dot.draw_circle(Vector2.ZERO, 10, col); dot.draw_circle(Vector2.ZERO, 5, Color.WHITE))
	a.add_child(dot)
	a.position = from
	a.z_index = 30
	add_child(a)
	var life := [0.0]
	a.set_physics_process(true)
	var tick := func(delta):
		a.position += vel * delta
		life[0] += delta
		if life[0] > 3.0:
			a.queue_free()
	get_tree().physics_frame.connect(func(): if is_instance_valid(a): tick.call(get_physics_process_delta_time()), CONNECT_REFERENCE_COUNTED)
	if friendly:
		a.area_entered.connect(func(o):
			var en = o.get_meta("ent") if o.has_meta("ent") else null
			if en and en.kind == "enemy" and en.alive:
				en.alive = false
				enemy_defeated(en, int(U.num(en.data, "value", 5)))
				en.queue_free()
				a.queue_free())
	else:
		a.body_entered.connect(func(b):
			if b == player:
				player.hurt(a.global_position)
				a.queue_free())

# ---------- edit-mode interaction (select / drag) ----------

func _unhandled_input(ev: InputEvent) -> void:
	if playing:
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var f := 1.1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.9
			cam_zoom_target = clampf(cam_zoom_target * f, 0.15, 2.5)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var wp := get_global_mouse_position()
			if mb.pressed:
				var hit := _pick(wp)
				selected = hit
				drag_moved = false
				if hit != "":
					dragging = hit
					drag_off = ents[hit].position - wp if hit != "__player" else player.position - wp
				else:
					dragging = "__pan"
					drag_off = wp
				main.emit_event({"type": "select", "id": hit})
			else:
				if dragging != "" and dragging != "__pan" and drag_moved:
					var pos: Vector2 = (ents[dragging].position if dragging != "__player" else player.position)
					main.on_dragged(dragging, [snappedf(pos.x, 1.0), snappedf(-pos.y, 1.0)])
				dragging = ""
	elif ev is InputEventMouseMotion and dragging != "":
		var wp2 := get_global_mouse_position()
		if dragging == "__pan":
			cam_target -= (ev as InputEventMouseMotion).relative / cam.zoom
			cam.position = cam_target
			return
		drag_moved = true
		var np := wp2 + drag_off
		np = np.snapped(Vector2(4, 4))
		if dragging == "__player":
			player.position = np
		elif ents.has(dragging):
			ents[dragging].position = np
			ents[dragging].home = np

func _pick(wp: Vector2) -> String:
	if player and Rect2(player.position - player.size * 0.5, player.size).has_point(wp):
		return "__player"
	var best := ""
	var best_area := INF
	var best_z := -999
	for id in ents:
		var e = ents[id]
		if not is_instance_valid(e):
			continue
		var r: Rect2 = e.world_rect()
		if r.has_point(wp):
			var area := r.size.x * r.size.y
			if e.z_index > best_z or (e.z_index == best_z and area < best_area):
				best = id
				best_area = area
				best_z = e.z_index
	return best

func _draw_sel() -> void:
	if playing or selected == "":
		return
	var r := Rect2()
	if selected == "__player" and player:
		r = Rect2(player.position - player.size * 0.5, player.size)
	elif ents.has(selected) and is_instance_valid(ents[selected]):
		r = ents[selected].world_rect()
	else:
		return
	var tt := Time.get_ticks_msec() / 1000.0
	sel_box.draw_rect(r.grow(6), Color(1, 0.85, 0.2, 0.9), false, 3.0)
	for c in [r.grow(6).position, Vector2(r.grow(6).end.x, r.grow(6).position.y), r.grow(6).end, Vector2(r.grow(6).position.x, r.grow(6).end.y)]:
		sel_box.draw_circle(c, 6 + sin(tt * 6.0) * 1.5, Color(1, 0.85, 0.2))
