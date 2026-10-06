shader_type canvas_item;

// Only source texture coverage is thresholded. Contact shadows and vertex
// tint keep their intended alpha, even when several piles share this material.
varying vec4 source_tint;
uniform float pulse_amount : hint_range(0.0, 0.05) = 0.03;
uniform float pulse_period : hint_range(1.0, 6.0) = 2.8;

void vertex() {
	source_tint = COLOR;
	// Real pickups draw around local (0, 0), their unchanged ground contact.
	// One shared material animates cached draw commands; no per-pile callbacks.
	float phase = TIME * (6.28318530718 / pulse_period) + MODEL_MATRIX[3].x * 0.017;
	VERTEX *= 1.0 + pulse_amount * sin(phase);
}

void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	if (ink.a < 0.5) { discard; }
	COLOR = vec4(ink.rgb, 1.0) * source_tint;
}
