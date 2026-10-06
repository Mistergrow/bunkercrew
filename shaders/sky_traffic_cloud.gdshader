shader_type canvas_item;
#include "res://shaders/sky_cloud_sampling.gdshaderinc"
uniform vec4 cloud_tint : source_color=vec4(0.45,0.53,0.65,0.5);
varying vec4 cloud_modulate;
varying vec2 sky_point;
void vertex() { cloud_modulate=COLOR*cloud_tint; sky_point=VERTEX; }
void fragment() {
	vec4 painted=sky_cloud_sample(UV);
	float shade=dot(painted.rgb,vec3(0.299,0.587,0.114));
	COLOR=vec4(cloud_modulate.rgb*(0.42+shade*0.8),painted.a*cloud_modulate.a*sky_visibility(sky_point));
}
