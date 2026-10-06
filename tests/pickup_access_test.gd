extends SceneTree
## Real physics barriers must protect loose cargo just as they protect mined ore.

const Cleanup = preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
var world: Node2D
var worker: Worker

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS ", label)
	else:
		failures += 1
		push_error(label)

func barrier(rect: Rect2, layer: int) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = rect.get_center()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	return body

func pile(at: Vector2, amount := 3) -> ResourcePickup:
	var result := ResourcePickup.new()
	result.kind = "ore"
	result.amount = amount
	result.position = at
	world.add_child(result)
	result.set_process(false)
	result.set_physics_process(false)
	return result

func sync_physics() -> void:
	await physics_frame
	await physics_frame

func run() -> void:
	world = Node2D.new()
	root.add_child(world)
	worker = load("res://scenes/player.tscn").instantiate()
	worker.position = Vector2(100,100)
	world.add_child(worker)
	worker.set_physics_process(false)
	var cargo := pile(Vector2(160,100),8)
	await sync_physics()
	check(cargo.can_interact(worker), "Adjacent cargo is selectable across unobstructed space")
	var rock := barrier(Rect2(124,40,16,70),1)
	await sync_physics()
	check(not cargo.can_interact(worker), "Solid earth blocks loose-material selection")
	cargo.interact(worker,0.016)
	check(worker.carried_count() == 0 and cargo.amount == 8, "Picking through solid earth cannot transfer or duplicate material")
	# Reset the fixture after the assertion so a pre-fix failure cannot cascade.
	worker.inventory.clear()
	cargo.amount = 8
	rock.queue_free()
	await process_frame
	await sync_physics()
	check(cargo.can_interact(worker), "Excavating the obstruction makes the same pile accessible")
	cargo.interact(worker,0.016)
	check(worker.carried_count() == worker.capacity() and cargo.amount == 8-worker.capacity(), "Accessible pickup fills only real capacity and retains overflow")
	check(not cargo.can_interact(worker), "A full inventory still leaves other interaction targets selectable")
	worker.inventory.clear()
	cargo.amount = 20
	var concrete := barrier(Rect2(124,40,16,70),2)
	await sync_physics()
	check(not cargo.can_interact(worker), "Defensive concrete walls block loose-material selection")
	var before := cargo.amount
	cargo.interact(worker,0.016)
	check(worker.carried_count() == 0 and cargo.amount == before, "A wall built after targeting also blocks the actual transfer")
	worker.inventory.clear()
	cargo.amount = 3
	concrete.queue_free()
	await process_frame
	await sync_physics()
	cargo.interact(worker,0.016)
	check(cargo.amount == 0 and cargo.is_queued_for_deletion() and worker.carried_count() == 3, "Removing the wall permits one conserved final transfer")
	worker.inventory.clear()
	var downstairs := pile(Vector2(100,156),20)
	var slab := barrier(Rect2(65,113,70,12),1)
	await sync_physics()
	check(not downstairs.can_interact(worker), "A floor slab separates piles on different storeys")
	downstairs.interact(worker,0.016)
	check(worker.carried_count() == 0 and downstairs.amount == 20, "Resources below a floor stay below that floor")
	worker.inventory.clear()
	slab.queue_free()
	await process_frame
	await sync_physics()
	check(downstairs.can_interact(worker), "An actual opening restores access to the lower pile")
	var core := pile(Vector2(100,100))
	core.kind = "core"
	check(not core.can_interact(worker), "Technology crystals keep their automatic collection path")
	core.interact(worker,1.0)
	check(worker.carried_count() == 0 and core.amount == 3, "Manual interaction never converts technology into inventory cargo")
	check(await Cleanup.free_scene(world,self), "All pickup and physics fixtures cleanly release")
	print("PICKUP ACCESS CHECKS: %d passed, %d failed" % [checks-failures,failures])
	quit(0 if failures == 0 else 1)
