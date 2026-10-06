shader_type canvas_item;
render_mode unshaded;
uniform float top_fade = 0.12;
uniform vec4 atmosphere_tint : source_color = vec4(0.32, 0.40, 0.44, 1.0);
uniform float atmospheric_depth = 0.0;
uniform float layer_opacity = 1.0;
uniform float side_fade = 0.0;
varying vec4 vertex_tint;
void vertex() {
	vertex_tint = COLOR;
}
void fragment() {
	vec4 painted = texture(TEXTURE, UV);
	painted.rgb = mix(painted.rgb, atmosphere_tint.rgb, atmospheric_depth);
	painted.a *= smoothstep(0.0, max(top_fade, 0.001), UV.y) * layer_opacity;
	if (side_fade > 0.0) {
		painted.a *= smoothstep(0.0, side_fade, UV.x) * smoothstep(0.0, side_fade, 1.0 - UV.x);
	}
	COLOR = painted * vertex_tint;
}
