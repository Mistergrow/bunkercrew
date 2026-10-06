extends SceneTree
## State transitions, finite rewards, retry boundaries and the existing V1 save.
var passed := 0
var failed := 0
class CrewProbe extends Node:
	var player_id := 1
	var character_id := "mara"
	var progression := PlayerProgression.new()
	func _init() -> void:
		add_child(progression)
class ResearchProbe extends Node:
	var points := 17
	var owned := {"boots":true,"weapon_handling":true,"convoy_mg":true}
	func has_upgrade(id: String) -> bool: return owned.has(id)

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if condition: passed+=1
	else: failed+=1; push_error(message)

func run() -> void:
	var crew := CrewProbe.new()
	var research := ResearchProbe.new()
	var state := CampaignState.new("user://expedition_routes_test.json",false)
	check(state.begin_new({"environment":"ash_foundry","build_type":"concrete","position":"left"},["mara","branko"],1),"New campaign starts at first defense")
	check(CampaignState.valid_checkpoint(state.checkpoint()),"New checkpoint passes strict schema")
	check(state.expedition.stage=="defense" and not state.expedition.vehicle.unlocked,"Truck is unavailable before twenty-wave victory")
	check(state.begin_journey("harbor").is_empty(),"Routes cannot bypass initial siege")
	var first := state.mission_start()
	check(not first.is_empty() and state.mission_running,"First campaign starts actual mission")
	check(state.complete_mission(first.id,19,[crew],research).is_empty(),"Wave nineteen cannot claim a vehicle")
	check(state.reserve_drop("first",3) and state.collect_salvage("first",3),"Only reserved finite mission salvage is banked")
	check(not state.collect_salvage("first",3),"Same salvage drop cannot be collected twice")
	var victory := state.complete_mission(first.id,20,[crew],research,{"steel":9,"scrap":6,"ammo":3})
	check(not victory.is_empty() and state.expedition.stage=="preparation","Wave twenty enters safe convoy preparation")
	check(state.expedition.vehicle.hp==600 and state.expedition.vehicle.fuel==12,"Recovered truck grants its finite initial supplies once")
	check(state.expedition.garage_stock=={"steel":9,"scrap":6,"ammo":3},"Victory banks only the supplied physical stock ledger")
	check(state.expedition.tech_points==17 and state.shared_personal_upgrades.has("convoy_mg"),"Unspent shared points and convoy research survive victory")
	check(state.complete_mission(first.id,20,[crew],research).is_empty(),"Duplicate victory cannot regrant supplies")
	check(state.select_destination("harbor"),"Secured entry opens next bunker route")
	check(state.select_stop("harbor:salvage"),"Crew chooses one optional roadside stop")
	check(state.prepare_expedition([crew],research) and state.expedition.selected_stop=="harbor:salvage" and state.expedition.garage_stock.steel==9,"Safe progress refresh preserves route and finite garage stock")
	check(not state.select_stop("quarry:weapon"),"A stop on a different route is rejected")
	check(state.mission_start().is_empty(),"Destination defense cannot bypass driving and occupation")
	var route := state.begin_journey()
	check(route.fuel_cost==10 and route.distance==2400,"Direct and detour costs fit bounded real travel arena")
	check(state.expedition.vehicle.fuel==12,"Departure reserves fuel; actual driving consumes it")
	check(not state.select_destination("harbor") and not state.select_stop(""),"Travel route cannot change during combat")
	check(not state.arrive_at_destination(),"An unclaimed selected stop cannot be skipped")
	check(CampaignState.valid_checkpoint(state.checkpoint()),"In-flight departure checkpoint is valid")
	var truck: Dictionary = state.expedition.vehicle.duplicate(true)
	truck.hp = 430.0
	truck.fuel = 7.0
	truck.cargo = {"concrete":15}
	truck.ammo = 14
	truck.reserve = 38
	check(state.update_vehicle(truck),"Authoritative runtime truck data is accepted")
	check(not state.update_vehicle(truck,true),"Transient combat state cannot be explicitly saved as preparation")
	check(state.reach_stop(),"Arriving route pauses for actual stop encounter")
	var stop_reward := state.secure_stop()
	check(stop_reward.cargo=={"steel":3} and CampaignCatalog.cargo_count(state.expedition.vehicle.cargo)==18,"Recovered cargo obeys capacity and never overfills")
	check(state.expedition.claimed_stops==["harbor:salvage"],"Cleared stop reward has one durable claim")
	check(state.secure_stop().is_empty(),"Repeated secure callbacks never grant a second reward")
	check(state.arrive_at_destination() and state.expedition.stage=="occupation","Arrival requires a bunker occupation encounter")
	state.expedition.vehicle.hp = 0.0
	state.fail_journey()
	check(state.expedition.stage=="failed","Vehicle loss enters failure stage")
	var retry := state.retry_journey()
	check(retry.resumed_after_stop and retry.stop.is_empty(),"Retry starts from cleared roadside stop without replaying reward")
	check(state.expedition.vehicle.hp==430 and state.expedition.vehicle.fuel==7,"Retry restores checkpoint HP and fuel, not free full supplies")
	check(state.expedition.vehicle.ammo==14 and state.expedition.vehicle.reserve==38,"Finite loaded MG and reserve rounds survive retry without refill")
	check(state.expedition.vehicle.cargo=={"concrete":15,"steel":3},"Retry restores actual earned and loaded cargo exactly")
	check(state.arrive_at_destination() and state.secure_destination(),"Cleared occupation starts next bunker deployment")
	check(state.expedition.garage_stock.is_empty(),"Old bunker stock cannot teleport to the next garage")
	check(state.expedition.vehicle.cargo.is_empty(),"Cargo leaves truck when transferred into bunker deployment")
	check(state.take_cargo()=={"concrete":15,"steel":3},"Fresh bunker receives only the material actually transported")
	check(state.take_cargo()==state.expedition.deployment_cargo,"Immutable delivery survives a failed bunker retry")
	check(not state.secure_destination(),"Destination clear cannot be applied twice")
	var second := state.mission_start()
	check(not second.is_empty() and second.options.environment=="abandoned_harbor","Next twenty-wave defense uses destination environment")
	state.fail_mission()
	check(not state.mission_start().is_empty(),"Failed defense can retry the same durable bunker deployment")
	var second_win := state.complete_mission(state.mission_id,20,[crew],research)
	check(not second_win.is_empty() and state.expedition.vehicle.fuel==7,"Second victory does not refill truck or recreate cargo")
	check(state.expedition.deployment_cargo.is_empty(),"Delivery from previous bunker is retired on victory")
	check(CampaignState.valid_checkpoint(state.checkpoint()),"Two secured sites and convoy state remain valid")
	check(state.unlock_route("dam_vault") and state.banked_salvage==0,"Legacy blueprint branch still spends exactly its three earned data")
	check(not state.unlock_route("dam_vault"),"Repeated unlock cannot spend twice")
	var legacy := state.checkpoint()
	legacy.version=1
	legacy.erase("expedition")
	legacy.shared_personal_upgrades=["boots","weapon_handling"]
	check(CampaignState.valid_checkpoint(legacy),"Existing V1 campaign is accepted for migration")
	var migrated := CampaignState.migrate_checkpoint(legacy)
	check(migrated.version==2 and migrated.expedition.vehicle.fuel==12 and migrated.completed==legacy.completed,"V1 migration preserves history and introduces recovered convoy once")
	check(CampaignState.migrate_checkpoint(migrated)==migrated,"V2 reload never reapplies migration rewards")
	var invalid := state.expedition.duplicate(true)
	invalid.vehicle.cargo={"steel":19}
	check(not CampaignState.valid_expedition(invalid),"Cargo overflow rejected")
	invalid=state.expedition.duplicate(true); invalid.vehicle.fuel=NAN
	check(not CampaignState.valid_expedition(invalid),"Nonfinite fuel rejected")
	invalid=state.expedition.duplicate(true); invalid.vehicle.hp=601
	check(not CampaignState.valid_expedition(invalid),"Armor above actual researched maximum rejected")
	invalid=state.expedition.duplicate(true); invalid.vehicle.upgrades=["convoy_armor_heavy"]
	check(not CampaignState.valid_expedition(invalid),"Dependent vehicle research requires its parent")
	invalid=state.expedition.duplicate(true); invalid.claimed_stops=["harbor:salvage","harbor:salvage"]
	check(not CampaignState.valid_expedition(invalid),"Duplicate stop claims rejected")
	invalid=state.expedition.duplicate(true); invalid.stage="travel"; invalid.departure={}
	check(not CampaignState.valid_expedition(invalid),"Travel requires a durable departure checkpoint")
	invalid=state.expedition.duplicate(true); invalid.epic_weapons=["veteran_rifle"]
	check(not CampaignState.valid_expedition(invalid),"Epic weapons require an actual claimed weapon-cache stop")
	invalid=state.expedition.duplicate(true); invalid.vehicle.reserve=241
	check(not CampaignState.valid_expedition(invalid),"Vehicle ammo reserve cannot exceed bounded snapshot limit")
	check(CampaignCatalog.route_fuel("harbor","harbor:fuel",["convoy_tank","convoy_economy"])==8,"Efficient motor reduces total drive cost by 25 percent before rounding")
	var stats := CampaignCatalog.vehicle_stats(CampaignCatalog.VEHICLE_UPGRADES)
	check(stats.max_hp==1100 and stats.cargo_capacity==36 and stats.fuel_capacity==50 and stats.mounted_mg,"All vehicle stats match shared research descriptions")
	await check_persistence(state)
	check_epic_stop(state)
	crew.free()
	research.free()
	print("EXPEDITION ROUTES: %d passed, %d failed" % [passed,failed])
	quit(1 if failed else 0)

func check_persistence(state: CampaignState) -> void:
	var path := "user://expedition_routes_fixture_%d.json" % Time.get_ticks_usec()
	var disk := CampaignState.new(path,true)
	# Isolated test-owned path deliberately opts into persistence despite the
	# global no-profile-save flag. The user's actual profile remains untouched.
	disk.persistence_enabled=true
	disk._restore(state.checkpoint())
	check(disk.save_checkpoint(),"V2 checkpoint writes and verifies temporary file")
	var reader := CampaignState.new(path,true)
	reader.persistence_enabled=true
	check(reader.load_checkpoint() and JSON.parse_string(JSON.stringify(reader.checkpoint()))==JSON.parse_string(JSON.stringify(disk.checkpoint())),"Real JSON disk round trip preserves nested convoy state")
	check(disk.save_checkpoint(),"Second checkpoint creates recoverable backup")
	var broken := FileAccess.open(path,FileAccess.WRITE)
	broken.store_string("{broken")
	broken.close()
	check(reader.load_checkpoint() and reader.recovered_backup,"Corrupt primary recovers last valid backup")
	var legacy := disk.checkpoint()
	legacy.version=1; legacy.erase("expedition"); legacy.shared_personal_upgrades=["boots"]
	var old_file := FileAccess.open(path,FileAccess.WRITE)
	old_file.store_string(JSON.stringify(legacy)); old_file.close()
	check(reader.load_checkpoint() and reader.expedition.vehicle.unlocked,"Actual V1 file is migrated on read")
	check(reader.save_checkpoint() and int(JSON.parse_string(FileAccess.get_file_as_string(path)).version)==2,"Next successful write upgrades file to V2")
	var fail_save := CampaignState.new("user://missing_campaign_directory/never.json",true)
	fail_save.persistence_enabled=true
	fail_save._restore(state.checkpoint())
	var before := fail_save.checkpoint()
	check(not fail_save.select_destination("quarry") and fail_save.checkpoint()==before,"Failed disk write rolls route selection back atomically")
	for suffix: String in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	await process_frame

func check_epic_stop(previous: CampaignState) -> void:
	var state := CampaignState.new("user://epic_stop_never_save.json",false)
	state._restore(previous.checkpoint())
	check(state.select_destination("quarry") and state.select_stop("quarry:weapon"),"Next cleared frontier offers a guarded weapon cache")
	check(state.begin_journey().is_empty(),"Detour cannot depart without all required fuel")
	var truck: Dictionary = state.expedition.vehicle.duplicate(true)
	truck.fuel=12.0
	state.update_vehicle(truck)
	check(not state.begin_journey().is_empty() and state.reach_stop(),"Fueled weapon-cache journey reaches its encounter")
	var reward := state.secure_stop()
	check(reward.weapon=="storm_arcgun" and state.expedition.epic_weapons==["storm_arcgun"],"This destination grants its actual finite epic weapon")
	check(CampaignState.valid_checkpoint(state.checkpoint()),"Earned epic weapon and stop claim validate together")
	state.fail_journey()
	state.retry_journey()
	check(state.secure_stop().is_empty() and state.expedition.epic_weapons.size()==1,"Retry never repeats a claimed weapon reward")
