extends RefCounted
## Reuses the painted steel and refractory surfaces from the original machinery
## atlas. The cached native-pixel faces stay fixed while machine parts move.
const ATLAS := preload("res://assets/machinery/components.png")
const REGIONS := {
	"steel": Rect2i(1157, 215, 179, 44),
	"brick": Rect2i(1190, 304, 45, 24),
}
const EDGE := Color("aba38a")
const INK := Color("1a201c")
const EFFECT_FPS := 12.0
static var _source: Image
static var _faces: Dictionary = {}

static func _texture(size: Vector2i, tint: Color, variation: int, surface: String = "steel") -> Texture2D:
	variation = posmod(variation, 7)
	var key := "%s:%s:%s:%d" % [surface, size, tint.to_html(), variation]
	if _faces.has(key):
		return _faces[key]
	if _source == null:
		_source = ATLAS.get_image()
	var region: Rect2i = REGIONS[surface]
	var pixels := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for x in size.x:
		for y in size.y:
			var sx := region.position.x + posmod(x * 3 + variation * 11, region.size.x)
			var sy := region.position.y + posmod(y * 3 + variation * 7, region.size.y)
			var sample := _source.get_pixel(sx, sy)
			var pixel_color := sample.lerp(tint, 0.18 if surface == "steel" else 0.10)
			if surface == "steel":
				pixel_color = pixel_color.darkened(1.0 - clampf(tint.v * 1.4, 0.50, 0.94))
			# The bevel is a separate face; keep the upper-left edges brighter.
			if x == 0 or y == 0:
				pixel_color = pixel_color.lerp(EDGE, 0.56)
			elif x == size.x - 1 or y == size.y - 1:
				pixel_color = pixel_color.darkened(0.58)
			elif x == size.x - 2 or y == size.y - 2:
				pixel_color = pixel_color.darkened(0.24)
			pixels.set_pixel(x, y, pixel_color)
	_faces[key] = ImageTexture.create_from_image(pixels)
	return _faces[key]

static func face(canvas: Node2D, rect: Rect2, tint: Color, variation: int = 0, surface: String = "steel") -> void:
	var size := Vector2i(maxi(1, roundi(rect.size.x)), maxi(1, roundi(rect.size.y)))
	canvas.draw_texture_rect(_texture(size, tint, variation, surface), Rect2(rect.position.round(), Vector2(size)), false)

static func panel(canvas: Node2D, rect: Rect2, tint: Color, variation: int = 0) -> void:
	canvas.draw_rect(rect.grow(1), INK)
	face(canvas, rect, tint, variation)
	for corner in [rect.position + Vector2(4, 4), rect.position + Vector2(rect.size.x - 5, 4), rect.end - Vector2(5, 5), rect.position + Vector2(4, rect.size.y - 5)]:
		canvas.draw_rect(Rect2(corner.round() - Vector2.ONE, Vector2(3, 3)), INK)
		canvas.draw_rect(Rect2(corner.round() - Vector2.ONE, Vector2.ONE), Color("b7a484"))
		canvas.draw_rect(Rect2(corner.round(), Vector2.ONE), Color("77725c"))

static func polygon(canvas: Node2D, vertices: PackedVector2Array, tint: Color, variation: int = 0) -> void:
	var bounds := Rect2(vertices[0], Vector2.ZERO)
	for vertex in vertices:
		bounds = bounds.expand(vertex)
	var size := Vector2i(maxi(1, roundi(bounds.size.x)), maxi(1, roundi(bounds.size.y)))
	var uvs := PackedVector2Array()
	for vertex in vertices:
		uvs.append((vertex - bounds.position) / Vector2(size))
	canvas.draw_polygon(vertices, PackedColorArray([Color.WHITE]), uvs, _texture(size, tint, variation))

static func firebox(canvas: Node2D, rect: Rect2, elapsed: float, working: bool, electric: bool = false) -> void:
	var animation_time := floorf(elapsed * EFFECT_FPS) / EFFECT_FPS
	var reduced := reduced_effects(canvas)
	if working and not reduced:
		_glow(canvas, rect, animation_time, electric)
	canvas.draw_rect(rect, Color("171710"))
	if not working:
		canvas.draw_rect(Rect2(rect.position + Vector2(2, rect.size.y - 3), Vector2(rect.size.x - 4, 2)), Color("3a3020"))
		return
	# Local pixel clusters build a dark chamber, hot bed and moving gas tongues;
	# the envelope stays behind the masonry and never becomes a flat orange card.
	var hot := Color("ffe7a9") if not electric else Color("edf3df")
	var amber := Color("d18438") if not electric else Color("a4a992")
	for row in range(0, int(rect.size.y), 2):
		var depth := float(row) / maxf(1.0, rect.size.y - 1.0)
		canvas.draw_rect(Rect2(rect.position + Vector2(1, row), Vector2(rect.size.x - 2, 2)), Color("382319").lerp(amber, depth * depth * 0.66))
	var columns := floori((rect.size.x - 4) / 7.0)
	for column in columns:
		var x := rect.position.x + 2 + column * 7
		var wave := sin(animation_time * 7.4 + column * 2.2) * 0.5 + sin(animation_time * 4.3 - column * 1.1) * 0.3
		var height := roundf(3 + (wave + 0.8) * (3.0 if electric else 11.0))
		var base_y := rect.end.y - 2
		var lean := roundf(sin(animation_time * 5.0 + column * 1.8))
		canvas.draw_rect(Rect2(x, base_y - roundf(height * 0.45), 7, roundf(height * 0.45)), amber)
		canvas.draw_rect(Rect2(x + 1, base_y - roundf(height * 0.75), 5, roundf(height * 0.50)), amber)
		canvas.draw_rect(Rect2(x + 2 + lean, base_y - height, 2, roundf(height * 0.5)), amber)
		canvas.draw_rect(Rect2(x + 1, base_y - roundf(height * 0.35), 5, roundf(height * 0.35)), hot)
		canvas.draw_rect(Rect2(x + 2, base_y - roundf(height * 0.60), 2, roundf(height * 0.50)), hot)
	# A broken glowing bed joins the tongues and leaves darker slag between them.
	for ember in range(1, int(rect.size.x) - 2, 3):
		var intensity := 0.55 + sin(animation_time * 6.0 + ember * 2.3) * 0.28
		canvas.draw_rect(Rect2(rect.position.x + ember, rect.end.y - 3, 2, 1), amber.lerp(hot, intensity))
	if not reduced:
		for spark in 4:
			var age := fmod(animation_time * 0.74 + spark * 0.23, 1.0)
			var spark_x := rect.position.x + 5 + fmod(spark * 11.0, rect.size.x - 10.0) + roundf(sin(age * 5.0 + spark) * 2.0)
			var spark_y := rect.end.y - 5 - roundf(age * (rect.size.y - 9))
			canvas.draw_rect(Rect2(spark_x, spark_y, 1, 1 if age > 0.6 else 2), amber.lerp(hot, 1.0 - age))
	if electric:
		for path in electric_paths(rect, animation_time, reduced):
			canvas.draw_polyline(path, Color(0.24, 0.33, 0.31, 0.8), 3)
			canvas.draw_polyline(path, Color("f6f3d6"), 1)

static func reduced_effects(canvas: Node2D) -> bool:
	if not "game" in canvas:
		return false
	var game = canvas.get("game")
	return is_instance_valid(game) and "weather" in game and is_instance_valid(game.weather) and game.weather.reduced_effects

static func electric_paths(rect: Rect2, elapsed: float, reduced: bool) -> Array[PackedVector2Array]:
	var paths: Array[PackedVector2Array] = []
	var tick := floori(elapsed * EFFECT_FPS)
	for electrode in (1 if reduced else 2):
		if not reduced and posmod(tick + electrode * 5, 13) < 2:
			continue
		var start := Vector2(rect.position.x + rect.size.x * (0.22 + electrode * 0.56), rect.position.y + 1).round()
		var end := start + Vector2(5 if electrode == 0 else -5, rect.size.y - 6)
		var path := PackedVector2Array([start])
		for segment in range(1, 5):
			var hash_value := posmod(tick * 137 + electrode * 211 + segment * 71, 997)
			var point := start.lerp(end, segment / 5.0) + Vector2(hash_value % 7 - 3, hash_value % 3 - 1)
			point.x = clampf(point.x, rect.position.x + 2, rect.end.x - 3)
			point.y = clampf(point.y, rect.position.y + 1, rect.end.y - 3)
			path.append(point.round())
		path.append(end.round())
		paths.append(path)
		if not reduced and posmod(tick + electrode, 3) != 0:
			var direction := 1 if electrode == 0 else -1
			var branch := PackedVector2Array([path[2]])
			for bend in 2:
				var point := path[2] + Vector2(direction * (4 + bend * 3), 3 + bend * 5)
				point.x = clampf(point.x, rect.position.x + 2, rect.end.x - 3)
				point.y = clampf(point.y, rect.position.y + 1, rect.end.y - 3)
				branch.append(point.round())
			paths.append(branch)
	return paths

static func _glow(canvas: Node2D, rect: Rect2, animation_time: float, electric: bool) -> void:
	var glow_tint := Color("e59a42") if not electric else Color("c3d4d5")
	var pulse := 0.85 + sin(animation_time * 7.4) * 0.15
	for ring in range(3, 0, -1):
		var bounds := rect.grow(3 + ring * 8)
		var corner := Vector2(7 + ring * 2, 0)
		var turn := Vector2(0, corner.x)
		var points := PackedVector2Array([bounds.position + corner, Vector2(bounds.end.x, bounds.position.y) - corner, Vector2(bounds.end.x, bounds.position.y) + turn, bounds.end - turn, bounds.end - corner, Vector2(bounds.position.x, bounds.end.y) + corner, Vector2(bounds.position.x, bounds.end.y) - turn, bounds.position + turn])
		glow_tint.a = 0.017 * pulse
		canvas.draw_colored_polygon(points, glow_tint)

static func exhaust(canvas: Node2D, outlets: PackedVector2Array, elapsed: float, working: bool) -> void:
	if not working or reduced_effects(canvas):
		return
	var animation_time := floorf(elapsed * EFFECT_FPS) / EFFECT_FPS
	for outlet_index in outlets.size():
		for puff in 4:
			var age := fmod(animation_time * 0.45 + puff * 0.25 + outlet_index * 0.12, 1.0)
			var drift := Vector2(sin(age * 4 + outlet_index) * (2 + age * 5), -3 - age * 28).round()
			var at := outlets[outlet_index] + drift
			var width := 3 + roundi(age * 5)
			var tint := Color(0.46, 0.47, 0.39, (1.0 - age) * 0.17)
			canvas.draw_rect(Rect2(at - Vector2(width * 0.5, 0).round(), Vector2(width, 3)), tint)
			canvas.draw_rect(Rect2(at + Vector2(-1, -2), Vector2(maxi(2, width - 2), 2)), tint)
