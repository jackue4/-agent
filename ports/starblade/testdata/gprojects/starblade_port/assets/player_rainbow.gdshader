shader_type spatial;
// Additive rolling rainbow shell for the hero after absorbing a blessing.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
uniform float amount = 0.0;
uniform float phase = 0.0;
varying vec3 world_pos;
vec3 hue(float h) { return clamp(abs(mod(h*6.0+vec3(0.0,4.0,2.0),6.0)-3.0)-1.0,0.0,1.0); }
void vertex() { world_pos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	float rim = pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),1.4);
	// Bands sweep up the body; brightness peaks on a travelling scan line.
	float band = fract(world_pos.y*.9 - TIME*1.6 + phase);
	float scan = smoothstep(.25,0.0,abs(fract(world_pos.y*.35 - phase*.8)-.5)-.2);
	vec3 c = hue(band);
	ALBEDO = c*amount*(.55+rim*1.2+scan*.6);
}
