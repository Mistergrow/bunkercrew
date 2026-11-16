shader_type canvas_item;
// Painted backdrop: keeps its authored value under world ambient and lamps.
render_mode unshaded;
#include "res://shaders/background_sampling.gdshaderinc"
// Aerial-perspective veil over the painted plate (rgb colour, a share), set
// by ParallaxLandscape for night worlds; transparent texels stay transparent.
uniform vec4 veil = vec4(0.0);
varying vec4 modulation;
void vertex() { modulation = COLOR; }
void fragment() {
	vec2 background_coords = UV;
	#include "res://shaders/background_fragment.gdshaderinc"
	painted.rgb = mix(painted.rgb, veil.rgb, veil.a);
	COLOR = modulation * painted;
}
