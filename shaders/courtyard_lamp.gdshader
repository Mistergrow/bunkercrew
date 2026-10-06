shader_type canvas_item;
// The slow shielded work-lamp variation is evaluated on the GPU. Only the
// source lamp glass changes; posts, mesh and the fixed contact feet stay still.
varying vec4 source_tint;
void vertex() {
	source_tint = COLOR;
}
void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	if (ink.a < 0.5) { discard; }
	float glass = step(0.207,UV.x) * step(UV.x,0.241) * step(0.631,UV.y) * step(UV.y,0.682);
	float warmth = glass * step(ink.g,ink.r * 0.9) * step(0.45,ink.r);
	ink.rgb *= mix(1.0,0.92 + 0.08 * sin(TIME * 0.83),warmth);
	COLOR = vec4(ink.rgb,1.0) * source_tint;
}
