shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 beam_color : source_color = vec4(0.2,0.9,1.0,1.0);
void fragment() {
 float vertical = pow(UV.y,0.75);
 float width = pow(max(0.0,1.0-abs(UV.x-0.5)*2.0),1.8);
 float pulse = 0.88+0.12*sin(TIME*3.0+UV.y*9.0);
 ALBEDO = beam_color.rgb;
 EMISSION = beam_color.rgb*2.5;
 ALPHA = width*vertical*pulse*0.65;
}
