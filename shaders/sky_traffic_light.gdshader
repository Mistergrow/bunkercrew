shader_type canvas_item;
#include "res://shaders/sky_cloud_sampling.gdshaderinc"
uniform vec4 near_clouds[4];
uniform float cloud_row=2.0;
uniform vec4 light_tint : source_color=vec4(0.91,0.80,0.57,1.0);
uniform float direction=1.0;
uniform float illumination=1.0;
uniform vec2 light_origin=vec2(0.0);
uniform vec2 light_scale=vec2(1.0);
varying vec2 world_point;
varying vec2 light_point;

void vertex() {
	world_point=VERTEX*light_scale+light_origin;
	light_point=VERTEX;
}

void fragment() {
	float density=0.0;
	for (int index=0;index<4;index++) {
		vec4 card=near_clouds[index];
		if (card.z>0.0 && card.w>0.0) {
			vec2 uv=(world_point-card.xy)/card.zw;
			if (uv.x>=0.0 && uv.x<=1.0 && uv.y>=0.0 && uv.y<=1.0) {
				uv.y=(cloud_row+uv.y)/3.0;
				density=max(density,sky_cloud_sample(uv).a);
			}
		}
	}
	// Dense volumes hide the aircraft completely. Wispy fringes retain a
	// subdued diffuse glint; this is attenuation, never an opaque overglow.
	float transmission=1.0-smoothstep(0.18,0.70,density);
	vec2 p=floor(light_point+0.5);
	float core=step(abs(p.x),1.5)*step(abs(p.y),1.0);
	float halo=exp(-dot(p/vec2(6.0,4.0),p/vec2(6.0,4.0))*1.4)*0.25;
	vec2 rear=p+vec2(direction*6.0,0.0);
	float navigation=step(abs(rear.x),0.5)*step(abs(rear.y),0.5)*0.65;
	vec3 color=mix(light_tint.rgb,vec3(0.65,0.29,0.22),navigation);
	float glow=max(max(core,halo),navigation)*illumination;
	COLOR=vec4(color,glow*transmission*sky_visibility(world_point));
}
