class_name ResourcePickup
extends Node2D

@export var kind: String = "sand"
@export var amount: int = 3
var game
var elapsed: float = 0.0
var fall_speed: float = 0.0
const GRAVITY := 1100.0
const PICKUP_ART = preload("res://scripts/pickup_art.gd")
var _last_visual_state: int = -1
var _support: WeakRef
var _support_shape: WeakRef
var _support_transform := Transform2D.IDENTITY
var _support_clock := 0.0
var support_queries := 0

func _ready() -> void:
	add_to_group("interactables")
	add_to_group("pickups")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	material = PICKUP_ART.cutout_material()
	set_process(kind=="core")
	_support_clock = float(get_instance_id()%15)/60.0
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	# Settled piles are static. A recovered controller only redraws when its
	# small indicator changes, instead of redrawing every pile every frame.
	if kind != "core":
		return
	var visual_state := PICKUP_ART.indicator_state(elapsed,visual_variant())
	if visual_state != _last_visual_state:
		_last_visual_state = visual_state
		queue_redraw()

func _physics_process(delta: float) -> void:
	if kind == "core": _collect_upgrade_points()
	if is_queued_for_deletion(): return
	_support_clock-=delta
	if supported() and _support_clock>0.0: return
	_support_clock=Balance.PICKUP_SUPPORT_INTERVAL
	# Sweep the footprint each frame so piles settle on slabs and newly exposed rock.
	# Workers can pass through loose resources; terrain and defensive walls support them.
	fall_speed = minf(fall_speed + GRAVITY * delta, 700.0)
	var next_y := global_position.y + fall_speed * delta
	var floor_y := INF
	var support_hit: Dictionary = {}
	for offset: float in [-8.0, 0.0, 8.0]:
		var from := global_position + Vector2(offset, -2.0)
		var to := Vector2(global_position.x + offset, next_y + 1.0)
		var query := PhysicsRayQueryParameters2D.create(from, to, 1 | 2)
		# Death drops can begin inside a fence or column. Interior hits have a
		# zero normal and are not support; ignoring them lets the same sweep
		# still find the actual floor, including another shape of that body.
		query.hit_from_inside = false
		support_queries+=1
		var hit := get_world_2d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.normal.y < 0.0:
			if hit.position.y<floor_y:
				floor_y=hit.position.y
				support_hit=hit
	if floor_y < INF:
		global_position.y = floor_y - 0.5
		fall_speed = 0.0
		var body: Node2D = support_hit.collider as Node2D
		_support = weakref(body) if is_instance_valid(body) else null
		_support_transform = body.global_transform if is_instance_valid(body) else Transform2D.IDENTITY
		_support_shape=null
		if body is CollisionObject2D:
			var shape_node = body.shape_owner_get_owner(body.shape_find_owner(support_hit.shape))
			if is_instance_valid(shape_node): _support_shape=weakref(shape_node)
	else:
		global_position.y = next_y
		_support=null
		_support_shape=null

func supported() -> bool:
	if _support==null or fall_speed!=0.0: return false
	var body = _support.get_ref()
	if not is_instance_valid(body) or body.is_queued_for_deletion() or body.global_transform!=_support_transform: return false
	if _support_shape!=null:
		var shape = _support_shape.get_ref()
		if not is_instance_valid(shape) or shape.get("disabled")==true: return false
	return true

func _collect_upgrade_points() -> void:
	if amount <= 0 or not is_instance_valid(game) or not "upgrades" in game or not is_instance_valid(game.upgrades):
		return
	for player in get_tree().get_nodes_in_group("players"):
		if not _same_owner_and_world(player) or absf(player.global_position.y-global_position.y) > 38:
			continue
		if player.global_position.distance_to(global_position) > 48:
			continue
		var ray := PhysicsRayQueryParameters2D.create(global_position-Vector2(0,15), player.global_position-Vector2(0,20), 1|2)
		if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		game.upgrades.add_points(amount)
		game.fx(global_position-Vector2(0,12), Color("c8a56a"), 5)
		preload("res://scripts/spatial_sound.gd").emit(game,"pickup",global_position)
		amount = 0
		queue_free()
		return

func interaction_point() -> Vector2:
	return global_position + Vector2(0, -13)

func _same_owner_and_world(player) -> bool:
	return is_instance_valid(player) and player is Node2D and not player.is_queued_for_deletion() and player.is_inside_tree() and player.get("game") == game and player.get_world_2d() == get_world_2d()

func can_interact(player) -> bool:
	if kind == "core" or amount <= 0 or is_queued_for_deletion() or not _same_owner_and_world(player):
		return false
	# A full worker must still be able to select the next mine block behind a pile.
	if player.carried_count() >= Balance.capacity_for(player):
		return false
	# Nearby piles can lie behind unexcavated earth or on the next storey.
	# Use the same solid layers as mining and dropping so cargo cannot pass
	# through terrain or a wall built after the worker selected this pile.
	var ray := PhysicsRayQueryParameters2D.create(player.global_position-Vector2(0,20),interaction_point(),1|2)
	ray.hit_from_inside = true
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()

func prompt(player) -> String:
	var label: String = Balance.RESOURCE_NAMES.get(kind, kind)
	if player.carried_count() >= Balance.capacity_for(player):
		return LocaleText.format("%s ×%d · Hände voll – Material abgeben", [label, amount])
	return LocaleText.format("%s ×%d aufnehmen · antippen", [label, amount])

func interaction_progress(_player) -> float:
	return 0.0

func interact(player, _delta: float) -> void:
	if not can_interact(player):
		return
	var added: int = player.add_item(kind, amount)
	amount -= added
	if added > 0 and is_instance_valid(game):
		preload("res://scripts/spatial_sound.gd").emit(game,"pickup",global_position)
	if amount <= 0:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var variant := visual_variant()
	PICKUP_ART.draw_world(self,kind,variant,Vector2.ZERO,0,PICKUP_ART.indicator_state(elapsed,variant) if kind == "core" else 0)
	# Quantity and the pickup action already live in the focused HUD dock.
	# Drawing them again above each pile buries combat and nearby characters.

func visual_variant() -> int:
	return PICKUP_ART.variant_for(kind,global_position.x)
