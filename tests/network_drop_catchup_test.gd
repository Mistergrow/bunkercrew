extends SceneTree
## A reliable press and release received in one poll must still perform a tap.
const Protocol := preload("res://scripts/network_protocol.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	game.start_scenario(2, {"environment": "ash_foundry", "build_type": "bastion", "position": "left"})
	game.rounds.running = false
	var network = game.network
	network.leave()
	network.set_process(false)
	network.set_physics_process(false)
	network.active = true
	network.is_host = true
	network.state = "playing"
	network._authenticated = true
	network._generation = 12
	network._clock = 10
	network._loading = false
	network.match_paused = false
	var worker = game.players[1]
	worker.set_physics_process(false)
	worker.inventory = {"steel": 2}
	worker.selected_kind = "steel"
	worker.global_position = Vector2(1000, 430)
	await physics_frame
	await process_frame
	for sequence: int in [1, 2, 3, 4]:
		var press: bool = sequence % 2 == 1
		network._packet(Protocol.encode({"kind": "input", "generation": 12, "seq": sequence,
			"input": {"held": {"drop": 1.0} if press else {}, "pressed": ["drop"] if press else [], "released": [] if press else ["drop"], "aim": [1500, 390], "mouse": true}}))
	check(network._remote_seq == 4 and network._input_edges.size() == 4, "Both real press/release taps arrive and queue their separate action frames")
	network._physics_process(1.0 / 60)
	worker._update_material_controls(1.0 / 60)
	check(worker._drop_held and worker.carried_count() == 2, "Queued press starts one real drop tap despite already receiving its release")
	network._physics_process(1.0 / 60)
	worker._update_material_controls(1.0 / 60)
	check(not worker._drop_held and worker.carried_count() == 1, "Queued release performs its actual one-unit drop exactly once")
	network._physics_process(1.0 / 60)
	worker._update_material_controls(1.0 / 60)
	network._physics_process(1.0 / 60)
	worker._update_material_controls(1.0 / 60)
	check(worker.inventory.is_empty(), "Second separately numbered press/release tap also drops its own carried unit")
	await process_frame
	var dropped := 0
	for pickup in get_nodes_in_group("pickups"):
		if pickup.game == game and pickup.kind == "steel": dropped += int(pickup.amount)
	check(dropped == 2, "Both original finite units become real world pickups without loss or duplication")
	network._physics_process(1.0 / 60)
	worker._update_material_controls(1.0 / 60)
	check(not worker._drop_held and network._input_edges.is_empty(), "Drained drop taps cannot replay after their releases")
	# The newest state may already be another held press. The earlier queued
	# release must still finish its own tap before that new hold begins.
	worker.inventory = {"steel": 3}
	worker.selected_kind = "steel"
	for sequence: int in [5, 6, 7]:
		var press: bool = sequence % 2 == 1
		network._packet(Protocol.encode({"kind": "input", "generation": 12, "seq": sequence,
			"input": {"held": {"drop": 1.0} if press else {}, "pressed": ["drop"] if press else [], "released": [] if press else ["drop"], "aim": [1500, 390], "mouse": true}}))
	network._physics_process(1.0 / 60)
	worker._update_material_controls(1.0 / 60)
	network._physics_process(1.0 / 60)
	worker._update_material_controls(1.0 / 60)
	check(worker.carried_count() == 2 and not worker._drop_held, "Earlier queued release drops exactly one unit even when the latest state is a new held press")
	network._physics_process(1.0 / 60)
	worker._update_material_controls(1.0 / 60)
	check(worker._drop_held and worker.carried_count() == 2, "Following held press begins its own independent tap without repeating the previous release")
	network._packet(Protocol.encode({"kind": "input", "generation": 12, "seq": 8,
		"input": {"held": {}, "pressed": [], "released": ["drop"], "aim": [1500, 390], "mouse": true}}))
	network._physics_process(1.0 / 60)
	worker._update_material_controls(1.0 / 60)
	await process_frame
	dropped = 0
	for pickup in get_nodes_in_group("pickups"):
		if pickup.game == game and pickup.kind == "steel": dropped += int(pickup.amount)
	check(worker.carried_count() == 1 and dropped == 4, "Overlapping catch-up taps preserve all five prepared units as four real pickups and one carried unit")
	network.leave()
	check(await Cleanup.free_scene(game, self), "Drop catch-up fixture releases real actors and pickups")
	print("NETWORK DROP CATCHUP: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
