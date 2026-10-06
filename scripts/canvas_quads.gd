extends RefCounted
## Four-vertex primitives batch with the renderer's thick lines. Separate
## polygon meshes and alternating RECT commands break those batches.
static func rect(canvas: CanvasItem, bounds: Rect2, color: Color) -> void:
	canvas.draw_primitive(PackedVector2Array([bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]),PackedColorArray([color]),PackedVector2Array())

static func patch(canvas: CanvasItem, transform: Transform2D, at: Vector2, size: Vector2, color: Color, snap: bool = true) -> void:
	var vertices := PackedVector2Array()
	for point in [at,at+Vector2(size.x,0),at+size,at+Vector2(0,size.y)]:
		var mapped: Vector2 = transform*point
		vertices.append(mapped.round() if snap else mapped)
	canvas.draw_primitive(vertices,PackedColorArray([color]),PackedVector2Array())
