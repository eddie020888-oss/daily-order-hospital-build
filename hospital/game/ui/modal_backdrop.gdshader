shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec4 veil : source_color = vec4(0.0863, 0.2353, 0.2392, 0.4392);

// Five binomial samples per axis at two output pixels give a two-pixel sigma.
// Sample the already rendered hospital and HUD before drawing the modal itself.
void fragment() {
	vec3 blurred = vec3(0.0);
	for (int y = -2; y <= 2; y++) {
		float wy = y == 0 ? 6.0 : (abs(y) == 1 ? 4.0 : 1.0);
		for (int x = -2; x <= 2; x++) {
			float wx = x == 0 ? 6.0 : (abs(x) == 1 ? 4.0 : 1.0);
			vec2 offset = vec2(float(x), float(y)) * SCREEN_PIXEL_SIZE * 2.0;
			blurred += texture(screen_texture, SCREEN_UV + offset).rgb * wx * wy;
		}
	}
	COLOR = vec4(mix(blurred / 256.0, veil.rgb, veil.a), 1.0);
}
