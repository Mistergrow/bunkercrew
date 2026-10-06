class_name LadderPassage
extends StaticBody2D
## A framed opening with two retracting steel leaves. Walking support, rain and
## projectiles use the same moving geometry that is drawn here.
const WIDTH := 56.0
const OPEN_TIME := 0.16
var game: Node
var slab_depth := 20.0
var rung_origin := 219.0
var opening := 0.0
var blocked := false
var clock := 0.0
var _requests: Dictionary = {}
var _leaves: Array[CollisionShape2D] = []

func _ready() -> void:
	add_to_group("ladder_passages")
	set_meta("weather_material","metal")
	set_meta("ladder_passage",true)
	collision_layer=1
	collision_mask=0
	z_index=7
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	for index in 2:
		var leaf:=CollisionShape2D.new()
		leaf.shape=RectangleShape2D.new()
		add_child(leaf)
		_leaves.append(leaf)
	_update_leaves()

static func _height(actor: Node2D) -> float:
	return 34.0 if actor.is_in_group("medics") else 70.0

static func allow_motion(actor: Node2D, next_feet_y: float) -> bool:
	if is_equal_approx(actor.global_position.y,next_feet_y): return true
	var allowed:=true
	for passage: LadderPassage in actor.get_tree().get_nodes_in_group("ladder_passages"):
		if absf(actor.global_position.x-passage.global_position.x)>WIDTH*.5+16: continue
		var lower:=maxf(actor.global_position.y,next_feet_y)
		var upper:=minf(actor.global_position.y,next_feet_y)-_height(actor)
		if lower<=passage.global_position.y+.75 or upper>=passage.global_position.y+passage.slab_depth+8: continue
		passage._requests[actor.get_instance_id()]={"actor":weakref(actor),"until":passage.clock+.20}
		if passage.opening<.999: allowed=false
	return allowed

static func landing_ready(actor: Node2D, floor_y: float) -> bool:
	var is_ready:=true
	for passage: LadderPassage in actor.get_tree().get_nodes_in_group("ladder_passages"):
		if absf(floor_y-passage.global_position.y)>2 or absf(actor.global_position.x-passage.global_position.x)>WIDTH*.5+12: continue
		passage._requests.erase(actor.get_instance_id())
		if passage.opening>.001: is_ready=false
	return is_ready

func aperture() -> Rect2:
	return Rect2(global_position-Vector2(WIDTH*.5,0),Vector2(WIDTH,slab_depth))

func _crew() -> Array:
	var result: Array=get_tree().get_nodes_in_group("players")
	result.append_array(get_tree().get_nodes_in_group("medics"))
	return result

func _physics_process(delta: float) -> void:
	clock+=delta
	for id in _requests.keys():
		if float(_requests[id].until)<clock or not is_instance_valid(_requests[id].actor.get_ref()): _requests.erase(id)
	var occupied:=false
	blocked=false
	for actor: Node2D in _crew():
		if absf(actor.global_position.x-global_position.x)>WIDTH*.5+10: continue
		var feet: float=actor.global_position.y-global_position.y
		# Never crush a crossing, wounded or stationary body. A worker standing
		# on a closed leaf keeps it shut until they move or choose to climb.
		if feet>.75 and feet-_height(actor)<slab_depth: occupied=true
		if absf(feet)<3 and not bool(actor.get("climbing")) and not _requests.has(actor.get_instance_id()): blocked=true
	var target:=1.0 if occupied or (not _requests.is_empty() and not blocked) else 0.0
	var previous:=opening
	opening=move_toward(opening,target,delta/OPEN_TIME)
	if not is_equal_approx(previous,opening):
		_update_leaves()
		if is_instance_valid(game) and is_instance_valid(game.get("weather")):
			game.weather.refresh_collision_cache()
	queue_redraw()

func _update_leaves() -> void:
	var width:=WIDTH*.5*(1.0-opening)
	collision_layer=0 if opening>=.999 else 1
	for index in _leaves.size():
		var leaf:=_leaves[index]
		var box: RectangleShape2D=leaf.shape
		box.size=Vector2(maxf(.01,width),8)
		leaf.position=Vector2(-WIDTH*.5+width*.5 if index==0 else WIDTH*.5-width*.5,4)

func _draw() -> void:
	var half:=WIDTH*.5
	# Dark reveal replaces the concrete cross-section; rungs live behind its
	# steel curb, so no rung or handrail is painted across a closed floor plate.
	draw_rect(Rect2(-half,-2,WIDTH,slab_depth+5),Color("101a1b"))
	draw_rect(Rect2(-half+5,3,WIDTH-10,slab_depth),Color("202e2d"))
	for side in [-1,1]:
		draw_rect(Rect2(side*12-2,0,4,slab_depth+4),Color("7b704e"))
	for y in range(int(global_position.y)-14,int(global_position.y+slab_depth)+14):
		if posmod(y-int(rung_origin),14)==0:
			draw_rect(Rect2(-12,y-global_position.y,24,3),Color("ac925c"))
	for side in [-1,1]:
		var x: float=-half-6 if side<0 else half
		draw_rect(Rect2(x,-4,6,slab_depth+10),Color("182525"))
		draw_rect(Rect2(x+1,-3,4,slab_depth+7),Color("68766b"))
		draw_rect(Rect2(x+1,-3,2,slab_depth+6),Color("a6a184"))
		for y in [1.0,slab_depth-3]: draw_rect(Rect2(x+2,y,2,2),Color("d0bb83"))
		# Recessed runners and short striped step plates stay beside the shaft.
		var step_x: float=-half-15 if side<0 else half+4
		draw_rect(Rect2(step_x,-3,11,5),Color("6f7260"))
		for stripe in 2: draw_rect(Rect2(step_x+stripe*6,-3,3,2),Color("b3a16a"))
	var leaf_width:=roundf(half*(1.0-opening))
	if leaf_width>0:
		for index in 2:
			var x: float=-half if index==0 else half-leaf_width
			draw_rect(Rect2(x,0,leaf_width,8),Color("283839"))
			draw_rect(Rect2(x,0,leaf_width,2),Color("a8aa91"))
			draw_rect(Rect2(x,3,leaf_width,3),Color("626e61"))
			for rib in range(3,int(leaf_width)-1,7): draw_rect(Rect2(x+rib,3,2,2),Color("343f3b"))
	var lamp:=Color("c98a48") if blocked else Color("a6bc86") if opening>.01 else Color("6a8372")
	draw_rect(Rect2(half+8,6,3,4),lamp)
