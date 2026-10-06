extends Node2D
## A small physical field record. Reading grants no supplies or mission credit.
const Catalog := preload("res://scripts/solo_story_catalog.gd")
const L := preload("res://scripts/locale_text.gd")
var game: Node
var director: Node
var entry_id := ""
var site_id := ""
var variant := 0
var _pulse := 0.0

func _ready() -> void:
	add_to_group("interactables")
	add_to_group("solo_story_finds")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func can_interact(worker: Node) -> bool:
	return is_instance_valid(director) and director.enabled and director.offline_solo() and is_instance_valid(worker) and worker in game.players and worker.can_act() and is_visible_in_tree() and worker.global_position.distance_to(global_position)<=64.0

func interaction_point() -> Vector2:
	return global_position-Vector2(0,15)

func interaction_title() -> String:
	return L.text("Feldaufzeichnung")

func prompt(_worker: Node) -> String:
	return str(Catalog.entry(entry_id).get("title",""))

func work_uses_real_time() -> bool:
	return true

func interaction_progress(_worker: Node) -> float:
	return 0.0

func interact(worker: Node,_delta: float) -> bool:
	return can_interact(worker) and director.read_find(entry_id,worker,self)

func _process(delta: float) -> void:
	_pulse = fposmod(_pulse+delta,4.0)
	queue_redraw()

func _draw() -> void:
	# Weathered clipboard/radio case, built from the existing bunker palette.
	draw_rect(Rect2(-12,-25,25,24),Color("151e1c"))
	draw_rect(Rect2(-10,-23,21,21),Color("566158"))
	draw_rect(Rect2(-8,-20,16,15),Color("b2ad8b") if variant==0 else Color("273830"))
	for row in 4:
		draw_rect(Rect2(-6,-17+row*3,10-row%2*3,1),Color("4c5449") if variant==0 else Color("8eaa87"))
	draw_rect(Rect2(-4,-25,8,4),Color("7e8877"))
	draw_rect(Rect2(-11,-6,3,3),Color("29322d"))
	draw_rect(Rect2(8,-6,3,3),Color("29322d"))
	var unread: bool = is_instance_valid(director) and entry_id not in director.records.events
	if unread:
		draw_rect(Rect2(7,-23,2,2),Color("d5ad65"))
		if _pulse<2.0: draw_line(Vector2(-4,-29),Vector2(4,-29),Color("a99368"),1)
