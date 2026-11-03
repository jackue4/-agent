shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled;

uniform sampler2D scene_color : hint_screen_texture, filter_linear;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest;
uniform vec4 level_rects[32];
uniform int level_rect_count = 0;
uniform float blur_spacing : hint_range(0.0, 3.0) = 2.4;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = textureLod(scene_depth, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 view_position = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_position /= view_position.w;
	vec3 world_position = (INV_VIEW_MATRIX * view_position).xyz;
	bool on_level = false;
	// Classify the visible surface, not screen distance from the player. Every
	// room, corridor, actor and raised cover stays sharp as the camera moves.
	if (world_position.y > -2.0) {
		for (int i = 0; i < level_rect_count; i++) {
			vec4 r = level_rects[i];
			if (world_position.x >= r.x && world_position.z >= r.y &&
				world_position.x <= r.z && world_position.z <= r.w) {
				on_level = true;
				break;
			}
		}
	}
	vec3 color = textureLod(scene_color, SCREEN_UV, 0.0).rgb;
	if (!on_level && level_rect_count > 0) {
		// Explicit Gaussian taps work in Compatibility too, where spatial screen
		// textures do not reliably supply blur mipmaps. No offset ghost outlines.
		vec2 px = 1.0 / vec2(textureSize(scene_color, 0));
		vec3 soft = vec3(0.0);
		float total = 0.0;
		for (int y = -4; y <= 4; y++) {
			for (int x = -4; x <= 4; x++) {
				vec2 offset = vec2(float(x),float(y));
				float weight = exp(-dot(offset,offset)/9.0);
				soft += textureLod(scene_color,clamp(SCREEN_UV+offset*px*blur_spacing,vec2(.001),vec2(.999)),0.0).rgb*weight;
				total += weight;
			}
		}
		soft /= total;
		float gray = dot(soft, vec3(.2126, .7152, .0722));
		color = mix(vec3(gray), soft, .68) * .90;
	}
	ALBEDO = color;
	ALPHA = 1.0;
}
