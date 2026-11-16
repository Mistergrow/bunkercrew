shader_type canvas_item;
render_mode unshaded, blend_mul;

// Light structure of one bunker room, multiplied over its walls, floor and
// machines (never over the crew, which is drawn above it): bright cones and
// floor pools under the three ceiling lamps, ambient occlusion along the floor,
// the side walls and the ceiling corners, and a cooler, darker grade with
// depth. Banded in four steps with a 4x4 ordered dither on whole world pixels,
// like the actor art. Drawn as one rect from the room's top-left corner.

uniform vec3 shade : source_color = vec3(0.8);
uniform vec3 lit : source_color = vec3(1.0);
uniform vec2 room = vec2(640.0, 205.0);
uniform vec3 lamps = vec3(109.0, 346.0, 544.0);
uniform float lamp_y = 36.0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

float bayer(vec2 cell) {
	int x = int(mod(cell.x, 4.0));
	int y = int(mod(cell.y, 4.0));
	int index = y * 4 + x;
	float table[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (table[index] + 0.5) / 16.0;
}

float cone(vec2 p, float x) {
	float below = p.y - lamp_y;
	float across = abs(p.x - x);
	// A wide cone that opens downward and fades toward the floor.
	float spread = 26.0 + max(below, 0.0) * 0.62;
	float beam = (1.0 - smoothstep(0.30, 1.0, across / spread)) * smoothstep(-10.0, 4.0, below);
	beam *= 1.0 - 0.45 * smoothstep(20.0, room.y - 30.0, below);
	// The pool where it meets the floor, and a short glow on the ceiling.
	float pool = (1.0 - smoothstep(30.0, 92.0, across)) * smoothstep(room.y - 70.0, room.y - 18.0, p.y);
	float ceiling = (1.0 - smoothstep(8.0, 46.0, across)) * (1.0 - smoothstep(0.0, 22.0, abs(below + 4.0)));
	return max(beam, max(pool * 0.85, ceiling * 0.75));
}

void fragment() {
	vec2 p = floor(local) + 0.5;
	float light = max(cone(p, lamps.x), max(cone(p, lamps.y), cone(p, lamps.z)));
	// Occlusion: the floor line, both side walls, the corners under the slab.
	float floor_ao = smoothstep(room.y - 34.0, room.y - 4.0, p.y);
	float wall_ao = 1.0 - smoothstep(18.0, 64.0, min(p.x, room.x - p.x));
	float ceiling_ao = 1.0 - smoothstep(14.0, 40.0, p.y);
	float occlusion = clamp(floor_ao * 0.55 + wall_ao * 0.6 + ceiling_ao * 0.35, 0.0, 1.0);
	float value = clamp(0.30 + light * 0.78 - occlusion * 0.38, 0.0, 1.0);
	// Four bands, dithered on the world pixel grid.
	float level = value * 4.0;
	float band = floor(level);
	if (fract(level) > bayer(floor(local))) band += 1.0;
	value = band / 4.0;
	vec3 grade = mix(shade, lit, value);
	COLOR = vec4(mix(vec3(1.0), grade, strength), 1.0);
}
