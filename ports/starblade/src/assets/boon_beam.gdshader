shader_type spatial;
// Rainbow light column for falling / resting blessings. UV.y runs top (0) to bottom (1).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float strength = 1.0;
uniform float hue_speed = .55;
uniform float bottom_weight = 1.4;
vec3 hue(float h) { return clamp(abs(mod(h*6.0+vec3(0.0,4.0,2.0),6.0)-3.0)-1.0,0.0,1.0); }
void fragment() {
	float h = fract(UV.y*1.3 - TIME*hue_speed + UV.x*.5);
	vec3 c = mix(hue(h), vec3(1.0), .2);
	float bands = .72 + .28*sin(UV.y*48.0 + TIME*16.0);
	float fade = pow(clamp(UV.y,0.0,1.0), bottom_weight);
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = c;
	EMISSION = c*2.2;
	ALPHA = clamp(fade*bands*strength*(.25 + .75*facing), 0.0, 1.0);
}
