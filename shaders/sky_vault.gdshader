shader_type canvas_item;
render_mode unshaded;

uniform float horizon_y=0.0;
uniform vec4 horizon_left : source_color;
uniform vec4 horizon_right : source_color;
uniform vec4 zenith : source_color;
uniform vec4 light_color : source_color;
uniform vec2 light_position=vec2(1550.0,-720.0);
uniform float light_strength=0.15;
uniform float star_strength=0.0;
varying vec2 world_position;

float grain(vec2 p) {
	return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);
}

void vertex() { world_position=VERTEX; }

void fragment() {
	vec2 p=floor(world_position/2.0)*2.0;
	float height=max(0.0,horizon_y-p.y);
	float altitude=1.0-exp(-height/1080.0);
	vec3 horizon=mix(horizon_left.rgb,horizon_right.rgb,clamp((p.x+2000.0)/5600.0,0.0,1.0));
	vec3 sky=mix(horizon,zenith.rgb,altitude);
	vec2 light_delta=(p-light_position)/vec2(870.0,620.0);
	float halo=exp(-dot(light_delta,light_delta)*1.6)*light_strength;
	float join=smoothstep(0.0,230.0,height);
	sky=mix(sky,light_color.rgb,halo*join);
	// A sub-palette dither prevents large gradient bands while retaining the
	// two-world-pixel grain of the painted background at every camera zoom.
	sky+=(grain(p)-0.5)*0.006*join;
	if (star_strength>0.0) {
		vec2 cell=floor(p/116.0);
		vec2 at=(cell+vec2(0.13+grain(cell)*0.72,0.13+grain(cell+19.0)*0.72))*116.0;
		float star=1.0-smoothstep(0.6,2.7,length(p-at));
		float chosen=step(0.53,grain(cell+37.0));
		sky=mix(sky,vec3(0.67,0.76,0.84),star*chosen*star_strength*join*altitude);
	}
	COLOR=vec4(sky,1.0);
}
