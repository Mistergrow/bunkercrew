shader_type canvas_item;
// Detached enemy wrecks (enemy_motion_wreck.gd): the parts of a destroyed
// machine as they fall, tumble and settle. Three things differ from the live
// actor material: no weather or team read on a dead hull; a tumbling or
// tilting part is rasterised in axis-aligned blocks of its own texel size
// (each block samples the source texel under its centre, anchored at the
// part origin), so it steps crisply instead of shimmering at screen
// resolution; and the wreck leaves texel by texel in the ordered dither of
// the shared effect grid (`dissolve`) instead of an alpha fade.
// Grid effect shapes (smoke drawn by a part) pass through as on live actors.
instance uniform float dissolve = 0.0;
varying vec4 tint;
varying vec2 part_origin;
varying float part_texel;
#include "res://shaders/pixel_effect_grid.gdshaderinc"

void vertex() {
	grid_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	part_origin = MODEL_MATRIX[3].xy;
	part_texel = max(length(MODEL_MATRIX[0].xy), 0.25);
	tint = COLOR;
}

void fragment() {
	vec2 texel = floor(grid_world);
	if (dissolve > 0.0 && grid_order(texel, 3) < dissolve) { discard; }
	if (UV.y > 30.0) {
		vec4 shaded = COLOR;
		if (!grid_shape(UV, shaded)) { discard; }
		COLOR = shaded;
	} else {
		mat2 screen_to_world = mat2(dFdx(grid_world), dFdy(grid_world));
		if (abs(determinant(screen_to_world)) > 1e-6) {
			vec2 block = part_origin + (floor((grid_world - part_origin) / part_texel) + 0.5) * part_texel;
			mat2 screen_to_uv = mat2(dFdx(UV), dFdy(UV));
			vec2 centre = UV + screen_to_uv * inverse(screen_to_world) * (block - grid_world);
			COLOR = texture(TEXTURE, centre) * tint;
		}
	}
}
