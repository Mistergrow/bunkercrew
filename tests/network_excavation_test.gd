extends SceneTree
## Real mine/build interactions survive late join and ordered stage snapshots.
const WORLD := preload("res://scripts/network_world.gd")
const FIXTURE := preload("res://tests/scenario_excavation_fixture.gd")
const CLEANUP := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func scene() -> Node:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(2, {"environment":"ash_foundry", "build_type":"bastion", "position":"left"})
	game.rounds.set_process(false)
	game.medic.set_physics_process(false)
	for worker in game.players: worker.set_physics_process(false)
	return game

func cell_removed(game: Node, index: int) -> bool:
	var block: MineBlock = game.scenario_bunker.fields[index].cell_at(Vector2i(0,2))
	var worker: Node2D = game.players[0]
	worker.position = Vector2(block.position.x - 44, block.position.y + 24)
	await physics_frame
	if not block.can_interact(worker): return false
	block.interact(worker, block.mining_duration() + .01)
	await physics_frame
	return not is_instance_valid(block) or block.depleted

func record(packet: Dictionary, kind: String, index := 0) -> Dictionary:
	var matches: Array = packet.entities.filter(func(entry): return entry.type == kind)
	return matches[index] if index < matches.size() else {}

func capture(world, game: Node, label: String) -> Dictionary:
	return {"label":label, "packet":world.capture(), "remaining":game.scenario_bunker.fields.map(func(field): return field.remaining_count()), "inventory":game.players[0].inventory.duplicate()}

func run() -> void:
	var host := scene()
	var authority := WORLD.new()
	authority.bind(host)
	var stages: Array[Dictionary] = [capture(authority, host, "untouched soil")]
	var worker = host.players[0]
	var site = host.scenario_bunker.modules[0]
	check(await cell_removed(host,0), "First exposed cell is physically mined")
	stages.append(capture(authority,host,"partial excavation"))
	check(await FIXTURE.clear_field(host,0,worker), "All remaining cells can be excavated")
	stages.append(capture(authority,host,"excavated room"))
	worker.inventory = site.spec().cost.duplicate()
	site.interact(worker,Balance.TRANSFER_TIME)
	stages.append(capture(authority,host,"one paid support beam"))
	site.interact(worker,Balance.TRANSFER_TIME)
	site.interact(worker,.6)
	stages.append(capture(authority,host,"support installation"))
	site.interact(worker,ScenarioRoomCatalog.SUPPORT_TIME)
	stages.append(capture(authority,host,"completed supports"))
	site.interact(worker,Balance.TRANSFER_TIME)
	stages.append(capture(authority,host,"partial room materials"))
	for payment in 20:
		if site.complete_materials(): break
		site.interact(worker,Balance.TRANSFER_TIME)
	site.interact(worker,ScenarioRoomCatalog.BUILD_TIME)
	stages.append(capture(authority,host,"curing room"))
	site._process(ScenarioRoomCatalog.CURE_TIME)
	stages.append(capture(authority,host,"finished room and locked next shaft"))
	host.rounds.wave = 5
	check(host.scenario_bunker.prepare_excavation(1), "The wave-five blueprint opens the next excavation")
	check(await cell_removed(host,1), "A new field loses a cell before its first network scan")
	stages.append(capture(authority,host,"second shaft with partial excavation"))
	var second: Dictionary = stages.back().packet
	var survivor_id := "fixed:diggable_terrain:218:696/mine_block:1:2"
	check(second.entities.any(func(entry): return entry.id == survivor_id and entry.state.grid_cell == Vector2i(1,2)), "New field cell IDs remain based on coordinates after earlier cells vanish")
	await CLEANUP.free_scene(host,self)
	var guest := scene()
	var replica := WORLD.new()
	replica.bind(guest)
	for stage in stages:
		check(replica.apply(stage.packet), "Replica accepts %s: %s" % [stage.label,replica.last_error])
		if not replica.last_error.is_empty(): break
		check(guest.scenario_bunker.fields.map(func(field): return field.remaining_count()) == stage.remaining, "%s retains exact remaining terrain" % stage.label)
		check(guest.players[0].inventory == stage.inventory, "%s never awards duplicate client resources" % stage.label)
		var source: Dictionary = record(stage.packet,"scenario_room_site").state
		var target = guest.scenario_bunker.modules[0]
		check(target.supported == source.supported and target.support_work == source.support_work and target.materials == source.materials and target.curing == source.curing, "%s retains every construction stage" % stage.label)
	check(guest.scenario_bunker.open_depths == 1 and guest.scenario_bunker.excavation_depths == 2 and guest.scenario_bunker.modules[1].position.y == 840, "Completed room and lower work panel retain separate depths")
	var current: Dictionary = replica.capture()
	var before := var_to_bytes(current)
	var bad: Array[Dictionary] = []
	var packet: Dictionary = current.duplicate(true)
	var support: Dictionary = record(packet,"scenario_room_site",1).state
	support.support_materials = {"steel":2}
	support.support_work = ScenarioRoomCatalog.SUPPORT_TIME
	support.supported = true
	bad.append(packet)
	packet = current.duplicate(true)
	record(packet,"scenario_room_site",1).state.support_materials = {"steel":3}
	bad.append(packet)
	packet = current.duplicate(true)
	record(packet,"scenario_room_site",1).state.materials = {"concrete":1}
	bad.append(packet)
	packet = current.duplicate(true)
	record(packet,"scenario_room_site",1).state.position.y -= 205
	bad.append(packet)
	packet = current.duplicate(true)
	packet.structure.excavation_depths = 3
	bad.append(packet)
	packet = current.duplicate(true)
	var vanished: Dictionary = record(stages[0].packet,"mine_block").duplicate(true)
	packet.entities.append(vanished)
	bad.append(packet)
	for invalid in bad:
		check(not replica.apply(invalid), "Impossible construction/soil state is rejected")
		check(var_to_bytes(replica.capture()) == before, "Invalid stage leaves all captured state unchanged")
	check(replica.apply(current), "Valid state still applies after rejected packets")
	await CLEANUP.free_scene(guest,self)
	# A late join has never seen the earlier cells, supports or moved work panel.
	guest = scene()
	replica = WORLD.new()
	replica.bind(guest)
	check(replica.apply(second), "Late join reconstructs the completed room and partly mined next shaft: " + replica.last_error)
	check(guest.scenario_bunker.fields[0].is_cleared() and guest.scenario_bunker.fields[1].remaining_count() == 29, "Late join removes all finished-room soil without resurrecting the missing next-room cell")
	check(replica.apply(second), "Applying the same authoritative snapshot is idempotent")
	check(guest.scenario_bunker.built_rooms == 2 and guest.scenario_bunker.modules.size() == 2, "Repeated state creates no duplicate rooms or panels")
	await CLEANUP.free_scene(guest,self)
	print("NETWORK EXCAVATION: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
