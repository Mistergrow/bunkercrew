extends SceneTree
## An existing legal 100000-unit save must remain usable after real production.
const Cleanup = preload("res://tests/scene_cleanup.gd")
const World = preload("res://scripts/network_world.gd")
var game
var checks := 0
var failures := 0
var path := "user://warehouse-production-%d.json" % OS.get_process_id()

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("WAREHOUSE PRODUCTION ", "PASS " if ok else "FAIL ", label)
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
	var host_world := World.new()
	host_world.bind(game)
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
	game.rounds.wave = Balance.TOTAL_WAVES
	check(game.expedition.on_victory(), "Real victory creates a valid preparation checkpoint")
	game.campaign.save_path = path
	game.campaign.persistence_enabled = true
	game.campaign.expedition.garage_stock = {"steel":100000, "ore":2}
	game.expedition._mirror_stock()
	check(game.campaign.save_checkpoint(), "Existing legal 100000 steel and two finite ore are durably saved")
	var ore: Supply
	var furnace: ProductionStation
	for crate in get_nodes_in_group("supplies"):
		if crate.game == game and crate.kind == "ore":
			ore = crate
	for station in get_nodes_in_group("stations"):
		if station.game == game and station.kind == "furnace":
			furnace = station
	var player = game.players[0]
	player.position = ore.position + Vector2(-28, 0)
	ore.interact(player, Balance.TRANSFER_TIME)
	ore.interact(player, Balance.TRANSFER_TIME)
	player.position = furnace.position + Vector2(-30, 0)
	furnace.interact(player, Balance.TRANSFER_TIME)
	furnace.interact(player, Balance.TRANSFER_TIME)
	furnace._process(0.01)
	check(furnace.working and player.inventory.is_empty(), "Real transfers pay both finite ingredients into actual furnace work")
	furnace._process(furnace.duration())
	var stock: Dictionary = game.expedition._capture_stock()
	check(int(stock.get("steel",0)) == 100002 and int(stock.get("ore",0)) == 0, "Actual production converts both ore units without dropping the two steel products")
	check(CampaignState.valid_stock(stock), "Normal production beyond the old per-material save threshold remains persistable")
	var snapshot: Dictionary = game.expedition.capture_state()
	check(int(snapshot.checkpoint.expedition.garage_stock.get("steel",0)) == 100002, "Current snapshot ledger includes both real products instead of retaining stale stock")
	check(game.campaign.save_checkpoint(), "Finite produced surplus saves into the isolated actual checkpoint")
	var restored := CampaignState.new(path, false)
	restored.persistence_enabled = true
	check(restored.load_checkpoint() and int(restored.expedition.garage_stock.get("steel",0)) == 100002, "Actual reload preserves the new manufactured surplus")
	check(game.expedition.handle_command("load", {"kind":"steel", "amount":1}, 1), "Ordinary garage operation remains usable after real production")
	check(int(game.expedition._capture_stock().get("steel",0)) == 100001 and int(game.campaign.expedition.vehicle.cargo.get("steel",0)) == 1, "Loading the produced surplus transfers ownership once without truncation")
	game.expedition._mirror_stock()
	check(int(game.expedition._capture_stock().get("steel",0)) == 100001 and furnace.output_amount == 0, "Committed production mirrors into accessible storage once and clears its old machine ownership")
	var world_snapshot: Dictionary = host_world.capture()
	var guest = load("res://scenes/main.tscn").instantiate()
	root.add_child(guest)
	guest.network.set_physics_process(false)
	guest.network.active = true
	guest.network.is_host = false
	guest.start_scenario(1, game.scenario_options)
	var guest_world := World.new()
	guest_world.bind(guest)
	check(guest_world.apply(world_snapshot), "Actual host snapshot accepts the naturally manufactured surplus: " + guest_world.last_error)
	check(int(guest.expedition._capture_stock().get("steel",0)) == 100001 and int(guest.campaign.expedition.vehicle.cargo.get("steel",0)) == 1, "Actual guest owns the complete mirrored surplus plus the one loaded unit")
	check(guest_world.apply(world_snapshot) and int(guest.expedition._capture_stock().get("steel",0)) == 100001, "Repeated actual guest snapshot cannot duplicate the manufactured surplus")
	paused = false
	await Cleanup.free_scene(guest, self)
	guest_world = null
	host_world = null
	await Cleanup.free_scene(game, self)
	for suffix: String in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("WAREHOUSE PRODUCTION CHECKS: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
