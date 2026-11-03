shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float dot_size = 5.0;
uniform float flash = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	// posterize a little for that printed-ink look
	vec3 pc = floor(c * 6.0 + 0.5) / 6.0;
	pc = mix(c, pc, 0.55);
	// Ben-Day halftone dots in mid/dark tones
	vec2 px = FRAGCOORD.xy;
	mat2 rot = mat2(vec2(0.7071, -0.7071), vec2(0.7071, 0.7071));
	vec2 g = rot * px / dot_size;
	vec2 cell = fract(g) - 0.5;
	float r = sqrt(clamp(1.0 - lum, 0.0, 1.0)) * 0.62;
	float d = length(cell);
	float dotm = 1.0 - smoothstep(r - 0.1, r + 0.1, d);
	float tone = smoothstep(0.92, 0.35, lum);
	vec3 col = mix(pc, pc * 0.62, dotm * tone * 0.55);
	// paper grain
	col *= 0.97 + 0.03 * hash(floor(px * 0.5));
	// manga impact frame: high contrast inverted silhouette
	float bw = step(0.42, lum);
	vec3 impact = mix(vec3(0.98, 0.95, 0.85), vec3(0.06, 0.04, 0.08), bw);
	col = mix(col, impact, flash);
	// vignette
	vec2 uv = SCREEN_UV - 0.5;
	col *= 1.0 - dot(uv, uv) * 0.55;
	COLOR = vec4(col, 1.0);
}
