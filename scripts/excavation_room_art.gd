class_name ExcavationRoomArt
extends RefCounted
## Construction layers use the same cutaway, piers and materials as paid rooms.
## Real MineBlock nodes cover the backing until their earth is actually removed.
const ROCK_PATH := "res://assets/rock.png"
const ROCK_REGION := Rect2(0, 0, 1254, 1254)
const Surface := preload("res://scripts/station_surface_art.gd")
const PERIOD := 480.0
## Lip, shade and lamp pools of an open dig, cached per rect and lamp layout.
static var _depth_cache: Dictionary = {}
const LIP_ROCK := [Color("2b2a24"), Color("4a463b"), Color("6a6250"), Color("8e8064")]
const POOL := Color(1.0, 0.70, 0.36)
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

## The rock face at one texel per world unit (its offline bake, see
## tools/world_density_bake.json); the 1254 px source only as a fallback.
static func rock_texture() -> Texture2D:
	var baked := WorldTexels.texture(ROCK_PATH, ROCK_REGION, Vector2i(roundi(PERIOD), roundi(PERIOD)))
	return baked if baked != null else load(ROCK_PATH) as Texture2D

static func draw_room(node: Node2D, bunker: Node, index: int, elapsed: float, rear_shift: Vector2) -> void:
	var rect: Rect2 = bunker.raw_rect(index)
	var site: Node = bunker.modules[index] if index < bunker.modules.size() else null
	var rear := Rect2(rect.position + Vector2(12, 24), rect.size - Vector2(24, 24))
	var supported := is_instance_valid(site) and bool(site.supported)
	var assembly := clampf(float(site.support_work) / ScenarioRoomCatalog.SUPPORT_TIME, 0.0, 1.0) if is_instance_valid(site) else 0.0
	var construction := clampf(float(site.construction) / ScenarioRoomCatalog.BUILD_TIME, 0.0, 1.0) if supported else 0.0
	if is_instance_valid(site) and site.curing:
		# Once poured, the finished structure is visible while its concrete cures.
		# Rewards and room access still belong to the real site's completion API.
		ScenarioBunkerArt.draw_room(node, rect, bunker.build_type, index + 1, elapsed, rear_shift, true, bunker.passage_rects())
		_draw_curing(node, rect, float(site.curing_remaining) / ScenarioRoomCatalog.CURE_TIME)
		return
	node.draw_rect(rear, Color("141d1b"))
	_draw_rock(node, rear, Color("65705e"))
	# Depth of the dig: a broken rock lip instead of a straight cut, the lip's
	# shadow and a floor that sinks into the dark, and warm pools around the
	# work lamp and the cable bulbs (D17).
	var work_lamp := Vector2(rect.position.x + 87, rear.position.y + 19)
	_draw_depth(node, rear, rect, work_lamp)
	# The roof is a fractured geological edge, without a rectangular ore inset.
	_draw_ceiling(node, rear)
	_draw_soil_footing(node, rear)
	# One work light follows the access shaft. Permanent lights and service pipes
	# are installed with the room, rather than appearing in unexcavated earth.
	ScenarioBunkerArt.draw_work_lamp(node, work_lamp, rect.end.y - 4, elapsed)
	_draw_festoon(node, rect)
	if construction > 0.0:
		_draw_wall_installation(node, rect, str(bunker.build_type), construction, rear_shift)
	if supported or assembly > 0.0:
		_draw_supports(node, rect, str(bunker.build_type), 1.0 if supported else assembly)
	elif is_instance_valid(site) and not site.support_materials.is_empty():
		_draw_material_stack(node, Vector2(rect.position.x + 135, rect.end.y), int(site.support_materials.get("steel", 0)))

## Bulbs of the temporary cable run strung from the shaft across an open
## excavation, in world space (WorldLighting gives them their glow).
const FESTOON := [.16, .40, .64, .88]
static func festoon_points(rect: Rect2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var left := rect.position.x + 104.0
	var right := rect.end.x - 26.0
	for share: float in FESTOON:
		var x := roundf(lerpf(left, right, share))
		# The cable sags between its three hooks; bulbs hang below it.
		var sag := roundf(sin(fposmod(share * 3.0, 1.0) * PI) * 6.0)
		points.append(Vector2(x, rect.position.y + 40.0 + sag + 5.0))
	return points

## A sagging work cable with caged bulbs over the unexcavated face, so the
## dig reads as a lit, worked site instead of a black box.
static func _draw_festoon(node: Node2D, rect: Rect2) -> void:
	var left := rect.position.x + 104.0
	var right := rect.end.x - 26.0
	var top := rect.position.y + 40.0
	var hooks := 3
	for hook in hooks:
		var from := lerpf(left, right, float(hook) / float(hooks))
		var to := lerpf(left, right, float(hook + 1) / float(hooks))
		var steps := int((to - from) / 4.0)
		for step in steps:
			var t := float(step) / float(steps)
			node.draw_rect(Rect2(roundf(from + float(step) * 4.0), roundf(top + sin(t * PI) * 6.0), 4, 1), Color("1d211c"))
		node.draw_rect(Rect2(roundf(from) - 1, top - 2, 3, 3), Color("4e5144"))
	node.draw_rect(Rect2(roundf(right) - 1, top - 2, 3, 3), Color("4e5144"))
	for point in festoon_points(rect):
		node.draw_rect(Rect2(point.x, point.y - 5, 1, 4), Color("1d211c"))
		node.draw_rect(Rect2(point.x - 1, point.y - 1, 3, 4), Color("ffd890"))
		node.draw_rect(Rect2(point.x, point.y, 1, 2), Color("fff6dc"))
		node.draw_rect(Rect2(point.x - 2, point.y - 2, 5, 1), Color("3c4036"))
		node.draw_rect(Rect2(point.x - 2, point.y + 3, 5, 1), Color("3c4036"))

static func _draw_rock(node: Node2D, rect: Rect2, tint: Color) -> void:
	var rock := rock_texture()
	var ratio := rock.get_size() / PERIOD
	var y := rect.position.y
	while y < rect.end.y - 0.01:
		var source_y := fposmod(y, PERIOD)
		var height := minf(rect.end.y - y, PERIOD - source_y)
		var x := rect.position.x
		while x < rect.end.x - 0.01:
			var source_x := fposmod(x, PERIOD)
			var width := minf(rect.end.x - x, PERIOD - source_x)
			node.draw_texture_rect_region(rock, Rect2(x, y, width, height), Rect2(Vector2(source_x, source_y) * ratio, Vector2(width, height) * ratio), tint)
			x += width
		y += height
	# Recessed rock remains readable in an excavated bay without competing with
	# the opaque working face drawn by real cells in front of it.
	node.draw_rect(rect, Color(0.025, 0.04, 0.035, 0.37))
	node.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 12)), Color(0.015, 0.025, 0.02, 0.35))

static func _draw_depth(node: Node2D, rear: Rect2, rect: Rect2, work_lamp: Vector2) -> void:
	var origin := rear.position.round()
	var size := Vector2i(rear.size.round())
	var lamps: Array[Vector3] = [Vector3(work_lamp.x - origin.x, work_lamp.y - origin.y + 8.0, 62.0)]
	for bulb in festoon_points(rect):
		lamps.append(Vector3(bulb.x - origin.x, bulb.y - origin.y + 2.0, 42.0))
	var key := "%s|%s" % [size, lamps]
	if not _depth_cache.has(key):
		_depth_cache[key] = _depth_texture(size, lamps)
	node.draw_texture(_depth_cache[key], origin)

## Whole texels only. The jagged lip of rock teeth (5 texels a step, 3-11 deep)
## overhangs the dig on both sides; its inner rim catches the lamps, the void
## beside it keeps a dark crack. Shade (lip shadow, deeper floor) and light
## (lamp pools) are stepped by a 4x4 ordered dither, never a smooth ramp.
static func _depth_texture(size: Vector2i, lamps: Array[Vector3]) -> ImageTexture:
	var light := PackedFloat32Array()
	light.resize(size.x * size.y)
	for lamp in lamps:
		var radius := lamp.z
		for y in range(maxi(0, floori(lamp.y - radius)), mini(size.y, ceili(lamp.y + radius * 1.2))):
			for x in range(maxi(0, floori(lamp.x - radius * 1.4)), mini(size.x, ceili(lamp.x + radius * 1.4))):
				# Pools spread along the rock more than they fall.
				var reach := Vector2((x - lamp.x) / 1.4, (y - lamp.y) * (1.0 if y < lamp.y else .85)).length() / radius
				if reach < 1.0:
					light[y * size.x + x] += (1.0 - reach) * (1.0 - reach) * (1.1 if radius > 50.0 else .9)
	var lip_left := _lip_depths(size.y, 3)
	var lip_right := _lip_depths(size.y, 11)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		var floor_shade := smoothstep(.45, 1.0, float(y) / float(size.y)) * .34
		for x in size.x:
			var lit := light[y * size.x + x]
			var left := lip_left[y]
			var right := size.x - lip_right[y]
			if x < left or x >= right:
				# Rock lip: darker toward the room edge, its inner rim lit.
				var rim := x == left - 1 or x == right
				var top := y > 0 and ((x < left and x >= lip_left[y - 1]) or (x >= right and x < size.x - lip_right[y - 1]))
				var tone := 1 + (1 if rim or top else 0) + (1 if lit > .25 and (rim or top) else 0)
				image.set_pixel(x, y, LIP_ROCK[mini(tone, 3)])
				continue
			var edge := mini(mini(x - left, right - 1 - x), y)
			var shade := floor_shade + (.42 if edge == 0 else maxf(0.0, .30 - .05 * edge))
			var value := lit * .8 - shade
			var level := floorf(value * 6.0 + float(BAYER[(y % 4) * 4 + x % 4]) / 16.0) / 6.0
			if level < 0.0:
				image.set_pixel(x, y, Color(0.008, 0.012, 0.01, minf(-level, .62)))
			elif level > 0.0:
				image.set_pixel(x, y, Color(POOL, minf(level, .55)))
	return ImageTexture.create_from_image(image)

## Depth of the rock lip for each row: chunky teeth of five texels, 3-11 deep.
static func _lip_depths(rows: int, salt: int) -> PackedInt32Array:
	var depths := PackedInt32Array()
	depths.resize(rows)
	for y in rows:
		var chunk := floori(y / 5.0)
		depths[y] = 3 + posmod(chunk * 37 + salt * 11 + (chunk * chunk) % 7, 9)
	return depths

static func _draw_ceiling(node: Node2D, rect: Rect2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7109 + roundi(rect.position.y)
	var x := rect.position.x
	while x < rect.end.x:
		var width := minf(float(rng.randi_range(13, 29)), rect.end.x - x)
		var depth := float(rng.randi_range(4, 11))
		var outline := PackedVector2Array([Vector2(x, rect.position.y), Vector2(x + width, rect.position.y), Vector2(x + width, rect.position.y + 3), Vector2(x + width - 3, rect.position.y + 3), Vector2(x + width - 3, rect.position.y + depth), Vector2(x + 3, rect.position.y + depth), Vector2(x + 3, rect.position.y + depth - 3), Vector2(x, rect.position.y + depth - 3)])
		node.draw_colored_polygon(outline, Color("464b3c") if rng.randf() > 0.5 else Color("353d32"))
		x += width

static func _draw_soil_footing(node: Node2D, rect: Rect2) -> void:
	var floor_y := rect.end.y
	node.draw_rect(Rect2(rect.position.x, floor_y - 4, rect.size.x, 8), Color("30372b"))
	node.draw_line(Vector2(rect.position.x, floor_y - 3), Vector2(rect.end.x, floor_y - 3), Color("655d47"), 2)
	for index in floori(rect.size.x / 13.0):
		var x := rect.position.x + index * 13 + posmod(index * 7, 6)
		node.draw_rect(Rect2(x, floor_y - 5 - index % 2, 4 + index % 4, 2), Color("827355") if index % 3 == 0 else Color("4b4936"))

static func _draw_supports(node: Node2D, rect: Rect2, build_type: String, progress: float) -> void:
	var palettes := {"bastion":Color("72776b"), "workshop":Color("5b6868"), "stronghold":Color("757469")}
	var steel: Color = palettes.get(build_type, palettes.bastion)
	var top := rect.position.y + 30
	var bottom := rect.end.y - 6
	for index in 2:
		var fraction: float = [0.33, 0.69][index]
		var x := floorf(rect.position.x + rect.size.x * fraction)
		var height := (bottom - top) * clampf(progress * 2.6 - index * 0.75, 0.0, 1.0)
		if height <= 0.0: continue
		var post := Rect2(x, bottom - height, 17, height)
		node.draw_rect(post.grow(2), Color("17221e"))
		var post_texture := Surface._texture(Vector2i(17, ceili(bottom - top)), steel.darkened(0.22), index + 3)
		node.draw_texture_rect_region(post_texture, post, Rect2(0, bottom - top - height, 17, height))
		node.draw_rect(Rect2(x + 1, bottom - height, 3, height), steel.lightened(0.09))
		node.draw_rect(Rect2(x + 12, bottom - height, 3, height), steel.darkened(0.43))
		Surface.face(node, Rect2(x - 5, bottom - 3, 27, 6), steel.darkened(0.08), index + 5)
		for bolt_y in [bottom - 8, bottom - height + 8]:
			node.draw_rect(Rect2(x + 6, bolt_y, 3, 3), Color("2d342b"))
			node.draw_rect(Rect2(x + 6, bolt_y, 2, 1), Color("ada589"))
	if progress < 0.66: return
	var beam := Rect2(rect.position.x + 103, top - 8, rect.size.x - 122, 13)
	Surface.face(node, beam, steel.darkened(0.12), 6)
	node.draw_line(beam.position + Vector2(0, 1), Vector2(beam.end.x, beam.position.y + 1), steel.lightened(0.13), 2)
	node.draw_line(Vector2(beam.position.x, beam.end.y), beam.end, steel.darkened(0.45), 3)
	for fraction in [0.33, 0.69]:
		var x := floorf(rect.position.x + rect.size.x * fraction)
		for direction in [-1, 1]:
			var from := Vector2(x + 8, top + 30)
			var to := Vector2(x + 8 + direction * 29, top + 4)
			node.draw_line(from, to, Color("1d2923"), 8)
			node.draw_line(from, to, steel.darkened(0.12), 5)
			node.draw_line(from + Vector2(-1, -1), to + Vector2(-1, -1), steel.lightened(0.1), 1)

static func _draw_wall_installation(node: Node2D, rect: Rect2, build_type: String, progress: float, rear_shift: Vector2) -> void:
	var rear := rect.grow_individual(-13, -17, -13, -7)
	var inset := rear.grow(8)
	var texture := ScenarioBunkerArt.wall_texture(build_type)
	var width := floorf(inset.size.x * progress)
	if width <= 0.0: return
	var destination := Rect2(inset.position - rear_shift.round() * 0.5, Vector2(width, inset.size.y))
	var source := Rect2(Vector2.ZERO, Vector2(texture.get_width() * progress, texture.get_height()))
	node.draw_texture_rect_region(texture, destination, source, Color("a3a59b"))
	node.draw_rect(Rect2(destination.position, Vector2(width, 17)), Color(0.035, 0.05, 0.055, 0.4))
	var pipe_length := maxf(0.0, (rear.size.x - 6) * clampf((progress - 0.35) / 0.65, 0.0, 1.0))
	for utility in 2:
		var at := rear.position + Vector2(3, 26 + utility * 11) - rear_shift.round()
		node.draw_line(at, at + Vector2(pipe_length, 0), Color("151d1e"), 6 if utility == 0 else 3)
		node.draw_line(at + Vector2(0, -1), at + Vector2(pipe_length, -1), Color("706954") if utility == 0 else Color("4c574f"), 2)
	# A narrow shuttering edge makes the moving installation front legible.
	node.draw_rect(Rect2(destination.end.x - 4, rear.position.y + 3, 4, rear.size.y - 4), Color("706a53"))
	node.draw_line(Vector2(destination.end.x - 1, rear.position.y + 3), Vector2(destination.end.x - 1, rear.end.y - 1), Color("a39b78"), 1)

static func _draw_material_stack(node: Node2D, point: Vector2, amount: int) -> void:
	for index in mini(2, amount):
		var rect := Rect2(point + Vector2(index * 3, -7 - index * 5), Vector2(50, 4))
		Surface.face(node, rect, Color("5b6861"), index + 1)
		node.draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Color("a1a68f"), 1)

static func _draw_curing(node: Node2D, rect: Rect2, remaining: float) -> void:
	var wetness := clampf(remaining, 0.0, 1.0)
	node.draw_rect(Rect2(rect.position.x + 25, rect.end.y - 7, rect.size.x - 50, 6), Color(0.06, 0.1, 0.1, wetness * 0.25))
	# Small physical buckets mark active work; they disappear on commissioning.
	for index in 2:
		var at := Vector2(rect.position.x + 153 + index * 16, rect.end.y - 1)
		Surface.face(node, Rect2(at - Vector2(5, 13), Vector2(10, 12)), Color("575e51"), index + 2)
		node.draw_line(at + Vector2(-4, -13), at + Vector2(4, -13), Color("bab299"), 1)
