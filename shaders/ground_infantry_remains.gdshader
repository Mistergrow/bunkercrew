shader_type canvas_item;
// The fallen pack and sleeves settle behind the actual support plane.
// Every body part is drawn with its own bone transform, so VERTEX is local to
// that part (a head tile is centred on its origin). The support plane is
// therefore compared in world space; the level is written once per corpse.
// No screen texture or timer; `dissolve` changes only while the body leaves.
instance uniform float ground_level = 1000000.0;
// Share of world texels already gone: the corpse leaves texel by texel in the
// ordered dither of the shared effect grid instead of fading translucent.
instance uniform float dissolve = 0.0;
varying float world_height;
varying vec4 tint;
#include "res://shaders/pixel_effect_grid.gdshaderinc"

void vertex() {
	vec2 world = (MODEL_MATRIX*vec4(VERTEX,0.0,1.0)).xy;
	world_height = world.y;
	grid_world = world;
	tint = COLOR;
}

void fragment() {
	if (world_height>ground_level) { discard; }
	vec2 texel = floor(grid_world);
	if (dissolve > 0.0 && grid_order(texel, 0) < dissolve) { discard; }
	// A toppling torso, head or weapon is a rotated texture. Every pixel of a
	// world texel samples the source texel under that texel's centre, so the
	// parts step in whole texels as they turn instead of shimmering at screen
	// resolution. Untextured limbs sample the white default texture: unchanged.
	mat2 screen_to_world = mat2(dFdx(grid_world), dFdy(grid_world));
	if (abs(determinant(screen_to_world)) > 1e-6) {
		mat2 screen_to_uv = mat2(dFdx(UV), dFdy(UV));
		vec2 centre = UV + screen_to_uv * inverse(screen_to_world) * (texel + 0.5 - grid_world);
		COLOR = texture(TEXTURE, centre) * tint;
	}
}
