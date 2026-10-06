extends SceneTree
## Two real clients: friend consent, live host presence, delivered invitation,
## authentic game handshake, lobby chat and chat across a mission restart.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OPTIONS := {"environment":"ash_foundry", "build_type":"workshop", "position":"left"}
var game
var hub
var role := ""
var prefix := ""
var relay_url := ""
var public_service := ""
var checks := 0
var failures := 0
var started_at := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error("SOCIAL E2E %s: %s" % [role, label])
	return ok

func publish(stage: String, data: Dictionary = {}) -> void:
	var file := FileAccess.open(prefix + "." + stage + ".json", FileAccess.WRITE)
	if file == null:
		check(false, "Fixture barrier opens")
		return
	file.store_string(JSON.stringify(data))
	file.close()

func read_stage(stage: String) -> Dictionary:
	var path := prefix + "." + stage + ".json"
	if not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func wait_for(predicate: Callable, label: String, seconds: float = 12.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline and Time.get_ticks_msec() - started_at < 50000:
		if is_instance_valid(current_scene): game = current_scene
		if predicate.call(): return true
		await process_frame
	var context := ""
	if is_instance_valid(game):
		context = "; game=" + str(game.started) + "; network=" + str(game.network.state)
	if is_instance_valid(hub):
		context += "; social=" + str(hub.connection_state) + "; error=" + str(hub.error_message)
	return check(false, label + " timed out" + context)

func has_chat(text: String) -> bool:
	return game.network.chat_history.any(func(entry): return entry.text == text)

func _run() -> void:
	started_at = Time.get_ticks_msec()
	role = OS.get_environment("BUNKERCREW_SOCIAL_ROLE")
	prefix = OS.get_environment("BUNKERCREW_SOCIAL_PATH")
	relay_url = OS.get_environment("BUNKERCREW_SOCIAL_RELAY")
	public_service = OS.get_environment("BUNKERCREW_SOCIAL_PUBLIC")
	if role not in ["host", "guest"] or prefix.is_empty() or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(2)
		return
	hub = root.get_node("SocialHub")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.network.listen_port = 24985
	game.network.lan_discovery_port = 24986
	game.hud.overlay = "network"
	game.hud.scenario_options = OPTIONS.duplicate()
	check(hub.set_display_name("Mara" if role == "host" else "Ivo"), "Actual local profile name is accepted")
	check(hub.configure_server(public_service if not public_service.is_empty() else relay_url), "Actual service endpoint is configured from the relay address")
	check(hub.connect_service(), "Actual client opens its presence connection")
	if not await wait_for(func(): return hub.connection_state == "online" and not hub.friend_code.is_empty(), "Authenticated social profile"):
		await finish()
		return
	check(game.social == hub, "Game binds the durable application social connection")
	publish("fixture-identity-" + role, {"code":hub.friend_code})
	if role == "host": await host_run()
	else: await guest_run()
	await finish()

func host_run() -> void:
	game.network.host_room(relay_url)
	if not await wait_for(func(): return game.network.state == "lobby", "Actual host room"): return
	game.social_bridge.refresh()
	publish("host-identity", {"code": hub.friend_code})
	if not await wait_for(func(): return not hub.requests.is_empty(), "Incoming friendship request"): return
	var guest_code: String = hub.requests[0].code
	check(hub.friends.is_empty(), "A request alone does not establish friendship")
	check(hub.accept_friend(guest_code), "Host explicitly accepts the friendship")
	if not await wait_for(func(): return hub.friends.any(func(entry): return entry.code == guest_code), "Mutual accepted friendship"): return
	check(hub.invite_friend(guest_code), "Host delivers an invitation through the authenticated service")
	if not public_service.is_empty():
		if not await wait_for(func(): return game.network.short_room_code.length() == 6, "Actual public broker alias"): return
		publish("public-alias", {"code":game.network.short_room_code})

	if not await wait_for(func(): return game.network.peer_connected and game.network.connected_player_count() == 2, "Invited guest game handshake"): return
	if not await wait_for(func(): return has_chat("Hallo aus der Lobby!"), "Guest lobby chat"): return
	check(game.network.chat_history.filter(func(entry): return entry.text == "Hallo aus der Lobby!")[0].player_id == 2, "Guest chat author is bound to the authenticated seat")
	check(game.network.send_chat("Bereit für die Schicht."), "Host replies through the actual session chat")
	if not await wait_for(func(): return not read_stage("lobby-chat-read").is_empty(), "Guest reads the host lobby reply"): return
	game.network.start_match(OPTIONS, game.selected_characters)
	if not await wait_for(func(): return game.started and game.network.state == "playing" and not game.network._loading, "Actual shared mission"): return
	if not await wait_for(func(): return not read_stage("playing-presence-read").is_empty(), "Guest sees host playing presence"): return
	check(game.network.send_chat("Wir halten den Bunker."), "Host can send text during combat")
	if not await wait_for(func(): return has_chat("Munition kommt."), "Guest in-game reply"): return
	var old_game_id: int = game.get_instance_id()
	var code: String = hub.friend_code
	check(game.restart(), "Actual host restarts the current mission")
	if not await wait_for(func(): return is_instance_valid(game) and game.get_instance_id() != old_game_id and game.started and game.network.state == "playing" and not game.network._loading, "Restarted actual mission"): return
	check(game.social == hub and hub.friend_code == code and hub.connection_state == "online", "Friend identity and service connection survive the scene reload")
	check(has_chat("Hallo aus der Lobby!") and has_chat("Munition kommt."), "Lobby and gameplay conversation survive the mission restart")
	publish("host-restarted", {"ready": true})
	if not await wait_for(func(): return has_chat("Weiter geht's!"), "Chat after restart"): return
	publish("complete", {"ready": true})

func guest_run() -> void:
	if not await wait_for(func(): return not read_stage("host-identity").is_empty(), "Host friend code"): return
	var host_code: String = read_stage("host-identity").code
	check(hub.add_friend(host_code), "Guest sends a friend request using the public code")
	if not await wait_for(func(): return not hub.invitations.is_empty(), "Delivered actual invitation"): return
	check(hub.friends.any(func(entry): return entry.code == host_code and entry.status == "lobby" and entry.joinable), "Guest sees the confirmed friend's actual ready room")
	var invite: Dictionary = hub.invitations[0].duplicate(true)
	check(not invite.is_empty() and not invite.has("room_token"), "Invitation provides a join code without exposing the host's authentication token")
	if invite.is_empty(): return
	game.hud._open_social()
	if not await wait_for(func(): return is_instance_valid(game.hud.social_panel), "Actual friends panel opens"): return
	game.hud.social_panel.select_tab("invitations")
	if not await wait_for(func(): return game.hud.social_panel.row_buttons.has(str(invite.id)), "Actual invitation join button appears"): return
	var join_button: Button = game.hud.social_panel.row_buttons[str(invite.id)][0]
	check(not join_button.disabled, "Actual invitation join button is available")
	if not public_service.is_empty():
		if not await wait_for(func(): return not read_stage("public-alias").is_empty(), "Shared public six-character code"): return
		game.hud._open_network()
		if not await wait_for(func(): return is_instance_valid(game.hud.network_panel), "Actual short-code join panel"): return
		var panel = game.hud.network_panel
		panel.server_field.text = relay_url
		panel.code_field.text = str(read_stage("public-alias").code)
		if not await wait_for(func(): return not panel.join_button.disabled, "Actual panel enables a complete six-character input", 2): return
		check(panel.code_field.text.length() == 6 and not panel.join_button.disabled, "Actual UI accepts the short code with the selected direct or relay connection")
		panel.join_button.pressed.emit()
	else:
		join_button.pressed.emit()
	if not await wait_for(func(): return game.network.state == "lobby" and game.network._authenticated, "Game connection from invitation"): return
	if not public_service.is_empty():
		if relay_url.is_empty(): check(game.network.relay_url.is_empty() and is_instance_valid(game.network.transport) and game.network.transport.peer != null, "Public broker resolves the six-code into a real direct ENet session")
		else: check(game.network.relay_url == relay_url and game.network._websocket != null and game.network._websocket.get_ready_state() == WebSocketPeer.STATE_OPEN, "Public broker resolves the six-code with a selected relay into the actual public game connection")
	check(game.network.send_chat("Hallo aus der Lobby!"), "Guest sends actual lobby text")
	if not await wait_for(func(): return has_chat("Bereit für die Schicht."), "Host lobby reply"): return
	publish("lobby-chat-read", {"ready": true})
	if not await wait_for(func(): return game.started and game.network.state == "playing" and not game.network._loading, "Shared mission starts"): return
	if not await wait_for(func(): return hub.friends.any(func(entry): return entry.code == host_code and entry.status == "playing" and not entry.joinable), "Actual friend playing status"): return
	publish("playing-presence-read", {"ready": true})
	if not await wait_for(func(): return has_chat("Wir halten den Bunker."), "Host combat chat"): return
	check(game.network.send_chat("Munition kommt."), "Guest can reply during combat")
	if not await wait_for(func(): return not read_stage("host-restarted").is_empty() and game.started and game.network.state == "playing" and not game.network._loading, "Shared mission restarts"): return
	check(has_chat("Hallo aus der Lobby!") and has_chat("Wir halten den Bunker."), "Guest preserves the conversation across a scene reload")
	check(game.network.send_chat("Weiter geht's!"), "Chat remains usable after restart")
	await wait_for(func(): return not read_stage("complete").is_empty(), "Host completes the end-to-end flow")

func finish() -> void:
	hub.disconnect_service()
	if is_instance_valid(game) and is_instance_valid(game.network): game.network.leave()
	if is_instance_valid(game): await Cleanup.free_scene(game, self)
	var session := root.get_node_or_null("NetworkSession")
	if session != null: await Cleanup.free_scene(session, self)
	print("SOCIAL END TO END %s: %d/%d checks passed" % [role, checks-failures, checks])
	quit(1 if failures else 0)
