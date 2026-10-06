shader_type canvas_item;
render_mode unshaded;
uniform vec4 shadow_tint : source_color;
uniform vec4 light_tint : source_color;
uniform vec4 mist_tint : source_color;
uniform float distance_haze = 0.0;
void fragment() {
	vec4 sample_color = texture(TEXTURE, UV);
	float luminance = dot(sample_color.rgb, vec3(0.299, 0.587, 0.114));
	float detail = clamp((luminance - 0.12) / 0.48, 0.0, 1.0);
	vec3 terrain = mix(shadow_tint.rgb, light_tint.rgb, detail);
	terrain = mix(terrain, mist_tint.rgb, distance_haze);
	float edge = smoothstep(0.0, 0.16, UV.x) * (1.0 - smoothstep(0.84, 1.0, UV.x));
	float alpha = smoothstep(0.12, 0.60, sample_color.a);
	COLOR = vec4(terrain, alpha * edge);
}
