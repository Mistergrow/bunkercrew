class_name ExcavationRoomArt
extends RefCounted
## Construction layers use the same cutaway, piers and materials as paid rooms.
## Real MineBlock nodes cover the backing until their earth is actually removed.
const ROCK := preload("res://assets/rock.png")
const Surface := preload("res://scripts/station_surface_art.gd")
const PERIOD := 480.0

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
	# The roof is a fractured geological edge, without a rectangular ore inset.
	_draw_ceiling(node, rear)
	_draw_soil_footing(node, rear)
	# One work light follows the access shaft. Permanent lights and service pipes
	# are installed with the room, rather than appearing in unexcavated earth.
	ScenarioBunkerArt.draw_work_lamp(node, Vector2(rect.position.x + 87, rear.position.y + 19), rect.end.y - 4, elapsed)
	if construction > 0.0:
		_draw_wall_installation(node, rect, str(bunker.build_type), construction, rear_shift)
	if supported or assembly > 0.0:
		_draw_supports(node, rect, str(bunker.build_type), 1.0 if supported else assembly)
	elif is_instance_valid(site) and not site.support_materials.is_empty():
		_draw_material_stack(node, Vector2(rect.position.x + 135, rect.end.y), int(site.support_materials.get("steel", 0)))

static func _draw_rock(node: Node2D, rect: Rect2, tint: Color) -> void:
	var ratio := ROCK.get_size() / PERIOD
	var y := rect.position.y
	while y < rect.end.y - 0.01:
		var source_y := fposmod(y, PERIOD)
		var height := minf(rect.end.y - y, PERIOD - source_y)
		var x := rect.position.x
		while x < rect.end.x - 0.01:
			var source_x := fposmod(x, PERIOD)
			var width := minf(rect.end.x - x, PERIOD - source_x)
			node.draw_texture_rect_region(ROCK, Rect2(x, y, width, height), Rect2(Vector2(source_x, source_y) * ratio, Vector2(width, height) * ratio), tint)
			x += width
		y += height
	# Recessed rock remains readable in an excavated bay without competing with
	# the opaque working face drawn by real cells in front of it.
	node.draw_rect(rect, Color(0.025, 0.04, 0.035, 0.37))
	node.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 12)), Color(0.015, 0.025, 0.02, 0.35))

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
