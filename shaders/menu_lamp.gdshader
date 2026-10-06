shader_type canvas_item;
render_mode unshaded;

uniform float illumination = 1.0;
uniform float edge_fade = 0.035;
uniform bool allow_white = false;
uniform vec2 source_center = vec2(0.5);
uniform vec2 source_radius = vec2(0.02);

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec2 local = (UV - source_center) / source_radius;
	float edge = max(0.0, 1.0 - dot(local, local));
	float warm = smoothstep(0.035, 0.18, source.r - max(source.g, source.b));
	warm *= smoothstep(0.18, 0.55, source.r);
	float white = allow_white ? smoothstep(0.65, 0.92, min(source.r, min(source.g, source.b))) : 0.0;
	float mask = max(warm, white) * edge * edge;
	mask *= smoothstep(0.0, edge_fade, UV.x) * (1.0 - smoothstep(1.0 - edge_fade, 1.0, UV.x));
	// Repaint only existing luminous pixels. Normal blending allows a failing
	// lamp to dim as well as brighten without a rectangle or a global flash.
	COLOR = vec4(source.rgb * illumination, source.a * mask);
}
