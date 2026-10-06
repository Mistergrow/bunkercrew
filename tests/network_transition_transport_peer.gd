extends "res://tests/network_chat_peer.gd"
## Actual closed sockets must not commit a start, restart or departure.

func phase() -> String:
	return OS.get_environment("BUNKERCREW_TRANSITION_PHASE")

func host_run() -> void:
	game.network.set_capacity(2)
	game.network.host_room(relay)
	if not await wait_for(func(): return game.network.state == "lobby", "actual relay host"):
		await finish(false, "host"); return
	publish("room", {"code":game.network.room_code})
	if not await barrier("joined2"):
		await finish(false, "join"); return
	if phase() == "start":
		await probe_lobby_start()
		return
	game.network.start_match(CHAT_OPTIONS, game.selected_characters)
	if not await wait_for(loaded, "actual shared defense") or not await barrier("started2"):
		await finish(false, "start"); return
	if phase() == "restart":
		await probe_restart()
		return
	game.rounds.running = false
	game.rounds.wave = 20
	check(game.expedition.on_victory(), "Actual campaign victory prepares a valid finite convoy")
	check(game.expedition.handle_command("prepare", {}, 1), "Actual preparation supplies the playable convoy world")
	check(game.expedition.handle_command("route", {"id":"harbor"}, 1), "Actual host selects a valid next destination")
	check(game.expedition.handle_command("depart", {}, 1), "Connected crew begins actual boarding before the world handoff")
	var truck = game.expedition.vehicle
	var all_seated := true
	for index in game.players.size():
		game.players[index].global_position = truck.global_position
		all_seated = truck.board(game.players[index], "driver" if index == 0 else "passenger_left") and all_seated
	check(all_seated and game.expedition.crew_ready(), "Actual seat ownership prepares the departure handoff")
	var checkpoint: Dictionary = game.campaign.checkpoint()
	var generation: int = game.network._generation
	var world = game.network.world
	var scene_id: int = game.get_instance_id()
	# Native close changes socket state synchronously, before Session's next poll.
	game.network._websocket.close(1000, "Campaign handoff regression")
	check(game.network.state == "playing" and game.network._websocket.get_ready_state() != WebSocketPeer.STATE_OPEN, "Real socket closes while the previously authenticated session still awaits polling")
	# Depart now begins boarding. The authoritative controller commits the
	# actual world handoff only after its crew is seated.
	var accepted: bool = game.expedition._launch_journey()
	check(not accepted, "Unavailable actual relay cannot accept a campaign world handoff")
	check(game.campaign.checkpoint() == checkpoint and game.network._generation == generation and game.network.world == world and not game._restart_pending, "Failed transport handoff preserves campaign, generation, world and pending restart")
	if accepted:
		await finish(false, "closed link accepted departure"); return
	await complete_recovery("playing", scene_id, generation, checkpoint, true)

func probe_lobby_start() -> void:
	var generation: int = game.network._generation
	var scene_id: int = game.get_instance_id()
	var checkpoint: Dictionary = game.campaign.checkpoint()
	game.network._websocket.close(1000, "Lobby start regression")
	check(game.network.state == "lobby" and game.network._websocket.get_ready_state() != WebSocketPeer.STATE_OPEN, "Actual lobby socket closes before polling its authenticated guest")
	game.network.start_match(CHAT_OPTIONS, game.selected_characters)
	check(not game.started and game.network._generation == generation and game.network.world == null and not game.network._loading and game.campaign.checkpoint() == checkpoint, "Unreachable authenticated guest cannot commit an initial world or generation")
	if game.started:
		await finish(false, "closed link accepted initial start"); return
	await complete_recovery("lobby", scene_id, generation, checkpoint)

func probe_restart() -> void:
	game.rounds.running = false
	game.network.pause_match(true)
	check(paused and game.network.match_paused, "Manual host pause precedes the actual socket interruption")
	var checkpoint: Dictionary = game.campaign.checkpoint()
	var generation: int = game.network._generation
	var world = game.network.world
	var scene_id: int = game.get_instance_id()
	game.network._websocket.close(1000, "Mission restart regression")
	check(game.network.state == "playing" and game.network._websocket.get_ready_state() != WebSocketPeer.STATE_OPEN, "Actual playing socket closes before polling its authenticated guest")
	var accepted: bool = game.restart()
	check(not accepted, "The actual game restart API rejects an unavailable guest transport")
	check(game.campaign.checkpoint() == checkpoint and game.network._generation == generation and game.network.world == world and not game.network._loading and not game._restart_pending, "Rejected restart preserves campaign, generation, world and current scene")
	if accepted:
		await finish(false, "closed link accepted restart"); return
	await complete_recovery("playing", scene_id, generation, checkpoint, true)

func complete_recovery(expected_state: String, scene_id: int, generation: int, checkpoint: Dictionary, requested_pause: bool = false) -> void:
	if not await wait_for(func(): return game.network.state == "reconnecting", "host observes actual close"):
		await finish(false, "disconnect"); return
	if not await wait_for(func(): return game.network.state == expected_state and not game.network._loading and game.network.connected_player_count() == 2, "actual relay room recovers", 15):
		await finish(false, "reconnect"); return
	check(game.get_instance_id() == scene_id and game.network._generation == generation and game.campaign.checkpoint() == checkpoint, "Recovery retains the current preparation scene and finite campaign state")
	check(game.network.match_paused == requested_pause and (not game.started or paused == requested_pause), "Recovered host preserves explicit pause while clearing automatic lobby waiting")
	publish("complete")
	if not await barrier("passed2"):
		await finish(false, "guest verification"); return
	if phase() == "start":
		game.network.leave()
		publish("host_left")
		if not await barrier("left_seen2"):
			await finish(false, "intentional lobby close"); return
	publish("finish")
	await delay(0.15)
	await finish(failures == 0, "actual relay close, rejected departure and recovered room")

func guest_run() -> void:
	game.network.join_room(relay, str(read_stage("room").get("code", "")))
	if not await wait_for(func(): return game.network.state == "lobby" and game.network._authenticated, "actual guest authentication"):
		await finish(false, "join"); return
	var scene_id: int = game.get_instance_id()
	var generation: int = game.network._generation
	publish("joined2")
	if phase() != "start":
		if not await wait_for(loaded, "actual guest defense"):
			await finish(false, "start"); return
		scene_id = game.get_instance_id()
		generation = game.network._generation
		publish("started2")
	if not await barrier("complete", 20):
		await finish(false, "handoff/recovery"); return
	# The host publishes after accepting Hello; its queued Welcome still needs
	# one real receiver poll before the guest's authentication becomes current.
	var expected_state := "lobby" if phase() == "start" else "playing"
	var expected_pause: bool = phase() != "start"
	if not await wait_for(func(): return game.network._authenticated and game.network.state == expected_state and game.network.match_paused == expected_pause, "guest completes the recovered handshake"):
		await finish(false, "guest reconnect handshake"); return
	check(game.get_instance_id() == scene_id and game.network._generation == generation and game.network._authenticated, "Guest remains in the same authenticated world after the rejected handoff")
	check(not game.started or paused == expected_pause, "Guest receives the authoritative retained pause after its actual reconnect")
	if phase() == "start": check(not game.started and game.network.state == "lobby", "Rejected initial start leaves the actual guest lobby usable")
	publish("passed2")
	if phase() == "start":
		if not await barrier("host_left"):
			await finish(false, "host close"); return
		# This awaited transition intentionally ends the guest session; the
		# shared wait helper correctly treats unexpected errors as failures.
		var deadline := Time.get_ticks_usec() + 2000000
		while game.network.state != "error" and Time.get_ticks_usec() < deadline:
			await process_frame
		check(game.network.state == "error" and game.network.error_message == "Der Gastgeber hat die Sitzung geschlossen.", "Intentional lobby host departure still ends the guest immediately")
		publish("left_seen2")
	if phase() == "start":
		var finish_deadline := Time.get_ticks_usec() + 2000000
		while not FileAccess.file_exists(path("finish")) and Time.get_ticks_usec() < finish_deadline:
			await process_frame
		check(FileAccess.file_exists(path("finish")), "Intentionally closed lobby fixture completes without another reconnect")
	elif not await barrier("finish"):
		await finish(false, "finish"); return
	await finish(failures == 0, "guest preserves the authenticated world")
