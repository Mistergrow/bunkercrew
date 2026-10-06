shader_type canvas_item;
#include "res://shaders/background_sampling.gdshaderinc"
uniform float scene_clock = 0.0;
uniform float motion_gain = 1.0;
uniform vec2 sky_drift = vec2(0.0);
// World cloud masks share the owner's transform; travel-only sky plates keep
// their established clock-driven animation without needing a mask owner.
uniform bool use_sky_drift = false;
varying vec4 modulation;
void vertex() { modulation = COLOR; }
void fragment() {
	// Small evolving wisps move within a generously overscanned opaque plate.
	vec2 drift = use_sky_drift ? sky_drift : vec2(sin(scene_clock * .022) * .014, sin(scene_clock * .017) * .004);
	vec2 background_coords = clamp(UV + drift * motion_gain, vec2(.001), vec2(.999));
	#include "res://shaders/background_fragment.gdshaderinc"
	COLOR = modulation * painted;
}
