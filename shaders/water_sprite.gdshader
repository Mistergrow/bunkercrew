shader_type canvas_item;
varying vec4 effect_tint;
void vertex() { effect_tint=COLOR; }
void fragment() {
	vec4 effect=texture(TEXTURE,UV);
	// The atlas preserves its generated alpha. Discard almost invisible export
	// residue so overlapping sprites cannot reveal rectangular tinted margins.
	effect.a*=smoothstep(0.008,0.025,effect.a);
	COLOR=effect*effect_tint;
}
