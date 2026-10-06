shader_type canvas_item;
// Painted architecture keeps fixed UVs. Only authored water reflection pixels
// receive a tiny horizontal displacement; elapsed is supplied by paused logic.
uniform float sky_cutoff=0.35;
uniform float sky_clock=0.0;
uniform vec4 water_bounds=vec4(0.0);
uniform float water_amplitude=4.5;
uniform float water_glint : hint_range(0.0, 0.12)=0.070;
uniform float water_turbulence : hint_range(0.0, 1.0)=0.6;
uniform float edge_fade=0.035;
// The follow camera can look above the authored panorama from the roof.
// Feather its sky into the continuous color extension, without moving UVs.
uniform float top_fade=0.075;
varying float sky_light;

void vertex() {
	// Uniform across the image: evaluate the slow light cycle per vertex.
	sky_light=sin(sky_clock*0.17)*0.006;
}

void fragment() {
	vec2 sample_uv=UV;
	float water=0.0;
	float crest=0.0;
	// Most pixels are solid scenery. They need neither ripple sines nor the
	// division by water bounds; the branch is uniform across large regions.
	if (water_bounds.z>0.0 && water_bounds.w>0.0 &&
		UV.x>water_bounds.x && UV.x<water_bounds.x+water_bounds.z &&
		UV.y>water_bounds.y && UV.y<water_bounds.y+water_bounds.w) {
		vec2 local=(UV-water_bounds.xy)/water_bounds.zw;
		water=smoothstep(0.0,0.035,local.y)*(1.0-smoothstep(0.965,1.0,local.y));
		water*=smoothstep(0.0,0.015,local.x)*(1.0-smoothstep(0.985,1.0,local.x));
		vec2 pixel=floor(UV/TEXTURE_PIXEL_SIZE);
		float row=floor(pixel.y/2.0)*2.0;
		// Crossing long swells and short ripples deform different reflection
		// columns at different times. Two-pixel rows preserve the painted style.
		float swell=sin(row*0.105-sky_clock*1.35+sin(pixel.x*0.017+sky_clock*0.19)*1.35);
		float ripple=sin(row*0.31+pixel.x*0.013+sky_clock*2.3);
		float cross_wave=sin(pixel.x*0.048-row*0.09-sky_clock*0.77);
		float height=swell*0.58+ripple*0.27+cross_wave*0.15*water_turbulence;
		float perspective=0.35+local.y*0.65;
		sample_uv.x=clamp(UV.x+height*TEXTURE_PIXEL_SIZE.x*water_amplitude*water*perspective,
			water_bounds.x+TEXTURE_PIXEL_SIZE.x*0.5,
			water_bounds.x+water_bounds.z-TEXTURE_PIXEL_SIZE.x*0.5);
		sample_uv.y=clamp(UV.y+(cross_wave-swell*0.3)*TEXTURE_PIXEL_SIZE.y*water_amplitude*0.18*water*local.y,
			water_bounds.y+TEXTURE_PIXEL_SIZE.y*0.5,
			water_bounds.y+water_bounds.w-TEXTURE_PIXEL_SIZE.y*0.5);
		crest=smoothstep(0.30,0.92,height)*water*water_glint;
	}
	vec4 original=texture(TEXTURE,sample_uv);
	float sky=1.0-smoothstep(max(0.0,sky_cutoff-0.10),sky_cutoff,UV.y);
	float light=1.0+sky_light*sky;
	float edge=edge_fade<=0.0 ? 1.0 : smoothstep(0.0,edge_fade,UV.x)*(1.0-smoothstep(1.0-edge_fade,1.0,UV.x));
	// Restrained two-pixel crests brighten existing reflections, without
	// introducing a separate glossy surface or moving the painted shoreline.
	vec3 reflection=original.rgb*light+vec3(0.62,0.76,0.80)*crest*dot(original.rgb,vec3(0.299,0.587,0.114));
	float top_edge=top_fade<=0.0 ? 1.0 : smoothstep(0.0,top_fade,UV.y);
	COLOR=vec4(reflection,original.a*edge*top_edge);
}
