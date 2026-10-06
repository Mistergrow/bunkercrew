shader_type canvas_item;
#include "res://shaders/background_sampling.gdshaderinc"
varying vec4 modulation;
void vertex() { modulation = COLOR; }
void fragment() {
	vec2 background_coords = UV;
	#include "res://shaders/background_fragment.gdshaderinc"
	COLOR = modulation * painted;
}
