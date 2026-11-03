extends RefCounted
## Hand-drawn pencil art kit: the same strokes, paper and palette as the platform's sketch board,
## so a Demo drawn with it looks like the sketch came alive. Every visual is an art slot with a
## stable id: it draws pencil lines until res://assets/<id>.png exists, then shows the final art
## at the same size, so code, layout and collisions never change when the art arrives.
##   const Pencil = preload("res://addons/ugc/pencil.gd")

const SKETCH = preload("res://addons/ugc/pencil_sketch.gd")

const PAPER := Color("f8f4ea")
const INK := Color("2a2a30")
const GRAPHITE := Color("5d5a55")
## Soft colored-pencil palette shared with the sketch board.
const COLORS := {
	"red": Color("d0574b"), "orange": Color("e08a3c"), "yellow": Color("e6b93a"), "green": Color("5d9a5a"),
	"teal": Color("3f9a95"), "blue": Color("4a78b8"), "purple": Color("8a63a8"), "pink": Color("d77a95"),
	"brown": Color("8b6a45"), "gray": Color("8f8c86"), "ink": INK, "paper": PAPER,
}
## Written by the art stage together with the first batch of final art.
const STYLE_KEY := "art_style"

static func color(name: String, fallback := INK) -> Color:
	return COLORS.get(name, fallback)

## res://assets/<id>.<ext> once the art stage has generated it; "" while the slot is still pencil.
static func art_path(id: String, exts := ["png", "jpg", "webp"]) -> String:
	for ext in exts:
		var p := "res://assets/%s.%s" % [id, ext]
		if ResourceLoader.exists(p):
			return p
	return ""

static func has_art(id: String) -> bool:
	return art_path(id) != ""

## True once final art has started landing: shaders drop the hatching and paper tint.
static func art_stage() -> bool:
	return has_art(STYLE_KEY)

static func texture(id: String) -> Texture2D:
	var p := art_path(id)
	if p == "":
		return null
	return load(p) as Texture2D

## A pencil drawing node. Draw into it with rect/circle/poly/line/text; it gently "boils" like
## animated hand-drawn lines unless boil = false.
static func sketch(seed := 0) -> Node2D:
	var s: Node2D = SKETCH.new()
	s.seed = seed
	return s

## Texture cropped to its opaque area (generated sprites have transparent margins).
static func cropped(tex: Texture2D) -> Texture2D:
	var img := tex.get_image()
	if img == null:
		return tex
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0 or used.size == Vector2i(tex.get_size()):
		return tex
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(used)
	return atlas

## 2D art slot: final art when it exists, otherwise pencil lines from draw.call(sketch, size).
## Both are centered on the returned node and fit `size`.
static func sprite(id: String, size: Vector2, draw: Callable, seed := -1) -> Node2D:
	var root := Node2D.new()
	root.name = id
	var tex := texture(id)
	if tex:
		var spr := Sprite2D.new()
		spr.name = "Art"
		spr.texture = cropped(tex)
		var src := spr.texture.get_size()
		var k: float = min(size.x / max(src.x, 1.0), size.y / max(src.y, 1.0))
		spr.scale = Vector2(k, k)
		root.add_child(spr)
	else:
		var s := sketch(seed if seed >= 0 else id.hash())
		s.name = "Pencil"
		s.position = -size / 2.0
		draw.call(s, size)
		root.add_child(s)
	return root

## Full-screen paper background (grain, faint grid, soft vignette). mouse_filter ignores clicks.
static func paper(grid := 32.0) -> ColorRect:
	var r := ColorRect.new()
	r.name = "Paper"
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = PAPER_SHADER
	m.set_shader_parameter("paper", PAPER)
	m.set_shader_parameter("grid", grid)
	r.material = m
	return r

## Background slot: the generated backdrop covering the screen, otherwise paper.
static func backdrop(id := "background", grid := 32.0) -> Control:
	var tex := texture(id)
	if tex == null:
		return paper(grid)
	var r := TextureRect.new()
	r.name = "Backdrop"
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.texture = tex
	return r

## Paper-like StyleBox for panels and buttons: off-white card, ink border, soft shadow.
static func style(fill := Color("fffdf7"), border := INK, width := 2, radius := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0.24, 0.19, 0.1, 0.18)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(1, 3)
	sb.set_content_margin_all(10)
	return sb

## A theme for Control UI that matches the paper: ink text, paper cards, yellow-highlighter hover.
static func theme(font_size := 22) -> Theme:
	var t := Theme.new()
	t.default_font_size = font_size
	for cls in ["Label", "Button", "RichTextLabel"]:
		t.set_color("font_color", cls, INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_stylebox("normal", "Button", style())
	t.set_stylebox("hover", "Button", style(Color("fff3b4")))
	t.set_stylebox("pressed", "Button", style(Color("f2e08a")))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", style())
	t.set_stylebox("panel", "Panel", style())
	return t

## 3D material slot: colored pencil on paper (toon tone, screen-space hatching, boiling ink
## outline). When res://assets/<art_id>.png exists it is mapped triplanar; in the art stage the
## hatching and paper tint give way to clean toon shading.
static func material(tint: Color, art_id := "", outline := 0.03) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = SPATIAL_SHADER
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("ink", INK)
	m.set_shader_parameter("paper", PAPER)
	m.set_shader_parameter("pencil", 0.0 if art_stage() else 1.0)
	var tex := texture(art_id) if art_id != "" else null
	if tex:
		m.set_shader_parameter("albedo_tex", tex)
		m.set_shader_parameter("use_tex", true)
	if outline > 0.0:
		var o := ShaderMaterial.new()
		o.shader = Shader.new()
		o.shader.code = OUTLINE_SHADER
		o.set_shader_parameter("ink", INK)
		o.set_shader_parameter("width", outline * (0.6 if art_stage() else 1.0))
		o.set_shader_parameter("boil", 0.0 if art_stage() else 1.0)
		m.next_pass = o
	return m

## 3D character/prop slot, applied in place: call after building `holder`'s pencil meshes. When
## the final art exists those meshes are hidden and an upright billboard `height` units tall is
## added to `holder`. Always returns `holder`, so the return value may be ignored.
static func actor3d(id: String, height: float, holder: Node3D) -> Node3D:
	var tex := texture(id)
	if tex == null or holder.has_node("Art_" + id):
		return holder
	for n in holder.find_children("*", "GeometryInstance3D", true, false):
		n.visible = false
	var s := Sprite3D.new()
	s.name = "Art_" + id
	s.texture = cropped(tex)
	# Full billboard: a Y-locked one is squashed by top-down and isometric cameras.
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.pixel_size = height / max(s.texture.get_size().y, 1.0)
	s.position.y = height / 2.0
	holder.add_child(s)
	return holder

## 3D: paper (or, in the art stage, soft studio) background and ambient. Returns the WorldEnvironment.
static func environment(parent: Node, sky := Color("dfe6ee")) -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = sky if art_stage() else PAPER
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	var we := WorldEnvironment.new()
	we.name = "PaperWorld"
	we.environment = env
	parent.add_child(we)
	return we

const PAPER_SHADER := """
shader_type canvas_item;
uniform vec4 paper : source_color = vec4(0.973, 0.957, 0.918, 1.0);
uniform float grid = 32.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 px = FRAGCOORD.xy;
	float grain = h(floor(px)) * 0.045 + h(floor(px / 4.0)) * 0.03;
	vec2 g = abs(fract(px / grid) - 0.5);
	float line = smoothstep(0.5 - 0.6 / grid, 0.5, max(g.x, g.y)) * 0.08;
	vec2 uv = SCREEN_UV - 0.5;
	float vig = dot(uv, uv) * 0.18;
	COLOR = vec4(paper.rgb - grain - vig - vec3(line * 0.6, line * 0.4, line * 0.1), 1.0);
}
"""

const SPATIAL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform vec4 tint : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform vec4 ink : source_color = vec4(0.16, 0.16, 0.19, 1.0);
uniform vec4 paper : source_color = vec4(0.973, 0.957, 0.918, 1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform float pencil = 1.0;
uniform vec3 light_dir = vec3(-0.45, -1.0, -0.6);
uniform float hatch_px = 6.0;
uniform float tex_scale = 0.2;
varying vec3 wpos;
varying vec3 wnrm;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float lines(vec2 p, float ang, float spacing) {
	vec2 d = vec2(cos(ang), sin(ang));
	float f = abs(fract(dot(p, d) / spacing) - 0.5);
	return 1.0 - smoothstep(0.1, 0.22, f);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 n = normalize(wnrm);
	vec3 base = tint.rgb;
	if (use_tex) {
		vec3 b = abs(n); b /= (b.x + b.y + b.z);
		vec3 tx = texture(albedo_tex, wpos.zy * tex_scale).rgb;
		vec3 ty = texture(albedo_tex, wpos.xz * tex_scale).rgb;
		vec3 tz = texture(albedo_tex, wpos.xy * tex_scale).rgb;
		// The art already carries its colour; the pencil tint only nudges it.
		base = (tx * b.x + ty * b.y + tz * b.z) * mix(vec3(1.0), tint.rgb, 0.15);
	}
	float tone = clamp(dot(n, -normalize(light_dir)) * 0.5 + 0.5, 0.0, 1.0);
	float band = tone > 0.75 ? 1.0 : tone > 0.5 ? 0.86 : 0.72;
	vec2 sp = FRAGCOORD.xy + vec2(floor(TIME * 6.0) * 1.7, floor(TIME * 6.0) * 0.9);
	float shade = 0.0;
	if (tone < 0.7) shade = lines(sp, 0.785, hatch_px);
	if (tone < 0.45) shade = max(shade, lines(sp, -0.785, hatch_px * 1.1));
	float grain = h(floor(FRAGCOORD.xy)) * 0.05 * pencil;
	vec3 col = mix(base, mix(paper.rgb, base, 0.82), pencil * (use_tex ? 0.0 : 1.0)) * band;
	col = mix(col, ink.rgb, shade * pencil * (use_tex ? 0.16 : 0.32));
	ALBEDO = col - grain;
}
"""

const OUTLINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front;
uniform vec4 ink : source_color = vec4(0.16, 0.16, 0.19, 1.0);
uniform float width = 0.03;
uniform float boil = 1.0;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wob = sin(w.x * 13.0 + w.y * 7.0 + floor(TIME * 6.0) * 2.1) * 0.25 * boil + 1.0;
	// Width in world units, so stretched slabs and pillars keep an even ink line.
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	VERTEX += (inverse(MODEL_MATRIX) * vec4(n * width * wob, 0.0)).xyz;
}
void fragment() { ALBEDO = ink.rgb; }
"""
