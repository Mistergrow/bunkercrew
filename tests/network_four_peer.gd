extends "res://tests/network_gameplay_peer.gd"
var slot:=1
var relay:=""
var recruit_fixture := false
const RECRUIT_CHARACTERS := ["oskar","rika","ivo","mara"]
const VoiceCodec:=preload("res://scripts/voice_codec.gd")
var voice_capture: AudioEffectCapture
var voice_capture_started_ms := 0
var voice_capture_discarded_before := 0
var voice_capture_pushed_before := 0
var support_events := 0

func _run() -> void:
	overall_timeout_ms=maxi(overall_timeout_ms,60000)
	role=OS.get_environment("LASTSHIFT_GAMEPLAY_ROLE")
	slot=int(OS.get_environment("LASTSHIFT_PARTY_SLOT"))
	prefix=OS.get_environment("LASTSHIFT_GAMEPLAY_PATH")
	relay=OS.get_environment("LASTSHIFT_PARTY_RELAY")
	recruit_fixture=OS.get_environment("LASTSHIFT_PARTY_RECRUITS")=="1"
	if recruit_fixture:
		CrewRoster.unlock("oskar")
		CrewRoster.unlock("rika")
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.hud.overlay="network"
	game.audio.set_music_volume(0.0)
	game.audio.set_sfx_volume(0.0)
	game.voice.set_enabled(true)
	game.combat_events.event.connect(func(kind: String,data: Dictionary):
		if kind=="support" and data.get("action")=="team" and int(data.get("player_id",0))==slot: support_events+=1)
	voice_capture=AudioEffectCapture.new()
	voice_capture.buffer_length=6.0
	AudioServer.add_bus_effect(0,voice_capture)
	game.network.listen_port=24917
	game.network.lan_discovery_port=24918
	game.network.lan_discovery_targets.assign(["127.0.0.1"])
	if slot==1: await host_run()
	else: await guest_run()

func loaded() -> bool:
	return game.started and game.network.state=="playing" and not game.network._loading and not paused

func personal_marker_matches(actual: Variant, expected: Variant) -> bool:
	# Coordination JSON parses integers as floats. Dictionary equality compares
	# their Variant types, so compare every discrete quantity exactly instead.
	if actual is Dictionary:
		if not expected is Dictionary or actual.size()!=expected.size(): return false
		for field in actual:
			if not expected.has(field) or not personal_marker_matches(actual[field],expected[field]): return false
		return true
	if actual is int:
		return (expected is int or expected is float) and is_finite(float(expected)) and float(expected)==floorf(float(expected)) and actual==int(expected)
	if actual is float:
		return (expected is int or expected is float) and is_finite(float(expected)) and absf(actual-float(expected))<=maxf(1e-10,absf(actual)*1e-12)
	return typeof(actual)==typeof(expected) and actual==expected

func each_barrier(label: String) -> bool:
	for id in range(2,5):
		if not await barrier(label+str(id),15): return false
	return true

func begin_voice_capture() -> void:
	# Cold imports and Wine startup are outside the simultaneous voice window.
	# Read the real AudioServer output only after every peer has a fresh buffer.
	voice_capture.clear_buffer()
	voice_capture_started_ms = Time.get_ticks_msec()
	voice_capture_discarded_before = voice_capture.get_discarded_frames()
	voice_capture_pushed_before = voice_capture.get_pushed_frames()

func send_tone() -> void:
	# Attempt a forged speaker first. Real sequence-one packets from that player
	# must still be accepted; the host cannot trust a voice payload identity.
	var silence:=PackedByteArray()
	silence.resize(VoiceCodec.BYTES)
	if slot!=1:
		var forged:={"kind":"voice","seq":9999,"generation":game.network._generation,"rate":VoiceCodec.RATE,"pcm":silence,"player_id":2 if slot!=2 else 3}
		game.network._send_encoded(game.network.Protocol.encode(forged),false,0,2)
	for packet_index in 40:
		var samples:=PackedFloat32Array()
		for frame in VoiceCodec.FRAMES:
			samples.append(.16*sin(TAU*float(330+slot*110)*float(packet_index*VoiceCodec.FRAMES+frame)/VoiceCodec.RATE))
		game.network.send_voice(VoiceCodec.encode(samples))
		await delay(.02)

func check_voices() -> void:
	if relay.is_empty():
		for remote in game.network.transport.remote_peers.values():
			print("VOICE_ENET ",role," throttle=",remote.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE)," limit=",remote.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_LIMIT)," loss=",remote.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS)," rtt=",remote.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	check(game.network._voice_sources.size()==3 and game.network._voice_sources.values().all(func(stream):return stream.highest>=25 and stream.highest<=40),"Three independently numbered real voices arrive; forged speaker IDs cannot poison sequence tracking")
	print("VOICE_DETAIL ",role," primary=",game.voice._primary_sender," played=",game.voice.played_frames," received=",game.voice.received_frames," queues=",game.voice._receivers.keys()," age=",Time.get_ticks_msec()-started_at)
	for id in game.network._voice_sources:
		var stream: Dictionary=game.network._voice_sources[id]
		print("VOICE_SOURCE ",id," recv=",stream.get("received",0)," accept=",stream.get("audio_accepted",0)," highest=",stream.highest)
	for id in game.voice._receivers:
		var receiver=game.voice._receivers[id]
		print("VOICE_CHILD ",id," enabled=",receiver.enabled," played=",receiver.played_frames," received=",receiver.received_frames," dropped=",receiver.dropped_frames," peak=",receiver._receive_peak)
	check(game.voice._receivers.size()==2 and game.voice.played_frames>=20 and game.voice._receivers.values().all(func(receiver):return receiver.played_frames>=20),"Every remote speaker has a separate bounded playback queue")
	var samples:=voice_capture.get_buffer(voice_capture.get_frames_available())
	var power:=0.0
	for sample in samples: power+=sample.length_squared()
	var discarded := voice_capture.get_discarded_frames() - voice_capture_discarded_before
	print("VOICE_MIX ",role," frames=",samples.size()," rms=",sqrt(power/maxf(1,samples.size()*2))," window_ms=",Time.get_ticks_msec()-voice_capture_started_ms," pushed=",voice_capture.get_pushed_frames()-voice_capture_pushed_before," discarded=",discarded)
	check(discarded==0,"The measured voice window fits its real capture buffer")
	check(samples.size()>8000 and sqrt(power/maxf(1,samples.size()*2))>.02,"All voices reach the actual AudioServer mix without opening the microphone")
	check(not game.microphone.capturing,"Network audio fixture leaves the physical microphone closed")

func host_run() -> void:
	game.network.host_room(relay)
	if not await wait_for(func():return game.network.state=="lobby","host lobby"): await finish(false,"host"); return
	publish("room",{"code":game.network.room_code})
	if not await each_barrier("joined") or not await wait_for(func():return game.network.connected_player_count()==4,"four authenticated slots"):
		await finish(false,"four joins"); return
	check(game.network.is_player_connected(4),"Host sees four independently connected participants")
	if recruit_fixture: game.selected_characters.assign(RECRUIT_CHARACTERS)
	publish("crew_authenticated", {"count":game.network.connected_player_count()})
	game.network.start_match(OPTIONS,game.selected_characters)
	if not await wait_for(loaded,"four-way ready barrier") or not await each_barrier("started"):
		await finish(false,"start"); return
	game.rounds.running=false
	var expected_characters: Array = RECRUIT_CHARACTERS if recruit_fixture else PartyConfig.DEFAULT_CHARACTERS
	for index in game.players.size():
		check(game.players[index].character_id==expected_characters[index],"Host starts the selected unique character for P%d"%(index+1))
	check(game.players.map(func(player):return player.character_id).size()==4 and PartyConfig.unique_characters(game.selected_characters)==game.selected_characters,"Host starts four distinct character identities")
	if recruit_fixture:
		check(game.players[0].character_id=="oskar" and game.players[1].character_id=="rika","New crew IDs survive the real four-player world handshake")
		check(not game.solo_story.enabled and game.solo_story.npcs.is_empty() and game.solo_story.finds.is_empty(),"Solo encounters never enter a shared network world")
	# Paid SAN software and recovery are introduced after the initial world.
	# Guests must receive new empty stores through audited dynamic entities.
	game.upgrades.points=20
	for id: String in ["bunker_workshop","medic_collection","bunker_dance","bunker_dance_2","bunker_dance_3","bunker_dance_4","bunker_dance_5"]:
		check(game.upgrades.purchase(id),"Host pays actual SAN research: "+id)
	game.medic.set_physics_process(false)
	var steel_store: Supply
	for crate in get_nodes_in_group("supplies"):
		if crate.game==game and crate.kind=="steel": steel_store=crate
	# Prepared finite carried unit remains in transit until the victory commit.
	steel_store.amount-=1
	game.medic.logistics_cargo="steel"
	game.medic.logistics_phase="holding"
	publish("san_research",{"steel":steel_store.amount})
	if not await each_barrier("san_seen"): await finish(false,"SAN recovery replication"); return
	# Allow the native RTT window to recover from four cold scene imports
	# before measuring steady simultaneous voice playback.
	await delay(1.2)
	publish("voice")
	if not await each_barrier("voice_capture_ready"): await finish(false,"voice capture readiness"); return
	begin_voice_capture()
	publish("voice_start")
	await send_tone()
	if not await each_barrier("voiced"): await finish(false,"voice"); return
	await delay(.2)
	check_voices()
	publish("voice_checked")
	if not await each_barrier("voice_asserted"): await finish(false,"voice assertions"); return
	check(game.player_count==4 and game.players.size()==4,"Four actual player entities start together")
	var target=game._entity("enemy",Vector2(1500,430),{"kind":"strider","wave":1})
	target.set_physics_process(false)
	var xp_before: Array=[]
	for player in game.players:
		xp_before.append(player.progression.xp)
		game.combat_events.record_activity(player)
	game.combat_hit(target,10.0,game.players[0])
	var expected_xp: Array=[]
	for index in 4:
		expected_xp.append(game.players[index].progression.xp)
		check(is_equal_approx(float(expected_xp[index])-float(xp_before[index]),.5125),"P%d receives exactly one equal share of the finite2.05XP pool"%(index+1))
	publish("xp",{"values":expected_xp})
	if not await each_barrier("xp_seen"): await finish(false,"shared XP"); return
	target.queue_free()
	await delay(.05)
	game.rounds.wave=20
	game.upgrades.points=30
	game.upgrades.owned["convoy_mg"]=true
	game.upgrades.owned.weapon_magazines=true
	game.upgrades.owned.weapon_pouches=true
	game.players[0].inventory={"steel":3,"ammo":2}
	check(game.expedition.on_victory(),"Four-player campaign commits a prepared defended site")
	check(game.medic.logistics_cargo.is_empty() and game.upgrades.medic_dance_level()==5,"Victory secures the one carried unit and retains all five robot software levels")
	check(game.expedition.handle_command("route",{"id":"harbor"},1),"Host selects destination")
	check(game.expedition.handle_command("load",{"kind":"ammo","amount":1},1),"Host loads finite convoy ammunition")
	check(game.expedition.handle_command("depart",{},1),"Four-player convoy departure reloads all worlds")
	check(game.expedition.boarding_active(),"Four-player departure waits in the actual garage")
	for id in range(1,5):
		game.players[id-1].global_position=game.expedition.vehicle.global_position
		check(game.expedition.vehicle.board(game.players[id-1],game.expedition.vehicle.SEAT_ROLES[id-1]),"P%d occupies an actual garage seat"%id)
	if not await wait_for(func():return loaded() and game.expedition.stage=="travel","host convoy"):
		await finish(false,"host travel"); return
	if not await wait_for(func():return game.expedition.vehicle.journey_state.phase=="driving","actual cinematic and ignition complete",25):
		await finish(false,"ignition");return
	var debug_file:=FileAccess.open("res://artifacts/expedition/network-four-checkpoint.json",FileAccess.WRITE)
	debug_file.store_string(JSON.stringify(game.campaign.checkpoint(),"  "))
	debug_file.close()
	check(CampaignState.valid_checkpoint(game.campaign.checkpoint()),"Host road checkpoint validates all four crew snapshots")
	if not await each_barrier("road"):
		await finish(false,"road"); return
	game.expedition.set_physics_process(false)
	var truck=game.expedition.vehicle
	check(truck.seats.all(func(seat):return is_instance_valid(seat.occupant)),"All four independent seats are occupied")
	var before: float=truck.position.x
	Input.action_press("p1_right")
	await delay(.45)
	Input.action_release("p1_right")
	publish("shoot")
	if not await each_barrier("fired"): await finish(false,"shoot"); return
	await delay(.2)
	check(truck.position.x>before and truck.fuel<12,"Driver input moves all passengers and consumes fuel")
	check(truck.ammo>0 and truck.ammo<20,"P2 reloads and fires the mounted MG with its own packets")
	for id in [3,4]:
		check(game.players[id-1].get_node("WorkerWeapon").current_ammo()<30,"P%d spends its personal weapon magazine from its passenger seat"%id)
	publish("checked")
	if not await each_barrier("seen"): await finish(false,"seen"); return
	var before_spoof: int=truck.ammo
	var p3_before_spoof: int=game.players[2].get_node("WorkerWeapon").current_ammo()
	publish("spoof")
	if not await barrier("spoof_sent"): await finish(false,"slot spoof"); return
	await delay(.2)
	check(truck.ammo==before_spoof and game.players[2].get_node("WorkerWeapon").current_ammo()<p3_before_spoof,"P3 cannot redirect forged player_id2 fire input to P2 or the shared MG")
	for id in [3,4]:
		var worker=game.players[id-1]
		var weapon=worker.get_node("WorkerWeapon")
		worker.inventory={"ammo":1}
		weapon.loaded.rifle=36
		weapon.reserve=179
		weapon.open_pack=0
	publish("refill")
	if not await barrier("refilled3") or not await barrier("refilled4"): await finish(false,"partial supply"); return
	await delay(.2)
	for id in [3,4]:
		var weapon=game.players[id-1].get_node("WorkerWeapon")
		check(weapon.reserve==180 and weapon.open_pack==19 and weapon.current_ammo()==36 and game.players[id-1].inventory.is_empty(),"P%d independently transfers one round and retains19 from its actual20-round crate"%id)
	publish("refill_checked")
	var old_generation: int=game.network._generation
	publish("authority")
	if not await each_barrier("commands"): await finish(false,"authority"); return
	await delay(.2)
	check(game.network._generation==old_generation and game.expedition.stage=="travel","Guest restart and strategic departure commands cannot replace the host world")
	publish("reconnect")
	var wire: int=game.network._slots[3].wire
	if relay.is_empty(): game.network.transport.disconnect_guest(wire)
	else:
		publish("drop3")
	if not await wait_for(func():return paused and game.network.state=="reconnecting","one guest drop"):
		await finish(false,"drop"); return
	publish("try_unpause")
	if not await barrier("unpause_sent"): await finish(false,"pause attack"); return
	await delay(.1)
	check(paused and game.network.match_paused,"Another guest cannot bypass the reconnect pause while P3 is absent")
	if not await barrier("rejoined3",15) or not await wait_for(loaded,"four-way reconnect ready",15):
		await finish(false,"reconnect"); return
	check(game.network.connected_player_count()==4 and game.network.is_player_connected(3),"Reconnect returns the same authenticated P3 slot")
	check(game.players[2].mounted_turret==truck.passenger_left_seat and get_nodes_in_group("convoy_vehicles").size()==1,"P3 retains its own seat and existing truck after reconnect")
	publish("arrive")
	game.expedition.set_physics_process(true)
	truck.position.x=1740
	if not await wait_for(func():return truck.journey_state.phase=="repair","four-player puncture"):
		await finish(false,"puncture");return
	for enemy in get_nodes_in_group("enemies"):
		if enemy.game==game and not enemy.dead: enemy.take_damage(enemy.hp+1)
	var repairer=game.players[0]
	repairer.preferred_focus=truck
	Input.action_press("p1_interact")
	if not await wait_for(func():return truck.journey_state.phase=="reboarding","real wheel work in four-player world",22):
		Input.action_release("p1_interact")
		await finish(false,"wheel");return
	Input.action_release("p1_interact")
	repairer.global_position=truck.global_position
	check(truck.board(repairer,"driver"),"Driver reboards after actual repair")
	if not await wait_for(func():return truck.journey_state.phase=="driving","reboard completed"):
		await finish(false,"reboard");return
	truck.position.x=game.expedition.ROAD_END
	var departure_deadline:=Time.get_ticks_msec()+8000
	var arrival_personal: Dictionary={}
	# Real asynchronous scene changes can leave refresh_game() with no scene
	# for a frame. The protected wait below resumes on the loaded destination.
	while is_instance_valid(game) and is_instance_valid(game.expedition) and game.expedition.stage=="travel" and Time.get_ticks_msec()<departure_deadline:
		for enemy in get_nodes_in_group("enemies"):
			if enemy.game==game and not enemy.dead: enemy.take_damage(enemy.hp+1)
		arrival_personal.clear()
		for player in game.players:
			arrival_personal[str(player.player_id)]=CampaignBonus.snapshot_player(player)
		publish("arrival_personal",{"snapshots":arrival_personal})
		await delay(.05)
	if not await wait_for(func():return loaded() and game.expedition.stage=="occupation","host destination",12) or not await each_barrier("occupied"):
		await finish(false,"occupation"); return
	for player in game.players:
		check(CampaignBonus.snapshot_player(player)==arrival_personal[str(player.player_id)],"P%d retains exact personal rounds, partial pack and earned progression at arrival"%player.player_id)
	for enemy in get_nodes_in_group("enemies"):
		if enemy.game==game and not enemy.dead: enemy.take_damage(enemy.hp+1)
	if not await wait_for(func():return loaded() and game.expedition.stage=="defense","host new defense",12) or not await each_barrier("defense"):
		await finish(false,"defense"); return
	game.rounds.running=false
	check(game.players.size()==4 and game.rounds.wave==1 and game.scenario_options.environment=="abandoned_harbor","All four crew members reach the secured bunker and start the next defense")
	check(game.medic.dance_level()==5 and not game.upgrades.has_upgrade("medic_collection"),"Robot software reaches the next bunker while local recovery infrastructure resets")
	publish("leave4")
	if not await barrier("left4") or not await wait_for(func():return not game.network.is_player_connected(4),"one voluntary guest leave"):
		await finish(false,"leave"); return
	check(paused and game.network.is_player_connected(2) and game.network.is_player_connected(3) and game.network.connected_player_count()==3,"One explicit guest leave pauses only its missing slot and preserves the other two authenticated links")
	publish("finish")
	if not await each_barrier("passed"): await finish(false,"finish"); return
	await finish(failures==0,"four-player ENet identity, input, authority, vehicle and reconnect")

func guest_run() -> void:
	game.network.join_room(relay,str(read_stage("room").get("code","")))
	if not await wait_for(func():return game.network._authenticated and game.network.state=="lobby","guest authentication"):
		await finish(false,"join"); return
	check(game.network.local_player_id==slot,"Server assigns this guest its independent player slot")
	game.network.send_command("character",{"id":RECRUIT_CHARACTERS[slot-1] if recruit_fixture else PartyConfig.DEFAULT_CHARACTERS[slot-1]})
	publish("joined"+str(slot))
	# A fourth native peer may still be cold-starting on another machine. Begin
	# the unchanged world-ready deadline at the actual host start, not at this
	# participant's earlier authenticated lobby admission.
	if not await barrier("crew_authenticated",25): await finish(false,"crew start readiness"); return
	if not await wait_for(loaded,"four-player world"):
		await finish(false,"world"); return
	check(game.players.size()==4 and game.network.connected_player_count()==4,"Guest receives all four player entities and lobby slots")
	var expected_characters: Array = RECRUIT_CHARACTERS if recruit_fixture else PartyConfig.DEFAULT_CHARACTERS
	for index in game.players.size():
		check(game.players[index].character_id==expected_characters[index],"Guest receives the selected unique character for P%d"%(index+1))
	publish("started"+str(slot))
	if not await barrier("san_research") or not await wait_for(func():return game.upgrades.medic_dance_level()==5 and get_nodes_in_group("supplies").filter(func(crate):return crate.game==game).size()==10 and game.medic.logistics_cargo=="steel","new SAN software, dynamic stores and cargo"):
		await finish(false,"SAN snapshot"); return
	check(game.upgrades.has_upgrade("medic_collection") and not game.upgrades.has_upgrade("medic_logistics"),"Recovery research replicates independently of machine feeding")
	check(not game.medic.dance_allowed(),"Guest cargo presentation cannot dance or execute a second inventory transaction")
	check(get_nodes_in_group("supplies").filter(func(crate):return crate.game==game and crate.get_script().resource_path=="res://scripts/convoy_supply.gd").size()==5,"Exactly five new empty material stores replicate dynamically after research")
	publish("san_seen"+str(slot))
	if not await barrier("voice"): await finish(false,"voice"); return
	begin_voice_capture()
	publish("voice_capture_ready"+str(slot))
	if not await barrier("voice_start"): await finish(false,"voice capture start"); return
	await send_tone()
	publish("voiced"+str(slot))
	if not await barrier("voice_checked"): await finish(false,"voice check"); return
	check_voices()
	publish("voice_asserted"+str(slot))
	if not await barrier("xp"): await finish(false,"XP snapshot"); return
	var expected_xp: Array=read_stage("xp").values
	if not await wait_for(func():return is_equal_approx(game.players[slot-1].progression.xp,float(expected_xp[slot-1])),"shared XP snapshot"):
		await finish(false,"shared XP"); return
	check(game.players.all(func(player):return is_equal_approx(player.progression.xp,float(expected_xp[player.player_id-1]))),"All four exact host XP shares replicate without guest-side duplication")
	check(support_events==1,"The local guest receives one team-support feedback event")
	publish("xp_seen"+str(slot))
	if not await wait_for(func():return loaded() and game.expedition.stage=="travel","guest road",15):
		await finish(false,"road"); return
	if not await wait_for(func():return game.expedition.vehicle.journey_state.phase=="driving","actual replicated cinematic and ignition complete",25):
		await finish(false,"ignition"); return
	var truck=game.expedition.vehicle
	check(game.players[slot-1].mounted_turret==truck.seats[slot-1],"Own player is attached to its replicated convoy seat")
	publish("road"+str(slot))
	if not await barrier("shoot"): await finish(false,"shoot wait"); return
	if slot==2:
		Input.action_press("p1_reload")
		await delay(.12)
		Input.action_release("p1_reload")
		if not await wait_for(func():return truck.ammo==20,"own mounted reload"):
			await finish(false,"reload"); return
	Input.action_press("p1_fire")
	await delay(.25)
	Input.action_release("p1_fire")
	publish("fired"+str(slot))
	if not await barrier("checked"): await finish(false,"checked"); return
	check(game.players[slot-1].mounted_turret==truck.seats[slot-1],"Personal firing keeps the correct occupant mounted")
	publish("seen"+str(slot))
	if slot==3:
		if not await barrier("spoof"): await finish(false,"spoof wait"); return
		game.network.set_physics_process(false)
		for attempt in 8:
			game.network._input_seq+=1
			game.network._send({"kind":"input","generation":game.network._generation,"seq":game.network._input_seq,"player_id":2,"input":{"held":{"fire":1.0},"pressed":["fire"] if attempt==0 else [],"released":[],"aim":[3100.0,300.0]}},false)
			await delay(.04)
		game.network.set_physics_process(true)
		publish("spoof_sent")
	if slot in [3,4]:
		if not await barrier("refill") or not await wait_for(func():return game.players[slot-1].get_node("WorkerWeapon").reserve==179,"finite crate refill setup"):
			await finish(false,"refill setup"); return
		Input.action_press("p1_reload")
		await delay(.15)
		Input.action_release("p1_reload")
		if not await wait_for(func():return game.players[slot-1].get_node("WorkerWeapon").open_pack==19,"partial crate reaches own replica"):
			await finish(false,"partial refill"); return
		check(game.players[slot-1].get_node("WorkerWeapon").reserve==180 and game.players[slot-1].inventory.is_empty(),"Own R input fills researched reserve and replicates the finite partial pack")
		publish("refilled"+str(slot))
	if not await barrier("refill_checked"): await finish(false,"refill barrier"); return
	if not await barrier("authority"): await finish(false,"authority"); return
	game.network.send_command("restart")
	game.network.send_command("expedition",{"action":"depart","data":{}})
	publish("commands"+str(slot))
	if not await barrier("reconnect"): await finish(false,"reconnect wait"); return
	if slot==3:
		if not relay.is_empty():
			if not await barrier("drop3"): await finish(false,"drop"); return
			game.network._websocket.close(1000,"Fixture reconnect")
		if not await wait_for(func():return game.network.state=="reconnecting","guest own drop") or not await wait_for(loaded,"guest resumed own slot",15):
			await finish(false,"rejoin"); return
		check(game.network.local_player_id==3 and game.players[2].mounted_turret==game.expedition.vehicle.seats[2],"Rejoined client cannot take another player's slot")
		publish("rejoined3")
	elif slot==2:
		if not await barrier("try_unpause"): await finish(false,"unpause test"); return
		game.network.pause_match(false)
		publish("unpause_sent")
	if not await barrier("arrive",15) or not await wait_for(func():return loaded() and game.expedition.stage=="occupation","new destination generation",35):
		await finish(false,"occupation"); return
	check(game.player_count==4 and game.players.size()==4 and game.scenario_options.environment=="abandoned_harbor","Occupation transition retains all four independent players")
	var arrival_personal: Dictionary=read_stage("arrival_personal").snapshots
	if not await wait_for(func():return personal_marker_matches(CampaignBonus.snapshot_player(game.players[slot-1]),arrival_personal[str(slot)]),"finite personal supplies at destination"):
		await finish(false,"personal arrival");return
	check(personal_marker_matches(CampaignBonus.snapshot_player(game.players[slot-1]),arrival_personal[str(slot)]),"Occupation carries this guest's exact spent rounds, partial crate and earned progression")
	publish("occupied"+str(slot))
	if not await wait_for(func():return loaded() and game.expedition.stage=="defense","secured bunker generation",12):
		await finish(false,"defense"); return
	check(game.rounds.wave==1 and game.players[slot-1].player_id==slot,"New defense preserves this guest's slot and resets waves")
	check(game.medic.dance_level()==5 and not game.upgrades.has_upgrade("medic_collection"),"Guest retains portable robot software across the real generation change")
	publish("defense"+str(slot))
	if slot==4:
		if not await barrier("leave4"): await finish(false,"leave wait"); return
		game.network._send({"kind":"leave"})
		publish("left4")
	if not await barrier("finish",15): await finish(false,"finish"); return
	publish("passed"+str(slot))
	await finish(failures==0,"independent guest %d"%slot)
