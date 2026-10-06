shader_type canvas_item;
render_mode unshaded;

uniform vec4 rock_tint : source_color = vec4(0.66, 0.63, 0.60, 1.0);
uniform vec4 seam_tint : source_color = vec4(0.51, 0.45, 0.40, 1.0);
uniform vec4 soil_tint : source_color = vec4(0.67, 0.59, 0.49, 1.0);
uniform float inclination = 0.21;
varying vec2 world_position;

float hash_point(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

float stone_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 fraction = fract(point);
	vec2 blend = fraction * fraction * (3.0 - 2.0 * fraction);
	return mix(mix(hash_point(cell), hash_point(cell + vec2(1.0, 0.0)), blend.x),
		mix(hash_point(cell + vec2(0.0, 1.0)), hash_point(cell + vec2(1.0)), blend.x), blend.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// Keep the original stone sizes and pixel clusters. The two texture offsets
	// crossfade only across broad geological pockets, breaking the 480px repeat.
	vec2 point = floor(world_position);
	float depth = max(0.0, point.y - 430.0);
	float deposits = stone_noise(point / vec2(330.0, 190.0));
	float broad = stone_noise(point / vec2(790.0, 310.0) + vec2(7.4, 2.1));
	vec2 rock_uv = vec2(point.x + 1850.0, depth) / 480.0;
	vec3 first_rock = texture(TEXTURE, fract(rock_uv)).rgb;
	vec3 second_rock = texture(TEXTURE, fract(rock_uv + vec2(0.413, 0.627))).rgb;
	float pocket = smoothstep(0.34, 0.68, deposits);
	vec3 rock = mix(first_rock, second_rock, pocket);
	// Irregular sediment bands cross several source tiles and are fixed in the
	// world. They tint the existing art rather than add floating ore or decals.
	float seam_depth = depth + point.x * inclination + (broad - 0.5) * 155.0;
	float band = sin(seam_depth * 0.034 + deposits * 1.4) * 0.5 + 0.5;
	float seam = smoothstep(0.66, 0.91, band) * 0.60;
	vec3 tint = mix(rock_tint.rgb, seam_tint.rgb, seam);
	float surface = 1.0 - smoothstep(10.0, 76.0, depth + deposits * 25.0);
	tint = mix(tint, soil_tint.rgb, surface * 0.50);
	float shade = mix(0.80, 1.17, broad) * mix(1.0, 0.43, smoothstep(130.0, 1250.0, depth));
	vec3 earth = rock * tint * shade;
	// The road's compacted upper lip uses the same unlimited field as the
	// geology, so a wide camera cannot reveal either end of a decorative strip.
	if (depth < 7.0) {
		float wear = hash_point(vec2(floor(point.x / 7.0), floor(depth / 2.0)));
		earth = soil_tint.rgb * mix(0.73, 0.84, wear);
	} else if (depth >= 8.0 && depth < 11.0) {
		float grit = step(0.40, fract(point.x / 19.0));
		earth = mix(earth, seam_tint.rgb * 0.56, grit * 0.65);
	}
	COLOR = vec4(earth, 1.0);
}
