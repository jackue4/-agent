shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D atlas : source_color, filter_nearest;
uniform float progress = 0.0;
uniform float opacity = 1.0;

void fragment() {
	float frame = min(floor(clamp(progress, 0.0, .9999) * 6.0), 5.0);
	vec2 sprite_uv = vec2((UV.x + frame) / 6.0, UV.y);
	vec4 pixel = texture(atlas, sprite_uv);
	ALBEDO = pixel.rgb;
	EMISSION = pixel.rgb * .45;
	ALPHA = pixel.a * opacity * (1.0 - smoothstep(.78, 1.0, progress));
}
