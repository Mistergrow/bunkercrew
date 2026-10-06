extends SceneTree
## Prepared wave-end victories; real scene reloads, finite garage transactions,
## drive/guard callbacks and every mandatory outpost objective. No player saves.
const L := preload("res://scripts/locale_text.gd")
const Roster := preload("res://scripts/crew_roster.gd")
const Controller := preload("res://scripts/expedition_controller.gd")
const Journey := preload("res://scripts/convoy_journey.gd")
const CLEANUP := preload("res://tests/scene_cleanup.gd")
const OPTIONS := {"environment":"ash_foundry", "build_type":"workshop", "position":"left"}
var game
var checks := 0
var failures := 0
var isolated_path := "user://expedition-flow-%d.json" % OS.get_process_id()
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("FLOW PASS ",label)
	return ok
func frames(count: int = 3) -> void:
	for frame in count: await process_frame
func freeze() -> void:
	paused = true
	game.expedition.set_physics_process(false)
	game.rounds.set_process(false)
	game.campaign.save_path = isolated_path
	game.campaign.persistence_enabled = true
	for person in game.players:
		person.set_physics_process(false)
		person.get_node("WorkerWeapon").set_physics_process(false)
	if is_instance_valid(game.expedition.vehicle): game.expedition.vehicle.set_physics_process(false)
	for enemy in enemies(): enemy.set_physics_process(false)
func enemies() -> Array:
	return get_nodes_in_group("enemies").filter(func(enemy):return enemy.game==game and not enemy.dead and not enemy.is_queued_for_deletion())
func clear_guards() -> void:
	for enemy in enemies(): enemy.take_damage(enemy.hp+1)
	await frames()
func tick() -> void:
	game.expedition._physics_process(.02)
	await frames()
func wait_reload(previous: int, expected: String) -> bool:
	var deadline := Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline:
		await frames()
		if is_instance_valid(current_scene) and current_scene.get_instance_id()!=previous:
			game=current_scene
			if game.started and game.expedition.stage==expected:
				freeze()
				return true
	return check(false,"Actual scene reload reached "+expected)
func fresh_menu() -> void:
	if is_instance_valid(game): await CLEANUP.free_scene(game,self)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await frames(6)
	game.campaign.save_path=isolated_path
	game.campaign.persistence_enabled=true
func reward_data() -> void:
	for index in 3:
		var key := "prepared-finite-salvage-%d" % index
		check(game.campaign.reserve_drop(key,3) and game.campaign.collect_salvage(key,3),"Real mission ledger grants finite route salvage")
func finish_bunker() -> void:
	reward_data()
	game.rounds.wave=20
	game.rounds.running=true
	game.rounds.victory()
	await frames()
	freeze()
	check(game.expedition.stage=="preparation" and game.hud.overlay in ["victory","campaign_victory"],"Actual wave20 callback commits defended bunker and opens victory")
func depart_to(id: String) -> bool:
	var controller=game.expedition
	if not controller.handle_command("route",{"id":id,"unlock":int(CampaignCatalog.node(id).cost)>0},1):
		return check(false,"Route selection to "+id)
	# Preparation fixture supplies only fuel, through the same finite scrap transaction.
	game.players[0].inventory["scrap"]=20
	while float(game.campaign.expedition.vehicle.fuel)<20:
		if not controller.handle_command("refuel",{},1): break
	return await board_and_depart("Host dispatches actual route to "+id)

func board_crew() -> bool:
	var truck=game.expedition.vehicle
	for person in game.expedition.connected_crew():
		if truck.seat_for(person)!=null: continue
		person.global_position=truck.global_position+Vector2(-120+person.player_id*20,0)
		if not check(truck.board(person,truck.SEAT_ROLES[person.player_id-1]),"Real crew P%d boards its available convoy seat"%person.player_id): return false
	return check(game.expedition.crew_ready(),"Every living connected player is in a real seat before departure")

func board_and_depart(label: String) -> bool:
	var controller=game.expedition
	var old: int=game.get_instance_id()
	if not check(controller.handle_command("depart",{},1),label): return false
	freeze()
	if not check(controller.can_manage() and controller.boarding_active() and controller.vehicle.journey_state.phase=="boarding","Departure opens boarding in the existing garage before any scene handoff"): return false
	if not board_crew(): return false
	var steps:=0
	while not controller.transitioning and steps<120:
		await physics_frame
		controller.vehicle._physics_process(1.0/60.0)
		controller._physics_process(1.0/60.0)
		steps+=1
		if steps==30:
			check(game.get_instance_id()==old and controller.vehicle.journey_state.phase=="departure","Half-second of real production physics does not skip the 1.2-second countdown")
	if not check(controller.transitioning and steps>=73,"Real seated crew completes the departure countdown before the scene handoff"): return false
	if not await wait_reload(old,"travel"): return false
	return await start_driving()

func start_driving() -> bool:
	freeze()
	var controller=game.expedition
	var truck=controller.vehicle
	var ignition_ticks:=ceili((game.travel_cinematic.startup_duration()+1.0)*Engine.physics_ticks_per_second)
	for unused in ignition_ticks:
		if truck.journey_state.phase=="driving": break
		await physics_frame
		truck._physics_process(1.0/60.0)
		controller._physics_process(1.0/60.0)
	return check(truck.journey_state.phase=="driving" and truck.driving_enabled,"Actual starting/reboarding physics enables driving after its engine interval")

func complete_tire() -> bool:
	var controller=game.expedition
	var truck=controller.vehicle
	if truck.journey_state.breakdown_done: return true
	truck.position.x=Controller.ROAD_START+(Controller.ROAD_END-Controller.ROAD_START)*Journey.BREAKDOWN_PROGRESS+.1
	await tick()
	if not check(truck.journey_state.phase=="repair" and not truck.driving_enabled and game.players[0].mounted_turret==null,"Actual route threshold punctures the tire and places the driver outside to repair"): return false
	await clear_guards()
	var person=game.players[0]
	person.global_position=truck.service_point()+Vector2(-48*truck.facing,20)
	for unused in 720:
		if truck.journey_state.phase!="repair": break
		await physics_frame
		truck._physics_process(1.0/60.0)
		var tightening: bool=truck.journey_state.repair_step=="tighten"
		var timed: bool=tightening and float(truck.journey_state.repair_cursor)>=Journey.TIMING_START and float(truck.journey_state.repair_cursor)<=Journey.TIMING_END
		truck.service_action(person,1.0/60.0,timed,not tightening)
		controller._physics_process(1.0/60.0)
	if not check(truck.journey_state.phase=="reboarding" and truck.journey_state.breakdown_done and truck.journey_state.repair_bolts==3,"Real held jack/remove/fit/lower and three timed bolts complete the tire mission"): return false
	if not board_crew(): return false
	return await start_driving()
func arrive() -> bool:
	var controller=game.expedition
	if not await start_driving() or not await complete_tire(): return false
	await clear_guards()
	controller.vehicle.position.x=Controller.ROAD_END-1
	controller._physics_process(.02)
	check(controller.ambushes==int(controller.route.get("ambushes",2)),"Actual travel dispatches every planned route ambush")
	var before_count: int=enemies().size()
	controller._physics_process(.02)
	check(enemies().size()==before_count,"Repeated travel ticks do not duplicate ambushes")
	await clear_guards()
	controller.vehicle.position.x=Controller.ROAD_END
	var old: int=game.get_instance_id()
	controller._physics_process(.02)
	return await wait_reload(old,"occupation")
func retry_occupation() -> bool:
	var destination: String=game.campaign.pending_node
	var origin: String=game.campaign.current_node
	var expected: String=game.campaign.options.environment if origin==CampaignCatalog.ENTRY else CampaignCatalog.node(origin).environment
	var cargo: Dictionary=game.campaign.expedition.departure.vehicle.cargo.duplicate()
	# JSON numbers are floats; runtime inventory stores equivalent integer units.
	for kind in cargo: cargo[kind]=int(cargo[kind])
	game.expedition.vehicle.take_damage(game.expedition.vehicle.hp+1)
	check(game.expedition.stage=="failed", "Real vehicle destruction during occupation enters failure state")
	var old: int=game.get_instance_id()
	check(game.expedition.handle_command("retry",{},1), "Occupation retry accepts the saved departure")
	if not await wait_reload(old,"travel"): return false
	check(game.scenario_options.environment==expected and game.campaign.pending_node==destination and game.campaign.current_node==origin, "Occupation retry restores the departure environment and retains its target")
	check(game.expedition.vehicle.cargo==cargo and not game.campaign.completed.has(destination), "Occupation retry neither duplicates cargo nor falsely secures the destination")
	return await arrive()

func clear_occupation(id: String) -> void:
	var controller=game.expedition
	check(game.scenario_options.environment==CampaignCatalog.node(id).environment,"Destination uses its authored world: "+id)
	check(enemies().size()>0 and not game.rounds.running,"Occupation creates a real finite garrison before waves begin")
	var enemy=enemies()[0]
	var chosen=controller.combat_target_for(enemy)
	check(is_instance_valid(chosen) and chosen in game.players and enemy.attack_direction==signf(chosen.position.x-enemy.position.x),"Garrison targets a living player with correct facing, never a distant core behind it")
	game.players[0].position=enemy.position+Vector2(-140,0)
	game.players[1].position=enemy.position+Vector2(500,0)
	check(controller.combat_target_for(enemy)==game.players[0] and enemy.attack_direction<0,"Occupation defender turns when the nearer player crosses to its other side")
	await clear_guards()
	controller._physics_process(.02)
	await frames()
	freeze()
	check(controller.stage=="defense" and game.campaign.mission_running,"Clearing real guards starts a durable site mission")
func test_outpost(id: String) -> void:
	var controller=game.expedition
	check(controller.outpost_pending() and not game.rounds.running and game.rounds.phase=="occupation","Outpost uses a facility interaction instead of twenty waves")
	# The remote UI sees only checkpoint data; mission_running is intentionally local.
	var running: bool=game.campaign.mission_running
	game.campaign.mission_running=false
	check(controller.outpost_pending() and game.core.interaction_title()==L.text(str(CampaignCatalog.objective(id).title)),"Outpost objective remains visible without non-replicated mission runtime fields")
	game.campaign.mission_running=running
	var person=game.players[0]
	person.position=game.core.position
	game.core.repair_work=0
	controller._spawn_guards(1,person.position.x+170,false)
	game.core.interact(person,5.0)
	check(game.core.repair_work==0 and not game.campaign.completed.has(id),"A surviving garrison member blocks facility capture")
	await clear_guards()
	if id=="dam_vault":
		# All-down defeat must work although the short objective has rounds.running=false.
		for player in game.players: player.hp=0; player._begin_knockout()
		controller._physics_process(.02)
		check(game.hud.overlay=="defeat" and not game.campaign.mission_running,"Both downed crew trigger a genuine outpost defeat outside the wave controller")
		var old: int=game.get_instance_id()
		check(controller.retry_defense(),"Outpost defeat exposes the real retry transition")
		if not await wait_reload(old,"defense"): return
		controller=game.expedition
		var expected_guards := ceili(int(CampaignCatalog.objective(id).guards)*Balance.wave_multiplier(Balance.active_players(game)))
		check(controller.outpost_pending() and enemies().size()==expected_guards,"Retry reconstructs the complete finite outpost garrison for the active crew")
		await clear_guards()
		person=game.players[0]
		person.position=game.core.position
	reward_data()
	game.core.interact(person,4.99)
	check(not game.campaign.completed.has(id) and game.core.repair_work<1,"Facility remains unsecured before the actual five-second hold")
	game.core.interact(person,.02)
	await frames()
	freeze()
	check(game.campaign.completed.has(id) and game.campaign.blueprints.has(CampaignCatalog.node(id).blueprint),"Core interaction commits strategic site and its permanent blueprint")
	var count: int=game.campaign.completed.size()
	controller.secure_outpost(person,5.0)
	check(game.campaign.completed.size()==count,"Captured facility cannot grant a duplicate reward")
	if id in ["dam_vault","refinery_archive","radar_archive"]:
		var identity: String={"dam_vault":"selma","refinery_archive":"nora","radar_archive":"levin"}[id]
		check(CharacterCatalog.is_unlocked(identity),"Actual objective callback rescues its missing crew member")
func run() -> void:
	if not "--no-profile-save" in OS.get_cmdline_user_args(): quit(2); return
	Roster.persistence_enabled=false
	Roster.unlocked.clear()
	L.set_locale("en",false)
	await fresh_menu()
	game.start_scenario(2,OPTIONS)
	await frames()
	freeze()
	check(game.campaign.mission_running,"Actual new local co-op scenario begins the first campaign mission")
	game.rounds.wave=20
	game.expedition._spawn_guards(1,game.scenario_bunker.room_right+150,false)
	check(not game.expedition.on_victory() and game.campaign.completed.is_empty(),"A surviving enemy blocks premature wave20 campaign completion")
	await clear_guards()
	check(enemies().is_empty(),"Fresh verified victory contains no enemy straggler")
	game.upgrades.points=80
	game.players[0].inventory={"steel":4,"ammo":3,"alloy":2,"scrap":20}
	await finish_bunker()
	var controller=game.expedition
	for action in ["prepare","depart","refuel","repair"]:
		check(not controller.handle_command(action,{},2),"Second peer cannot mutate host-only convoy state: "+action)
	check(controller.handle_command("prepare",{},1) and paused,"Garage opens the actual truck and pauses the world")
	var saved_fuel: float=controller.vehicle.fuel
	controller.vehicle.fuel=29.0
	var scrap_before: int=controller._capture_stock().get("scrap",0)
	check(controller.handle_command("refuel",{},1) and controller.vehicle.fuel==30.0,"Near-full tank accepts the enabled refuel action")
	check(controller._capture_stock().get("scrap",0)==scrap_before-2,"Partial refuel consumes its advertised finite cost")
	check(not controller.handle_command("refuel",{},1),"Full tank rejects refuel without spending stock")
	controller.vehicle.fuel=saved_fuel
	var steel: int=controller._capture_stock().get("steel",0)
	check(controller.handle_command("load",{"kind":"steel","amount":2},1),"Finite steel loads through the host command")
	check(controller._capture_stock().steel==steel-2 and controller.vehicle.cargo.steel==2,"Paused garage mirrors the ledger back to physical stores without duplication")
	check(not controller.handle_command("load",{"kind":"steel","amount":18},2),"Guest cannot spend shared garage supplies")
	check(controller.handle_command("load",{"kind":"ammo","amount":1},1) and controller.handle_command("load",{"kind":"alloy","amount":1},1),"Ammunition and rare material enter the actual truck")
	var before: Dictionary=game.upgrades.owned.duplicate()
	var points: int=game.upgrades.points
	var core_max: float=game.core.max_hp
	game.campaign.save_path="user://missing-flow-directory/never-created/save.json"
	for id in ["boots","bunker_workshop","convoy_armor"]:
		check(not game.upgrades.purchase(id) and game.upgrades.points==points and game.upgrades.owned==before,"Failed durable research rejects every category without charging or activating: "+id)
	check(game.core.max_hp==core_max and controller.vehicle.max_hp==600,"Failed research leaves core and truck effects unchanged")
	var cargo: Dictionary=controller.vehicle.cargo.duplicate()
	check(not controller.handle_command("load",{"kind":"steel","amount":1},1) and controller.vehicle.cargo==cargo and controller._capture_stock().steel==steel-2,"Failed cargo save leaves physical supplies and vehicle unchanged")
	game.campaign.save_path=isolated_path
	check(game.upgrades.purchase("convoy_mg") and game.upgrades.purchase("convoy_armor"),"Successful durable research equips actual gunner seat and armour")
	check(controller.vehicle.has_mg and controller.vehicle.hp==800 and game.campaign.expedition.vehicle.hp==800,"Armour HP increase is saved with the upgrade rather than silently lost on reload")
	check(game.upgrades.purchase("boots"),"Portable crew research is persisted in the garage")
	check(controller.handle_command("route",{"id":"harbor"},1) and controller.handle_command("stop",{"id":"harbor:weapon"},1),"Choose a real guarded epic detour")
	var old: int=game.get_instance_id()
	if not await board_and_depart("Prepared first convoy begins its real seated departure"): await finish(); return
	controller=game.expedition
	var truck=controller.vehicle
	check(truck.driver_seat.occupant==game.players[0] and truck.gunner_seat.occupant==game.players[1],"Both real local players occupy independent vehicle roles")
	check(game.upgrades.has_upgrade("boots") and truck.max_hp==800 and truck.hp==800,"Fresh road restores portable research and paid armour HP")
	var fuel: float=truck.fuel
	truck.advance_motion(.5,1.0)
	check(truck.fuel<fuel and truck.position.x>Controller.ROAD_START,"Actual vehicle motion consumes finite fuel")
	check(truck.start_reload(),"Mounted weapon reload starts from actual cargo")
	truck._physics_process(1.5)
	check(truck.ammo==20 and not truck.cargo.has("ammo"),"One cargo crate is converted once into finite MG ammunition")
	if not await complete_tire(): await finish(); return
	truck.position.x=2130
	await tick()
	freeze()
	check(controller.stage=="stop" and enemies().size()>0,"Driving into selected detour creates real hostile guards")
	check(not controller.handle_command("resume",{},1),"Uncleared stop cannot grant epic loot")
	await clear_guards()
	check(controller.handle_command("resume",{},1),"Cleared guarded stop commits one real reward")
	freeze()
	var loot: Dictionary=controller.vehicle.cargo.duplicate()
	check(game.campaign.expedition.epic_weapons==["breacher_shotgun"] and not controller.handle_command("resume",{},1),"Epic stop is usable and cannot be claimed twice")
	# Resume the disk checkpoint in an entirely new main scene.
	await fresh_menu()
	check(game.expedition.resume_saved(),"Fresh offline menu loads a real isolated saved journey")
	check(game.player_count==1 and game.players.size()==1,"Offline Continue activates only the saved first player")
	game.join_coop()
	check(game.player_count==2 and game.players.size()==2,"Explicit local rejoin restores the second crew member for the remaining coop flow")
	freeze()
	controller=game.expedition
	check(controller.stage=="travel" and controller.stop_done and controller.ambushes==1 and controller.vehicle.position.x==2100,"Secured-stop reload starts beyond the completed first ambush")
	check(controller.vehicle.cargo==loot and game.campaign.expedition.epic_weapons==["breacher_shotgun"],"Saved detour keeps exactly the claimed cargo and epic weapon")
	if not await start_driving(): await finish(); return
	await tick()
	check(enemies().is_empty(),"Restored first-half ambush is not spawned a second time")
	# Empty-tank recovery is a real UI action, with the same finite retry boundary.
	controller.vehicle.fuel=0
	controller._sync_vehicle()
	controller.request("map")
	await frames()
	var panel=game.hud.expedition_panel
	check(controller.can_retry_journey() and panel.depart_button.text==L.text("Erneut versuchen") and not panel.depart_button.disabled,"Empty tank exposes a working retry action in the actual map")
	old=game.get_instance_id()
	panel.depart_button.pressed.emit()
	if not await wait_reload(old,"travel"): await finish(); return
	controller=game.expedition
	check(controller.vehicle.fuel>0 and controller.vehicle.cargo==loot and controller.stop_done,"Empty-tank retry restores the saved boundary without new fuel or loot grants")
	controller.request("map")
	await frames()
	game.hud.expedition_panel.depart_button.pressed.emit()
	check(game.hud.overlay.is_empty(),"Continue travel closes the map instead of sending an inapplicable loot command")
	freeze()
	controller.vehicle.hp=0
	controller.vehicle_destroyed()
	check(controller.stage=="failed" and paused,"Destroyed transport enters retry state")
	old=game.get_instance_id()
	check(controller.handle_command("retry",{},1),"Retry uses the saved stop boundary")
	if not await wait_reload(old,"travel"): await finish(); return
	check(game.expedition.vehicle.hp>0 and game.expedition.vehicle.cargo==loot and game.expedition.ambushes==1,"Retry restores pre-failure resources without duplicating loot or early ambush")
	if not await arrive(): await finish(); return
	if not await retry_occupation(): await finish(); return
	await clear_occupation("harbor")
	check(game.rounds.running and game.rounds.wave==1,"Ordinary occupied bunker begins a new twenty-wave defense")
	check(game.campaign.expedition.deployment_cargo.get("steel",0)==2 and game.expedition.vehicle.cargo.is_empty(),"Vehicle delivery enters the new base once")
	await finish_bunker()
	# Reload at harbor first: later travel must not revert to the initial world's environment.
	await fresh_menu()
	check(game.expedition.resume_saved(),"Offline Continue restores completed harbor preparation")
	check(game.player_count==1 and game.players.size()==1,"Harbor offline Continue also starts one active player")
	game.join_coop()
	check(game.player_count==2 and game.players.size()==2,"Harbor coop fixture explicitly restores its parked second player")
	freeze()
	check(game.scenario_options.environment=="abandoned_harbor","Preparation resume chooses the current harbor world")
	var sites := ["dam_vault","quarry","refinery_archive","steelworks","rail_yard","radar_archive","canyon","buried_archive","power_station","mountain_pass"]
	for site: String in sites:
		if not await depart_to(site): break
		if not await arrive(): break
		if site=="dam_vault" and not await retry_occupation(): break
		await clear_occupation(site)
		if CampaignCatalog.site_kind(site)=="outpost": await test_outpost(site)
		else: await finish_bunker()
		check(CampaignState.valid_checkpoint(game.campaign.checkpoint()),"Real site completion remains a valid checkpoint: "+site)
	check(CampaignCatalog.all_complete(game.campaign.completed) and game.campaign.completed.size()==12 and game.hud.overlay=="campaign_victory","Actual callbacks show final victory only after all twelve required sites")
	await fresh_menu()
	check(game.expedition.resume_saved() and game.hud.overlay=="campaign_victory" and paused,"Completed campaign resumes into its final result without a thirteenth mission")
	await test_midroad_join()
	await finish()
func test_midroad_join() -> void:
	await fresh_menu()
	game.start_scenario(1,OPTIONS)
	await frames()
	freeze()
	await finish_bunker()
	if not await depart_to("harbor"): return
	check(game.player_count==1 and game.campaign.player_count==1,"Separate prepared convoy begins with one driver")
	var saved_player: Dictionary=game.campaign.snapshots["1"].duplicate(true)
	game.players[0].progression.award_damage(500.0)
	check(game.players[0].progression.level>int(saved_player.level),"Real road combat XP is uncommitted before a local partner joins")
	game.join_coop()
	check(game.campaign.snapshots["1"]==saved_player,"Local join preserves the first player's secured snapshot")
	check(game.player_count==2 and game.campaign.player_count==2 and CampaignState.valid_checkpoint(game.campaign.checkpoint()),"Mid-road local join updates both current and departure snapshots consistently")
	check(game.expedition.vehicle.gunner_seat.occupant==game.players[1],"Joining local defender boards beside the moving convoy")
	game.expedition.vehicle.hp=0
	game.expedition.vehicle_destroyed()
	var old: int=game.get_instance_id()
	check(game.expedition.handle_command("retry",{},1),"Two-player convoy can retry after a mid-road join")
	if not await wait_reload(old,"travel"): return
	check(game.players.size()==2 and game.expedition.vehicle.gunner_seat.occupant==game.players[1] and CampaignState.valid_checkpoint(game.campaign.checkpoint()),"Actual retry restores both local crew and independent seats after joining")
	check(game.players[0].progression.level==int(saved_player.level) and is_equal_approx(game.players[0].progression.xp,float(saved_player.xp)),"Retry restores secured XP rather than uncommitted progress captured at local join")
func finish() -> void:
	paused=false
	if is_instance_valid(game): await CLEANUP.free_scene(game,self)
	for suffix in ["", ".tmp", ".bak"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(isolated_path+suffix))
	print("EXPEDITION FLOW: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
