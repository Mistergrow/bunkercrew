extends SceneTree
## Real alternative ingredients retain their material identity until completion.
const Cleanup = preload("res://tests/scene_cleanup.gd")
const World = preload("res://scripts/network_world.gd")
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("FURNACE MATERIAL ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1
		push_error(label)

func run():
	if not "--no-profile-save" in OS.get_cmdline_user_args() or not "--no-upnp" in OS.get_cmdline_user_args():
		quit(2)
		return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start_scenario(1, {"environment":"ash_foundry", "position":"left", "build_type":"bastion"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.expedition.set_physics_process(false)
	game.medic.set_physics_process(false)
	for player in game.players:
		player.set_physics_process(false)
	for station in get_nodes_in_group("stations"):
		if station.game == game:
			station.set_process(false)
	paused = true
	for frame in 3:
		await physics_frame
	var host_world := World.new()
	host_world.bind(game)
	var source: Supply = game.expedition._new_supply("scrap", 2, 0)
	var furnace: ProductionStation
	for station in get_nodes_in_group("stations"):
		if station.game == game and station.kind == "furnace":
			furnace = station
	check(is_instance_valid(source) and is_instance_valid(furnace), "Fixture uses two finite scrap units and the actual steel furnace")
	var player = game.players[0]
	var before: Dictionary = game.expedition._capture_stock()
	player.position = source.position + Vector2(-28, 0)
	source.interact(player, Balance.TRANSFER_TIME)
	source.interact(player, Balance.TRANSFER_TIME)
	check(player.inventory.get("scrap", 0) == 2 and game.expedition._capture_stock() == before, "Ordinary withdrawal moves exactly two scrap units from actual storage")
	player.position = furnace.position + Vector2(-30, 0)
	furnace.interact(player, Balance.TRANSFER_TIME)
	check(furnace.input_amount == 1 and player.inventory.get("scrap", 0) == 1, "Actual furnace accepts its documented finite scrap alternative")
	check(game.expedition._capture_stock() == before, "Partially loaded furnace preserves the original material kind in campaign stock")
	furnace.interact(player, Balance.TRANSFER_TIME)
	furnace._process(0.01)
	check(furnace.working and player.inventory.is_empty(), "Actual furnace begins a fully paid scrap batch")
	check(game.expedition._capture_stock() == before, "Unfinished furnace batch preserves scrap instead of manufacturing raw ore")
	game.rounds.wave = Balance.TOTAL_WAVES
	check(game.expedition.on_victory(), "Real victory secures an unfinished alternative-input batch")
	check(game.expedition._capture_stock() == before, "Committed victory recovers the exact original finite ingredients")
	check(furnace.input_scrap == 0 and furnace.working_scrap == 0 and not furnace.working, "Committed ownership transfer clears all alternative-input provenance exactly once")
	game.upgrades.points = 20
	check(game.upgrades.purchase("bunker_workshop") and game.upgrades.purchase("medic_logistics"), "SAN feeding research is actually purchased with finite points")
	player.position = source.position + Vector2(-28, 0)
	source.interact(player, Balance.TRANSFER_TIME)
	player.position = furnace.position + Vector2(-30, 0)
	furnace.interact(player, Balance.TRANSFER_TIME)
	var medic = game.medic
	medic.position = source.position + Vector2(-28, 0)
	medic.logistics.source = source
	medic.logistics.station = furnace
	medic.logistics._resource = "scrap"
	medic.logistics_phase = "collect"
	medic.logistics._handoff(source)
	check(medic.logistics_cargo == "scrap" and game.expedition._capture_stock() == before, "Actual SAN pickup owns exactly one remaining finite scrap unit")
	medic.position = furnace.position + Vector2(-30, 0)
	medic.logistics._handoff(furnace)
	check(medic.logistics_cargo.is_empty() and furnace.input_amount == 2 and furnace.input_scrap == 2 and game.expedition._capture_stock() == before, "Actual SAN delivery retains scrap identity beside a manually deposited unit")
	furnace._process(0.01)
	check(furnace.working_scrap == 2 and furnace.input_scrap == 0, "Actual all-scrap batch transfers provenance from its buffer into paid work")
	furnace._process(furnace.duration())
	check(not furnace.working and furnace.output_amount == 2 and furnace.working_scrap == 0, "Completed production consumes scrap into steel once and clears paid-input provenance")
	player.position = furnace.position + Vector2(-30, 0)
	furnace.interact(player, Balance.TRANSFER_TIME)
	furnace.interact(player, Balance.TRANSFER_TIME)
	var steel: Supply
	for crate in get_nodes_in_group("supplies"):
		if crate.game == game and crate.kind == "steel":
			steel = crate
			break
	player.position = steel.position + Vector2(-28, 0)
	player.selected_kind = "steel"
	steel.deposit(player, Balance.TRANSFER_TIME)
	steel.deposit(player, Balance.TRANSFER_TIME)
	check(furnace.output_amount == 0 and player.inventory.is_empty() and int(game.expedition._capture_stock().get("steel",0)) == int(before.get("steel",0)) + 2, "Real collection and storage retain both manufactured steel products")
	var ore: Supply = game.expedition._new_supply("ore", 1, 0)
	source.amount = 1
	var mixed_before: Dictionary = game.expedition._capture_stock()
	for crate: Supply in [source, ore]:
		player.position = crate.position + Vector2(-28, 0)
		crate.interact(player, Balance.TRANSFER_TIME)
		player.position = furnace.position + Vector2(-30, 0)
		furnace.interact(player, Balance.TRANSFER_TIME)
	check(furnace.input_amount == 2 and furnace.input_scrap == 1 and game.expedition._capture_stock() == mixed_before, "Mixed ore/scrap buffer preserves both exact original material types")
	var guest = load("res://scenes/main.tscn").instantiate()
	root.add_child(guest)
	guest.network.set_physics_process(false)
	guest.network.active = true
	guest.network.is_host = false
	guest.start_scenario(1, game.scenario_options)
	var guest_world := World.new()
	guest_world.bind(guest)
	var buffered: Dictionary = host_world.capture()
	check(guest_world.apply(buffered) and guest.expedition._capture_stock() == mixed_before, "Actual host snapshot preserves a mixed buffered recipe on its guest: " + guest_world.last_error)
	furnace._process(0.01)
	check(furnace.working and furnace.working_scrap == 1 and furnace.input_scrap == 0 and game.expedition._capture_stock() == mixed_before, "Mixed batch records one finite scrap unit and one finite ore unit during production")
	var working: Dictionary = host_world.capture()
	check(guest_world.apply(working) and guest.expedition._capture_stock() == mixed_before, "Actual host snapshot preserves the paid mixed batch on its guest: " + guest_world.last_error)
	var replica: ProductionStation
	for station in get_nodes_in_group("stations"):
		if station.game == guest and station.kind == "furnace":
			replica = station
	check(is_instance_valid(replica) and replica.input_scrap == 0 and replica.working_scrap == 1 and replica.working, "Guest machine receives the exact bounded paid-input provenance fields")
	check(guest_world.apply(working) and guest.expedition._capture_stock() == mixed_before, "Repeated authoritative mixed snapshot cannot credit a second raw ingredient")
	paused = false
	await Cleanup.free_scene(guest, self)
	paused = false
	await Cleanup.free_scene(game, self)
	print("FURNACE MATERIAL CHECKS: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
