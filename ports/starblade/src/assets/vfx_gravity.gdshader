shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(.65,.35,1.,1.);
uniform float progress = 0.0;
uniform float opacity = 1.0;
float band(float r,float center,float width) { return 1.-smoothstep(width*.35,width,abs(r-center)); }
void fragment() {
	vec2 p = UV*2.-1.; float r = length(p); float a = atan(p.y,p.x);
	float spiral = pow(max(0.,sin(a*4.+log(max(.10,r))*12.+progress*16.)),10.);
	float body = smoothstep(.10,.25,r)*(1.-smoothstep(.76,.94,r));
	float ring = band(r,.91,.018)*(.55+.45*step(-.1,sin(a*12.-progress*4.)));
	float core = band(r,.13,.022)+band(r,.20,.010)*.45;
	float fade = smoothstep(0.,.055,progress)*(1.-smoothstep(.91,1.,progress));
	ALBEDO = mix(tint.rgb,vec3(.92,.83,1.),ring*.8+core*.25);
	EMISSION = ALBEDO*.75;
	ALPHA = (spiral*body*.23+ring*.80+core*.50)*fade*opacity;
}
