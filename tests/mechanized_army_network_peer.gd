extends "res://tests/network_gameplay_peer.gd"
## Real ENet replication of the factory-spawned vehicle rig and physical rounds.
const KINDS := ["scout_car","mortar_carrier"]

func vehicles() -> Array:
	return get_nodes_in_group("enemies").filter(func(unit):return unit.game==game and unit.kind in KINDS and not unit.is_queued_for_deletion())

func rounds_in_flight() -> Array:
	return get_nodes_in_group("air_projectiles").filter(func(shot):return shot.game==game and not shot.is_queued_for_deletion())

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
	game.rounds.set_process(false)
	game.medic.set_physics_process(false)
	for player in game.players: player.set_physics_process(false)
	for kind: String in KINDS:
		var wave: int=EnemyCatalog.INTRO_WAVES[kind]
		var count: int=Balance.WAVE_COUNTS[wave-1]
		var roster:=EnemyCatalog.wave_roster(wave,count,false)
		if not check(roster.has(kind),kind+" occurs in its actual introduction wave"):
			await finish(false,"roster")
			return
		game.spawn_enemy(wave,roster.find(kind),count)
		var unit=vehicles()[-1]
		unit.set_physics_process(false)
		unit.position=Vector2(1250+KINDS.find(kind)*220,430)
		unit.target=game.core
		unit.moving=false
		unit._pose_parts()
		unit.abilities.prepare_attack(Vector2(1080,390))
		unit.windup=float(unit.profile.windup)*.7
		check(unit.profile.legs==0 and not unit.is_in_group("human_enemies"),kind+" is a machine vehicle without hidden walker legs")
	check(vehicles().size()==2,"Factory creates both vehicle classes")
	publish("vehicles")
	if not await barrier("vehicles_seen"):
		await finish(false,"vehicle replicas")
		return
	for unit in vehicles():
		var before:=rounds_in_flight().size()
		check(unit.abilities.fire_projectiles(Vector2(1080,390),float(unit.profile.damage)),unit.kind+" host releases real ordnance")
		check(rounds_in_flight().size()==before+1,unit.kind+" releases exactly one physical round per fire call")
		if rounds_in_flight().size()>before:
			rounds_in_flight()[-1].set_physics_process(false)
	publish("rounds")
	if not await barrier("rounds_seen"):
		await finish(false,"round replicas")
		return
	game.network.transport.disconnect_guest()
	if not await wait_for(func():return game.network.state=="reconnecting" and paused,"host disconnect") or not await wait_for(func():return playing(),"host reconnect",12):
		await finish(false,"reconnect")
		return
	if not await barrier("rejoined",12):
		await finish(false,"rejoin barrier")
		return
	check(vehicles().size()==2 and rounds_in_flight().size()==2,"Reconnect retains original vehicles and rounds without duplicating them")
	publish("host_passed")
	if not await barrier("guest_passed"):
		await finish(false,"completion")
		return
	publish("finish")
	await finish(failures==0,"two vehicle roles, real ordnance, authority and reconnect")

func guest_run() -> void:
	game.network.join_room("",str(read_stage("room").get("code","")))
	if not await wait_for(func():return game.network.peer_connected and game.network.state=="lobby","guest lobby"):
		await finish(false,"lobby")
		return
	publish("joined")
	if not await wait_for(func():return playing() and game.network.received_snapshots>=3,"guest match"):
		await finish(false,"start")
		return
	publish("guest_started")
	if not await barrier("vehicles") or not await wait_for(func():return vehicles().size()==2,"vehicle replicas"):
		await finish(false,"vehicle replicas")
		return
	for unit in vehicles():
		check(unit.get_script().resource_path=="res://scripts/enemy.gd" and EnemyCatalog.is_vehicle(unit.kind),unit.kind+" uses the actual vehicle-capable scene")
		check(not unit.is_physics_processing() and unit.profile.legs==0,unit.kind+" does not run a second movement or combat simulation")
		check(unit.abilities.aim_locked and unit.abilities.aim_point==Vector2(1080,390),unit.kind+" retains the host's locked attack warning")
		check(not unit.abilities.fire_projectiles(Vector2(1080,390),5),unit.kind+" rejects client-authored rounds")
		check(is_equal_approx(float(unit.body_part.material.get_shader_parameter("sprite_alpha_cutoff")),.5),unit.kind+" replica uses the clean vehicle hull edge")
	publish("vehicles_seen")
	if not await barrier("rounds") or not await wait_for(func():return rounds_in_flight().size()==2,"two physical round replicas"):
		await finish(false,"round replicas")
		return
	var bullets:=rounds_in_flight().filter(func(shot):return shot.flavor=="tracer")
	var shells:=rounds_in_flight().filter(func(shot):return shot.flavor=="grenade")
	check(bullets.size()==1 and shells.size()==1,"Guest receives distinct gun and mortar projectile types")
	if bullets.size()==1 and shells.size()==1:
		check(bullets[0].gravity==0 and shells[0].gravity==380 and shells[0].velocity.y<0,"Ballistic mortar arc differs from the scout's straight bullet")
	for shot in rounds_in_flight(): check(not shot.is_physics_processing(),"Replica round cannot apply local damage")
	publish("rounds_seen")
	if not await wait_for(func():return game.network.state=="reconnecting" and paused,"guest disconnect") or not await wait_for(func():return playing(),"guest reconnect",12):
		await finish(false,"reconnect")
		return
	check(vehicles().size()==2 and rounds_in_flight().size()==2,"Authenticated rejoin restores both vehicle types and original ordnance")
	publish("rejoined")
	if not await barrier("host_passed"):
		await finish(false,"host completion")
		return
	publish("guest_passed")
	if not await barrier("finish"):
		await finish(false,"finish")
		return
	await finish(failures==0,"vehicle rigs, warnings, real shells, guest authority and rejoin")
