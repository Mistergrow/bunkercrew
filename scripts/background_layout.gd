extends RefCounted
## One source image covers the visible above-ground world without edge patches.
const MIN_WIDTH := 1800.0
const CLOSE_WIDTH := 1600.0
const HORIZON := 430.0
const MARGIN := 64.0

static func frame(view: Rect2, aspect: float, zoom: float = 1.0) -> Rect2:
	var bottom := HORIZON + MARGIN
	# Keep the 1672px source close to its native density; coverage can enlarge
	# it for wide views. Reveal more source pixels as the camera moves in.
	var near_zoom := maxf(1.0,zoom)
	var detail_width := lerpf(MIN_WIDTH,CLOSE_WIDTH,clampf((near_zoom-1.0)/1.5,0,1))/near_zoom
	var width := maxf(detail_width, maxf(view.size.x + MARGIN * 2.0, (bottom - view.position.y + MARGIN) * aspect))
	var height := width / aspect
	var left := clampf(720.0 - width * .5, view.end.x + MARGIN - width, view.position.x - MARGIN)
	return Rect2(left, bottom - height, width, height)
