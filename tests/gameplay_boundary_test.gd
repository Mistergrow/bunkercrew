extends SceneTree
## Real crate/worker transactions must stay inside their owning physical world.
## Explicit restored convoy seating must retain one actual driver.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Expedition := preload("res://scripts/expedition_controller.gd")
var checks := 0
var failures := 0

class World extends Node2D:
	var started := false
	var network: Node
	var players: Array = []

class Crew extends Node:
	var game: Node
	var player_id := 1
	var character_id := "mara"
	var progression := PlayerProgression.new()
	func _init() -> void:
		add_child(progression)

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("GAMEPLAY BOUNDARY %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures += 1
		push_error(label)

func worker(world: World) -> Worker:
	var person: Worker = load("res://scenes/player.tscn").instantiate()
	person.game = world
	person.position = Vector2(120,200)
	world.add_child(person)
	world.players.append(person)
	person.set_physics_process(false)
	return person

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var fixtures := Node.new()
	root.add_child(fixtures)
	var local_world := World.new()
	fixtures.add_child(local_world)
	var local := worker(local_world)
	var same_space_world := World.new()
	fixtures.add_child(same_space_world)
	var foreign := worker(same_space_world)
	var other_view := SubViewport.new()
	other_view.world_2d = World2D.new()
	fixtures.add_child(other_view)
	var separate_world := World.new()
	other_view.add_child(separate_world)
	var separate := worker(separate_world)
	var crate := Supply.new()
	crate.game = local_world
	crate.kind = "steel"
	crate.amount = 3
	crate.position = Vector2(150,200)
	local_world.add_child(crate)
	crate.set_physics_process(false)
	for unused in 3:
		await physics_frame
	check(crate.can_interact(local),"Native nearby owner still reaches its physical crate")
	crate.interact(local,Balance.TRANSFER_TIME)
	check(crate.amount==2 and local.inventory=={"steel":1},"Owner withdrawal transfers exactly one stored unit")
	for person: Worker in [foreign,separate]:
		var description := "another Game in the same World2D" if person==foreign else "another Game and World2D"
		check(not crate.can_interact(person),"Crate rejects "+description)
		var stock := crate.amount
		var hands := person.inventory.duplicate()
		crate.interact(person,Balance.TRANSFER_TIME)
		check(crate.amount==stock and person.inventory==hands,"Foreign withdrawal preserves both owners: "+description)
		person.inventory={"steel":2}
		person.selected_kind="steel"
		hands=person.inventory.duplicate()
		stock=crate.amount
		crate.deposit(person,Balance.TRANSFER_TIME)
		check(crate.amount==stock and person.inventory==hands,"Foreign deposit preserves both owners: "+description)
		person.inventory.clear()
	# Matching the Game field is not sufficient to cross an independent physics world.
	separate.game=local_world
	check(not crate.can_interact(separate),"Same Game reference cannot bypass independent World2D isolation")
	separate.game=separate_world
	local.selected_kind="steel"
	crate.deposit(local,Balance.TRANSFER_TIME)
	check(crate.amount==3 and local.inventory.is_empty(),"Owner deposit returns its exact finite unit after rejected probes")
	var orphan: Worker = load("res://scenes/player.tscn").instantiate()
	orphan.game=local_world
	orphan.position=local.position
	check(not crate.can_interact(orphan),"Worker outside the scene cannot claim a physical crate")
	orphan.free()
	var detached := Node.new()
	check(not crate.can_interact(detached),"Non-spatial caller is rejected without property access")
	detached.free()
	var crew := Crew.new()
	fixtures.add_child(crew)
	var campaign := CampaignState.new("user://gameplay-boundary-never-save.json",false)
	check(campaign.begin_new({"environment":"ash_foundry","position":"left","build_type":"bastion"},["mara"],1),"Actual campaign accepts one valid crew identity")
	var mission := campaign.mission_start()
	check(not campaign.complete_mission(str(mission.id),Balance.TOTAL_WAVES,[crew]).is_empty(),"Actual victory establishes a finite departure snapshot")
	check(campaign.select_destination("harbor") and not campaign.begin_journey().is_empty(),"Actual selected route produces a valid travel checkpoint")
	var payload: Dictionary={"checkpoint":campaign.checkpoint(),"mode":"travel","options":campaign.options.duplicate(),"crew_seats":["driver"]}
	check(Expedition.valid_transition(payload),"Explicit driver role validates on the native campaign payload")
	for role: String in ["gunner","passenger_left","passenger_right"]:
		payload.crew_seats=[role]
		check(not Expedition.valid_transition(payload),"Explicit "+role+"-only crew cannot restore an undrivable convoy")
	payload.erase("crew_seats")
	check(Expedition.valid_transition(payload),"Original three-field resume still infers its driver seat")
	check(await Cleanup.free_scene(fixtures,self),"All actual worker/crate/world fixtures release cleanly")
	print("GAMEPLAY BOUNDARIES: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
