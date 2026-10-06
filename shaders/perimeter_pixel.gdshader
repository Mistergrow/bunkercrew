shader_type canvas_item;
// The source atlas contains very faint generated fringe pixels. Threshold only
// texture coverage: vertex tint/health bars/contact shadows retain their alpha.
varying vec4 source_tint;
void vertex() {
	source_tint = COLOR;
}
void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	if (ink.a < 0.5) { discard; }
	COLOR = vec4(ink.rgb, 1.0) * source_tint;
}
