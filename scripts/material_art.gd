class_name MaterialArt
extends RefCounted
## Shared small material silhouettes for world piles, supply labels and carried loads.

static func draw_material(node: CanvasItem, kind: String, origin: Vector2, size: float = 1.0) -> void:
	if ItemCatalog.draw_carried(node,kind,origin,size): return
	if kind in ["jaw_trap", "blast_trap", "sentry_kit"]:
		# Small steel kit silhouettes are shared by cargo, world drops and the HUD.
		node.draw_rect(Rect2(origin+Vector2(-13,-8)*size,Vector2(26,19)*size),Color("162020"))
		node.draw_rect(Rect2(origin+Vector2(-11,-6)*size,Vector2(22,15)*size),Color("626b58"))
		node.draw_line(origin+Vector2(-10,-5)*size,origin+Vector2(9,-5)*size,Color("c0b997"),maxf(1,size))
		if kind == "jaw_trap":
			for x in [-9,-3,3,9]:
				node.draw_colored_polygon(_points([Vector2(x-2,-6),Vector2(x,-13),Vector2(x+2,-6)],origin,size),Color("c1c3a5"))
			node.draw_rect(Rect2(origin+Vector2(-7,1)*size,Vector2(14,3)*size),Color("9b8060"))
		elif kind == "blast_trap":
			node.draw_rect(Rect2(origin+Vector2(-7,-9)*size,Vector2(14,6)*size),Color("8c6550"))
			node.draw_rect(Rect2(origin+Vector2(-3,-8)*size,Vector2(6,3)*size),Color("eda765"))
			for x in [-8,0,8]:
				node.draw_line(origin+Vector2(x,2)*size,origin+Vector2(x+4,6)*size,Color("d9b163"),maxf(1,size*2))
		else:
			node.draw_rect(Rect2(origin+Vector2(-7,-10)*size,Vector2(13,7)*size),Color("90a18a"))
			node.draw_line(origin+Vector2(4,-7)*size,origin+Vector2(15,-7)*size,Color("c7c6a5"),maxf(1,size*3))
			node.draw_line(origin+Vector2(0,-2)*size,origin+Vector2(-8,8)*size,Color("b4a784"),maxf(1,size*2))
			node.draw_line(origin+Vector2(0,-2)*size,origin+Vector2(8,8)*size,Color("b4a784"),maxf(1,size*2))
	elif kind == "glass":
		for pane in 2:
			var at := origin+Vector2(-9+pane*3,-10-pane*2)*size
			node.draw_rect(Rect2(at,Vector2(16,23)*size),Color("122932"))
			node.draw_rect(Rect2(at+Vector2.ONE*size,Vector2(14,21)*size),Color(0.36,0.69,0.77,0.71))
			node.draw_rect(Rect2(at+Vector2.ONE*size,Vector2(14,21)*size),Color("a8e1df"),false,maxf(1,size))
			node.draw_line(at+Vector2(3,12)*size,at+Vector2(11,4)*size,Color("e1fff3"),maxf(1,size))
			node.draw_line(at+Vector2(4,17)*size,at+Vector2(9,12)*size,Color("9fe0df"),maxf(1,size))
		node.draw_rect(Rect2(origin+Vector2(-10,9)*size,Vector2(24,3)*size),Color("9b997e"))
	elif kind == "limestone":
		var outline := _points([Vector2(-12,4),Vector2(-10,-3),Vector2(-4,-6),Vector2(1,-11),Vector2(10,-8),Vector2(13,0),Vector2(10,11),Vector2(-5,13)],origin,size)
		node.draw_colored_polygon(outline,Color("273136"))
		node.draw_colored_polygon(_points([Vector2(-10,4),Vector2(-8,-1),Vector2(-2,-3),Vector2(3,2),Vector2(1,9),Vector2(-5,10)],origin,size),Color("adaf9a"))
		node.draw_colored_polygon(_points([Vector2(-2,-5),Vector2(2,-9),Vector2(9,-6),Vector2(10,0),Vector2(4,5),Vector2(-2,1)],origin,size),Color("e3dcc2"))
		node.draw_colored_polygon(_points([Vector2(4,6),Vector2(9,2),Vector2(11,4),Vector2(8,10),Vector2(3,11)],origin,size),Color("c4c6af"))
		node.draw_line(origin+Vector2(2,-7)*size,origin+Vector2(7,-5)*size,Color("fff2d4"),maxf(1,size*2))
		node.draw_line(origin+Vector2(-8,2)*size,origin+Vector2(-3,0)*size,Color("d8d4ba"),maxf(1,size))
	elif kind == "tungsten":
		node.draw_colored_polygon(_points([Vector2(-13,5),Vector2(-10,-6),Vector2(-4,-11),Vector2(4,-10),Vector2(12,-2),Vector2(13,7),Vector2(4,12),Vector2(-8,11)],origin,size),Color("151f2b"))
		node.draw_colored_polygon(_points([Vector2(-10,3),Vector2(-8,-5),Vector2(-3,-8),Vector2(5,-6),Vector2(7,2),Vector2(1,9),Vector2(-7,8)],origin,size),Color("55586c"))
		node.draw_colored_polygon(_points([Vector2(5,-6),Vector2(10,-1),Vector2(11,6),Vector2(4,10),Vector2(1,9),Vector2(7,2)],origin,size),Color("343d50"))
		for vein in [[Vector2(-8,2),Vector2(-4,-4),Vector2(1,-6)],[Vector2(-3,7),Vector2(1,2),Vector2(6,0)],[Vector2(5,8),Vector2(8,4)]]:
			node.draw_polyline(_points(vein,origin,size),Color("a49cbc"),maxf(1,2*size))
		node.draw_rect(Rect2(origin+Vector2(-3,-5)*size,Vector2(3,2)*size),Color("d9d5df"))
		node.draw_rect(Rect2(origin+Vector2(3,1)*size,Vector2(2,2)*size),Color("cebcdb"))
	elif kind == "alloy":
		for plate in 3:
			var at := origin + Vector2(0,7-plate*6)*size
			node.draw_colored_polygon(_points([Vector2(-13,-3),Vector2(4,-7),Vector2(13,-4),Vector2(13,2),Vector2(-4,6),Vector2(-13,3)],at,size),Color("172a36"))
			node.draw_colored_polygon(_points([Vector2(-11,-2),Vector2(4,-5),Vector2(11,-3),Vector2(-4,1)],at,size),Color("9cbac7"))
			node.draw_colored_polygon(_points([Vector2(-11,-1),Vector2(-4,2),Vector2(11,-2),Vector2(11,1),Vector2(-4,4),Vector2(-11,2)],at,size),Color("536e83"))
			node.draw_line(at+Vector2(-3,0)*size,at+Vector2(8,-2)*size,Color("d2dbd4"),maxf(1,size))
			node.draw_rect(Rect2(at+Vector2(-9,0)*size,Vector2(3,2)*size),Color("ceab70"))

static func _points(points: Array, origin: Vector2, size: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in points:
		result.append(origin+point*size)
	return result
