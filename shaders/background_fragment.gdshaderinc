// Include inside fragment(), with background_coords set by the caller.
// Sample the built-in texture here; sampler arguments trigger an error in
// Godot's headless shader compiler, and TEXTURE is only visible in fragment().
vec2 center_uv;
vec4 painted;
if (world_block.x > 0.0) {
	// Stepped UVs have no useful derivatives: explicit levels, block centres.
	center_uv = world_block_uv(background_coords);
	float block_lod = world_block_lod(TEXTURE_PIXEL_SIZE);
	painted = textureLod(TEXTURE, center_uv, block_lod);
	if (detail_strength > 0.0 || contour_strength > 0.0) {
		// Local contrast between neighbouring blocks, at the block scale.
		painted = background_detail(painted,
			textureLod(TEXTURE, center_uv - vec2(world_block.x, 0.0), block_lod),
			textureLod(TEXTURE, center_uv + vec2(world_block.x, 0.0), block_lod),
			textureLod(TEXTURE, center_uv - vec2(0.0, world_block.y), block_lod),
			textureLod(TEXTURE, center_uv + vec2(0.0, world_block.y), block_lod));
	}
} else {
	center_uv = background_uv(background_coords, TEXTURE_PIXEL_SIZE);
	painted = texture(TEXTURE, center_uv);
	if (detail_strength > 0.0 || contour_strength > 0.0) {
		vec2 radius = TEXTURE_PIXEL_SIZE * sample_radius;
		painted = background_detail(painted,
			texture(TEXTURE, center_uv - vec2(radius.x, 0.0)),
			texture(TEXTURE, center_uv + vec2(radius.x, 0.0)),
			texture(TEXTURE, center_uv - vec2(0.0, radius.y)),
			texture(TEXTURE, center_uv + vec2(0.0, radius.y)));
	}
}
