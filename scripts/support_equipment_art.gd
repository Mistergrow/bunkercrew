extends RefCounted
## Small service machines share the furnace's painted steel, worn olive finish
## and one-pixel hardware. The caller supplies all animation and gameplay state.

const Surface := preload("res://scripts/station_surface_art.gd")
const WORKBENCH := preload("res://assets/props/workbench.tres")
const INK := Color("17211f")
const OLIVE := Color("55614d")
const EDGE := Color("b3aa87")
const RUST := Color("87634b")

static func workshop(canvas: Node2D, elapsed: float, working: bool) -> void:
	canvas.draw_rect(Rect2(-49, -2, 98, 5), Color(0, 0, 0, 0.30))
	# Source proportions place the vise above the tabletop and both feet on
	# the old floor. The tools are part of the equipment, not floating UI icons.
	canvas.draw_texture_rect(WORKBENCH, Rect2(-49, -61, 98, 61), false)
	canvas.draw_line(Vector2(34, -36), Vector2(34, -69), INK, 5)
	canvas.draw_line(Vector2(33, -37), Vector2(33, -68), RUST, 2)
	canvas.draw_line(Vector2(34, -69), Vector2(12, -69), INK, 4)
	canvas.draw_line(Vector2(33, -70), Vector2(12, -70), EDGE, 1)
	Surface.face(canvas, Rect2(8, -72, 14, 5), OLIVE, 1)
	canvas.draw_rect(Rect2(10, -67, 10, 2), Color("e4c68a"))
	canvas.draw_rect(Rect2(11, -67, 8, 1), Color("fff0bf"))
	canvas.draw_line(Vector2(31, -38), Vector2(31, -56), Color("343a2d"), 1)
	if working:
		var tick := floori(elapsed * 12.0)
		var contact := Vector2(-26, -45)
		for spark in 3:
			var phase := posmod(tick + spark * 2, 7)
			var point := contact + Vector2(phase * (1 if spark % 2 else -1), -6 + phase)
			canvas.draw_rect(Rect2(point, Vector2(1, 1 + spark % 2)), Color("e0ac62") if phase > 2 else Color("ffe7a8"))

static func casing(canvas: Node2D, rect: Rect2, tint := OLIVE, variation := 0) -> void:
	canvas.draw_rect(rect.grow(1), INK)
	Surface.face(canvas, rect, tint, variation)
	for point in [rect.position + Vector2(2, 2), rect.end - Vector2(3, 3)]:
		canvas.draw_rect(Rect2(point, Vector2(2, 2)), INK)
		canvas.draw_rect(Rect2(point, Vector2.ONE), EDGE)

static func joint(canvas: Node2D, point: Vector2, radius := 3.0) -> void:
	point = point.round()
	canvas.draw_circle(point, radius, INK)
	canvas.draw_circle(point, radius - 1.0, RUST)
	canvas.draw_rect(Rect2(point - Vector2.ONE, Vector2(2, 2)), Color("555b4a"))
	canvas.draw_rect(Rect2(point - Vector2.ONE, Vector2.ONE), EDGE)

static func linkage(canvas: Node2D, start: Vector2, end: Vector2, width := 4.0) -> void:
	start = start.round()
	end = end.round()
	var normal := (end - start).normalized().orthogonal()
	if normal.y > 0:
		normal = -normal
	canvas.draw_line(start, end, INK, width + 2.0)
	var face := PackedVector2Array([(start + normal * width * 0.5).round(), (end + normal * width * 0.5).round(), (end - normal * width * 0.5).round(), (start - normal * width * 0.5).round()])
	# Arm lengths and angles change during climbing/treatment. Reuse one fixed
	# texture instead of caching a new surface for every animated bounding box.
	canvas.draw_polygon(face, PackedColorArray([Color.WHITE]), PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]), Surface._texture(Vector2i(32, 6), OLIVE, 3))
	canvas.draw_line(start + normal, end + normal, EDGE, 1)
	canvas.draw_line(start - normal, end - normal, Color("333e32"), 1)

static func tracks(canvas: Node2D, motion_phase: float) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(-18, -7), Vector2(-15, -11), Vector2(14, -11), Vector2(18, -7), Vector2(16, -1), Vector2(-16, -1)]), INK)
	Surface.face(canvas, Rect2(-15, -9, 30, 6), Color("55594b"), 4)
	for x in [-12, 0, 12]:
		joint(canvas, Vector2(x, -6), 3)
	for index in 9:
		var x := floorf(fposmod(index * 4.0 - motion_phase, 36.0)) - 18.0
		canvas.draw_rect(Rect2(x, -2, 2, 1), Color("8c8870"))
		if x > -14 and x < 14:
			canvas.draw_rect(Rect2(-x, -10, 2, 1), Color("7a7860"))

static func medic_body(canvas: Node2D, bob: float, look: float, supplies: int, treating: bool, head_drop: float = 0.0) -> void:
	casing(canvas, Rect2(-15, -27 + bob, 30, 17), OLIVE, 2)
	Surface.face(canvas, Rect2(-15, -13 + bob, 30, 3), Color("414c3d"), 5)
	canvas.draw_rect(Rect2(-12, -24 + bob, 14, 12), Color("273b32"))
	canvas.draw_line(Vector2(-11, -24 + bob), Vector2(0, -24 + bob), Color("62745e"), 1)
	canvas.draw_rect(Rect2(-8, -22 + bob, 3, 9), Color("d1d0b5"))
	canvas.draw_rect(Rect2(-11, -19 + bob, 9, 3), Color("d1d0b5"))
	# Tiny wear marks retain a recognizable medical emblem at normal scale.
	canvas.draw_rect(Rect2(-10, -19 + bob, 1, 1), Color("899781"))
	canvas.draw_rect(Rect2(4, -23 + bob, 10, 12), INK)
	for index in MedicalCatalog.MAX_CHARGES:
		var at := Vector2(5 + index * 5, -21 + bob)
		canvas.draw_rect(Rect2(at, Vector2(3, 7)), Color("8a9770") if index < supplies else Color("3c4a39"))
		canvas.draw_rect(Rect2(at + Vector2(0, 1), Vector2(2, 1)), Color("d6c995") if index < supplies else Color("607057"))
	var head_y := bob + clampf(head_drop, 0.0, 4.5)
	linkage(canvas, Vector2(0, -28 + bob), Vector2(look, -33 + head_y), 3)
	casing(canvas, Rect2(look - 7, -39 + head_y, 14, 8), Color("616857"), 6)
	canvas.draw_rect(Rect2(look - 5, -37 + head_y, 10, 3), Color("141f1e"))
	canvas.draw_rect(Rect2(look - 4, -37 + head_y, 7, 2), Color("d2b778") if treating else Color("93b6a0"))
	canvas.draw_rect(Rect2(look - 3, -37 + head_y, 2, 1), Color("eadcae") if treating else Color("c3d6bb"))
	canvas.draw_rect(Rect2(look + 4, -37 + head_y, 1, 2), Color("897650"))

static func construction_panel(canvas: Node2D, tint: Color, built: bool) -> void:
	canvas.draw_rect(Rect2(-21, -2, 42, 3), Color(0, 0, 0, 0.28))
	Surface.panel(canvas, Rect2(-18, -43, 36, 39), Color("68705c"), 3)
	Surface.face(canvas, Rect2(15, -40, 4, 34), Color("384437"), 4)
	canvas.draw_rect(Rect2(-14, -37, 28, 21), INK)
	canvas.draw_rect(Rect2(-12, -35, 24, 16), Color("27352e"))
	canvas.draw_line(Vector2(-12, -35), Vector2(11, -35), Color("607159"), 1)
	for index in 3:
		var at := Vector2(-10 + index * 8, -32)
		canvas.draw_rect(Rect2(at - Vector2(1, 1), Vector2(6, 12)), Color("18251f"))
		canvas.draw_rect(Rect2(at, Vector2(4, 9)), tint if built or index == 0 else tint.darkened(0.55))
		canvas.draw_rect(Rect2(at, Vector2(3, 1)), tint.lightened(0.16) if built or index == 0 else tint.darkened(0.38))
	joint(canvas, Vector2(-10, -10), 3)
	canvas.draw_line(Vector2(-10, -12), Vector2(-9, -10), EDGE, 1)
	canvas.draw_rect(Rect2(-1, -12, 10, 4), Color("202c25"))
	for x in [1, 4, 7]:
		canvas.draw_rect(Rect2(x, -11, 1, 2), Color("76806b"))
