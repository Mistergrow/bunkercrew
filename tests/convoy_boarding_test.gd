extends SceneTree
## Prepared siege victory, actual garage boarding, scene reload, flat tire,
## secured stop and return to its finite checkpoint. No live player profiles.
const Journey := preload("res://scripts/convoy_journey.gd")
const Controller := preload("res://scripts/expedition_controller.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var game
var checks := 0
var failures := 0
var isolated_path := "user://convoy-boarding-%d.json" % OS.get_process_id()

func _initialize() -> void: run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	print("BOARDING %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)

func freeze() -> void:
	paused=true
	game.rounds.set_process(false)
	game.rounds.running=false
	game.expedition.set_physics_process(false)
	game.medic.set_physics_process(false)
	game.campaign.save_path=isolated_path
	game.campaign.persistence_enabled=true
	for player in game.players:
		player.set_physics_process(false)
		player.get_node("WorkerWeapon").set_physics_process(false)
	if is_instance_valid(game.expedition.vehicle): game.expedition.vehicle.set_physics_process(false)
	for station in get_nodes_in_group("stations"):
		if station.game==game: station.set_process(false)
	for enemy in get_nodes_in_group("enemies"):
		if enemy.game==game: enemy.set_physics_process(false)

func wait_reload(previous: int, expected: String) -> bool:
	var deadline := Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.get_instance_id()!=previous:
			game=current_scene
			if game.started and game.expedition.stage==expected:
				freeze()
				return true
	check(false,"Actual world reload reaches "+expected)
	return false

func clear_guards() -> void:
	for enemy in get_nodes_in_group("enemies"):
		if enemy.game==game and not enemy.is_queued_for_deletion(): enemy.take_damage(enemy.hp+1)
	for frame in 3: await process_frame

func run() -> void:
	if not "--no-profile-save" in OS.get_cmdline_user_args() or not "--no-upnp" in OS.get_cmdline_user_args(): quit(2); return
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	game.start_scenario(2,{"environment":"ash_foundry","build_type":"workshop","position":"left"})
	freeze()
	game.rounds.wave=Balance.TOTAL_WAVES
	check(game.expedition.on_victory(),"Prepared real wave twenty unlocks the finite vehicle")
	check(game.expedition.handle_command("prepare",{},1),"Garage displays its actual parked vehicle")
	freeze()
	check(game.expedition.handle_command("route",{"id":"harbor"},1) and game.expedition.handle_command("stop",{"id":"harbor:salvage"},1),"Real route and optional stop are selected")
	var controller=game.expedition
	var truck=controller.vehicle
	var before: Dictionary=game.campaign.checkpoint()
	var stores: Dictionary=controller._capture_stock()
	check(controller.handle_command("depart",{},1),"Depart closes the map and requests visible boarding")
	check(controller.boarding_active() and not paused and not truck.driving_enabled and truck.velocity==Vector2.ZERO,"Crew boards a parked van with gameplay controls active")
	check(game.campaign.checkpoint()==before and controller._capture_stock()==stores and not game._restart_pending,"Starting boarding commits no departure, scene handoff or resources")
	for person in game.players: person.position=truck.position
	check(truck.board(game.players[0],"passenger_left"),"First player deliberately boards a passenger role")
	controller._physics_process(.05)
	check(not controller.crew_ready() and truck.journey_state.phase=="boarding","A passenger alone cannot dispatch a driverless journey")
	check(truck.board(game.players[1],"driver") and controller.crew_ready(),"Every connected living worker and a real driver are required")
	controller._physics_process(.05)
	check(truck.journey_state.phase=="departure" and not game._restart_pending,"Full crew begins a visible departure countdown")
	truck.dismount(game.players[0])
	controller._physics_process(.05)
	check(truck.journey_state.phase=="boarding" and truck.journey_state.phase_time==0,"Exiting resets readiness and the departure countdown")
	check(controller.handle_command("map",{},1) and not controller.boarding_active(),"Host can abort boarding back to the garage map")
	check(truck.seats.all(func(seat):return not is_instance_valid(seat.occupant)) and game.campaign.checkpoint()==before and controller._capture_stock()==stores,"Abort unboards all crew without changing stock or checkpoint")
	var rounds: Array=[]
	for person in game.players:
		var weapon: WorkerWeapon=person.get_node("WorkerWeapon")
		rounds.append(weapon.capture_ammunition())
		weapon.reserve=0
		weapon.open_pack=0
		for kind in weapon.loaded: weapon.loaded[kind]=0
	check(not controller.handle_command("depart",{},1) and not controller.boarding_active(),"Completely unarmed crew stays in the garage to reload")
	for index in game.players.size(): game.players[index].get_node("WorkerWeapon").restore_ammunition(rounds[index])
	check(controller.handle_command("depart",{},1),"Loaded personal weapons permit departure without requiring MG research")
	for person in game.players: person.position=truck.position
	truck.board(game.players[0],"passenger_left")
	truck.board(game.players[1],"driver")
	check(controller.crew_seat_roles()==["passenger_left","driver"],"Transport roles preserve which crew member actually drives")
	controller._physics_process(.05)
	var previous: int=game.get_instance_id()
	for frame in 6:
		Journey.advance(truck.journey_state,.1)
		controller._physics_process(.1)
	check(not game._restart_pending and truck.journey_state.phase=="departure","Half of the countdown cannot skip the boarding scene")
	for frame in 10:
		if game._restart_pending: break
		Journey.advance(truck.journey_state,.1)
		controller._physics_process(.1)
	check(game._restart_pending,"Ready crew dispatches the actual atomic scene transition")
	if not await wait_reload(previous,"travel"): await finish(); return
	controller=game.expedition
	truck=controller.vehicle
	check(truck.seat_for(game.players[0]).role=="passenger_left" and truck.driver_seat.occupant==game.players[1],"Actual loaded journey restores the chosen driver and passenger")
	check(truck.journey_state.phase=="starting" and not truck.driving_enabled,"Loaded road begins with a finite engine-start window")
	check(game.world_left==740 and game.world_right==3700 and game.scenario_combat.arena_left==740,"Road floor and combat/camera limits exclude the hidden old bunker")
	var payload: Dictionary={"checkpoint":game.campaign.checkpoint(),"mode":"travel","options":game.scenario_options.duplicate()}
	check(Controller.valid_transition(payload),"Original three-field disk/resume payload remains supported")
	payload.crew_seats=["passenger_left","driver"]
	check(Controller.valid_transition(payload),"Optional unique crew roles validate on the real travel checkpoint")
	payload.crew_seats=["driver","driver"]
	check(not Controller.valid_transition(payload),"Duplicate driver roles cannot enter a scene transition")
	for frame in 9:
		Journey.advance(truck.journey_state,.1)
		controller._physics_process(.1)
	check(game.travel_cinematic.active and game.travel_cinematic.blocks_gameplay() and not truck.driving_enabled,"Fresh departure presents its shared scene before the normal ignition completes")
	for frame in ceili(game.travel_cinematic.startup_duration()/.1):
		if truck.journey_state.phase=="driving": break
		Journey.advance(truck.journey_state,.1)
		controller._physics_process(.1)
	check(truck.journey_state.phase=="driving" and truck.driving_enabled and truck.journey_state.events[0].kind=="engine_start","Starter publishes after baseline and enables driving only at completion")
	truck.position.x=Controller.ROAD_START+(Controller.ROAD_END-Controller.ROAD_START)*Journey.BREAKDOWN_PROGRESS
	controller._physics_process(.05)
	check(truck.journey_state.phase=="repair" and not truck.driving_enabled and controller.stage=="travel","Authored flat tire stops the real road journey")
	check(truck.can_service(game.players[1]) and truck.seat_for(game.players[0])!=null,"Driver can work immediately while the passenger keeps defending")
	var contacts: int=controller._living_guards()
	controller._physics_process(.05)
	check(contacts>0 and contacts<=Controller.MAX_ROAD_GUARDS and controller._living_guards()==contacts,"Breakdown defense is bounded and cannot spawn repeatedly")
	truck.service_action(game.players[1],.05,false,true)
	check(not truck.journey_state.solo_assist,"Two connected players cannot request invisible solo repair")
	# Exercise the same host helper to prepare the completed repair; the focused
	# journey test separately proves each held/timed tool input and guard.
	for frame in 1000:
		if truck.journey_state.phase!="repair": break
		Journey.advance(truck.journey_state,.05)
		Journey.service(truck.journey_state,.05,false,true,2)
	check(truck.journey_state.phase=="reboarding" and truck.journey_state.repair_bolts==3,"Finite held-tool fallback completes a full real journey tire")
	controller._physics_process(.05)
	check(not truck.driving_enabled,"Completed tire waits for the missing driver to reboard")
	check(truck.board(game.players[1],"driver"),"Real repairer can board the freed driver seat")
	for frame in 7: Journey.advance(truck.journey_state,.1)
	controller._physics_process(.1)
	check(truck.driving_enabled and truck.journey_state.phase=="driving","Seated repaired crew resumes driving")
	await clear_guards()
	truck.position.x=2100
	controller._physics_process(.05)
	check(controller.stage=="stop","Optional roadside encounter still follows the repaired segment")
	await clear_guards()
	check(controller.handle_command("resume",{},1),"Cleared roadside encounter secures its finite reward")
	var boundary: Dictionary=game.campaign.expedition.departure.duplicate(true)
	var claimed: Array=game.campaign.expedition.claimed_stops.duplicate()
	var garage: Dictionary=game.campaign.expedition.garage_stock.duplicate()
	game.campaign.fail_journey()
	previous=game.get_instance_id()
	check(controller.handle_command("garage",{},1),"Failed journey can return to its actual last secured checkpoint")
	if not await wait_reload(previous,"preparation"): await finish(); return
	check(game.campaign.expedition.vehicle==boundary.vehicle and game.campaign.snapshots==boundary.snapshots,"Actual garage reload restores exact secured cargo, fuel and personal ammunition")
	check(game.campaign.expedition.garage_stock==garage and game.campaign.expedition.claimed_stops==claimed and game.campaign.expedition.departure.is_empty(),"Garage return preserves finite stores and claimed rewards without granting new materials")
	check(game.scenario_options.environment=="ash_foundry" and game.expedition.vehicle.journey_state.phase=="garage", "Garage return restores the source scenery and parked gameplay phase")
	var saved := CampaignState.new(isolated_path,false)
	saved.persistence_enabled=true
	check(saved.load_checkpoint() and saved.expedition.stage=="preparation" and saved.expedition.departure.is_empty(),"Closing immediately after garage return resumes the garage rather than an old road checkpoint")
	await finish()

func finish() -> void:
	paused=false
	if is_instance_valid(game): await Cleanup.free_scene(game,self)
	for suffix: String in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(isolated_path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(isolated_path+suffix))
	print("CONVOY BOARDING CHECKS: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
