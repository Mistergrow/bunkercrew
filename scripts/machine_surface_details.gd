extends RefCounted
const Quads := preload("res://scripts/canvas_quads.gd")
## Worn metal for small mechanisms. Every animated face maps a fixed 32px tile;
## no changing stroke length, angle or world position enters the texture cache.
const Surface := preload("res://scripts/station_surface_art.gd")
const INK := Color("19231f")
const FINISHES := {
	"steel": Color("7b8172"),
	"dark": Color("414d43"),
	"brass": Color("a18b60"),
}
const HIGHLIGHTS := {"steel": Color("c0b99b"), "dark": Color("838875"), "brass": Color("c5ac78")}

static func polygon(canvas: Node2D, points: PackedVector2Array, finish := "steel", variation := 0) -> void:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	var size := Vector2(maxf(1, bounds.size.x), maxf(1, bounds.size.y))
	var uvs := PackedVector2Array()
	for point in points:
		uvs.append((point - bounds.position) / size)
	var tint: Color = FINISHES.get(finish, FINISHES.steel)
	canvas.draw_polygon(points, PackedColorArray([Color.WHITE]), uvs, Surface._texture(Vector2i(32, 32), tint, posmod(variation, 7)))

static func face(canvas: Node2D, rect: Rect2, finish := "steel", variation := 0) -> void:
	polygon(canvas, PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]), finish, variation)

static func shaft(canvas: Node2D, start: Vector2, end: Vector2, width: float, finish := "steel") -> void:
	var normal := (end - start).normalized().orthogonal()
	if normal.y > 0: normal = -normal
	canvas.draw_line(start, end, INK, width + 2)
	polygon(canvas, PackedVector2Array([(start + normal * width * .5).round(), (end + normal * width * .5).round(), (end - normal * width * .5).round(), (start - normal * width * .5).round()]), finish, 2)
	canvas.draw_line((start + normal).round(), (end + normal).round(), HIGHLIGHTS.get(finish, HIGHLIGHTS.steel), 1)
	canvas.draw_line((start - normal).round(), (end - normal).round(), Color("30392f"), 1)

static func disc(canvas: Node2D, at: Vector2, radius: float, finish := "steel") -> void:
	var points := PackedVector2Array()
	for index in 24:
		var point := (at + Vector2.from_angle(index * TAU / 24.0) * radius).round()
		if points.is_empty() or point != points[-1]: points.append(point)
	polygon(canvas, points, finish, 4)

static func wheel(canvas: Node2D, at: Vector2, radius: float, angle: float) -> void:
	canvas.draw_circle(at, radius + 1, INK)
	disc(canvas, at, radius, "dark")
	disc(canvas, at - Vector2.ONE, radius - 2, "steel")
	canvas.draw_circle(at, radius - 6, INK)
	canvas.draw_arc(at - Vector2.ONE, radius - 1, -PI, -.35, 22, Color("c0a780"), 1)
	canvas.draw_arc(at, radius - 3, .1, 2.8, 22, Color("343c31"), 2)
	for index in 4:
		var direction := Vector2.from_angle(angle + index * PI * .5)
		shaft(canvas, at + direction * 3, at + direction * (radius - 4), 3)
	canvas.draw_circle(at, 5, INK)
	disc(canvas, at, 4, "brass")
	Quads.rect(canvas,Rect2(at - Vector2.ONE, Vector2(2, 2)), Color("484936"))
	Quads.rect(canvas,Rect2(at - Vector2.ONE, Vector2.ONE), Color("dcc595"))

static func chamber_frame(canvas: Node2D, opening: Rect2) -> void:
	# Cast side returns, underside shadow and a worn sill give the aperture
	# depth while leaving the existing flame/electrode effect bounds untouched.
	face(canvas, Rect2(opening.position - Vector2(5, 3), Vector2(5, opening.size.y + 6)), "steel", 1)
	face(canvas, Rect2(opening.end.x, opening.position.y - 3, 5, opening.size.y + 6), "dark", 2)
	face(canvas, Rect2(opening.position.x - 5, opening.end.y, opening.size.x + 10, 5), "steel", 3)
	canvas.draw_line(opening.position, Vector2(opening.end.x, opening.position.y), Color("101913"), 3)
	canvas.draw_line(opening.position - Vector2(2, 1), Vector2(opening.position.x - 2, opening.end.y + 2), Color("b2a084"), 1)
	canvas.draw_line(Vector2(opening.position.x - 3, opening.end.y + 1), opening.end + Vector2(3, 1), Color("aa9573"), 1)
	for y in [opening.position.y + 7, opening.end.y - 9]:
		face(canvas, Rect2(opening.end.x + 1, y, 7, 5), "brass", 2)
		Quads.rect(canvas,Rect2(opening.end.x + 3, y + 1, 1, 3), Color("cab283"))
