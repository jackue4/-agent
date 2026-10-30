extends Node3D
## Sky, sun, fog, tonemap and glow for the 3D world. Everything here works on the
## gl_compatibility renderer (Web/WebGL2): procedural sky, one directional shadow,
## depth fog and glow. Presets come from world.light ("sunny"|"sunset"|"night"|"cloudy"
## or a number = sun energy) and are tinted by the spec's sky_color / horizon_color.
const U = preload("res://util.gd")

const DEFAULT_PRESET := "sunny"
const PRESETS := {
	"sunny": {
		"top": Color("#3d9be9"), "horizon": Color("#d4efff"), "ground": Color("#c3e4f7"),
		"sun": Color("#fff1d6"), "energy": 1.0, "pitch": -52.0, "yaw": -38.0,
		"ambient": 0.6, "shadow": 0.72, "exposure": 1.0, "glow": 0.3,
	},
	"sunset": {
		"top": Color("#4a3f86"), "horizon": Color("#ffb073"), "ground": Color("#a86a63"),
		"sun": Color("#ffbb80"), "energy": 1.0, "pitch": -22.0, "yaw": -60.0,
		"ambient": 0.6, "shadow": 0.7, "exposure": 1.0, "glow": 0.5,
	},
	"night": {
		"top": Color("#050a26"), "horizon": Color("#2a3a78"), "ground": Color("#1b2448"),
		"sun": Color("#a9bcff"), "energy": 0.55, "pitch": -58.0, "yaw": 30.0,
		"ambient": 0.9, "shadow": 0.6, "exposure": 1.1, "glow": 0.9,
	},
	"cloudy": {
		"top": Color("#8ea6bd"), "horizon": Color("#e3e9ef"), "ground": Color("#c8d2dc"),
		"sun": Color("#f4f4f4"), "energy": 0.6, "pitch": -65.0, "yaw": -30.0,
		"ambient": 0.85, "shadow": 0.4, "exposure": 1.05, "glow": 0.2,
	},
}
## How strongly an explicit spec sky_color / horizon_color overrides the preset.
const SPEC_SKY_WEIGHT := 0.65
const SPEC_HORIZON_WEIGHT := 0.55
const TWEEN_SECS := 0.8
const SHADOW_MIN := 30.0
const SHADOW_MAX := 140.0

var env: Environment
var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var horizon_color := Color.WHITE
var preset_name := DEFAULT_PRESET

func _ready() -> void:
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_curve = 0.08
	sky_mat.ground_curve = 0.08
	sky_mat.sun_angle_max = 18.0
	sky_mat.sun_curve = 0.08
	sky_mat.use_debanding = true
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_sky_affect = 0.0
	env.fog_depth_curve = 1.6
	env.glow_enabled = true
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.02
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.5
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	add_child(sun)

## Apply world settings (light preset + optional spec colours); animate tweens the sky.
func apply(w: Dictionary, animate: bool) -> void:
	var light = w.get("light", DEFAULT_PRESET)
	preset_name = str(light) if typeof(light) == TYPE_STRING and PRESETS.has(light) else DEFAULT_PRESET
	var p: Dictionary = PRESETS[preset_name]
	var top: Color = p.top
	var horizon: Color = p.horizon
	var spec_sky = w.get("sky_color", w.get("background_color"))
	if typeof(spec_sky) == TYPE_STRING:
		top = top.lerp(U.col(spec_sky, top), SPEC_SKY_WEIGHT)
		if top.get_luminance() > 0.6:
			top = top.lerp(Color(top.h, minf(top.s + 0.25, 1.0), 0.55), 0.6)  # keep a gradient for pale AI skies
	if typeof(w.get("horizon_color")) == TYPE_STRING:
		horizon = horizon.lerp(U.col(w.get("horizon_color"), horizon), SPEC_HORIZON_WEIGHT)
	horizon_color = horizon
	var energy: float = p.energy
	if typeof(light) == TYPE_INT or typeof(light) == TYPE_FLOAT:
		energy = clampf(float(light), 0.1, 3.0) * 1.4
	_set_sky(top, horizon, p.ground, animate)
	sky_mat.sun_angle_max = 30.0 if preset_name == "sunset" else 18.0
	sun.rotation_degrees = Vector3(p.pitch, p.yaw, 0)
	sun.light_color = U.col(w.get("sun_color"), p.sun)
	sun.light_energy = energy
	sun.shadow_opacity = p.shadow
	env.ambient_light_energy = p.ambient
	env.tonemap_exposure = p.exposure
	env.glow_intensity = p.glow
	env.fog_light_color = horizon
	env.fog_light_energy = 1.0

## Match fog and shadow range to the camera distance / level size.
func fit_view(view_dist: float, level_span: float) -> void:
	env.fog_depth_begin = maxf(view_dist * 1.1, 24.0)
	env.fog_depth_end = maxf(maxf(view_dist * 3.5, level_span * 1.6), env.fog_depth_begin + 60.0)
	sun.directional_shadow_max_distance = clampf(view_dist * 2.2, SHADOW_MIN, SHADOW_MAX)

func _set_sky(top: Color, horizon: Color, ground: Color, animate: bool) -> void:
	# The void below the horizon mirrors the sky, so floating islands read as airborne.
	var ground_h := horizon
	var bottom := top.lerp(horizon, 0.45).lerp(ground, 0.25)
	if not animate:
		sky_mat.sky_top_color = top
		sky_mat.sky_horizon_color = horizon
		sky_mat.ground_horizon_color = ground_h
		sky_mat.ground_bottom_color = bottom
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(sky_mat, "sky_top_color", top, TWEEN_SECS)
	tw.tween_property(sky_mat, "sky_horizon_color", horizon, TWEEN_SECS)
	tw.tween_property(sky_mat, "ground_horizon_color", ground_h, TWEEN_SECS)
	tw.tween_property(sky_mat, "ground_bottom_color", bottom, TWEEN_SECS)