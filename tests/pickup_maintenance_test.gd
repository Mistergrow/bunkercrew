extends "res://tests/pickup_visual_test.gd"
## Preserve real loot quantities, wire bounds, support changes and room access.
func piles(host, kind: String="") -> Array:
	return get_nodes_in_group("pickups").filter(func(pile):return pile.game==host and not pile.is_queued_for_deletion() and (kind.is_empty() or pile.kind==kind))
func total(host, kind: String) -> int:
	var result:=0
	for pile in piles(host,kind):result+=pile.amount
	return result
func solid(host, at: Vector2, size: Vector2) -> StaticBody2D:
	var body:=StaticBody2D.new()
	body.collision_layer=1;body.position=at
	var shape:=CollisionShape2D.new()
	var rectangle:=RectangleShape2D.new();rectangle.size=size
	shape.shape=rectangle;body.add_child(shape);host.add_child(body)
	return body
func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():quit(2);return
	var host=scene()
	host._place_pickup("scrap",20007,Vector2(1200,420))
	await frames(24)
	var maintenance=host.get_node("PickupMaintenance")
	maintenance.set_process(false)
	check(piles(host).size()==3 and total(host,"scrap")==20007,"Large drop is split without losing any raw resource")
	check(piles(host).all(func(pile):return pile.amount>0 and pile.amount<=10000 and pile.supported()),"Every resulting stack respects network limits and settles")
	host._place_pickup("scrap",3,Vector2(1240,420))
	await frames(20)
	maintenance.compact();await frames(2)
	check(total(host,"scrap")==20010 and piles(host,"scrap").size()==3,"Settled nearby stacks compact while preserving every unit")
	var sleeper:ResourcePickup=piles(host,"scrap")[0]
	sleeper.set_physics_process(false)
	var previous:=sleeper.support_queries
	for tick in 180:sleeper._physics_process(1.0/60)
	check(sleeper.supported() and sleeper.support_queries-previous<=39,"Three seconds of settled loot use at most 39 support rays instead of 540")
	check(not sleeper.is_processing() and sleeper.elapsed==0,"Raw loot has no changing animation field in snapshots")
	var wall:=solid(host,Vector2(1320,400),Vector2(4,60))
	await frames(3)
	host._place_pickup("sand",5,Vector2(1300,420))
	host._place_pickup("sand",7,Vector2(1340,420))
	host._place_pickup("iron",4,Vector2(1300,420))
	await frames(20);maintenance.compact();await frames(2)
	check(piles(host,"sand").size()==2 and total(host,"sand")==12,"A real solid wall prevents merging accessible loot into another room")
	check(total(host,"iron")==4 and piles(host,"iron").size()==1,"Different resources remain independent")
	wall.queue_free();await frames(3);maintenance.compact();await frames(2)
	check(piles(host,"sand").size()==1 and total(host,"sand")==12,"Opening the room permits consolidation with no loss")
	var floor_body:=solid(host,Vector2(1500,360),Vector2(100,20))
	await frames(3)
	host._place_pickup("stone",2,Vector2(1500,340))
	await frames(15)
	var falling:ResourcePickup=piles(host,"stone")[0]
	falling.set_physics_process(false)
	check(falling.supported() and absf(falling.position.y-349.5)<1,"Loose resources settle on a separate real platform")
	floor_body.get_child(0).set_deferred("disabled",true)
	await frames(3)
	check(not falling.supported(),"Disabling a supporting collision shape immediately wakes the pile")
	var old_y:=falling.position.y
	falling._physics_process(1.0/60)
	check(falling.position.y>old_y and falling.fall_speed>0,"A woken pile resumes gravity without waiting for its probe timer")
	floor_body.get_child(0).set_deferred("disabled",false)
	await frames(3)
	falling.position=Vector2(1500,349.5);falling._physics_process(1.0/60)
	check(falling.supported(),"Support can be restored")
	floor_body.position.x+=200;await frames(3)
	check(not falling.supported(),"Moving a support also wakes the pile")
	floor_body.queue_free();await frames(3)
	check(not falling.supported(),"Deleting a support leaves no stale strong reference")
	var authority:=World.new();authority.bind(host)
	var snapshot:=authority.capture()
	check(snapshot.entities.filter(func(record):return record.type=="resource_pickup").all(func(record):return record.state.amount<=10000),"Compacted and split loot stays within the existing snapshot schema")
	var original:=total(host,"scrap")
	for maintenance_pass in 100:maintenance.compact()
	check(total(host,"scrap")==original,"Repeated maintenance has no lifetime or quantity decay")
	check(await Cleanup.free_scene(host,self),"Loot fixture releases cleanly")
	print("PICKUP MAINTENANCE: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
