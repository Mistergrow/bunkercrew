extends SceneTree
## Prepared live-game boundary states travel through the real packet decoder.
const PROTOCOL := preload("res://scripts/network_protocol.gd")
const CLEANUP := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
var game

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func deliver(message: Dictionary) -> void:
	var bytes := PROTOCOL.encode(message)
	check(not bytes.is_empty(), "Fixture uses the real compressed network protocol")
	game.network._packet(bytes)

func input_packet(generation: int, sequence: int, action: String) -> Dictionary:
	return {"kind":"input", "generation":generation, "seq":sequence, "input":{
		"held":{action:1.0}, "pressed":[action], "released":[], "aim":[700.0, 250.0], "mouse":true}}

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.start_scenario(2, {"environment":"sector07", "build_type":"workshop", "position":"left"})
	var session = game.network
	session.set_process(false)
	session.set_physics_process(false)
	session.active = true
	session.is_host = true
	session.peer_connected = true
	session._authenticated = true
	session.state = "playing"
	session._generation = 4
	deliver(input_packet(4, 900, "right"))
	session._physics_process(1.0 / 60.0)
	check(session.remote_input.get("held", {}).has("right"), "Current match guest input reaches the host")
	# Same session/socket, as in an actual F5 rematch; the old frame remains in flight.
	session._generation = 5
	session._match_characters = ["mara", "branko"]
	session._pressed = ["jump"]
	session._released = ["drop"]
	session._local_pressed = ["reload"]
	session._local_released = ["interact"]
	session._begin_local_match()
	check(session.remote_input.is_empty() and session._pending_remote.is_empty(), "Starting a match clears old held movement")
	check(session._pressed.is_empty() and session._released.is_empty() and session._local_pressed.is_empty() and session._local_released.is_empty(), "Starting a match clears queued action edges")
	deliver(input_packet(4, 901, "fire"))
	check(session._remote_seq == -1 and session._pending_remote.is_empty(), "Delayed previous-match input cannot consume a new sequence number")
	deliver(input_packet(5, 1, "left"))
	session._loading = false
	session.match_paused = false
	paused = false
	session._physics_process(1.0 / 60.0)
	check(session._remote_seq == 1 and session.remote_input.get("held", {}).has("left") and not session.remote_input.get("held", {}).has("fire"), "First input of the new match works immediately after a delayed old packet")
	var missing_generation := input_packet(5, 2, "jump")
	missing_generation.erase("generation")
	deliver(missing_generation)
	check(session._remote_seq == 1, "Input without a match generation is rejected")
	for invalid_generation in [true, 5.0, "5", null]:
		var invalid := input_packet(5, 2, "jump")
		invalid.generation = invalid_generation
		deliver(invalid)
		check(session._remote_seq == 1, "Invalid generation types cannot consume an input sequence")
	deliver(input_packet(5, 2, "reload"))
	session._physics_process(1.0 / 60.0)
	check("reload" in session.remote_input.get("pressed", []), "A valid action still arrives after rejected inputs")
	session._physics_process(1.0 / 60.0)
	check(session.remote_input.get("pressed", []).is_empty(), "An accepted action edge is consumed only once")
	# A reconnecting guest legitimately sends ready even if the match just ended.
	for phase in ["victory", "defeat"]:
		game.rounds.phase = phase
		game.hud.overlay = "network"
		session.state = "reconnecting"
		session._loading = true
		session.match_paused = true
		paused = true
		deliver({"kind":"ready", "generation":5})
		check(session.state == "playing" and session._ready_for_snapshots and not session._loading, "Reconnect completes after " + phase)
		game.hud._process(0.0)
		await process_frame
		check(session.match_paused and paused and game.hud.overlay == phase, "Reconnect preserves the finished " + phase + " screen and frozen simulation")
		session.pause_match(false)
		check(session.match_paused and paused and game.hud.overlay == phase, "Late resume cannot restart a finished " + phase + " simulation")
	game.rounds.phase = "build"
	game.hud.overlay = "network"
	session._loading = true
	deliver({"kind":"ready", "generation":5})
	check(not paused and not session.match_paused and game.hud.overlay.is_empty(), "A live match still resumes normally after reconnect")
	# The guest restores its result from the authoritative snapshot after ready.
	session.is_host = false
	session.local_player_id = 2
	var sequence := 0
	for phase in ["victory", "defeat"]:
		game.rounds.phase = phase
		var finished_world: Dictionary = session.world.capture()
		game.hud.overlay = "network"
		session.state = "reconnecting"
		session._loading = true
		sequence += 1
		deliver({"kind":"snapshot", "generation":5, "seq":sequence, "world":finished_world, "paused":true})
		game.hud._process(0.0)
		await process_frame
		check(session.state == "playing" and paused and session.match_paused and game.hud.overlay == phase, "Guest restores " + phase + " through its next HUD frame")
		deliver({"kind":"pause", "paused":false,"generation":5})
		check(paused and session.match_paused and game.hud.overlay == phase, "A late guest resume cannot dismiss " + phase)
	# A pre-fix client must receive an explicit build rejection, never join
	# successfully with old input frames that lack the mandatory generation.
	session.is_host = true
	session._authenticated = false
	deliver({"kind":"hello", "version":PROTOCOL.VERSION, "build":"lastshift-net-1", "resume":""})
	check(session._rejecting and not session._authenticated, "Old clients are explicitly rejected by the build handshake")
	session.leave()
	paused = false
	check(await CLEANUP.free_scene(game, self), "Prepared session releases its scene and audio")
	print("NETWORK LIFECYCLE BOUNDARIES: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
