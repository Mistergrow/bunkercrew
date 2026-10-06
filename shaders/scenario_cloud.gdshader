shader_type canvas_item;
uniform vec4 cloud_tint : source_color=vec4(0.54,0.58,0.60,0.19);
uniform bool mask_landmarks=false;
uniform sampler2D skyline : filter_nearest, repeat_disable;
uniform vec4 panorama_bounds=vec4(0.0,0.0,1536.0,512.0);
uniform float panorama_edge_fade=0.035;
// Scene time pauses exactly with gameplay. Only small internal wisps change;
// texture sampling remains nearest and never escapes its atlas row.
uniform float cloud_clock=0.0;
uniform float cloud_phase=0.0;
uniform float cloud_morph_strength=1.0;
uniform float cloud_wind=0.0;
uniform float storm_light=0.0;
uniform bool preserve_painted_color=false;
uniform bool mask_extended_land=false;
uniform sampler2D extended_land : filter_nearest, repeat_disable;
uniform float land_baseline=430.0;
uniform vec3 land_widths=vec3(2100.0,1740.0,1460.0);
uniform vec3 land_heights=vec3(227.0,179.0,104.0);
uniform vec3 land_offsets=vec3(-417.0,193.0,-631.0);
uniform vec4 land_region_0;
uniform vec4 land_region_1;
uniform vec4 land_region_2;
varying vec4 cloud_modulate;
varying vec2 cloud_position;

float landscape_visibility(vec2 p,float depth,float width,float height,float offset,vec4 region) {
	if (p.y<land_baseline-height || p.y>land_baseline) { return 1.0; }
	float period=width*0.74;
	float last=floor((p.x-offset)/period);
	float visible=1.0;
	for (int copy_index=0;copy_index<2;copy_index++) {
		float tile=last-float(copy_index);
		float u=(p.x-floor(tile*period+offset+0.5))/width;
		if (u>=0.0 && u<=1.0) {
			if (mod(tile+depth,2.0)>0.5) { u=1.0-u; }
			float v=(p.y-(land_baseline-height))/height;
			float alpha=texture(extended_land,region.xy+vec2(u,v)*region.zw).a;
			float edge=smoothstep(0.0,0.16,u)*(1.0-smoothstep(0.84,1.0,u));
			visible*=1.0-smoothstep(0.12,0.60,alpha)*edge;
		}
	}
	return visible;
}

float outer_sky(vec2 p) {
	if (!mask_extended_land) { return 1.0; }
	return landscape_visibility(p,0.0,land_widths.x,land_heights.x,land_offsets.x,land_region_0)
		*landscape_visibility(p,1.0,land_widths.y,land_heights.y,land_offsets.y,land_region_1)
		*landscape_visibility(p,2.0,land_widths.z,land_heights.z,land_offsets.z,land_region_2);
}

void vertex() {
	cloud_modulate=COLOR*cloud_tint;
	cloud_position=VERTEX;
}

void fragment() {
	float rows=abs(1.0/TEXTURE_PIXEL_SIZE.y-1024.0)<0.5 ? 3.0 : 1.0;
	float row=floor(min(UV.y,0.99999)*rows);
	float local_y=UV.y*rows-row;
	float envelope=smoothstep(0.0,0.055,local_y)*(1.0-smoothstep(0.945,1.0,local_y));
	envelope*=smoothstep(0.0,0.06,UV.x)*(1.0-smoothstep(0.94,1.0,UV.x));
	vec2 cell=floor(UV/TEXTURE_PIXEL_SIZE/8.0)*8.0*TEXTURE_PIXEL_SIZE;
	float clock=cloud_clock*(0.043+cloud_phase*0.0017);
	float broad=sin(cell.x*19.0+cell.y*11.0+clock+cloud_phase);
	float wisp=sin(cell.x*37.0-cell.y*17.0-clock*0.73+cloud_phase*2.3);
	vec2 shift=vec2(broad*3.0+wisp*0.8, wisp*1.7+broad*0.65);
	shift*=cloud_morph_strength*(1.0+abs(cloud_wind)*0.22)*envelope;
	vec2 moving_uv=UV+shift*TEXTURE_PIXEL_SIZE;
	moving_uv=clamp(moving_uv,vec2(TEXTURE_PIXEL_SIZE.x*0.5,row/rows+TEXTURE_PIXEL_SIZE.y),vec2(1.0-TEXTURE_PIXEL_SIZE.x*0.5,(row+1.0)/rows-TEXTURE_PIXEL_SIZE.y));
	vec4 cloud=texture(TEXTURE,moving_uv);
	// The atlas has 1/255 alpha noise on its rectangular outer edges.
	if (cloud.a>0.006 && cloud_modulate.a>0.001) {
		float light=dot(cloud.rgb,vec3(0.299,0.587,0.114));
		// The source is not seamless: adjacent copies overlap through alpha ramps.
		float edge=smoothstep(0.0,0.21,UV.x)*(1.0-smoothstep(0.79,1.0,UV.x));
		float visibility=1.0;
		if (mask_landmarks) {
			vec2 local=(cloud_position-panorama_bounds.xy)/panorama_bounds.zw;
			if (local.x<0.0 || local.x>1.0 || local.y<0.0) {
				visibility=outer_sky(cloud_position);
			} else {
				float painted=texture(skyline,clamp(local,vec2(0.0),vec2(1.0))).r;
				float edge=1.0;
				if (mask_extended_land) {
					edge=smoothstep(0.0,panorama_edge_fade,local.x)*(1.0-smoothstep(1.0-panorama_edge_fade,1.0,local.x));
					edge*=smoothstep(0.0,0.075,local.y);
				}
				// The fading painted land hands cloud occlusion to the actual
				// extended ridge silhouette, never a clamped vertical edge texel.
				visibility=edge>=1.0 ? painted : mix(outer_sky(cloud_position),painted,edge);
			}
		}
		vec3 color=preserve_painted_color ? cloud.rgb*cloud_modulate.rgb : cloud_modulate.rgb*(0.38+light+storm_light*0.30);
		COLOR=vec4(color,cloud.a*cloud_modulate.a*edge*visibility);
	} else {
		COLOR=vec4(0.0);
	}
}
