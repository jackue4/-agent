shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(.4,.9,1.,1.);
uniform float progress = 0.0;
uniform float opacity = .6;
varying vec3 local_pos;
void vertex() { local_pos = VERTEX; }
void fragment() {
	float rim = pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),1.8);
	float bands = .72+.28*step(.45,fract(local_pos.y*11.0-progress*.3));
	ALBEDO = mix(tint.rgb,vec3(.9,1.,1.),rim*.5);
	EMISSION = ALBEDO*.45;
	ALPHA = (.12+rim*.45)*bands*pow(1.-progress,1.6)*opacity;
}
