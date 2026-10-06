shader_type canvas_item;
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
uniform float light_gain = 1.0;
varying vec4 modulation;
void vertex() { modulation = COLOR; }
vec3 surface_at(vec2 uv) {
	vec2 local = (uv - surface_bounds.xy) / surface_bounds.zw;
	if (any(lessThan(local, vec2(0.0))) || any(greaterThanEqual(local, vec2(1.0)))) { return vec3(0.0); }
	return texture(surface_mask, local).rgb;
}
void fragment() {
	// Keep the original camera footprint. Derivatives of stepped, animated UVs
	// would select different mip levels even on adjacent unmasked bank pixels.
	vec2 original_uv = background_uv(UV, TEXTURE_PIXEL_SIZE);
	vec2 gradient_x = dFdx(original_uv);
	vec2 gradient_y = dFdy(original_uv);
	vec4 source = textureGrad(TEXTURE, original_uv, gradient_x, gradient_y);
	vec3 mask = vec3(0.0);
	vec2 shift = vec2(0.0);
	float glint = 0.0;
	if (surface_enabled && motion_gain > 0.0) {
		// Generated opaque plate texels often carry alpha 251–254. Gate their
		// silhouettes, without weakening an already feathered liquid mask twice.
		mask = surface_at(UV) * step(.98, source.a);
		if (mask.r > 0.0 || mask.g > 0.0) {
			// Integer source-pixel offsets retain painted clusters and their palette.
			// Two interacting long swells move reflection rows rather than the lake.
			vec2 pixel = floor(UV / TEXTURE_PIXEL_SIZE);
			float swell = sin(pixel.y * .10 - scene_clock * 1.25 + sin(pixel.x * .011 + scene_clock * .21));
			float ripple = sin(pixel.y * .28 + pixel.x * .018 - scene_clock * 2.2);
			vec2 travel = vec2((swell * .72 + ripple * .28) * water_travel_texels, 0.0) * mask.r;
			// Falling water scrolls through the painted falling-water column. The
			// bounded ping-pong travel avoids importing concrete from its ends.
			float falling = sin(pixel.y * .22 - scene_clock * 3.7 + pixel.x * .025);
			travel += vec2(0.0, falling * flow_travel_texels) * mask.g;
			shift = round(travel * motion_gain) * TEXTURE_PIXEL_SIZE;
			vec3 neighbor = surface_at(UV + shift);
			// Both source and destination must belong to the same surface: shores,
			// reeds, piers, machinery and alpha silhouettes never slide into water.
			float safe = max(min(mask.r, neighbor.r), min(mask.g, neighbor.g));
			shift *= step(.02, safe);
			glint = (swell * .65 + ripple * .35) * water_glint * mask.r * motion_gain;
			glint += smoothstep(.55, .95, falling) * flow_glint * mask.g * motion_gain;
		}
		// Ice stays solid. Only faint light changes along existing pale facets;
		// its cracks, silhouette and texture coordinates remain fixed.
		float facet = smoothstep(.38, .78, dot(source.rgb, vec3(.299, .587, .114)));
		glint += sin(UV.x * 81.0 + UV.y * 29.0 - scene_clock * .48) * ice_glint * mask.b * facet * motion_gain;
	}
	vec2 center_uv = original_uv + shift;
	vec4 painted = textureGrad(TEXTURE, center_uv, gradient_x, gradient_y);
	if (detail_strength > 0.0 || contour_strength > 0.0) {
		vec2 radius = TEXTURE_PIXEL_SIZE * sample_radius;
		painted = background_detail(painted,
			textureGrad(TEXTURE, center_uv - vec2(radius.x, 0.0), gradient_x, gradient_y),
			textureGrad(TEXTURE, center_uv + vec2(radius.x, 0.0), gradient_x, gradient_y),
			textureGrad(TEXTURE, center_uv - vec2(0.0, radius.y), gradient_x, gradient_y),
			textureGrad(TEXTURE, center_uv + vec2(0.0, radius.y), gradient_x, gradient_y));
	}
	// Water transports painted color, never the plate's transparency. Neighbor
	// texels can differ slightly in alpha even inside an opaque reviewed region.
	painted.a = source.a;
	painted.rgb *= 1.0 + glint;
	float lamp = smoothstep(.48,.76,painted.r)*step(painted.b*1.55+.06,painted.r)*smoothstep(.22,.5,painted.g);
	painted.rgb *= 1.0+lamp*((sin(scene_clock*2.7)*.055+sin(scene_clock*.83)*.04)*motion_gain+clamp(beat_pulse,0.0,1.0)*.09)*light_gain;
	COLOR = modulation * painted;
}
