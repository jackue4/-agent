shader_type spatial;
render_mode diffuse_burley, cull_disabled, depth_draw_never;
uniform vec3 sand_color : source_color = vec3(.62,.51,.35);
void fragment() {
	vec2 p=UV*2.0-1.0;
	float edge=length(p*vec2(1.0,.85));
	float wind=sin(p.x*11.0+p.y*3.0)*.065+sin(p.y*17.0)*.035;
	ALBEDO=sand_color*(.94+sin(p.x*40.0+p.y*8.0)*.025);
	ROUGHNESS=.98;
	ALPHA=(1.0-smoothstep(.48,.98,edge+wind))*.86;
}
