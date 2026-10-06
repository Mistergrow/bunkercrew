extends SceneTree
const World := preload("res://scripts/network_world.gd")
const Excavation := preload("res://tests/scenario_excavation_fixture.gd")
var checks:=0
var failures:=0
func _initialize(): call_deferred("run")
func check(ok:bool,label:String):
	checks+=1
	print("WORLD %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)
func scene():
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(2,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.rounds.set_process(false)
	game.medic.set_physics_process(false)
	return game
func frames(n:=2):
	for frame in n:
		await process_frame
		await physics_frame
func run():
	var host=scene()
	var authority=World.new()
	authority.bind(host)
	host.rounds.wave=20
	var p=host.players[0]
	for worker in host.players: worker.set_physics_process(false)
	var site=host.scenario_bunker.modules[0]
	check(await Excavation.clear_field(host,0,p),"Host physically excavates the first room before paying for construction")
	p.inventory={"concrete":4,"steel":3}
	Excavation.pay_supports(site,p)
	Excavation.pay_room(site,p)
	check(host.scenario_bunker.built_rooms==2 and p.inventory.is_empty(),"Host room is built from the real paid recipe")
	for index in range(1,4):
		check(host.scenario_bunker.prepare_excavation(index),"Host opens the next paid room's excavation")
		check(await Excavation.clear_field(host,index,p),"Host physically excavates the complete new room")
		var expansion=host.scenario_bunker.modules[index]
		p.inventory=expansion.spec().cost.duplicate()
		Excavation.pay_supports(expansion,p)
		Excavation.pay_room(expansion,p)
	host.view_stage=4
	host.update_scenario_camera()
	check(host.scenario_bunker.open_depths==4 and p.inventory.is_empty(),"Host builds all four expansions with paid physical recipes")
	p.position=Vector2(876,430)
	p.velocity=Vector2(31,0)
	p.hp=73.0
	p.inventory={"ore":4,"ammo":2}
	p.progression.level=3
	p.progression.skills.combat=2
	p.medical.bleeding=2
	p.medical.fractured=true
	p.medical.state="injured"
	p.get_node("WorkerWeapon").loaded.rifle=7
	host.players[1].mounted_turret=host.turret
	host.turret.occupant=host.players[1]
	host.turret.ammo=11
	host.upgrades.points=17
	host.upgrades.owned={"bunker_fortress":true,"shotgun":true}
	host.core.hp=402.0
	host.workshop.orders={"1:0":{"materials":{"steel":1},"remaining":1.4,"working":true,"ready":false,"owner":1,"recipe":0,"transfer":0.0}}
	var enemy=host._entity("enemy",Vector2(1300,430),{"kind":"strider","wave":7})
	enemy.hp=88.0
	enemy.set_physics_process(false)
	var air=host._entity("air_enemy",Vector2(1100,100),{"kind":"scout_drone","wave":8})
	air.set_physics_process(false)
	var boss=host._entity("boss_enemy",Vector2(1490,430),{"wave":20})
	boss.set_physics_process(false)
	boss.overdrive=true
	boss.set_meta("boss_phase",2)
	host.combat_events.announce_boss(boss,"MUTTERMASCHINE",true)
	var specialist=host._entity("enemy",Vector2(1450,430),{"kind":"shield_guard","wave":20})
	specialist.set_physics_process(false)
	specialist.abilities.shield_hp=24.0
	var tank=host._entity("enemy",Vector2(1580,430),{"kind":"battle_tank","wave":9})
	tank.set_physics_process(false)
	tank.weapon_recoil=4.0
	tank._pose_parts()
	var sentry=host._entity("field_defense",Vector2(820,430),{"kind":"sentry_kit","builder":p})
	sentry.set_physics_process(false)
	sentry.turret.set_physics_process(false)
	sentry.turret.ammo=9
	var shot=host._entity("projectile",Vector2(920,300))
	shot.credit_worker=p
	shot.source=host.turret
	shot.set_physics_process(false)
	host.flak_station.materials=host.flak_station.next_spec().cost.duplicate()
	host.flak_station._complete()
	host.flak_station.turret.set_physics_process(false)
	host.flak_station.turret.ammo=8
	host.dome.unlock()
	for pane in host.dome.segments:
		pane.set_frame()
		pane.glaze()
	host.dome.frame_built=true
	host.dome.built=true
	host.dome.segments[0].hp=51.0
	await frames()
	var snapshot:Dictionary=authority.capture()
	var bytes:=var_to_bytes(snapshot)
	check(bytes.size()<512*1024 and bytes_to_var(bytes)==snapshot,"Full state round-trips as data and fits under512KiB")
	var target_count:int=snapshot.entities.size()
	await preload("res://tests/scene_cleanup.gd").free_scene(host,self)
	var guest=scene()
	var replica=World.new()
	replica.bind(guest)
	check(replica.apply(snapshot),"Client accepts full snapshot: "+replica.last_error)
	if not replica.last_error.is_empty():
		await preload("res://tests/scene_cleanup.gd").free_scene(guest,self)
		quit(1)
		return
	check(guest.scenario_bunker.built_rooms==5 and guest.scenario_bunker.open_depths==4 and guest.view_stage==4,"Paid room collision/floors/station are rebuilt")
	check(guest.scenario_bunker.fields.all(func(field):return field.is_cleared()),"Finished rooms have no leftover earth and replica construction awards no material")
	check(guest.players[0].position==p.position if is_instance_valid(p) else guest.players[0].position==Vector2(876,430),"Player position is authoritative")
	check(guest.players[0].hp==73 and guest.players[0].inventory=={"ore":4,"ammo":2},"Health and physical cargo replicate")
	check(guest.players[0].medical.bleeding==2 and guest.players[0].medical.fractured and guest.players[0].progression.level==3 and guest.players[0].progression.skills.combat==2,"Medical and progression controllers replicate")
	check(guest.players[0].get_node("WorkerWeapon").loaded.rifle==7 and guest.turret.ammo==11,"Hand weapon and mounted ammunition replicate")
	check(guest.players[1].mounted_turret==guest.turret and guest.turret.occupant==guest.players[1],"Mount references resolve to local player and turret")
	check(guest.upgrades.points==17 and guest.upgrades.owned.shotgun and guest.core.hp==402,"Shared upgrades and core HP replicate")
	check(guest.workshop.orders["1:0"].materials.steel==1,"Paid workshop buffers replicate")
	check(guest.flak_station.built and guest.flak_station.turret.ammo==8 and guest.dome.built and guest.dome.segments[0].hp==51,"Flak structure and glass panel state replicate")
	var enemies:=get_nodes_in_group("enemies")
	check(enemies.size()==5,"Ground, air, boss, specialist and tank enemies spawn through allowed factories")
	var tanks=enemies.filter(func(machine):return machine.kind=="battle_tank")
	check(tanks.size()==1 and tanks[0].uses_rolling_contacts() and is_equal_approx(tanks[0].visual_scale,.88) and is_equal_approx(tanks[0].weapon_recoil,4.0),"Tank identity, reduced scale, running gear and cannon recoil replicate to the guest")
	check(guest.combat_events.boss_status().get("phase")==2,"Boss HUD weak reference and overdrive phase replicate")
	var shields=enemies.filter(func(machine):return machine.kind=="shield_guard")
	check(shields.size()==1 and shields[0].abilities.shield_hp==24.0,"Nested enemy shield ability state replicates")
	var defenses=get_nodes_in_group("field_defenses")
	check(defenses.size()==1 and defenses[0].builder==guest.players[0] and defenses[0].turret.ammo==9,"Deployed sentry child gun and builder ownership replicate")
	var projectile
	for node in replica.entities.values():
		if is_instance_valid(node) and node.get_script().resource_path=="res://scripts/projectile.gd": projectile=node
	check(is_instance_valid(projectile) and projectile.credit_worker==guest.players[0] and projectile.source==guest.turret,"Projectile damage ownership resolves locally")
	var before_hp:float=guest.core.hp
	var before_ammo:int=guest.turret.ammo
	var before_count:=get_nodes_in_group("enemies").size()
	await frames(10)
	check(guest.core.hp==before_hp and guest.turret.ammo==before_ammo and get_nodes_in_group("enemies").size()==before_count and not guest.players[0].is_physics_processing(),"Client physics, AI, production and projectiles cannot simulate duplicate damage")
	check(guest.players[0].get_node("PixelVisual").is_processing() and guest.weather.is_processing(),"Worker animation and weather remain live")
	var removed:=snapshot.duplicate(true)
	removed.entities=removed.entities.filter(func(record): return not record.type in ["enemy","air_machine","boss_machine","ground_machine_abilities","projectile"])
	removed.boss=""
	check(replica.apply(removed) and get_nodes_in_group("enemies").is_empty(),"Missing host enemies and projectiles despawn on client")
	var moved:=removed.duplicate(true)
	moved.entities.filter(func(record):return record.id=="player:1")[0].state.position=Vector2(896,430)
	check(replica.apply(moved),"Movement snapshot accepted")
	replica.interpolate(.025)
	check(guest.players[0].position.x>876 and guest.players[0].position.x<896,"Actor rendering interpolates between authoritative snapshots")
	replica.interpolate(.025)
	check(guest.players[0].position==Vector2(896,430),"Actor interpolation reaches target within50ms without running physics")
	moved.entities.filter(func(record):return record.id=="player:1")[0].state.position=Vector2(1200,430)
	check(replica.apply(moved) and guest.players[0].position==Vector2(1200,430),"Large authoritative teleports snap immediately")
	var malicious:=removed.duplicate(true)
	malicious.entities.filter(func(record):return record.type=="field_medic")[0].erase("status_message")
	check(not replica.apply(malicious),"Missing medic message IDs are rejected before mutation")
	malicious=removed.duplicate(true)
	malicious.entities.filter(func(record):return record.type=="field_medic")[0].status_message={"key":"SAN-1 · unterwegs zu P%d","args":{"literal":"invalid number"}}
	malicious.game.notice="Should not apply"
	var unchanged_notice:String=guest.notice
	check(not replica.apply(malicious) and guest.notice==unchanged_notice,"Invalid medic format values reject the whole snapshot before mutation")
	malicious=removed.duplicate(true)
	malicious.game["network"]="bad"
	check(not replica.apply(malicious),"Unlisted game properties are rejected before mutation")
	malicious=removed.duplicate(true)
	malicious.entities[0].type="arbitrary_script"
	check(not replica.apply(malicious),"Incoming scene/script types cannot escape the local factory whitelist")
	removed.entities.filter(func(record):return record.type=="round_controller")[0].state.phase="victory"
	check(replica.apply(removed) and guest.hud.overlay=="victory","Terminal host phase opens client result UI")
	print("NETWORK WORLD: %d/%d checks passed; %dentities, %dbytes"%[checks-failures,checks,target_count,bytes.size()])
	await preload("res://tests/scene_cleanup.gd").free_scene(guest,self)
	quit(1 if failures else 0)
