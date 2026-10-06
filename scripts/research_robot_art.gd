extends RefCounted
## SAN-1's existing olive chassis, amber sensor and medical cross, as a UI glyph.
static func draw(canvas: CanvasItem, at: Vector2, size: float, tint: Color = Color.WHITE, variant: int = 0) -> void:
	var unit := size / 40.0
	var base := at.round()
	var shadow := Color("111a17") * tint
	var metal := Color("647463") * tint
	var light := Color("a0ab8b") * tint
	var amber := Color("e4ae55") * tint
	var head_y := float(variant % 2)
	for shape in [Rect2(4,30,31,8), Rect2(8,17,23,17), Rect2(10,2+head_y,18,13), Rect2(15,13+head_y,8,5)]:
		canvas.draw_rect(Rect2(base + shape.position * unit, shape.size * unit), shadow)
	for shape in [Rect2(6,32,27,4), Rect2(10,19,19,12), Rect2(12,4+head_y,14,8)]:
		canvas.draw_rect(Rect2(base + shape.position * unit, shape.size * unit), metal)
	canvas.draw_rect(Rect2(base + Vector2(13,5+head_y)*unit, Vector2(12,2)*unit), light)
	canvas.draw_rect(Rect2(base + Vector2(15,9+head_y)*unit, Vector2(10,2)*unit), amber)
	for x in [8,14,20,26,31]: canvas.draw_line(base+Vector2(x,32)*unit, base+Vector2(x-1,36)*unit, light, unit)
	canvas.draw_rect(Rect2(base+Vector2(17,21)*unit, Vector2(4,8)*unit), Color("d0d2b9")*tint)
	canvas.draw_rect(Rect2(base+Vector2(15,23)*unit, Vector2(8,4)*unit), Color("d0d2b9")*tint)
	var elbow := Vector2(34,18 - (variant % 3)*3)
	var hand := Vector2(36 - (variant % 2)*5,12 - (variant % 3)*2)
	canvas.draw_polyline(PackedVector2Array([base+Vector2(29,24)*unit,base+elbow*unit,base+hand*unit]), shadow, 4*unit)
	canvas.draw_polyline(PackedVector2Array([base+Vector2(29,24)*unit,base+elbow*unit,base+hand*unit]), light, 2*unit)
	canvas.draw_rect(Rect2(base+(hand-Vector2(2,2))*unit,Vector2(4,4)*unit), amber)
