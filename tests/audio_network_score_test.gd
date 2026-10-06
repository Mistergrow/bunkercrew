extends SceneTree
## Actual host start and its decoded guest packet, with prepared authenticated
## party slots. Captured transport isolates recorded score selection from sockets.
const PROTOCOL := preload("res://scripts/network_protocol.gd")
const PEER_STATE := preload("res://scripts/network_peer_state.gd")
const CLEANUP := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

class CapturedTransport:
	extends Node
	var connected_peer := 2
	var last_packet_channel := 0
	var remote_peers: Dictionary = {2:true}
	var packets: Array[PackedByteArray] = []
	func can_send_to(target: int = 0) -> bool:
		return remote_peers.has(target if target>0 else connected_peer)
	func send(packet: PackedByteArray,_reliable: bool=true,_channel: int=-1,_target: int=0) -> Error:
		packets.append(packet.duplicate())
		return OK
	func flush_departure() -> void: pass
	func close() -> void: pass

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func prepare_game(host: bool) -> Node:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.hud.story_selected = false
	# Native scores have their own integration test. This fixture exercises the
	# documented recording fallback through the same network loading route.
	game.audio.set_live_music_enabled(false)
	var session: Node = game.network
	session.set_process(false)
	session.set_physics_process(false)
	session.active = true
	session.is_host = host
	session.local_player_id = 1 if host else 2
	session.peer_connected = true
	session._authenticated = true
	session._connected_slots = [1,2]
	session.state = "lobby"
	var transport := CapturedTransport.new()
	transport.connected_peer = 2 if host else 1
	transport.remote_peers = {2:true} if host else {1:true}
	session.add_child(transport)
	session.transport = transport
	if host:
		var link := PEER_STATE.create(0.0)
		link.slot = 2
		link.wire = 2
		link._authenticated = true
		session._peers[2] = link
		session._slots[2] = link
	return game

func check_score(game: Node, environment_id: String, score: String, role: String) -> void:
	var session: Node = game.network
	check(game.started and session.state == "playing" and game.players.size() == 2 and game.scenario_options.environment == environment_id, "%s starts the selected %s scenario" % [role, environment_id])
	check(game.audio.music_set == score and game.audio._deck_active(game.audio.music_player) and not game.audio.live_music.native_active, "%s starts the correct %s recording through game.start_scenario" % [role, score])
	check(game.audio.is_processing() and game.audio.process_mode == Node.PROCESS_MODE_ALWAYS and session.match_paused, "%s keeps recorded audio ticking while the network waits for readiness" % role)
	game.audio._process(float(game.audio.MUSIC_CROSSFADE_SECONDS))
	var playing_scores := 0
	for player in game.audio.music_players:
		if game.audio._deck_active(player):
			playing_scores += 1
	if playing_scores != 1:
		print("RECORDED DECK DIAGNOSTIC %s/%s: fade=%s decks=%s" % [role, environment_id, game.audio._crossfade, game.audio.music_players.map(func(deck):return {"playing":deck.playing,"stream":str(deck.stream)})])
	check(playing_scores == 1 and game.audio.music_player.stream == game.audio.music_stream, "%s completes the world recording fade while the shared match remains paused" % role)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		push_error("Use --no-profile-save --no-upnp and an isolated XDG_DATA_HOME")
		quit(1)
		return
	var scenarios := {"ash_foundry":"glutkern", "abandoned_harbor":"hafennebel", "frozen_rail_yard":"frostsignal"}
	for environment_id: String in scenarios:
		var host := prepare_game(true)
		check(host.network.connected_player_count() == 2, "The host fixture contains two authenticated party slots")
		var options := {"environment":environment_id, "build_type":"workshop", "position":"center"}
		host.network.start_match(options, ["mara", "branko"])
		var start_packet := PackedByteArray()
		for packet: PackedByteArray in host.network.transport.packets:
			if PROTOCOL.decode(packet).get("kind","") == "start":
				start_packet = packet
		check(not start_packet.is_empty(), "The actual host start sends a compressed start packet")
		var message := PROTOCOL.decode(start_packet)
		check(message.get("count",0) == 2 and message.get("slots",[]) == [1,2], "The actual start packet contains its current party count and slots")
		var guest := prepare_game(false)
		guest.network._packet(start_packet)
		await process_frame
		check_score(host, environment_id, scenarios[environment_id], "Host")
		check_score(guest, environment_id, scenarios[environment_id], "Guest")
		guest.network.leave()
		host.network.leave()
		paused = false
		check(await CLEANUP.free_scene(guest,self), "Guest recording and world release all playback handles")
		check(await CLEANUP.free_scene(host,self), "Host recording and world release all playback handles")
	print("AUDIO NETWORK SCORE: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
