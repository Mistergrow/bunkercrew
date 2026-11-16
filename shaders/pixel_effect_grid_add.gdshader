shader_type canvas_item;
render_mode blend_add, unshaded;
// Effect layer whose PixelEffectArt grid shapes step in whole world texels.
#include "res://shaders/pixel_effect_grid.gdshaderinc"

void vertex() {
	grid_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	if (UV.y > 30.0) {
		vec4 tint = COLOR;
		if (!grid_shape(UV, tint)) discard;
		COLOR = tint;
	}
}
