extends Node
## Global access point (autoload "G").

const SH_PAPER := preload("res://shaders/paper.gdshader")
const SH_PAPER_PX := preload("res://shaders/paper_px.gdshader")
const SH_ADD := preload("res://shaders/fx_add.gdshader")

var autostart := false
var bot := false
var bot_speed := 1.0
var shots := false
var all_weapons := false
var unlock_all := false
var map_id := 0
var ui_shot := ""
## Mobile / web: low quality tier (no glow, fewer particles, smaller crowd cap).
var low := false
## True once the touch layer is active (shows touch hints instead of keys).
var touch := false
## Self-test runs on a throwaway save so real progress is never touched.
var test_mode := false
var save := {"gold": 0, "meta": {}, "best": {}, "spent": 0}
var game = null
var player = null
var fx = null
var sfx = null
var hud = null
var cam: Camera3D = null
var font: Font
var to_cam := Vector3(0, 0.78, 0.62).normalized()
var cam_basis := Basis()
var flat_basis := Basis(Vector3.RIGHT, Vector3(0, 0, -1), Vector3.UP)
var _mats: Dictionary = {}
var _tex: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	if args.has("--bot"):
		bot = true
		autostart = true
	for a in args:
		if a == "--all":
			all_weapons = true
		if a == "--shots":
			shots = true
		if a.begins_with("--speed="):
			bot_speed = float(a.substr(8))
		if a.begins_with("--map="):
			map_id = int(a.substr(6))
		if a.begins_with("--ui="):
			ui_shot = a.substr(5)
		if a == "--unlock":
			unlock_all = true
	low = OS.has_feature("web") or OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--low")
	touch = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") or (OS.has_feature("web") and DisplayServer.is_touchscreen_available())
	load_save()
	cam_basis = Basis(Vector3.RIGHT, to_cam.cross(Vector3.RIGHT).normalized(), to_cam)
	# Web builds have no system CJK fonts: use the platform's bundled font, slightly emboldened.
	var ff = load("res://addons/ugc/font.ttf") if ResourceLoader.exists("res://addons/ugc/font.ttf") else null
	if ff is Font:
		var fv := FontVariation.new()
		var fb = load("res://assets/fallback.ttf")
		if fb is Font:
			ff.fallbacks = [fb]
		fv.base_font = ff
		fv.variation_embolden = 0.6
		font = fv
	else:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "PingFang SC", "Noto Sans CJK SC", "Source Han Sans SC", "sans-serif"])
		sf.font_weight = 700
		font = sf
	_act("move_left", [KEY_A, KEY_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_act("move_right", [KEY_D, KEY_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_act("move_up", [KEY_W, KEY_UP], JOY_AXIS_LEFT_Y, -1.0)
	_act("move_down", [KEY_S, KEY_DOWN], JOY_AXIS_LEFT_Y, 1.0)
	_act("pause", [KEY_ESCAPE, KEY_P])


func _act(action: String, keys: Array, axis: int = -1, axis_val: float = 0.0) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	if axis >= 0:
		var j := InputEventJoypadMotion.new()
		j.axis = axis
		j.axis_value = axis_val
		InputMap.action_add_event(action, j)


func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path)
	return _tex[path]


## kind: 0 = paper (smooth), 1 = pixel (nearest), 2 = additive glow
## Materials are shared per texture/kind until a sprite needs its own tint / energy / flash / flip (see sp()).
## Regular uniforms are used instead of instance uniforms: WebGL2 (GL Compatibility) renders
## instance-uniform sprites black, so per-sprite values live on a lazily duplicated material.
func mat(t: Texture2D, kind: int = 0) -> ShaderMaterial:
	var key := "%s#%d" % [t.resource_path, kind]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = [SH_PAPER, SH_PAPER_PX, SH_ADD][kind]
	m.set_shader_parameter("tex", t)
	_mats[key] = m
	return m


## Kept for call-site compatibility: shared materials already start at the default values.
func init_inst(_g: GeometryInstance3D) -> void:
	pass


## Set a per-sprite shader value (tint / energy / flash / flip). The first call gives the sprite its own
## copy of the shared material so other sprites are unaffected.
func sp(g: GeometryInstance3D, k: StringName, v) -> void:
	var m := g.material_override as ShaderMaterial
	if m == null:
		return
	if not g.has_meta(&"_own_mat"):
		m = m.duplicate() as ShaderMaterial
		g.material_override = m
		g.set_meta(&"_own_mat", true)
	m.set_shader_parameter(k, v)


func sprite(path: String, psize: float, kind: int = 0, feet: bool = true) -> Sprite3D:
	var t := tex(path)
	var s := Sprite3D.new()
	s.texture = t
	s.pixel_size = psize
	s.material_override = mat(t, kind)
	init_inst(s)
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if feet:
		s.offset = Vector2(0, t.get_height() * 0.5)
	return s


func shadow(diam: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex("res://assets/fx/shadow.png")
	s.pixel_size = diam / 128.0
	s.modulate = Color(0.0, 0.04, 0.0, 0.8)
	s.rotation.x = -PI * 0.5
	s.position.y = 0.03
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return s


## Basis whose +Y points along dir and whose plane faces the camera as much as possible.
func face_basis(dir: Vector3) -> Basis:
	var y := dir.normalized()
	if y.length_squared() < 0.0001:
		y = Vector3.UP
	var x := y.cross(to_cam)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## Basis lying flat on the ground with +Y pointing along dir.
func ground_basis(dir: Vector3) -> Basis:
	var y := Vector3(dir.x, 0.0, dir.z).normalized()
	if y.length_squared() < 0.0001:
		y = Vector3(0, 0, -1)
	var x := y.cross(Vector3.UP).normalized()
	return Basis(x, y, Vector3.UP)


func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# ------------------------------------------------------------------ save / meta
func _save_path() -> String:
	return "user://save_bot.json" if bot else "user://save.json"


func load_save() -> void:
	var f: FileAccess = FileAccess.open("user://save_bot.json", FileAccess.READ) if bot else FileAccess.open("user://save.json", FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		for k in d:
			save[k] = d[k]


func write_save() -> void:
	if test_mode:
		return
	# Web saves live in IndexedDB (user://); a direct write is atomic enough there.
	var f: FileAccess = FileAccess.open("user://save_bot.json", FileAccess.WRITE) if bot else FileAccess.open("user://save.json", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(save, "\t"))
	f.close()


func meta(id: String) -> int:
	return int(save.meta.get(id, 0))


func best_time(map: int) -> float:
	return float(save.best.get(str(map), 0.0))


func map_unlocked(i: int) -> bool:
	var Data = load("res://scripts/data.gd")
	var u: int = Data.MAPS[i].unlock
	return unlock_all or u < 0 or best_time(u) >= Data.UNLOCK_TIME
