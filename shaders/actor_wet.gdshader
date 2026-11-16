shader_type canvas_item;

// Applied only to character/machine art, never to the HUD or identity labels.
// Original texture alpha and material hue are retained; no full-sprite blue wash.
instance uniform float wetness : hint_range(0.0, 1.0) = 0.0;
// Hit read (WeaponEffectArt.strike): rgb is the flash colour, a its strength.
// The sprite's one-texel silhouette rim takes the colour and the interior only
// lifts slightly, so a struck actor keeps its detail instead of a flat fill.
instance uniform vec4 struck = vec4(0.0);
// Team read (ActorWetness): 0 none, 1 crew, 2 hostile. Every textured part gets
// a one-world-texel silhouette edge (dark ink by day; on hostile parts a warm
// rim at night); hostile parts also get a warm crest just inside their upper
// edges and lit sensor pixels, so enemies stay legible against dark or busy
// ground. Measured in world texels, not atlas texels, so a
// downscaled hull and a native infantry part carry the same line.
instance uniform float team = 0.0;
// 0 by day, 1 at night or in a storm (WorldLighting through ActorWetMaterials).
uniform float team_night : hint_range(0.0, 1.0) = 0.0;
uniform float wet_clock = 0.0;
// Exterior light from WorldLighting (ActorWetMaterials.set_world_light): the
// backdrop's key light as a rim on upward and key-side silhouette edges
// (rgb colour, a strength), the key's side (-1 left .. 1 right), the bunker
// interior in world space (x0, y0, x1, y1) where lamps light the actors
// instead, and lightning: strength and the bolt's world x.
uniform vec4 sky_rim = vec4(0.0);
uniform float rim_side = 0.0;
uniform vec4 interior = vec4(0.0);
uniform float flash = 0.0;
uniform float flash_x = 0.0;
// Night grade outside the bunker (rgb multiplier, a strength): figures under
// a night sky sink toward its light; their sky rim grows by the same share,
// so they read by edge light instead of by a flat full-value body.
uniform vec4 exterior_grade = vec4(1.0, 1.0, 1.0, 0.0);
uniform float metal : hint_range(0.0, 1.0) = 0.0;
uniform float art_top = -10000.0;
uniform bool opaque_only = false;
// Opt-in for the generated vehicle hulls; use texture alpha so death fades and
// vertex opacity remain continuous rather than clipping with the source edge.
uniform float sprite_alpha_cutoff : hint_range(0.0, 1.0) = 0.0;
varying vec2 art_position;
// Exhaust, damage smoke and steam drawn on an actor part use the shared
// texel-grid effect shapes (PixelEffectArt.grid_*), stepping in world texels
// however the part is turned or scaled.
#include "res://shaders/pixel_effect_grid.gdshaderinc"

void vertex() {
	art_position = VERTEX;
	grid_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// Derivatives first: they are undefined after a discard or inside a branch.
	vec2 uv_dx = dFdx(UV);
	vec2 uv_dy = dFdy(UV);
	vec2 world_dx = dFdx(grid_world);
	vec2 world_dy = dFdy(grid_world);
	if (UV.y > 30.0) {
		vec4 tint = COLOR;
		if (!grid_shape(UV, tint)) discard;
		COLOR = tint;
	} else {
	vec4 original = COLOR;
	if (sprite_alpha_cutoff > 0.0 && texture(TEXTURE, UV).a < sprite_alpha_cutoff) {
		discard;
	}
	// Dry actors retain their exact input pixels and skip all material work.
	if (wetness > 0.001 && art_position.y >= art_top && original.a > 0.01 && (!opaque_only || original.a > 0.85)) {
		float luminous = max(step(original.g * 1.6 + 0.08, original.r), step(0.90, min(original.r, min(original.g, original.b))));
		float amount = wetness * (1.0 - luminous * 0.9);
		vec3 damp = original.rgb * mix(vec3(0.77, 0.82, 0.81), vec3(0.80, 0.86, 0.88), metal);
		float neutral = 1.0 - smoothstep(0.12, 0.30, max(original.r, max(original.g, original.b)) - min(original.r, min(original.g, original.b)));
		vec2 pixel = floor(art_position);
		// Stable arithmetic hash: no per-pixel sine just to pick wet flecks.
		vec2 hash = fract(pixel * vec2(0.1031, 0.11369));
		hash += dot(hash, hash.yx + 19.19);
		float grain = fract((hash.x + hash.y) * hash.x);
		float fleck = step(0.91, grain);
		float sheen = (0.5 + 0.5 * sin(wet_clock * 1.7 + pixel.y * 0.10 + pixel.x * 0.04));
		damp += vec3(0.12, 0.16, 0.17) * neutral * fleck * sheen * (0.35 + metal * 0.65) * smoothstep(0.12, 0.50, original.g);
		// Small downward-running highlights belong to saturated metal only.
		// They are anchored in local art pixels and never outline the sprite.
		if (metal > 0.01 && wetness > 0.55) {
			float rivulet = step(0.84, fract(pixel.x * 0.6180339)) * (1.0 - smoothstep(0.0, 0.20, fract(pixel.y * 0.065 - wet_clock * 0.32 + grain * 0.08)));
			damp += vec3(0.035, 0.05, 0.055) * rivulet * metal * neutral * smoothstep(0.55, 1.0, wetness);
		}
		COLOR = vec4(mix(original.rgb, damp, amount), original.a);
	}
	if (team > 0.5 && original.a > 0.01) {
		float hostile = step(1.5, team);
		// UV step of one world texel along world x and world y. Untextured
		// primitives have no UV gradient and keep their own drawn ink.
		float det = world_dx.x * world_dy.y - world_dx.y * world_dy.x;
		if (abs(det) > 1e-8 && dot(uv_dx, uv_dx) + dot(uv_dy, uv_dy) > 0.0) {
			mat2 per_world = mat2(uv_dx, uv_dy) * inverse(mat2(world_dx, world_dy));
			vec2 sx = per_world * vec2(1.0, 0.0);
			vec2 sy = per_world * vec2(0.0, 1.0);
			float solid = step(0.5, texture(TEXTURE, UV).a);
			float left = texture(TEXTURE, UV - sx).a;
			float right = texture(TEXTURE, UV + sx).a;
			float open_side = min(left, right);
			float above = texture(TEXTURE, UV - sy).a;
			float below = texture(TEXTURE, UV + sy).a;
			float open_all = min(open_side, min(above, below));
			float edge = solid * (1.0 - step(0.5, open_all));
			// Hostile parts draw their silhouette two world texels deep where the
			// part is thick enough (the texel three in from that side is solid):
			// a one-texel line vanished against snow, busy rail yards and bright
			// sky at the co-op camera. Rods, barrels and limbs under six texels
			// keep the single line, so thin parts do not turn solid black.
			float edge2 = 0.0;
			if (hostile > 0.5) {
				float l2 = 1.0 - step(0.5, texture(TEXTURE, UV - 2.0 * sx).a);
				float r2 = 1.0 - step(0.5, texture(TEXTURE, UV + 2.0 * sx).a);
				float a2 = 1.0 - step(0.5, texture(TEXTURE, UV - 2.0 * sy).a);
				float b2 = 1.0 - step(0.5, texture(TEXTURE, UV + 2.0 * sy).a);
				float l3 = step(0.5, texture(TEXTURE, UV - 3.0 * sx).a);
				float r3 = step(0.5, texture(TEXTURE, UV + 3.0 * sx).a);
				float a3 = step(0.5, texture(TEXTURE, UV - 3.0 * sy).a);
				float b3 = step(0.5, texture(TEXTURE, UV + 3.0 * sy).a);
				float deep = max(max(l2 * r3, r2 * l3), max(a2 * b3, b2 * a3));
				edge2 = solid * (1.0 - edge) * deep;
			}
			// The texel under a top edge: the rim a light behind the actor draws.
			// Rods, barrels and straps (under six texels) keep their plain edge.
			float crest = solid * (1.0 - edge) * (1.0 - step(0.5, texture(TEXTURE, UV - 2.0 * sy).a)) * step(0.5, texture(TEXTURE, UV + 4.0 * sy).a);
			bool inside = grid_world.x > interior.x && grid_world.x < interior.z && grid_world.y > interior.y && grid_world.y < interior.w;
			if (!inside && exterior_grade.a > 0.004) {
				// Under a night sky the body sinks toward the scene's light before
				// any edge, crest or rim is drawn, so those stay at full strength.
				// Lamps and sensors keep burning; hostile hulls sink less, their
				// read already rests on the warm rim.
				float lit = step(0.80, max(COLOR.r, max(COLOR.g, COLOR.b))) * step(0.5, max(COLOR.r, max(COLOR.g, COLOR.b)) - min(COLOR.r, min(COLOR.g, COLOR.b)));
				// The crew sink in value only and keep their own colours: the
				// night's hue lean turned every outfit the same blue-grey, and
				// the figures merged with the fence and the night behind them.
				vec3 grade = hostile > 0.5 ? exterior_grade.rgb : vec3(min(1.0, dot(exterior_grade.rgb, vec3(0.299, 0.587, 0.114)) * 1.18));
				COLOR.rgb *= mix(vec3(1.0), grade, exterior_grade.a * (1.0 - lit) * mix(1.0, 0.5, hostile));
				// Their colours even gain a little against the grey-blue night.
				if (hostile < 0.5) COLOR.rgb = clamp(mix(vec3(dot(COLOR.rgb, vec3(0.299, 0.587, 0.114))), COLOR.rgb, 1.0 + 0.30 * exterior_grade.a), 0.0, 1.0);
			}
			// Polarity follows the world: against a bright day backdrop the
			// silhouette edge is dark ink; against a dark night backdrop a dark
			// edge would sink into it, so hostile edges catch a warm rim instead.
			float value = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
			vec3 ink = COLOR.rgb * 0.24 + vec3(0.020, 0.018, 0.022);
			COLOR.rgb = mix(COLOR.rgb, ink, edge * mix(0.62, 0.96, hostile) * (1.0 - team_night));
			// The second texel: well toward ink by day; at night it sinks a
			// little, so the warm rim on the outer texel stands off the hull.
			COLOR.rgb = mix(COLOR.rgb, COLOR.rgb * 0.40, edge2 * mix(0.66, 0.42, team_night));
			vec3 ember = vec3(1.0, 0.66, 0.40) * (0.66 + 0.50 * value);
			// A rim catches light on top and at the sides, hardly underneath.
			float facing = mix(1.0, 0.30, (1.0 - step(0.5, below)) * step(0.5, above) * step(0.5, open_side));
			facing = mix(facing, 1.35, 1.0 - step(0.5, above));
			COLOR.rgb = mix(COLOR.rgb, ember, edge * hostile * team_night * 0.60 * facing);
			COLOR.rgb = mix(COLOR.rgb, ember, crest * hostile * mix(0.40, 0.62, team_night));
			// Under the open sky the key light catches the top and the key-side
			// edge; a lightning bolt lights the edges that face it.
			if (!inside && (sky_rim.a > 0.004 || flash > 0.004)) {
				float top_open = 1.0 - step(0.5, above);
				float key_open = 1.0 - step(0.5, rim_side < 0.0 ? left : right);
				float sky = solid * max(top_open, key_open * abs(rim_side) * 0.8);
				COLOR.rgb += sky_rim.rgb * sky_rim.a * sky * (1.0 + 1.6 * exterior_grade.a);
				if (flash > 0.004) {
					float facing_bolt = 1.0 - step(0.5, flash_x < grid_world.x ? left : right);
					float bolt = solid * max(facing_bolt, top_open * 0.6);
					// The whole figure takes a share of the flash (WorldLighting's
					// exterior wash lifts what stands behind it alike), the edges
					// that face the bolt the rest.
					float near_bolt = 1.0 - smoothstep(0.0, 1100.0, abs(grid_world.x - flash_x));
					COLOR.rgb += vec3(0.80, 0.88, 1.0) * flash * 0.22 * mix(0.4, 1.0, near_bolt) * solid;
					COLOR.rgb = mix(COLOR.rgb, vec3(0.86, 0.92, 1.0), bolt * flash * 0.85);
				}
			}
		}
		// Sensor and visor lamps (bright, strongly red pixels; not rust, wood or
		// webbing) burn at full value.
		vec3 c = COLOR.rgb;
		float lamp = hostile * step(0.78, c.r) * step(c.g, c.r * 0.42) * step(c.b, c.r * 0.40);
		COLOR.rgb = mix(c, vec3(1.0, 0.46 + 0.20 * c.g, 0.26 + 0.15 * c.b), lamp * mix(0.45, 0.85, team_night));
	}
	if (struck.a > 0.004 && original.a > 0.01) {
		vec2 px = TEXTURE_PIXEL_SIZE;
		float inside = min(min(texture(TEXTURE, UV + vec2(px.x, 0.0)).a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a), min(texture(TEXTURE, UV + vec2(0.0, px.y)).a, texture(TEXTURE, UV - vec2(0.0, px.y)).a));
		float rim = step(0.5, texture(TEXTURE, UV).a) * (1.0 - step(0.5, inside));
		vec3 lifted = mix(COLOR.rgb, struck.rgb, struck.a * .16);
		COLOR.rgb = mix(lifted, struck.rgb, rim * struck.a);
	}
	}
}
