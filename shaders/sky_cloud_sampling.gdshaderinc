// Shared atlas coordinates keep foreground pixels and their light occlusion
// identical. The imported cloud cutouts are reused without any image readback.
uniform sampler2D cloud_atlas : filter_nearest, repeat_disable;
uniform vec2 cloud_texel=vec2(0.0006510417,0.0009765625);
uniform float cloud_clock=0.0;
uniform float cloud_phase=0.0;
uniform bool mask_sky=false;
uniform sampler2D skyline : filter_nearest, repeat_disable;
uniform vec4 sky_bounds=vec4(0.0,0.0,1.0,1.0);
uniform vec2 sky_drift=vec2(0.0);

float sky_visibility(vec2 point) {
	if (!mask_sky) { return 1.0; }
	vec2 uv=(point-sky_bounds.xy)/sky_bounds.zw+sky_drift;
	if (uv.x<0.0 || uv.x>1.0 || uv.y<0.0 || uv.y>1.0) { return 0.0; }
	return texture(skyline,uv).r;
}

vec4 sky_cloud_sample(vec2 uv) {
	float row=floor(min(uv.y,0.99999)*3.0);
	float local_y=uv.y*3.0-row;
	float envelope=smoothstep(0.0,0.055,local_y)*(1.0-smoothstep(0.945,1.0,local_y));
	envelope*=smoothstep(0.0,0.06,uv.x)*(1.0-smoothstep(0.94,1.0,uv.x));
	vec2 cell=floor(uv/cloud_texel/8.0)*8.0*cloud_texel;
	float clock=cloud_clock*0.048;
	float broad=sin(cell.x*19.0+cell.y*11.0+clock+cloud_phase);
	float wisp=sin(cell.x*37.0-cell.y*17.0-clock*0.73+cloud_phase*2.3);
	vec2 shift=vec2(broad*3.0+wisp*0.8,wisp*1.7+broad*0.65)*envelope;
	vec2 moving_uv=clamp(uv+shift*cloud_texel,vec2(cloud_texel.x*0.5,row/3.0+cloud_texel.y),vec2(1.0-cloud_texel.x*0.5,(row+1.0)/3.0-cloud_texel.y));
	vec4 cloud=texture(cloud_atlas,moving_uv);
	float edge=smoothstep(0.0,0.15,uv.x)*(1.0-smoothstep(0.85,1.0,uv.x));
	cloud.a*=edge;
	if (cloud.a<0.006) { cloud.a=0.0; }
	return cloud;
}
