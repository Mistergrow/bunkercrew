shader_type canvas_item;
global uniform float beat_pulse;
// Shade the machine's existing opaque pixels. No extra glow card, screen read,
// texture lookup or alpha expansion; labels and the fire itself stay untouched.
uniform vec4 chamber = vec4(0.0);
uniform vec3 heat_tint : source_color = vec3(1.0, 0.48, 0.16);
uniform float heat_strength = 0.0;
uniform vec4 power_contact_a = vec4(0.0);
uniform vec4 power_contact_b = vec4(0.0);
uniform vec3 power_tint : source_color = vec3(0.58, 0.78, 0.72);
uniform float power_strength = 0.0;
uniform float effect_phase = 0.0;
varying vec2 surface_pixel;

void vertex() {
	surface_pixel = VERTEX;
}

float rectangle_distance(vec2 pixel, vec4 bounds) {
	vec2 distance = abs(pixel - bounds.xy - bounds.zw * 0.5) - bounds.zw * 0.5;
	return length(max(distance, vec2(0.0))) + min(max(distance.x, distance.y), 0.0);
}

void fragment() {
	vec4 original = COLOR;
	if (original.a > 0.96 && surface_pixel.y >= -120.0 && surface_pixel.y < -5.0) {
		vec2 pixel = floor(surface_pixel) + vec2(0.5);
		vec3 light = vec3(0.0);
		// A short falloff around the chamber reveals warm mortar and worn steel.
		// Its negative distance excludes existing flame and arc drawing entirely.
		if (heat_strength > 0.0) {
			float distance = rectangle_distance(pixel, chamber);
			float rim = step(0.0, distance) * (1.0 - smoothstep(0.0, 16.0, distance));
			float facing = mix(0.60, 1.0, smoothstep(chamber.y - 12.0, chamber.y + chamber.w, pixel.y));
			float metal_detail = smoothstep(0.04, 0.46, max(original.r, max(original.g, original.b)));
			light += heat_tint * heat_strength * (1.0 + clamp(beat_pulse, 0.0, 1.0) * 0.24) * rim * facing * metal_detail;
		}
		if (power_strength > 0.0) {
			float first = rectangle_distance(pixel, power_contact_a);
			float second = rectangle_distance(pixel, power_contact_b);
			float contact = 1.0 - smoothstep(0.0, 7.0, min(first, second));
			// Uneven ribs pick up travelling light; the equipment never turns into
			// a smooth neon tube and black recesses keep their depth.
			float rib = mix(0.46, 1.0, step(0.58, fract(pixel.y * 0.143 - effect_phase)));
			float metal_detail = smoothstep(0.035, 0.52, max(original.r, max(original.g, original.b)));
			light += power_tint * power_strength * (1.0 + clamp(beat_pulse, 0.0, 1.0) * 0.20) * contact * rib * metal_detail;
		}
		// Screen-like material response preserves scratches and prevents clipping.
		COLOR = vec4(original.rgb + (vec3(1.0) - original.rgb) * light, original.a);
	}
}
