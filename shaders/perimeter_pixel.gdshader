shader_type canvas_item;
// The source atlas contains very faint generated fringe pixels. Threshold only
// texture coverage: vertex tint/health bars/contact shadows retain their alpha.
varying vec4 source_tint;
varying vec2 world;
// Exterior light from WorldLighting, all off by default (other users of this
// shader set none of them): the backdrop's key light as a rim on upward and
// key-side edges (rgb colour, a strength), the key's side (-1 left .. 1
// right), lightning strength and the bolt's world x.
uniform vec4 sky_rim = vec4(0.0);
uniform float rim_side = 0.0;
uniform float flash = 0.0;
uniform float flash_x = 0.0;
// Weather settled on upward faces (TerrainStrata surface kinds): 0 none,
// 1 snow, 3 wet sheen, 4 ash, 5 sand; with the world's cover colour.
uniform int settle_kind = 0;
uniform vec4 settle_tint : source_color = vec4(1.0);

void vertex() {
	source_tint = COLOR;
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// Derivatives first: they are undefined after a discard or inside a branch.
	vec2 uv_dx = dFdx(UV);
	vec2 uv_dy = dFdy(UV);
	vec2 world_dx = dFdx(world);
	vec2 world_dy = dFdy(world);
	vec4 ink = texture(TEXTURE, UV);
	if (ink.a < 0.5) { discard; }
	vec3 color = ink.rgb;
	float det = world_dx.x * world_dy.y - world_dx.y * world_dy.x;
	if ((sky_rim.a > 0.004 || flash > 0.004 || settle_kind > 0) && abs(det) > 1e-8 && dot(uv_dx, uv_dx) + dot(uv_dy, uv_dy) > 0.0) {
		// One world texel along world x and y, in UV: the same line width on
		// every module however the atlas is scaled.
		mat2 per_world = mat2(uv_dx, uv_dy) * inverse(mat2(world_dx, world_dy));
		vec2 sx = per_world * vec2(1.0, 0.0);
		vec2 sy = per_world * vec2(0.0, 1.0);
		float above = step(0.5, texture(TEXTURE, UV - sy).a);
		float above_two = step(0.5, texture(TEXTURE, UV - 2.0 * sy).a);
		// A face needs body under it: wires and mesh diagonals stay as drawn.
		float body = step(0.5, texture(TEXTURE, UV + 2.0 * sy).a);
		float left = step(0.5, texture(TEXTURE, UV - sx).a);
		float right = step(0.5, texture(TEXTURE, UV + sx).a);
		float top = (1.0 - above) * body;
		float second = above * (1.0 - above_two) * body;
		float value = dot(color, vec3(0.299, 0.587, 0.114));
		vec2 cell = floor(world);
		float grain = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		if (settle_kind == 1) {
			// Snow: a lit crust on the top texel, a cooler second row in places.
			color = mix(color, settle_tint.rgb * 1.04, top);
			color = mix(color, settle_tint.rgb * vec3(0.80, 0.86, 0.95), second * step(0.35, grain));
		} else if (settle_kind == 3) {
			// Wet: the top texel mirrors the sky, broken where it runs off.
			color = mix(color, mix(color * 1.5, sky_rim.rgb * 0.9, 0.5), top * step(0.30, grain) * 0.75);
		} else if (settle_kind == 4) {
			// Ash: grey dust on the top texel, dark cinder grains.
			color = mix(color, grain > 0.86 ? settle_tint.rgb * 0.42 : settle_tint.rgb, top * 0.85);
		} else if (settle_kind == 5) {
			color = mix(color, settle_tint.rgb * mix(0.88, 1.0, grain), top * 0.7);
		}
		if (settle_kind != 1) {
			float key_open = 1.0 - (rim_side < 0.0 ? left : right);
			float sky = max(top, key_open * abs(rim_side) * 0.7 * step(0.5, above));
			color += sky_rim.rgb * sky_rim.a * sky * (0.6 + value);
		}
		if (flash > 0.004) {
			// Thick parts catch it on the side that faces the bolt; single-texel
			// wires and mesh stay dark against the lit sky.
			float facing = (1.0 - (flash_x < world.x ? left : right)) * (flash_x < world.x ? right : left);
			// Every part takes a share of the flash, as the ground and the
			// bunker shell behind it do; thick faces toward the bolt the rest.
			float near_bolt = 1.0 - smoothstep(0.0, 1100.0, abs(world.x - flash_x));
			color += vec3(0.80, 0.88, 1.0) * flash * 0.20 * mix(0.4, 1.0, near_bolt);
			color = mix(color, vec3(0.86, 0.92, 1.0), max(facing, top * 0.7) * flash * 0.8);
		}
	}
	COLOR = vec4(color, 1.0) * source_tint;
}
