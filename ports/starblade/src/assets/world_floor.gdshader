shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 base_color : source_color = vec4(.16,.21,.27,1.0);
uniform vec3 accent_color : source_color = vec3(.28,.65,.72);
uniform float art_clock = 0.0;
uniform float freeze_amount = 0.0;
uniform float stone_style = 0.0;
varying vec3 slab_tint;
uniform vec3 pulse_center = vec3(0.0);
uniform float pulse_age = 10.0;
uniform float pulse_strength = 0.0;
uniform float pulse_radius = 5.8;
// Seconds for the crest to reach pulse_radius; prism tints lifted slabs rainbow.
uniform float pulse_travel = .62;
uniform float pulse_prism = 0.0;
uniform vec4 path_seg_0 = vec4(0.0);
uniform vec4 path_seg_1 = vec4(0.0);
uniform vec4 path_seg_2 = vec4(0.0);
uniform vec4 path_seg_3 = vec4(0.0);
uniform vec4 path_ages = vec4(10.0);
uniform float path_strength = 1.0;
uniform vec3 path_accent : source_color = vec3(.35,.9,.95);
varying vec3 world_pos;
varying float path_lift;
varying vec3 local_normal;
varying vec2 panel_uv;
varying float pulse_lift;
// Travelling crest along one dash segment: slabs rise behind the front and settle.
float path_wave(vec2 tile, vec4 seg, float age) {
	if (age > 2.5) return 0.0;
	vec2 a = seg.xy; vec2 ab = seg.zw-seg.xy;
	float len2 = max(dot(ab,ab),.0001);
	float t = clamp(dot(tile-a,ab)/len2,0.0,1.0);
	float d = length(tile-(a+ab*t));
	float behind = age*34.0-t*sqrt(len2);
	if (behind < 0.0) return 0.0;
	float crest = exp(-behind*.55)*(.65+.35*cos(behind*1.7));
	float width = 1.0-smoothstep(1.1,2.9,d);
	return crest*width*(1.0-smoothstep(.9,1.6,age));
}
void vertex() {
	slab_tint = COLOR.rgb;
	world_pos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	// The entire tile moves as one slab, producing concentric stepped terraces.
	vec2 tile_center = (MODEL_MATRIX*vec4(0.0,0.0,0.0,1.0)).xz;
	float distance_to_pulse = length(tile_center-pulse_center.xz);
	float travel = max(pulse_travel,.1);
	float t = pulse_age/travel;
	float radius = (pulse_radius+1.2)*clamp(t,0.0,1.0);
	float offset = distance_to_pulse-radius;
	float crest = 1.0-smoothstep(.24,1.65,abs(offset));
	// Wide waves leave a decaying trailing ripple behind the main crest.
	float trail = pulse_prism*max(0.0,sin(-offset*1.15))*exp(offset*.28)*step(offset,0.0)*.55;
	float limit = 1.0-smoothstep(pulse_radius-.45,pulse_radius+.8,distance_to_pulse);
	float fade = (1.0-smoothstep(.77,1.48,t))*smoothstep(0.0,.035,pulse_age);
	pulse_lift = min(.95,floor(max(crest,trail)*fade*limit*pulse_strength*9.0)*.105);
	float pw = max(max(path_wave(tile_center,path_seg_0,path_ages.x),path_wave(tile_center,path_seg_1,path_ages.y)),max(path_wave(tile_center,path_seg_2,path_ages.z),path_wave(tile_center,path_seg_3,path_ages.w)));
	path_lift = floor(pw*path_strength*6.0)*.075;
	VERTEX.y += max(max(pulse_lift,0.0),path_lift);
	panel_uv = VERTEX.xz*.5+vec2(.5);
	local_normal = NORMAL;
}
float line(float v,float at,float width) { return 1.0-smoothstep(width,width+.006,abs(v-at)); }
void fragment() {
	vec2 cell = floor(world_pos.xz*.5);
	vec2 p = panel_uv;
	float tile_id = mod(cell.x*7.0+cell.y*13.0,11.0);
	float top = step(.6,local_normal.y);
	vec2 edge = min(p,1.0-p);
	float seam = 1.0-smoothstep(.003,.007,min(edge.x,edge.y));
	float bevel = smoothstep(.006,.008,min(edge.x,edge.y))*(1.0-smoothstep(.012,.018,min(edge.x,edge.y)));
	float inset = step(.14,p.x)*step(p.x,.86)*step(.14,p.y)*step(p.y,.86);
	float panel = inset*step(tile_id,3.0);
	float grate = panel*(.5+.5*sin(p.x*125.6637))*.025;
	float screw = 0.0;
	for(int x=0;x<2;x++) for(int y=0;y<2;y++) {
		vec2 c = vec2(.09+float(x)*.82,.09+float(y)*.82);
		screw += 1.0-smoothstep(.008,.015,length(p-c));
	}
	float channel = (line(p.x,.18,.008)*step(.18,p.y)*step(p.y,.65)+line(p.y,.65,.008)*step(.18,p.x)*step(p.x,.47))*step(8.0,tile_id);
	float dash = line(p.x,.81,.012)*step(.15,p.y)*step(p.y,.34)*step(9.0,tile_id);
	float inset_border = (line(p.x,.14,.003)+line(p.x,.86,.003))*step(.14,p.y)*step(p.y,.86);
	inset_border += (line(p.y,.14,.003)+line(p.y,.86,.003))*step(.14,p.x)*step(p.x,.86);
	float ribs = step(.65,fract(p.x*18.0))*step(.24,p.x)*step(p.x,.76)*step(.80,p.y)*step(p.y,.84);
	float mill = sin(floor(p.y*160.0)*1.73+cell.x*7.0+cell.y)*.012;
	float rivet_glint = screw*(.5+.5*step(.5,fract((p.x+p.y)*55.0)));
	vec3 color = base_color.rgb*(.86+tile_id*.023);
	color *= 1.0-panel*.035-grate+mill-inset_border*.06-ribs*.08;
	color = mix(color,color*.38,seam);
	color += vec3(.022,.035,.045)*bevel;
	color = mix(color,vec3(.075,.10,.13),screw*.8);
	color += vec3(.03,.04,.05)*rivet_glint;
	ALBEDO = mix(color*.5,color,top);
	float polish = .5+.5*sin(world_pos.x*.23+sin(world_pos.z*.31)*2.1);
	float scuff = smoothstep(.91,.99,sin(p.x*153.0+p.y*48.0))*smoothstep(.6,.9,polish)*.055;
	METALLIC = .62;
	ROUGHNESS = .24+polish*.14+grate+scuff+inset_border*.08;
	// Fine bevel normals catch light along the thin panel lips.
	vec2 slope = ((1.0-smoothstep(vec2(.0),vec2(.015),p))-smoothstep(vec2(.985),vec2(1.0),p))*.28*top;
	NORMAL_MAP = normalize(vec3(slope,1.0))*.5+.5;
	SPECULAR = .55;
	float signal = .65+.35*sin(art_clock*1.4+cell.x*.7+cell.y*.4);
	EMISSION = accent_color*(channel*.28*signal+dash*.40+bevel*.008)*top;
	if (stone_style > .5) {
		float grain = fract(sin(dot(floor(world_pos.xz*47.0),vec2(12.9898,78.233)))*43758.5453);
		float wear = sin(world_pos.x*.64+sin(world_pos.z*.8))*sin(world_pos.z*.49);
		float chipped = 1.0-smoothstep(.008,.023+grain*.012,min(edge.x,edge.y));
		float crack = (1.0-smoothstep(.002,.006,abs(p.x-.32-sin(p.y*5.7+tile_id)*.09)))*step(8.5,tile_id);
		ALBEDO = base_color.rgb*slab_tint*(.96+wear*.085+grain*.08);
		ALBEDO = mix(ALBEDO,base_color.rgb*.48,chipped*.65+crack*.28);
		ALBEDO = mix(ALBEDO*.65,ALBEDO,top);
		ROUGHNESS = .9; METALLIC = 0.0; SPECULAR = .18;
		EMISSION = vec3(0.0);
	}
	ALBEDO = mix(ALBEDO,ALBEDO*vec3(.65,.9,1.17),freeze_amount*.7);
	EMISSION += accent_color*freeze_amount*(channel*.24+bevel*.05);
	// Exposed slab lips briefly turn white-hot; never fill the whole floor.
	vec3 lip = mix(vec3(.8,.36,.105),clamp(abs(mod(fract(length(world_pos.xz-pulse_center.xz)*.06-pulse_age*.5)*6.0+vec3(0.0,4.0,2.0),6.0)-3.0)-1.0,0.0,1.0),pulse_prism);
	EMISSION += lip*pulse_lift*(bevel*.48+(1.0-top)*.13+top*.08*pulse_prism);
	EMISSION += path_accent*path_lift*(bevel*1.6+(1.0-top)*.55+top*.22);
}
