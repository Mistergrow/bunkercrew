extends SceneTree
## Prepared valid completed campaign; the return journey itself uses real
## steering, fuel, scene handoffs, physical crates and survivor interaction.
## This does not claim that a human or bot fought the eight twenty-wave shifts.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Catalog := preload("res://scripts/solo_story_catalog.gd")
const Protocol := preload("res://scripts/network_protocol.gd")
const Messages := preload("res://scripts/network_messages.gd")
const World := preload("res://scripts/network_world.gd")
var checks := 0
var failures := 0
var game: Node
var fixture_root := ""
var observations: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	print("REVISIT %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)

func freeze() -> void:
	game.rounds.running=false
	for actor: Node in game.find_children("*","Node",true,false):
		actor.set_physics_process(false)
	game.set_process(false)
	game.rounds.set_process(false)
	game.solo_story.set_process(false)
	game.story.set_process(false)

func prepared_checkpoint(count: int, carried: Dictionary, cargo: Dictionary) -> Dictionary:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(count,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	freeze()
	game.rounds.wave=20
	check(game.expedition.on_victory(),"Prepared wave20 evidence reaches the real victory ledger")
	var saved: Dictionary=game.campaign.checkpoint()
	saved.completed.clear()
	saved.claimed_missions.clear()
	saved.unlocked_routes.clear()
	saved.blueprints.clear()
	saved.banked_salvage=0
	saved.total_salvage_earned=0
	for site: Dictionary in CampaignCatalog.NODES:
		saved.completed.append(site.id)
		saved.claimed_missions.append(saved.campaign_id+":"+str(site.id))
		if int(site.cost)>0:
			saved.unlocked_routes.append(site.id)
			saved.total_salvage_earned+=int(site.cost)
		if not str(site.blueprint).is_empty(): saved.blueprints.append(site.blueprint)
	saved.current_node="mountain_pass"
	saved.pending_node="mountain_pass"
	saved.expedition.stage="preparation"
	saved.expedition.departure={}
	saved.expedition.garage_stock={"steel":37,"ammo":11,"concrete":15}
	saved.expedition.vehicle.fuel=30.0
	saved.expedition.vehicle.cargo=cargo.duplicate()
	saved.expedition.vehicle.ammo=7
	saved.expedition.vehicle.reserve=13
	saved.expedition.vehicle.upgrades=["convoy_mg"]
	saved.shared_personal_upgrades=["convoy_mg"]
	for index in count:
		var snapshot: Dictionary=saved.snapshots[str(index+1)]
		snapshot.inventory=carried.duplicate() if index==0 else {}
		snapshot.ammunition.loaded.rifle=7
		snapshot.ammunition.reserve=9
	check(CampaignState.valid_checkpoint(saved),"Prepared full campaign, finite supplies and every character snapshot validate")
	return saved

func payload(saved: Dictionary, mode: String) -> Dictionary:
	var options: Dictionary=saved.options.duplicate()
	var site: String=saved.pending_node if mode in ["occupation","defense"] else saved.current_node
	options.environment=CampaignCatalog.node(site).environment
	return {"checkpoint":saved,"mode":mode,"options":options}

func authority_packet() -> void:
	var world:=World.new()
	world.bind(game)
	var captured:=world.capture()
	var packet:=Protocol.decode(Protocol.encode({"kind":"snapshot","generation":1,"seq":1,"paused":false,"world":captured}))
	check(Messages.valid(packet,false),"Actual authoritative return-visit world passes the unchanged network codec and snapshot envelope")
	check(world._validate(packet.world),"Actual return-visit snapshot passes complete world validation: "+world.last_error)

func state_case(count: int, empty: bool) -> void:
	var hands: Dictionary={} if empty else {"concrete":2,"steel":1}
	var cargo: Dictionary={} if empty else {"ammo":2,"steel":3}
	var saved:=prepared_checkpoint(count,hands,cargo)
	var campaign_id: String=saved.campaign_id
	await Cleanup.free_scene(game,self)
	game=null
	var path:=fixture_root.path_join("state-%d-%s.json"%[count,str(empty)])
	var state:=CampaignState.new(path,false)
	state._restore(saved)
	state.persistence_enabled=true
	check(not state.can_revisit("mountain_pass") and not state.can_revisit("last_shift"),"Current garage and entry without an inbound route cannot become self trips")
	check(state.can_revisit("quarry") and state.route_status("quarry").can_travel,"A skipped quarry survivor remains reachable after all twelve completed sites")
	check(state.select_destination("quarry"),"Return visit uses ordinary destination selection")
	check(not state.select_stop("quarry:fuel") and state.expedition.selected_stop.is_empty(),"Safe follow-up visits cannot reopen finite roadside rewards")
	var departure:=state.checkpoint()
	check(not state.begin_journey().is_empty(),"Return visit starts an ordinary paid-fuel journey")
	var disk:=CampaignState.new(path,false)
	disk.persistence_enabled=true
	check(disk.load_checkpoint() and disk.expedition.stage=="travel" and disk.pending_node=="quarry", "Real JSON continuation retains the selected return visit")
	var vehicle: Dictionary=state.expedition.vehicle.duplicate(true)
	vehicle.hp=0.0
	vehicle.fuel=1.0
	vehicle.ammo=0
	vehicle.reserve=0
	check(state.update_vehicle(vehicle),"Prepared journey loss uses finite vehicle update")
	state.fail_journey()
	check(not state.retry_journey().is_empty() and state.expedition.vehicle==departure.expedition.vehicle and state.snapshots==departure.snapshots,"Failed return trip restores precisely the finite departure vehicle, crew and ammunition")
	check(state.arrive_at_destination() and state.secure_destination(),"Secured destination becomes a safe garage through the ordinary arrival API")
	var result:=state.checkpoint()
	check(result.current_node=="quarry" and result.pending_node=="quarry" and result.expedition.stage=="preparation","Return arrival does not start another twenty-wave siege")
	check(result.campaign_id==campaign_id and result.completed==saved.completed and result.claimed_missions==saved.claimed_missions and result.blueprints==saved.blueprints and result.banked_salvage==saved.banked_salvage and result.total_salvage_earned==saved.total_salvage_earned,"All twelve claims, blueprints, earned currency and campaign identity remain unchanged")
	var expected: Dictionary={} if empty else {"concrete":2,"steel":4,"ammo":2}
	check(result.expedition.garage_stock==expected and result.expedition.vehicle.cargo.is_empty() and result.expedition.deployment_cargo.is_empty(),"Only actual hands and vehicle cargo become destination stock; source warehouse is not cloned")
	check(state.mission_start().is_empty() and not state.mission_running and not state.reserve_drop("repeat",3),"Return visit cannot mint mission drops or start a previously claimed mission")
	check(state.complete_mission(campaign_id+":quarry",20,[]).is_empty() and state.complete_outpost(campaign_id+":quarry",0,true,[]).is_empty(),"Both victory APIs reject repeated reward claims")
	var restored:=CampaignState.new(path,false)
	restored.persistence_enabled=true
	check(restored.load_checkpoint() and JSON.parse_string(JSON.stringify(restored.checkpoint()))==JSON.parse_string(JSON.stringify(result)),"Post-visit JSON checkpoint retains exact inventory ownership")
	for visit in 3:
		game=load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene=game
		check(game.expedition.restore(payload(result,"preparation")),"Repeated completed-campaign garage continuation is accepted")
		freeze()
		var physical: Dictionary=game.expedition._capture_stock()
		for kind: String in CampaignCatalog.CARGO_KINDS:
			check(int(physical.get(kind,0))==int(expected.get(kind,0)),"Continuation %d keeps exact %s supplies"%[visit,kind])
		check(game.scenario_bunker.roof_guns.all(func(gun): return gun.ammo==0 and gun.reserve==0),"Continuation grants no fresh rooftop magazines")
		for worker: Node in game.players:
			check(worker.get_node("WorkerWeapon").capture_ammunition()==result.snapshots[str(worker.player_id)].ammunition,"Personal loaded rounds and reserve survive without refill")
		game.expedition._spawn_vehicle(Vector2(game.scenario_bunker.room_right+170,430))
		check(game.expedition.vehicle.ammo==7 and game.expedition.vehicle.reserve==13,"Finite convoy rounds survive without refill")
		authority_packet()
		paused=false
		await Cleanup.free_scene(game,self)
		game=null
	observations.append({"players":count,"empty_cargo":empty,"repeated_continuations":3,"stock":expected,"completed_sites":result.completed.size()})

func journey_case() -> void:
	var saved:=prepared_checkpoint(1,{"concrete":2},{"steel":2})
	await Cleanup.free_scene(game,self)
	var state:=CampaignState.new("user://unused-revisit-journey.json",false)
	state._restore(saved)
	check(state.select_destination("quarry") and not state.begin_journey().is_empty(),"Prepared actual solo journey selects the missed contact")
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.story_mode=true
	check(game.expedition.restore(payload(state.checkpoint(),"travel")),"Actual full-completed solo export state restores into travel instead of being forced into the ending")
	check(game.expedition.vehicle.journey_state.breakdown_done,"Safe follow-up journey does not invent another forced tire encounter")
	var start_fuel: float=game.expedition.vehicle.fuel
	Input.action_press("p1_right")
	var started:=Time.get_ticks_msec()
	var reached:=false
	var quiet_road:=true
	var telemetry_clock:=0
	while Time.get_ticks_msec()-started<45000:
		await physics_frame
		if is_instance_valid(current_scene) and current_scene!=game: game=current_scene
		if not is_instance_valid(game): continue
		if game.started and not game._restart_pending and game.expedition.stage=="preparation" and game.campaign.current_node=="quarry" and game.scenario_options.environment=="basalt_quarry":
			reached=true
			break
		if game.expedition.stage=="travel" and not game.travel_cinematic.blocks_gameplay(): Input.action_press("p1_right")
		quiet_road=quiet_road and game.expedition.guard_count==0 and get_nodes_in_group("enemies").is_empty()
		telemetry_clock+=1
		if telemetry_clock%300==0:
			print("REVISIT DRIVE stage=",game.expedition.stage," paused=",paused," overlay=",game.hud.overlay," progress=",game.expedition.progress," position=",game.expedition.vehicle.position if is_instance_valid(game.expedition.vehicle) else Vector2.INF," vehicle=",game.expedition.vehicle.journey_state if is_instance_valid(game.expedition.vehicle) else {}," right=",Input.is_action_pressed("p1_right"))
	Input.action_release("p1_right")
	check(quiet_road,"Actual safe return road contains no reward-bearing spawned guard")
	check(reached,"Native steering completes both real scene handoffs into the quarry garage")
	if reached:
		freeze()
		paused=false
		game.hud.overlay=""
		check(game.campaign.completed==saved.completed and not game.campaign.mission_running,"Live follow-up keeps all chapter claims and starts no new mission")
		check(game.expedition.vehicle.fuel<start_fuel and game.expedition.guard_count==0,"Real return drive spends fuel and produces no combat rewards")
		check(game.solo_story.enabled and game.solo_story.npcs.has("oskar"),"Missed physical Oskar is present after actual trip and chapter reload")
		var worker: Worker=game.players[0]
		var npc: Node2D=game.solo_story.npcs.get("oskar")
		var crate: Supply
		for supply: Node in get_nodes_in_group("supplies"):
			if supply.game==game and supply.kind=="concrete" and supply.amount>0: crate=supply; break
		check(is_instance_valid(crate) and crate.amount==2,"Previously carried rescue concrete arrives as one finite real supply")
		if is_instance_valid(crate) and is_instance_valid(npc):
			worker.position=crate.position
			for unused in 2: crate.interact(worker,Balance.TRANSFER_TIME+.01)
			worker.position=npc.position+Vector2(20,0)
			check(npc.interact(worker,0.0) and game.solo_story.encounter_view().can_recruit,"Ordinary physical encounter can rescue Oskar after the skipped completed chapter")
			check(game.solo_story.recruit("oskar") and CharacterCatalog.is_unlocked("oskar") and worker.inventory.get("concrete",0)==0,"Actual explicit rescue consumes exactly two transported concrete and unlocks Oskar")
			check(not game.solo_story.recruit("oskar"),"Repeated admission cannot charge or award again")
		observations.append({"actual_steering":true,"actual_scene_handoffs":2,"destination":"quarry","late_rescue":"oskar","fuel_before":start_fuel,"fuel_after":game.expedition.vehicle.fuel})
	paused=false
	if is_instance_valid(game): await Cleanup.free_scene(game,self)
	game=null

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args(): quit(2); return
	AudioServer.set_bus_mute(0,true)
	CrewRoster.persistence_enabled=false
	CrewRoster._loaded=true
	CrewRoster.unlocked.clear()
	fixture_root=ProjectSettings.globalize_path("res://artifacts/p1-beta-readiness-20261004/story-balance/persistence-%d"%OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(fixture_root)
	if "--journey-only" not in OS.get_cmdline_user_args():
		for count in [1,2]:
			for empty in [true,false]: await state_case(count,empty)
	CrewRoster.unlocked.clear()
	Engine.time_scale=4.0
	await journey_case()
	Engine.time_scale=1.0
	var report:={"checks":checks,"failures":failures,"cases":observations,"prepared_states":["All twelve chapter claims, initial finite vehicle/cargo/crew are prepared valid ledger fixtures, not real combat victories.","State loss explicitly mutates vehicle hp/fuel/rounds to test rewind, not normal driving.","Three real scene continuations per state fixture exercise source ledger suppression and unchanged protocol/world validation.","Solo follow-up uses native steering and two actual deferred scene reloads; only the final supply/NPC approach omits walking.","Physical finite supplies pay the missed Oskar admission; no invented rescue materials."],"limits":["No native Windows/WAN or human playtest claim.","No persistent reconstruction of every built room, roof magazine or binder across previous sites.","This does not prove eight regular twenty-wave defenses or the twelve-chapter human balance gate."]}
	FileAccess.open("res://artifacts/p1-beta-readiness-20261004/story-balance/revisit-test.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for filename: String in DirAccess.get_files_at(fixture_root): DirAccess.remove_absolute(fixture_root.path_join(filename))
	DirAccess.remove_absolute(fixture_root)
	print("CAMPAIGN REVISIT: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
