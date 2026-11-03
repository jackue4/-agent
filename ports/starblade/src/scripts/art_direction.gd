extends CanvasLayer
## Compatibility-friendly art pass behind HUD. Never changes gameplay speed/camera.
const POST = preload("res://assets/art_post.gdshader")
const CRT_OVERLAY = preload("res://assets/art_crt_overlay.gdshader")
var time_stop := 0.0
var rush := 0.0
var frozen := false
var _target_stop := 0.0
var _target_rush := 0.0
var _clock := 0.0
var _screen: ColorRect
var _material: ShaderMaterial
var _flash_left := 0.0
var _flash_duration := .14
var _flash_strength := .18
var _crt_armed := false
var _crt_entry_age := 1.0
var _crt_reduced := false
var _overlay_layer: CanvasLayer
var _overlay: ColorRect
var _overlay_material: ShaderMaterial
var _slam_age := 1.0
var _slam_uv := Vector2(.5,.5)
var _slam_reduced := false
var _kill_left := 0.0
var _kill_strength := 0.0
var _kill_cooldown := 0.0
var _warp_age := 2.0
var _warp_uv := Vector2(.5,.5)
var _warp_reduced := false
var flashlight := 0.0
var _target_flashlight := 0.0
var _light_uv := Vector2(.5,.5)
var _light_dir := Vector2(0,-1)
var _rush_uv := Vector2(.5,.5)
var _rush_freeze := 0.0
var _rush_freeze_left := 0.0
var _combo_heat := 0.0
var _target_combo_heat := 0.0
var _combo_color := Color(1,.72,.35)
const SAND_DURATION := 4.6
const SAND_GAPS := [18.0,22.0,16.0]
var _sand_enabled := false
var _sand_reduced := false
var _sand_wait := 7.0
var _sand_age := SAND_DURATION
var _sand_cycle := 0

## Desert weather has its own schedule and never consumes gameplay randomness.
func set_sand_weather(enabled: bool, reduced: bool = false) -> void:
	_sand_reduced = reduced
	if enabled != _sand_enabled:
		_sand_enabled = enabled
		_sand_wait = 7.0
		_sand_age = SAND_DURATION
		_sand_cycle = 0
	_push_parameters()

func _tick_sand(delta: float) -> void:
	if not _sand_enabled: return
	# Carry over frame time at boundaries so quiet gaps and gusts stay consistent.
	var remaining := delta
	while remaining > 0.0:
		if _sand_wait > 0.0:
			var elapsed := minf(remaining,_sand_wait)
			_sand_wait -= elapsed
			remaining -= elapsed
			if _sand_wait <= 0.0: _sand_age = 0.0
		else:
			var elapsed := minf(remaining,SAND_DURATION-_sand_age)
			_sand_age += elapsed
			remaining -= elapsed
			if _sand_age >= SAND_DURATION:
				_sand_wait = SAND_GAPS[_sand_cycle % SAND_GAPS.size()]
				_sand_cycle += 1

## Flashlight floor: the post pass keeps a cone ahead of the hero lit.
func set_flashlight(enabled: bool) -> void:
	_target_flashlight = 1.0 if enabled else 0.0

func set_light(screen_uv: Vector2, screen_dir: Vector2) -> void:
	if screen_uv.is_finite(): _light_uv = screen_uv
	if screen_dir.is_finite() and screen_dir.length_squared() > .0001: _light_dir = _light_dir.lerp(screen_dir.normalized(),.35).normalized()

func set_rush_center(screen_uv: Vector2) -> void:
	if screen_uv.is_finite(): _rush_uv = screen_uv.clamp(Vector2.ZERO,Vector2.ONE)

## Short blue-shifted hold frame for the rush entry (visual time-stop only).
func trigger_rush_freeze(duration: float = .16, reduced: bool = false) -> void:
	_rush_freeze_left = clampf(duration,.02,.4)
	_rush_freeze = .45 if reduced else 1.0
	_push_parameters()

func set_combo_heat(amount: float, color: Color = Color(1,.72,.35)) -> void:
	_target_combo_heat = clampf(amount,0,1)
	_combo_color = color

func trigger_slam(screen_uv: Vector2, reduced: bool = false) -> void:
	if not screen_uv.is_finite(): return
	_slam_uv = screen_uv.clamp(Vector2.ZERO,Vector2.ONE)
	_slam_age = 0.0
	_slam_reduced = reduced
	_push_parameters()

func trigger_kill(tier: int = 0, reduced: bool = false) -> void:
	# A chain kill is one accent, not a stack of full-screen flashes.
	if _kill_cooldown > 0.0: return
	_kill_strength = (.025+.015*clampi(tier,0,2))*(.4 if reduced else 1.0)
	_kill_left = .16
	_kill_cooldown = .12
	_push_parameters()

## Full-screen space ripple for blessing pickups; one front, never a loop.
func trigger_warp(screen_uv: Vector2, reduced: bool = false) -> void:
	if not screen_uv.is_finite(): return
	_warp_uv = screen_uv.clamp(Vector2.ZERO,Vector2.ONE)
	_warp_age = 0.0
	_warp_reduced = reduced
	_push_parameters()

func warp_active() -> bool:
	return _warp_age < 1.15

func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_screen = ColorRect.new()
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material = ShaderMaterial.new(); _material.shader = POST
	_screen.material = _material
	add_child(_screen)
	_overlay_layer = CanvasLayer.new(); _overlay_layer.layer = 12
	add_child(_overlay_layer)
	_overlay = ColorRect.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_material = ShaderMaterial.new(); _overlay_material.shader = CRT_OVERLAY
	_overlay.material = _overlay_material
	_overlay_layer.add_child(_overlay)

func configure(_camera: Camera3D, environment = null) -> void:
	# Keep the author's light setup. The pass itself provides grade and highlights.
	if environment is WorldEnvironment: environment = environment.environment
	if environment is Environment:
		environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC

func set_time_stop(amount: float) -> void:
	_target_stop = clampf(amount,0,1)

func set_rush(amount: float) -> void:
	_target_rush = clampf(amount,0,1)

func set_frozen(value: bool) -> void:
	frozen = value

func set_enabled(value: bool) -> void:
	visible = value
	if _overlay_layer != null: _overlay_layer.visible = value

func trigger_time_stop_crt(reduced: bool = false) -> void:
	_crt_armed = true
	_crt_entry_age = 0.0
	_crt_reduced = reduced
	_target_stop = 1.0

func reset() -> void:
	time_stop = 0.0; rush = 0.0
	_target_stop = 0.0; _target_rush = 0.0
	_flash_left = 0.0; _crt_entry_age = 1.0
	_slam_age = 1.0; _kill_left = 0.0; _kill_cooldown = 0.0; _warp_age = 2.0
	_crt_armed = false; frozen = false
	_rush_freeze = 0.0; _rush_freeze_left = 0.0; _combo_heat = 0.0; _target_combo_heat = 0.0
	set_sand_weather(false)
	_push_parameters()

func flash(amount: float = .18, duration: float = .14, color: Color = Color("e9faff")) -> void:
	_flash_strength = clampf(amount,0.0,.35)
	_flash_duration = clampf(duration,.06,.3)
	_flash_left = _flash_duration
	if _material != null: _material.set_shader_parameter("flash_color",color)

func _process(delta: float) -> void:
	if frozen or _material == null: return
	_clock += delta
	_tick_sand(delta)
	_slam_age = minf(1.0,_slam_age+delta)
	_warp_age = minf(2.0,_warp_age+delta)
	_kill_left = maxf(0.0,_kill_left-delta)
	_kill_cooldown = maxf(0.0,_kill_cooldown-delta)
	if _crt_armed: _crt_entry_age += delta
	_flash_left = maxf(0.0,_flash_left-delta)
	time_stop = move_toward(time_stop,_target_stop,delta*5.5)
	rush = move_toward(rush,_target_rush,delta*9.0)
	flashlight = move_toward(flashlight,_target_flashlight,delta*2.5)
	_combo_heat = move_toward(_combo_heat,_target_combo_heat,delta*2.0)
	_rush_freeze_left = maxf(0.0,_rush_freeze_left-delta)
	if _rush_freeze_left <= 0.0: _rush_freeze = move_toward(_rush_freeze,0.0,delta*7.0)
	if time_stop <= 0.0 and _crt_entry_age > .42: _crt_armed = false
	_push_parameters()

func _push_parameters() -> void:
	if _material == null: return
	_material.set_shader_parameter("time_stop",time_stop)
	_material.set_shader_parameter("rush",rush)
	_material.set_shader_parameter("art_clock",_clock)
	var sand_envelope := smoothstep(0.0,1.3,_sand_age)*(1.0-smoothstep(2.8,SAND_DURATION,_sand_age))
	_material.set_shader_parameter("sand_amount",sand_envelope*(.5 if _sand_reduced else 1.0) if _sand_enabled else 0.0)
	_material.set_shader_parameter("sand_clock",_sand_age*(.65 if _sand_reduced else 1.0)+float(_sand_cycle)*11.7)
	_material.set_shader_parameter("flash_amount",_flash_strength*pow(_flash_left/_flash_duration,2.0))
	_material.set_shader_parameter("crt_amount",time_stop if _crt_armed else 0.0)
	_material.set_shader_parameter("crt_entry_age",_crt_entry_age)
	_material.set_shader_parameter("crt_reduced",1.0 if _crt_reduced else 0.0)
	_material.set_shader_parameter("slam_age",_slam_age)
	_material.set_shader_parameter("slam_uv",_slam_uv)
	_material.set_shader_parameter("slam_reduced",1.0 if _slam_reduced else 0.0)
	_material.set_shader_parameter("kill_amount",_kill_strength*pow(_kill_left/.16,2.0))
	_material.set_shader_parameter("warp_age",_warp_age)
	_material.set_shader_parameter("warp_uv",_warp_uv)
	_material.set_shader_parameter("warp_reduced",1.0 if _warp_reduced else 0.0)
	_material.set_shader_parameter("flashlight",flashlight)
	_material.set_shader_parameter("light_uv",_light_uv)
	_material.set_shader_parameter("light_dir",_light_dir)
	_material.set_shader_parameter("rush_uv",_rush_uv)
	_material.set_shader_parameter("rush_freeze",_rush_freeze)
	_material.set_shader_parameter("combo_heat",_combo_heat)
	_material.set_shader_parameter("combo_color",_combo_color)
	if _overlay_material != null:
		_overlay_material.set_shader_parameter("amount",time_stop if _crt_armed else 0.0)
