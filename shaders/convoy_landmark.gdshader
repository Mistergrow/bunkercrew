shader_type canvas_item;
render_mode unshaded;
uniform bool cloth_motion = false;
uniform float phase = 0.0;
uniform float animation_time = 0.0;
uniform float motion_gain = 1.0;
uniform float sprite_height = 180.0;
void vertex() {
	if (cloth_motion) {
		// Bend the suspended tarp gently; the axle and wheel contact stay fixed.
		float top_weight = pow(clamp(1.0 - VERTEX.y / max(sprite_height, 1.0), 0.0, 1.0), 2.0);
		float gust = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(animation_time * 0.43 + phase), 3.0);
		VERTEX.x += sin(animation_time * 1.65 + phase + VERTEX.x * 0.013) * top_weight * gust * 3.0 * motion_gain;
	}
}
void fragment() {
	vec4 sample_color = texture(TEXTURE, UV);
	if (sample_color.a < 0.5) { discard; }
	COLOR *= vec4(sample_color.rgb, 1.0);
}
