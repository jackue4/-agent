shader_type canvas_item;
render_mode blend_add, unshaded;

uniform float clock = 0.0;
uniform float strength : hint_range(0.0, 1.0) = 0.75;
uniform float landing : hint_range(0.0, 1.0) = 0.0;
uniform vec2 card_size = vec2(352.0, 620.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float inherited_alpha = COLOR.a;
	vec2 p = UV * card_size;
	vec2 edge = min(p, card_size - p);
	float rim = 1.0 - smoothstep(3.0, 13.0, min(edge.x, edge.y));
	float sweep = fract(clock * 0.28) * 2.0 - 0.45;
	float band = exp(-pow((UV.x * 0.6 + UV.y - sweep) * 12.0, 2.0));
	vec3 rainbow = 0.5 + 0.5 * cos(vec3(0.0, 2.1, 4.2) + UV.x * 8.0 + UV.y * 3.0 + clock * 1.3);
	vec3 gold = mix(vec3(1.0, 0.63, 0.20), vec3(1.0, 0.90, 0.61), band);
	vec3 foil = mix(gold, rainbow, 0.27);
	// The body stays quiet for text; foil travels across the frame and artwork.
	float artwork = smoothstep(0.02, 0.05, UV.y) * (1.0 - smoothstep(0.35, 0.40, UV.y));
	float sheen = band * (rim * 0.65 + artwork * 0.12);
	vec2 cell = floor(p / 16.0);
	vec2 local = fract(p / 16.0) - 0.5;
	float seed = hash(cell);
	float crystal = 1.0 - smoothstep(0.10, 0.15, abs(local.x) + abs(local.y) * 0.65);
	float sparkle = pow(max(0.0, sin(clock * 2.6 + seed * 25.0)), 14.0);
	float flakes = crystal * step(0.83, seed) * sparkle * max(rim, artwork * 0.4);
	float alpha = strength * (rim * 0.045 + sheen + flakes * 0.8 + landing * rim * 0.48);
	COLOR = vec4(foil, clamp(alpha, 0.0, 0.85) * inherited_alpha);
}
