shader_type canvas_item;
// The slow shielded work-lamp variation is evaluated on the GPU. Only the
// source lamp glass changes; posts, mesh and the fixed contact feet stay still.
// The lamp glass in UV (x0, y0, x1, y1): the module atlas by default, its
// world-texel bake when CourtyardArt draws that.
uniform vec4 glass_rect = vec4(0.207, 0.631, 0.241, 0.682);
varying vec4 source_tint;
void vertex() {
	source_tint = COLOR;
}
void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	if (ink.a < 0.5) { discard; }
	float glass = step(glass_rect.x,UV.x) * step(UV.x,glass_rect.z) * step(glass_rect.y,UV.y) * step(UV.y,glass_rect.w);
	float warmth = glass * step(ink.g,ink.r * 0.9) * step(0.45,ink.r);
	ink.rgb *= mix(1.0,0.92 + 0.08 * sin(TIME * 0.83),warmth);
	COLOR = vec4(ink.rgb,1.0) * source_tint;
}
