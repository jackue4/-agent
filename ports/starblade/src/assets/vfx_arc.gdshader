shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.3, 0.9, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float ends = pow(max(sin(UV.x * 3.14159265), 0.0), 0.42);
	float leading = smoothstep(0.26, 1.0, UV.y);
	float thin_core = smoothstep(0.84, 0.965, UV.y);
	float ribs = 0.83 + 0.17 * sin(UV.x * 54.0);
	float fade = pow(1.0 - progress, 1.15);
	ALBEDO = mix(tint.rgb, vec3(1.0, 0.99, 0.92), thin_core * 0.9);
	EMISSION = ALBEDO * 1.05;
	ALPHA = ends * (0.13 + leading * 0.62 + thin_core * 0.62) * ribs * fade * opacity;
}
