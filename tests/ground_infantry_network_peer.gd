extends "res://tests/network_gameplay_peer.gd"
## Real ENet carries all six infantry roles, finite treatment and physical rounds.
const EXTRA_ROLES := ["scout","heavy_gunner","marksman","combat_medic"]
const TROOP_COUNT := 7 # Original three soldiers plus four new role introductions.
func troops() -> Array:
	return get_nodes_in_group("human_enemies").filter(func(unit):return unit.game==game and not unit.is_queued_for_deletion())

func check_camera(id: int,value: float) -> void:
	var followed: Array=game.player_camera.follow_players()
	check(followed.size()==1 and followed[0].player_id==id,"Online camera follows only the local player's real node")
	check(is_equal_approx(game.player_camera.view_zoom,value),"Local zoom remains independent of authoritative snapshots")

func host_run() -> void:
	game.network.host_room("")
	publish("room",{"code":game.network.room_code})
	if not await barrier("joined"):
		await finish(false,"lobby")
		return
	game.network.start_match(OPTIONS,game.selected_characters)
	if not await wait_for(func():return playing(),"host match") or not await barrier("guest_started"):
		await finish(false,"start")
		return
	game.set_camera_zoom(1.1)
	game.rounds.set_process(false)
	game.medic.set_physics_process(false)
	for player in game.players: player.set_physics_process(false)
	var roster:=EnemyCatalog.wave_roster(6,Balance.WAVE_COUNTS[5],false)
	for index in roster.size():
		if not roster[index] in ["grenadier","rifle_guard"]: continue
		game.spawn_enemy(6,index,roster.size())
		var unit=troops()[-1]
		unit.set_physics_process(false)
		unit.position=Vector2(1120-unit.squad_slot*70,430)
		unit.stance=.8
		unit.target=game.core
		unit._pose_parts()
		unit.abilities.prepare_attack(Vector2(840,390))
		unit.windup=.65
	check(troops().size()==3,"Actual wave factory allocates exactly one grenadier and two covering soldiers")
	for kind: String in EXTRA_ROLES:
		var intro: int=EnemyCatalog.INTRO_WAVES[kind]
		var count: int=Balance.WAVE_COUNTS[intro-1]
		var introduced:=EnemyCatalog.wave_roster(intro,count,false)
		var slot:=introduced.find(kind)
		if not check(slot>=0,kind+" is present at its actual introduction wave"):
			await finish(false,"missing introduction")
			return
		game.spawn_enemy(intro,slot,count)
		var unit=troops()[-1]
		unit.set_physics_process(false)
		unit.position=Vector2(1230+EXTRA_ROLES.find(kind)*60,430)
		unit.stance=.8
		unit.target=game.core
		unit._pose_parts()
		unit.abilities.prepare_attack(Vector2(840,390))
		unit.windup=.65
	check(troops().size()==TROOP_COUNT,"Every introduced role uses the real wave factory and human scene")
	check_camera(1,1.1)
	publish("squad")
	if not await barrier("squad_seen"):
		await finish(false,"squad")
		return
	var grenadier=troops().filter(func(unit):return unit.kind=="grenadier")[0]
	check(grenadier.abilities.fire_projectiles(Vector2(840,390),20),"Host releases a real bounded grenade")
	var grenade=get_nodes_in_group("ground_ordnance")[0]
	grenade.set_physics_process(false)
	publish("grenade")
	if not await barrier("grenade_seen"):
		await finish(false,"grenade")
		return
	var medic=troops().filter(func(unit):return unit.kind=="combat_medic")[0]
	var wounded=troops().filter(func(unit):return unit.kind=="heavy_gunner")[0]
	medic.position=wounded.position+Vector2(42,0)
	wounded.hp-=30
	medic.windup=0
	medic.worker_windup=0
	medic.burst_remaining=0
	medic.abilities.aim_locked=false
	medic.abilities.repair_clock=0
	check(medic.abilities.try_treat(),"Host begins treatment of a nearby wounded human")
	check(is_equal_approx(wounded.hp,wounded.max_hp-30),"Treatment has a real windup before health changes")
	medic.abilities.update(1.01)
	check(is_equal_approx(wounded.hp,wounded.max_hp-10) and is_equal_approx(medic.abilities.repair_remaining,40),"Host spends exactly twenty finite supplies for twenty health")
	publish("treated",{"hp":wounded.hp,"reserve":medic.abilities.repair_remaining,"healed":medic.abilities.repaired_total})
	if not await barrier("treatment_seen"):
		await finish(false,"treatment")
		return
	check_camera(1,1.1)
	game.network.transport.disconnect_guest()
	if not await wait_for(func():return game.network.state=="reconnecting" and paused,"host disconnect") or not await wait_for(func():return playing(),"host reconnect",12):
		await finish(false,"reconnect")
		return
	if not await barrier("reconnected",12):
		await finish(false,"reconnected")
		return
	check(troops().size()==TROOP_COUNT and is_instance_valid(grenade),"Reconnect retains every authoritative role and ordnance")
	check(is_equal_approx(medic.abilities.repair_remaining,40),"Reconnect does not refill the medic's finite supplies")
	check_camera(1,1.1)
	publish("host_passed")
	if not await barrier("guest_passed"):
		await finish(false,"completion")
		return
	publish("finish")
	await finish(failures==0,"human squad, grenade marker, real projectile, reconnect and independent cameras")

func guest_run() -> void:
	game.network.join_room("",str(read_stage("room").get("code","")))
	if not await wait_for(func():return game.network.peer_connected and game.network.state=="lobby","guest lobby"):
		await finish(false,"lobby")
		return
	publish("joined")
	if not await wait_for(func():return playing() and game.network.received_snapshots>=3,"guest match"):
		await finish(false,"start")
		return
	game.set_camera_zoom(1.7)
	publish("guest_started")
	if not await barrier("squad") or not await wait_for(func():return troops().size()==TROOP_COUNT,"all human role replicas"):
		await finish(false,"squad")
		return
	for unit in troops():
		check(unit.get_script().resource_path=="res://scripts/ground_infantry.gd" and unit.has_node("InfantryRig"),"Replica creates the actual human scene and animated rig")
		check(not unit.is_physics_processing() and is_equal_approx(unit.stance,.8),"Replica retains the crouch pose without a second AI simulation")
		check(unit.abilities.aim_locked and unit.abilities.aim_point==Vector2(840,390),"Fixed grenade/rifle aim is serialized through the ability child")
		check(not unit.abilities.fire_projectiles(Vector2(840,390),20),"Replica cannot spawn new authoritative bullets")
	check_camera(2,1.7)
	publish("squad_seen")
	if not await barrier("grenade") or not await wait_for(func():return get_nodes_in_group("air_projectiles").any(func(shot):return shot.flavor=="grenade"),"real grenade replica"):
		await finish(false,"grenade")
		return
	var grenade=get_nodes_in_group("air_projectiles").filter(func(shot):return shot.flavor=="grenade")[0]
	check(grenade.gravity==380 and grenade.velocity.y<0 and not grenade.is_physics_processing(),"Host-authored ballistic grenade is visible but cannot simulate guest damage")
	check_camera(2,1.7)
	publish("grenade_seen")
	if not await barrier("treated"):
		await finish(false,"treatment")
		return
	var medic=troops().filter(func(unit):return unit.kind=="combat_medic")[0]
	var wounded=troops().filter(func(unit):return unit.kind=="heavy_gunner")[0]
	var expected:=read_stage("treated")
	if not await wait_for(func():return is_equal_approx(wounded.hp,float(expected.hp)) and is_equal_approx(medic.abilities.repair_remaining,float(expected.reserve)),"authoritative treatment result"):
		await finish(false,"treatment snapshot")
		return
	check(is_equal_approx(medic.abilities.repaired_total,float(expected.healed)),"Replica receives actual healed total with the supply reserve")
	medic.abilities.repair_clock=0
	var previous_hp: float=wounded.hp
	var previous_reserve: float=medic.abilities.repair_remaining
	check(not medic.abilities.try_treat(),"Guest cannot begin its own treatment")
	medic.abilities.update(1.01)
	check(wounded.hp==previous_hp and medic.abilities.repair_remaining==previous_reserve,"Guest ability update cannot duplicate health or consume supplies")
	publish("treatment_seen")
	if not await wait_for(func():return game.network.state=="reconnecting" and paused,"guest disconnect") or not await wait_for(func():return playing(),"guest reconnect",12):
		await finish(false,"reconnect")
		return
	check(troops().size()==TROOP_COUNT,"Authenticated rejoin reconstructs all six human roles")
	medic=troops().filter(func(unit):return unit.kind=="combat_medic")[0]
	check(is_equal_approx(medic.abilities.repair_remaining,40),"Rejoined guest retains the spent medical supplies")
	check_camera(2,1.7)
	publish("reconnected")
	if not await barrier("host_passed"):
		await finish(false,"host completion")
		return
	publish("guest_passed")
	if not await barrier("finish"):
		await finish(false,"finish")
		return
	await finish(failures==0,"human types, aim markers, crouches, grenade authority and local camera preferences")
