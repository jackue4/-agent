shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0,.4,.12,1.0);
uniform float progress = 0.0;
uniform float opacity = 1.0;

void fragment() {
	// A broad eight-sided white-hot core, not the sparse thin rays of a loot beam.
	float stripes = .55+.45*pow(max(cos(UV.x*50.26548),0.0),3.0);
	float flames = .78+.22*sin(UV.y*18.0-UV.x*12.0-progress*5.0);
	float edge = pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),2.0);
	float vertical = smoothstep(0.0,.07,UV.y)*(1.0-smoothstep(.87,1.0,UV.y));
	float fade = 1.0-smoothstep(.53,1.0,progress);
	vec3 heat = mix(tint.rgb,vec3(1.0,.92,.63),stripes*.62);
	ALBEDO = heat;
	EMISSION = heat*.65;
	ALPHA = (.62+stripes*.23+edge*.15)*vertical*flames*fade*opacity;
}
