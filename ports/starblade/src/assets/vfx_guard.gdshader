shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(.7,.4,1.,1.);
uniform float progress = 0.0;
uniform float opacity = 1.0;
void fragment() {
	vec2 p = abs(UV*2.-1.);
	float hex = max(p.x*.866+p.y*.5,p.y);
	float shape = 1.-smoothstep(.84,.88,hex);
	float edge = smoothstep(.77,.83,hex)*shape;
	float inner = (1.-smoothstep(.013,.028,abs(hex-.56)))*.17;
	float scan = pow(max(0.,sin(UV.y*25.-progress*9.)),18.)*.035;
	float fade = smoothstep(0.,.035,progress)*(1.-smoothstep(.91,1.,progress));
	ALBEDO = mix(tint.rgb,vec3(.90,.95,1.),edge*.65);
	EMISSION = ALBEDO*.65;
	ALPHA = (shape*.035+edge*.50+inner+scan*shape)*fade*opacity;
}
