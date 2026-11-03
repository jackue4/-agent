extends Node
## Global game state, juice helpers (hitstop / shake / impact frames) and spawning helpers.

const INK := Color(0.07, 0.05, 0.09)
const PAPER := Color(0.97, 0.93, 0.83)
const WHITE := Color(1, 1, 1)
const RED := Color(0.93, 0.17, 0.2)
const YELLOW := Color(1.0, 0.85, 0.14)
const BLUE := Color(0.18, 0.55, 0.98)
const ORANGE := Color(1.0, 0.55, 0.12)
const PURPLE := Color(0.6, 0.35, 0.95)
const GREEN := Color(0.3, 0.85, 0.35)
const ARENA := Rect2(-1500, -1000, 3000, 2000)
const SFX_WORDS := ["POW!", "BAM!", "WHAM!", "SMASH!", "KRAK!", "BONK!", "THWACK!", "KA-BOOM!", "CRUNCH!", "SPLAT!", "BOOM!", "ZOK!"]
var MAX_SHARDS := 280
const CELL := 80.0

signal enemy_died(enemy)

var main: Node2D = null
var entities: Node2D = null
var fx: Node2D = null
var decals: Decals = null
var particles: Debris = null
var camera: Camera2D = null
var post_mat: ShaderMaterial = null
var player: Player = null
var boss: Enemy = null
var enemies: Array = []
var props: Array = []
var shards: Array = []
var pickup_count := 0
var game_time := 0.0
var kills := 0
var combo := 0
var best_combo := 0
var combo_timer := 0.0
var skip_title := false
var banner_text := ""
var banner_t := 0.0
var font: Font
var font_cn: Font
## Mobile/web tier: no full-screen post pass, fewer shards/particles/decals.
var low := false
## True once the touch layer is active (mobile browser or first real touch).
var touch := false
var trauma := 0.0
var zoom_kick := 0.0
var grid := {}
var _hitstop_end := 0
var _impact_end := 0
var _last_ms := 0
var prof := {}
var view_rect := Rect2()
# run modifiers (maps / curses / protocol)
var wind := Vector2.ZERO
var ice_floor := false
var env_slow := 1.0
var xp_mult := 1.0
var no_hearts := false
var dmg_in_mult := 1.0
var blizzard := false
var heal_mult := 1.0
var goto_hub := false
var run_cfg := {}
# player settings (Meta.apply_settings)
var shake_k := 1.0
var dmg_numbers := true
var hitstop_on := true
var show_fps := false
var auto_low := false


func pf(key: String, t0: int) -> void:
	prof[key] = int(prof.get(key, 0)) + Time.get_ticks_usec() - t0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The platform ships one CJK font (addons/ugc/font.ttf); system fonts do not exist on the web.
	var base: Font = load("res://addons/ugc/font.ttf") if ResourceLoader.exists("res://addons/ugc/font.ttf") else ThemeDB.fallback_font
	var bold := FontVariation.new()
	bold.base_font = base
	bold.variation_embolden = 0.9
	font = bold
	var cn := FontVariation.new()
	cn.base_font = base
	cn.variation_embolden = 0.5
	font_cn = cn
	low = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	auto_low = low
	if low:
		MAX_SHARDS = 150
	_setup_input()
	_last_ms = Time.get_ticks_msec()


func reset() -> void:
	enemies.clear()
	props.clear()
	shards.clear()
	grid.clear()
	pickup_count = 0
	game_time = 0.0
	kills = 0
	combo = 0
	best_combo = 0
	combo_timer = 0.0
	trauma = 0.0
	zoom_kick = 0.0
	banner_text = ""
	banner_t = 0.0
	boss = null
	player = null
	wind = Vector2.ZERO
	ice_floor = false
	env_slow = 1.0
	xp_mult = 1.0
	no_hearts = false
	dmg_in_mult = 1.0
	blizzard = false
	heal_mult = 1.0
	Engine.time_scale = 1.0
	_hitstop_end = 0
	_impact_end = 0


func _setup_input() -> void:
	_add_keys("move_left", [KEY_A, KEY_LEFT])
	_add_keys("move_right", [KEY_D, KEY_RIGHT])
	_add_keys("move_up", [KEY_W, KEY_UP])
	_add_keys("move_down", [KEY_S, KEY_DOWN])
	_add_keys("attack", [KEY_J])
	_add_mouse("attack", MOUSE_BUTTON_LEFT)
	_add_keys("heavy", [KEY_K])
	_add_mouse("heavy", MOUSE_BUTTON_RIGHT)
	_add_keys("dash", [KEY_SPACE, KEY_SHIFT, KEY_L])


func _add_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _add_mouse(action: String, btn: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = btn
	InputMap.action_add_event(action, ev)


func _process(_d: float) -> void:
	var now := Time.get_ticks_msec()
	var rd := minf((now - _last_ms) / 1000.0, 0.1)
	_last_ms = now
	if Engine.time_scale < 1.0 and now >= _hitstop_end:
		Engine.time_scale = 1.0
	if post_mat != null:
		post_mat.set_shader_parameter("flash", 1.0 if now < _impact_end else 0.0)
	banner_t = maxf(banner_t - rd, 0.0)
	zoom_kick = maxf(zoom_kick - rd * 0.5, 0.0)
	if camera != null and is_instance_valid(camera):
		var vs := camera.get_viewport_rect().size / camera.zoom
		view_rect = Rect2(camera.get_screen_center_position() - vs * 0.5, vs).grow(220)
		trauma = maxf(trauma - rd * 1.7, 0.0)
		var s := trauma * trauma
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 30.0 * s
		camera.rotation = randf_range(-1, 1) * 0.04 * s


# ---------------------------------------------------------------- juice
func on_screen(p: Vector2) -> bool:
	return view_rect.size == Vector2.ZERO or view_rect.has_point(p)


func hitstop(sec: float) -> void:
	if not hitstop_on:
		return
	var now := Time.get_ticks_msec()
	_hitstop_end = maxi(_hitstop_end, now + int(minf(sec, 0.3) * 1000.0))
	Engine.time_scale = 0.03


func slowmo(scale: float, sec: float) -> void:
	_hitstop_end = maxi(_hitstop_end, Time.get_ticks_msec() + int(sec * 1000.0))
	Engine.time_scale = scale


func shake(amount: float) -> void:
	trauma = minf(trauma + amount * shake_k, 1.0)


func impact_frame(sec: float) -> void:
	_impact_end = maxi(_impact_end, Time.get_ticks_msec() + int(sec * 1000.0))


func kick_zoom(amount: float) -> void:
	zoom_kick = minf(zoom_kick + amount, 0.12)


func banner(text: String, sec: float = 2.5) -> void:
	banner_text = text
	banner_t = sec


func register_hit() -> void:
	combo += 1
	combo_timer = 2.2
	if combo > best_combo:
		best_combo = combo


# ---------------------------------------------------------------- spatial queries
func rebuild_grid() -> void:
	grid.clear()
	for e in enemies:
		var p: Vector2 = e.position
		var k := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
		if grid.has(k):
			grid[k].append(e)
		else:
			grid[k] = [e]


func query(p: Vector2, r: float) -> Array:
	var out := []
	var x0 := floori((p.x - r - 90.0) / CELL)
	var x1 := floori((p.x + r + 90.0) / CELL)
	var y0 := floori((p.y - r - 90.0) / CELL)
	var y1 := floori((p.y + r + 90.0) / CELL)
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			var k := Vector2i(x, y)
			if not grid.has(k):
				continue
			for e in grid[k]:
				if e.dead:
					continue
				var ep: Vector2 = e.position
				if ep.distance_to(p) <= r + float(e.radius):
					out.append(e)
	return out


func hittables_in(p: Vector2, r: float) -> Array:
	var out := query(p, r)
	for pr in props:
		if not pr.dead and (pr.position as Vector2).distance_to(p) <= r + float(pr.radius):
			out.append(pr)
	return out


func nearest_enemy(p: Vector2, max_d: float, exclude: Dictionary = {}):
	var best = null
	var bd := max_d
	for e in enemies:
		if e.dead or exclude.has(e.get_instance_id()):
			continue
		var d: float = (e.position as Vector2).distance_to(p)
		if d < bd:
			bd = d
			best = e
	return best


func densest_point(origin: Vector2, rng: float):
	var cand := []
	for e in enemies:
		if not e.dead and (e.position as Vector2).distance_to(origin) < rng:
			cand.append(e)
	if cand.is_empty():
		return null
	var best: Vector2 = cand[0].position
	var best_n := 0
	for i in mini(10, cand.size()):
		var e = cand.pick_random()
		var n := query(e.position, 130.0).size()
		if n > best_n:
			best_n = n
			best = e.position
	return best


# ---------------------------------------------------------------- fx spawning
func spawn_text(pos: Vector2, text: String, col: Color = YELLOW, size: int = 34, burst: bool = true, life: float = 0.75) -> void:
	if fx == null:
		return
	if fx.get_child_count() > 160 and not burst:
		return
	var t := FxText.new()
	t.position = pos
	t.text = text
	t.col = col
	t.size = size
	t.burst = burst
	t.life = life
	fx.add_child(t)


func damage_number(pos: Vector2, amount: float, crit: bool) -> void:
	if fx == null or fx.get_child_count() > 140 or not dmg_numbers:
		return
	var t := FxText.new()
	t.position = pos
	t.text = str(int(round(amount))) + ("!" if crit else "")
	t.col = YELLOW if crit else WHITE
	t.size = 34 if crit else 22
	t.burst = false
	t.life = 0.6
	t.vel = Vector2(randf_range(-60, 60), -180)
	fx.add_child(t)


func spawn_slash(pos: Vector2, dir: Vector2, radius: float, arc: float, kind: String = "", col: Color = WHITE) -> void:
	if fx == null:
		return
	var s := FxSlash.new()
	s.position = pos
	s.dir = dir
	s.radius = radius
	s.arc = arc
	s.kind = kind
	s.col = col
	fx.add_child(s)


func spawn_ring(pos: Vector2, r0: float, r1: float, col: Color = WHITE, life: float = 0.3, width: float = 12.0, kind: String = "") -> void:
	if fx == null:
		return
	var r := FxRing.new()
	r.position = pos
	r.r0 = r0
	r.r1 = r1
	r.col = col
	r.life = life
	r.width = width
	r.kind = kind
	fx.add_child(r)


func spawn_bolt(a: Vector2, b: Vector2, col: Color = YELLOW) -> void:
	if fx == null:
		return
	var bo := FxBolt.new()
	bo.a = a
	bo.b = b
	bo.col = col
	fx.add_child(bo)


func spawn_ghost(pos: Vector2, pose: Dictionary, facing: float) -> void:
	if fx == null:
		return
	var gh := FxGhost.new()
	gh.position = pos
	gh.pose = pose
	gh.facing = facing
	entities.add_child(gh)


# ---------------------------------------------------------------- drops
func drop_xp(pos: Vector2, total: int) -> void:
	if pickup_count > 140 and player != null:
		player.add_xp(total)
		return
	var remain := total
	while remain > 0:
		var v := 1
		if remain >= 30:
			v = remain
		elif remain >= 10:
			v = 10
		elif remain >= 3:
			v = 3
		remain -= v
		_spawn_pickup(pos, "xp", v)


func drop_heart(pos: Vector2) -> void:
	_spawn_pickup(pos, "heart", 25)


func _spawn_pickup(pos: Vector2, kind: String, v: int) -> void:
	var p := Pickup.new()
	p.kind = kind
	p.value = v
	p.position = pos
	p.vel = Vector2.from_angle(randf() * TAU) * randf_range(60, 220)
	p.vz = randf_range(200, 420)
	entities.add_child.call_deferred(p)


# ---------------------------------------------------------------- shattering
var _shard_tex: Texture2D = null
var _shard_uv := Transform2D.IDENTITY


## Shatter a sprite: pieces carry UVs into the texture so the real art flies apart.
func shatter_sprite(id: String, entity_xf: Transform2D, radius: float, facing: float, col: Color, dir: Vector2, force: float, ground_y: float, pieces: int = 8) -> void:
	var d := Art.shatter_data(id, entity_xf, radius, facing)
	_shard_tex = Art.tex(id)
	_shard_uv = d[1]
	shatter(d[0], col, dir, force, ground_y, pieces)
	_shard_tex = null


func shatter(poly: PackedVector2Array, col: Color, dir: Vector2, force: float, ground_y: float, pieces: int = 8) -> void:
	if entities == null or poly.size() < 3:
		return
	var c := _centroid(poly)
	var rad := 0.0
	for v in poly:
		rad = maxf(rad, v.distance_to(c))
	var center := c + Vector2(randf_range(-0.25, 0.25), randf_range(-0.25, 0.25)) * rad
	var cuts: Array[float] = []
	var base := randf() * TAU
	for i in pieces:
		cuts.append(base + TAU * (float(i) + randf_range(-0.3, 0.3)) / float(pieces))
	cuts.sort()
	var made := 0
	for i in pieces:
		var a0: float = cuts[i]
		var a1: float = cuts[i + 1] if i < pieces - 1 else cuts[0] + TAU
		var wedge := PackedVector2Array([
			center,
			center + Vector2.from_angle(a0) * 4000.0,
			center + Vector2.from_angle((a0 + a1) * 0.5) * 4000.0,
			center + Vector2.from_angle(a1) * 4000.0,
		])
		var res := Geometry2D.intersect_polygons(poly, wedge)
		for piece in res:
			if piece.size() < 3:
				continue
			var ar := absf(_area(piece))
			if ar < 25.0:
				continue
			if ar > 900.0 and randf() < 0.75:
				for sub in _split(piece):
					var sp: PackedVector2Array = sub
					if sp.size() >= 3 and absf(_area(sp)) > 25.0:
						_spawn_shard(sp, col, dir, force, ground_y, center)
						made += 1
			else:
				_spawn_shard(piece, col, dir, force, ground_y, center)
				made += 1
			if made > pieces * 2 + 4:
				return


func _split(piece: PackedVector2Array) -> Array:
	var c := _centroid(piece)
	var n := Vector2.from_angle(randf() * PI)
	var t := n.orthogonal()
	var half := PackedVector2Array([c + t * 3000.0, c + t * 3000.0 + n * 3000.0, c - t * 3000.0 + n * 3000.0, c - t * 3000.0])
	var out: Array = []
	out.append_array(Geometry2D.intersect_polygons(piece, half))
	out.append_array(Geometry2D.clip_polygons(piece, half))
	return out


func _spawn_shard(piece: PackedVector2Array, col: Color, dir: Vector2, force: float, ground_y: float, center: Vector2) -> void:
	var sc := _centroid(piece)
	var local := PackedVector2Array()
	for p in piece:
		local.append(p - sc)
	var s := Shard.new()
	if _shard_tex != null:
		s.texture = _shard_tex
		var uv := PackedVector2Array()
		for p in piece:
			uv.append(_shard_uv * p)
		s.uvs = uv
	var tint := randf()
	if tint < 0.25:
		s.col = col.darkened(0.25)
	elif tint < 0.45:
		s.col = col.lightened(0.2)
	else:
		s.col = col
	s.poly = local
	s.position = Vector2(sc.x, ground_y + randf_range(-8.0, 8.0))
	s.z = maxf(ground_y - sc.y, 0.0)
	var out := (sc - center).normalized()
	var f := clampf(force / 900.0, 0.6, 1.8)
	var d := dir.normalized() if dir.length() > 0.01 else Vector2.ZERO
	s.linear_velocity = d * force * randf_range(0.35, 1.05) + out * randf_range(140.0, 420.0) * f
	s.angular_velocity = randf_range(-20.0, 20.0)
	s.vz = randf_range(260.0, 700.0) * f
	entities.add_child(s)
	shards.append(s)
	while shards.size() > MAX_SHARDS:
		var old = shards.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func push_shards(center: Vector2, radius: float, force: float) -> void:
	for s in shards:
		if not is_instance_valid(s):
			continue
		var d: Vector2 = s.position - center
		var l := d.length()
		if l < radius and l > 0.1:
			var k := 1.0 - l / radius
			s.linear_velocity += d / l * force * (0.5 + k)
			s.vz = maxf(s.vz, 180.0 + 300.0 * k)
			s.angular_velocity += randf_range(-12.0, 12.0)


func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / float(maxi(poly.size(), 1))


func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return a * 0.5