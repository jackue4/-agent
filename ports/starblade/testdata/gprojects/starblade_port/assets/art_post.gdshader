shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float time_stop = 0.0;
uniform float rush = 0.0;
uniform float art_clock = 0.0;
uniform float sand_amount = 0.0;
uniform float sand_clock = 0.0;
uniform float strength = 1.0;
uniform float flash_amount = 0.0;
uniform vec3 flash_color : source_color = vec3(.8,.95,1.0);
uniform float crt_amount = 0.0;
uniform float crt_entry_age = 1.0;
uniform float crt_reduced = 0.0;
uniform float slam_age = 1.0;
uniform vec2 slam_uv = vec2(.5);
uniform float slam_reduced = 0.0;
uniform float kill_amount = 0.0;
uniform float warp_age = 2.0;
uniform vec2 warp_uv = vec2(.5);
uniform float warp_reduced = 0.0;
// Flashlight floor: bright cone ahead of the hero, dim but readable surroundings.
uniform float flashlight = 0.0;
uniform vec2 light_uv = vec2(.5);
uniform vec2 light_dir = vec2(0.0,-1.0);
uniform float light_dim = .62;
// Rush cinematics: radial zoom streaks around the hero and an entry freeze.
uniform vec2 rush_uv = vec2(.5);
uniform float rush_freeze = 0.0;
// Combo heat: warm edge glow that intensifies with long chains.
uniform float combo_heat = 0.0;
uniform vec3 combo_color : source_color = vec3(1.0,.72,.35);
vec3 warp_hue(float h) { return clamp(abs(mod(h*6.0+vec3(0.0,4.0,2.0),6.0)-3.0)-1.0,0.0,1.0); }
float sand_hash(vec2 p) {
	return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);
}
float sand_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(sand_hash(cell),sand_hash(cell+vec2(1,0)),f.x),
		mix(sand_hash(cell+vec2(0,1)),sand_hash(cell+vec2(1,1)),f.x),f.y);
}
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 pixel = SCREEN_PIXEL_SIZE;
	vec3 original = texture(screen_texture,uv).rgb;
	// One outward pressure front, driven by gameplay time; never a repeating strobe.
	float slam = 1.0-smoothstep(.025,.36,slam_age);
	float aspect = pixel.y/pixel.x;
	vec2 impact_delta = (uv-slam_uv)*vec2(aspect,1.0);
	float impact_distance = length(impact_delta);
	vec2 impact_direction = impact_delta/max(.0001,impact_distance)/vec2(aspect,1.0);
	float pressure_radius = .018+slam_age*.92;
	float pressure = exp(-pow((impact_distance-pressure_radius)/.042,2.0));
	float focus = exp(-impact_distance*6.5);
	uv += impact_direction*(pressure*.010-focus*.004)*slam*(1.0-slam_reduced);
	// Blessing pickup: one wide space-ripple front that sweeps past the screen edge.
	float warp_life = 1.0-smoothstep(.55,1.15,warp_age);
	vec2 warp_delta = (uv-warp_uv)*vec2(aspect,1.0);
	float warp_distance = length(warp_delta);
	vec2 warp_direction = warp_delta/max(.0001,warp_distance)/vec2(aspect,1.0);
	float warp_radius = warp_age*1.75;
	float warp_x = (warp_distance-warp_radius)/.11;
	float warp_front = exp(-warp_x*warp_x);
	float warp_ripple = sin(warp_x*4.2)*exp(-abs(warp_x)*.55)*step(warp_distance,warp_radius+.25);
	float warp_core = exp(-warp_distance*5.0)*(1.0-smoothstep(0.0,.22,warp_age));
	float warp_scale = warp_life*(1.0-warp_reduced*.75);
	vec2 warp_offset = warp_direction*(warp_front*.03+warp_ripple*.009-warp_core*.02)*warp_scale;
	uv += warp_offset;
	float entry = (1.0-smoothstep(.10,.42,crt_entry_age))*crt_amount*(1.0-crt_reduced);
	float pinch = sin(min(crt_entry_age/.24,1.0)*3.14159)*entry;
	uv.x = (uv.x-.5)*(1.0+pinch*.105)+.5;
	float sync_band = (1.0-smoothstep(.008,.022,abs(uv.y-(.32+crt_entry_age*.53))));
	float sync_echo = (1.0-smoothstep(.006,.015,abs(uv.y-(.73-crt_entry_age*.28))));
	uv.x += (sync_band*.019-sync_echo*.012)*entry;
	uv = clamp(uv,vec2(.001),vec2(.999));
	vec3 source = texture(screen_texture,uv).rgb;
	// Radial zoom blur centred on the hero during rush; sampled toward the centre.
	if (rush > .01) {
		vec2 to_center = rush_uv-uv;
		float edge = smoothstep(.06,.45,length(to_center*vec2(aspect,1.0)));
		vec3 acc = source;
		for (int i=1;i<6;i++) acc += texture(screen_texture,clamp(uv+to_center*float(i)*.012*rush*edge,vec2(.001),vec2(.999))).rgb;
		source = mix(source,acc/6.0,rush*.85);
	}
	float rgb_shift = crt_amount*(.80+entry*5.8)*(1.0-crt_reduced*.62);
	source.r = texture(screen_texture,uv+vec2(pixel.x*rgb_shift,0.0)).r;
	source.b = texture(screen_texture,uv-vec2(pixel.x*rgb_shift,0.0)).b;
	vec2 impact_shift = impact_direction*pixel.y*(3.2*pressure+focus)*slam*(1.0-slam_reduced);
	source.r = texture(screen_texture,clamp(uv+vec2(pixel.x*rgb_shift,0.0)+impact_shift,vec2(.001),vec2(.999))).r;
	source.b = texture(screen_texture,clamp(uv-vec2(pixel.x*rgb_shift,0.0)-impact_shift,vec2(.001),vec2(.999))).b;
	vec2 warp_shift = warp_direction*pixel.y*(9.0*warp_front+2.5*abs(warp_ripple))*warp_scale;
	source.r = mix(source.r,texture(screen_texture,clamp(uv+warp_shift,vec2(.001),vec2(.999))).r,min(warp_scale*2.0,1.0));
	source.b = mix(source.b,texture(screen_texture,clamp(uv-warp_shift,vec2(.001),vec2(.999))).b,min(warp_scale*2.0,1.0));
	vec3 halo = vec3(0.0);
	for(int i=0;i<4;i++) {
		vec2 d = vec2((i==0?1.0:(i==1?-1.0:0.0)),(i==2?1.0:(i==3?-1.0:0.0)));
		halo += max(texture(screen_texture,uv+d*pixel*2.4).rgb-vec3(.64),vec3(0.0));
	}
	vec3 color = source+halo*.075;
	float lum = dot(color,vec3(.2126,.7152,.0722));
	color = mix(vec3(lum),color,.84)*.94;
	color = (color-.25)*1.025+.25;
	float radius = length((uv-.5)*vec2(1.35,1.0));
	color *= 1.0-smoothstep(.38,.90,radius)*.085;
	// Wind-driven sand sheets behind the HUD; stronger on the frame than at the hero.
	if (sand_amount > .001) {
		vec2 wind_uv = SCREEN_UV*vec2(aspect,1.0);
		wind_uv.x += wind_uv.y*.45;
		vec2 drift = wind_uv-vec2(sand_clock*.62,-sand_clock*.06);
		float sheets = sand_noise(drift*vec2(2.7,7.5))*.57
			+sand_noise(drift*vec2(6.0,17.0)+vec2(4.1,2.7))*.43;
		float cloud = smoothstep(.27,.66,sheets);
		float ribbon = smoothstep(.34,.75,sand_noise(drift*vec2(1.2,4.2)+vec2(8.3,1.1)));
		float gust_front = 1.0-smoothstep(.12,.65,abs(wind_uv.x-(-.4+sand_clock*.57)));
		float center_clear = mix(.72,1.0,smoothstep(.10,.65,radius));
		float veil = (.065+cloud*.27+ribbon*.13+gust_front*.12)*sand_amount*center_clear;
		// Dark, desaturated dust reduces scene contrast without a bright flash.
		color = mix(color,vec3(.35,.33,.29),veil);
		// Fine, stretched grains ride the same wind as the broad dust bands.
		vec2 grain_uv = drift*vec2(105.0,235.0);
		vec2 grain_cell = floor(grain_uv);
		vec2 grain_local = fract(grain_uv)-.5;
		float grain = step(.92,sand_hash(grain_cell));
		grain *= (1.0-smoothstep(.12,.5,abs(grain_local.x)))
			*(1.0-smoothstep(.04,.31,abs(grain_local.y)));
		color = mix(color,vec3(.58,.53,.44),grain*sand_amount*center_clear*(.20+cloud*.16));
	}
	vec3 stopped = mix(vec3(lum),color,.45)*vec3(.79,1.01,1.12);
	color = mix(color,stopped,time_stop*.7);
	float rim = smoothstep(.42,.67,radius)*(1.0-smoothstep(.72,.90,radius));
	color += vec3(.025,.12,.16)*rim*time_stop;
	float separation = rush*.85;
	color.r = mix(color.r,texture(screen_texture,uv+vec2(pixel.x*separation,0.0)).r,rush*.30);
	color.b = mix(color.b,texture(screen_texture,uv-vec2(pixel.x*separation,0.0)).b,rush*.30);
	color += vec3(.025,.045,.08)*rim*rush;
	// Entry freeze: desaturated, inverted-blue impact frame for the hold.
	float freeze_lum = dot(color,vec3(.2126,.7152,.0722));
	vec3 frozen_grade = mix(vec3(freeze_lum),color,.25)*vec3(.82,.98,1.22)+vec3(.0,.02,.05);
	color = mix(color,frozen_grade,rush_freeze*.85);
	float speed_lines = 0.0;
	if (rush > .01) {
		vec2 rd = (uv-rush_uv)*vec2(aspect,1.0);
		float ang = atan(rd.y,rd.x);
		float streak = step(.86,fract(sin(floor(ang*38.0)*91.7)*437.5+art_clock*7.0));
		speed_lines = streak*smoothstep(.28,.62,length(rd))*rush;
	}
	color += vec3(.70,.92,1.0)*speed_lines*.18;
	// Flashlight: cone of light plus a small halo; outside stays dim, never black.
	if (flashlight > .001) {
		vec2 ld = (uv-light_uv)*vec2(aspect,1.0);
		float dist = length(ld);
		vec2 fwd = normalize(light_dir*vec2(aspect,1.0)+vec2(.0001));
		float along = dot(ld,fwd);
		float cone_cos = dot(ld/max(dist,.0001),fwd);
		float cone = smoothstep(.72,.9,cone_cos)*(1.0-smoothstep(.34,.85,along))*step(0.0,along);
		float halo = 1.0-smoothstep(.09,.26,dist);
		float lit = clamp(max(cone,halo),0.0,1.0);
		float flicker = .985+.015*sin(art_clock*23.0)*sin(art_clock*7.3);
		vec3 dim = mix(vec3(dot(color,vec3(.2126,.7152,.0722))),color,.55)*vec3(.62,.78,.92);
		vec3 lit_color = color*(1.10+cone*.18)*vec3(1.04,1.0,.92);
		color = mix(mix(color,dim*light_dim,flashlight),lit_color,lit*flashlight*flicker);
	}
	// Combo heat on the screen frame; breathes with the art clock.
	float frame = smoothstep(.48,.92,radius);
	color += combo_color*frame*combo_heat*(.10+.05*sin(art_clock*6.0));
	float mono = dot(color,vec3(.2126,.7152,.0722));
	vec3 phosphor = vec3(mono*.70,mono*.99,mono*1.15);
	phosphor += vec3(.022,.014,.047)*(1.0-smoothstep(.05,.55,mono));
	phosphor = mix(phosphor,color,.14);
	float scan = mix(.80,1.025,step(1.0,mod(floor(SCREEN_UV.y/pixel.y),3.0)));
	float shadow_mask = .97+.03*step(1.0,mod(floor(SCREEN_UV.x/pixel.x),3.0));
	phosphor *= scan*shadow_mask;
	phosphor += vec3(.035,.075,.09)*halo;
	color = mix(color,phosphor,crt_amount*.97);
	color += vec3(.06,.10,.14)*(sync_band+sync_echo)*entry*.5;
	color = mix(color,flash_color,flash_amount*(1.0-radius*.35));
	float impact_envelope = slam*(.45+.55*focus)*(1.0-slam_reduced*.65);
	vec3 impact_grade = mix(color,vec3(dot(color,vec3(.2126,.7152,.0722))),.32)*vec3(1.07,1.005,.90);
	color = mix(color,impact_grade,impact_envelope);
	color += vec3(.17,.105,.045)*slam*focus*(1.0-slam_reduced*.75);
	color *= 1.0-smoothstep(.32,.83,radius)*slam*.17*(1.0-slam_reduced*.7);
	color += vec3(.75,.61,.38)*kill_amount*(.3+.7*(1.0-smoothstep(.1,.7,radius)));
	vec3 prism = warp_hue(fract(warp_distance*1.6-warp_age*1.2+atan(warp_delta.y,warp_delta.x)*.16));
	color += prism*warp_front*.20*warp_scale+vec3(1.0,.95,.88)*warp_core*.35*warp_scale;
	COLOR = vec4(mix(original,clamp(color,vec3(0.0),vec3(1.0)),strength),1.0);
}
