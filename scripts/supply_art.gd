class_name SupplyArt
extends RefCounted
## One textured chest shared by every resource. Badges reuse the carried-item
## artwork, so storage and cargo remain recognizable at the same pixel scale.

const SOURCE := "res://assets/supplies/industrial_crate.png"
const REGION := Rect2(296, 192, 969, 622)
const BOUNDS := Rect2(-29, -38, 58, 38)
static var _crate: AtlasTexture

static func texture() -> AtlasTexture:
	if _crate == null:
		_crate = AtlasTexture.new()
		_crate.atlas = load(SOURCE)
		_crate.region = REGION
		_crate.filter_clip = true
	return _crate

static func draw(canvas: CanvasItem, kind: String, amount: int) -> void:
	var tint := Color.WHITE if amount > 0 else Color(0.70, 0.73, 0.69)
	canvas.draw_rect(Rect2(-28, -2, 56, 3), Color(0.015, 0.02, 0.015, 0.30))
	canvas.draw_texture_rect(texture(), BOUNDS, false, tint)
	# A small physical material plate sits between the straps. It has no frame
	# ornaments or separate icon vocabulary; count and state stay in the label.
	canvas.draw_rect(Rect2(-11, -25, 16, 15), Color(0.10, 0.13, 0.12, 0.82))
	canvas.draw_line(Vector2(-11, -25), Vector2(4, -25), Color("756e54"), 1.0)
	UiArt.material(canvas, kind, Vector2(-11, -24), 15.0)
