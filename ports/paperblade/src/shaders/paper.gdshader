shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D tex : source_color, filter_linear, repeat_disable;
// Regular (per-material) uniforms: instance uniforms render black on WebGL2 / GL Compatibility.
uniform float flash = 0.0;
uniform vec4 tint = vec4(1.0);
uniform float flip = 0.0;
uniform float energy = 1.0;

void fragment() {
	vec2 uv = UV;
	if (flip > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	vec4 c = texture(tex, uv);
	vec3 col = c.rgb * tint.rgb * max(energy, 0.0);
	col = mix(col, vec3(1.0), clamp(flash, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
