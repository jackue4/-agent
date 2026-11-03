shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 beam_color : source_color = vec4(0.2,0.9,1.0,1.0);
uniform float strength = 1.0;
void fragment() {
 float height_fade = pow(UV.y, 1.6);
 float bands = 0.65 + 0.2*sin(UV.y*40.0-TIME*4.0) + 0.15*sin(UV.x*38.0+TIME*2.0);
 ALBEDO = beam_color.rgb;
 EMISSION = beam_color.rgb * 1.8;
 ALPHA = height_fade * bands * 0.62 * strength;
}
