shader_type canvas_item;
render_mode unshaded;

uniform float smoke_clock = 0.0;
uniform float emitter_index = 0.0;
uniform vec2 smoke_origin = vec2(0.0);
uniform float wind_phase = 0.0;
uniform float base_wind = 4.0;
uniform float gust_strength = 1.0;
uniform float plume_width = 1.0;
uniform bool reduced_effects = false;

float wind_at(float at) {
	float clock = at + wind_phase;
	float cycle = floor(clock / 32.0);
	float within = mod(clock, 32.0);
	float gust = smoothstep(3.0, 8.0, within) * (1.0 - smoothstep(12.0, 18.0, within));
	float direction = mod(cycle, 3.0) > 1.5 ? -1.0 : 1.0;
	return base_wind + sin(clock * 0.18) * 1.5 + gust * direction * 62.0 * gust_strength;
}

void vertex() {
	float puff = UV.x;
	float cluster = UV.y;
	float life = 12.0 + emitter_index * 0.7;
	float age = mod(smoke_clock + puff * life / 28.0, life);
	float progress = age / life;
	float drift = age * (wind_at(smoke_clock - age) + 4.0 * wind_at(smoke_clock - age * 0.5) + wind_at(smoke_clock)) / 6.0;
	float mean_wind = abs(drift) / max(age, 0.001);
	vec2 point = smoke_origin + vec2(drift * 0.48 + sin(age * 0.7 + emitter_index) * age * 0.7, -age * 13.0 / (1.0 + mean_wind / 95.0));
	float size = 4.0 + progress * 25.0;
	float angle = cluster * TAU / 5.0 + (puff + emitter_index * 7.0) * 0.7;
	vec2 cluster_offset = vec2(cos(angle), sin(angle)) * 0.4;
	float radius = max(2.0, round(size * (0.4 + mod(cluster, 3.0) * 0.09)));
	float alpha = smoothstep(0.0, 0.035, progress) * pow(1.0 - progress, 1.1) * 0.58;
	// Wind stretches adjoining puffs into a continuous trail. Keeping round
	// calm-weather puffs at this spacing would leave a visible string of beads.
	float stretch = 1.0 + min(2.3, mean_wind / 26.0);
	vec2 shape = vec2(VERTEX.x * stretch, VERTEX.y);
	cluster_offset.x *= max(1.0, stretch * 0.75);
	alpha /= sqrt(stretch);
	VERTEX = round(shape * radius * plume_width) + round(round(point) + cluster_offset * size * plume_width) - smoke_origin;
	COLOR.a *= alpha;
	if (alpha < 0.005 || (reduced_effects && mod(puff, 3.0) > 0.5)) {
		VERTEX = vec2(0.0);
		COLOR.a = 0.0;
	}
}
