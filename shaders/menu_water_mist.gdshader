shader_type canvas_item;
render_mode unshaded;
uniform vec4 mist_tint : source_color = vec4(0.59,0.72,0.76,1.0);
varying vec4 mist_modulate;
void vertex() {
	mist_modulate=COLOR;
}
void fragment() {
	float row=floor(min(UV.y,0.99999)*2.0);
	float local_y=UV.y*2.0-row;
	vec2 source_uv=clamp(UV,vec2(TEXTURE_PIXEL_SIZE.x,(row*0.5)+TEXTURE_PIXEL_SIZE.y),vec2(1.0-TEXTURE_PIXEL_SIZE.x,(row+1.0)*0.5-TEXTURE_PIXEL_SIZE.y));
	vec4 source=texture(TEXTURE,source_uv);
	float edge=smoothstep(0.0,0.16,UV.x)*(1.0-smoothstep(0.84,1.0,UV.x));
	edge*=smoothstep(0.0,0.10,local_y)*(1.0-smoothstep(0.90,1.0,local_y));
	float luminance=dot(source.rgb,vec3(0.299,0.587,0.114));
	float alpha=source.a>0.025 ? source.a*edge : 0.0;
	COLOR=vec4(mist_tint.rgb*(0.55+luminance*0.45),alpha*mist_modulate.a*mist_tint.a);
}
