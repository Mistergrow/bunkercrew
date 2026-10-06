extends RefCounted
## Four authored phases per effect, sampled from the original RGBA atlas.
const ATLAS := preload("res://assets/environments/water_effects.png")
const CROPS := [Rect2(0,132,384,198),Rect2(0,84,384,246),Rect2(0,110,384,184)]

static func draw_effect(canvas: Node2D,rect: Rect2,row: int,progress: float,tint: Color) -> void:
	var frame := mini(3,floori(clampf(progress,0.0,.9999)*4.0))
	var source: Rect2 = CROPS[row]
	source.position += Vector2(frame*384.0,row*(1024.0/3.0))
	canvas.draw_texture_rect_region(ATLAS,Rect2(rect.position.round(),rect.size.round()),source,tint)
