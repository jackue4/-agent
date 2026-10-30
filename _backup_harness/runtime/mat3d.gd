extends RefCounted
## Cached toy-like materials for the 3D runtime (soft specular + rim light, like painted
## plastic). Materials are shared by colour/flags, so rebuilding entities doesn't churn GPU state.

const ROUGHNESS := 0.5
const SPECULAR := 0.35
const RIM := 0.2
const RIM_TINT := 0.6
const GLOW_ENERGY := 0.8

static var _cache := {}

## Opaque toy plastic. glow>0 adds emission (picked up by the Environment glow).
static func toy(col: Color, glow := 0.0, metal := 0.0) -> StandardMaterial3D:
	var key := "t%s_%.2f_%.2f" % [col.to_html(), glow, metal]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = ROUGHNESS if metal <= 0.0 else 0.25
	m.metallic = metal
	m.metallic_specular = SPECULAR
	m.rim_enabled = true
	m.rim = RIM
	m.rim_tint = RIM_TINT
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = glow * GLOW_ENERGY
	_cache[key] = m
	return m

## Unlit flat colour (eyes, highlights, clouds).
static func flat(col: Color) -> StandardMaterial3D:
	var key := "f%s" % col.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if col.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cache[key] = m
	return m

## Translucent glowing shell (powerup bubble, goal ring). Not cached: callers animate alpha.
static func glass(col: Color, alpha: float, glow := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.1
	m.metallic_specular = 0.9
	m.rim_enabled = true
	m.rim = 1.0
	m.rim_tint = 0.2
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = glow * 0.5
	m.disable_receive_shadows = true
	return m

## Vertical light shaft fading towards the top (goal beacon) for a 1-unit-tall mesh.
static func beam(col: Color) -> ShaderMaterial:
	var key := "b%s" % col.to_html()
	if _cache.has(key):
		return _cache[key]
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color;
varying float h;
void vertex() { h = VERTEX.y + 0.5; }  // mesh is 1 unit tall; the node is scaled
void fragment() {
	float edge = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
	float a = (1.0 - h) * (0.35 + 0.65 * (1.0 - edge)) * (0.8 + 0.2 * sin(TIME * 3.0 + h * 12.0));
	ALBEDO = tint.rgb * a;
	ALPHA = a;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tint", col)
	_cache[key] = m
	return m