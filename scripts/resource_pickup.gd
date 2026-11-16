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
## A drop left by a defeated enemy materialises texel by texel (the ordered
## dither of pickup_cutout's `reveal`) instead of popping in at full size:
## inside the blast of a machine, after the fall of a soldier. It is found
## from the fresh remains next to it, which host and guests both create, and
## a presentation child runs the build-up (a guest's replica is frozen).
## Settled piles, mined material and worker drops appear as before.
const REVEAL_TIME := 0.30
const REVEAL_AFTER_BLAST := 0.06
const REVEAL_AFTER_FALL := 0.70
const REVEAL_REACH := 40.0
var _reveal_checked := false

class DropReveal extends Node:
	var delay := 0.0
	var duration := 0.3
	var age := 0.0
	var shown := -1.0
	func _ready() -> void:
		_apply()
	func _process(delta: float) -> void:
		age += delta
		_apply()
	func _apply() -> void:
		var value := snappedf(clampf((age-delay)/duration,0.0,1.0),1.0/16.0)
		if value != shown:
			shown = value
			(get_parent() as CanvasItem).set_instance_shader_parameter(&"reveal",value)
		if value >= 1.0: queue_free()

func _ready() -> void:
	add_to_group("interactables")
	add_to_group("pickups")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	material = PICKUP_ART.cutout_material()
	set_process(kind=="core")
	_support_clock = float(get_instance_id()%15)/60.0
	# A guest may receive the drop just before the remains: look once more
	# after this frame's snapshot has been applied.
	if not _start_reveal(): _start_reveal.call_deferred()
	queue_redraw()

func _start_reveal() -> bool:
	if _reveal_checked or not is_inside_tree(): return false
	var delay := _fresh_remains_delay()
	if delay < 0.0: return false
	_reveal_checked = true
	var reveal := DropReveal.new()
	reveal.name = "DropReveal"
	reveal.delay = delay
	reveal.duration = REVEAL_TIME
	add_child(reveal)
	return true

## Reveal delay for a drop beside remains that are still settling, -1 when
## there are none (any other pile).
func _fresh_remains_delay() -> float:
	for wreck in get_tree().get_nodes_in_group("enemy_motion_wrecks"):
		if wreck is Node2D and float(wreck.get("elapsed")) < .25 and absf((wreck as Node2D).global_position.x-global_position.x) < REVEAL_REACH*1.5:
			return REVEAL_AFTER_BLAST
	for body in get_tree().get_nodes_in_group("infantry_remains"):
		if body is Node2D and float(body.get("corpse_age")) < .25 and absf((body as Node2D).global_position.x-global_position.x) < REVEAL_REACH:
			return REVEAL_AFTER_FALL
	return -1.0

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
