shader_type canvas_item;

// Applied only to character/machine art, never to the HUD or identity labels.
// Original texture alpha and material hue are retained; no full-sprite blue wash.
instance uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float wet_clock = 0.0;
uniform float metal : hint_range(0.0, 1.0) = 0.0;
uniform float art_top = -10000.0;
uniform bool opaque_only = false;
// Opt-in for the generated vehicle hulls; use texture alpha so death fades and
// vertex opacity remain continuous rather than clipping with the source edge.
uniform float sprite_alpha_cutoff : hint_range(0.0, 1.0) = 0.0;
varying vec2 art_position;

void vertex() {
	art_position = VERTEX;
}

void fragment() {
	vec4 original = COLOR;
	if (sprite_alpha_cutoff > 0.0 && texture(TEXTURE, UV).a < sprite_alpha_cutoff) {
		discard;
	}
	// Dry actors retain their exact input pixels and skip all material work.
	if (wetness > 0.001 && art_position.y >= art_top && original.a > 0.01 && (!opaque_only || original.a > 0.85)) {
		float luminous = max(step(original.g * 1.6 + 0.08, original.r), step(0.90, min(original.r, min(original.g, original.b))));
		float amount = wetness * (1.0 - luminous * 0.9);
		vec3 damp = original.rgb * mix(vec3(0.77, 0.82, 0.81), vec3(0.80, 0.86, 0.88), metal);
		float neutral = 1.0 - smoothstep(0.12, 0.30, max(original.r, max(original.g, original.b)) - min(original.r, min(original.g, original.b)));
		vec2 pixel = floor(art_position);
		// Stable arithmetic hash: no per-pixel sine just to pick wet flecks.
		vec2 hash = fract(pixel * vec2(0.1031, 0.11369));
		hash += dot(hash, hash.yx + 19.19);
		float grain = fract((hash.x + hash.y) * hash.x);
		float fleck = step(0.91, grain);
		float sheen = (0.5 + 0.5 * sin(wet_clock * 1.7 + pixel.y * 0.10 + pixel.x * 0.04));
		damp += vec3(0.12, 0.16, 0.17) * neutral * fleck * sheen * (0.35 + metal * 0.65) * smoothstep(0.12, 0.50, original.g);
		// Small downward-running highlights belong to saturated metal only.
		// They are anchored in local art pixels and never outline the sprite.
		if (metal > 0.01 && wetness > 0.55) {
			float rivulet = step(0.84, fract(pixel.x * 0.6180339)) * (1.0 - smoothstep(0.0, 0.20, fract(pixel.y * 0.065 - wet_clock * 0.32 + grain * 0.08)));
			damp += vec3(0.035, 0.05, 0.055) * rivulet * metal * neutral * smoothstep(0.55, 1.0, wetness);
		}
		COLOR = vec4(mix(original.rgb, damp, amount), original.a);
	}
}
