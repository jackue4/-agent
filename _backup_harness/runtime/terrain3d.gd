extends RefCounted
## Stylised terrain for platforms and the ground plane: a grass/snow/candy cap with a
## scalloped drip lip, layered soil sides and (for floating islands) a tapering rock
## underside. Surface colours are baked into vertex colours; one shared shader adds
## world-space noise and an optional planar/triplanar texture from an AI asset.
const Mesh3D = preload("res://mesh3d.gd")

## Side/rock palettes per theme. "drip" scales the lip scallops (0 = clean bevel).
const THEMES := {
	"grass": {"side": Color("#a8744a"), "band": Color("#8a5f3b"), "rock": Color("#a3a0b3"), "lip": 0.12, "drip": 1.0},
	"snow": {"side": Color("#a9bfd8"), "band": Color("#8ea6c2"), "rock": Color("#8f9bb3"), "lip": 0.06, "drip": 1.3},
	"sand": {"side": Color("#e0ad66"), "band": Color("#c99250"), "rock": Color("#a78063"), "lip": 0.1, "drip": 0.0},
	"stone": {"side": Color("#8d909a"), "band": Color("#777a85"), "rock": Color("#686b76"), "lip": 0.08, "drip": 0.0},
	"candy": {"side": Color("#7a4a32"), "band": Color("#fff0d6"), "rock": Color("#d77aa8"), "lip": 0.12, "drip": 1.4},
	"lava": {"side": Color("#4c3b3b"), "band": Color("#3a2c2c"), "rock": Color("#2f2828"), "lip": 0.08, "drip": 0.0},
	"ice": {"side": Color("#6283b4"), "band": Color("#4f6f9e"), "rock": Color("#41597f"), "lip": 0.06, "drip": 1.0},
}
const ROCK_STEPS := [[0.0, 0.97], [0.22, 0.86], [0.45, 0.66], [0.68, 0.42], [0.86, 0.2], [1.0, 0.04]]
const ROCK_DEPTH_K := 0.5
const ROCK_DEPTH_MAX := 7.0
const MAX_CORNER := 0.7
## Texture tiling: one crop of the image covers this many metres of platform top.
const TEX_PERIOD_PLATFORM := 6.0
const TEX_PERIOD_GROUND := 8.0
const TEX_CROP_PLATFORM := 0.62

const SHADER_CODE := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D top_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float tex_mix = 0.0;
uniform float tex_period = 6.0;
uniform float tex_crop = 1.0;
uniform bool tex_mirror = false;
uniform float noise_amt = 0.09;
varying vec3 lpos;
varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
vec3 top_sample(vec2 p) {
	vec2 uv = p / tex_period + 0.5;
	if (tex_mirror) { uv = 1.0 - abs(mod(uv, 2.0) - 1.0); }
	uv = (fract(uv) - 0.5) * tex_crop + 0.5;
	return texture(top_tex, uv).rgb;
}
void vertex() {
	lpos = VERTEX;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 c = COLOR.rgb;
	float n = vnoise(wpos.xz * 1.1 + wpos.y * 0.9) * 0.6 + vnoise(wpos.xz * 3.7 - wpos.y * 2.9) * 0.4;
	c *= 1.0 + (n - 0.5) * 2.0 * noise_amt;
	if (tex_mix > 0.0 && COLOR.a > 0.5) {
		c = mix(c, top_sample(lpos.xz), tex_mix);
	}
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
}
"""

static var _shader: Shader

static func _material(tex: Texture2D, period: float, crop: float, mirror: bool) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	var m := ShaderMaterial.new()
	m.shader = _shader
	if tex:
		m.set_shader_parameter("top_tex", tex)
		m.set_shader_parameter("tex_mix", 1.0)
		m.set_shader_parameter("tex_period", period)
		m.set_shader_parameter("tex_crop", crop)
		m.set_shader_parameter("tex_mirror", mirror)
	return m

## Pick a terrain theme from an explicit world.theme or from the platform's top colour.
static func theme_for(col: Color, world_theme: String) -> String:
	if THEMES.has(world_theme):
		return world_theme
	if col.s < 0.16:
		return "snow" if col.v > 0.8 else "stone"
	var h := col.h
	if h >= 0.17 and h < 0.45:
		return "grass"
	if h >= 0.08 and h < 0.17:
		return "sand"
	if h >= 0.45 and h < 0.72:
		return "ice"
	if h >= 0.72 or (col.v > 0.85 and col.s < 0.55):
		return "candy"
	return "lava"

## Linear-space vertex colour; alpha=1 marks "top surface" texels for the texture.
static func _c(col: Color, top: bool) -> Color:
	var l := col.srgb_to_linear()
	l.a = 1.0 if top else 0.0
	return l

## Platform mesh centred on the collision box: top face exactly at +size.y/2.
static func platform(size: Vector3, top_col: Color, theme: String, floating: bool, tex: Texture2D) -> MeshInstance3D:
	var th: Dictionary = THEMES.get(theme, THEMES.grass)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var h := size.y
	var top := h * 0.5
	var r := minf(MAX_CORNER, minf(hx, hz) * 0.35)
	var lip := clampf(h * 0.32, 0.12, 0.38)
	var drip: float = lip * 0.7 * float(th.drip)
	var bulge: float = th.lip
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Soften AI-picked neon colours a touch so the cap reads as painted grass, not plastic.
	var soft := Color.from_hsv(top_col.h, top_col.s * 0.82, minf(top_col.v * 1.04, 1.0))
	var cap_c := _c(soft, true)
	var lip_c := _c(soft.darkened(0.08), true)
	var under_c := _c(soft.darkened(0.3), false)
	# Cap: flat top, rounded bevel, overhanging lip with scallops, tucked underside.
	Mesh3D.slab(st, [
		Mesh3D.ring(hx - 0.1, hz - 0.1, r, top, cap_c, Vector2(0, 1)),
		Mesh3D.ring(hx + bulge * 0.6, hz + bulge * 0.6, r, top - 0.05, cap_c, Vector2(0.6, 0.8)),
		Mesh3D.ring(hx + bulge, hz + bulge, r, top - lip * 0.45, lip_c, Vector2(1, 0.15)),
		Mesh3D.ring(hx + bulge * 0.8, hz + bulge * 0.8, r, top - lip, lip_c, Vector2(0.7, -0.7), drip),
		Mesh3D.ring(hx - 0.05, hz - 0.05, r, top - lip * 0.9, under_c, Vector2(0, -1), drip * 0.6),
	], true, false)
	# Soil sides with a darker stratum band, slightly tapering inward.
	var side: Color = th.side
	var band: Color = th.band
	var soil_top := top - lip * 0.5
	var bottom := -h * 0.5
	var sh := soil_top - bottom
	var rings := [
		Mesh3D.ring(hx - 0.02, hz - 0.02, r, soil_top, _c(side.darkened(0.25), false), Vector2(1, 0)),
		Mesh3D.ring(hx - 0.02, hz - 0.02, r, soil_top - sh * 0.4, _c(side, false), Vector2(1, 0), 0.0, 0.02),
		Mesh3D.ring(hx - 0.04, hz - 0.04, r, soil_top - sh * 0.55, _c(band, false), Vector2(1, 0), 0.0, 0.02),
		Mesh3D.ring(hx - 0.07, hz - 0.07, r, soil_top - sh * 0.85, _c(band.darkened(0.1), false), Vector2(1, -0.1), 0.0, 0.03),
		Mesh3D.ring(hx - 0.18, hz - 0.18, r, bottom, _c(band.darkened(0.25), false), Vector2(0.5, -0.85)),
	]
	if floating:
		var rock: Color = th.rock
		var depth := clampf(maxf(size.x, size.z) * ROCK_DEPTH_K, 1.2, ROCK_DEPTH_MAX)
		for step in ROCK_STEPS.slice(1):
			var t: float = step[0]
			var k: float = step[1]
			var rr := minf(hx, hz) * k * 0.8
			rings.append(Mesh3D.ring((hx - 0.18) * k, (hz - 0.18) * k, rr, bottom - depth * t,
				_c(rock.darkened(t * 0.2), false), Vector2(1.0 - t * 0.5, -0.4 - t * 0.5), 0.0, 0.12 * minf(hx, hz) * k))
	Mesh3D.slab(st, rings, false, true)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material(tex, minf(TEX_PERIOD_PLATFORM, maxf(size.x, size.z)), TEX_CROP_PLATFORM, true)
	return mi

## Large ground slab whose top sits at y=0.
static func ground(gsize: float, col: Color, theme: String, tex: Texture2D) -> MeshInstance3D:
	var mi := platform(Vector3(gsize, 1.0, gsize), col, theme, false, null)
	mi.position.y = -0.5
	mi.material_override = _material(tex, TEX_PERIOD_GROUND, 1.0, false)
	return mi