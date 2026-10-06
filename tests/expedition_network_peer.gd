extends "res://tests/network_gameplay_peer.gd"
## Prepared wave20 victory; real ENet scene reloads, authoritative convoy,
## finite supplies, actual guarded cache and new-bunker occupation callbacks.
const Journey := preload("res://scripts/convoy_journey.gd")

func _initialize() -> void:
	started_at=Time.get_ticks_msec()
	overall_timeout_ms=95000
	_run.call_deferred()

func relay() -> String: return OS.get_environment("LASTSHIFT_CONVOY_RELAY")

func truck():
	return game.expedition.vehicle if is_instance_valid(game) and is_instance_valid(game.expedition.vehicle) else null

func guards() -> Array:
	return get_nodes_in_group("enemies").filter(func(unit):return unit.game==game and not unit.is_queued_for_deletion() and not unit.dead)

func clear_guards() -> void:
	for unit in guards(): unit.take_damage(unit.hp+1)

func stage(value: String) -> bool:
	return playing() and game.expedition.stage==value and is_instance_valid(truck())

func host_run() -> void:
	game.network.host_room(relay())
	if not await wait_for(func():return game.network.state=="lobby","host lobby"): await finish(false,"host room");return
	publish("room",{"code":game.network.room_code})
	if not await barrier("joined"): await finish(false,"lobby"); return
	game.network.start_match(OPTIONS,game.selected_characters)
	if not await wait_for(func():return playing(),"host first defense") or not await barrier("guest_started"): await finish(false,"start"); return
	game.rounds.running=false
	game.rounds.wave=20
	game.upgrades.points=19
	game.upgrades.owned["convoy_mg"]=true
	game.players[0].inventory={"steel":2,"ammo":1,"alloy":1}
	check(game.expedition.on_victory(),"Verified prepared wave20 commits finite stock and campaign victory")
	check(game.expedition.handle_command("route",{"id":"harbor"},1),"Host chooses next real bunker")
	check(game.expedition.handle_command("stop",{"id":"harbor:weapon"},1),"Host chooses epic weapon stop")
	check(game.expedition.handle_command("load",{"kind":"steel","amount":1},1),"Actual steel leaves finite garage for truck")
	check(game.expedition.handle_command("load",{"kind":"ammo","amount":1},1),"Actual ammunition leaves finite garage for truck")
	check(game.expedition.handle_command("load",{"kind":"alloy","amount":1},1),"Rare recovered alloy can be loaded from a dynamic garage crate")
	var garage_id: int=game.get_instance_id()
	check(game.expedition.handle_command("depart",{},1),"Host departure begins actual crew boarding")
	check(game.get_instance_id()==garage_id and game.expedition.boarding_active(),"Garage remains loaded until every worker occupies a seat")
	for index in 2:
		game.players[index].global_position=truck().global_position
		check(truck().board(game.players[index],"driver" if index==0 else "gunner"),"Actual garage seat entry for P%d"%(index+1))
	if not await wait_for(func():return stage("travel"),"host road reload",12) or not await barrier("road_seen",12): await finish(false,"road"); return
	if not await wait_for(func():return truck().journey_state.phase=="driving","real engine start"): await finish(false,"ignition");return
	game.expedition.set_physics_process(false)
	var before_x: float=truck().position.x
	var before_fuel: float=truck().fuel
	Input.action_press("p1_right")
	await delay(.55)
	Input.action_release("p1_right")
	await delay(.3)
	check(truck().position.x>before_x and truck().fuel<before_fuel,"Actual driver input advances the body and spends fuel")
	publish("gun_ready")
	if not await wait_for(func():return truck().ammo==20,"actual guest reload input") or not await barrier("guest_gun_fired"):
		await finish(false,"guest gun controls"); return
	if not await wait_for(func():return truck().ammo<20,"actual guest fire input"):
		await finish(false,"guest shot"); return
	truck().set_physics_process(false)
	var remaining_ammo: int=truck().ammo
	check(not truck().cargo.has("ammo"),"Guest reload input spends one actual carried ammunition crate")
	check(remaining_ammo>=15 and remaining_ammo<20 and truck().gunner_seat.occupant==game.players[1],"Guest fire input drives authoritative convoy MG and spends finite rounds")
	for shot in get_nodes_in_group("projectiles"):
		if shot.get("source")==truck(): shot.set_physics_process(false)
	game.expedition._sync_vehicle()
	publish("driven",{"x":truck().position.x,"fuel":truck().fuel,"ammo":remaining_ammo})
	if not await barrier("driven_seen"): await finish(false,"moving rig"); return
	# Cause a real puncture before dropping the link: partial tool progress is
	# authoritative and must survive the actual transport reconnection.
	game.expedition.set_physics_process(true)
	truck().set_physics_process(true)
	truck().position.x=1740
	if not await wait_for(func():return truck().journey_state.phase=="repair" and not guards().is_empty(),"real flat and defenders"): await finish(false,"flat");return
	clear_guards()
	truck().dismount(game.players[1])
	game.players[1].global_position=truck().service_point()+Vector2(-45,20)
	game.players[1].preferred_focus=truck()
	game.players[1].focus=truck()
	publish("repair_ready")
	if not await wait_for(func():return truck().journey_state.repair_work>.1,"guest actual held tool input"): await finish(false,"repair input");return
	publish("repair_partial",{"work":truck().journey_state.repair_work})
	if not await barrier("repair_partial_seen"): await finish(false,"partial replica");return
	if relay().is_empty(): game.network.transport.disconnect_guest()
	else: publish("drop_guest")
	if not await wait_for(func():return game.network.state=="reconnecting" and paused,"host disconnect") or not await wait_for(func():return playing(),"host authenticated reconnect",12) or not await barrier("rejoined",12): await finish(false,"reconnect"); return
	check(get_nodes_in_group("convoy_vehicles").filter(func(v):return v.game==game).size()==1 and truck().ammo==remaining_ammo,"Reconnect retains one truck and finite magazine")
	check(truck().journey_state.phase=="repair" and truck().journey_state.repair_work>=float(read_stage("repair_partial").work),"Reconnect retains the actual partial wheel task")
	publish("repair_continue")
	if not await wait_for(func():return truck().journey_state.phase=="reboarding","guest completes real held five-stage repair",22) or not await barrier("repair_done_seen"):
		await finish(false,"wheel completion");return
	check(truck().journey_state.breakdown_done and truck().journey_state.repair_bolts==3 and not truck().driving_enabled,"Three bolts and lowering complete before movement is allowed")
	for index in 2:
		game.players[index].global_position=truck().global_position
		check(truck().board(game.players[index],"driver" if index==0 else "gunner"),"Actual reboarding for P%d"%(index+1))
	if not await wait_for(func():return truck().journey_state.phase=="driving","whole crew reboards"): await finish(false,"reboard");return
	game.expedition.set_physics_process(true)
	truck().position.x=2140
	if not await wait_for(func():return game.expedition.stage=="stop" and guards().size()>0,"actual weapon-cache guards"): await finish(false,"cache"); return
	publish("cache")
	if not await barrier("cache_seen"): await finish(false,"cache replicas"); return
	clear_guards()
	if not await wait_for(func():return guards().is_empty(),"cache cleared"): await finish(false,"cache clear"); return
	check(game.expedition.handle_command("resume",{},1),"Cleared cache awards one epic and resumes travel")
	check(game.campaign.expedition.epic_weapons==["breacher_shotgun"],"Harbor cache awards its actual epic weapon")
	publish("loot")
	if not await barrier("loot_seen"): await finish(false,"loot replication"); return
	truck().position.x=3300
	game.expedition.ambushes=2
	if not await wait_for(func():return stage("occupation") and guards().size()>0,"host occupied harbor reload",12) or not await barrier("occupation_seen",12): await finish(false,"occupation transition"); return
	check(game.scenario_options.environment=="abandoned_harbor" and game.rounds.wave==1,"Destination uses harbor world before next wave begins")
	clear_guards()
	if not await wait_for(func():return game.expedition.stage=="defense" and game.rounds.running,"new bunker waveone"): await finish(false,"new defense"); return
	game.rounds.running=false
	check(game.campaign.expedition.deployment_cargo.get("steel",0)==1 and truck().cargo.is_empty(),"Transported steel commits once into fresh bunker")
	check(get_nodes_in_group("supplies").any(func(crate):return crate.game==game and crate.kind=="alloy" and crate.amount==1 and crate.get_script().resource_path=="res://scripts/convoy_supply.gd"),"Rare delivered material creates a dynamic supply crate")
	publish("defense")
	if not await barrier("defense_seen"): await finish(false,"defense replica"); return
	publish("host_passed")
	if not await barrier("guest_passed"): await finish(false,"completion"); return
	publish("finish")
	await finish(failures==0,"convoy, finite supplies, epic cache, occupation, new defense and reconnect")

func guest_run() -> void:
	game.network.join_room(relay(),str(read_stage("room").get("code","")))
	if not await wait_for(func():return game.network.peer_connected and game.network.state=="lobby","guest lobby"): await finish(false,"lobby"); return
	publish("joined")
	if not await wait_for(func():return playing() and game.network.received_snapshots>=2,"guest initial defense"): await finish(false,"start"); return
	publish("guest_started")
	if not await wait_for(func():return stage("travel") and game.network.received_snapshots>=2,"guest road generation",12): await finish(false,"road"); return
	check(game.world_right==3700 and game.expedition.road_open,"Validated expedition creates deterministic extended road")
	check(game.players[0].mounted_turret==truck().driver_seat and game.players[1].mounted_turret==truck().gunner_seat,"Both real worker mounts resolve to their replicated seats")
	check(not truck().is_physics_processing() and not truck().fire(game.players[1]),"Guest convoy cannot run damage or movement authority")
	var audit: Dictionary=game.network.world.capture()
	var bad:=audit.duplicate(true)
	bad.expedition.checkpoint.expedition.vehicle.fuel=-1.0
	var saved_x: float=truck().position.x
	check(not game.network.world.apply(bad) and truck().position.x==saved_x,"Invalid convoy checkpoint rejected before world mutation")
	bad=audit.duplicate(true)
	for record in bad.entities:
		if record.type=="convoy_seat" and record.state.role=="driver": record.refs.occupant="player:2"
	check(not game.network.world.apply(bad),"Forged driver/gunner ownership rejected before mutation")
	check(game.network.world.apply(audit),"Last valid convoy snapshot remains applicable after rejection")
	publish("road_seen")
	if not await barrier("gun_ready"): await finish(false,"gun readiness"); return
	Input.action_press("p1_reload")
	await delay(.10)
	Input.action_release("p1_reload")
	if not await wait_for(func():return truck().ammo==20,"guest sees its own reload result"): await finish(false,"remote reload"); return
	check(not truck().cargo.has("ammo"),"Reload key travels to host and returns consumed cargo")
	Input.action_press("p1_fire")
	await delay(.14)
	Input.action_release("p1_fire")
	publish("guest_gun_fired")
	if not await barrier("driven") or not await wait_for(func():return truck().ammo==int(read_stage("driven").ammo),"finite host magazine"): await finish(false,"ammo"); return
	await delay(.1)
	check(absf(truck().position.x-float(read_stage("driven").x))<1 and absf(truck().fuel-float(read_stage("driven").fuel))<.01,"Driven transform and fuel arrive over ENet")
	check(not truck().cargo.has("ammo"),"Consumed carried ammunition disappears on guest")
	check(game.players[1].global_position.distance_to(truck().gunner_seat.operator_position())<1,"Gunner remains attached after vehicle interpolation")
	publish("driven_seen")
	if not await barrier("repair_ready") or not await wait_for(func():return truck().journey_state.phase=="repair" and not is_instance_valid(game.players[1].mounted_turret),"guest real wheel site"): await finish(false,"wheel site");return
	Input.action_press("p1_interact")
	if not await barrier("repair_partial") or not await wait_for(func():return truck().journey_state.repair_work>=float(read_stage("repair_partial").work),"guest partial wheel work"): await finish(false,"partial");return
	Input.action_release("p1_interact")
	publish("repair_partial_seen")
	if not relay().is_empty():
		if not await barrier("drop_guest"): await finish(false,"relay drop");return
		game.network._websocket.close(1000,"Fixture reconnect during repair")
	if not await wait_for(func():return game.network.state=="reconnecting" and paused,"guest disconnect") or not await wait_for(func():return stage("travel"),"guest reconnect",12): await finish(false,"reconnect"); return
	check(truck().ammo==int(read_stage("driven").ammo) and truck().journey_state.phase=="repair" and not is_instance_valid(game.players[1].mounted_turret),"Authenticated reconnect preserves finite ammo and dismounted mechanic")
	publish("rejoined")
	if not await barrier("repair_continue"): await finish(false,"repair continue");return
	Input.action_press("p1_interact")
	if not await wait_for(func():return truck().journey_state.phase=="reboarding","guest five-stage tool completion",22): await finish(false,"tool completion");return
	Input.action_release("p1_interact")
	check(truck().journey_state.breakdown_done and truck().journey_state.repair_bolts==3,"Real held remote input completes three bolts exactly once")
	publish("repair_done_seen")
	if not await barrier("cache") or not await wait_for(func():return game.expedition.stage=="stop" and guards().size()>0,"replicated weapon-cache defenders"): await finish(false,"cache"); return
	check(guards().all(func(unit):return not unit.is_physics_processing()),"Roadside enemies are frozen guest replicas")
	publish("cache_seen")
	if not await barrier("loot") or not await wait_for(func():return game.campaign.expedition.epic_weapons.has("breacher_shotgun"),"earned epic weapon snapshot"): await finish(false,"epic"); return
	check(game.players[1].get_node("WorkerWeapon").available_weapons().has("breacher_shotgun"),"Earned cache unlocks actual guest weapon selection")
	publish("loot_seen")
	if not await wait_for(func():return stage("occupation") and guards().size()>0,"guest occupied harbor reload",12): await finish(false,"occupation"); return
	check(game.scenario_options.environment=="abandoned_harbor" and game.world_right<3700,"New generation restores destination bounds")
	publish("occupation_seen")
	if not await barrier("defense") or not await wait_for(func():return game.expedition.stage=="defense" and game.rounds.phase=="build","new defense snapshot"): await finish(false,"defense"); return
	check(game.rounds.wave==1 and game.campaign.expedition.deployment_cargo.get("steel",0)==1,"Guest starts waveone with same finite cargo boost")
	check(get_nodes_in_group("supplies").any(func(crate):return crate.game==game and crate.kind=="alloy" and crate.amount==1 and crate.get_script().resource_path=="res://scripts/convoy_supply.gd"),"Guest reconstructs rare delivery crate through audited dynamic factory")
	publish("defense_seen")
	if not await barrier("host_passed"): await finish(false,"host"); return
	publish("guest_passed")
	if not await barrier("finish"): await finish(false,"finish"); return
	await finish(failures==0,"road/occupation generations, crew seats, finite cargo, earned epic and rejoin")
