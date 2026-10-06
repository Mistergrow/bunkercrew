extends SceneTree
## Real rejected NetworkSession transitions must leave the current world playable.
const Cleanup = preload("res://tests/scene_cleanup.gd")
const Storage = preload("res://scripts/medic_storage.gd")
const Journey = preload("res://scripts/convoy_journey.gd")
var game
var checks := 0
var failures := 0
var isolated_path := "user://transition-rollback-%d.json" % OS.get_process_id()

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("TRANSITION ROLLBACK ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1
		push_error(label)

func freeze() -> void:
	paused = true
	game.rounds.running = false
	game.rounds.set_process(false)
	game.expedition.set_physics_process(false)
	game.medic.set_physics_process(false)
	for player in game.players:
		player.set_physics_process(false)
	for station in get_nodes_in_group("stations"):
		if station.game == game:
			station.set_process(false)

func mission_records() -> Dictionary:
	var state: CampaignState = game.campaign
	return {"id":state.mission_id, "running":state.mission_running, "salvage":state.mission_salvage, "issued":state._issued.duplicate(), "collected":state._collected.duplicate()}

func configure_rejection() -> void:
	game.network.set_physics_process(false)
	game.network.active = true
	game.network.is_host = true
	game.network.state = "playing"
	game.network._loading = false
	# The real network transition refuses mismatched session topology before
	# touching its transport, generation or scene. No mocked return function.
	game.network._match_player_count = game.player_count + 1

func run():
	if not "--no-profile-save" in OS.get_cmdline_user_args() or not "--no-upnp" in OS.get_cmdline_user_args():
		quit(2)
		return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start_scenario(1, {"environment":"ash_foundry", "build_type":"bastion", "position":"left"})
	freeze()
	for frame in 3:
		await physics_frame
	game.campaign.save_path = isolated_path
	game.campaign.persistence_enabled = true
	game.rounds.wave = Balance.TOTAL_WAVES
	check(game.expedition.on_victory(), "Real victory establishes an isolated durable preparation checkpoint")
	game.campaign.expedition.garage_stock = {"sand":100000, "steel":4, "scrap":4}
	game.expedition._mirror_stock()
	check(game.expedition.handle_command("prepare", {}, 1), "Actual garage prepares the live convoy")
	check(game.expedition.handle_command("route", {"id":"harbor"}, 1), "Actual route selection commits an available destination")
	check(game.expedition.handle_command("load", {"kind":"steel", "amount":2}, 1), "Actual loading transfers finite steel into convoy cargo")
	configure_rejection()
	var before: Dictionary = game.campaign.checkpoint()
	var physical: Dictionary = game.expedition._capture_stock()
	var reserves: Dictionary = Storage.reserved(game)
	var vehicle_data: Dictionary = game.expedition.vehicle.vehicle_data()
	check(game.expedition.handle_command("depart", {}, 1), "Departure begins visible garage boarding before a scene transition")
	game.expedition.vehicle.set_physics_process(false)
	game.players[0].position=game.expedition.vehicle.position
	check(game.expedition.vehicle.board(game.players[0]), "Real driver boards before the rejected handoff")
	check(not game.expedition._launch_journey(), "Rejected real network transition reports failed departure")
	check(game.expedition.can_manage() and game.campaign.checkpoint() == before and not game.expedition.transitioning and not game._restart_pending, "Rejected departure preserves preparation state instead of stranding the garage in travel")
	check(game.expedition._capture_stock() == physical and Storage.reserved(game) == reserves and game.expedition.vehicle.vehicle_data() == vehicle_data, "Rejected departure changes no reserve, physical store or convoy cargo")
	var saved := CampaignState.new(isolated_path, false)
	saved.persistence_enabled = true
	check(saved.load_checkpoint() and JSON.parse_string(JSON.stringify(saved.checkpoint())) == JSON.parse_string(JSON.stringify(before)), "Rejected departure restores its actual durable checkpoint")
	# Read a real valid travel checkpoint, then make its retry fail at the same
	# actual network boundary. Cargo and claimed route rewards remain untouched.
	game.campaign._restore(before)
	check(not game.campaign.begin_journey().is_empty(), "Real journey state provides a valid retry fixture")
	game.campaign.fail_journey()
	var failed: Dictionary = game.campaign.checkpoint()
	check(not game.expedition.handle_command("retry", {}, 1), "Rejected real retry reports failure")
	check(game.campaign.checkpoint() == failed and game.expedition.can_retry_journey(), "Rejected retry retains the previous retry boundary and finite cargo")
	check(not game.expedition.handle_command("garage", {}, 1), "Rejected actual return-to-garage handoff reports failure")
	check(game.campaign.checkpoint()==failed and game.expedition.can_retry_journey() and game.expedition._capture_stock()==physical, "Rejected garage return retains the retry checkpoint and all finite warehouse ownership")
	var bad_path := "user://missing-convoy-directory-%d/campaign.json" % OS.get_process_id()
	game.campaign.save_path=bad_path
	check(not game.expedition.handle_command("garage",{},1), "An unwritable garage checkpoint refuses the transition")
	check(game.campaign.checkpoint()==failed and not game.expedition.transitioning and not game._restart_pending and game.expedition._capture_stock()==physical, "Failed garage save rolls back finite campaign and world ownership")
	game.campaign.save_path=isolated_path
	game.campaign._restore(before)
	game.campaign.begin_journey()
	game.expedition.route = CampaignCatalog.journey(game.campaign.pending_node)
	game.expedition.ambushes = int(game.expedition.route.ambushes)
	game.expedition.vehicle.journey_state=Journey.new_state("driving",true)
	game.expedition.vehicle.driving_enabled=true
	game.expedition.vehicle.position.x = game.expedition.ROAD_END
	var travel: Dictionary = game.campaign.checkpoint()
	game.expedition._physics_process(0.02)
	check(game.campaign.checkpoint() == travel and game.expedition.stage == "travel" and not game.expedition.transitioning and not game._restart_pending, "Rejected arrival keeps the live convoy in travel for a later accepted handoff")
	check(game.expedition.vehicle.journey_state.phase=="driving" and game.expedition.vehicle.driving_enabled, "Rejected arrival keeps live motion available instead of stranding a complete-phase van")
	check(game.expedition._capture_stock() == physical and game.expedition.vehicle.vehicle_data() == vehicle_data, "Rejected arrival cannot swallow old warehouse ownership or truck cargo")
	check(not game.combat_events.unlocked.has("convoy_route"), "Rejected arrival cannot award a completed-route achievement")
	# Retrying an active defense also owns a finite in-progress salvage ledger.
	game.campaign._restore(before)
	game.campaign.expedition = CampaignState.new_expedition()
	game.campaign.pending_node = "harbor"
	game.campaign.mission_start()
	check(game.campaign.reserve_drop("finite-inflight", 1) and game.campaign.collect_salvage("finite-inflight", 1), "Active real mission has issued and collected finite salvage")
	var defense: Dictionary = game.campaign.checkpoint()
	var mission: Dictionary = mission_records()
	check(not game.expedition.retry_defense(), "Rejected real defense restart reports failure")
	check(game.campaign.checkpoint() == defense and mission_records() == mission, "Rejected restart preserves live mission ID, salvage and claimed drop records")
	game.network.active = false
	paused = false
	await Cleanup.free_scene(game, self)
	for suffix: String in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(isolated_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(isolated_path + suffix))
	print("TRANSITION ROLLBACK CHECKS: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
