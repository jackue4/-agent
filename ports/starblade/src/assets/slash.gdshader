shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 slash_color : source_color = vec4(0.4,0.9,1.0,1.0);
uniform float progress : hint_range(0.0,1.0) = 0.0;
void fragment() {
	float ends = pow(max(sin(UV.x*3.14159),0.0),0.35);
	float rim = smoothstep(0.8,1.0,UV.y);
	ALBEDO = mix(slash_color.rgb,vec3(1.0),rim*.85);
	EMISSION = ALBEDO * 1.3;
	ALPHA = ends * (0.2+UV.y*.8) * (1.0-progress);
}
