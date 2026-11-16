extends RefCounted
## Whole screen pixels for the pixel-art world. Actor art (workers, infantry,
## terrain, effects) is authored at one texel per world unit, while the UI keeps
## the project's canvas_items stretch (1440x900 base, so 1.2 at 1080p). The
## world camera therefore settles on zooms where one world unit covers a whole
## number of physical pixels, and on positions where texel edges meet pixel
## edges. Presentation only: nothing here touches simulation or replicated state.
##
## Scales are physical screen pixels per world unit. Below one pixel per unit
## (very wide co-op or overview framings) no clean zoom exists; those framings
## keep their exact fit.

## Smallest world area a rounded-up step may leave on screen: the longest enemy
## weapon reach (420) on both sides of a worker, and a floor above and below.
const MIN_FRAME := Vector2(840.0, 480.0)
const EPSILON := 0.0001

## Physical pixels per logical canvas unit, per axis. The expand aspect rounds
## the logical size to whole units, so the axes can differ slightly (1366x768).
static func stretch(viewport: Viewport) -> Vector2:
	if viewport == null: return Vector2.ONE
	var final := viewport.get_final_transform()
	var result := Vector2(absf(final.x.x), absf(final.y.y))
	if not result.is_finite() or result.x <= EPSILON or result.y <= EPSILON: return Vector2.ONE
	return result

## Physical size of the viewport in pixels.
static func window_pixels(viewport: Viewport) -> Vector2:
	if viewport == null: return Vector2(1440.0, 900.0)
	return viewport.get_visible_rect().size * stretch(viewport)

## Settled scale for a framing that would like `preferred` and must not exceed
## `limit` (for example: every couch player inside the view). Rounds to the
## nearest whole scale in ratio terms, taking the larger, more readable step only
## while the world area of MIN_FRAME still fits on `window` (keep_frame: the
## default framing; a player who zoomed in on purpose may go past it).
static func settle_scale(preferred: float, limit: float, window: Vector2, keep_frame: bool = true) -> float:
	if not is_finite(preferred) or preferred <= 0.0: preferred = 1.0
	var cap := limit if is_finite(limit) and limit > 0.0 else INF
	var result := nearest_scale(preferred)
	if keep_frame and result > preferred + EPSILON:
		# Rounded up: only while the designed world area still fits the window.
		var room := window.x / result >= MIN_FRAME.x - EPSILON and window.y / result >= MIN_FRAME.y - EPSILON
		if not room: result = floorf(preferred + EPSILON) if preferred + EPSILON >= 1.0 else preferred
	if result > cap + EPSILON:
		result = floorf(cap + EPSILON) if cap + EPSILON >= 1.0 else cap
	return result

## Nearest whole scale in ratio terms (authored close-ups). From sqrt(1/2) up
## to one the nearest step is one pixel per texel; farther out no whole step
## exists and the value stays as it is.
static func nearest_scale(preferred: float) -> float:
	if not is_finite(preferred) or preferred <= 0.0: return 1.0
	if preferred + EPSILON < 1.0: return 1.0 if preferred >= sqrt(.5) else preferred
	var low := floorf(preferred + EPSILON)
	return low + 1.0 if preferred > low + EPSILON and preferred >= sqrt(low * (low + 1.0)) else low

## Largest whole scale that keeps the framing (a fit); the exact fit below one.
static func fit_scale(fit: float) -> float:
	if not is_finite(fit) or fit <= 0.0: return 1.0
	return floorf(fit + EPSILON) if fit + EPSILON >= 1.0 else fit

static func is_whole(scale: float) -> bool:
	return scale >= 1.0 - EPSILON and absf(scale - roundf(scale)) <= EPSILON * 10.0

## Camera2D zoom that shows `scale` physical pixels per world unit on both axes.
static func zoom_for(scale: float, viewport: Viewport) -> Vector2:
	var factor := stretch(viewport)
	return Vector2(scale / factor.x, scale / factor.y)

## Physical pixels per world unit of a Camera2D zoom.
static func scale_of(zoom: Vector2, viewport: Viewport) -> Vector2:
	return zoom * stretch(viewport)

## Camera centre whose canvas origin lands on whole physical pixels, so world
## texel edges meet pixel edges and scrolling moves in whole pixels. Below one
## pixel per texel nearest sampling drops texels anyway; the centre stays exact.
static func snap_center(center: Vector2, zoom: Vector2, viewport: Viewport) -> Vector2:
	if not center.is_finite(): return center
	var scale := scale_of(zoom, viewport)
	if scale.x < 1.0 - EPSILON or scale.y < 1.0 - EPSILON: return center
	var half := window_pixels(viewport) * 0.5
	return Vector2((roundf(center.x * scale.x - half.x) + half.x) / scale.x, (roundf(center.y * scale.y - half.y) + half.y) / scale.y)

## A logical-pixel offset (shake, kick) as whole physical pixels in world units.
static func snap_offset(screen_logical: Vector2, zoom: Vector2, viewport: Viewport) -> Vector2:
	var factor := stretch(viewport)
	var scale := zoom * factor
	if scale.x <= EPSILON or scale.y <= EPSILON: return Vector2.ZERO
	if scale.x < 1.0 - EPSILON or scale.y < 1.0 - EPSILON: return screen_logical.round() / zoom
	return Vector2(roundf(screen_logical.x * factor.x) / scale.x, roundf(screen_logical.y * factor.y) / scale.y)
