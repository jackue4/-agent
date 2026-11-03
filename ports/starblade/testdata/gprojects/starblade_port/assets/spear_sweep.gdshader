shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 sweep_color : source_color = vec4(0.45,0.9,1.0,1.0);
uniform float progress : hint_range(0.0,1.0) = 0.0;
void fragment() {
	vec2 uv = (floor(UV*256.0)/256.0-0.5)*2.0;
	float radius = length(uv);
	float angle = atan(uv.y,uv.x)/6.2831853;
	float tail = fract(progress*1.25-angle);
	float sweep = smoothstep(0.0,0.09,tail)*(1.0-smoothstep(0.15,0.82,tail));
	float band = smoothstep(0.60,0.82,radius)*(1.0-smoothstep(0.91,0.96,radius));
	float edge = smoothstep(0.86,0.91,radius);
	ALBEDO = mix(sweep_color.rgb,vec3(1.0),edge*0.8);
	EMISSION = ALBEDO*1.1;
	ALPHA = sweep*band*(1.0-progress)*0.72;
}
