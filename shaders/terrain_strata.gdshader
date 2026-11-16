shader_type canvas_item;
render_mode unshaded;

uniform vec4 rock_tint : source_color = vec4(0.66, 0.63, 0.60, 1.0);
uniform vec4 seam_tint : source_color = vec4(0.51, 0.45, 0.40, 1.0);
uniform vec4 soil_tint : source_color = vec4(0.67, 0.59, 0.49, 1.0);
uniform vec4 cap_tint : source_color = vec4(0.67, 0.59, 0.49, 1.0);
uniform vec4 accent_tint : source_color = vec4(0.93, 0.54, 0.15, 1.0);
// Colour of the painted land along the ground line (BackdropLightKeys): the
// topsoil and the upper rock lean toward it so the cut belongs to the panorama.
uniform vec4 land_tint : source_color = vec4(0.30, 0.29, 0.27, 1.0);
// Loose ground between the cover and the rock (TerrainStrata.subsoil_for).
uniform vec4 subsoil_tint : source_color = vec4(0.35, 0.31, 0.27, 1.0);
// World ambient from WorldLighting. The field is unshaded so that the sixteen
// lights-per-item budget is never spent on one screen-filling item.
uniform vec4 ambient : source_color = vec4(1.0);
// 1 for a daylight world, 0 at night (1 - WorldLighting.night).
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
// Sky key on the exposed top surface: rgb colour, a strength (WorldLighting).
uniform vec4 sky_rim : source_color = vec4(0.0);
// Lightning: strength and the bolt's world x. Only the exposed surface takes
// it; the rock below the first texels and every room keep their light.
uniform float flash = 0.0;
uniform float flash_x = 0.0;
uniform float inclination = 0.21;
// 0 soil, 1 snow, 2 moss, 3 wet, 4 ash, 5 sand.
uniform int surface_kind = 0;
uniform float world_seed = 0.0;
uniform float ground_line = 430.0;
// Rows above the ground line the ground cover may rise into.
uniform float cover_rise = 26.0;
// Software rasterisers (WorldLighting.software_renderer) get the plain tier:
// one warp octave, no stone-by-stone bed interlock, single-octave clods and no
// standing features. The same ground, a little coarser, for far less work.
uniform bool rich = true;
// The rock's own structure (TerrainStrata.GEOLOGY): 0 rubble, 1 layered
// sediment, 2 crystal or ice veins, 3 columnar basalt, 4 slag and cinder with
// hot specks, 5 roots and shell grit in loam, 6 seeping wet rock; its accent
// colour and strength. All on the world texel grid in flat value steps.
uniform int geology = 0;
uniform vec4 vein_tint : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform float geology_strength : hint_range(0.0, 1.0) = 0.0;
varying vec2 world_position;

const float BED = 236.0;
// Rows on both sides of a bed boundary where the two beds interlock stone by stone.
const float BED_BLEND = 26.0;
// At most one larger piece (boulder, clump, stump, heap) per this many texels.
const float FEATURE_CELL = 180.0;

float hash_point(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

float stone_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 fraction = fract(point);
	vec2 blend = fraction * fraction * (3.0 - 2.0 * fraction);
	return mix(mix(hash_point(cell), hash_point(cell + vec2(1.0, 0.0)), blend.x),
		mix(hash_point(cell + vec2(0.0, 1.0)), hash_point(cell + vec2(1.0)), blend.x), blend.y);
}

float luma(vec3 color) {
	return dot(color, vec3(0.299, 0.587, 0.114));
}

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

// 4x4 ordered dither threshold of a world texel: transitions step texel by
// texel over a few rows instead of cutting a straight line or blending softly.
float bayer4(vec2 point) {
	ivec2 cell = ivec2(mod(point, 4.0));
	return (BAYER[cell.x + cell.y * 4] + 0.5) / 16.0;
}

// Texels of the rock tile darker than this are the crevices between stones.
const float CREVICE = 0.05;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// One bed's place on the shared rock tile: its own phase, mirrored in every
// other bed, so neighbouring beds never repeat the same boulder group.
vec2 bed_uv(vec2 point, float depth, float bed) {
	float phase_a = hash_point(vec2(bed, world_seed));
	float phase_b = hash_point(vec2(bed + 17.0, world_seed + 5.0));
	vec2 rock_uv = vec2(point.x + 1850.0 + phase_a * 480.0, depth + phase_b * 480.0) / 480.0;
	if (phase_b > 0.5) {
		rock_uv.x = -rock_uv.x;
	}
	return fract(rock_uv);
}

// Height of the ground cover above the ground line at one world column, in
// whole texels: drifts, tufts, heaps or ripples by catalog weather.
float cover_height(float x) {
	float broad = stone_noise(vec2(x / 74.0, world_seed + 21.0));
	float mid = stone_noise(vec2(x / 29.0, world_seed + 23.0));
	float fine = stone_noise(vec2(x / 9.0, world_seed + 25.0));
	float column = hash_point(vec2(x, world_seed + 27.0));
	float h = 0.0;
	if (surface_kind == 1) {
		// Snow: soft drifts that swell over a few dozen texels.
		h = smoothstep(0.25, 0.75, broad) * (3.0 + mid * 7.0) + fine * 1.5;
	} else if (surface_kind == 2) {
		// Grass and moss: clumps of single-texel blades with ragged tips.
		float clump = smoothstep(0.30, 0.70, mid) * (0.6 + broad * 0.6);
		h = clump * (2.0 + column * column * 9.0);
	} else if (surface_kind == 3) {
		// Wet ground: low mud ridges between flat, puddled stretches, sparse sedge.
		h = smoothstep(0.45, 0.85, broad) * (1.5 + mid * 3.5) + step(0.90, column) * smoothstep(0.35, 0.7, mid) * (3.0 + column * 4.0);
	} else if (surface_kind == 4) {
		// Ash: settled heaps with cinder lumps.
		h = smoothstep(0.28, 0.80, broad) * (2.0 + mid * 6.0) + step(0.88, hash_point(vec2(floor(x / 3.0), world_seed + 29.0))) * 2.0;
	} else if (surface_kind == 5) {
		// Sand and dust: low dunes and ripples.
		h = smoothstep(0.22, 0.85, broad) * (1.5 + mid * 4.5) + fine * 1.0;
	} else {
		// Compacted soil: gravel and rubble lumps a few texels wide.
		float lump = hash_point(vec2(floor(x / 4.0), world_seed + 31.0));
		h = step(0.66, lump) * (1.0 + floor(lump * 9.0 - 5.5)) + smoothstep(0.50, 0.85, broad) * (1.5 + mid * 2.0);
	}
	return min(floor(h), cover_rise);
}

// Sparse larger pieces on the ground line, at most one per FEATURE_CELL: a
// clump of stems (grass, reeds, a dead shrub) or, in snow, a snowed-over
// lump. Height at x, 0 where none; `shape` = (1 stems or 2 mass, offset from
// the piece's centre, its full height).
float feature_height(float x, out vec3 shape) {
	shape = vec3(0.0);
	float cell = floor(x / FEATURE_CELL);
	if (hash_point(vec2(cell, world_seed + 51.0)) < 0.35) return 0.0;
	float half_width = 6.0 + floor(hash_point(vec2(cell, world_seed + 53.0)) * 13.0);
	float centre = cell * FEATURE_CELL + half_width + 8.0 + floor(hash_point(vec2(cell, world_seed + 55.0)) * (FEATURE_CELL - 2.0 * half_width - 16.0));
	float dx = x - centre;
	if (abs(dx) > half_width) return 0.0;
	float tall = 8.0 + floor(hash_point(vec2(cell, world_seed + 57.0)) * 12.0);
	float across = abs(dx) / half_width;
	float variant = hash_point(vec2(cell, world_seed + 59.0));
	bool stems = (surface_kind == 2 || surface_kind == 3) ? variant > 0.30 : (surface_kind == 0 && variant > 0.65);
	float h;
	if (stems) {
		float stem = hash_point(vec2(x, world_seed + 61.0));
		h = (tall + 5.0) * pow(1.0 - across, 0.5) * (0.40 + 0.60 * stem) * step(0.28, stem);
		shape = vec3(1.0, dx, tall + 5.0);
	} else if (surface_kind == 1) {
		// A snowed-over lump: a broad, lopsided crest with steep ends; the
		// outline breaks into short flat runs. Other worlds already stand
		// rocks and machines on the ground line, so only snow gets these.
		float lean = (variant - 0.5) * 0.9;
		float side = clamp(dx / half_width - lean, -1.0, 1.0);
		float profile = 1.0 - pow(abs(side), 2.6);
		float facet = hash_point(vec2(floor((x - centre) / 4.0), cell + world_seed + 63.0));
		h = tall * 0.7 * max(0.0, profile) * (0.84 + 0.16 * facet);
		shape = vec3(2.0, dx, tall * 0.7);
	} else {
		return 0.0;
	}
	return min(floor(h), cover_rise);
}

// Colour of a feature texel `rise` above the ground line.
vec3 feature_color(vec2 point, float rise, float height, vec3 shape) {
	vec3 mineral = rock_tint.rgb * rock_tint.rgb * 1.45;
	float top = step(height - 0.5, rise);
	if (shape.x < 1.5) {
		// Stems: dark at the root, lighter toward a lit tip.
		vec3 stem = surface_kind == 2 ? cap_tint.rgb * 0.52 : (surface_kind == 3 ? mix(cap_tint.rgb, seam_tint.rgb, 0.5) * 0.62 : seam_tint.rgb * 0.46);
		return stem * mix(0.78, 1.25, rise / max(shape.z, 1.0)) * (top > 0.5 ? 1.15 : 1.0);
	}
	// A rounded mass lit from above: three value steps, the top texel brightest,
	// and the world's cover settled on its crown.
	float up = rise / max(shape.z, 1.0);
	float level = up > 0.66 ? 1.0 : (up > 0.33 ? 0.82 : 0.64);
	vec3 mass = mineral * 0.62 * level;
	if (surface_kind == 4) mass = mix(mass, cap_tint.rgb * 0.42, 0.6);
	if (top > 0.5) mass *= 1.28;
	if (surface_kind == 1 && height - rise < 2.5) mass = cap_tint.rgb * (top > 0.5 ? 1.04 : 0.88);
	if (surface_kind == 4 && height - rise < 1.5) mass = cap_tint.rgb * 0.95;
	if (surface_kind == 5 && height - rise < 1.5) mass = cap_tint.rgb * 0.92;
	return mass;
}

// Colour of the cover above the ground line; `rise` counts texels above it.
vec3 cover_color(vec2 point, float rise, float height) {
	float speck = hash_point(point + vec2(world_seed, 3.0));
	float top = step(height - 0.5, rise);
	vec3 cover = cap_tint.rgb;
	if (surface_kind == 1) {
		cover *= top > 0.5 ? 1.05 : mix(0.90, 0.97, rise / max(height, 1.0));
		if (speck > 0.985 && top < 0.5) cover = min(cap_tint.rgb * 1.08, vec3(1.0));
	} else if (surface_kind == 2) {
		cover *= top > 0.5 ? 1.30 : mix(0.62, 0.95, rise / max(height, 1.0));
		if (speck > 0.80 && top < 0.5) cover *= 0.78;
	} else if (surface_kind == 3) {
		cover *= top > 0.5 ? 1.10 : 0.82;
	} else if (surface_kind == 4) {
		cover *= mix(0.78, 1.0, hash_point(vec2(floor(point.x / 3.0), floor(rise / 2.0))));
		if (top > 0.5) cover *= 1.12;
		if (speck > 0.90) cover = cap_tint.rgb * 0.40;
	} else if (surface_kind == 5) {
		cover *= top > 0.5 ? 1.08 : mix(0.82, 0.94, step(0.5, fract((point.x + rise * 3.0) / 11.0)));
	} else {
		// Rubble keeps the soil's own stone value with a lit top texel.
		cover = mix(soil_tint.rgb, seam_tint.rgb, 0.35) * (top > 0.5 ? 0.95 : 0.74);
		if (speck > 0.7) cover *= 0.82;
	}
	return cover;
}

// Mean spacing of the basalt joints (geology 3) in texels.
const float BASALT_PITCH = 32.0;

// World x of basalt joint `k` at `depth`: the pitch, a fixed jitter of up to
// seven texels per joint and a one-texel waver that changes every 13 rows,
// out of step with its neighbours.
float basalt_joint(float k, float depth) {
	float jitter = hash_point(vec2(k, world_seed + 61.0));
	float waver = floor(hash_point(vec2(k, floor((depth + jitter * 40.0) / 13.0) + world_seed + 3.0)) * 3.0) - 1.0;
	return k * BASALT_PITCH + floor((jitter - 0.5) * 14.0) + waver;
}

// The world's rock structure over the shared rubble tile (see `geology`).
vec3 apply_geology(vec3 earth, vec2 point, float depth, float rock_height, float warp, vec3 tint) {
	float value = luma(earth);
	vec3 accent = vein_tint.rgb;
	vec3 shaped = earth;
	if (geology == 1) {
		// Sediment: layers of a dozen to two dozen texels, each its own value
		// and some in the accent hue. A layer's edge wanders at stone scale and
		// steps over a few texels in the ordered dither: no straight colour cut
		// and no one-texel parting line (both read as seams in the rock).
		float edge = (stone_noise(point / vec2(13.0, 8.0) + vec2(world_seed, 87.0)) - 0.5) * 9.0 + (bayer4(point) - 0.5) * 4.0;
		float coord = (depth + point.x * inclination * 0.6 + warp * 0.35 + edge) / 23.0;
		float layer = floor(coord);
		float lh = hash_point(vec2(layer, world_seed + 91.0));
		float lift = lh < 0.25 ? 0.80 : (lh < 0.5 ? 0.93 : (lh < 0.8 ? 1.07 : 1.20));
		// The layer's own flat colour takes over part of the stones' relief.
		shaped = mix(earth, tint * 0.62, 0.40) * lift;
		if (lh > 0.55) shaped = mix(shaped, accent * luma(shaped) / max(luma(accent), 0.05) * 1.10, 0.58);
	} else if (geology == 2) {
		// Ice or quartz: frost and crystal fill the crevices between the stones
		// in irregular patches whose edges thin out in the ordered dither, with
		// a bright grain here and there. No long fissures: thin straight lines
		// across the rock read as seams or as weather falling through it.
		float field = stone_noise(point / vec2(52.0, 34.0) + vec2(world_seed * 0.3, 41.0));
		float patch = smoothstep(0.58, 0.80, field) * 0.55;
		if (rock_height < CREVICE * 0.6 && bayer4(point) < patch) {
			float glint = hash_point(point + vec2(world_seed, 5.0));
			shaped = mix(shaped, accent * (glint > 0.90 ? 0.62 : 0.34), 0.85);
		}
		if (hash_point(point + vec2(world_seed, 9.0)) > 0.9992) shaped = accent * 0.85;
	} else if (geology == 3) {
		// Basalt columns: upright prisms 16 to 48 texels wide (jittered
		// joints, never a fixed period), each face its own value with a lit
		// edge beside its joint. A joint wavers by a texel every dozen rows and
		// breaks where rubble fills it; cross joints sit at their own depth in
		// every column, from hashes independent of the column's block height
		// (an offset tied to it put every second cross joint on one row).
		float cx = point.x + floor(warp * 0.12);
		float k = floor(cx / BASALT_PITCH);
		float left = basalt_joint(k, depth);
		if (cx < left) {
			k -= 1.0;
			left = basalt_joint(k, depth);
		} else {
			float next = basalt_joint(k + 1.0, depth);
			if (cx >= next) {
				k += 1.0;
				left = next;
			}
		}
		float ch = hash_point(vec2(k, world_seed + 67.0));
		float within = cx - left;
		float span = 38.0 + floor(hash_point(vec2(k, world_seed + 69.0)) * 44.0);
		float run = depth + floor(hash_point(vec2(k, world_seed + 71.0)) * span);
		float block = floor(run / span);
		float face = mix(0.82, 1.14, ch) * mix(0.93, 1.06, hash_point(vec2(k, block + world_seed)));
		vec3 flat_face = tint * 0.55 * face;
		shaped = mix(earth * face, flat_face, 0.35);
		// The joints only shade the stone they cross: flat dark joint lines
		// (earth * 0.52 / 0.58) joined into a continuous one-pixel seam grid
		// in the wide view (review 7). The columns already part by face value.
		bool open_joint = hash_point(vec2(k, floor((depth + ch * 30.0) / 11.0) + world_seed + 73.0)) > 0.22;
		if (within < 1.0 && open_joint) shaped *= 0.84;
		else if (within < 2.0) shaped = mix(shaped * 1.08, accent * value * 2.0, 0.06);
		if (within >= 1.0 && run - block * span < 1.0 && hash_point(vec2(k, block + world_seed + 75.0)) > 0.35) shaped *= 0.90;
	} else if (geology == 4) {
		// Slag: broad pockets where black glassy slag fills the crevices and
		// the stones sit a little darker, their edges stepping out in the
		// ordered dither; rare hot specks. A flat dark lens laid over the
		// stones read as a hard shadow bar. The pockets are the rich tier's;
		// every tier keeps the specks.
		if (rich) {
			float lens = smoothstep(0.58, 0.78, stone_noise(point / vec2(64.0, 30.0) + vec2(world_seed * 0.7, 19.0)));
			if (bayer4(point) < lens) {
				shaped = rock_height < CREVICE * 1.4 ? mix(earth * 0.40, vec3(0.05, 0.045, 0.055), 0.45) : earth * mix(0.96, 0.84, lens);
			}
		}
		// Hot specks in two sizes, more of them nearer the surface.
		float speck = hash_point(floor(point / 2.0) + vec2(world_seed, 23.0));
		if (speck > mix(0.9975, 0.9993, smoothstep(0.0, 700.0, depth))) shaped = accent * (speck > 0.9995 ? 1.15 : 0.9);
	} else if (geology == 5) {
		// Loam: dark root threads hanging from the topsoil, jagged and
		// tapering out within a hundred texels or so; shell and grit flecks.
		float jag = floor(hash_point(vec2(floor(depth / 5.0), floor(point.x / 11.0) + world_seed)) * 3.0) - 1.0;
		float strand = point.x + jag;
		float root_cell = floor(strand / 11.0);
		float root = step(0.86, hash_point(vec2(root_cell, world_seed + 33.0))) * step(fract(strand / 11.0), 0.09);
		root *= 1.0 - step(50.0 + 110.0 * hash_point(vec2(root_cell, world_seed + 35.0)), depth);
		shaped = mix(shaped, mix(shaped * 0.45, accent * 0.35, 0.5), root);
		if (hash_point(point + vec2(world_seed, 31.0)) > 0.9945) shaped = accent * 0.80;
	} else if (geology == 6) {
		// Seepage: water running down the rock in narrow trickles that waver a
		// texel to either side every dozen rows, darken and cool what they
		// cross and thin out toward their end; lit stone texels in a trickle
		// catch a sheen. No regular glints: a dotted column read as rain
		// falling through the rock.
		float lane = floor(point.x / 6.0);
		float lh = hash_point(vec2(lane, world_seed + 71.0));
		float start = hash_point(vec2(lane, world_seed + 73.0)) * 600.0;
		float streak_length = 50.0 + hash_point(vec2(lane, world_seed + 75.0)) * 140.0;
		float sway = floor(hash_point(vec2(lane, floor((depth + lh * 40.0) / 13.0) + world_seed)) * 3.0) - 1.0;
		float within = point.x - lane * 6.0 - sway;
		float along = (depth - start) / streak_length;
		float inside = step(0.68, lh) * step(0.0, along) * step(along, 1.0) * step(0.0, within) * step(within, 1.0 + floor(lh * 2.0));
		inside *= step(bayer4(point), 1.0 - smoothstep(0.55, 1.0, along));
		vec3 wet = shaped * vec3(0.50, 0.56, 0.62);
		if (rock_height > 0.16) wet = mix(wet, accent * value * 1.6, 0.30);
		shaped = mix(shaped, wet, inside);
	}
	return mix(earth, shaped, geology_strength);
}

void fragment() {
	vec2 point = floor(world_position);
	float depth = point.y - ground_line;
	vec3 earth;
	// 0 deep rock .. 1 exposed top surface: weight of sky light and lightning.
	float exposure = 0.0;
	if (depth < 0.0) {
		float rise = -depth;
		float height = cover_height(point.x);
		vec3 shape = vec3(0.0);
		float piece = rich ? feature_height(point.x, shape) : 0.0;
		if (rise > max(height, piece)) {
			discard;
		}
		if (piece > height || (shape.x > 1.5 && piece > 0.0 && rise > height - 1.0)) {
			earth = feature_color(point, rise, piece, shape);
			exposure = rise > piece - 0.5 ? 1.0 : 0.3;
		} else {
			earth = cover_color(point, rise, height);
			// Only the highest texel of a column faces the sky.
			exposure = rise > height - 0.5 ? 1.0 : 0.55;
		}
	} else {
		// Keep the original stone sizes and pixel clusters. Two tile offsets and
		// neighbouring beds interlock by stone height, never by a crossfade, so
		// no boundary is a straight line and no stone is ghosted.
		float deposits = stone_noise(point / vec2(330.0, 190.0));
		float broad = stone_noise(point / vec2(790.0, 310.0) + vec2(7.4, 2.1));
		// Beds: inclined layers a few hundred pixels thick with warped boundaries.
		float warp = (stone_noise(point / vec2(520.0, 260.0) + vec2(world_seed, 3.7)) - 0.5) * 150.0;
		if (rich) warp += (stone_noise(point / vec2(140.0, 90.0) + vec2(world_seed * 0.7, 8.1)) - 0.5) * 44.0;
		float bed_depth = depth + point.x * inclination + warp;
		// The plain tier has no stone-by-stone interlock: its bed boundary
		// steps over a few texels in the dither instead of a clean tile cut.
		if (!rich) bed_depth += (bayer4(point) - 0.5) * 6.0;
		float bed_coord = bed_depth / BED + world_seed;
		float bed = floor(bed_coord);
		float bed_edge = fract(bed_coord) * BED;
		vec3 rock = texture(TEXTURE, bed_uv(point, depth, bed)).rgb;
		float rock_height = luma(rock);
		float near_edge = min(bed_edge, BED - bed_edge);
		if (rich && near_edge < BED_BLEND) {
			float other = bed_edge < BED * 0.5 ? bed - 1.0 : bed + 1.0;
			vec3 neighbour = texture(TEXTURE, bed_uv(point, depth, other)).rgb;
			// Own bed is favoured inside, neither at the boundary itself.
			float bias = 0.5 * near_edge / BED_BLEND;
			if (luma(neighbour) > rock_height + bias * 0.9) {
				rock = neighbour;
				bed = other;
				rock_height = luma(neighbour);
			}
		}
		float bed_hash = hash_point(vec2(bed, world_seed));
		float bed_hash_b = hash_point(vec2(bed + 17.0, world_seed + 5.0));
		// Broad pockets: a second tile offset whose stones replace the first
		// where they stand higher, weighted by the pocket field.
		vec3 second_rock = texture(TEXTURE, fract(vec2(point.x + 1850.0 + bed_hash * 480.0, depth + bed_hash_b * 480.0) / 480.0 + vec2(0.413, 0.627))).rgb;
		float pocket = smoothstep(0.30, 0.72, deposits);
		if (luma(second_rock) + pocket * 0.8 > rock_height + 0.4) {
			rock = second_rock;
			rock_height = luma(second_rock);
		}
		// The source tile is a warm brown; pull it toward its own value so each
		// world's mineral tint decides the hue instead of the shared tile.
		rock = mix(rock, vec3(rock_height), 0.72) * 1.85;
		// Irregular sediment bands cross several source tiles and are fixed in the
		// world. They tint the existing art rather than add floating ore or decals.
		float seam_depth = depth + point.x * inclination + (broad - 0.5) * 155.0;
		float band = sin(seam_depth * 0.034 + deposits * 1.4) * 0.5 + 0.5;
		float seam = smoothstep(0.66, 0.91, band) * 0.60;
		vec3 mineral = rock_tint.rgb * rock_tint.rgb * 1.45;
		vec3 vein = seam_tint.rgb * seam_tint.rgb * 1.50;
		vec3 tint = mix(mineral, vein, clamp(seam + (bed_hash - 0.5) * 0.40, 0.0, 1.0));
		// Near the surface the rock takes the painted land's hue.
		float upper = 1.0 - smoothstep(20.0, 360.0, depth);
		vec3 land_hue = land_tint.rgb / max(0.08, luma(land_tint.rgb));
		tint = mix(tint, land_hue * luma(mineral), upper * 0.38);
		// Depth: daylight is gone within a few rooms; far below only value remains.
		float sink = smoothstep(30.0, 1150.0, depth);
		float shade = mix(0.84, 1.14, broad) * mix(0.86, 1.12, bed_hash_b) * mix(1.0, 0.36, sink);
		// The first rooms of a daylight world sit in lighter, sunlit ground.
		shade *= 1.0 + 0.30 * daylight * upper;
		// Rare large hollows of darker, finer rock.
		float hollow = smoothstep(0.71, 0.86, stone_noise(point / vec2(1150.0, 520.0) + vec2(world_seed * 0.37, 11.0)));
		shade *= mix(1.0, 0.72, hollow);
		earth = rock * tint * shade;
		if (geology > 0) earth = apply_geology(earth, point, depth, rock_height, warp, tint * shade);
		earth = mix(earth, vec3(luma(earth)) * vec3(0.90, 0.97, 1.10), sink * 0.45);

		// Everything below lives in the first rows under the ground line; the
		// deep rock skips its noise entirely (cheaper on software rasterisers).
		if (depth < 80.0) {
			// Topsoil: a horizon of the world's own ground (frozen soil, loam, mud,
			// layered ash, sand, road gravel) whose lower edge follows the stones.
			float run = floor(point.x / 3.0);
			float column = hash_point(vec2(run, world_seed + 1.0));
			float slow_column = hash_point(vec2(floor(point.x / 7.0), world_seed + 2.0));
			float drift = stone_noise(vec2(point.x / 46.0, world_seed));
			float speck = hash_point(point + vec2(world_seed, 0.0));
			float horizon = 16.0 + 30.0 * stone_noise(vec2(point.x / 96.0, world_seed + 13.0)) + 9.0 * stone_noise(vec2(point.x / 27.0, world_seed + 15.0));
			if (depth < horizon + 18.0) {
				// Clods: flattened lumps of three hard values (no dither), with dark
				// pores and a few pale grains, at the art's texel density.
				float clod = stone_noise(point / vec2(8.0, 4.5) + vec2(world_seed, 71.0));
				if (rich) clod = clod * 0.66 + stone_noise(point / 3.0 + vec2(world_seed, 73.0)) * 0.34;
				vec3 subsoil = subsoil_tint.rgb * (clod < 0.40 ? 0.74 : (clod < 0.60 ? 0.94 : 1.14));
				if (speck > 0.90) subsoil *= 0.70;
				else if (speck < 0.025) subsoil *= 1.22;
				float grain = hash_point(floor(point / 2.0) + vec2(world_seed, 7.0));
				float near = 1.0 - clamp(depth / max(horizon, 1.0), 0.0, 1.0);
				if (surface_kind == 1) {
					// Frozen soil: hoar frost thinning with depth, small ice lenses
					// that swell to two texels in their middle and break up toward
					// their tips (a one-texel pale dash read as a wind streak).
					if (speck > mix(0.995, 0.93, near)) subsoil = mix(subsoil, cap_tint.rgb * 0.84, 0.8);
					float lens = stone_noise(vec2(point.x / 21.0, floor(depth / 5.0) + world_seed));
					float row = mod(depth, 5.0);
					if (lens > 0.80 && row < (lens > 0.88 ? 2.0 : 1.0) && bayer4(point) < smoothstep(0.80, 0.88, lens) * 1.6) subsoil = mix(subsoil, cap_tint.rgb * vec3(0.70, 0.80, 0.94) * (row < 1.0 ? 1.0 : 0.82), 0.32);
				} else if (surface_kind == 2) {
					// Loam with pale root threads hanging from the turf.
					float root_x = point.x + floor(sin(depth * 0.21 + slow_column * 6.0) * 2.0);
					float root = step(0.88, hash_point(vec2(floor(root_x / 2.0), world_seed + 33.0))) * step(fract(root_x / 2.0), 0.4);
					root *= 1.0 - step(horizon * (0.35 + 0.55 * hash_point(vec2(floor(root_x / 2.0), world_seed + 35.0))), depth);
					subsoil = mix(subsoil, soil_tint.rgb * 0.70, root * 0.75);
				} else if (surface_kind == 3) {
					// Mud: water standing in the upper pores catches the sky.
					if (speck > mix(0.99, 0.95, near)) subsoil = mix(subsoil, cap_tint.rgb * 0.75 + accent_tint.rgb * 0.15, 0.7);
				} else if (surface_kind == 4) {
					// Pale fall layers of uneven thickness between the cinder beds.
					float layer = fract((depth + stone_noise(vec2(point.x / 40.0, world_seed + 75.0)) * 9.0) / 9.0);
					subsoil = mix(subsoil, cap_tint.rgb * mix(0.56, 0.66, grain), step(0.62, layer) * step(layer, 0.80) * 0.85);
					if (speck > 0.996 && depth < 9.0) subsoil = accent_tint.rgb * 0.8;
				} else if (surface_kind == 5) {
					// Sand: faint cross-bedded laminae.
					float lamina = step(0.62, fract((depth + point.x * 0.32 + drift * 9.0) / 6.0));
					subsoil *= mix(1.0, 0.90, lamina);
				}
				// Pebbles: small rounded stones lit from above, on the texel grid.
				vec2 cell = floor(point / 7.0);
				float pebble_hash = hash_point(cell + vec2(world_seed * 1.7, 41.0));
				if (pebble_hash > (surface_kind == 0 ? 0.78 : 0.90)) {
					vec2 centre = cell * 7.0 + vec2(2.0, 2.0) + floor(vec2(hash_point(cell + vec2(3.1, 0.0)), hash_point(cell + vec2(7.7, 0.0))) * 3.0);
					vec2 offset = point - centre;
					float radius = 1.2 + floor(hash_point(cell + vec2(9.3, 0.0)) * 2.0);
					if (offset.x * offset.x + offset.y * offset.y * 1.5 <= radius * radius) {
						vec3 stone = mineral * mix(0.55, 0.80, hash_point(cell + vec2(11.0, 0.0)));
						if (offset.y < -0.5 && offset.x < 0.5) stone *= 1.25;
						else if (offset.y > 0.5) stone *= 0.70;
						subsoil = stone;
					}
				}
				// The horizon's lower edge: stones rise into the soil where they stand
				// higher than the soil's own uneven floor.
				float reach = (depth - horizon) / 18.0;
				if (rock_height + reach * 0.9 < 0.42 + (grain - 0.5) * 0.12) {
					earth = subsoil;
				}
			}
			// Ground cover. Columns are grouped in small runs so the lower edge of the
			// cap is uneven without leaving the pixel grid. Only what is drawn changes:
			// floors, mining cells and collision are separate nodes.
			if (surface_kind == 0) {
				// The road's compacted upper lip uses the same unlimited field as the
				// geology, so a wide camera cannot reveal either end of a decorative strip.
				if (depth < 7.0) {
					float wear = hash_point(vec2(floor(point.x / 7.0), floor(depth / 2.0)));
					earth = soil_tint.rgb * mix(0.73, 0.84, wear);
					exposure = depth < 1.0 ? 1.0 : 0.4;
				} else if (depth >= 8.0 && depth < 11.0) {
					float grit = step(0.40, fract(point.x / 19.0));
					earth = mix(earth, seam_tint.rgb * 0.56, grit * 0.65);
				}
			} else {
				float thickness = 5.0;
				vec3 cap = cap_tint.rgb;
				if (surface_kind == 1) {
					// Snow: a soft drifted cap shaded in horizontal layers (lit crust,
					// body, cooler underside), a blue shadow under its lip, frozen soil
					// below. No per-column value bands: the drift varies only broadly.
					thickness = 7.0 + floor(drift * 5.0 + slow_column * 0.9);
					float layer = depth < 1.0 ? 1.0 : (depth < 3.0 ? 0.94 : (depth < thickness - 3.0 ? 0.89 : 0.84));
					cap = cap_tint.rgb * layer * mix(0.97, 1.02, drift);
					if (speck > 0.975 && depth >= 1.0 && depth < 4.0) cap = min(cap_tint.rgb * 1.06, vec3(1.0));
					if (depth >= thickness - 1.0) cap = cap_tint.rgb * vec3(0.60, 0.70, 0.86);
				} else if (surface_kind == 2) {
					// Moss and short grass: light blades on top, a ragged hanging fringe.
					thickness = 4.0 + floor(column * 4.0) + floor(drift * 2.0);
					cap = cap_tint.rgb * (depth < 1.0 ? mix(1.18, 1.42, step(0.5, speck)) : mix(0.72, 0.98, column));
					if (depth >= thickness - 2.0 && speck > 0.5) cap = cap_tint.rgb * 0.52;
				} else if (surface_kind == 3) {
					// Wet ground: dark saturated crust with broken sky glints on top.
					thickness = 6.0 + floor(drift * 1.6 + slow_column * 0.9);
					cap = cap_tint.rgb * mix(0.92, 1.10, hash_point(vec2(floor(point.x / 7.0), floor(depth / 2.0))));
					float glint = step(0.58, stone_noise(vec2(point.x / 23.0, world_seed + 9.0)));
					if (depth < 1.0) cap = mix(cap * 1.12, accent_tint.rgb * 0.45 + cap_tint.rgb * 0.95, glint * 0.85);
					else if (depth < 2.0) cap *= mix(1.0, 1.22, glint);
					else if (depth >= thickness - 2.0) cap *= 0.74;
				} else if (surface_kind == 4) {
					// Ash: pale powder, dark cinders and a rare live ember.
					thickness = 4.0 + floor(drift * 4.0 + slow_column * 0.9);
					cap = cap_tint.rgb * mix(0.74, 0.96, hash_point(vec2(floor(point.x / 5.0), floor(depth / 2.0))));
					if (depth < 1.0) cap *= 1.14;
					if (speck > 0.93) cap = cap_tint.rgb * 0.38;
					if (speck > 0.9965 && depth < 3.0) cap = accent_tint.rgb;
				} else {
					// Sand and dust: wind ripples of two values over a firm lower edge.
					thickness = 4.0 + floor(drift * 5.0 + slow_column * 0.9);
					float ripple = step(0.5, fract((point.x + depth * 3.0) / 11.0));
					cap = cap_tint.rgb * mix(0.80, 0.95, ripple);
					if (depth < 1.0) cap = cap_tint.rgb * 1.08;
					if (speck > 0.95) cap *= 0.72;
				}
				if (depth < thickness) {
					earth = cap;
					exposure = depth < 1.0 ? 0.8 : 0.35;
				} else if (depth < thickness + 2.0) {
					// Contact line: the cover shades the first rows of soil beneath it.
					earth = mix(earth, seam_tint.rgb * 0.34, 0.80);
				}
			}
		}
	}
	// Ambient colours the surface; its hue fades out with depth.
	// Rock is already the darkest value on screen, so it takes only half of the
	// ambient drop and keeps its bedding readable at night.
	float reach_ambient = depth < 0.0 ? 1.0 : (depth < 16.0 ? 0.9 : 0.5);
	vec3 soft = mix(vec3(1.0), ambient.rgb, reach_ambient);
	vec3 light = mix(soft, vec3(luma(soft)), smoothstep(0.0, 520.0, depth));
	vec3 result = earth * light;
	// The sky key catches what faces it; lightning lights the same surfaces,
	// strongest under the bolt.
	result += sky_rim.rgb * sky_rim.a * exposure * luma(earth) * 1.6;
	if (flash > 0.0) {
		float under = 1.0 - smoothstep(120.0, 1100.0, abs(point.x - flash_x));
		float lit = flash * (0.25 + 0.75 * under) * max(exposure, 1.0 - smoothstep(0.0, 10.0, depth));
		result = mix(result, result * 1.9 + vec3(0.78, 0.86, 1.0) * 0.10, lit * 0.8);
	}
	COLOR = vec4(result, 1.0);
}
