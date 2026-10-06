extends "res://tests/pickup_visual_test.gd"
## Embedded death drops must reach a real floor without inventing support or
## relaxing the ownership/sightline rules used to collect their finite cargo.

func add_shape(body: StaticBody2D, center: Vector2, size: Vector2) -> CollisionShape2D:
	var collider := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collider.shape = rectangle
	collider.position = center
	body.add_child(collider)
	return collider

func column(host: Node, center: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1 | 2
	body.collision_mask = 0
	add_shape(body,center,Vector2(64,80))
	host.add_child(body)
	return body

func embedded_drop(host: Node, at: Vector2) -> ResourcePickup:
	var pile := ResourcePickup.new()
	pile.game = host
	pile.kind = "ore"
	pile.amount = 3
	pile.position = at
	host.add_child(pile)
	return pile

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	AudioServer.set_bus_mute(0,true)
	var host = scene()
	var fence := column(host,Vector2(1400,390))
	await frames()
	# All three footprint rays begin inside the column, whose bottom meets
	# the independent real scenario floor. No outside ray can hide a failure.
	var pile := embedded_drop(host,Vector2(1400,410))
	await frames(30)
	pile.set_physics_process(false)
	check(pile.supported() and absf(pile.position.y-429.5)<0.1 and pile.fall_speed==0.0,"All three embedded footprint rays find the real scenario floor")
	check(pile._support != null and pile._support.get_ref()!=fence,"An interior fence hit never becomes cached floor support")
	var worker = host.players[0]
	worker.position = Vector2(1350,430)
	check(not pile.can_interact(worker),"Correctly grounded loot remains inaccessible through the intact fence")
	pile.interact(worker,0.016)
	check(pile.amount==3 and worker.inventory.is_empty(),"A fence-blocked pickup cannot debit or duplicate cargo")
	fence.queue_free()
	await frames()
	check(pile.can_interact(worker),"Removing the real obstruction restores access to the same grounded pile")
	worker.game = null
	check(not pile.can_interact(worker),"Opening the fence does not relax pickup ownership")
	worker.game = host
	pile.interact(worker,0.016)
	check(pile.amount==0 and int(worker.inventory.get("ore",0))==3,"Accessible embedded loot transfers its original finite quantity exactly once")
	await frames()
	# A compound body is the harder case: the column and its supporting floor
	# share one collider RID, so excluding the whole body would lose the floor.
	var compound := StaticBody2D.new()
	compound.collision_layer = 1 | 2
	compound.collision_mask = 0
	var slab := add_shape(compound,Vector2(2200,440),Vector2(180,20))
	add_shape(compound,Vector2(2200,390),Vector2(64,80))
	host.add_child(compound)
	await frames()
	var compound_pile := embedded_drop(host,Vector2(2200,410))
	await frames(30)
	compound_pile.set_physics_process(false)
	check(compound_pile.supported() and absf(compound_pile.position.y-429.5)<0.1,"Embedded rays still reach the floor belonging to the same compound collider")
	check(compound_pile._support_shape!=null and compound_pile._support_shape.get_ref()==slab,"Only the actual upward slab shape is cached as support")
	slab.set_deferred("disabled",true)
	await frames()
	check(not compound_pile.supported(),"Disabling the real slab wakes loot even while the column remains")
	var old_y := compound_pile.position.y
	compound_pile._physics_process(0.1)
	check(compound_pile.position.y>old_y and compound_pile.fall_speed>0.0,"The remaining column cannot suspend unsupported cargo")
	check(await Cleanup.free_scene(host,self),"Embedded pickup and collision fixtures release cleanly")
	print("PICKUP SUPPORT: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
