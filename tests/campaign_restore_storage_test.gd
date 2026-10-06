extends SceneTree
## Repeated fresh deployment in one Game must deliver once per physical world.
const Cleanup = preload("res://tests/scene_cleanup.gd")
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("RESTORE STORAGE ", "PASS " if ok else "FAIL ", label)
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

func run():
	if not "--no-profile-save" in OS.get_cmdline_user_args() or not "--no-upnp" in OS.get_cmdline_user_args():
		quit(2)
		return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start_scenario(1, {"environment":"ash_foundry", "position":"left", "build_type":"bastion"})
	freeze()
	for frame in 3:
		await physics_frame
	var baseline: Dictionary = game.expedition._capture_stock()
	game.rounds.wave = Balance.TOTAL_WAVES
	check(game.expedition.on_victory(), "Real victory establishes completed entry for an actual deployment checkpoint")
	var state: CampaignState = game.campaign
	state.expedition.vehicle.cargo = {"steel":2, "glass":1}
	check(state.select_destination("harbor") and not state.begin_journey().is_empty() and state.arrive_at_destination() and state.secure_destination(), "Actual campaign operations create a finite transported defense payload")
	var checkpoint: Dictionary = state.checkpoint()
	var options: Dictionary = checkpoint.options.duplicate()
	options.environment = "abandoned_harbor"
	var payload := {"checkpoint":checkpoint, "mode":"defense", "options":options}
	var expected: Dictionary = baseline.duplicate()
	expected.steel = int(expected.get("steel", 0)) + 2
	expected.glass = int(expected.get("glass", 0)) + 1
	for iteration in 3:
		game.started = false
		check(game.expedition.restore(payload), "Actual same-instance fresh deployment accepted, pass %d" % iteration)
		freeze()
		check(game.expedition._capture_stock() == expected, "Fresh physical world receives finite cargo once, pass %d" % iteration)
		game.expedition._apply_delivery()
		check(game.expedition._capture_stock() == expected, "Repeated delivery within one world cannot duplicate cargo, pass %d" % iteration)
	var current: Dictionary = game.campaign.checkpoint()
	var physical: Dictionary = game.expedition._capture_stock()
	check(not game.expedition.restore(payload), "Restore refuses an already-started physical world")
	check(game.campaign.checkpoint() == current and game.expedition._capture_stock() == physical and game.campaign.mission_running, "Refused live-world restore cannot replace campaign ownership or clear active mission")
	paused = false
	await Cleanup.free_scene(game, self)
	print("RESTORE STORAGE CHECKS: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
