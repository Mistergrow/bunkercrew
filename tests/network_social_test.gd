extends SceneTree
## Identity-bound whisper history and preferences survive slot compaction safely.
const Session := preload("res://scripts/network_session.gd")
const Peer := preload("res://scripts/network_peer_state.gd")
const Chat := preload("res://scripts/network_chat.gd")
const Messages := preload("res://scripts/network_messages.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

class FixtureSession extends Session:
	var outgoing: Array[Dictionary] = []
	func _send(message: Dictionary, _reliable := true, target_id: int = 0) -> bool:
		outgoing.append({"message":message.duplicate(true), "target":target_id})
		return true

class FixtureHud extends Node:
	var scenario_options := {"environment":"ash_foundry", "build_type":"workshop", "position":"left"}
	var story_selected := false

class FixtureVoice extends Node:
	var states: Dictionary = {}
	func set_sender_muted(slot: int, value: bool) -> void: states[slot] = value
	func clear_sender_mutes() -> void: states.clear()
	func reset() -> void: pass

class FixtureHub extends Node:
	@warning_ignore("unused_signal")
	signal room_resolved(request: String, route: Dictionary)
	var connection_state := "offline"
	var server_url := "wss://friends.example.com/social"
	var cancelled := 0
	func resolve_short_code(_code: String) -> String: return "a".repeat(32)
	func cancel_room_resolution(_request: String) -> void: cancelled += 1

class FixtureTransport extends Node:
	var mapping_confirmed := false
	var public_address := "8.8.8.8"
	var port := 24777
	func close() -> void: pass

class FixtureGame extends Node:
	var selected_characters: Array = ["mara", "ivo", "nora", "branko"]
	var started := false
	var voice: Node
	var hud: Node
	var player_count := 4
	var network
	var social: Node

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func _run() -> void:
	var game := FixtureGame.new()
	game.hud = FixtureHud.new()
	game.voice = FixtureVoice.new()
	game.social = FixtureHub.new()
	game.add_child(game.social)
	game.add_child(game.hud)
	game.add_child(game.voice)
	var network := FixtureSession.new()
	network.game = game
	game.network = network
	game.add_child(network)
	root.add_child(game)
	network.active = true
	network.is_host = true
	network.state = "lobby"
	network.peer_connected = true
	for slot in [2,3,4]:
		var link := Peer.create(0.0)
		link.slot = slot
		link.wire = slot * 10
		link._authenticated = true
		link.chat_name = "Guest %d" % slot
		network._slots[slot] = link
		network._peers[link.wire] = link
	var lobby: Dictionary = network._lobby_message()
	check(Messages.valid(lobby, false), "Anonymous lobby has validated opaque member identifiers")
	check(network.crew_members().all(func(row): return row.member_key.length() == 48), "Actions have stable member identifiers even without a friend service")
	var key: String = network.crew_members()[1].member_key
	check(network.set_player_muted(2, true) and game.voice.states[2], "Mute immediately controls only the selected actual speaker")
	check(not network.set_player_muted(1, true), "Own character cannot be remotely muted")
	check(network.send_private_chat(2, "Private before replacement"), "Actual authoritative private routing accepts a connected recipient")
	var whisper: Dictionary = network.chat_history[0]
	check(Chat.valid_row(whisper) and whisper.recipient_key == key, "Private history is bound to the actual recipient identity")
	check(network.outgoing.filter(func(packet): return packet.message.kind == "chat_message").all(func(packet): return packet.target == 20), "Private message never enters the broadcast path")
	check(network.set_player_blocked(2, true) and not network.private_chat_available(2), "Local blocking is useful with an offline service")
	check(not network.send_private_chat(2, "Blocked") and network.chat_error == Chat.error_text("blocked"), "Blocked private text has explicit feedback")
	check(network.set_player_blocked(2, false) and network.is_player_muted(2), "Unblock preserves an independently chosen mute")
	var old_link: Dictionary = network._slots[2]
	network._peers.erase(old_link.wire)
	network._slots.erase(2)
	network._social.remove_member(2)
	var replacement := Peer.create(0.0)
	replacement.slot = 2
	replacement.wire = 22
	replacement._authenticated = true
	network._slots[2] = replacement
	network._peers[22] = replacement
	network._lobby_message()
	check(network.crew_members()[1].member_key != key and not network.is_player_muted(2), "Replacement in the same slot inherits neither member key nor mute")
	network._context_peer = 22
	network.outgoing.clear()
	network._replay_chat()
	var histories: Array = network.outgoing.filter(func(packet): return packet.message.kind == "chat_history")
	check(histories.size() == 1 and histories[0].message.messages.is_empty(), "New occupant cannot receive the previous occupant's private history")
	network._context_peer = 0
	network.set_player_muted(3, true)
	var old_members: Dictionary = network._social.member_keys.duplicate()
	network._social.apply_roster({}, {"1":old_members["1"], "2":old_members["3"], "3":old_members["4"]})
	check(network.is_player_muted(2) and not network.is_player_muted(3), "A compacted crew keeps preference attached to its actual member")
	var identity := {"code":"ABCDEFGHJKLM", "service":"wss://friends.example.com/social", "context":"a".repeat(48), "proof":"b".repeat(64)}
	check(Session.Social.valid_identity(identity), "Canonical public attestation is accepted")
	identity.proof = identity.proof.to_upper()
	check(not Session.Social.valid_identity(identity), "Malformed attestation never becomes a service verification request")
	var malformed: Dictionary = whisper.duplicate(true)
	malformed.recipient_key = ""
	check(not Chat.valid_row(malformed), "Private messages require a bounded, real recipient key")
	var observed_transport := FixtureTransport.new()
	network.add_child(observed_transport)
	network.transport = observed_transport
	network._invite_secret = "23456789ABCDEFGH"
	network.observe_public_address("8.8.8.8")
	check(network.observed_public_address == "8.8.8.8" and network.internet_code.is_empty(), "Observed public IPv4 alone never claims incoming UDP reachability")
	network._public_address("8.8.8.8", "Mapping failed")
	check(network.internet_code.is_empty(), "Failed UPnP discovery cannot advertise an unconfirmed public endpoint")
	observed_transport.mapping_confirmed = true
	network._public_address("8.8.8.8", "Mapping confirmed")
	check(not network.internet_code.is_empty(), "A genuinely confirmed forwarding report enables the public invitation")
	observed_transport.mapping_confirmed = false
	check(network.set_advertised_address("8.8.8.8") and not network.internet_code.is_empty(), "Explicit manual public-address configuration remains available")
	network.peer_connected = false
	network.leave()
	check(game.voice.states.is_empty() and network.crew_members().is_empty(), "Leaving retires local communication preferences")
	network.join_room("", "ABCDEF")
	check(network.active and network.state == "connecting" and not network._short_resolution.is_empty(), "A short-code lookup is bounded asynchronous work before ENet exists")
	var request: String = network._short_resolution
	network.leave()
	check(game.social.cancelled == 1 and network._short_resolution.is_empty(), "Leaving cancels the actual pending broker request")
	game.social.room_resolved.emit(request, {"ok":true, "room_code":Session.JoinCode.invite("127.0.0.1",24777,"23456789ABCDEFGH"), "relay_url":""})
	network._resolved_short_room(request, {"ok":true, "room_code":Session.JoinCode.invite("127.0.0.1",24777,"23456789ABCDEFGH"), "relay_url":""})
	check(not network.active and network.transport == null, "A late successful broker reply cannot resurrect a departed game connection")
	network.join_room("", "ABCDEF")
	var failed_request: String = network._short_resolution
	game.social.room_resolved.emit(failed_request, {"ok":false, "error_code":"service_unavailable"})
	check(network.state == "error" and network._short_resolution.is_empty() and network.transport == null, "Service loss retires pending resolution without opening a game socket")
	network.leave()
	await Cleanup.free_scene(game, self)
	print("NETWORK SOCIAL: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
