shader_type canvas_item;
// The fallen pack and sleeves settle behind the actual support plane.
// Local feet are at y=0; no screen texture, timer or per-frame uniforms.
varying float ground_height;
void vertex() { ground_height=VERTEX.y; }
void fragment() {
	if (ground_height>0.0) { discard; }
}
