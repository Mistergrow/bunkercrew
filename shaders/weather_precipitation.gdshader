shader_type canvas_item;
render_mode unshaded;

// One depth layer of falling weather (rain, snow, ash, dust, mist). The whole
// layer is one static mesh with one quad (dots) or two stacked half quads
// (streaks) per particle; this shader animates every particle from the shared
// presentation clock, so the CPU never touches a single particle. Positions
// wrap in a tile that follows the view and snap to whole world pixels, the
// texel grid of the actor art. Unshaded: weather_precipitation.gd picks the
// colours per world so that they stay readable at night.
// Vertex encoding (exact in 32-bit floats):
//   VERTEX = cell * 8 + corner, cell = place in the tile in 1/1024 steps,
//            corner.x = 0..1 plus 2 on the lower half of a streak,
//            corner.y = 0, 0.5 or 1;
//   UV     = (speed factor, seed); COLOR = particle tint.

uniform float clock = 0.0;
uniform vec2 tile_origin = vec2(0.0);
uniform vec2 tile_size = vec2(1024.0, 640.0);
uniform vec2 parallax_shift = vec2(0.0);
uniform float fall_speed = 300.0;
uniform float wind = 0.0;
uniform float sway = 0.0;
uniform float amount = 1.0;
uniform float flash = 0.0;
uniform float streak = 0.0;
uniform float slant = 0.0;
uniform float tumble = 0.0;
uniform bool use_shelter = false;
uniform sampler2D shelter : filter_nearest, repeat_disable;
uniform float shelter_left = 0.0;
uniform float shelter_step = 8.0;
uniform float shelter_count = 1.0;
uniform float shelter_width = 1.0;

void vertex() {
	vec2 cell = floor(VERTEX / 8.0);
	vec2 packed = VERTEX - cell * 8.0;
	float lower = floor(packed.x / 2.0);
	vec2 corner = vec2(packed.x - lower * 2.0, packed.y);
	float factor = UV.x;
	float seed = UV.y;
	// Embers (ash) carry a flag of 4 on their speed factor: they rise slowly on
	// the heat with a wider sway and glow between steps of brightness.
	bool ember = factor > 3.0;
	if (ember) { factor -= 4.0; }
	// Density follows the shower: the lowest seeds stay, the others step out.
	bool hidden = seed >= amount;
	vec2 field = cell / 1024.0 * tile_size + vec2(wind, ember ? -fall_speed * 0.7 : fall_speed) * factor * clock;
	if (sway > 0.0) {
		float phase = seed * 61.0;
		float reach = ember ? sway * 1.6 : sway;
		field.x += sin(clock * (0.9 + seed * 1.3) + phase) * reach + sin(clock * 2.3 + phase * 1.7) * reach * 0.35;
		// Flat flakes bob as they turn: a slow vertical lilt.
		if (tumble > 0.0) { field.y += sin(clock * (1.3 + seed) + phase * 0.6) * sway * 0.30; }
	}
	vec2 position = floor(tile_origin + mod(field - parallax_shift - tile_origin, tile_size));
	vec2 local;
	float extent;
	if (streak > 0.0) {
		extent = floor(streak * factor);
		// The lower half steps sideways with the wind by whole pixels.
		local = vec2(corner.x + lower * slant, floor(corner.y * extent));
	} else {
		// The faster, nearer particles of a layer are one pixel larger.
		vec2 size = factor > 1.12 ? vec2(2.0) : vec2(1.0);
		if (ember) {
			// A spark: one texel, two side by side while it flares.
			float flare = fract(clock * (0.5 + seed * 0.7) + seed * 13.0);
			size = flare < 0.3 ? vec2(2.0, 1.0) : vec2(1.0);
			COLOR.rgb *= flare < 0.3 ? 1.0 : (flare < 0.75 ? 0.82 : 0.62);
		} else if (tumble > 0.0) {
			// Flat flakes turn edge-on and back: 2x1, 1x1, 1x2 on the pixel grid;
			// the faster, nearer flakes 3x1, 2x1, 1x2. Never a square: a square
			// flake reads as snow.
			float turn = fract(clock * tumble * (0.6 + seed) + seed * 7.0);
			bool large = factor > 1.12;
			size = turn < 0.4 ? vec2(large ? 3.0 : 2.0, 1.0) : (turn < 0.55 ? vec2(large ? 2.0 : 1.0, 1.0) : (turn < 0.9 ? vec2(1.0, 2.0) : vec2(1.0)));
		}
		extent = size.y;
		local = corner * size;
	}
	if (use_shelter && !hidden) {
		// The whole particle stays above the roof, rock or water line of its column.
		float column = floor((position.x - shelter_left) / shelter_step);
		if (column < 0.0 || column >= shelter_count) {
			hidden = true;
		} else {
			float top = textureLod(shelter, vec2((column + 0.5) / shelter_width, 0.5), 0.0).r;
			hidden = position.y + extent > top;
		}
	}
	VERTEX = hidden ? vec2(0.0) : position + local;
	COLOR.rgb *= 1.0 + flash * 0.9;
	COLOR.a = min(1.0, COLOR.a * (1.0 + flash * 0.8));
}
