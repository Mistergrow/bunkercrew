shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float light_clock = 0.0;
uniform float phase = 0.0;
uniform float strength = 0.30;
uniform float edge_fade = 0.035;
uniform bool allow_white = false;
uniform vec2 source_center = vec2(0.5);
uniform vec2 source_radius = vec2(0.02);
varying float flicker;
varying vec4 light_tint;

void vertex() {
	// Shared clock, evaluated at the four corners instead of every fragment.
	flicker = 0.82 + sin(light_clock * 1.8 + phase) * 0.12;
	flicker += sin(light_clock * 3.1 + phase * 1.7) * 0.06;
	light_tint = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec2 local = (UV - source_center) / source_radius;
	float edge = max(0.0, 1.0 - dot(local, local));
	float warm = smoothstep(0.035, 0.18, source.r - max(source.g, source.b));
	warm *= smoothstep(0.18, 0.55, source.r);
	float white = allow_white ? smoothstep(0.65, 0.92, min(source.r, min(source.g, source.b))) : 0.0;
	// Only actual lit paint emits. Dark steel and the region's borders stay clear.
	float opacity = max(warm, white) * edge * edge * source.a;
	// The panorama blends into its edge extension as the camera widens. Its
	// painted emitters must fade with it, especially harbor/viaduct edge lamps.
	float panorama_edge = smoothstep(0.0, edge_fade, UV.x) * (1.0 - smoothstep(1.0 - edge_fade, 1.0, UV.x));
	opacity *= panorama_edge;
	COLOR = vec4(source.rgb * light_tint.rgb, opacity * strength * flicker * light_tint.a);
}
