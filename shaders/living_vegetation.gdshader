shader_type canvas_item;

// One material covers all grounded species and the three static mesh batches.
// Vertex colour carries phase, root x, tip fraction and depth/stiffness data.
uniform float ecology_clock = 0.0;
uniform float wind_strength = 1.0;
uniform float gust_strength = 0.0;
uniform float motion_scale = 1.0;
uniform vec4 habitat_tint : source_color = vec4(1.0);
uniform vec4 nearby_actors[4];
uniform vec2 ground_extent = vec2(-410.0,2260.0);
varying vec4 painted_tint;

void vertex() {
	float phase = COLOR.r * 6.2831853;
	float root_x = ground_extent.x + COLOR.g * ground_extent.y;
	float tip = COLOR.b;
	float packed = COLOR.a * 3.0;
	float depth = floor(packed);
	float stiffness = clamp((fract(packed) - 0.35) / 0.5,0.15,1.0);
	float bend = smoothstep(0.12,1.0,tip);
	float traveling = sin(ecology_clock * 1.37 - root_x * 0.021);
	float flutter = sin(ecology_clock * (2.2 + stiffness) + phase + tip * 4.8);
	float strength = gust_strength * wind_strength * motion_scale;
	VERTEX.x += (traveling * 1.8 + flutter * 0.7 + 1.8) * bend * strength * (1.15 - stiffness * 0.55);
	// Low grasses yield around nearby outdoor feet; no collision body or raycast.
	for (int index = 0; index < 4; index++) {
		vec4 actor = nearby_actors[index];
		float distance = root_x - actor.x;
		float proximity = (1.0 - smoothstep(7.0,42.0,abs(distance))) * actor.z;
		float direction = sign(distance + 0.001);
		VERTEX.x += direction * proximity * bend * 5.0 * (1.0 - stiffness * 0.6);
		VERTEX.y += proximity * bend * 1.8;
	}
	float variation = 0.92 + sin(phase * 1.73) * 0.035;
	float depth_shade = 0.9 + depth * 0.04;
	painted_tint = vec4(habitat_tint.rgb * variation * depth_shade,habitat_tint.a);
}

void fragment() {
	vec4 source = texture(TEXTURE,UV);
	// Generated alpha<=2 fringe pixels may contain arbitrary bright RGB.
	// Keep the authored visible silhouette without exposing that edge noise.
	if (source.a < 0.04) { discard; }
	COLOR = source * painted_tint;
}
