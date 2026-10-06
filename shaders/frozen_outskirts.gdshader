shader_type canvas_item;
render_mode unshaded;
uniform float clear_left;
uniform float clear_right;
uniform bool foreground = false;
varying float world_x;
void vertex() { world_x = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).x; }
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float shade = dot(source.rgb, vec3(0.299,0.587,0.114));
	vec3 winter = mix(vec3(0.075,0.13,0.18),vec3(0.64,0.79,0.88),shade);
	float edge = smoothstep(0.0,0.12,UV.x)*(1.0-smoothstep(0.88,1.0,UV.x));
	float outside = 1.0;
	if (foreground) {
		outside = 1.0-smoothstep(clear_left-100.0,clear_left,world_x)
			+smoothstep(clear_right,clear_right+100.0,world_x);
	}
	COLOR = vec4(winter, smoothstep(0.18,0.65,source.a)*edge*outside);
}
