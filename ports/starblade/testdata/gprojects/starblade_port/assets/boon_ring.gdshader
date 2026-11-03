shader_type spatial;
// Ground ring for blessings. burst=0: steady ring at 'radius'. burst=1: one expanding
// shockwave driven by explicit 'progress' (0..1) so freezes and pauses stay exact.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float radius = .6;
uniform float width = .05;
uniform float strength = 1.0;
uniform float fill = 0.0;
uniform float burst = 0.0;
uniform float progress = 0.0;
vec3 hue(float h) { return clamp(abs(mod(h*6.0+vec3(0.0,4.0,2.0),6.0)-3.0)-1.0,0.0,1.0); }
void fragment() {
	vec2 d = (UV-.5)*2.0;
	float r = length(d);
	float ang = atan(d.y,d.x)/6.28318;
	float p = clamp(progress,0.0,1.0);
	float ring_r = mix(radius, mix(.06,.97,1.0-pow(1.0-p,2.4)), burst);
	float w = mix(width, width*(1.6-p), burst);
	vec3 c = mix(hue(fract(ang + TIME*.45 + r*.5)), vec3(1.0), .15);
	float ring = 1.0 - smoothstep(w*.45, w, abs(r-ring_r));
	float inner = fill*(1.0-smoothstep(0.0,ring_r,r))*.32;
	float ticks = step(.55, fract(ang*28.0 + TIME*.9))*(1.0-smoothstep(.0,.018,abs(r-ring_r-w*1.8)))*.55*(1.0-burst);
	float life = mix(1.0, 1.0-p, burst);
	ALBEDO = c;
	EMISSION = c*2.0;
	ALPHA = clamp((ring + inner + ticks)*strength*life*step(r,1.0), 0.0, 1.0);
}
