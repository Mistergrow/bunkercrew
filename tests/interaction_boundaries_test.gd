extends SceneTree
## Malformed interaction times must not alter cargo or poison future work.

class TestWorld extends Node2D:
	var started := false
	var drops: Array[Dictionary] = []
	func spawn_pickup(kind: String, amount: int, point: Vector2) -> void:
		drops.append({"kind":kind,"amount":amount,"position":point})
	func fx(_point: Vector2, _color: Color = Color.WHITE, _amount: int = 8) -> void:
		pass

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _run() -> void:
	var world := TestWorld.new()
	root.add_child(world)
	var player := preload("res://scenes/player.tscn").instantiate() as Worker
	player.game = world
	player.position = Vector2(100,100)
	world.add_child(player)
	player.set_physics_process(false)
	player.inventory = {"steel":player.capacity()+2}
	var original := player.inventory.duplicate()
	for amount in [-1,0,1,3]:
		check(player.add_item("ore",amount)==0,"Over-capacity inventory accepts zero units (%d)" % amount)
	check(player.inventory==original,"Over-capacity inventory preserves every carried resource")
	var block := MineBlock.new()
	block.game = world
	block.kind = "ore"
	block.yield_amount = 3
	block.position = Vector2(140,78)
	world.add_child(block)
	for _frame in 3:
		await physics_frame
	check(block.can_interact(player),"Real mining collider is reachable")
	for invalid in [NAN,INF,-INF,-1.0,0.0]:
		block.interact(player,invalid)
		check(not block.depleted and block.mining==0.0,"Invalid mining delta makes no progress: %s" % str(invalid))
	# Reset the fixture after probing invalid input, so the conservation assertion
	# can independently reproduce a capacity overflow in the unpatched code.
	if is_instance_valid(block) and not block.is_queued_for_deletion():
		block.mining = 0.0
		block.interact(player,block.mining_duration())
	check(world.drops.size()==1 and int(world.drops[0].amount)==3,"Full hands leave exactly the three mined resources on the ground")
	check(player.inventory==original,"Mining preserves over-capacity cargo")
	await process_frame
	player.inventory = {"ore":3,"steel":2}
	for machine: ProductionStation in [ProductionStation.new(),RecipeStation.new()]:
		machine.kind = "furnace" if not machine is RecipeStation else "ammo_press"
		world.add_child(machine)
		machine.set_process(false)
		var cargo := player.inventory.duplicate()
		for invalid in [NAN,INF,-INF,-1.0,0.0]:
			machine.interact(player,invalid)
			check(machine.input_amount==0 and machine.transfer.is_empty() and player.inventory==cargo,"%s rejects invalid transfer delta %s" % [machine.get_class(),str(invalid)])
		machine.transfer.clear()
		machine.input_amount = 0
		player.inventory = cargo.duplicate()
		machine.interact(player,Balance.TRANSFER_TIME*0.5)
		check(machine.input_amount==0,"Valid machine transfer still requires holding")
		machine.interact(player,Balance.TRANSFER_TIME*0.5)
		check(machine.input_amount==1 and player.carried_count()==5-1,"Valid transfer deposits exactly one unit after invalid calls")
		var buffer := machine.input_amount
		var after_transfer := player.inventory.duplicate()
		machine.interact(null,Balance.TRANSFER_TIME)
		check(machine.input_amount==buffer and player.inventory==after_transfer,"Missing worker cannot consume machine input")
		machine.queue_free()
		player.inventory = {"ore":3,"steel":2}
	var workshop := FieldWorkshop.new()
	world.add_child(workshop)
	workshop.set_process(false)
	workshop.set_physics_process(false)
	player.inventory = {"steel":2}
	for invalid in [NAN,INF,-INF,-1.0,0.0]:
		workshop.interact(player,invalid)
		check(workshop.orders.is_empty() and player.inventory=={"steel":2},"Workshop rejects invalid transfer delta %s" % str(invalid))
	workshop.orders.clear()
	player.inventory = {"steel":2}
	workshop.interact(player,Balance.TRANSFER_TIME)
	check(workshop.order_for(player).materials.get("steel",0)==1 and player.inventory.get("steel",0)==1,"Workshop resumes normal resource transfer")
	workshop.interact(player,Balance.TRANSFER_TIME)
	check(workshop.order_for(player).working and player.carried_count()==0,"Workshop starts only after exact recipe payment")
	var orders := workshop.orders.duplicate(true)
	workshop.interact(null,Balance.TRANSFER_TIME)
	check(workshop.orders==orders,"Missing worker cannot mutate personal work orders")
	check(await preload("res://tests/scene_cleanup.gd").free_scene(world,self),"Fixture releases all scene nodes")
	print("INTERACTION BOUNDARIES: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
