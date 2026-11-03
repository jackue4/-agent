shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0,.37,.12,1.0);
uniform float progress = 0.0;
uniform float opacity = 1.0;
uniform float warning = 0.0;

float band(float r, float at, float width) {
	return 1.0-smoothstep(width*.25,width,abs(r-at));
}

void fragment() {
	vec2 p = (UV-.5)*2.0;
	float r = length(p);
	float a = atan(p.y,p.x);
	float tick = step(.94,cos(a*12.0));
	float mask = 1.0-smoothstep(.97,1.0,r);
	float body = 0.0;
	float core = 0.0;
	float fade = 1.0;
	float seam = 0.0;
	float heat = 0.0;
	if(warning>.5) {
		// Radius never grows: this is the exact area that will be struck.
		core = band(r,.98,.018);
		body = band(r,.88,.009)*step(-.6,sin(a*6.0));
		body += tick*smoothstep(.79,.82,r)*(1.0-smoothstep(.93,.95,r))*.65;
		float converge = mix(.78,.17,progress);
		body += band(r,converge,.016)*.45;
		body += band(p.x,0.0,.014)*(1.0-smoothstep(.10,.23,abs(p.y)));
		body += band(p.y,0.0,.014)*(1.0-smoothstep(.10,.23,abs(p.x)));
		fade = .55+progress*.45;
	} else {
		float radial_sector = floor((a+3.14159)/6.28318*12.0);
		float jagged = sin(floor(r*13.0)*2.17+radial_sector*1.41)*.26;
		float fracture = abs(sin(a*12.0+jagged));
		float extent = smoothstep(.10,.18,r)*(1.0-smoothstep(.69,.92,r));
		seam = (1.0-smoothstep(.035,.18,fracture))*extent;
		heat = (1.0-smoothstep(.016,.065,fracture))*extent;
		float reach = 1.0-pow(1.0-progress,4.0);
		core = band(r,mix(.10,.96,reach),.030)*(1.0-progress)*.65;
		body = seam*.85;
		body += band(r,.55,.012)*step(.2,cos(a*7.0))*.25;
		body *= smoothstep(0.0,.06,progress);
		fade = pow(1.0-progress,1.1);
	}
	vec3 ink = mix(tint.rgb,vec3(1.0,.95,.77),clamp(core,0.0,1.0)*.84);
	ALBEDO = ink;
	EMISSION = ink*.8;
	if(warning<.5) {
		ALBEDO = mix(vec3(.10,.022,.007),tint.rgb,clamp(core+heat*.75,0.0,1.0));
		EMISSION = vec3(1.0,.23,.025)*heat*.72+ink*core*.55;
	}
	ALPHA = clamp(core+body,0.0,1.0)*mask*fade*opacity;
}
