shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(.3,.8,1.,1.);
uniform float progress = 0.0;
uniform float opacity = 1.0;
void fragment() {
	float fresnel = pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),2.2);
	vec2 grid = fract(UV*vec2(18.0,10.0));
	float line = (1.0-smoothstep(.015,.045,min(min(grid.x,1.-grid.x),min(grid.y,1.-grid.y))));
	float facet = step(.48,fract(sin(dot(floor(UV*vec2(18.,10.)),vec2(12.98,78.23)))*43758.54));
	float cuts = .35+.65*facet;
	float fade = smoothstep(0.,.06,progress)*(1.-smoothstep(.50,1.,progress));
	ALBEDO = mix(tint.rgb,vec3(.85,.98,1.),line*.65);
	EMISSION = ALBEDO*.65;
	ALPHA = (fresnel*.20+line*.12+facet*.008)*cuts*fade*opacity;
}
