extends RefCounted
## Lightning drawn as pixel art on the world texel grid. A bolt (trunk,
## branches and forks, each a polyline in world texels) is rasterised once per
## strike into a small texture of two-texel cells: every segment steps one cell
## at a time in its major axis (no smooth sub-texel diagonal), trunk, branches
## and forks alike with a white core and a pale-blue edge, the trunk also with a
## dithered glow. Each cell takes one tone (no stacked translucent squares,
## which blur into an anti-aliased line), so the whole bolt fades as one image.
## Presentation only.

const GLOW := 1
const EDGE := 2
const CORE := 3
## Tone per level (index): none, glow, edge, core.
const TONES := [Color(0, 0, 0, 0), Color(.55, .70, .98, .34), Color(.64, .78, 1.0, .92), Color(.97, .98, 1.0, 1.0)]
const MARGIN := 4
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

## Jagged copy of `path`: every straight span longer than `step` texels gets
## kinks pushed sideways by up to `kink` texels, drawn from `random`, so no
## branch is one long straight run. End points stay where they are.
static func jag(path: PackedVector2Array, random: RandomNumberGenerator, step: float = 9.0, kink: float = 3.0) -> PackedVector2Array:
	var result := PackedVector2Array()
	if path.is_empty(): return result
	result.append(path[0].round())
	for index in range(1, path.size()):
		var from := path[index - 1]
		var to := path[index]
		var span := to - from
		var pieces := maxi(1, int(span.length() / step))
		var side := span.orthogonal().normalized() if span.length_squared() > .01 else Vector2.RIGHT
		for piece in range(1, pieces):
			var at := from + span * (float(piece) / float(pieces)) + side * random.randf_range(-kink, kink)
			result.append(at.round())
		result.append(to.round())
	return result

## The bolt as a texture, its world origin (top-left texel) and its drawn
## size, or an empty dictionary for an empty bolt. The bolt is built in cells
## of `cell` world texels (the chunky two-texel grain of the actor art), so its
## steps stay clearly visible at the wide camera too. trunk_glow: a dithered
## glow around the trunk. Draw it with draw_texture_rect(texture, Rect2(origin,
## size), false, modulate).
static func rasterise(trunk: PackedVector2Array, branches: Array[PackedVector2Array], forks: Array[PackedVector2Array], trunk_glow: bool = true, cell: int = 2) -> Dictionary:
	if trunk.size() < 2 or cell < 1: return {}
	var unit := float(cell)
	var paths: Array[PackedVector2Array] = []
	for path: PackedVector2Array in [trunk] + branches + forks:
		var scaled := PackedVector2Array()
		for point in path: scaled.append((point / unit).floor())
		paths.append(scaled)
	var low := paths[0][0]
	var high := paths[0][0]
	for path in paths:
		for point in path:
			low = low.min(point)
			high = high.max(point)
	var origin := Vector2i(low) - Vector2i(MARGIN, MARGIN)
	var size := Vector2i(high) - origin + Vector2i(MARGIN + 1, MARGIN + 1)
	if size.x <= 0 or size.y <= 0 or size.x * size.y > 600000: return {}
	var levels := PackedByteArray()
	levels.resize(size.x * size.y)
	var rgba := PackedByteArray()
	rgba.resize(size.x * size.y * 4)
	# Trunk, branches and forks share one construction: a one-cell core and a
	# one-cell edge; the trunk alone carries the glow.
	_stroke(paths[0], origin, size, levels, rgba, 1, 2 if trunk_glow else 0)
	for index in range(1, paths.size()): _stroke(paths[index], origin, size, levels, rgba, 1, 0)
	var image := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, rgba)
	return {"texture": ImageTexture.create_from_image(image), "origin": Vector2(origin) * unit, "size": Vector2(size) * unit}

## One path into the level buffer: a `core`-texel core, one edge texel around
## it and, with `glow` > 0, a dithered glow of that many texels around the edge.
static func _stroke(path: PackedVector2Array, origin: Vector2i, size: Vector2i, levels: PackedByteArray, rgba: PackedByteArray, core: int, glow: int) -> void:
	var lead := core >> 1
	var count := 0
	for index in range(1, path.size()):
		var from := path[index - 1].round()
		var span := path[index].round() - from
		var steps := maxi(1, int(maxf(absf(span.x), absf(span.y))))
		for step in steps + 1:
			var at := Vector2i((from + span * (float(step) / float(steps))).round()) - origin
			count += 1
			# Core and edge at every step; the glow (a wider square) only at
			# every other one: neighbouring steps cover nearly the same texels.
			var reach := lead + 1 + (glow if count % 2 == 0 else 0)
			for dy in range(-reach, core - lead + reach):
				var y := at.y + dy
				if y < 0 or y >= size.y: continue
				for dx in range(-reach, core - lead + reach):
					var x := at.x + dx
					if x < 0 or x >= size.x: continue
					# Distance outside the core square, in texels (Chebyshev).
					var out := maxi(maxi(-lead - dx, dx - (core - lead - 1)), maxi(-lead - dy, dy - (core - lead - 1)))
					var level := CORE if out <= 0 else (EDGE if out == 1 else GLOW)
					var cell := y * size.x + x
					if levels[cell] >= level: continue
					# The glow thins out texel by texel in the ordered dither.
					if level == GLOW and BAYER[(x & 3) + (y & 3) * 4] >= (9 if out == 2 else 4): continue
					levels[cell] = level
					var tone: Color = TONES[level]
					rgba[cell * 4] = tone.r8
					rgba[cell * 4 + 1] = tone.g8
					rgba[cell * 4 + 2] = tone.b8
					rgba[cell * 4 + 3] = tone.a8

## A straight streak of single texels from `from` to `to` (one rect per texel,
## never a smooth sub-texel line), for sparks at the struck point.
static func stepped_line(node: CanvasItem, from: Vector2, to: Vector2, color: Color) -> void:
	var a := from.round()
	var span := to.round() - a
	var steps := maxi(1, int(maxf(absf(span.x), absf(span.y))))
	for step in steps + 1:
		node.draw_rect(Rect2((a + span * (float(step) / float(steps))).round(), Vector2.ONE), color)
