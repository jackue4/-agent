shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 stone_color : source_color = vec4(.65,.55,.39,1);
varying vec3 p;
float grain(vec3 v) { return fract(sin(dot(v,vec3(12.9898,78.233,35.719)))*43758.5453); }
void vertex() { p = (MODEL_MATRIX*vec4(VERTEX,1)).xyz; }
void fragment() {
	float sediment = sin(p.y*24.0+sin(p.x*1.3+p.z)*.7)*.025;
	float fleck = grain(floor(p*32.0));
	float stain = sin(p.x*.72+sin(p.z*.7))*sin(p.y*.81)*.07;
	ALBEDO = stone_color.rgb*(.92+sediment+fleck*.11+stain);
	ROUGHNESS = .88;
	METALLIC = 0.0;
	SPECULAR = .22;
}
