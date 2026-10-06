class_name BetaInternetLifecycleCheck
extends "res://tests/network_four_peer.gd"
## Independent four-peer lobby/start/pause/rematch and deliberate/hard departure.
var departure_mode := "leave"

func _run() -> void:
	overall_timeout_ms=85000
	role=OS.get_environment("LASTSHIFT_GAMEPLAY_ROLE")
	prefix=OS.get_environment("LASTSHIFT_GAMEPLAY_PATH")
	slot=OS.get_environment("LASTSHIFT_PARTY_SLOT").to_int()
	relay=OS.get_environment("LASTSHIFT_PARTY_RELAY")
	departure_mode=OS.get_environment("BUNKERCREW_HOST_DEPARTURE")
	if prefix.is_empty() or slot not in [1,2,3,4] or departure_mode not in ["leave","crash"] or "--no-upnp" not in OS.get_cmdline_user_args() or "--no-profile-save" not in OS.get_cmdline_user_args():
		await finish(false,"safe isolated lifecycle arguments missing"); return
	publish("identity"+str(slot),preload("res://tests/internet_peer_identity.gd").capture())
	if not check(relay.begins_with("wss://"),"Lifecycle uses the actual TLS relay"):
		await finish(false,"TLS relay required"); return
	if OS.get_environment("BUNKERCREW_EXPORTED_PEER")=="1" and not check(not OS.has_feature("editor"),"Actual exported template runs its embedded lifecycle"):
		await finish(false,"exported template required"); return
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.hud.overlay="network"
	game.combat_events.persistence_enabled=false
	if slot==1: await lifecycle_host()
	else: await lifecycle_guest()

func lifecycle_host() -> void:
	game.network.host_room(relay)
	if not await wait_for(func(): return game.network.state=="lobby","TLS host lobby",15): await finish(false,"host"); return
	check(preload("res://scripts/social_hub.gd").valid_room_alias(game.network.room_code),"Actual TLS room invitation has six readable symbols")
	publish("room",{"code":game.network.room_code})
	if not await each_barrier("joined") or not await wait_for(func(): return game.network.connected_player_count()==4,"four authenticated lobby slots",15): await finish(false,"lobby"); return
	check(game.selected_characters==["mara","branko","ivo","mara"],"Each authenticated guest selects its own lobby character")
	game.network.start_match(OPTIONS,game.selected_characters)
	if not await wait_for(loaded,"four-party start",15) or not await each_barrier("started"): await finish(false,"start"); return
	game.rounds.running=false
	check(game.players.size()==4,"Started authoritative world has exactly four workers")
	publish("pause_request")
	if not await barrier("pause_sent2") or not await wait_for(func(): return paused and game.network.match_paused,"actual guest pause",5): await finish(false,"pause"); return
	publish("paused")
	if not await each_barrier("pause_seen"): await finish(false,"pause replicas"); return
	game.network.pause_match(false)
	if not await wait_for(loaded,"host resumes all",5) or not await each_barrier("resumed"): await finish(false,"resume"); return
	var previous_generation: int=game.network._generation
	publish("restart",{"previous_generation":previous_generation})
	game.network.restart_match()
	if not await wait_for(func(): return loaded() and game.network._generation>previous_generation,"host starts a genuine new generation",15) or not await each_barrier("restarted"): await finish(false,"restart"); return
	game.rounds.running=false
	check(game.players.size()==4 and game.network.connected_player_count()==4,"Rematch preserves all four authenticated slots")
	publish("guest_leave")
	if not await barrier("left4") or not await wait_for(func(): return not game.network.is_player_connected(4),"intentional fourth guest departure",5): await finish(false,"guest leave"); return
	check(game.network.is_player_connected(2) and game.network.is_player_connected(3),"Guest departure retains both healthy guest links")
	if not await each_remaining("remaining_seen"): await finish(false,"healthy guests"); return
	publish("host_departure_ready",{"mode":departure_mode})
	if departure_mode=="crash":
		# The external launcher kills this owned process; it observes guest state
		# through their independent reports, never a synthetic session callback.
		while not done: await delay(.1)
	else:
		# WAN stage coordination may arrive after an actual WSS leave packet.
		# Each remaining guest must enter the expected-departure observation
		# before the host deliberately closes the real game connection.
		if not await each_remaining("host_departure_seen"): await finish(false,"host departure observation ready"); return
		game.network.leave()
		publish("host_left")
		if not await each_remaining("host_closed"): await finish(false,"host leave delivery"); return
		await finish(failures==0,"TLS four-person pause/rematch and intentional departures")

func each_remaining(stage: String) -> bool:
	for id in [2,3]:
		if not await barrier(stage+str(id),15): return false
	return true

func lifecycle_guest() -> void:
	game.network.join_room(relay,str(read_stage("room").get("code","")))
	if not await wait_for(func(): return game.network._authenticated and game.network.state=="lobby","TLS guest authentication",15): await finish(false,"join"); return
	check(game.network.local_player_id==slot,"Relay authentication binds the expected unique guest slot")
	game.network.send_command("character",{"id":["mara","branko","ivo","mara"][slot-1]})
	await delay(.15)
	publish("joined"+str(slot))
	if not await wait_for(loaded,"actual started replica",15): await finish(false,"start"); return
	check(game.players.size()==4 and game.players[slot-1].character_id==["mara","branko","ivo","mara"][slot-1],"Replica contains four workers with its selected character")
	publish("started"+str(slot))
	if not await barrier("pause_request"): await finish(false,"pause request"); return
	if slot==2:
		game.network.pause_match(true)
		publish("pause_sent2")
	if not await barrier("paused") or not await wait_for(func(): return paused and game.network.match_paused,"shared real pause",5): await finish(false,"pause"); return
	publish("pause_seen"+str(slot))
	if not await wait_for(loaded,"shared real resume",5): await finish(false,"resume"); return
	publish("resumed"+str(slot))
	if not await barrier("restart"): await finish(false,"restart barrier"); return
	var previous: int=int(read_stage("restart").previous_generation)
	if not await wait_for(func(): return loaded() and game.network._generation>previous,"real rematch replica",15): await finish(false,"restart"); return
	check(game.players.size()==4 and game.network.world.last_error.is_empty(),"New generation reconstructs exactly four valid workers")
	publish("restarted"+str(slot))
	if not await barrier("guest_leave"): await finish(false,"guest leave barrier"); return
	if slot==4:
		game.network.leave()
		publish("left4")
		await finish(failures==0,"fourth guest voluntarily leaves"); return
	if not await wait_for(func(): return game.network.is_player_connected(2) and game.network.is_player_connected(3) and not game.network.is_player_connected(4),"remaining healthy peers retained",5): await finish(false,"roster"); return
	check(game.network.active and game.network._authenticated,"A different guest leaving does not evict this authenticated player")
	publish("remaining_seen"+str(slot))
	if not await barrier("host_departure_ready"): await finish(false,"host departure barrier"); return
	var began:=Time.get_ticks_usec()
	if departure_mode!="crash": publish("host_departure_seen"+str(slot))
	if departure_mode=="crash":
		if not await wait_for(func(): return game.network.state=="reconnecting" and paused,"actual killed host enters bounded retry",8): await finish(false,"hard host loss"); return
		check(game.network._reconnect_deadline>game.network._clock and game.network._reconnect_deadline-game.network._clock<=30.1,"Hard host loss preserves only the bounded thirty-second return window")
		if not await wait_for(func(): return game.network.state=="error","hard host retry expires",33): await finish(false,"retry deadline"); return
		check(not game.network.error_message.is_empty() and not game.network.peer_connected and not game.network._authenticated,"A permanently missing host ends with a readable failure and a closed link")
	else:
		if not await wait_for(func(): return game.network.state=="error","actual host leave is delivered",5): await finish(false,"intentional host loss"); return
		check(game.network._reconnect_deadline==0 and not game.network.peer_connected and not game.network._authenticated,"Intentional host leave cannot start an unnecessary thirty-second retry")
	publish("host_closed"+str(slot),{"elapsed_seconds":float(Time.get_ticks_usec()-began)/1000000.0,"error_message":game.network.error_message,"state":game.network.state})
	await finish(failures==0,"TLS guest pause/rematch and finite host-departure handling")
