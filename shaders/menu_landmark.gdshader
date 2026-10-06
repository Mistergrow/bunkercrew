shader_type canvas_item;
render_mode unshaded;
uniform vec4 source_region=vec4(0.0,0.0,1.0,1.0);
uniform float landmark_clock=0.0;
uniform float phase=0.0;
uniform float illumination=1.0;
uniform float motion_strength=1.0;
uniform int effect=0;
uniform bool white_light=false;

void fragment() {
	vec2 local=(UV-source_region.xy)/source_region.zw;
	float edge=smoothstep(0.0,0.14,local.x)*(1.0-smoothstep(0.86,1.0,local.x));
	edge*=smoothstep(0.0,0.14,local.y)*(1.0-smoothstep(0.86,1.0,local.y));
	vec4 source=texture(TEXTURE,UV);
	float luminance=dot(source.rgb,vec3(0.299,0.587,0.114));
	float mask=0.0;
	vec3 result=source.rgb;
	if (effect==0) {
		// Repaint only authored luminous pixels; rust, stone and the cropped
		// rectangular background remain completely transparent.
		float warmth=source.r-max(source.g*0.95,source.b*1.14);
		mask=smoothstep(0.035,0.12,warmth)*smoothstep(0.22,0.56,source.r);
		if (white_light) { mask=max(mask,smoothstep(0.52,0.82,luminance)); }
		result*=illumination;
	} else if (effect==1) {
		// Water travels inside its painted pale channels. The source rectangle
		// never shifts and no UV can reach adjacent dry masonry.
		float cool=source.b-source.r*0.93;
		mask=smoothstep(0.012,0.07,cool)*smoothstep(0.20,0.47,luminance);
		float row=local.y*source_region.w/TEXTURE_PIXEL_SIZE.y;
		float ripple=sin(row*0.43-landmark_clock*(3.4+phase*0.17)+local.x*5.0);
		vec2 displaced=UV+vec2(sin(local.y*17.0+phase)*0.35,-ripple*1.1)*TEXTURE_PIXEL_SIZE*motion_strength*edge;
		displaced=clamp(displaced,source_region.xy+TEXTURE_PIXEL_SIZE,source_region.xy+source_region.zw-TEXTURE_PIXEL_SIZE);
		vec3 moving=texture(TEXTURE,displaced).rgb;
		float moving_water=smoothstep(0.012,0.07,moving.b-moving.r*0.93)*smoothstep(0.20,0.47,dot(moving,vec3(0.299,0.587,0.114)));
		mask*=moving_water;
		result=moving*(1.0+max(0.0,ripple)*0.10*motion_strength);
	} else if (effect==2) {
		// Moving filtered sunlight touches green ivy only. Painted steelwork
		// keeps its shape and brightness, with no cut-out canopy rectangle.
		mask=smoothstep(0.008,0.055,source.g-source.b)*smoothstep(-0.015,0.025,source.g-source.r);
		float canopy=sin(local.x*13.0+local.y*4.0+landmark_clock*0.27+phase);
		canopy+=sin(local.x*4.0-local.y*11.0-landmark_clock*0.16+phase)*0.45;
		result*=1.0+canopy*0.065*motion_strength;
	} else {
		// These chimneys already have painted vapor. Animate brightness inside
		// its pale pixels; its UVs and silhouette remain fixed.
		float saturation=max(source.r,max(source.g,source.b))-min(source.r,min(source.g,source.b));
		mask=smoothstep(0.40,0.70,luminance)*(1.0-smoothstep(0.40,0.68,saturation));
		float rising=sin(local.y*23.0+landmark_clock*0.8+phase);
		float rolling=sin(local.y*11.0-local.x*8.0+landmark_clock*0.31+phase*1.7);
		result=source.rgb*(1.0+(rising*0.045+rolling*0.025)*motion_strength);
	}
	COLOR=vec4(result,source.a*mask*edge);
}
