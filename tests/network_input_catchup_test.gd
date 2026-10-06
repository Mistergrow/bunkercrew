extends SceneTree
## Multiple separately numbered reliable taps may arrive in one network poll.
## Their actual gameplay actions must remain separate across physics ticks.
const Protocol := preload("res://scripts/network_protocol.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const PeerState := preload("res://scripts/network_peer_state.gd")
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
	game.upgrades.owned.shotgun = true
	var network = game.network
	network.leave()
	network.set_process(false)
	network.set_physics_process(false)
	network.active = true
	network.is_host = true
	network.state = "playing"
	network._authenticated = true
	network._generation = 41
	network._clock = 10
	network._loading = false
	network.match_paused = false
	var worker = game.players[1]
	worker.set_physics_process(false)
	var weapon = worker.get_node("WorkerWeapon")
	weapon.set_physics_process(false)
	weapon.weapon_kind = "rifle"
	for sequence in [1, 2]:
		network._packet(Protocol.encode({"kind": "input", "generation": 41, "seq": sequence,
			"input": {"held": {}, "pressed": ["cycle_weapon"], "released": [], "aim": [1500, 390], "mouse": true}}))
	check(network._remote_seq == 2, "Both separate authenticated reliable input packets are decoded")
	network._physics_process(1.0 / 60)
	weapon._physics_process(1.0 / 60)
	check(weapon.weapon_kind == "shotgun", "First independently numbered tap changes the actual weapon once")
	network._physics_process(1.0 / 60)
	weapon._physics_process(1.0 / 60)
	check(weapon.weapon_kind == "rifle", "Second tap received in the same poll survives for its own actual gameplay action")
	network._physics_process(1.0 / 60)
	weapon._physics_process(1.0 / 60)
	check(weapon.weapon_kind == "rifle", "The drained catch-up queue never replays an acknowledged action")
	# A paused tap cannot become a surprising action when gameplay resumes.
	network._set_pause(true)
	network._packet(packet(3, 41, ["cycle_weapon"]))
	check(network._input_edges.is_empty(), "Inputs received during shared pause cannot queue gameplay taps")
	network._set_pause(false)
	network._physics_process(1.0 / 60)
	weapon._physics_process(1.0 / 60)
	check(weapon.weapon_kind == "rifle", "Resuming does not execute a tap received while paused")
	# A queued valid tap becoming stale must not be revived by fresh held input.
	network._clock = 10
	network._packet(packet(4, 41, ["cycle_weapon"]))
	check(network._input_edges.size() == 1, "Valid unconsumed input remains in the bounded edge FIFO")
	network._clock = 10.51
	network._physics_process(1.0 / 60)
	check(network._input_edges.is_empty() and network.remote_input.is_empty(), "Actual half-second stale-input policy clears held state and old action FIFO")
	network._packet(packet(5, 41, []))
	network._physics_process(1.0 / 60)
	weapon._physics_process(1.0 / 60)
	check(weapon.weapon_kind == "rifle", "A fresh input packet cannot revive a stale old action")
	network._packet(packet(6, 40, ["cycle_weapon"]))
	check(network._remote_seq == 5 and network._input_edges.is_empty(), "Wrong-generation taps neither queue nor advance authenticated input sequence")
	# One guest's catch-up must never share the other guest's queue.
	for pair: Array in [[20, 2], [30, 3]]:
		var link: Dictionary = PeerState.create(network._clock)
		link.wire = pair[0]
		link.slot = pair[1]
		link._authenticated = true
		link._ready_for_snapshots = true
		network._peers[pair[0]] = link
		network._slots[pair[1]] = link
	network._packet_from(packet(1, 41, ["cycle_weapon"]), 20)
	network._packet_from(packet(2, 41, ["cycle_weapon"]), 20)
	network._packet_from(packet(1, 41, ["jump"]), 30)
	check(network._slots[2]._input_edges.size() == 2 and network._slots[3]._input_edges.size() == 1, "Independent authenticated peers own their own catch-up FIFOs")
	network._physics_process(1.0 / 60)
	weapon._physics_process(1.0 / 60)
	check(network.remote_input_for(2).pressed == ["cycle_weapon"] and network.remote_input_for(3).pressed == ["jump"], "First catch-up step preserves per-peer action identity")
	network._physics_process(1.0 / 60)
	weapon._physics_process(1.0 / 60)
	check(weapon.weapon_kind == "rifle" and network.remote_input_for(3).pressed.is_empty(), "Only the peer with two taps receives a second actual action")
	# A real generation transition flushes both pending per-peer streams.
	network._packet_from(packet(3, 41, ["cycle_weapon"]), 20)
	network._packet_from(packet(2, 41, ["jump"]), 30)
	network._generation = 42
	network._begin_local_match()
	check(network._slots[2]._input_edges.is_empty() and network._slots[3]._input_edges.is_empty() and network._input_edges.is_empty(), "Actual local-match transition flushes old-generation actions for every authenticated peer")
	# Overflow rejects the guilty link explicitly instead of silently discarding
	# an otherwise accepted action or affecting a healthy guest.
	network._loading = false
	network.match_paused = false
	paused = false
	network._enter_peer(20)
	for sequence in range(1, network.MAX_PENDING_INPUT_EDGES + 2):
		network._receive_input({"kind": "input", "generation": 42, "seq": sequence,
			"input": {"held": {}, "pressed": ["cycle_weapon"], "released": [], "aim": [1500, 390], "mouse": true}})
	network._leave_peer()
	check(network._slots[2]._rejecting and network._slots[2]._input_edges.size() <= network.MAX_PENDING_INPUT_EDGES, "Overflow never grows its FIFO beyond the cap and explicitly rejects its own authenticated link")
	check(not network._slots[3]._rejecting and network._slots[3]._input_edges.is_empty(), "A peer overflowing its action queue does not reject or pollute a healthy guest")
	# The agreed provisional two-second catch-up at the maximum normal physics
	# input rate contains 120 reliable frames, rather than an abusive flood.
	network.leave()
	network.active = true
	network.is_host = true
	network.state = "playing"
	network._authenticated = true
	network._generation = 50
	network._remote_seq = -1
	network._clock = 20
	network._loading = false
	network.match_paused = false
	game.hud.overlay = ""
	weapon.weapon_kind = "rifle"
	for sequence in range(1, 121): network._packet(packet(sequence, 50, ["cycle_weapon"]))
	check(network._remote_seq == 120 and network._input_edges.size() == 120 and not network._rejecting, "Two seconds of separately numbered normal 60-Hz input frames survive the real message budget")
	var changes := 0
	for _frame in 120:
		var before: String = weapon.weapon_kind
		network._physics_process(1.0 / 60)
		weapon._physics_process(1.0 / 60)
		if before != weapon.weapon_kind: changes += 1
	check(changes == 120 and network._input_edges.is_empty(), "Every buffered normal action reaches its real weapon once while FIFO stays bounded")
	# During same-generation reconnect a pre-Start input may already be in
	# transit. A locally rebound guest must never restart sequence numbering.
	network.leave()
	network.active = true
	network.is_host = false
	network._authenticated = true
	network.peer_connected = true
	network.state = "playing"
	network._generation = 51
	network._input_seq = 300
	network._begin_local_match()
	check(network._input_seq == 300, "Actual same-generation guest world rebind preserves its already sent input sequence")
	network._loading = false
	network.match_paused = false
	paused = false
	game.hud.overlay = ""
	network._physics_process(1.0 / 30)
	check(network._input_seq == 301, "Next freshly sampled guest input advances beyond all pre-reconnect frames")
	network.leave()
	check(network._input_seq == 0, "Leaving the authenticated session resets its sequence for a new independent room")
	check(await Cleanup.free_scene(game, self), "Real input catch-up fixture releases game, workers and audio")
	print("NETWORK INPUT CATCHUP: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func packet(sequence: int, generation: int, pressed: Array) -> PackedByteArray:
	return Protocol.encode({"kind": "input", "generation": generation, "seq": sequence,
		"input": {"held": {}, "pressed": pressed, "released": [], "aim": [1500, 390], "mouse": true}})
