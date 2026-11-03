shader_type canvas_item;
render_mode unshaded;
uniform float amount = 0.0;
void fragment() {
	// A stationary, extremely light scan layer connects HUD to the CRT presentation.
	// No screen texture, distortion, flashing, or mouse interception above the HUD.
	float scan = 1.0-step(1.0,mod(floor(SCREEN_UV.y/SCREEN_PIXEL_SIZE.y),3.0));
	COLOR = vec4(.015,.055,.09,scan*amount*.045);
}
