// Effect shapes on the actor texel grid (one texel per world unit).
// PixelEffectArt.grid_*() emit one textured quad per shape whose UV carries the
// local coordinate (-1..1) plus an encoded shape in whole steps of four:
// UV.x + 4 * (variant + 64 * level), UV.y + 4 * (16 + shape * 32 + step), where
// step is the thin step 0..16 for shapes 0-7 and a full 0..31 for shapes 8+.
// level (0..15) is a per-shape parameter: heat for fire, fire light on smoke,
// thickness for rings. The fragment evaluates the shape once per world texel
// (every pixel of a texel samples its centre), so silhouettes step in whole
// texels at any camera zoom, and a dissolving shape drops texels instead of
// fading softly. Everything else the node draws (debris, lines, rects: UV
// inside 0..1) passes through unchanged.
// Each shader's vertex() fills this with the world position of the vertex.
varying vec2 grid_world;

const float GRID_EDGE[16] = float[16](0.0, -.10, .06, -.04, .11, -.08, .03, .09, -.12, .05, -.02, .08, -.07, .10, -.05, .02);
const float GRID_BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
// Key light of every cel-shaded mass: from the sky, upper left.
const vec2 GRID_LIGHT = vec2(-.55, -.835);
// Fire ramp, hottest first: white heart, pale yellow, amber, orange, red, ember.
const vec3 GRID_FIRE[6] = vec3[6](vec3(1.0, .984, .902), vec3(1.0, .878, .541), vec3(1.0, .667, .235), vec3(.933, .416, .141), vec3(.698, .227, .110), vec3(.361, .125, .094));

float grid_bayer(vec2 texel) {
	ivec2 cell = ivec2(mod(texel, 4.0));
	return (GRID_BAYER[cell.x + cell.y * 4] + .5) / 16.0;
}

float grid_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth value noise: clumps of texels instead of a per-texel speckle.
float grid_value(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = grid_hash(cell);
	float b = grid_hash(cell + vec2(1.0, 0.0));
	float c = grid_hash(cell + vec2(0.0, 1.0));
	float d = grid_hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Dissolve order of a texel: the 4x4 ordered dither, clumped by a coarse
// per-shape noise so holes open as irregular wisps rather than a dot screen.
float grid_order(vec2 texel, int variant) {
	vec2 shift = vec2(float(variant), float(variant * 3 + 1));
	vec2 coarse = floor((texel + shift * 5.0) / 3.0);
	return clamp(grid_bayer(texel) * .45 + grid_hash(coarse) * .55, 0.0, 1.0);
}

// Bumpy cloud outline of the cel masses: a few lobes around the rim.
float grid_lumps(vec2 at, float v) {
	float a = atan(at.y, at.x);
	return 1.0 + .075 * sin(a * 3.0 + v * 1.7) + .05 * sin(a * 5.0 + v * 2.9) + .03 * sin(a * 9.0 + v * .7);
}

// Integer lattice hash (no sine): cheap on GPUs and software rasterisers alike.
// Cells stay small (shape-local noise), so the offset keeps them positive.
float grid_ihash(float x, float y) {
	uint h = uint(int(x) + 65536) * 668265261u ^ (uint(int(y) + 65536) * 374761393u + 2654435769u);
	h ^= h >> 15u;
	h *= 739982445u;
	h ^= h >> 12u;
	h *= 695872825u;
	h ^= h >> 15u;
	return float(h >> 8u) * (1.0 / 16777216.0);
}

// Value noise whose lattice repeats every `period` cells along y: a scroll of
// exactly `period` cells per loop of the procedural flipbook is seamless.
float grid_noise(vec2 p, float period) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float y0 = mod(cell.y, period);
	float y1 = mod(cell.y + 1.0, period);
	return mix(mix(grid_ihash(cell.x, y0), grid_ihash(cell.x + 1.0, y0), f.x), mix(grid_ihash(cell.x, y1), grid_ihash(cell.x + 1.0, y1), f.x), f.y);
}

// Smoke mass (shape 8): a cluster of round billows inside the unit disk, laid
// out from the variant and seen front-most first, each shaded as a sphere lit
// from the sky (lit edge, body, shade, a shadowed crescent; the cluster's
// lower part one tone darker and, while fresh above a fire, warm). Billow rims
// wobble on a little shape-local noise. fade 0..1 eats the billows from their
// rims inward through the ordered dither (translucent wisps), never by
// shrinking them; the thin rim of fresh smoke is dithered too.
bool grid_smoke(vec2 at, vec2 texel, float radius, float v, float warmth, float fade, inout vec4 color) {
	if (dot(at, at) > 1.0) return false;
	// One world texel in the shape's local units.
	float px = 1.0 / max(radius, 1.0);
	// A gentle, low-frequency wobble keeps billow rims round but hand-drawn.
	float wobble = grid_noise(at * clamp(radius * .09, .9, 2.2) + vec2(v * 3.1 + 5.0, v * 1.7 + 3.0), 4096.0) - .5;
	int count = radius < 5.0 ? 3 : (radius < 16.0 ? 5 : 6);
	vec2 light = normalize(GRID_LIGHT);
	// The texel just toward the sky from this one: a billow in front that
	// covers it casts a shadow here (a shaded seam under each front billow).
	vec2 probe = at + light * px * 2.2;
	float best = -9.0;
	vec2 normal = vec2(0.0);
	float height = 0.0;
	float low = 0.0;
	float span = 1.0;
	float cover = -9.0;
	float own = -9.0;
	for (int index = 0; index < 7; index++) {
		if (index >= count) break;
		float fi = float(index);
		// A broad base billow and a crown of smaller ones across its top.
		vec2 centre = vec2(0.0, .14);
		float size = .58;
		float depth = 0.0;
		if (index > 0) {
			float angle = -3.1416 * (.06 + .88 * (fi - 1.0) / float(max(count - 2, 1))) + (grid_ihash(v, fi + 1.0) - .5) * .6;
			centre = vec2(cos(angle), sin(angle)) * (.36 + .16 * grid_ihash(fi + 9.0, v)) + vec2(0.0, .08);
			size = .32 + .15 * grid_ihash(v + 31.0, fi);
			float reach = length(centre) + size;
			if (reach > .97) centre *= max(.97 - size, 0.0) / max(length(centre), .001);
			// Upper billows sit in front, so their lit caps overlap the body.
			depth = (grid_ihash(fi + 3.0, v + 11.0) - .5) * .30 - centre.y * .25;
		}
		vec2 d = (at - centre) / size;
		float h = 1.0 - dot(d, d) + wobble * .22;
		vec2 e = (probe - centre) / size;
		float k = 1.0 - dot(e, e) + wobble * .22;
		float reach_z = k > 0.0 ? depth + size * sqrt(k) : -9.0;
		float z = h > 0.0 ? depth + size * sqrt(h) : -9.0;
		if (h > 0.0 && z > best) {
			// The previous front billow may still shade this one's seam.
			cover = max(cover, own);
			own = reach_z;
			best = z;
			normal = d;
			height = h;
			low = centre.y;
			span = size;
		} else cover = max(cover, reach_z);
	}
	if (best < -1.0) return false;
	// Hand-shaded billows: a round lit cap set toward the sky, the body, a
	// shaded crescent on the far rim, and a shaded seam where a billow in
	// front overlaps this one. The caps are offset circles, never a straight
	// cut across the billow, so a cluster never shows parallel bands.
	float jitter = (grid_bayer(texel) - .5) * px / span * 1.4;
	// The whole cluster is lit from the sky too: caps grow on its sky side
	// and shade crescents widen on the far side, so it reads as one mass.
	float side = dot(at, light);
	float tone_index = 1.0;
	if (length(normal - light * .48) < .50 + side * .30 + wobble * .20 + jitter) tone_index = 2.0;
	else if (length(normal - light * .26) > 1.0 - max(-side, 0.0) * .45 + jitter) tone_index = 0.0;
	// The seam: a billow in front reaches over the texel toward the sky.
	if (cover > best + .02 * span) tone_index = min(tone_index, 0.0) - (tone_index > .5 ? 0.0 : 1.0);
	// The billows low in the cluster lie in its own shadow: no lit cap.
	if (low > .30 && tone_index > 1.5) tone_index = 1.0;
	vec3 body = color.rgb;
	vec3 tone = tone_index > 1.5 ? min(body * 1.22 + vec3(.07, .07, .075), vec3(1.0)) : (tone_index > .5 ? body : (tone_index > -.5 ? body * .80 + vec3(-.006, 0.0, .014) : body * .66 + vec3(-.01, 0.0, .02)));
	if (warmth > 0.0 && tone_index < 1.5) {
		// Fire light from below on the underside of fresh smoke.
		// In three dithered steps, not a smooth gradient.
		float under = floor(smoothstep(-.05, .70, at.y) * 3.0 + grid_bayer(texel) * .999) / 3.0 * (tone_index < .5 ? 1.0 : .55);
		tone = mix(tone, vec3(.88, .43, .16) * (.50 + .50 * clamp(dot(body, vec3(.9)) * 1.6, 0.0, 1.0)), warmth * under * .80);
	}
	color.rgb = clamp(tone, 0.0, 1.0);
	// Thinning: the outermost texel of fresh smoke is a half-dithered soft
	// edge; with age, clumps of texels (a few texels across, fixed to the
	// puff) leave from the rims inward, so it frays into wisps instead of a
	// dot screen, and what is left turns translucent.
	float rim = clamp(height / min((.8 + fade * 4.0) * 2.0 * px / span, .40), 0.0, 1.0);
	if (fade > .04 && rim < 1.0 && grid_bayer(texel) > rim) return false;
	float clump = grid_noise(at * radius / 3.2 + vec2(v * 5.3 + 1.0, v * 2.9 + 7.0), 4096.0);
	float core = clamp(height, 0.0, 1.0);
	float keep = core * .55 + clump * .55 + (grid_bayer(texel) - .5) * .10;
	if (keep < fade * 1.25 - .05) return false;
	color.a *= mix(.94, .60, fade);
	return true;
}

// Flame (shape 9): a procedural flipbook of 32 frames on a looping lattice.
// The quad spans base (local y +1) to tip (y -1); tongues rise through a
// banded ramp (pale core near the base, yellow, orange, red, dark-red tips),
// sway, and tear off as separate licks near the top. heat 0..1 shrinks and
// reddens a dying fire.
bool grid_flame(vec2 at, vec2 radii, float v, float heat, float frame, inout vec4 color) {
	float t = (1.0 - at.y) * .5;
	vec2 p = vec2(at.x * radii.x, at.y * radii.y);
	vec2 q = vec2(p.x / 2.4 + v * 7.3, p.y / 3.5 + frame * .5);
	float n = grid_noise(q, 16.0) * .62 + grid_noise(q * 2.0 + vec2(3.7, 0.0), 32.0) * .38;
	float sway = (grid_noise(vec2(v * 1.31, frame * .25), 8.0) - .5) * 2.0;
	float x = at.x - sway * t * t * .30;
	// Wide low body narrowing to the tip, rounded where it leaves the wood.
	float half_width = .86 * pow(max(1.0 - t, 0.0), .65) * mix(.66, 1.0, smoothstep(0.0, .16, t));
	float across = abs(x) / max(half_width, .03);
	float f = (1.0 - across * across) * (1.05 - t * .55) - t * .60 + (n - .5) * (.42 + t * 1.05);
	f = f * (.62 + .38 * heat) + heat * .06;
	// The lowest rows burn redder: no flat bright line along the base.
	f -= (1.0 - smoothstep(0.0, .09, t)) * .30;
	if (f < .08) return false;
	vec3 tone = (f > .86 && t < .32) ? vec3(1.0, .96, .80) : (f > .64 ? vec3(1.0, .80, .30) : (f > .42 ? vec3(.97, .50, .15) : (f > .24 ? vec3(.78, .24, .09) : vec3(.44, .11, .07))));
	color.rgb *= tone;
	return true;
}

// Breakup of the cel masses: clusters of texels in the shape's own frame leave
// together, the rim first, so old smoke tears into a few ragged pieces that
// travel with it instead of turning into a uniform dot screen.
bool grid_eroded(vec2 local_texel, vec2 texel, float rim, float thin, int variant, float cell) {
	float clump = grid_value(local_texel / cell + vec2(float(variant) * 3.1, float(variant) * 1.7));
	float score = clump * .46 + (1.0 - clamp(rim, 0.0, 1.0)) * .54 + (grid_bayer(texel) - .5) * .05;
	return score < thin * 1.02;
}

// Returns false when the fragment must be discarded; tints COLOR for facets.
// Shapes: 0 blob, 1 puff (lumpier, with facets), 2 bar (oriented rectangle:
// streaks and lines), 3 diamond (debris shards), 4 cel mass (dust: three
// tones from COLOR, level = fire light from below), 5 fire mass (fixed ramp,
// level = heat), 6 ring (level = thickness), 7 petal (flame tongue). Shapes 8
// and up use the whole 0..31 step: 8 smoke (step = fade, level = warmth),
// 9 flame (step = flipbook frame, level = heat), 10 halo (additive glow).
bool grid_shape(vec2 uv, inout vec4 color) {
	vec2 code = floor((uv + 2.0) * .25);
	vec2 local = uv - code * 4.0;
	int variant = int(mod(code.x, 64.0));
	float level = floor(code.x / 64.0) / 15.0;
	float packed = code.y - 16.0;
	float shape = floor(packed / 32.0);
	float thin = (packed - shape * 32.0) / 16.0;
	vec2 texel = floor(grid_world);
	// Local coordinate of this texel's centre, from the affine screen derivatives.
	mat2 to_world = mat2(dFdx(grid_world), dFdy(grid_world)) * inverse(mat2(dFdx(local), dFdy(local)));
	vec2 at = inverse(to_world) * (texel + .5 - grid_world) + local;
	float radius = length(to_world[0]);
	if (shape > 7.5) {
		// Shapes with 32 steps: 8 smoke (step = fade), 9 flame (step = frame),
		// 10 halo (additive glow in dithered bands).
		float step_value = packed - shape * 32.0;
		if (shape > 9.5) {
			float d = length(at);
			if (d >= 1.0) return false;
			float g = (1.0 - d) * (1.0 - d);
			float band = floor(g * 3.0 + grid_bayer(texel) * .999) / 3.0;
			if (band <= 0.0) return false;
			color.a *= band;
			return true;
		}
		if (shape > 8.5) return grid_flame(at, vec2(radius, length(to_world[1])), float(variant), level, step_value, color);
		return grid_smoke(at, texel, radius, float(variant), level, step_value / 31.0, color);
	}
	if (shape > 3.5) {
		float v = float(variant);
		float rim = 1.0;
		if (shape > 6.5) {
			// Petal: widest a third of the way from its base (x = -1) to its tip.
			float half_width = at.x < -.4 ? (at.x + 1.0) / .6 : (1.0 - at.x) / 1.4;
			if (at.x < -1.0 || at.x > 1.0 || abs(at.y) > half_width) return false;
			rim = abs(at.y) / max(half_width, .001);
		} else if (shape > 5.5) {
			float d = length(at) / (1.0 + .04 * sin(atan(at.y, at.x) * 7.0 + v));
			float inner = 1.0 - (level * 15.0 + 1.0) * .045;
			if (d > 1.0 || d < inner) return false;
			rim = .55;
		} else {
			float lump = grid_lumps(at, v);
			float boil = 0.0;
			if (shape > 4.5) {
				// Fire boils: turbulent tongues inside and along the rim, their
				// pattern rolling on as the mass cools (level steps).
				boil = grid_noise(at * 2.7 + vec2(v * 2.3 + 3.0, v * 1.1 + level * 2.4), 4096.0) - .5;
				lump += boil * .20;
			}
			float d = length(at) / lump;
			if (d > 1.0) return false;
			rim = d;
			if (shape > 4.5) {
				// Fire: banded ramp, hottest at the heart; a cooling mass slides
				// down the ramp from white and yellow to orange, red and ember.
				float q = length(at - GRID_LIGHT * .16) / lump;
				// The whole ramp shows across every ball (white or yellow heart,
				// amber and orange body, a red rim) so it never reads as a flat
				// disc; cooling shifts the ramp outward-in.
				float cool = (1.0 - level) * .85 + q * .95 + boil * .70 - .12 + (grid_bayer(texel) - .5) * .06;
				color.rgb *= GRID_FIRE[clamp(int(cool * 3.4), 0, 5)];
			} else {
				// Smoke and dust: lit cap, body, shaded crescent and a deep rim
				// below, cut by offset circles like a hand-shaded pixel ball.
				// Fresh smoke keeps the fire's glow on its underside.
				vec3 body = mix(color.rgb, color.rgb * vec3(1.22, .90, .76) + vec3(.06, .02, 0.0), level * .55);
				vec3 tone = body;
				if (length(at - GRID_LIGHT * .40) / lump < .60) tone = body * 1.24 + vec3(.05, .045, .035);
				else if (length(at - GRID_LIGHT * .32) / lump > 1.06) tone = mix(body * .58 + vec3(-.012, 0.0, .02), vec3(.62, .22, .09), level * .85);
				else if (length(at - GRID_LIGHT * .20) / lump > .90) tone = mix(body * .70 + vec3(-.012, 0.0, .018), vec3(.80, .36, .13), level * .85);
				color.rgb = clamp(tone, 0.0, 1.0);
			}
		}
		if (thin > 0.0 && grid_eroded(at * radius, texel, rim, thin, variant, clamp(radius * .22, 2.5, 7.0))) return false;
		return true;
	}
	// How far out this texel sits (0 centre, 1 rim): dissolving shapes erode
	// from the rim inwards.
	float rim = 1.0;
	if (shape > 2.5) {
		rim = abs(at.x) + abs(at.y);
		if (rim > 1.0) return false;
	} else if (shape > 1.5) {
		rim = max(abs(at.x), abs(at.y));
		if (rim > 1.0) return false;
	} else {
		vec2 p = at * radius;
		float chord2 = radius * radius - p.y * p.y;
		if (chord2 <= 0.0) return false;
		float chord = sqrt(chord2);
		int row = int(floor(p.y * .5));
		float lump = shape > .5 ? 2.0 : 1.0;
		float left = -chord * (1.0 + GRID_EDGE[(row * 3 + variant * 5) & 15] * lump);
		float right = chord * (1.0 + GRID_EDGE[(row * 5 + variant * 7 + 3) & 15] * lump);
		if (p.x < left || p.x >= right) return false;
		rim = length(at);
		if (shape > .5) {
			// Puff: a lighter upper-left and a darker lower facet on the same grid.
			if (at.x >= -.42 && at.x < .16 && at.y >= -.47 && at.y < -.25) color.rgb = mix(color.rgb, min(color.rgb * 1.12 + .03, vec3(1.0)), .32);
			else if (at.x >= .06 && at.x < .64 && at.y >= .28 && at.y < .50) color.rgb = mix(color.rgb, color.rgb * .78, .30);
		}
	}
	// Ordered dither, phase-shifted per shape so stacked layers never drop the
	// same texels; the rim goes first, the core last.
	if (thin > 0.0) {
		float erode = clamp(thin * (.55 + .9 * min(rim, 1.0)) + thin * thin * .45, 0.0, 1.0);
		if (grid_order(texel, variant) < erode) return false;
	}
	return true;
}
