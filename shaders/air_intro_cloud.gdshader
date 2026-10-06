shader_type canvas_item;
render_mode unshaded;

uniform vec4 source_region = vec4(0.0, 0.0, 0.5, 0.5);
uniform float cloud_clock = 0.0;
uniform float phase = 0.0;
uniform float morph_amount = 1.0;
uniform vec4 cloud_tint : source_color = vec4(1.0);
varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

void fragment() {
	// Deform the silhouette and inner billows together. Each cell has its own
	// phase; a padded local domain prevents sampling neighbouring atlas cells.
	vec2 local = UV;
	float clock = cloud_clock * 0.42 + phase;
	vec2 flow = vec2(
		sin(local.y * 11.0 + clock) + 0.45 * sin(local.x * 17.0 - clock * 0.61),
		cos(local.x * 12.0 - clock * 0.74) + 0.4 * sin(local.y * 19.0 + clock * 0.57));
	local += flow * 0.018 * morph_amount;
	vec2 pixel_size = TEXTURE_PIXEL_SIZE / source_region.zw;
	// Preserve the painted pixel clusters instead of smearing them under warp.
	local = (floor(local / pixel_size) + 0.5) * pixel_size;
	vec2 safe_local = clamp(local, pixel_size, vec2(1.0) - pixel_size);
	vec4 texel = texture(TEXTURE, source_region.xy + safe_local * source_region.zw);
	float inside = step(0.0, local.x) * step(local.x, 1.0) * step(0.0, local.y) * step(local.y, 1.0);
	float edge = smoothstep(0.0, 0.055, min(min(local.x, 1.0-local.x), min(local.y, 1.0-local.y)));
	// Palette by luminance also prevents saturated transparent-edge colour
	// from appearing as blue/cyan outlines over the dark cloud sea.
	float luminance = dot(texel.rgb, vec3(0.2126, 0.7152, 0.0722));
	COLOR = vec4(vec3(luminance) * cloud_tint.rgb, texel.a * inside * edge * cloud_tint.a) * vertex_tint;
}
