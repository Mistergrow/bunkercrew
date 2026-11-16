shader_type canvas_item;

// Only source texture coverage is thresholded. Contact shadows and vertex
// tint keep their intended alpha, even when several piles share this material.
varying vec4 source_tint;
uniform float pulse_amount : hint_range(0.0, 0.05) = 0.03;
uniform float pulse_period : hint_range(1.0, 6.0) = 2.8;
// Share of a fresh drop already materialised (1: whole). A drop that appears
// out of a defeated enemy builds up texel by texel in the shared ordered
// dither instead of popping in at full size; settled piles never set it.
instance uniform float reveal = 1.0;
#include "res://shaders/pixel_effect_grid.gdshaderinc"

void vertex() {
	source_tint = COLOR;
	// Real pickups draw around local (0, 0), their unchanged ground contact.
	// One shared material animates cached draw commands; no per-pile callbacks.
	float phase = TIME * (6.28318530718 / pulse_period) + MODEL_MATRIX[3].x * 0.017;
	VERTEX *= 1.0 + pulse_amount * sin(phase);
	grid_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	if (ink.a < 0.5) { discard; }
	if (reveal < 1.0 && grid_order(floor(grid_world), 5) >= reveal) { discard; }
	COLOR = vec4(ink.rgb, 1.0) * source_tint;
}
