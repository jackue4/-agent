shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
// Regular (per-material) uniforms: instance uniforms render black on WebGL2 / GL Compatibility.
uniform vec4 tint = vec4(1.0);
uniform float energy = 1.0;
uniform float flash = 0.0;
uniform float flip = 0.0;

void fragment() {
	vec2 uv = UV;
	if (flip > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	vec4 c = texture(tex, uv);
	ALBEDO = c.rgb * tint.rgb * (energy + flash);
	ALPHA = c.a * tint.a;
}
