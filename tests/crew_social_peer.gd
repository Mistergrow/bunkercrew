extends "res://tests/network_gameplay_peer.gd"
## Four real clients; the uninvolved guest cannot receive a private message.
const Codec := preload("res://scripts/voice_codec.gd")
var slot := 1
var relay := ""
var service := ""
var hub
var use_short := false
var completions: Array[Dictionary] = []
var blocked_direct := false
var direct_port_blocker: PacketPeerUDP

func _run() -> void:
	overall_timeout_ms = 90000
	slot = OS.get_environment("BUNKERCREW_CREW_SLOT").to_int()
	role = "host" if slot == 1 else "guest%d" % slot
	prefix = OS.get_environment("BUNKERCREW_CREW_PATH")
	relay = OS.get_environment("BUNKERCREW_CREW_RELAY")
	service = OS.get_environment("BUNKERCREW_CREW_SERVICE")
	use_short = OS.get_environment("BUNKERCREW_CREW_SHORT") == "1"
	blocked_direct = OS.get_environment("BUNKERCREW_CREW_BLOCKED_DIRECT") == "1"
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args() or prefix.is_empty(): quit(2); return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	hub = root.get_node("SocialHub")
	hub.set_display_name("Crew %d" % slot)
	game.hud.overlay = "network"
	game.hud.scenario_options = OPTIONS.duplicate()
	game.audio.set_music_volume(0.0)
	game.audio.set_sfx_volume(0.0)
	game.network.listen_port = 24981
	game.network.lan_discovery_port = 24982
	game.network.lan_discovery_targets.assign(["127.0.0.1"])
	game.network.chat_send_completed.connect(func(text: String, accepted: bool): completions.append({"text":text, "accepted":accepted}))
	if blocked_direct:
		check(hub.configure_server(service), "Blocked-UDP fixture selects its actual shared presence service")
		if slot == 1:
			direct_port_blocker = PacketPeerUDP.new()
			check(direct_port_blocker.bind(game.network.listen_port, "0.0.0.0") == OK, "Actual direct host UDP port is unavailable throughout the online round")
			check(game.network.default_relay_url() == relay, "Production online default follows the configured shared TLS/presence service")
	if slot == 1 and relay.is_empty():
		check(hub.configure_server(service) and hub.connect_service(), "Direct host connects its configured public presence service")
		if not await wait_for(func(): return hub.connection_state == "online", "direct host presence"): await finish(false, "service"); return
	if slot == 1:
		if blocked_direct:
			await delay(.04)
			check(is_instance_valid(game.hud.network_panel) and game.hud.network_panel.server_field.text == relay and not game.hud.network_panel.direct_mode, "Actual Online UI offers the shared Relay by default without editing its server field")
			game.hud.network_panel.create_button.pressed.emit()
		else: game.network.host_room(relay)
		if not await wait_for(func(): return game.network.state == "lobby", "host lobby"): await finish(false, "lobby"); return
		if use_short:
			if not await wait_for(func(): return game.network.short_room_code.length() == 6, "actual published six-character alias", 20): await finish(false, "alias"); return
			check(relay.is_empty() or game.network.short_room_code != game.network.room_code, "Broker alias is distinct from the selected relay's legacy code")
		publish("room", {"code":game.network.short_room_code if use_short else game.network.room_code})
	else:
		if not await barrier("room", 20): await finish(false, "room"); return
		if use_short: check(hub.configure_server(service), "Fixture selects its actual shared short-code broker")
		if blocked_direct:
			await delay(.04)
			check(is_instance_valid(game.hud.network_panel) and game.hud.network_panel.server_field.text == relay, "Actual guest UI derives its server from shared presence without manual entry")
			game.hud.network_panel.code_field.text = str(read_stage("room").code)
			game.hud.network_panel.join_button.pressed.emit()
		else: game.network.join_room(relay, read_stage("room").code)
		if not await wait_for(func(): return game.network.state == "lobby" and game.network._authenticated, "authenticated join", 20): await finish(false, "join"); return
		check(game.network.local_player_id == slot, "Actual game assigns the expected seat")
		publish("joined%d" % slot)
	if blocked_direct:
		check(game.network.relay_url == relay and not is_instance_valid(game.network.transport), "Short alias joins the genuine Relay host without an ENet/direct socket or manual guest URL")
	if not await wait_for(func(): return hub.connection_state == "online" and game.network.crew_members().size() == 4 and game.network.crew_members().all(func(row): return row.connected and row.friend_service == hub.server_url and not row.friend_code.is_empty()), "verified connected four-player identities including the local published identity", 25):
		print("CREW STATE ", JSON.stringify(game.network.crew_members()), " hub=", hub.connection_state, " error=", hub.error_message)
		await finish(false, "identities"); return
	check(hub.server_url == hub.normalize_url(service), "Selected relay or advertised direct service connects automatically")
	check(game.network.crew_members().all(func(row): return row.friend_service == hub.server_url and row.connected), "Names and friend identities belong to the current authenticated crew")
	if slot == 1:
		check(not JSON.stringify(game.network._social.identities).contains(str(game.network._slots[2]._guest_token)), "Public identity proofs never reveal private resumption tokens")
	publish("verified%d" % slot)
	for id in range(1, 5):
		if not await barrier("verified%d" % id, 25): await finish(false, "verification barrier"); return
	if slot == 2:
		check(hub.set_display_name("Crew 2 renamed"), "Actual service profile accepts a lobby rename")
	if not await wait_for(func(): return game.network.crew_members().any(func(row): return row.player_id == 2 and row.name == "Crew 2 renamed"), "verified crew rename", 15): await finish(false, "rename"); return
	check(not code_for(2).is_empty(), "A genuine rename preserves the verified social identity")
	publish("renamed%d" % slot)
	for id in range(1, 5):
		if not await barrier("renamed%d" % id, 15): await finish(false, "rename barrier"); return
	if slot == 1: await host_flow()
	elif slot == 2: await alice_flow()
	elif slot == 3: await bob_flow()
	else: await observer_flow()
	if slot == 1: publish("complete")
	else: await barrier("complete", 30)
	publish("done%d" % slot)
	if slot == 1:
		for id in range(2, 5): await barrier("done%d" % id, 15)
	else: await delay(0.2)
	hub.disconnect_service()
	await finish(failures == 0, "Verified identities, explicit consent, private routing, mute/block and reconnection")

func code_for(id: int) -> String:
	for row in game.network.crew_members():
		if row.player_id == id: return row.friend_code
	return ""

func has_text(text: String) -> bool:
	return game.network.chat_history.any(func(row): return row.text == text)

func acknowledged(text: String, accepted: bool = true) -> bool:
	return completions.any(func(row): return row.text == text and row.accepted == accepted)

func host_flow() -> void:
	if not await barrier("privacy", 30): return
	check(not has_text("Only Alice and Bob") and not has_text("Bob's private reply"), "Host conversation does not expose whispers between guests")
	check(game.network.send_private_chat(2, "Host's private greeting"), "Host sends a genuine private message")
	if not await barrier("hostprivate"): return
	if not await barrier("blocked"): return
	if not await barrier("reconnectready"): return
	game.network.start_match(OPTIONS, game.selected_characters)
	if not await wait_for(playing, "real shared game", 20): return
	publish("gameplaying")
	if not await barrier("dropping"): return
	if relay.is_empty(): game.network.transport.disconnect_guest(int(game.network._slots[2].wire))
	else: publish("droprelay")
	if not await wait_for(func(): return game.network.state == "reconnecting", "actual interrupted transport", 15): return
	if not await wait_for(playing, "actual reconnect", 20): return
	if not await barrier("reconnected"): return
	check(has_text("After reconnect") and not has_text("Only Alice and Bob"), "Reconnected private history remains limited to its participants")
	publish("reconnectpassed")
	if not await barrier("voicepassed"): return

func alice_flow() -> void:
	check(hub.add_friend(code_for(3)), "Clicking verified player sends a friendship request")
	check(hub.is_friend_request_pending(code_for(3)), "A local send is pending rather than falsely marked confirmed")
	if not await wait_for(func(): return hub.outgoing_requests.any(func(row): return row.code == code_for(3)), "server-confirmed outgoing request"): return
	check(not hub.is_friend_request_pending(code_for(3)), "Actual server confirmation retires the transient send state")
	publish("requestsent")
	if not await wait_for(func(): return hub.requests.any(func(row): return row.code == code_for(3)), "crossed pending request"): return
	check(hub.friends.is_empty(), "Crossed requests do not automatically establish friendship")
	publish("crosschecked")
	if not await wait_for(func(): return hub.friends.any(func(row): return row.code == code_for(3)), "explicit mutual acceptance"): return
	check(hub.outgoing_requests.is_empty(), "Explicit acceptance removes the confirmed outgoing request")
	check(game.network.send_private_chat(3, "Only Alice and Bob"), "Guest sends a targeted private message")
	if not await wait_for(func(): return acknowledged("Only Alice and Bob") and has_text("Bob's private reply"), "private response"): return
	if not await barrier("privacy"): return
	if not await wait_for(func(): return has_text("Host's private greeting"), "host whisper"): return
	publish("hostprivate")
	if not await barrier("blocked"): return
	check(game.network.send_private_chat(3, "Blocked private text"), "Guest sends while remote recipient has blocked it")
	if not await wait_for(func(): return acknowledged("Blocked private text", false), "blocked recipient rejection"): return
	check(not has_text("Blocked private text") and not game.network.chat_error.is_empty(), "Rejected whisper keeps a useful sender acknowledgement")
	publish("blockedack")
	if not await barrier("unblocked"): return
	publish("reconnectready")
	if not await barrier("gameplaying", 20): return
	var token: String = game.network._client_token
	publish("dropping")
	if not relay.is_empty():
		if not await barrier("droprelay"): return
		game.network._websocket.close(1001, "Isolated fixture drop")
	if not await wait_for(func(): return game.network.state == "reconnecting", "own transport interruption", 15): return
	if not await wait_for(playing, "own real rejoin", 20): return
	check(game.network._client_token == token and has_text("Only Alice and Bob") and has_text("Host's private greeting"), "Actual reconnection preserves identity and authorized private history")
	check(game.network.send_private_chat(1, "After reconnect"), "Whisper still works after actual reconnect")
	if not await wait_for(func(): return acknowledged("After reconnect"), "reconnected private acknowledgement"): return
	publish("reconnected")
	if not await barrier("muted"): return
	var pcm := PackedByteArray()
	pcm.resize(Codec.BYTES)
	for index in Codec.FRAMES: pcm.encode_s16(index * 2, int(sin(float(index) * 0.12) * 10000))
	for frame in range(6):
		check(game.network.send_voice(pcm), "Actual voice packet remains routable")
		await delay(0.025)
	publish("voiced")
	if not await barrier("unmuted"): return
	for frame in range(6):
		game.network.send_voice(pcm)
		await delay(0.025)
	publish("voicedagain")
	await barrier("voicepassed")

func bob_flow() -> void:
	if not await barrier("requestsent"): return
	if not await wait_for(func(): return hub.requests.any(func(row): return row.code == code_for(2)), "incoming request"): return
	check(hub.friends.is_empty(), "Incoming request awaits explicit consent")
	check(hub.add_friend(code_for(2)), "A reverse request remains a request")
	if not await barrier("crosschecked"): return
	check(hub.friends.is_empty() and hub.accept_friend(code_for(2)), "Only explicit Accept establishes mutual friendship")
	if not await wait_for(func(): return has_text("Only Alice and Bob"), "Alice whisper"): return
	check(game.network.chat_history.filter(func(row): return row.text == "Only Alice and Bob")[0].recipient_id == 3, "Recipient is bound by the authoritative host")
	check(game.network.send_private_chat(2, "Bob's private reply"), "Recipient can privately answer")
	if not await wait_for(func(): return acknowledged("Bob's private reply"), "reply acknowledgement"): return
	publish("privacy")
	if not await barrier("hostprivate"): return
	check(game.network.set_player_blocked(2, true), "Block uses the confirmed identity and local communication filter")
	await delay(0.25)
	publish("blocked")
	if not await barrier("blockedack"): return
	check(not has_text("Blocked private text") and game.network.is_player_blocked(2), "Blocked sender cannot enter local conversation")
	check(game.network.set_player_blocked(2, false), "Unblocking restores only communication, not friendship")
	if not await wait_for(func(): return not game.network.is_player_blocked(2), "confirmed unblock"): return
	check(hub.friends.is_empty(), "Unblock never silently restores friendship")
	await delay(0.25)
	publish("unblocked")
	if not await barrier("reconnectpassed", 35): return
	game.voice.enabled = true
	game.voice.remote_muted = false
	check(game.network.set_player_muted(2, true), "Selected speaker is individually muted")
	var before: int = game.voice.received_frames
	publish("muted")
	if not await barrier("voiced"): return
	await delay(0.15)
	check(game.voice.received_frames == before and not game.voice.remote_speaking, "Muted real packets never enter an audio playback queue")
	check(game.network.set_player_muted(2, false), "Individual unmute leaves global voice preference alone")
	publish("unmuted")
	if not await barrier("voicedagain"): return
	if not await wait_for(func(): return game.voice.received_frames > before, "audible unmuted packet"): return
	publish("voicepassed")

func observer_flow() -> void:
	if not await barrier("privacy", 30): return
	check(not has_text("Only Alice and Bob") and not game.network._chat.history.any(func(row): return bool(row.get("private", false))), "Uninvolved actual guest receives no private payload or history")
	check(hub.friends.is_empty() and hub.requests.is_empty(), "Other players' friendships remain private")
	if not await barrier("hostprivate"): return
	check(not has_text("Host's private greeting"), "Host whisper is not broadcast to the third guest")
	if not await barrier("voicepassed", 50): return
	check(not game.network._chat.history.any(func(row): return bool(row.get("private", false))), "Replay after another user's real reconnect does not leak private text")
