shader_type canvas_item;
render_mode unshaded;

// One immutable mesh holds all five octagons of every puff. Its UVs encode
// puff and cluster indices; the explicit clock follows the scene's pause/F3.
uniform float smoke_clock = 0.0;
uniform float smoke_wind = 8.0;
uniform float emitter_index = 0.0;
uniform vec2 smoke_origin = vec2(0.0);
uniform bool reduced_effects = false;

void vertex() {
	float puff = UV.x;
	float cluster = UV.y;
	float life = 12.0 + emitter_index * 0.7;
	float age = mod(smoke_clock + puff * life / 28.0, life);
	float progress = age / life;
	vec2 point = smoke_origin + vec2(age * smoke_wind * 0.48 + sin(age * 0.7 + emitter_index) * age * 0.7, -age * 13.0);
	float size = 4.0 + progress * 25.0;
	float angle = cluster * TAU / 5.0 + (puff + emitter_index * 7.0) * 0.7;
	vec2 cluster_offset = vec2(cos(angle), sin(angle)) * 0.4;
	float radius = max(2.0, round(size * (0.4 + mod(cluster, 3.0) * 0.09)));
	float alpha = smoothstep(0.0, 0.035, progress) * pow(1.0 - progress, 1.1) * 0.58;
	VERTEX = round(VERTEX * radius) + round(round(point) + cluster_offset * size) - smoke_origin;
	COLOR.a *= alpha;
	if (alpha < 0.005 || (reduced_effects && mod(puff, 3.0) > 0.5)) {
		VERTEX = vec2(0.0);
		COLOR.a = 0.0;
	}
}
