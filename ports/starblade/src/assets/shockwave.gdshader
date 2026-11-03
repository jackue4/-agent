shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 wave_color : source_color = vec4(0.2,0.9,1.0,1.0);
uniform float progress = 0.0;
uniform float start_ratio = 0.05;
void fragment() {
 float radius = length((UV-0.5)*2.0);
 float ring = mix(start_ratio,0.98,progress);
 float band = 1.0-smoothstep(0.006,0.026,abs(radius-ring));
 float trail = (1.0-smoothstep(0.0,0.12,ring-radius))*step(radius,ring);
 ALBEDO = wave_color.rgb;
 EMISSION = wave_color.rgb * 1.5;
 ALPHA = (band*0.75 + trail*0.1) * (1.0-progress);
}
