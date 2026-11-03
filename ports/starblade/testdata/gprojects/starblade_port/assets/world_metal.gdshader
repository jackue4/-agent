shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 base_color : source_color = vec4(.2,.3,.4,1.0);
uniform vec3 edge_color : source_color = vec3(.39,.62,.72);
uniform vec3 half_extent = vec3(.5);
uniform float emission_strength = 0.0;
uniform float art_clock = 0.0;
uniform float freeze_amount = 0.0;
uniform float hero_surface = 0.0;
varying vec3 local_pos;
varying vec3 local_normal;
void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}
void fragment() {
	vec3 n = abs(normalize(local_normal));
	vec3 gap = max(half_extent-abs(local_pos),vec3(0.0));
	float nearest_edge = n.x>.7 ? min(gap.y,gap.z) : (n.y>.7 ? min(gap.x,gap.z) : min(gap.x,gap.y));
	float bevel = 1.0-smoothstep(.006,.035,nearest_edge);
	vec2 p = n.y>.7 ? local_pos.xz : (n.x>.7 ? local_pos.zy : local_pos.xy);
	vec2 face_extent = max(n.y>.7 ? half_extent.xz : (n.x>.7 ? half_extent.zy : half_extent.xy),vec2(.001));
	vec2 face_uv = p/(face_extent*2.0)+.5;
	float large_panel = step(.42,min(face_extent.x,face_extent.y));
	float brushed = .985+.015*sin(floor(p.y*135.0)*1.17);
	float rim = pow(1.0-max(dot(normalize(NORMAL),normalize(VIEW)),0.0),3.5);
	float etched = (1.0-smoothstep(.014,.027,abs(fract(p.x*2.0+.5)-.5))) * .06;
	vec2 edge_uv = min(face_uv,1.0-face_uv);
	float channel = (1.0-smoothstep(.002,.008,abs(min(edge_uv.x,edge_uv.y)-.105)))*large_panel;
	float outer_lip = smoothstep(.035,.045,nearest_edge)*(1.0-smoothstep(.048,.065,nearest_edge));
	float stamping = step(.80,face_uv.y)*step(face_uv.y,.84)*step(.18,face_uv.x)*step(face_uv.x,.41)*step(.52,fract(face_uv.x*36.0))*large_panel;
	float plate_variation = fract(sin(dot(floor(p*3.0),vec2(13.37,47.21)))*653.73)*.035;
	vec3 base = base_color.rgb*brushed;
	base *= 1.0-plate_variation-channel*.32-stamping*.16;
	base = mix(base,base*.52,etched);
	base = mix(base,base_color.rgb*.35+edge_color*.60,bevel*.67);
	base += edge_color*outer_lip*.055;
	float scan = pow(max(sin((local_pos.y+art_clock*.18)*20.0),0.0),18.0)*hero_surface;
	ALBEDO = mix(base,mix(base,vec3(.13,.24,.32),.35),freeze_amount);
	METALLIC = .58-hero_surface*.44;
	ROUGHNESS = .32+etched*.8+channel*.22+plate_variation-hero_surface*.06;
	SPECULAR = .65;
	EMISSION = edge_color*(rim*.15+bevel*.060)+base_color.rgb*emission_strength*(.94+.06*sin(art_clock*2.0));
	EMISSION += vec3(.05,.35,.46)*scan*.10;
	EMISSION += vec3(.10,.32,.42)*freeze_amount*(bevel*.13+rim*.18);
}
