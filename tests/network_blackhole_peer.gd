extends "res://tests/network_gameplay_peer.gd"
## Driver stops one real process without a leave or socket-close message.
var slot:=1
func _run() -> void:
	overall_timeout_ms=35000
	slot=OS.get_environment("LASTSHIFT_PARTY_SLOT").to_int()
	role="host" if slot==1 else "guest%d"%slot
	prefix=OS.get_environment("LASTSHIFT_GAMEPLAY_PATH")
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game);current_scene=game
	game.network.listen_port=39317;game.network.lan_discovery_port=39318
	game.network.lan_discovery_targets.assign(["127.0.0.1"])
	if slot==1:
		game.network.host_room("")
		publish("room",{"code":game.network.room_code})
		if not await wait_for(func():return game.network.connected_player_count()==3,"three authenticated players",15):await finish(false,"lobby");return
		game.network.start_match(OPTIONS,game.selected_characters)
	else:
		game.network.join_room("",read_stage("room").code)
		if not await wait_for(func():return game.network.state=="lobby" and game.network._authenticated,"authenticated ordered join",15):await finish(false,"join");return
		if not check(game.network.local_player_id==slot,"Stopped/healthy fixture role matches its authenticated room slot"):await finish(false,"slot");return
		publish("joined%d"%slot,{"player_id":game.network.local_player_id})
	if not await wait_for(playing,"match starts",15):await finish(false,"start");return
	game.rounds.running=false
	publish("started%d"%slot)
	if not await barrier("stopped",15):await finish(false,"stop barrier");return
	if slot==1:
		var began:=Time.get_ticks_msec()
		if not await wait_for(func():return not game.network.is_player_connected(2),"silent stopped guest detected",7):await finish(false,"timeout");return
		check(game.network.is_player_connected(3),"A silent guest does not disconnect the healthy guest")
		check(game.network.state=="reconnecting" and paused,"Missing seat receives the existing paused reconnection grace")
		publish("detected",{"elapsed_ms":Time.get_ticks_msec()-began,"checks":checks,"failures":failures})
		if not await barrier("healthy"):await finish(false,"healthy");return
		publish("finish");await finish(failures==0,"silent failure isolation")
	elif slot==3:
		if not await barrier("detected",8):await finish(false,"detection");return
		var received:int=game.network.received_snapshots
		if not await wait_for(func():return game.network.received_snapshots>received and paused,"healthy guest receives paused host snapshots",3):await finish(false,"healthy snapshots");return
		check(game.network.active and game.network.peer_connected and game.network.state in ["playing","reconnecting"], "Healthy guest retains its authenticated link and receives snapshots during missing-seat grace")
		publish("healthy",{"checks":checks,"failures":failures})
		if not await barrier("finish"):await finish(false,"finish");return
		await finish(failures==0,"healthy peer survives")
