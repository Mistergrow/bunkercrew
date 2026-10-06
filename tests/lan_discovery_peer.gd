class_name BetaLanDiscoveryCheck
extends "res://tests/network_gameplay_peer.gd"
## Four real processes use ordinary adapter discovery and its loopback fallback.
## This proves the local default path, not discovery across two physical devices.
const JoinCode := preload("res://scripts/network_join_code.gd")
const Transport := preload("res://scripts/network_transport.gd")
var slot := 1
var resolution: Dictionary = {}

func _run() -> void:
	overall_timeout_ms=35000
	role=OS.get_environment("LASTSHIFT_GAMEPLAY_ROLE")
	prefix=OS.get_environment("LASTSHIFT_GAMEPLAY_PATH")
	slot=OS.get_environment("LASTSHIFT_PARTY_SLOT").to_int()
	if slot not in [1,2,3,4] or prefix.is_empty() or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		print("NETWORK_GAMEPLAY_FAIL invalid LAN arguments")
		quit(1)
		return
	publish("identity"+str(slot),preload("res://tests/internet_peer_identity.gd").capture())
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.combat_events.persistence_enabled=false
	game.hud.overlay="network"
	game.network.listen_port=OS.get_environment("LASTSHIFT_TEST_PORT").to_int()
	game.network.lan_discovery_port=OS.get_environment("LASTSHIFT_TEST_DISCOVERY_PORT").to_int()
	if not check(game.network.listen_port>1024 and game.network.lan_discovery_port>1024 and game.network.listen_port!=game.network.lan_discovery_port,"Fixture uses distinct isolated UDP ports"):
		await finish(false,"ports"); return
	if not check(game.network.lan_discovery_targets.is_empty(),"Session retains ordinary empty discovery targets"):
		await finish(false,"targets"); return
	if slot==1: await lan_host()
	else: await lan_guest()

func lan_host() -> void:
	game.network.host_room("")
	if not await wait_for(func():return game.network.state=="lobby","actual LAN host",8):
		await finish(false,"host"); return
	check(JoinCode.is_lan_code(game.network.room_code) and JoinCode.compact(game.network.room_code).length()==16,"Host creates the actual authenticated 16-symbol LAN invitation")
	check(game.network.relay_url.is_empty() and game.network.transport.lan_address in Transport.lan_addresses(),"Host advertises its selected actual LAN adapter without a relay")
	check(is_instance_valid(game.network.lan_discovery) and game.network.lan_discovery.discovery_targets.is_empty(),"Host opens ordinary production LAN discovery")
	# A wildcard UDP responder uses the route to each querying adapter. Its
	# actual source can differ from the preferred adapter shown in the lobby.
	publish("room",{"code":game.network.room_code,"address":game.network.transport.lan_address,"adapters":IP.get_local_addresses(),"port":game.network.listen_port})
	for peer_slot in range(2,5):
		if not await barrier("joined"+str(peer_slot),12):
			await finish(false,"join"); return
	if not await wait_for(func():return game.network.connected_player_count()==4,"four authenticated LAN slots",8):
		await finish(false,"slots"); return
	check(game.network._slots.size()==3 and game.network._slots.values().all(func(peer):return bool(peer.get("_authenticated",false))),"Three independent LAN guests complete the real game authentication")
	for peer_slot in range(2,5):
		check(game.network.is_player_connected(peer_slot),"Host authenticates LAN player "+str(peer_slot))
	check(game.network.lan_discovery.sent_responses>=3,"Discovery replies travel through the actual UDP responder")
	publish("checked",{"count":game.network.connected_player_count(),"responses":game.network.lan_discovery.sent_responses})
	for peer_slot in range(2,5):
		if not await barrier("verified"+str(peer_slot),8):
			await finish(false,"guest verification"); return
	publish("finish")
	for peer_slot in range(2,5):
		if not await barrier("passed"+str(peer_slot),8):
			await finish(false,"guest cleanup"); return
	publish("result1",{"checks":checks,"failures":failures,"scope":"same-host adapter broadcast and ordinary fallback","responses":game.network.lan_discovery.sent_responses})
	await finish(failures==0,"four authenticated peers through default LAN discovery")

func lan_guest() -> void:
	if not await barrier("room",8):
		await finish(false,"room"); return
	var room: Dictionary=read_stage("room")
	game.network.join_room("",str(room.code))
	if not check(is_instance_valid(game.network.lan_discovery),"The LAN invitation enters actual UDP discovery before ENet"):
		await finish(false,"discovery"); return
	var discovery=game.network.lan_discovery
	var targets: Array=discovery._targets.duplicate()
	var initial_requests: int=discovery.sent_requests
	check(discovery.discovery_targets.is_empty() and "255.255.255.255" in targets and "127.0.0.1" in targets,"Ordinary discovery opens actual adapter broadcast and the documented fallback")
	check(initial_requests==targets.size() and initial_requests>=2,"Every actual adapter/fallback query was accepted by the UDP socket")
	discovery.found.connect(func(address: String,port: int):resolution={"sender":address,"port":port,"targets":targets,"initial_requests":initial_requests,"sent_requests":discovery.sent_requests,"source":"loopback fallback" if address.begins_with("127.") else "LAN adapter"})
	if not await wait_for(func():return game.network.state=="lobby" and game.network._authenticated,"authenticated discovered guest",12):
		await finish(false,"authentication"); return
	check(not resolution.is_empty() and int(resolution.port)==int(room.port) and (str(resolution.sender) in room.get("adapters",[]) or str(resolution.sender)=="127.0.0.1"),"Valid discovery resolves an actual host adapter and authenticated game port")
	check(not resolution.is_empty() and game.network._address==str(resolution.sender) and game.network._port==int(resolution.port),"Authenticated ENet connects to the actual UDP sender and returned port")
	check(game.network.local_player_id==slot and game.network.relay_url.is_empty(),"ENet assigns this independent discovered client its own slot")
	publish("joined"+str(slot))
	if not await barrier("checked",12) or not await wait_for(func():return game.network.connected_player_count()==4,"complete LAN lobby",8):
		await finish(false,"lobby"); return
	check(game.network.connected_player_count()==4 and game.network.room_code==str(room.code),"The authenticated lobby retains all four participants and the shared invitation")
	publish("verified"+str(slot))
	if not await barrier("finish",8):
		await finish(false,"finish"); return
	publish("result"+str(slot),{"checks":checks,"failures":failures,"resolution":resolution,"scope":"same-host adapter broadcast and ordinary fallback"})
	publish("passed"+str(slot))
	await finish(failures==0,"default adapter-bound discovery completed")
