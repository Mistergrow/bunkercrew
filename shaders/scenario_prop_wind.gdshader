shader_type canvas_item;

// Twelve mesh bands bend along the trunk. Local y=0 is always the fixed root;
// the engine's TIME is deliberately unused so shared pause really stops wind.
uniform float wind_clock = 0.0;
uniform float wind_strength = 1.0;
uniform float motion_scale = 1.0;
uniform float stiffness = 1.0;
uniform float gust_strength = 1.0;
uniform float tree_phase = 0.0;
uniform float tree_rate = 1.0;
uniform float hit_amount = 0.0;
varying vec4 source_tint;
varying vec2 rooted_position;

void vertex() {
	source_tint = COLOR;
	rooted_position = VERTEX;
	float height = clamp(-VERTEX.y / 192.0, 0.0, 1.0);
	float clock = wind_clock * tree_rate;
	float phase = tree_phase;
	float gust = sin(clock * 0.73 + phase) * 0.52;
	gust += sin(clock * 1.41 + phase * 1.73) * 0.23;
	// A shared gust travels through the scene, while local branches keep
	// their own rate and phase. Adjacent trees never form a rigid metronome.
	gust += sin(wind_clock * 0.91 - MODEL_MATRIX[3].x * 0.011) * 0.25;
	// The root zone is rigid; deformation begins above the exposed roots.
	float bend = clamp((height - 0.18) / 0.82, 0.0, 1.0);
	bend *= bend;
	float direction = sign(MODEL_MATRIX[0].x);
	float branch = sin(clock * 2.17 + height * 8.3 + VERTEX.x * 0.037 + phase) * height * height;
	VERTEX.x += ((2.0 + gust * 6.5) * bend + branch * 0.8 * bend) * wind_strength * gust_strength * motion_scale * direction / stiffness;
	VERTEX.x += hit_amount * bend;
	VERTEX.y += sin(clock * 1.13 + phase + VERTEX.x * 0.041) * 0.45 * bend * motion_scale * clamp(gust_strength,0.0,1.0);
}

void fragment() {
	// The measured trunk flare enters real ground. The image's long exposed
	// root illustration is buried rather than dangling above the terrain.
	if (rooted_position.y > -0.15) { discard; }
	COLOR = texture(TEXTURE, UV) * source_tint;
}
