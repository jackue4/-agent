shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.7, 0.2, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float edge = pow(abs(UV.x - 0.5) * 2.0, 5.0);
	float streaks = pow(max(0.0, sin(UV.x * 50.26548)), 16.0);
	float upward = 0.5 + 0.5 * sin(UV.y * 31.0 - progress * 24.0);
	float vertical = smoothstep(0.0, 0.12, UV.y) * (1.0 - smoothstep(0.65, 1.0, UV.y));
	ALBEDO = mix(tint.rgb, vec3(1.0), edge * 0.45);
	EMISSION = ALBEDO * 0.55;
	ALPHA = (edge * 0.23 + streaks * 0.10 + upward * 0.035) * vertical * pow(1.0 - progress, 1.2) * opacity;
}
