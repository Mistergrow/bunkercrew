extends Node2D
## Weather settled on the exterior's upward faces: snow caps, ash dust, a wet
## sheen or blown sand on the bunker roof and on the crates stored outside,
## and the backdrop's key light along those edges in every world. Built from
## the bunker's own layout and the supplies every peer already has; rebuilt
## only when that layout changes. Presentation only: no collision, no state.
## Shaded like the props beside it (ambient and gate lights apply).
const STRATA := preload("res://scripts/terrain_strata.gd")
## Above crates (z 0), roof guns (6) and the perimeter (5); below the room
## grade (9) and every actor (14+).
const Z := 8
## Most rects one layout may produce (roof plus a full crate row).
const MAX_RECTS := 1600
## Surface kinds from TerrainStrata.SURFACES.
const SNOW := 1
const WET := 3
const ASH := 4
const SAND := 5
var bunker: Node2D
var game: Node
var kind := 0
var cap := Color.WHITE
## Sky key: rgb colour, a strength (WorldLighting.sky_rim_for).
var rim := Color(1, 1, 1, 0)
var rects: Array[Rect2] = []
var colors := PackedColorArray()
var builds := 0
var _signature := 0

func _ready() -> void:
	name = "WeatherAccumulation"
	z_as_relative = false
	z_index = Z
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func configure(data: Dictionary, sky_rim: Color) -> void:
	kind = STRATA.surface_for(data)
	var id := str(data.get("id", "sector07"))
	var spec: Array = STRATA.PROFILES.get(id, STRATA.PROFILES.sector07)
	cap = STRATA.cap_tint_for(data, kind, spec[2])
	rim = sky_rim
	_signature = 0

## Rebuilds the cap geometry when the roof, its hatches or the crates changed.
## Called from WorldLighting's staggered refresh, never from _draw.
func refresh() -> void:
	if not is_instance_valid(bunker) or not bool(bunker.get("_bootstrapped")): return
	var signature := hash([bunker.room_left, bunker.room_right, kind, rim, _spans_signature()])
	if signature == _signature: return
	_signature = signature
	_build()
	queue_redraw()

func _spans_signature() -> int:
	var total := 0
	for supply: Node in get_tree().get_nodes_in_group("supplies"):
		if _outdoor_supply(supply): total = total * 31 + hash((supply as Node2D).global_position.round())
	for passage: Variant in bunker.get("passages"):
		if is_instance_valid(passage): total = total * 17 + hash((passage as Node).call("aperture"))
	return total

func _outdoor_supply(supply: Node) -> bool:
	if not supply is Node2D or not supply.is_visible_in_tree() or not is_instance_valid(game) or not game.is_ancestor_of(supply): return false
	var weather: Node = game.get("weather")
	var lid := (supply as Node2D).global_position + Vector2(0, -42)
	return is_instance_valid(weather) and weather.has_method("is_outdoors") and bool(weather.is_outdoors(lid))

## Upward faces as [from x, to x, top y]: the roof slab between its hatches
## and the lid of every crate standing outside.
func top_spans() -> Array[Vector3]:
	var spans: Array[Vector3] = []
	var roof := float(bunker.get("ROOF_Y"))
	var cuts: Array[Vector2] = []
	for passage: Variant in bunker.get("passages"):
		if not is_instance_valid(passage): continue
		var hole: Rect2 = (passage as Node).call("aperture")
		if absf(hole.position.y - roof) < 1.0: cuts.append(Vector2(hole.position.x, hole.end.x))
	cuts.sort()
	var cursor := float(bunker.room_left)
	for cut in cuts:
		if cut.x > cursor + 2.0: spans.append(Vector3(cursor, cut.x, roof))
		cursor = maxf(cursor, cut.y)
	if float(bunker.room_right) > cursor + 2.0: spans.append(Vector3(cursor, float(bunker.room_right), roof))
	for supply: Node in get_tree().get_nodes_in_group("supplies"):
		if not _outdoor_supply(supply): continue
		var at := (supply as Node2D).global_position.round()
		# The lid's first opaque row lies two texels under the art's bounds.
		spans.append(Vector3(at.x - 27.0, at.x + 27.0, at.y - 35.0))
	return spans

static func _hash01(x: int, salt: int) -> float:
	return float(posmod(hash(Vector2i(x, salt)), 10007)) / 10007.0

## Smooth value noise along x: whole-texel steps, never per-texel jitter.
static func _noise(x: float, salt: int) -> float:
	var cell := floori(x)
	var t := x - cell
	t = t * t * (3.0 - 2.0 * t)
	return lerpf(_hash01(cell, salt), _hash01(cell + 1, salt), t)

func _rect(area: Rect2, color: Color) -> void:
	if rects.size() >= MAX_RECTS or area.size.x <= 0.0 or area.size.y <= 0.0: return
	rects.append(area)
	colors.append(color)

func _build() -> void:
	rects.clear()
	colors.clear()
	builds += 1
	var salt := 0
	for span in top_spans():
		salt += 1
		match kind:
			SNOW: _snow(span, salt)
			ASH: _dust(span, salt, 3, true)
			SAND: _dust(span, salt, 2, false)
			WET: _sheen(span, salt)
		_rim(span)

## The sky key along a lit upper edge (and a wet surface's sky glint).
func _rim(span: Vector3) -> void:
	if rim.a <= .01 or kind == SNOW: return
	_rect(Rect2(span.x, span.z, span.y - span.x, 1.0), Color(rim.r, rim.g, rim.b, rim.a * .85))

## Snow: a drift of one to five texels with a lit crust, a body and a cool
## underside, rounded at both ends and hanging one texel past the edge.
func _snow(span: Vector3, salt: int) -> void:
	var from := int(span.x) - 1
	var to := int(span.y) + 1
	var top := span.z
	var crust := Color(minf(1.0, cap.r * 1.05 + rim.r * rim.a * .25), minf(1.0, cap.g * 1.05 + rim.g * rim.a * .25), minf(1.0, cap.b * 1.05 + rim.b * rim.a * .25))
	var body := Color(cap.r * .93, cap.g * .94, cap.b * .96)
	var shade := Color(cap.r * .66, cap.g * .74, cap.b * .88)
	var x := from
	while x < to:
		var height := _snow_height(x, from, to, salt)
		var run := 1
		while x + run < to and run < 24 and _snow_height(x + run, from, to, salt) == height: run += 1
		if height > 0:
			_rect(Rect2(x, top - height, run, 1), crust)
			if height > 2: _rect(Rect2(x, top - height + 1, run, height - 2), body)
			if height > 1: _rect(Rect2(x, top - 1, run, 1), shade)
		x += run
	# A thin cool lip where the snow overhangs the edge on both sides.
	_rect(Rect2(from, top, 1, 1), shade)
	_rect(Rect2(to - 1, top, 1, 1), shade)

func _snow_height(x: int, from: int, to: int, salt: int) -> int:
	var drift := _noise(x / 11.0, salt) * .6 + _noise(x / 37.0, salt + 101) * .4
	var height := 3 + int(drift * 4.4)
	# Rounded ends: one texel higher per texel in from the edge.
	return mini(height, 1 + mini(x - from, to - 1 - x))

## Ash or sand: a thin uneven film with dark specks (cinders) or ripples.
func _dust(span: Vector3, salt: int, most: int, cinders: bool) -> void:
	var from := int(span.x)
	var to := int(span.y)
	var top := span.z
	var light := Color(minf(1.0, cap.r * 1.16), minf(1.0, cap.g * 1.16), minf(1.0, cap.b * 1.16))
	var body := Color(cap.r * .86, cap.g * .86, cap.b * .86)
	var x := from
	while x < to:
		var height := mini(most, int(_noise(x / 9.0, salt) * (most + 1.4)))
		var run := 1
		while x + run < to and run < 16 and mini(most, int(_noise((x + run) / 9.0, salt) * (most + 1.4))) == height: run += 1
		if height > 0:
			_rect(Rect2(x, top - height, run, 1), light)
			if height > 1: _rect(Rect2(x, top - height + 1, run, height - 1), body)
		x += run
	for index in int((to - from) / 6.0):
		var at := from + int(_hash01(index, salt + 7) * maxf(1.0, to - from - 1))
		if _hash01(index, salt + 11) < .55:
			_rect(Rect2(at, top - 1, 1, 1), Color(cap.r * .40, cap.g * .38, cap.b * .36) if cinders else Color(cap.r * .74, cap.g * .70, cap.b * .62))

## Wet: standing water along the flat top catching the sky in broken glints.
func _sheen(span: Vector3, salt: int) -> void:
	var from := int(span.x)
	var to := int(span.y)
	var x := from + int(_hash01(0, salt) * 6.0)
	var index := 0
	while x < to:
		var length := 3 + int(_hash01(index, salt + 3) * 14.0)
		var glint := Color(lerpf(.62, rim.r, .5), lerpf(.70, rim.g, .5), lerpf(.78, rim.b, .5), .34 + .30 * _hash01(index, salt + 5))
		_rect(Rect2(x, span.z, mini(length, to - x), 1), glint)
		x += length + 2 + int(_hash01(index, salt + 9) * 9.0)
		index += 1

func _draw() -> void:
	for index in rects.size():
		draw_rect(rects[index], colors[index])

func diagnostics() -> Dictionary:
	return {"kind":kind, "rects":rects.size(), "builds":builds}
