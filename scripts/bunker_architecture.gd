class_name BunkerArchitecture
extends RefCounted
## One material renderer for the original floors and every paid underground bay.
const REAR := preload("res://assets/bunker_wall.png")

static func concrete(node: CanvasItem, rect: Rect2) -> void:
	node.draw_rect(rect,Color("242b2b"))
	node.draw_rect(Rect2(rect.position+Vector2(2,2),rect.size-Vector2(4,5)),Color("676b60"))
	node.draw_line(rect.position,rect.position+Vector2(rect.size.x,0),Color("9e9f86"),2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(rect.position.x*17+rect.position.y*23+rect.size.x*13)
	for i in int(rect.get_area()/85):
		var p := Vector2(rng.randf_range(rect.position.x+2,rect.end.x-2),rng.randf_range(rect.position.y+2,rect.end.y-2)).round()
		node.draw_rect(Rect2(p,Vector2(3,2)),[Color("4f584f"),Color("858778"),Color("575c53")][i%3])

static func rear_wall(node: CanvasItem, rect: Rect2, region: Rect2=Rect2(), wetness: float=0.0) -> void:
	node.draw_rect(rect,Color("373b38"))
	var tint := Color(0.92,0.95,0.94).lerp(Color(0.70,0.77,0.77),wetness*0.65)
	if region.has_area():
		node.draw_texture_rect_region(REAR,rect,region,tint)
	else:
		node.draw_texture_rect(REAR,rect,false,tint)
	node.draw_rect(Rect2(rect.position,Vector2(rect.size.x,14)),Color(0,0,0,0.20))
	node.draw_rect(Rect2(rect.position+Vector2(0,rect.size.y-16),Vector2(rect.size.x,16)),Color(0,0,0,0.15))
