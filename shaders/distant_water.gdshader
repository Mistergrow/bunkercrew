shader_type canvas_item;
render_mode unshaded;

uniform sampler2D panorama_water : filter_nearest, repeat_disable;
uniform vec2 source_water = vec2(0.64, 0.86);
uniform vec2 source_pixel = vec2(0.00046, 0.00138);
uniform vec4 top_left : source_color;
uniform vec4 top_right : source_color;
uniform vec4 bottom_left : source_color;
uniform vec4 bottom_right : source_color;
uniform float water_top = 304.64;
uniform float water_height = 125.36;
uniform float water_clock = 0.0;
uniform float turbulence = 0.45;
uniform float motion_strength = 1.0;
varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 point = floor(world_position);
	float depth = clamp((point.y - water_top) / water_height, 0.0, 1.0);
	float across = clamp((point.x + 2000.0) / 5600.0, 0.0, 1.0);
	vec3 near_color = mix(bottom_left.rgb, bottom_right.rgb, across);
	vec3 far_color = mix(top_left.rgb, top_right.rgb, across);
	vec3 base = mix(far_color, near_color, depth);
	// Unequal traveling ripples and horizontal reflection fragments retain the
	// existing panorama's pixel scale. Supplied scene time makes pause exact.
	float row = floor(point.y * 0.5) * 2.0;
	float swell = sin(row * 0.105 - water_clock * 1.35 + sin(point.x * 0.017 + water_clock * 0.19) * 1.35);
	float ripple = sin(row * 0.31 + point.x * 0.013 + water_clock * 2.3);
	float wave = swell * 0.65 + ripple * 0.35;
	float drift = wave * (1.5 + depth * 3.0) * motion_strength;
	// Mirror a water-only source strip, preserving the fine painted ripples.
	// No sky, ship or dam pixels can be sampled by this extension.
	float horizontal = (point.x + drift) / 1728.0;
	float mirrored = 1.0 - abs(fract(horizontal * 0.5) * 2.0 - 1.0);
	vec2 uv = vec2(mix(0.025, 0.975, mirrored), mix(source_water.x + source_pixel.y * 2.0, source_water.y - source_pixel.y * 2.0, depth));
	vec3 painted = texture(panorama_water, uv).rgb;
	vec2 lower_uv = vec2(uv.x, min(source_water.y - source_pixel.y, uv.y + source_pixel.y * 4.0));
	vec3 neighbor = texture(panorama_water, lower_uv).rgb;
	float detail = dot(painted - neighbor, vec3(0.299, 0.587, 0.114));
	float crest = smoothstep(0.55, 0.92, wave) * (0.011 + turbulence * 0.009) * motion_strength;
	vec3 water = base * (0.96 + wave * 0.028 * motion_strength) + detail * 0.48 + vec3(0.56, 0.74, 0.77) * crest;
	COLOR = vec4(max(water, vec3(0.0)), 1.0);
}
