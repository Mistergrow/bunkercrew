extends SceneTree
## Holds the real P1/P2 InputMap actions while actual Workers run physics/input.

class StationProbe extends Node2D:
	var work := 0.0
	func _ready(): add_to_group("interactables")
	func interaction_point(): return global_position-Vector2(0,20)
	func can_interact(_player): return true
	func interact(_player,delta): work += delta

class MiningGame extends Node2D:
	var started := true
	var world_right := 1050.0
	var floor_levels: Array = [320.0]
	var ladders: Array[Rect2] = []
	var upgrades
	func valid_focus(player,target) -> bool:
		if not is_instance_valid(target) or target.is_queued_for_deletion(): return false
		if target.has_method("can_interact") and not target.can_interact(player): return false
		var center: Vector2 = player.global_position-Vector2(0,20)
		var point: Vector2 = target.surface_near(center) if target is MineBlock else target.interaction_point()
		return center.distance_to(point)<=88
	func focus_candidates(player) -> Array:
		var result: Array = []
		for target in get_tree().get_nodes_in_group("interactables"):
			if valid_focus(player,target): result.append(target)
		result.sort_custom(func(a,b): return a.interaction_point().distance_squared_to(player.global_position)<b.interaction_point().distance_squared_to(player.global_position))
		return result
	func get_focus(player):
		var targets := focus_candidates(player)
		return targets[0] if not targets.is_empty() else null
	func fx(_position,_color,_count): pass
	func sound(_kind): pass
	func notify(_message): pass
	func spawn_pickup(_kind,_amount,_position): pass

var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks += 1
	if value: print("PASS ",label)
	else:
		failures += 1
		push_error(label)
func frames(count: int):
	for frame in count: await physics_frame
func field_at(game,point: Vector2,size: Vector2):
	var field = load("res://scripts/diggable_terrain.gd").new()
	field.setup(game,Rect2(point,size))
	game.add_child(field)
	return field
func worker_at(game,point: Vector2,id: int):
	var worker = load("res://scenes/player.tscn").instantiate()
	worker.game = game
	worker.player_id = id
	worker.position = point
	game.add_child(worker)
	return worker
func pickup_at(game,point: Vector2,amount: int):
	var pickup = load("res://scenes/resource_pickup.tscn").instantiate()
	pickup.kind = "ore"
	pickup.amount = amount
	pickup.position = point
	pickup.game = game
	game.add_child(pickup)
	return pickup
func run():
	InputSetup.install()
	var game := MiningGame.new()
	root.add_child(game)
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(1100,20)
	shape.shape = box
	shape.position = Vector2(550,330)
	floor_body.add_child(shape)
	game.add_child(floor_body)
	var left = field_at(game,Vector2(192,272),Vector2(96,48))
	var right = field_at(game,Vector2(720,272),Vector2(96,48))
	var p1 = worker_at(game,Vector2(166,320),1)
	var p2 = worker_at(game,Vector2(694,320),2)
	var station := StationProbe.new()
	station.position = Vector2(311,320)
	game.add_child(station)
	var pickup = pickup_at(game,Vector2(305,305),2)
	await frames(5)
	p1.preferred_focus = left.cell_at(Vector2i(0,0))
	Input.action_press("p1_interact")
	Input.action_press("p1_right")
	await frames(10)
	check(left.cell_at(Vector2i(0,0)).mining>0 and left.cell_at(Vector2i(1,0)).mining==0,"Held E works only on the exposed cell; buried cell remains untouched")
	check(right.cell_at(Vector2i(0,0)).mining==0 and p2.inventory.is_empty(),"P1 mining input never operates P2")
	for frame in 150:
		await physics_frame
		if left.is_cleared(): break
	Input.action_release("p1_right")
	check(left.is_cleared() and p1.inventory.get("sand",0)==2,"One uninterrupted held E mines two successive real cells")
	check(p1.global_position.x>215,"Held right movement enters the first excavated cell")
	await frames(45)
	check(station.work==0 and pickup.amount==2 and p1.inventory.get("ore",0)==0,"Mining continuation never switches to a nearby station or pickup")
	p2.preferred_focus = right.cell_at(Vector2i(0,0))
	Input.action_press("p2_interact")
	Input.action_press("p2_right")
	for frame in 150:
		await physics_frame
		if right.is_cleared(): break
	Input.action_release("p2_right")
	Input.action_release("p2_interact")
	check(right.is_cleared() and p2.inventory.get("sand",0)==2 and p1.inventory.get("sand",0)==2,"P2 has its own continuous mining gesture and inventory")
	Input.action_release("p1_interact")
	await frames(3)
	p1.preferred_focus = station
	Input.action_press("p1_interact")
	await frames(12)
	check(station.work>0 and pickup.amount==2,"After releasing E, a new press can deliberately operate a station")
	Input.action_release("p1_interact")
	await frames(3)
	var near_mine = field_at(game,Vector2(p1.global_position.x+35,272),Vector2(48,48))
	var deliberate_pickup = pickup_at(game,p1.global_position+Vector2(24,-12),1)
	await frames(4)
	p1.preferred_focus = deliberate_pickup
	Input.action_press("p1_interact")
	await frames(60)
	check(p1.inventory.get("ore",0)==1 and near_mine.remaining_count()==1 and near_mine.blocks[0].mining==0,"A press that began on a pickup never gains automatic mining continuation")
	Input.action_release("p1_interact")
	await frames(3)
	print("MINING INPUT CHECKS: %d passed, %d failed" % [checks-failures,failures])
	game.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
