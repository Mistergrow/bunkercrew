shader_type canvas_item;

// The inherited CanvasItem uses nearest filtering, just like the standing mesh.
// Preserve its painted crown for the short fall; root and terrain remain fixed.
uniform float cut_local_y = -18.0;
uniform float ground_y = 430.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
varying float original_y;
varying vec2 world_position;
varying vec4 source_tint;

void vertex() {
	original_y = VERTEX.y;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	source_tint = COLOR;
}

void fragment() {
	if (original_y > cut_local_y || world_position.y >= ground_y) { discard; }
	vec4 painted = texture(TEXTURE, UV) * source_tint;
	painted.a *= opacity;
	if (painted.a < 0.04) { discard; }
	COLOR = painted;
}
