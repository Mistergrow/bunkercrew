extends SceneTree
## An actually open native WebSocket cannot block retry after game silence.
const Cleanup := preload("res://tests/scene_cleanup.gd")
class SessionProbe extends "res://scripts/network_session.gd":
	var resume_attempts := 0
	func _connect_relay(action: String) -> void:
		if action == "resume": resume_attempts += 1
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
	return value

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	var listener := TCPServer.new()
	if not check(listener.listen(25487, "127.0.0.1") == OK, "Private native TCP listener starts on loopback"): quit(1); return
	var client := WebSocketPeer.new()
	var server := WebSocketPeer.new()
	check(client.connect_to_url("ws://127.0.0.1:25487/ws") == OK, "Native WebSocket client opens its private local connection")
	var accepted := false
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		if not accepted and listener.is_connection_available():
			check(server.accept_stream(listener.take_connection()) == OK, "Native WebSocket server accepts the actual TCP stream")
			accepted = true
		client.poll()
		if accepted: server.poll()
		if client.get_ready_state() == WebSocketPeer.STATE_OPEN and server.get_ready_state() == WebSocketPeer.STATE_OPEN: break
		await process_frame
	if not check(client.get_ready_state() == WebSocketPeer.STATE_OPEN and server.get_ready_state() == WebSocketPeer.STATE_OPEN, "Both native sockets have actually completed the WebSocket upgrade"):
		listener.stop(); quit(1); return
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	game.start_scenario(1, {"environment": "ash_foundry", "build_type": "bastion", "position": "left"})
	game.rounds.running = false
	var session := SessionProbe.new()
	game.add_child(session)
	session.game = game
	session.set_process(false)
	session.set_physics_process(false)
	session.active = true
	session.is_host = false
	session.state = "playing"
	session.peer_connected = true
	session._authenticated = true
	session.relay_url = "ws://127.0.0.1:25487/ws"
	session._websocket = client
	session._relay_requested = true
	session._relay_resume_token = "test-existing-resume-token-32abcd"
	session._last_packet_at = 0
	session._clock = 6
	session._clock_updated_usec = Time.get_ticks_usec()
	session._process(0)
	check(session.state == "reconnecting" and paused, "Actual five-second game-silence path pauses and enters reconnect even while TCP remains open")
	check(session._websocket == null, "Timed-out open WebSocket is retired instead of preventing a resume attempt")
	check(session._relay_resume_token == "test-existing-resume-token-32abcd", "Socket retirement preserves the authenticated room's resume identity")
	session._clock = session._retry_at + .01
	session._clock_updated_usec = Time.get_ticks_usec()
	session._process(0)
	check(session.resume_attempts == 1, "Next real retry deadline schedules exactly one resume with the old socket detached")
	session.leave()
	paused = false
	server.close()
	client.close()
	listener.stop()
	var until := Time.get_ticks_msec() + 2300
	while Time.get_ticks_msec() < until:
		server.poll()
		client.poll()
		await process_frame
	check(await Cleanup.free_scene(game, self), "Native pair, silence recovery and actual game/audio release cleanly")
	print("NETWORK RELAY SILENCE: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
