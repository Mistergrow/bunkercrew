class_name ScenarioBunkerArt
extends RefCounted
## Cutaway construction pieces. Backing, ribs, utilities and lights are drawn
## separately so the same assembly can serve a full room or a menu preview.
const FALLBACK := preload("res://assets/bunker_wall.png")
static var _walls: Dictionary = {}

static func wall_texture(build_type: String) -> Texture2D:
	if _walls.has(build_type):
		return _walls[build_type]
	var path := "res://assets/environments/wall_%s.png" % build_type
	if ResourceLoader.exists(path):
		var texture: Texture2D = load(path)
		_walls[build_type] = texture
		return texture
	return FALLBACK

static func draw_room(node: CanvasItem, rect: Rect2, build_type: String = "bastion", depth: int = 0, elapsed: float = 0.0, rear_shift: Vector2 = Vector2.ZERO, frame: bool = true, passages: Array[Rect2] = []) -> void:
	var rear := rect.grow_individual(-13,-17,-13,-7)
	node.draw_rect(rect,Color("0f171b"))
	# Only the recessed backing and attached utility layer move. Cut edges stay
	# attached to physical floors and avoid gaps during camera parallax.
	var inset := rear.grow(8)
	node.draw_texture_rect(wall_texture(build_type),Rect2(inset.position-rear_shift.round()*0.5,inset.size),false,Color("a3a59b"))
	node.draw_rect(Rect2(rear.position,Vector2(rear.size.x,17)),Color(0.035,0.05,0.055,0.40))
	node.draw_rect(Rect2(rear.position.x,rear.end.y-26,rear.size.x,26),Color(0.03,0.04,0.04,0.26))
	var pipe_y := rear.position.y+26
	var shift := rear_shift.round()
	for utility in 2:
		var y := pipe_y+utility*11-shift.y
		node.draw_line(Vector2(rear.position.x+3,y),Vector2(rear.end.x-3,y),Color("151d1e"),6 if utility==0 else 3)
		node.draw_line(Vector2(rear.position.x+3,y-1),Vector2(rear.end.x-3,y-1),Color("706954") if utility==0 else Color("4c574f"),2)
		for x in range(int(rear.position.x)+17,int(rear.end.x)-7,57):
			node.draw_rect(Rect2(x-shift.x,y-3,4,8),Color("8a8060"))
	var colors := {"bastion":Color("72776b"),"workshop":Color("5b6868"),"stronghold":Color("757469")}
	var material: Color = colors.get(build_type,colors.bastion)
	# Recessed load-bearing piers are distinct from the darker foreground frame.
	for fraction in [0.33,0.69]:
		var x := floorf(rect.position.x+rect.size.x*fraction-shift.x)
		var pier := Rect2(x,rear.position.y+9,17,rear.size.y-12)
		node.draw_rect(pier.grow(3),Color(0.035,0.055,0.055,0.38))
		node.draw_rect(pier,material.darkened(0.35))
		node.draw_rect(Rect2(x,rear.position.y+9,3,rear.size.y-12),material)
		if build_type == "workshop":
			for y in range(int(pier.position.y)+9,int(pier.end.y)-4,29):
				node.draw_rect(Rect2(x+9,y,3,3),Color("b0ac90"))
		else:
			node.draw_line(Vector2(x+15,rear.position.y+15),Vector2(x+39,rear.position.y+15),material.darkened(0.14),8)
			for chip in 6:
				node.draw_rect(Rect2(x+4+posmod(chip*7,11),rear.position.y+28+chip*21,3,2),material.darkened(0.17))
	for fraction in [0.17,0.54,0.85]:
		var lamp := Vector2(roundf(rect.position.x+rect.size.x*fraction-shift.x),rear.position.y+19-shift.y)
		_draw_lamp(node,lamp,rect.end.y-8,elapsed,depth)
	if frame:
		draw_frame(node,rect,build_type,depth,passages)

static func draw_frame(node: CanvasItem,rect: Rect2,build_type: String,depth: int = 0,passages: Array[Rect2] = []) -> void:
	var top := rect.position.y
	var floor_rect := rect.end.y
	var left := rect.position.x
	var right := rect.end.x
	draw_slab(node,Rect2(left,top,rect.size.x,17),passages)
	draw_slab(node,Rect2(left,floor_rect,rect.size.x,18),passages)
	node.draw_rect(Rect2(left+11,top+17,rect.size.x-22,7),Color(0.02,0.04,0.04,0.58))
	node.draw_rect(Rect2(left+9,floor_rect-8,rect.size.x-18,8),Color(0.015,0.025,0.025,0.50))
	for x in [left,right-25]:
		# At surface level the lower opening is a destructible defense gate.
		var height := rect.size.y-17 if depth>0 else rect.size.y-108
		BunkerArchitecture.concrete(node,Rect2(x,top+17,25,height))
		node.draw_rect(Rect2(x+21,top+19,4,height-2),Color("273331"))
		if build_type == "workshop":
			node.draw_rect(Rect2(x+5,top+20,13,height-4),Color("354447"))
			node.draw_line(Vector2(x+6,top+21),Vector2(x+6,top+height+12),Color("8b9386"),2)
			for y in range(int(top)+28,int(top+height)+9,23):
				node.draw_rect(Rect2(x+12,y,3,3),Color("b1a98b"))
		elif build_type == "stronghold":
			for segment in range(0,int(height),28):
				node.draw_rect(Rect2(x+2,top+20+segment,20,2),Color("4c5149"))
		# The inner chamfer creates a visible 12px reveal, not a flat border.
		var side := 1.0 if x==left else -1.0
		var anchor: float = x+25 if x==left else x
		node.draw_colored_polygon(PackedVector2Array([Vector2(anchor,top+17),Vector2(anchor+side*18,top+17),Vector2(anchor,top+35)]),Color("85897b"))
	if build_type == "workshop":
		node.draw_rect(Rect2(left+25,top+3,rect.size.x-50,10),Color("39484a"))
		node.draw_line(Vector2(left+28,top+4),Vector2(right-28,top+4),Color("949b8a"),2)
		for x in range(int(left)+35,int(right)-30,32):
			node.draw_rect(Rect2(x,top+8,3,3),Color("baad8e"))
	elif build_type == "stronghold":
		for x in range(int(left)+12,int(right)-12,48):
			node.draw_line(Vector2(x,top+3),Vector2(x+8,top+13),Color("49544d"),2)
	if depth>0:
		node.draw_line(Vector2(left+25,floor_rect-3),Vector2(right-25,floor_rect-3),Color("a29b7b"),2)

static func draw_slab(node: CanvasItem,rect: Rect2,passages: Array[Rect2]) -> void:
	var holes: Array[Rect2]=[]
	for hole in passages:
		if absf(hole.position.y-rect.position.y)<1: holes.append(hole)
	holes.sort_custom(func(a: Rect2,b: Rect2): return a.position.x<b.position.x)
	var cursor:=rect.position.x
	for hole in holes:
		if hole.position.x>cursor:
			BunkerArchitecture.concrete(node,Rect2(cursor,rect.position.y,hole.position.x-cursor,rect.size.y))
		cursor=maxf(cursor,hole.end.x)
	if cursor<rect.end.x:
		BunkerArchitecture.concrete(node,Rect2(cursor,rect.position.y,rect.end.x-cursor,rect.size.y))

static func _draw_lamp(node: CanvasItem,point: Vector2,floor_y: float,elapsed: float,seed_value: int) -> void:
	var pulse := 0.96+sin(elapsed*2.1+point.x+seed_value)*0.04
	var lower := minf(floor_y,point.y+151)
	node.draw_colored_polygon(PackedVector2Array([point+Vector2(-8,7),point+Vector2(8,7),Vector2(point.x+66,lower),Vector2(point.x-66,lower)]),Color(1.0,0.63,0.25,0.032*pulse))
	for radius in range(4,0,-1):
		node.draw_circle(point+Vector2(0,17),radius*20,Color(1.0,0.64,0.29,0.016*pulse))
	node.draw_line(point-Vector2(0,14),point,Color("242a25"),3)
	node.draw_rect(Rect2(point+Vector2(-17,-3),Vector2(34,9)),Color("222b2a"))
	node.draw_rect(Rect2(point+Vector2(-15,-2),Vector2(30,3)),Color("958a68"))
	node.draw_rect(Rect2(point+Vector2(-12,2),Vector2(24,4)),Color("edc780"))
	node.draw_rect(Rect2(point+Vector2(-11,2),Vector2(22,2)),Color("fff1b1"))

static func draw_work_lamp(node: CanvasItem,point: Vector2,floor_y: float,elapsed: float) -> void:
	_draw_lamp(node,point,floor_y,elapsed,0)
