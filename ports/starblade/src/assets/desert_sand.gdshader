shader_type spatial;
render_mode diffuse_burley, cull_disabled;
uniform vec3 sand_color : source_color = vec3(.55,.46,.32);
varying vec3 p;
void vertex() {
	VERTEX.y += sin(VERTEX.x*.072+sin(VERTEX.z*.043))*2.8+sin(VERTEX.z*.063)*1.7;
	p = (MODEL_MATRIX*vec4(VERTEX,1)).xyz;
}
void fragment() {
	float ripple = sin(p.x*5.5+sin(p.z*.39)*1.6)*.025;
	float drift = sin(p.x*.17+p.z*.05)*.07;
	ALBEDO = sand_color*(.94+ripple+drift);
	ROUGHNESS = .97;
}
