class_name BetaPerimeterNetworkCheck
extends "res://tests/network_gameplay_peer.gd"
const Gore=preload("res://scripts/combat_gore.gd")

func site(role_name: String,index: int=0):
	return game.perimeter.sites.filter(func(node):return node.role==role_name)[index]

func frame_arena() -> void:
	game.player_camera.set_process(false)
	game.camera.position=Vector2(1040,400)
	game.camera.zoom=Vector2.ONE
	game.camera.force_update_scroll()

func build_site(target,player,cargo: Dictionary) -> void:
	player.position=target.global_position-Vector2(30,0)
	player.inventory=cargo.duplicate()
	for index in 50: target.interact(player,.2)
	target.set_physics_process(false)

func host_run() -> void:
	game.combat_gore.set_level(0)
	game.network.host_room(OS.get_environment("LASTSHIFT_PERIMETER_RELAY"))
	if not await wait_for(func():return game.network.state=="lobby" and not game.network.room_code.is_empty(),"host room ready"):
		await finish(false,"host creation")
		return
	publish("room",{"code":game.network.room_code})
	if not await barrier("joined"):
		await finish(false,"lobby")
		return
	game.network.start_match(OPTIONS,game.selected_characters)
	if not await wait_for(func():return playing(),"host match") or not await barrier("guest_started"):
		await finish(false,"start")
		return
	frame_arena()
	game.rounds.set_process(false)
	game.rounds.wave=16
	game.medic.set_physics_process(false)
	for player in game.players:
		player.set_physics_process(false)
		player.medical.set_process(false)
	check(site("fence").tier==1 and site("fence").hp==120 and site("fence").builder_player_id==0,"Real host starts with one installed outer mesh and no construction owner")
	publish("starter")
	if not await barrier("starter_seen"):
		await finish(false,"starter replication")
		return
	site("fence").take_damage(37)
	publish("starter_damaged")
	if not await barrier("starter_damage_seen"):
		await finish(false,"starter damage replication")
		return
	site("fence").take_damage(10000)
	publish("starter_destroyed")
	if not await barrier("starter_destruction_seen"):
		await finish(false,"starter destruction replication")
		return
	game.upgrades.owned={"bunker_workshop":true,"bunker_armor":true,"perimeter_automation":true}
	var p=game.players[0]
	build_site(site("fence"),p,{"steel":2})
	for gun_index in 2:
		var gun=site("ground",gun_index)
		build_site(gun,p,{"steel":2,"concrete":1})
		p.inventory={"ammo":gun_index+1}
		for index in 6*(gun_index+1): gun.interact(p,.2)
	check(site("fence").tier==1 and site("ground").ammo==20 and site("ground",1).ammo==40 and p.inventory.get("ammo",0)==0,"Host pays for two independently supplied sentries and a fence")
	var soldier=game._entity("ground_infantry",Vector2(1190,430),{"kind":"rifle_guard","wave":16})
	soldier.set_physics_process(false)
	game.players[1].position=Vector2(1050,430)
	publish("built")
	if not await barrier("built_seen"):
		await finish(false,"build")
		return
	var rig: Dictionary=Gore._rig(soldier)
	ImpactBurst.contact(game,soldier,rig[8].tip,Vector2.LEFT,Vector2.RIGHT,1.0,"cannon")
	game.combat_hit(soldier,999,p)
	check(soldier.gore_mask==8 and game.combat_gore.parts.is_empty() and game.combat_gore.particles.is_empty(),"Host Off preserves authoritative limb selection and hides local blood")
	publish("fatal")
	if not await barrier("fatal_seen"):
		await finish(false,"fatal hit")
		return
	var worker=game.players[1]
	worker.invulnerability=0
	var limbs: Dictionary=Gore._rig(worker)
	ImpactBurst.contact(game,worker,limbs[2].tip,Vector2.LEFT,Vector2.RIGHT,1.0,"cannon")
	worker.take_damage(999,Vector2.RIGHT)
	check(worker.is_downed() and worker.gore_mask>0,"Host accepts real player KO with medical system intact")
	publish("ko")
	if not await barrier("ko_seen"):
		await finish(false,"player KO")
		return
	worker.medical.state="wounded"
	worker._restore_from_aid(.35)
	publish("revived")
	if not await barrier("revive_seen"):
		await finish(false,"player revival")
		return
	var survivor=game._entity("enemy",Vector2(1400,430),{"kind":"strider","wave":16})
	survivor.set_physics_process(false)
	await delay(.25)
	publish("drop_guest")
	if OS.get_environment("LASTSHIFT_PERIMETER_RELAY").is_empty(): game.network.transport.disconnect_guest()
	if not await wait_for(func():return game.network.state=="reconnecting" and paused,"host disconnect") or not await wait_for(func():return playing(),"host rejoin",12):
		await finish(false,"reconnect")
		return
	if not await barrier("reconnected",12):
		await finish(false,"guest rejoin")
		return
	var new_enemy=game._entity("enemy",Vector2(1480,430),{"kind":"strider","wave":16})
	new_enemy.set_physics_process(false)
	var fresh: Dictionary=game.network.world.capture()
	var ids: Array=fresh.entities.map(func(record):return record.id)
	var unique: Dictionary={}
	for id in ids: unique[id]=true
	check(unique.size()==ids.size() and survivor.get_meta("network_entity_id")!=new_enemy.get_meta("network_entity_id"),"Post-reconnect spawn reserves every surviving dynamic ID")
	check(site("ground").ammo==20 and site("ground",1).ammo==40 and game.combat_gore.level==0,"Reconnect retains finite ammunition and host-local violence setting")
	publish("host_passed")
	if not await barrier("guest_passed"):
		await finish(false,"completion")
		return
	publish("finish")
	await finish(failures==0,"defense construction, independent cosmetics and authoritative KO/revive")

func guest_run() -> void:
	game.combat_gore.set_level(2)
	game.network.join_room(OS.get_environment("LASTSHIFT_PERIMETER_RELAY"),str(read_stage("room").get("code","")))
	if not await wait_for(func():return game.network.peer_connected and game.network.state=="lobby","guest lobby"):
		await finish(false,"lobby")
		return
	publish("joined")
	if not await wait_for(func():return playing() and game.network.received_snapshots>=3,"guest match"):
		await finish(false,"start")
		return
	frame_arena()
	publish("guest_started")
	if not await barrier("starter") or not await wait_for(func():return site("fence").tier==1 and site("fence").hp==120,"installed outer fence snapshot"):
		await finish(false,"starter")
		return
	check(site("fence").builder_player_id==0 and site("fence").collision_layer==3,"Guest receives the installed physical outer line without a paid builder")
	publish("starter_seen")
	if not await barrier("starter_damaged") or not await wait_for(func():return site("fence").hp==83,"damaged outer fence snapshot"):
		await finish(false,"starter damage")
		return
	check(site("fence").tier==1 and site("fence").hp==83,"Host damage reaches the real guest without resetting the starter HP")
	publish("starter_damage_seen")
	if not await barrier("starter_destroyed") or not await wait_for(func():return site("fence").tier==0 and site("fence").ruined,"destroyed outer fence snapshot"):
		await finish(false,"starter destruction")
		return
	check(site("fence").collision_layer==0 and not site("fence").is_blocking(),"Destroyed outer fence removes collision on the real guest")
	publish("starter_destruction_seen")
	if not await barrier("built") or not await wait_for(func():return site("fence").tier==1 and site("ground").ammo==20 and site("ground",1).ammo==40 and get_nodes_in_group("human_enemies").size()==1,"paid defense snapshot"):
		await finish(false,"build")
		return
	check(site("ground").get_meta("network_entity_id")!=site("ground",1).get_meta("network_entity_id"),"Two fixed sentries have independent replicated entity IDs")
	check(not site("ground").is_physics_processing() and not site("ground").fire(),"Guest cannot fire an extra autonomous round")
	check(game.combat_gore.level==2,"Host Off does not overwrite guest Full")
	publish("built_seen")
	if not await barrier("fatal") or not await wait_for(func():return not game.combat_gore.parts.is_empty(),"remote detached native limb"):
		await finish(false,"fatal hit")
		return
	check(game.combat_gore.parts.size()==1 and game.combat_gore.parts[0].part==8,"One authoritative fatal impact produces one guest limb")
	if not await wait_for(func():return get_nodes_in_group("human_enemies").is_empty() and not get_nodes_in_group("infantry_remains").is_empty(),"remote corpse"):
		await finish(false,"corpse")
		return
	check(get_nodes_in_group("infantry_remains")[0].gore_mask==8,"Remote corpse hides the same limb despite independent event/snapshot timing")
	publish("fatal_seen")
	if not await barrier("ko") or not await wait_for(func():return game.players[1].is_downed() and game.combat_gore.parts.any(func(part):return part.player_id==2),"local player KO replica"):
		await finish(false,"player KO")
		return
	check(game.players[1].gore_mask>0 and game.combat_gore.parts.filter(func(part):return part.player_id==2).size()==1,"Player KO has one local fragment and the host medical state")
	publish("ko_seen")
	if not await barrier("revived") or not await wait_for(func():return not game.players[1].is_downed() and game.players[1].gore_mask==0 and game.combat_gore.parts.all(func(part):return part.player_id!=2),"restored player replica"):
		await finish(false,"revive")
		return
	check(game.players[1].hp>0,"Medical revival restores the complete player and retires detached parts")
	publish("revive_seen")
	if not await barrier("drop_guest"):
		await finish(false,"disconnect signal")
		return
	if not OS.get_environment("LASTSHIFT_PERIMETER_RELAY").is_empty():
		game.network._websocket.close(1000,"Isolated courtyard reconnect")
	if not await wait_for(func():return game.network.state=="reconnecting" and paused,"guest disconnect") or not await wait_for(func():return playing(),"guest rejoin",12):
		await finish(false,"reconnect")
		return
	check(site("fence").tier==1 and site("ground").ammo==20 and site("ground",1).ammo==40 and game.combat_gore.level==2,"Authenticated reconnect retains defenses and the guest-local option")
	publish("reconnected")
	if not await barrier("host_passed"):
		await finish(false,"host completion")
		return
	if not await wait_for(func():return get_nodes_in_group("enemies").size()==2,"post-reconnect new enemy"):
		await finish(false,"new spawn after rejoin")
		return
	check(get_nodes_in_group("enemies").size()==2,"Reconnect followed by new spawning preserves both distinct replicas")
	publish("guest_passed")
	if not await barrier("finish"):
		await finish(false,"finish")
		return
	await finish(failures==0,"finite defenses, independent Full display, player recovery and reconnect")
