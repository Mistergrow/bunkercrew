extends "res://tests/network_gameplay_peer.gd"
## Prepared positions and stopped AI; all entity/event transport uses real peers.
var slot := 1
var party_size := 2
var relay := ""

func _process(delta: float) -> bool:
	# Prepared actors have no flight/attack AI, but their authoritative animation
	# age must keep ticking just as it does in a normal active host world.
	if slot == 1 and is_instance_valid(game) and game.started and not paused:
		for aircraft in air_nodes(): aircraft.age += delta
	return false

func _run() -> void:
	overall_timeout_ms = 48000
	role = OS.get_environment("LASTSHIFT_GAMEPLAY_ROLE")
	prefix = OS.get_environment("LASTSHIFT_GAMEPLAY_PATH")
	slot = int(OS.get_environment("BUNKERCREW_AIR_SLOT"))
	party_size = int(OS.get_environment("BUNKERCREW_AIR_PARTY"))
	relay = OS.get_environment("BUNKERCREW_AIR_RELAY")
	if slot < 1 or slot > party_size or party_size not in [2,4] or prefix.is_empty() or "--no-profile-save" not in OS.get_cmdline_user_args():
		await finish(false,"isolated air fixture arguments required")
		return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.hud.overlay = "network"
	game.audio.set_music_volume(0.0)
	game.audio.set_sfx_volume(0.5)
	game.network.listen_port = 24927
	game.network.lan_discovery_port = 24928
	game.network.lan_discovery_targets.assign(["127.0.0.1"])
	game.network.max_players = party_size
	if slot == 1: await host_run()
	else: await guest_run()

func air_nodes() -> Array:
	return get_nodes_in_group("air_enemies").filter(func(node): return node.get("game") == game and not node.is_queued_for_deletion())

func ordnance() -> Array:
	return get_nodes_in_group("air_projectiles").filter(func(node): return node.get("game") == game and not node.is_queued_for_deletion())

func kinds_match(expected: Array) -> bool:
	var actual: Array = air_nodes().map(func(node): return node.kind)
	actual.sort()
	var wanted := expected.duplicate()
	wanted.sort()
	return actual == wanted

func peers_barrier(stage: String) -> bool:
	for peer in range(2,party_size+1):
		if not await barrier(stage+str(peer)): return false
	return true

func host_run() -> void:
	game.network.host_room(relay)
	if not await wait_for(func(): return game.network.state == "lobby","host air lobby"):
		await finish(false,"host room failed"); return
	publish("room",{"code":game.network.room_code})
	if not await peers_barrier("joined") or not await wait_for(func(): return game.network.connected_player_count() == party_size,"all air peers authenticated"):
		await finish(false,"joins failed"); return
	game.network.start_match(OPTIONS,game.selected_characters)
	if not await wait_for(playing,"host playing") or not await peers_barrier("started"):
		await finish(false,"start failed"); return
	game.rounds.running = false
	check(game.players.size() == party_size,"actual party workers")
	for batch in 3:
		var expected: Array = AirEnemyCatalog.CLASS_ORDER.slice(batch*4,batch*4+4)
		for index in expected.size():
			var aircraft = game.AIR_ENEMY.instantiate()
			aircraft.kind = expected[index]
			aircraft.game = game
			aircraft.wave = AirEnemyCatalog.INTRO_WAVES[aircraft.kind]
			aircraft.position = Vector2(850+index*150,100+index*13)
			game.scenario_combat.configure_enemy(aircraft,aircraft.wave,index)
			game.add_child(aircraft)
			aircraft.position = Vector2(850+index*150,100+index*13)
			aircraft.set_physics_process(false)
			aircraft.entered = true
			aircraft.entry_time = AirEnemyCatalog.ENTRY_GRACE
			aircraft._fire_at(aircraft.global_position+Vector2(-150,150))
		for projectile in ordnance(): projectile.set_physics_process(false)
		check(air_nodes().size() == 4 and ordnance().size() == 4,"four distinct real hulls and physical shots per batch")
		publish("batch"+str(batch),{"kinds":expected})
		if not await peers_barrier("seen"+str(batch)+"_"):
			await finish(false,"new air snapshots or spatial events failed"); return
		if batch == 2:
			var departed_slot := party_size
			publish("drop")
			if relay.is_empty(): game.network.transport.disconnect_guest(int(game.network._slots[departed_slot].wire))
			if not await wait_for(func(): return paused and game.network.state == "reconnecting","real air guest loss"):
				await finish(false,"loss did not pause"); return
			if not await barrier("rejoined",15.0) or not await wait_for(playing,"air guest reauthenticated",15.0):
				await finish(false,"air reconnect failed"); return
			check(kinds_match(expected),"existing authoritative aircraft survive reconnect")
			publish("resumed")
			if not await peers_barrier("resumed_"):
				await finish(false,"resumed hulls failed"); return
		var victim = air_nodes()[0]
		var kind: String = victim.kind
		var before_kills: int = game.stats.kills
		var before_xp: float = game.players[0].progression.xp
		var before_level: int = game.players[0].progression.level
		game.combat_hit(victim,victim.hp*4.0+100.0,game.players[0])
		victim.die()
		check(game.stats.kills == before_kills+1 and (game.players[0].progression.xp > before_xp or game.players[0].progression.level > before_level),"authoritative aircraft death grants one kill and credited finite XP")
		expected.erase(kind)
		publish("death"+str(batch),{"kinds":expected,"kills":game.stats.kills,"xp":game.players[0].progression.xp})
		if not await peers_barrier("dead"+str(batch)+"_"):
			await finish(false,"death replicated incorrectly"); return
		for node in air_nodes()+ordnance(): node.queue_free()
		await delay(0.12)
		publish("clear"+str(batch))
		if not await peers_barrier("clear"+str(batch)+"_"):
			await finish(false,"retirement failed"); return
	publish("finished")
	if not await peers_barrier("finished_"):
		await finish(false,"peer completion failed"); return
	await finish(failures == 0,"twelve hulls, spatial events, finite kills and reconnect over actual transport")

func guest_run() -> void:
	if not await barrier("room"):
		await finish(false,"room missing"); return
	game.network.join_room(relay,str(read_stage("room").code))
	if not await wait_for(func(): return game.network.state == "lobby" and game.network._authenticated,"air guest lobby"):
		await finish(false,"guest join failed"); return
	publish("joined"+str(slot))
	if not await wait_for(playing,"air guest playing"):
		await finish(false,"guest start failed"); return
	check(game.network.local_player_id == slot,"guest retains authenticated player slot")
	publish("started"+str(slot))
	for batch in 3:
		if not await barrier("batch"+str(batch)):
			await finish(false,"batch missing"); return
		var expected: Array = read_stage("batch"+str(batch)).kinds
		if not await wait_for(func(): return kinds_match(expected) and ordnance().size() == 4,"all new aircraft and shots arrive"):
			await finish(false,"air state missing"); return
		for aircraft in air_nodes():
			check(aircraft.profile == AirEnemyCatalog.profile(aircraft.kind),"immutable replicated profile "+aircraft.kind)
			check(not aircraft.is_physics_processing() and not aircraft.authoritative() and aircraft.collision_mask == 0,"guest air AI remains presentation only with no moving collision response "+aircraft.kind)
			var hp: float = aircraft.hp
			var projectiles_before := ordnance().size()
			aircraft._fire_at(Vector2.ZERO)
			aircraft.take_damage(hp+1.0)
			aircraft.die()
			check(not aircraft.dead and aircraft.hp == hp and ordnance().size() == projectiles_before,"guest cannot fire damage or retire "+aircraft.kind)
			var clock: float = aircraft.flight_presentation.clock
			await delay(0.035)
			check(aircraft.flight_presentation.clock > clock,"frozen guest parent keeps animated propulsion "+aircraft.kind)
		check(game.network.world.last_error.is_empty(),"all twelve profile records pass audited wire validation")
		check(game.audio.voices.any(func(voice): return str(voice.get_meta("kind","")).begins_with("air_") and voice.get_meta("acoustic_source",Vector2.ZERO).x > 700),"native positioned aircraft weapon event arrives from its world source")
		publish("seen"+str(batch)+"_"+str(slot))
		if batch == 2:
			if not await barrier("drop"):
				await finish(false,"drop missing"); return
			if slot == party_size:
				if not relay.is_empty(): game.network._websocket.close(1000,"Air reconnect fixture")
				if not await wait_for(func(): return game.network.state == "reconnecting","guest own loss") or not await wait_for(playing,"guest air restore",15.0):
					await finish(false,"guest restore failed"); return
				check(kinds_match(expected),"reconnect restores twelve-class final batch without duplicates")
				publish("rejoined")
			if not await barrier("resumed") or not await wait_for(playing,"remaining crew resumes"):
				await finish(false,"crew restore failed"); return
			check(kinds_match(expected),"all crew see same surviving aircraft")
			publish("resumed_"+str(slot))
		if not await barrier("death"+str(batch)):
			await finish(false,"death missing"); return
		var state := read_stage("death"+str(batch))
		if not await wait_for(func(): return kinds_match(state.kinds) and game.stats.kills == int(state.kills),"host death applied exactly once"):
			await finish(false,"death missing on guest"); return
		check(is_equal_approx(game.players[0].progression.xp,float(state.xp)),"credited host XP replicates without local duplicate reward")
		publish("dead"+str(batch)+"_"+str(slot))
		if not await barrier("clear"+str(batch)) or not await wait_for(func(): return air_nodes().is_empty() and ordnance().is_empty(),"dynamic air objects retire"):
			await finish(false,"clear failed"); return
		publish("clear"+str(batch)+"_"+str(slot))
	if not await barrier("finished"):
		await finish(false,"finish missing"); return
	publish("finished_"+str(slot))
	await delay(0.2)
	await finish(failures == 0,"all aircraft stay host-authoritative, spatial and animated through reconnect")
