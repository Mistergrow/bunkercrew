shader_type canvas_item;

// The original atlas fixes the silhouette, rim, mounting hub and light direction.
// Only the cylindrical skin and the blades inside its opening rotate.
uniform vec4 atlas_region;
uniform sampler2D shell_texture : source_color, filter_nearest, repeat_enable;
uniform sampler2D paddle_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 paddle_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool has_shell = false;
uniform bool has_paddle = false;
uniform float turn_phase = 0.0;
varying vec4 modulation;

void vertex() {
	modulation = COLOR;
}

vec4 paddle_sample(vec2 point, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	vec2 turned = vec2(c * point.x + s * point.y, -s * point.x + c * point.y);
	vec2 blade_uv = (turned - vec2(0.0, -0.47)) / vec2(0.50, 0.98) + vec2(0.5);
	vec4 blade = texture(paddle_texture, paddle_region.xy + clamp(blade_uv, vec2(0.0), vec2(1.0)) * paddle_region.zw);
	blade.a *= step(0.5, blade.a);
	blade.a *= step(0.0, blade_uv.x) * step(blade_uv.x, 1.0) * step(0.0, blade_uv.y) * step(blade_uv.y, 1.0);
	return blade;
}

void fragment() {
	vec4 original = texture(TEXTURE, UV);
	vec2 local_uv = (UV - atlas_region.xy) / atlas_region.zw;
	// One world pixel is the smallest cluster; texture motion never produces
	// smooth subpixel swirls that clash with the surrounding machinery.
	vec2 pixel = floor(local_uv * vec2(74.0, 65.0)) + vec2(0.5);
	vec2 from_mouth = pixel - vec2(18.5, 19.0);
	vec2 axis = vec2(0.83646, 0.54802);
	vec2 cross_axis = vec2(-axis.y, axis.x);
	float along = dot(from_mouth, axis);
	float across = dot(from_mouth, cross_axis);
	vec2 mouth = vec2(along / 9.2, across / 18.1);
	float mouth_radius = length(mouth);
	vec3 result = original.rgb;
	if (has_shell && original.a > 0.2 && mouth_radius > 1.30 && along > -7.0 && along < 45.0) {
		float cylinder_radius = mix(24.0, 22.0, smoothstep(8.0, 43.0, along));
		float side = clamp(across / cylinder_radius, -0.995, 0.995);
		float around = asin(side) / TAU;
		vec2 skin_uv = vec2(clamp((along + 7.0) / 53.0, 0.0, 1.0), fract(around + turn_phase));
		vec3 skin = texture(shell_texture, skin_uv).rgb;
		// Blend a narrow wrap seam into the middle of the same painted surface.
		// Both sides converge to the identical texel as the drum completes a turn.
		float seam_distance = min(skin_uv.y, 1.0 - skin_uv.y);
		float seam_blend = 1.0 - smoothstep(0.0, 0.035, seam_distance);
		skin = mix(skin, texture(shell_texture, vec2(skin_uv.x, fract(skin_uv.y + 0.5))).rgb, seam_blend);
		// Original shadows remain tied to the room lights. A small neighbourhood
		// keeps fixed scratches from fighting with the moving painted steel.
		vec2 tap = TEXTURE_PIXEL_SIZE * 5.0;
		vec3 lighting = (original.rgb + texture(TEXTURE, UV + vec2(tap.x, 0.0)).rgb + texture(TEXTURE, UV - vec2(tap.x, 0.0)).rgb + texture(TEXTURE, UV + vec2(0.0, tap.y)).rgb + texture(TEXTURE, UV - vec2(0.0, tap.y)).rgb) * 0.2;
		float shade = clamp(dot(lighting, vec3(0.62, 0.28, 0.10)) / 0.64, 0.24, 1.13);
		float edge = smoothstep(0.055, 0.20, max(original.r, max(original.g, original.b)));
		float shell_mask = edge * smoothstep(1.30, 1.43, mouth_radius) * (1.0 - smoothstep(42.0, 45.0, along));
		result = mix(result, skin * shade, shell_mask * 0.92);
	}
	if (has_paddle && mouth_radius < 0.84 && original.a > 0.5) {
		float turn = turn_phase * TAU;
		vec4 blade_a = paddle_sample(mouth, turn);
		vec4 blade_b = paddle_sample(mouth, turn + PI);
		float recess = 0.46 + 0.16 * clamp(-mouth.y, -1.0, 1.0);
		result = mix(result, blade_a.rgb * recess, blade_a.a * 0.94);
		result = mix(result, blade_b.rgb * recess, blade_b.a * 0.94);
	}
	COLOR = vec4(result, original.a) * modulation;
}
