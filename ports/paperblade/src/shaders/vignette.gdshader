shader_type canvas_item;

uniform vec4 col : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float strength = 0.5;
uniform float inner = 0.35;

void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.25, 1.0);
	float v = smoothstep(inner, 0.85, length(d));
	COLOR = vec4(col.rgb, v * strength);
}
