extends RefCounted
## Existing painted machine surfaces keep defensive structures in the same
## material family as the furnace, gun mount and bunker equipment.
const Surface := preload("res://scripts/station_surface_art.gd")
const CONSOLE := preload("res://assets/props/console.tres")
const FLAK_CONSOLE_BOUNDS := Rect2(-26,-59,53,51)
const INK := Color("182221")
const STEEL := Color("596254")
const EDGE := Color("a9aa8d")
static var _glass: Texture2D

static func beam(canvas: Node2D, from: Vector2, to: Vector2, width: float, variation: int=0, broken: bool=false) -> void:
	if from.distance_squared_to(to)<1.0: return
	var normal := (to-from).normalized().orthogonal()*width*.5
	canvas.draw_line(from.round(),to.round(),INK,width+2)
	var vertices := PackedVector2Array([(from+normal).round(),(to+normal).round(),(to-normal).round(),(from-normal).round()])
	Surface.polygon(canvas,vertices,Color("39413b") if broken else STEEL,variation)

static func rail(canvas: Node2D, path: PackedVector2Array, width: float, variation: int, broken: bool=false) -> void:
	if path.size()<2: return
	# A closed outline forms a ring with a hole; draw its individual braces
	# instead of passing a self-intersecting ring to polygon triangulation.
	if path[0].is_equal_approx(path[-1]):
		for index in path.size()-1:
			beam(canvas,path[index],path[index+1],width,variation,broken)
		return
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for index in path.size():
		var from := path[maxi(0,index-1)]
		var to := path[mini(path.size()-1,index+1)]
		var normal := (to-from).normalized().orthogonal()*width*.5
		left.append(path[index]+normal)
		right.append(path[index]-normal)
	right.reverse()
	left.append_array(right)
	canvas.draw_polyline(path,INK,width+2)
	Surface.polygon(canvas,left,Color("39413b") if broken else STEEL,variation)

static func bolt(canvas: Node2D, at: Vector2) -> void:
	canvas.draw_rect(Rect2(at.round()-Vector2.ONE,Vector2(3,3)),INK)
	canvas.draw_rect(Rect2(at.round()-Vector2.ONE,Vector2.ONE),EDGE)
	canvas.draw_rect(Rect2(at.round(),Vector2.ONE),Color("797b64"))

static func _glass_texture() -> Texture2D:
	if _glass==null:
		var pixels := Image.create(96,48,false,Image.FORMAT_RGBA8)
		for x in 96:
			for y in 48:
				var grain := posmod(x*73+y*151,211)
				var tint := Color(.50,.65,.62,.10+float(grain%5)*.009)
				if grain%31==0: tint=Color(.76,.83,.74,.18)
				if posmod(x+y*2,43)<2 and y%7<3: tint=Color(.79,.87,.79,.25)
				pixels.set_pixel(x,y,tint)
		_glass=ImageTexture.create_from_image(pixels)
	return _glass

static func glass(canvas: Node2D, shape: PackedVector2Array, flash: float=0.0, rear: bool=false) -> void:
	if shape.size()<3: return
	var bounds := Rect2(shape[0],Vector2.ZERO)
	for point in shape: bounds=bounds.expand(point)
	var uv := PackedVector2Array()
	for point in shape:
		uv.append((point-bounds.position)/Vector2(maxf(bounds.size.x,1),maxf(bounds.size.y,1)))
	var tint := Color(1,1,1,.64 if rear else 1.0)
	if flash>0: tint=Color(1.2,1.2,1.1,1.7)
	canvas.draw_polygon(shape,PackedColorArray([tint]),uv,_glass_texture())

static func dome_console(canvas: Node2D, site: Vector2, frame_built: bool, built: bool, damaged: bool) -> void:
	# Raised instrument cabinet and narrow service conduit leave the walking
	# silhouette clear. The floor interaction anchor remains independent.
	var plate := Rect2(site+Vector2(-32,-136),Vector2(65,62))
	canvas.draw_rect(plate.grow(2),Color(0,0,0,.26))
	Surface.panel(canvas,plate,Color("38443c"),3)
	canvas.draw_texture_rect(CONSOLE,Rect2(site+Vector2(-30,-134),Vector2(60,56)),false)
	beam(canvas,site+Vector2(19,-76),site+Vector2(19,-36),4,2)
	beam(canvas,site+Vector2(19,-36),site+Vector2(7,-36),4,2)
	Surface.panel(canvas,Rect2(site+Vector2(-9,-47),Vector2(22,22)),Color("3e493e"),1)
	canvas.draw_rect(Rect2(site+Vector2(-4,-41),Vector2(12,8)),INK)
	var status := Color("c59b59") if not built else Color("a9b68a")
	if damaged: status=Color("c27a51")
	canvas.draw_rect(Rect2(site+Vector2(-2,-39),Vector2(8,3)),status)
	# A small canopy diagram replaces a permanent floating machine label.
	var display := site+Vector2(-18,-108)
	canvas.draw_rect(Rect2(display,Vector2(27,17)),Color("172a2a"))
	var diagram := PackedVector2Array([Vector2(3,13),Vector2(3,9),Vector2(6,6),Vector2(9,4),Vector2(14,3),Vector2(19,5),Vector2(23,9),Vector2(23,13)])
	for index in diagram.size(): diagram[index]+=display
	canvas.draw_polyline(diagram,Color("b1b89b") if frame_built else Color("6b8072"),1)
	if built:
		canvas.draw_line(display+Vector2(7,10),display+Vector2(11,7),Color("72998d"),1)
		canvas.draw_line(display+Vector2(15,11),display+Vector2(19,8),Color("72998d"),1)
	canvas.draw_rect(Rect2(site+Vector2(15,-95),Vector2(3,3)),status)

static func flak_console(canvas: Node2D, tier: int, built: bool, operational: bool) -> void:
	Surface.panel(canvas,Rect2(-25,-9,50,8),Color("414c43"),4)
	canvas.draw_texture_rect(CONSOLE,FLAK_CONSOLE_BOUNDS,false)
	Surface.face(canvas,Rect2(-15,-26,29,13),Color("344038"),1)
	canvas.draw_rect(Rect2(-12,-24,21,9),Color("172525"))
	# Engraved twin barrels and a traverse mark identify the AA station even
	# before the actual tower exists, without adding world-space text.
	for y in [-20,-17]:
		canvas.draw_line(Vector2(-9,y),Vector2(3,y-3),Color("b7b79a"),1)
	canvas.draw_line(Vector2(-4,-17),Vector2(-4,-14),Color("929b81"),1)
	for index in 3:
		var tint := Color("afbc8a") if built and operational else Color("b8894f")
		if index>=tier: tint=Color("3b4536")
		canvas.draw_rect(Rect2(13,-31+index*5,3,3),INK)
		canvas.draw_rect(Rect2(13,-31+index*5,2,2),tint)
