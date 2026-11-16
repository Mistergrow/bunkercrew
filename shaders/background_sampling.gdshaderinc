// Preserve texel centers when magnifying; blend only across one screen pixel
// at an edge. Unlike point sampling, fractional camera movement stays smooth.
uniform float pixel_clarity : hint_range(0.0, 1.0) = 1.0;
uniform float detail_strength : hint_range(0.0, 1.5) = 1.0;
uniform float sample_radius : hint_range(1.0, 3.0) = 2.25;
uniform float contour_strength : hint_range(0.0, 0.4) = 0.22;
// World texel blocks (style bible §1, rule 5): the plate is sampled once per
// world unit of its own extent; world_block is the UV size of one unit (zero
// keeps the screen-pixel sampling of background_uv). ParallaxLandscape keeps
// the plate origin and size on whole world units, so a block is exactly one
// world texel on screen, never smaller than a figure's pixel, and scrolling
// moves whole blocks instead of crawling through them.
uniform vec2 world_block = vec2(0.0);
vec2 world_block_uv(vec2 uv) {
	return (floor(uv / world_block) + .5) * world_block;
}
// Prefilter level for a block: one bilinear tap averages the 2x2 source
// texels under a block up to two texels wide; wider blocks take mip levels.
float world_block_lod(vec2 texel_size) {
	return max(0.0, log2(max(world_block.x / texel_size.x, world_block.y / texel_size.y)) - 1.0);
}
vec2 background_uv(vec2 uv, vec2 texel_size) {
	if (pixel_clarity <= 0.0) { return uv; }
	vec2 pixels = uv / texel_size;
	vec2 footprint = max(fwidth(pixels), vec2(.001));
	vec2 box = min(footprint, vec2(1.0));
	vec2 shifted = pixels - .5 * box;
	vec2 coverage = smoothstep(vec2(1.0) - box, vec2(1.0), fract(shifted));
	vec2 crisp = (floor(shifted) + .5 + coverage) * texel_size;
	float magnification = clamp(2.0 - max(footprint.x, footprint.y), 0.0, 1.0);
	return mix(uv, crisp, pixel_clarity * magnification);
}
vec4 background_detail(vec4 center, vec4 left, vec4 right, vec4 above, vec4 below) {
	vec3 average = (left.rgb + right.rgb + above.rgb + below.rgb) * .25;
	vec3 low = min(center.rgb, min(min(left.rgb, right.rgb), min(above.rgb, below.rgb)));
	vec3 high = max(center.rgb, max(max(left.rgb, right.rgb), max(above.rgb, below.rgb)));
	// Never sharpen across an alpha silhouette or beyond existing local colors.
	float opaque = smoothstep(.98, 1.0, min(center.a, min(min(left.a, right.a), min(above.a, below.a))));
	// Painted material edges span several source texels. Broader neighbors
	// recover their local contrast; dark-side contours echo the bunker ink.
	vec3 luma = vec3(.299, .587, .114);
	float contrast = dot(high - low, luma);
	float dark_side = max(0.0, dot(average - center.rgb, luma));
	float contour = smoothstep(.025, .12, contrast) * clamp(dark_side / max(contrast, .001), 0.0, 1.0);
	vec3 detailed = center.rgb + (center.rgb - average) * detail_strength;
	detailed -= (high - low) * contour * contour_strength;
	center.rgb = mix(center.rgb, clamp(detailed, low, high), opaque);
	return center;
}
