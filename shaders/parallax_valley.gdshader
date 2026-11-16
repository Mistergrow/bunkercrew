shader_type canvas_item;
// Painted backdrop: keeps its authored value under world ambient and lamps.
render_mode unshaded;
global uniform float beat_pulse;
#include "res://shaders/background_sampling.gdshaderinc"
uniform float scene_clock = 0.0;
uniform float motion_gain = 1.0;
// Data texture: painted water R, falling water G, solid ice B. All region
// boundaries and dry islands are authored against this exact foreground plate.
uniform sampler2D surface_mask : filter_nearest, repeat_disable, hint_default_black;
uniform vec4 surface_bounds = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool surface_enabled = false;
uniform float water_travel_texels : hint_range(0.0, 3.0) = 2.0;
uniform float flow_travel_texels : hint_range(0.0, 4.0) = 3.0;
uniform float water_glint : hint_range(0.0, 0.06) = 0.022;
uniform float flow_glint : hint_range(0.0, 0.06) = 0.016;
uniform float ice_glint : hint_range(0.0, 0.04) = 0.032;
// Light carried by moving water, on top of the texel transport above: lit
// streak sheets that run down every masked fall column, drifting white crests
// on turbulent water (region strength above ~0.7) and sparse travelling
// glitter on calm water. Each only recolours texels inside its own mask, in
// whole source texels and a few stepped values (no gradients).
uniform float flow_foam : hint_range(0.0, 1.0) = 0.65;
uniform float flow_speed_texels : hint_range(0.0, 160.0) = 64.0;
// Painted texels of a fall scroll down by up to flow_period texels at
// flow_scroll texels per second (0: the bounded ping-pong travel only).
uniform float flow_scroll : hint_range(0.0, 120.0) = 46.0;
uniform float flow_period : hint_range(4.0, 32.0) = 14.0;
uniform float water_foam : hint_range(0.0, 1.0) = 0.6;
uniform float light_gain = 1.0;
varying vec4 modulation;
void vertex() { modulation = COLOR; }
// Arithmetic cell hash (no per-texel sine).
float cell_hash(vec2 cell) {
	vec2 h = fract(cell * vec2(0.1031, 0.11369));
	h += dot(h, h.yx + 19.19);
	return fract((h.x + h.y) * h.x);
}
vec3 surface_at(vec2 uv) {
	vec2 local = (uv - surface_bounds.xy) / surface_bounds.zw;
	if (any(lessThan(local, vec2(0.0))) || any(greaterThanEqual(local, vec2(1.0)))) { return vec3(0.0); }
	return texture(surface_mask, local).rgb;
}
void fragment() {
	// Keep the original camera footprint. Derivatives of stepped, animated UVs
	// would select different mip levels even on adjacent unmasked bank pixels.
	// In world texel blocks every effect below runs on the block centre, so
	// water, lamps and glints step per world texel like the rest of the plate.
	bool blocks = world_block.x > 0.0;
	vec2 sample_uv = blocks ? world_block_uv(UV) : UV;
	vec2 smooth_uv = background_uv(UV, TEXTURE_PIXEL_SIZE);
	vec2 original_uv = blocks ? sample_uv : smooth_uv;
	// Block centres carry no derivatives: a footprint of half a block selects
	// the prefilter level (0 up to two source texels per block).
	vec2 gradient_x = blocks ? vec2(world_block.x * .5, 0.0) : dFdx(smooth_uv);
	vec2 gradient_y = blocks ? vec2(0.0, world_block.y * .5) : dFdy(smooth_uv);
	vec4 source = textureGrad(TEXTURE, original_uv, gradient_x, gradient_y);
	vec3 mask = vec3(0.0);
	vec2 shift = vec2(0.0);
	bool scrolling = false;
	vec2 scroll_a = vec2(0.0);
	vec2 scroll_b = vec2(0.0);
	float scroll_mix = 1.0;
	float glint = 0.0;
	// Stepped light of moving water: -1 trough, +1 lit sheet, +2 white crest.
	float sheet = 0.0;
	float sheet_weight = 0.0;
	vec2 pixel = floor(sample_uv / TEXTURE_PIXEL_SIZE);
	if (surface_enabled && motion_gain > 0.0) {
		// Generated opaque plate texels often carry alpha 251–254. Gate their
		// silhouettes, without weakening an already feathered liquid mask twice.
		mask = surface_at(sample_uv) * step(.98, source.a);
		if (mask.r > 0.0 || mask.g > 0.0) {
			// Integer source-pixel offsets retain painted clusters and their palette.
			// Two interacting long swells move reflection rows rather than the lake.
			float swell = sin(pixel.y * .10 - scene_clock * 1.25 + sin(pixel.x * .011 + scene_clock * .21));
			float ripple = sin(pixel.y * .28 + pixel.x * .018 - scene_clock * 2.2);
			vec2 travel = vec2((swell * .72 + ripple * .28) * water_travel_texels, 0.0) * mask.r;
			// Falling water scrolls through the painted falling-water column. The
			// bounded ping-pong travel avoids importing concrete from its ends.
			float falling = sin(pixel.y * .22 - scene_clock * 3.7 + pixel.x * .025);
			travel += vec2(0.0, falling * flow_travel_texels) * mask.g;
			shift = round(travel * motion_gain) * TEXTURE_PIXEL_SIZE;
			vec3 neighbor = surface_at(sample_uv + shift);
			// Both source and destination must belong to the same surface: shores,
			// reeds, piers, machinery and alpha silhouettes never slide into water.
			float safe = max(min(mask.r, neighbor.r), min(mask.g, neighbor.g));
			shift *= step(.02, safe);
			if (mask.g > .02 && flow_scroll > 0.0) {
				// The painted fall itself runs downward without end: two copies of
				// it, scrolled half a period apart, cross-fade so that each one is
				// invisible at the moment it wraps around (a flow-map crossfade;
				// the blend reads as the motion blur of falling water). Each copy
				// samples only texels of the same fall (else it stays put).
				float column = floor(pixel.x * .5);
				float h = cell_hash(vec2(column, 5.0));
				float phase = fract(scene_clock * flow_scroll * (.85 + .3 * h) / flow_period + h);
				scroll_mix = 1.0 - abs(2.0 * phase - 1.0);
				vec2 first = vec2(0.0, -floor(phase * flow_period)) * TEXTURE_PIXEL_SIZE;
				vec2 second = vec2(0.0, -floor(fract(phase + .5) * flow_period)) * TEXTURE_PIXEL_SIZE;
				scroll_a = surface_at(sample_uv + first).g > .02 ? first : shift;
				scroll_b = surface_at(sample_uv + second).g > .02 ? second : shift;
				scrolling = true;
			}
			glint = (swell * .65 + ripple * .35) * water_glint * mask.r * motion_gain;
			glint += smoothstep(.55, .95, falling) * flow_glint * mask.g * motion_gain;
			if (mask.g > .02 && flow_foam > 0.0) {
				// Two-texel streak columns, each with its own speed, length and
				// phase, scrolling downward without end: the water visibly falls
				// while the painted column and its edges stay where they are.
				// Sheets: wavy bands a few texels apart run down the whole fall
				// width together (a lagging column here and there), broken into
				// dashes so the painted streaks still show between them.
				float column = floor(pixel.x * .5);
				float h1 = cell_hash(vec2(column, 3.0));
				float lag = sin(column * .83) * 2.2 + sin(column * .27 + 1.7) * 3.0 + floor(h1 * 3.0);
				float fallen = pixel.y - floor(scene_clock * flow_speed_texels) - lag;
				float band = floor(fallen / 15.0);
				float run = fract(fallen / 15.0);
				// Sparse: about a quarter of the column cells carry a crest.
				float broken = step(.74, cell_hash(vec2(column, band)));
				sheet = (run < .12 ? 2.0 : (run < .26 ? 1.0 : 0.0)) * broken;
				sheet_weight = flow_foam * smoothstep(.02, .45, mask.g);
			} else if (mask.r > .02 && water_foam > 0.0) {
				// Turbulent water: short crests in drifting cells that rise, crest
				// and break in steps. Calm water: a rare single glinting texel that
				// travels along a reflection row.
				float churn = smoothstep(.62, .9, mask.r);
				vec2 drift = floor(vec2(scene_clock * 6.0, scene_clock * 3.0));
				vec2 q = pixel - drift;
				vec2 cell = floor(q / vec2(6.0, 2.0));
				float h = cell_hash(cell);
				float cycle = fract(scene_clock * (.45 + .4 * h) + h * 5.3);
				float within = q.x - cell.x * 6.0;
				float dash = step(mod(q.y, 2.0), .5) * step(within, 1.0 + floor(4.0 * cycle)) * step(1.0 - .30 * churn, h);
				float crest = dash * (cycle < .55 ? 1.0 : (cycle < .8 ? 2.0 : 0.0));
				float row = floor(pixel.y / 3.0);
				float lane = cell_hash(vec2(row, 13.0));
				float spark = step(.82, lane) * step(abs(mod(pixel.x - floor(scene_clock * (8.0 + 10.0 * lane)) + lane * 97.0, 41.0 + floor(lane * 30.0))), .5);
				sheet = max(crest, spark * (1.0 - churn));
				sheet_weight = water_foam * smoothstep(.02, .3, mask.r) * max(churn, .55);
			}
		}
		// Ice stays solid. Only faint light changes along existing pale facets;
		// its cracks, silhouette and texture coordinates remain fixed.
		float facet = smoothstep(.38, .78, dot(source.rgb, vec3(.299, .587, .114)));
		glint += sin(sample_uv.x * 81.0 + sample_uv.y * 29.0 - scene_clock * .48) * ice_glint * mask.b * facet * motion_gain;
	}
	// TEXTURE is only visible in fragment(): the detail filter is spelled out
	// for each copy rather than wrapped in a helper.
	vec2 radius = blocks ? world_block : TEXTURE_PIXEL_SIZE * sample_radius;
	bool detailed = detail_strength > 0.0 || contour_strength > 0.0;
	vec2 center_uv = original_uv + (scrolling ? scroll_a : shift);
	vec4 painted = textureGrad(TEXTURE, center_uv, gradient_x, gradient_y);
	if (detailed) {
		painted = background_detail(painted,
			textureGrad(TEXTURE, center_uv - vec2(radius.x, 0.0), gradient_x, gradient_y),
			textureGrad(TEXTURE, center_uv + vec2(radius.x, 0.0), gradient_x, gradient_y),
			textureGrad(TEXTURE, center_uv - vec2(0.0, radius.y), gradient_x, gradient_y),
			textureGrad(TEXTURE, center_uv + vec2(0.0, radius.y), gradient_x, gradient_y));
	}
	if (scrolling) {
		vec2 other_uv = original_uv + scroll_b;
		vec4 other = textureGrad(TEXTURE, other_uv, gradient_x, gradient_y);
		if (detailed) {
			other = background_detail(other,
				textureGrad(TEXTURE, other_uv - vec2(radius.x, 0.0), gradient_x, gradient_y),
				textureGrad(TEXTURE, other_uv + vec2(radius.x, 0.0), gradient_x, gradient_y),
				textureGrad(TEXTURE, other_uv - vec2(0.0, radius.y), gradient_x, gradient_y),
				textureGrad(TEXTURE, other_uv + vec2(0.0, radius.y), gradient_x, gradient_y));
		}
		painted = mix(other, painted, scroll_mix);
	}
	// Water transports painted color, never the plate's transparency. Neighbor
	// texels can differ slightly in alpha even inside an opaque reviewed region.
	painted.a = source.a;
	painted.rgb *= 1.0 + glint;
	if (sheet_weight > 0.0 && sheet != 0.0) {
		// Foam leans to a cool white lifted from the water's own colour; troughs
		// sink a step. The value steps keep the painted palette's texture.
		float value = dot(painted.rgb, vec3(.299, .587, .114));
		vec3 foam = mix(painted.rgb, vec3(.88, .94, .98) * max(.70, value + .32), .75);
		if (sheet < 0.0) painted.rgb *= 1.0 - .20 * sheet_weight;
		else if (sheet < 1.5) painted.rgb = mix(painted.rgb, painted.rgb * 1.22 + .04, sheet_weight);
		else painted.rgb = mix(painted.rgb, foam, sheet_weight);
	}
	float lamp = smoothstep(.48,.76,painted.r)*step(painted.b*1.55+.06,painted.r)*smoothstep(.22,.5,painted.g);
	// Every lit window keeps its own slow life: most burn steadily with a faint
	// independent waver, a few dim and recover, one in a while goes dark for a
	// spell. Cells of 6x5 source texels; nothing changes faster than ~1.5 Hz.
	if (lamp > 0.0) {
		vec2 window = floor(pixel / vec2(6.0, 5.0));
		float wh = cell_hash(window + vec2(31.0, 17.0));
		float waver = sin(scene_clock * (.9 + 1.4 * wh) + wh * 40.0) * .05;
		float dim = wh > .86 ? smoothstep(.55, 1.0, sin(scene_clock * (.31 + .2 * wh) + wh * 23.0)) * .42 : 0.0;
		float dark = wh > .965 ? step(.62, sin(scene_clock * .09 + wh * 61.0)) * .78 : 0.0;
		float shared_wave = sin(scene_clock*2.7)*.025+sin(scene_clock*.83)*.02;
		painted.rgb *= 1.0+lamp*(((shared_wave+waver)*motion_gain-(dim+dark)*motion_gain)+clamp(beat_pulse,0.0,1.0)*.09)*light_gain;
	}
	COLOR = modulation * painted;
}
