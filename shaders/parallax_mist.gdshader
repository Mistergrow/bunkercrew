shader_type canvas_item;
uniform float scene_clock = 0.0;
uniform float motion_gain = 1.0;
uniform vec4 mist_color : source_color = vec4(.43,.46,.68,1.0);
uniform float mist_opacity = .12;
void fragment() {
	float band = exp(-pow((UV.y-.68)*19.0,2.0));
	float slow = scene_clock*.010*motion_gain;
	float billow = .5+.22*sin(UV.x*18.0-slow)+.15*sin(UV.x*41.0+UV.y*17.0-slow*1.8);
	COLOR = vec4(mist_color.rgb,band*billow*mist_opacity*motion_gain);
}
