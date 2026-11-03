shader_type spatial;
render_mode unshaded;

uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform float tile = 8.0;
uniform vec3 tint = vec3(1.0);
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = texture(tex, wpos.xz / tile).rgb * tint;
	// very soft, large-scale tonal drift so the floor never looks flat-tiled
	float n = sin(wpos.x * 0.031 + sin(wpos.z * 0.023) * 2.0) * sin(wpos.z * 0.037 + 1.3) * 0.5 + 0.5;
	c *= mix(0.94, 1.04, n);
	ALBEDO = c;
}
