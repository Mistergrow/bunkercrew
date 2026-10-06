class_name Art
extends RefCounted

const INK = Color("111c24")
const LIGHT = Color("e8dfc9")
const MUTED = Color("83999e")
const AMBER = Color("ecb75c")
const CYAN = Color("72cfcb")
const RED = Color("f16e5c")

static func text(node: CanvasItem, pos: Vector2, value: String, size: int = 14, color: Color = LIGHT) -> void:
	value=LocaleText.text(value)
	node.draw_string(UiArt.FONT, pos.round(), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

static func bar(node: CanvasItem, rect: Rect2, ratio: float, color: Color) -> void:
	node.draw_rect(rect, INK)
	node.draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(ratio, 0, 1), rect.size.y)), color)

static func bolts(node: CanvasItem, rect: Rect2) -> void:
	for p in [rect.position + Vector2(5, 5), rect.position + Vector2(rect.size.x - 5, 5), rect.end - Vector2(5, 5), rect.position + Vector2(5, rect.size.y - 5)]:
		var at: Vector2 = p.round()-Vector2(2,2)
		node.draw_rect(Rect2(at,Vector2(4,4)),INK)
		node.draw_rect(Rect2(at+Vector2.ONE,Vector2(2,2)),MUTED)
		node.draw_rect(Rect2(at+Vector2.ONE,Vector2.ONE),LIGHT)
