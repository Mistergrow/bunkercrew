extends SceneTree
## Welcome and Start can arrive in separate polls after actual authentication.
const Protocol := preload("res://scripts/network_protocol.gd")
const Messages := preload("res://scripts/network_messages.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	game.start_scenario(2, {"environment":"ash_foundry", "build_type":"workshop", "position":"left"})
	game.rounds.running = false
	var session = game.network
	session.leave()
	session.set_process(false)
	session.set_physics_process(false)
	session.active = true
	session.is_host = false
	session.state = "reconnecting"
	session._generation = 1
	session._clock = 10
	session._reconnect_deadline = 40
	session._retry_at = 20
	# The native connection establishes liveness before issuing its Hello.
	session._connected()
	var welcome := {"kind":"welcome", "version":Protocol.VERSION, "build":Protocol.BUILD, "world_revision":Protocol.WORLD_REVISION, "content_fingerprint":preload("res://scripts/content_registry.gd").fingerprint(), "token":"a".repeat(48), "player_id":2, "options":game.scenario_options, "characters":game.selected_characters, "story":false, "count":2, "capacity":4, "slots":[1, 2]}
	check(Messages.valid(welcome, false), "Fixture decodes the actual current Welcome schema")
	session._packet(Protocol.encode(welcome))
	check(session._authenticated and session.state == "reconnecting" and session._reconnect_deadline == 40, "Welcome authenticates while retaining the original bounded reconnect deadline")
	session._process(0)
	check(session.state != "error" and session._authenticated, "A separate poll before Start cannot interpret cleared deadline0 as an expired30s reconnect")
	var native_host: NetworkTransport
	if session.state != "error":
		# A confirmed direct link must survive a retry becoming due while the
		# authoritative Start packet is still waiting for its next frame.
		native_host = NetworkTransport.new()
		root.add_child(native_host)
		native_host.set_process(false)
		check(native_host.host(39849, false) == OK, "Direct admission fixture opens its isolated actual UDP port")
		session._address = "127.0.0.1"
		session._port = 39849
		session._make_transport()
		session.transport.set_process(false)
		check(session.transport.join(session._address, session._port) == OK, "Actual direct guest connects before its authenticated world packet")
		var connected_until := Time.get_ticks_usec() + 2000000
		while (not session.transport.can_send_to() or not native_host.can_send_to()) and Time.get_ticks_usec() < connected_until:
			native_host._process(0)
			session.transport._process(0)
			await process_frame
		var authenticated_transport = session.transport
		check(authenticated_transport.can_send_to() and native_host.can_send_to(), "Both confirmed actual UDP links are available before the due retry")
		session._retry_at = 0
		session._process(0)
		check(session.transport == authenticated_transport and authenticated_transport.can_send_to() and session._authenticated and session._reconnect_deadline == 40, "Due direct retry preserves the authenticated native link and its original deadline")
		var start := {"kind":"start", "generation":1, "options":game.scenario_options, "characters":game.selected_characters, "story":false, "count":2, "capacity":4, "slots":[1, 2], "reset":false}
		session._packet(Protocol.encode(start))
		check(session.state == "playing" and session._loading and session._reconnect_deadline == 0 and session._load_deadline > session._clock, "Actual Start switches to the existing loading deadline and clears completed admission")
		check(session.world != null and session.world.client and not game.players[1].is_physics_processing(), "Existing guest world is re-bound as a frozen authoritative replica")
	session.leave()
	if is_instance_valid(native_host):
		native_host.close()
		native_host.free()
	paused = false
	check(await Cleanup.free_scene(game, self), "Separated admission releases decoder worker, audio and scene")
	print("NETWORK RECONNECT ADMISSION: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
