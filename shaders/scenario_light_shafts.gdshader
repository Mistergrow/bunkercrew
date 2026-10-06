shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float light_clock = 0.0;
uniform float edge_fade = 0.035;
uniform sampler2D sky_mask : filter_nearest, repeat_disable;
uniform vec4 panorama_bounds;
varying vec2 world_position;
varying vec4 shaft_tint;
varying float drift;

void vertex() {
	world_position = VERTEX;
	shaft_tint = COLOR;
	drift = sin(light_clock * 0.31) * 0.022;
}

void fragment() {
	// Broad, slightly broken light through haze, quantized to the art's pixels.
	vec2 point = floor(UV * vec2(180.0, 120.0)) / vec2(180.0, 120.0);
	float width = mix(0.075, 0.48, point.y);
	float center = 0.34 + point.y * 0.23 + drift;
	float cone = 1.0 - smoothstep(width * 0.55, width, abs(point.x - center));
	cone *= smoothstep(0.0, 0.12, point.y) * (1.0 - smoothstep(0.48, 1.0, point.y));
	float streak = 0.78 + sin((point.x - point.y * 0.23) * 67.0) * 0.15;
	vec2 local = (world_position - panorama_bounds.xy) / panorama_bounds.zw;
	float sky = texture(sky_mask, clamp(local, vec2(0.0), vec2(1.0))).r;
	float inside = step(0.0, local.x) * step(local.x, 1.0) * step(0.0, local.y) * step(local.y, 1.0);
	float panorama_edge = smoothstep(0.0, edge_fade, local.x) * (1.0 - smoothstep(1.0 - edge_fade, 1.0, local.x));
	COLOR = vec4(shaft_tint.rgb, cone * streak * shaft_tint.a * sky * inside * panorama_edge);
}
