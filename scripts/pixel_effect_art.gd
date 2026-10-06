extends RefCounted
## Small authored pixel silhouettes shared by combat dust and machine exhaust.
## Drawing only: owners retain their lifetime, movement and particle budgets.
const PUFFS := [
	[Vector2(-6,-2),Vector2(-4,-2),Vector2(-4,-4),Vector2(-1,-4),Vector2(-1,-5),Vector2(2,-5),Vector2(2,-3),Vector2(5,-3),Vector2(5,-1),Vector2(6,-1),Vector2(6,2),Vector2(4,2),Vector2(4,4),Vector2(0,4),Vector2(0,5),Vector2(-3,5),Vector2(-3,3),Vector2(-5,3),Vector2(-5,1),Vector2(-6,1)],
	[Vector2(-6,-1),Vector2(-5,-1),Vector2(-5,-3),Vector2(-2,-3),Vector2(-2,-5),Vector2(1,-5),Vector2(1,-4),Vector2(4,-4),Vector2(4,-2),Vector2(6,-2),Vector2(6,1),Vector2(5,1),Vector2(5,3),Vector2(2,3),Vector2(2,5),Vector2(-1,5),Vector2(-1,4),Vector2(-4,4),Vector2(-4,2),Vector2(-6,2)],
	[Vector2(-6,-3),Vector2(-3,-3),Vector2(-3,-5),Vector2(0,-5),Vector2(0,-4),Vector2(3,-4),Vector2(3,-2),Vector2(5,-2),Vector2(5,0),Vector2(6,0),Vector2(6,3),Vector2(3,3),Vector2(3,5),Vector2(0,5),Vector2(0,4),Vector2(-3,4),Vector2(-3,2),Vector2(-5,2),Vector2(-5,0),Vector2(-6,0)],
]
const SHOCK_RADIUS := [.91,1.03,.98,1.11,.88,1.02,.95,1.07,.90,1.04,.97,1.09]

static func puff(node: CanvasItem, center: Vector2, radius: float, color: Color, variant: int = 0, detail: bool = true) -> void:
	if radius <= 0.0 or color.a <= 0.0: return
	var point := center.round()
	if radius < 2.5:
		node.draw_rect(Rect2(point-Vector2.ONE,Vector2(2,2)),color)
		return
	var shape := PackedVector2Array()
	for corner: Vector2 in PUFFS[posmod(variant,PUFFS.size())]:
		var vertex := (point+corner*(radius/6.0)).round()
		if shape.is_empty() or shape[-1] != vertex: shape.append(vertex)
	node.draw_colored_polygon(shape,color)
	if not detail: return
	# Sparse opaque-looking facets within a transparent silhouette, aligned to
	# the same pixel grid as armor and stone. No circular soft brush overlays.
	var fleck := Vector2(maxf(1.0,roundf(radius*.58)),maxf(1.0,roundf(radius*.22)))
	node.draw_rect(Rect2((point+Vector2(-radius*.42,-radius*.47)).round(),fleck),Color(color.lightened(.12),color.a*.32))
	node.draw_rect(Rect2((point+Vector2(radius*.06,radius*.28)).round(),fleck),Color(color.darkened(.22),color.a*.30))

static func glow(node: CanvasItem, center: Vector2, radius: float, color: Color, variant: int = 0) -> void:
	# Several smaller patches keep an explosion's halo granular at world scale;
	# stretching one tiny silhouette would create conspicuous giant pixel blocks.
	var offsets: Array[Vector2] = [Vector2(-.30,-.12),Vector2(.13,-.24),Vector2(.25,.19)]
	for index in offsets.size():
		puff(node,center+offsets[index]*radius,radius*.38,Color(color,color.a*.70),variant+index,false)
	puff(node,center,radius*.28,Color(color,color.a*1.10),variant+1,false)

static func shockwave(node: CanvasItem, center: Vector2, radius: float, color: Color, variant: int = 0) -> void:
	if radius <= 0.0 or color.a <= 0.0: return
	# Broken, uneven pressure fronts keep the impact readable without a smooth
	# UI-like circular outline floating over the world.
	for index in 6:
		var angle := float(index)*TAU/6.0+float(posmod(variant,3))*.19
		var first: Vector2 = center+Vector2.from_angle(angle)*radius*SHOCK_RADIUS[index*2]
		var middle: Vector2 = center+Vector2.from_angle(angle+.21)*radius*SHOCK_RADIUS[index*2+1]
		var last: Vector2 = center+Vector2.from_angle(angle+.42)*radius*SHOCK_RADIUS[(index*2+2)%SHOCK_RADIUS.size()]
		node.draw_polyline(PackedVector2Array([first.round(),middle.round(),last.round()]),color,1.0,false)
