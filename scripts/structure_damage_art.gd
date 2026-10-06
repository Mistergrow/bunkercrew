extends RefCounted
## Health-only presentation shared by existing walls and the original core.
## Fixed local pixel clusters reveal material and condition without emitters,
## resources, network state or collision changes.
enum Stage { INTACT, WORN, DAMAGED, CRITICAL }
const INK := Color("182221")
const CONCRETE_DARK := Color("303a35")
const CONCRETE_EDGE := Color("a5a28b")
const STEEL_DARK := Color("293934")
const STEEL_EDGE := Color("a9aa8d")
const EXPOSED_STEEL := Color("787d69")
const RUST := Color("765035")
static var _concrete_main := PackedVector2Array([Vector2(13,-77),Vector2(1,-62),Vector2(7,-52),Vector2(-4,-41),Vector2(-1,-31)])
static var _concrete_branch := PackedVector2Array([Vector2(-14,-51),Vector2(-4,-46),Vector2(3,-34),Vector2(12,-28)])
static var _concrete_notch := PackedVector2Array([Vector2(15,-46),Vector2(10,-44),Vector2(10,-40),Vector2(5,-40),Vector2(5,-35),Vector2(9,-35),Vector2(9,-26),Vector2(15,-26)])
static var _concrete_critical := PackedVector2Array([Vector2(-15,-76),Vector2(-10,-76),Vector2(-10,-72),Vector2(-6,-72),Vector2(-6,-64),Vector2(-10,-64),Vector2(-10,-57),Vector2(-15,-57)])
static var _armor_tear := PackedVector2Array([Vector2(16,-43),Vector2(10,-43),Vector2(10,-39),Vector2(6,-39),Vector2(6,-34),Vector2(10,-34),Vector2(10,-25),Vector2(16,-25)])
static var _core_breach := PackedVector2Array([Vector2(34,-38),Vector2(43,-38),Vector2(43,-19),Vector2(39,-19),Vector2(39,-15),Vector2(34,-15),Vector2(34,-23),Vector2(30,-23),Vector2(30,-32),Vector2(34,-32)])

static func stage(hp: float, maximum: float) -> int:
	if not is_finite(hp) or not is_finite(maximum) or maximum <= 0.0:
		return Stage.INTACT
	var ratio := clampf(hp / maximum, 0.0, 1.0)
	if ratio >= 0.85: return Stage.INTACT
	if ratio >= 0.50: return Stage.WORN
	if ratio >= 0.25: return Stage.DAMAGED
	return Stage.CRITICAL

static func monitor_scan_y(seconds: float) -> float:
	return -59.0 + floorf(fposmod(seconds * 7.0, 11.0)) if is_finite(seconds) else -59.0

static func wall(canvas: CanvasItem, hp: float, maximum: float, tier: int, reinforced: bool) -> void:
	var damage := stage(hp, maximum)
	if damage == Stage.INTACT: return
	if tier >= 3:
		_armor(canvas, damage)
	else:
		_concrete(canvas, damage, reinforced or tier >= 2)

static func _concrete(canvas: CanvasItem, damage: int, steel_visible: bool) -> void:
	canvas.draw_polyline(_concrete_main, INK, 2)
	canvas.draw_line(Vector2(12,-77),Vector2(0,-62),CONCRETE_EDGE,1)
	canvas.draw_rect(Rect2(10,-81,4,2),CONCRETE_DARK)
	if damage < Stage.DAMAGED: return
	canvas.draw_polyline(_concrete_branch, INK, 2)
	canvas.draw_colored_polygon(_concrete_notch, CONCRETE_DARK)
	canvas.draw_line(Vector2(10,-44),Vector2(5,-40),CONCRETE_EDGE,1)
	canvas.draw_line(Vector2(8,-35),Vector2(8,-28),Color("626b5a"),1)
	if steel_visible:
		canvas.draw_rect(Rect2(11,-42,2,14),INK)
		canvas.draw_rect(Rect2(11,-41,1,12),EXPOSED_STEEL)
	if damage < Stage.CRITICAL: return
	canvas.draw_colored_polygon(_concrete_critical, INK)
	canvas.draw_rect(Rect2(-14,-75,4,2),CONCRETE_EDGE)
	canvas.draw_rect(Rect2(-10,-71,3,2),CONCRETE_EDGE)
	canvas.draw_rect(Rect2(-14,-58,4,2),CONCRETE_DARK)
	canvas.draw_rect(Rect2(9,-26,6,6),INK)
	canvas.draw_rect(Rect2(10,-27,4,1),CONCRETE_EDGE)
	canvas.draw_line(Vector2(-5,-42),Vector2(-9,-28),INK,2)
	if steel_visible:
		canvas.draw_rect(Rect2(-12,-72,2,14),EXPOSED_STEEL)
		canvas.draw_rect(Rect2(-12,-66,6,2),STEEL_DARK)
		canvas.draw_rect(Rect2(-12,-71,1,11),STEEL_EDGE)

static func _armor(canvas: CanvasItem, damage: int) -> void:
	# Short scraped folds stop at plate seams, unlike a concrete fracture.
	canvas.draw_line(Vector2(-10,-66),Vector2(-4,-63),STEEL_DARK,2)
	canvas.draw_line(Vector2(-10,-67),Vector2(-4,-64),STEEL_EDGE,1)
	canvas.draw_line(Vector2(3,-30),Vector2(8,-28),STEEL_DARK,2)
	canvas.draw_rect(Rect2(10,-74,4,2),RUST)
	if damage < Stage.DAMAGED: return
	canvas.draw_rect(Rect2(11,-75,4,5),INK)
	canvas.draw_rect(Rect2(10,-76,3,1),STEEL_EDGE)
	canvas.draw_rect(Rect2(9,-73,2,2),RUST)
	canvas.draw_line(Vector2(-11,-53),Vector2(2,-53),INK,2)
	canvas.draw_line(Vector2(-10,-55),Vector2(1,-55),STEEL_EDGE,1)
	canvas.draw_rect(Rect2(12,-37,4,9),STEEL_DARK)
	canvas.draw_rect(Rect2(11,-37,1,8),STEEL_EDGE)
	if damage < Stage.CRITICAL: return
	canvas.draw_colored_polygon(_armor_tear, INK)
	canvas.draw_rect(Rect2(6,-39,4,1),STEEL_EDGE)
	canvas.draw_rect(Rect2(9,-34,1,8),RUST)
	canvas.draw_rect(Rect2(12,-40,2,13),EXPOSED_STEEL)
	canvas.draw_rect(Rect2(12,-39,1,10),STEEL_EDGE)
	canvas.draw_rect(Rect2(-16,-68,5,12),STEEL_DARK)
	canvas.draw_rect(Rect2(-16,-69,5,1),STEEL_EDGE)
	canvas.draw_rect(Rect2(-16,-67,2,9),INK)
	canvas.draw_rect(Rect2(-14,-59,3,2),RUST)

static func core(canvas: CanvasItem, hp: float, maximum: float) -> void:
	var damage := stage(hp, maximum)
	if damage == Stage.INTACT: return
	# Cabinet wear follows actual side vents and cast panel edges; the original
	# furnace, meters and monitor remain readable at the native 90px body size.
	canvas.draw_line(Vector2(19,-84),Vector2(28,-82),STEEL_DARK,2)
	canvas.draw_line(Vector2(19,-85),Vector2(27,-83),STEEL_EDGE,1)
	canvas.draw_rect(Rect2(34,-68,5,2),RUST)
	if damage < Stage.DAMAGED: return
	canvas.draw_rect(Rect2(32,-77,11,4),INK)
	canvas.draw_rect(Rect2(31,-78,10,1),STEEL_EDGE)
	canvas.draw_rect(Rect2(35,-74,6,2),RUST)
	canvas.draw_line(Vector2(-37,-47),Vector2(-35,-31),STEEL_DARK,3)
	canvas.draw_line(Vector2(-38,-47),Vector2(-36,-32),STEEL_EDGE,1)
	canvas.draw_rect(Rect2(-38,-30,5,2),RUST)
	if damage < Stage.CRITICAL: return
	canvas.draw_colored_polygon(_core_breach, INK)
	canvas.draw_line(Vector2(33,-35),Vector2(40,-33),STEEL_EDGE,1)
	canvas.draw_rect(Rect2(35,-32,2,13),EXPOSED_STEEL)
	canvas.draw_rect(Rect2(35,-31,1,10),STEEL_EDGE)
	canvas.draw_line(Vector2(38,-32),Vector2(38,-27),RUST,2)
	canvas.draw_line(Vector2(38,-27),Vector2(32,-25),RUST,2)
	canvas.draw_rect(Rect2(-37,-70,7,4),INK)
	canvas.draw_rect(Rect2(-37,-71,7,1),STEEL_EDGE)
