shader_type spatial;
// Opaque prismatic cube body: white heart, cycling rainbow toward the silhouette.
render_mode unshaded, shadows_disabled;
uniform float glow = 1.0;
uniform float hue_offset = 0.0;
vec3 hue(float h) { return clamp(abs(mod(h*6.0+vec3(0.0,4.0,2.0),6.0)-3.0)-1.0,0.0,1.0); }
void fragment() {
	float f = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.6);
	vec3 c = hue(fract(TIME*.4 + hue_offset + f*.55 + UV.x*.25));
	ALBEDO = mix(vec3(1.0), c, .45 + f*.55)*glow;
}
