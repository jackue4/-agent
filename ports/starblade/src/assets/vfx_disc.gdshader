shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.3, 0.9, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float style = 0.0;
uniform float rotation_offset = 0.0;

float band(float value, float center, float width) {
	return 1.0 - smoothstep(width * 0.35, width, abs(value - center));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float angle = atan(p.y, p.x) + rotation_offset;
	float sweep = 1.0 - pow(1.0 - progress, 2.6);
	float radius = mix(0.06, 0.94, sweep);
	float core = band(r, radius, 0.024);
	float trail = band(r, radius - 0.025, 0.07) * 0.20;
	float detail = 0.0;
	if (style > 0.5 && style < 1.5) {
		// Sparse circuit glyphs and broken concentric rings, no filled disc.
		float spokes = pow(max(0.0, cos(angle * 12.0)), 16.0);
		float ticks = step(0.8, cos(angle * 24.0));
		core = band(r, 0.73, 0.022) * (0.25 + 0.75 * step(-0.4, sin(angle * 6.0)));
		detail = band(r, 0.92, 0.020) * ticks + band(r, 0.47, 0.018) * 0.5;
		detail += spokes * smoothstep(0.50, 0.54, r) * (1.0 - smoothstep(0.62, 0.66, r)) * 0.7;
		trail = band(r, 0.73, 0.05) * 0.10;
	} else if (style > 1.5 && style < 2.5) {
		// A broad leading ring with small trailing radial fractures.
		float cracks = pow(max(0.0, sin(angle * 17.0 + sin(angle * 5.0) * 1.8)), 28.0);
		detail = cracks * smoothstep(radius - 0.19, radius - 0.12, r) * (1.0 - smoothstep(radius - 0.01, radius + 0.01, r));
		trail += band(r, radius * 0.78, 0.012) * 0.22;
	} else if (style > 3.5) {
		float minutes = step(.965,cos(angle*60.0));
		float hours = step(.94,cos(angle*12.0));
		core = band(r,.88,.020)+band(r,.69,.009)*.45;
		detail = minutes*smoothstep(.77,.80,r)*(1.-smoothstep(.85,.88,r));
		detail += hours*smoothstep(.70,.73,r)*(1.-smoothstep(.84,.88,r));
		float broken = step(-.55,sin(angle*4.0));
		detail += band(r,.96,.013)*broken*.7+band(r,.18,.015)*.6;
		trail = band(r,.88,.055)*.12;
	} else if (style > 2.5) {
		float spokes = pow(max(0.0, cos(angle * 6.0)), 40.0);
		core = band(r, 0.62, 0.014) * 0.6;
		detail = spokes * smoothstep(0.18, 0.23, r) * (1.0 - smoothstep(0.86, 0.93, r));
		trail = band(r, 0.62, 0.055) * 0.12;
	}
	float fade = min(progress * 14.0 + 0.12, 1.0) * pow(1.0 - progress, 0.8);
	vec3 ink = mix(tint.rgb, vec3(1.0, 0.98, 0.90), core * 0.72);
	ALBEDO = ink;
	EMISSION = ink * 0.85;
	ALPHA = clamp(core * 0.85 + trail + detail * 0.55, 0.0, 1.0) * fade * opacity * tint.a;
}
