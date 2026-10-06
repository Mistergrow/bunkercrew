// Include inside fragment(), with background_coords set by the caller.
// Sample the built-in texture here; sampler arguments trigger an error in
// Godot's headless shader compiler, and TEXTURE is only visible in fragment().
vec2 center_uv = background_uv(background_coords, TEXTURE_PIXEL_SIZE);
vec4 painted = texture(TEXTURE, center_uv);
if (detail_strength > 0.0 || contour_strength > 0.0) {
	vec2 radius = TEXTURE_PIXEL_SIZE * sample_radius;
	painted = background_detail(painted,
		texture(TEXTURE, center_uv - vec2(radius.x, 0.0)),
		texture(TEXTURE, center_uv + vec2(radius.x, 0.0)),
		texture(TEXTURE, center_uv - vec2(0.0, radius.y)),
		texture(TEXTURE, center_uv + vec2(0.0, radius.y)));
}
