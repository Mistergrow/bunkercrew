extends RefCounted
## Source-image focal points, independent of gameplay camera and terrain.
## zoom, panorama bottom in the 900px menu canvas, focal U, focal screen X.
const EDGE_FADE := .015
const SHOTS := {
	"ash_foundry": [1.52, 945.0, .720, 1080.0],
	"abandoned_harbor": [1.48, 930.0, .765, 1070.0],
	"basalt_quarry": [1.65, 940.0, .650, 1110.0],
	"overgrown_steelworks": [1.53, 940.0, .825, 1045.0],
	"frozen_rail_yard": [1.62, 940.0, .700, 1100.0],
	"iron_canyon": [1.58, 930.0, .730, 1130.0],
	"flooded_power_station": [1.55, 940.0, .690, 1100.0],
	"mountain_pass": [1.50, 945.0, .715, 1100.0],
	"storm_dam": [2.10, 995.0, .680, 1100.0],
	"sulfur_refinery": [1.48, 940.0, .820, 1120.0],
	"radar_highlands": [1.50, 940.0, .810, 1110.0],
	"buried_megafactory": [1.58, 950.0, .800, 1110.0],
	"sector07": [2.45, 1030.0, .720, 1110.0],
}

static func frame(environment_id: String, panorama: Rect2, bounds: Rect2) -> Transform2D:
	if bool(ScenarioCatalog.environment(environment_id).get("continuous_background",false)):
		var scale := maxf(bounds.size.x / panorama.size.x, bounds.size.y / panorama.size.y) * 1.015
		var background_origin := bounds.size * .5 - panorama.get_center() * scale
		return Transform2D(Vector2(scale,0),Vector2(0,scale),background_origin)
	var shot: Array = SHOTS.get(environment_id, SHOTS.ash_foundry)
	var zoom := maxf(float(shot[0]), bounds.size.x * 1.16 / panorama.size.x)
	var width := panorama.size.x * zoom
	var focus_x := float(shot[3]) + maxf(0.0, bounds.end.x - 1440.0) * .35
	# Keep the painted edge blend outside the viewport, including ultrawide.
	# This prevents thin duplicate scenery at either side of the original art.
	var margin := width * (EDGE_FADE + .005)
	var image_left := clampf(focus_x - float(shot[2]) * width,
		bounds.end.x + margin - width, bounds.position.x - margin)
	var image_bottom := maxf(float(shot[1]), bounds.end.y + 30.0)
	var origin := Vector2(image_left, image_bottom - panorama.size.y * zoom) - panorama.position * zoom
	return Transform2D(Vector2(zoom, 0), Vector2(0, zoom), origin - bounds.position)
