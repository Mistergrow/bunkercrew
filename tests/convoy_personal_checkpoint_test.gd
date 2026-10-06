extends SceneTree
## Real road weapon expenditure, earned progression and collected material must
## survive atomic safe stops and actual destination world replacement.
const Journey := preload("res://scripts/convoy_journey.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const World := preload("res://scripts/network_world.gd")
const Protocol := preload("res://scripts/network_protocol.gd")
var game
var checks := 0
var failures := 0
var isolated_path := "user://convoy-personal-%d.json" % OS.get_process_id()

func _initialize() -> void: run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	print("PERSONAL CHECKPOINT %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)

func freeze() -> void:
	paused=true
	game.rounds.running=false
	game.rounds.set_process(false)
	game.expedition.set_physics_process(false)
	game.medic.set_physics_process(false)
	game.campaign.save_path=isolated_path
	game.campaign.persistence_enabled=true
	for player in game.players:
		player.set_physics_process(false)
		player.get_node("WorkerWeapon").set_physics_process(false)
	if is_instance_valid(game.expedition.vehicle): game.expedition.vehicle.set_physics_process(false)
	for enemy in get_nodes_in_group("enemies"):
		if enemy.game==game: enemy.set_physics_process(false)
	for station in get_nodes_in_group("stations"):
		if station.game==game: station.set_process(false)

func wait_reload(previous: int,expected: String) -> bool:
	var deadline:=Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.get_instance_id()!=previous:
			game=current_scene
			if game.started and game.expedition.stage==expected:
				freeze()
				return true
	check(false,"Real replacement reaches "+expected)
	return false

func start_driving() -> bool:
	# This fixture freezes the world after reload. Advance the actual shared
	# startup interval before requesting an ordinary garage action.
	var controller=game.expedition
	var truck=controller.vehicle
	var tick:=1.0/float(Engine.physics_ticks_per_second)
	var budget:=ceili((game.travel_cinematic.startup_duration()+1.0)/tick)
	for unused in budget:
		if truck.journey_state.phase=="driving": break
		await physics_frame
		truck._physics_process(tick)
		controller._physics_process(tick)
	check(truck.journey_state.phase=="driving" and truck.driving_enabled,"Actual startup cinematic and ignition complete before an ordinary garage action")
	return truck.journey_state.phase=="driving" and truck.driving_enabled

func clear_guards() -> void:
	for enemy in get_nodes_in_group("enemies"):
		if enemy.game==game and not enemy.is_queued_for_deletion(): enemy.take_damage(enemy.hp+1)
	for frame in 3: await process_frame

func live_snapshots() -> Dictionary:
	var result: Dictionary={}
	for player in game.players: result[str(player.player_id)]=CampaignBonus.snapshot_player(player)
	return result

func spend_and_earn(amount: float) -> void:
	var player=game.players[1]
	var weapon: WorkerWeapon=player.get_node("WorkerWeapon")
	weapon.cooldown=0
	weapon.aim_direction=Vector2.UP
	var rounds:=weapon.total_ammunition()
	check(weapon.fire() and weapon.total_ammunition()==rounds-1,"Actual passenger shot consumes one finite personal round")
	player.progression.award_team(amount,"repair")
	check(player.progression.level>1 or player.progression.xp>=amount,"Real progression award changes run-local crew progress")

func disk_checkpoint() -> Dictionary:
	var saved:=CampaignState.new(isolated_path,false)
	saved.persistence_enabled=true
	return saved.checkpoint() if saved.load_checkpoint() else {}

func collect_scrap(amount: int) -> void:
	var collector=game.players[0]
	var truck=game.expedition.vehicle
	if truck.seat_for(collector)!=null: truck.dismount(collector)
	collector.position=truck.position+Vector2(-170,0)
	var previous_amount:=int(collector.inventory.get("scrap",0))
	var pickup:=ResourcePickup.new()
	pickup.game=game
	pickup.kind="scrap"
	pickup.amount=amount
	pickup.position=collector.position+Vector2(-12,0)
	game.add_child(pickup)
	for frame in 3: await physics_frame
	pickup.interact(collector,0)
	check(collector.inventory.get("scrap",0)==previous_amount+amount,"Actual world pickup transfers exact finite scrap into player hands")

func persisted_inventory_graph() -> void:
	# JSON whole numbers are floats. Exercise the actual saved file, fresh host
	# restoration and complete network entity graph, not a hand-built inventory.
	var saved:=CampaignState.new(isolated_path,false)
	saved.persistence_enabled=true
	check(saved.load_checkpoint(),"Fresh JSON campaign file reloads its secured-stop inventory")
	check(saved.snapshots["1"].inventory.scrap is float and saved.snapshots["1"].inventory.scrap==2.0,"Actual JSON parser supplies whole-number float quantities to campaign restoration")
	var payload: Dictionary={"checkpoint":saved.checkpoint(),"mode":"travel","options":saved.options.duplicate()}
	var hosts: Array=[]
	var viewports: Array[SubViewport]=[]
	for index in 2:
		var viewport:=SubViewport.new()
		viewport.world_2d=World2D.new()
		root.add_child(viewport)
		viewports.append(viewport)
		var restored=load("res://scenes/main.tscn").instantiate()
		viewport.add_child(restored)
		hosts.append(restored)
		check(restored.expedition.restore(payload),"Persisted crew restores into independent "+("host" if index==0 else "guest")+" World2D")
		check(restored.players[0].inventory=={"scrap":2} and restored.players[0].inventory.scrap is int,"Restored physical inventory keeps exact quantities as canonical wire integers")
	var authority:=World.new()
	authority.bind(hosts[0])
	var graph: Dictionary=authority.capture()
	var observed_player:=false
	for record: Dictionary in graph.entities:
		if record.id=="player:1":
			observed_player=record.state.inventory=={"scrap":2} and record.state.inventory.scrap is int
	check(observed_player,"Actual authoritative graph captures the restored player's canonical inventory")
	var decoded:=Protocol.decode(Protocol.encode({"kind":"snapshot","generation":1,"seq":1,"paused":false,"world":graph}))
	var replica:=World.new()
	replica.bind(hosts[1])
	check(replica.apply(decoded.world),"Complete decoded world graph accepts persisted inventory at the real replica validator: "+replica.last_error)
	check(hosts[1].players[0].inventory=={"scrap":2} and hosts[1].players[0].inventory.scrap is int,"Applied guest keeps exact collected material and canonical integer quantities")
	var physical: Dictionary=hosts[1].expedition._capture_stock()
	check(replica.apply(decoded.world) and hosts[1].expedition._capture_stock()==physical and hosts[1].players[0].inventory=={"scrap":2},"Repeated full graph application cannot duplicate personal or warehouse resource ownership")
	for restored in hosts: await Cleanup.free_scene(restored,self)
	for viewport in viewports: viewport.queue_free()
	await process_frame

func run() -> void:
	if not "--no-profile-save" in OS.get_cmdline_user_args() or not "--no-upnp" in OS.get_cmdline_user_args(): quit(2);return
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	game.start_scenario(2,{"environment":"ash_foundry","build_type":"workshop","position":"left"})
	freeze()
	var legacy:=CampaignBonus.snapshot_player(game.players[0])
	legacy.erase("inventory")
	check(CampaignBonus.valid_snapshot(legacy),"Existing eight-field ammunition snapshots remain valid")
	legacy.erase("ammunition")
	check(CampaignBonus.valid_snapshot(legacy),"Existing seven-field campaign snapshots remain valid")
	for invalid: Dictionary in [{"scrap":-1},{"scrap":NAN},{"scrap":INF},{"scrap":1.5},{"scrap":10001},{"unknown":1}]:
		var candidate:=legacy.duplicate(true)
		candidate.inventory=invalid
		check(not CampaignBonus.valid_snapshot(candidate),"Snapshot validator refuses invalid personal inventory "+str(invalid))
	game.rounds.wave=20
	check(game.expedition.on_victory() and game.expedition.handle_command("prepare",{},1),"Real victory and finite garage seed a durable campaign")
	check(game.expedition.handle_command("route",{"id":"harbor"},1) and game.expedition.handle_command("stop",{"id":"harbor:salvage"},1),"Real destination with a safe roadside checkpoint is selected")
	var controller=game.expedition
	var previous: int=game.get_instance_id()
	var source_stock: Dictionary=controller._capture_stock()
	check(controller.handle_command("depart",{},1),"Actual garage begins visible boarding")
	freeze()
	var source_supply: Supply=null
	for supply in get_nodes_in_group("supplies"):
		if supply.game==game and not supply.is_queued_for_deletion() and supply.kind=="steel" and supply.amount>=2:
			source_supply=supply
			break
	check(source_supply!=null,"Finite source steel supply remains reachable during visible boarding")
	game.players[0].position=source_supply.position
	for frame in 3: await physics_frame
	source_supply.interact(game.players[0],Balance.TRANSFER_TIME)
	source_supply.interact(game.players[0],Balance.TRANSFER_TIME)
	check(game.players[0].inventory=={"steel":2} and controller._capture_stock()==source_stock,"Actual boarding-stage supply pickup conserves source stock while moving two units into hands")
	for player in game.players:
		player.position=controller.vehicle.position
		check(controller.vehicle.board(player,"driver" if player.player_id==1 else "gunner"),"Connected crew enters its real seat")
	var boarding_before: Dictionary=game.campaign.checkpoint()
	var before_launch_disk:=disk_checkpoint()
	game.campaign.save_path="user://missing-boarding-carry-%d/campaign.json" % OS.get_process_id()
	check(not controller._launch_journey(),"Unwritable boarding checkpoint refuses departure with carried source stock")
	check(game.campaign.checkpoint()==boarding_before and game.players[0].inventory=={"steel":2} and controller._capture_stock()==source_stock,"Failed boarding save preserves exact source ownership and actual picked-up hands")
	game.campaign.save_path=isolated_path
	check(disk_checkpoint()==before_launch_disk,"Failed boarding save cannot replace the finite source checkpoint")
	check(controller.handle_command("depart",{},1),"Crew can re-enter boarding after failed source save")
	for player in game.players:
		player.position=controller.vehicle.position
		controller.vehicle.board(player,"driver" if player.player_id==1 else "gunner")
	game.network.set_physics_process(false)
	game.network.active=true
	game.network.is_host=true
	game.network.state="playing"
	game.network._loading=false
	game.network._match_player_count=game.player_count+1
	check(not controller._launch_journey(),"Real refused handoff rolls back a carried-source-stock departure")
	check(game.campaign.checkpoint()==boarding_before and game.players[0].inventory=={"steel":2} and controller._capture_stock()==source_stock,"Rejected boarding handoff restores source ledger without removing or duplicating actual hands")
	game.network.active=false
	check(controller.handle_command("depart",{},1),"Crew can board again after rejected source handoff")
	for player in game.players:
		player.position=controller.vehicle.position
		controller.vehicle.board(player,"driver" if player.player_id==1 else "gunner")
	check(controller._launch_journey(),"Boarded crew commits actual road replacement")
	if not await wait_reload(previous,"travel"): await finish();return
	controller=game.expedition
	var remaining_source:=source_stock.duplicate()
	remaining_source.steel=int(remaining_source.steel)-2
	check(game.campaign.expedition.garage_stock==remaining_source and game.players[0].inventory=={"steel":2},"Road hands own their picked-up source steel separately from the remaining source ledger")
	if not await start_driving(): await finish();return
	previous=game.get_instance_id()
	check(controller.handle_command("garage",{},1),"Direct return before any stop rewinds exact finite departure supplies")
	if not await wait_reload(previous,"preparation"): await finish();return
	controller=game.expedition
	check(game.campaign.expedition.garage_stock==source_stock and controller._capture_stock()==source_stock and game.players[0].inventory.is_empty(),"Direct garage return restores original source steel exactly once with no ownership inflation")
	previous=game.get_instance_id()
	check(controller.handle_command("depart",{},1),"Exact returned warehouse supports a new finite departure")
	for player in game.players:
		player.position=controller.vehicle.position
		check(controller.vehicle.board(player,"driver" if player.player_id==1 else "gunner"),"Returned source crew boards the real vehicle")
	check(controller._launch_journey(),"Redeployment retains its exact source warehouse")
	if not await wait_reload(previous,"travel"): await finish();return
	controller=game.expedition
	check(game.campaign.expedition.garage_stock==source_stock and game.players[0].inventory.is_empty(),"Redeployment adds no second ownership of previously returned steel")
	controller.vehicle.journey_state=Journey.new_state("driving",true)
	controller.vehicle.driving_enabled=true
	controller.ambushes=int(controller.route.ambushes)
	spend_and_earn(63)
	game.upgrades.add_points(3)
	await collect_scrap(2)
	var stop_live:=live_snapshots()
	var stop_points: int=game.upgrades.points
	controller.vehicle.position.x=2100
	controller._physics_process(.02)
	await clear_guards()
	check(controller.stage=="stop","Real road reaches and clears its optional stop")
	var before: Dictionary=game.campaign.checkpoint()
	var durable:=disk_checkpoint()
	game.campaign.save_path="user://missing-personal-checkpoint-%d/campaign.json" % OS.get_process_id()
	check(not controller.handle_command("resume",{},1),"Unwritable safe checkpoint refuses the stop reward")
	check(game.campaign.checkpoint()==before and live_snapshots()==stop_live and game.upgrades.points==stop_points,"Save failure preserves old retry checkpoint and all current live ammunition and progression")
	game.campaign.save_path=isolated_path
	check(disk_checkpoint()==durable,"Failed stop save cannot replace the prior durable checkpoint")
	check(controller.handle_command("resume",{},1),"Actual stop commits crew and finite reward together")
	check(game.campaign.expedition.departure.snapshots==stop_live and game.campaign.snapshots==stop_live,"Secured stop captures exact spent ammunition and earned progression")
	check(game.campaign.expedition.departure.tech_points==stop_points,"Collected finite portable tech points join the secured retry boundary")
	await persisted_inventory_graph()
	var boundary: Dictionary=game.campaign.expedition.departure.duplicate(true)
	spend_and_earn(11)
	game.campaign.fail_journey()
	previous=game.get_instance_id()
	check(controller.handle_command("retry",{},1),"Actual road retry uses the last secured checkpoint")
	if not await wait_reload(previous,"travel"): await finish();return
	controller=game.expedition
	check(live_snapshots()==stop_live and game.upgrades.points==stop_points,"Real safe-stop retry restores exact safe ammunition and progression without later transient awards")
	check(game.players[0].inventory=={"scrap":2},"Secured-stop retry preserves recovered hands exactly once")
	var warehouse: Dictionary=game.campaign.expedition.garage_stock.duplicate()
	previous=game.get_instance_id()
	check(controller.handle_command("garage",{},1),"Safe-stop rewind can return its collected hands to the source garage")
	if not await wait_reload(previous,"preparation"): await finish();return
	controller=game.expedition
	warehouse.scrap=int(warehouse.get("scrap",0))+2
	check(game.campaign.expedition.garage_stock==warehouse and game.players[0].inventory.is_empty(),"Returned safe hands transfer once into the finite source warehouse")
	check(game.campaign.snapshots["1"].inventory.is_empty(),"Warehouse-owned returned hands cannot also remain in the personal save snapshot")
	controller._mirror_stock()
	check(controller._capture_stock()==warehouse,"Repeated garage mirroring cannot duplicate returned hand material")
	previous=game.get_instance_id()
	check(controller.handle_command("depart",{},1),"Returned crew can depart again using its same finite supplies")
	for player in game.players:
		player.position=controller.vehicle.position
		check(controller.vehicle.board(player,"driver" if player.player_id==1 else "gunner"),"Returned crew reboards actual seats")
	check(controller._launch_journey(),"Redeployment commits no additional hand or warehouse grant")
	if not await wait_reload(previous,"travel"): await finish();return
	controller=game.expedition
	boundary=game.campaign.expedition.departure.duplicate(true)
	check(game.players[0].inventory.is_empty() and game.campaign.expedition.garage_stock==warehouse,"Redeployment preserves garage ownership and does not refill personal hands")
	controller.vehicle.journey_state=Journey.new_state("driving",true)
	controller.vehicle.driving_enabled=true
	controller.ambushes=int(controller.route.ambushes)
	spend_and_earn(21)
	game.upgrades.add_points(2)
	await collect_scrap(2)
	var collector=game.players[0]
	var carried: Dictionary=collector.inventory.duplicate()
	var arrival_live:=live_snapshots()
	var arrival_points: int=game.upgrades.points
	controller.vehicle.position.x=controller.ROAD_END
	var travel_before: Dictionary=game.campaign.checkpoint()
	durable=disk_checkpoint()
	game.campaign.save_path="user://missing-arrival-checkpoint-%d/campaign.json" % OS.get_process_id()
	controller._physics_process(.02)
	check(game.campaign.checkpoint()==travel_before and live_snapshots()==arrival_live and not controller.transitioning,"Arrival save failure preserves checkpoint and all actual finite crew supplies")
	game.campaign.save_path=isolated_path
	check(disk_checkpoint()==durable,"Unwritable arrival cannot replace the previous durable safe boundary")
	game.network.set_physics_process(false)
	game.network.active=true
	game.network.is_host=true
	game.network.state="playing"
	game.network._loading=false
	game.network._match_player_count=game.player_count+1
	controller._physics_process(.02)
	check(game.campaign.checkpoint()==travel_before and live_snapshots()==arrival_live and collector.inventory==carried,"Rejected real arrival rolls back durable metadata while preserving actual carried material and spent rounds")
	check(not controller.transitioning and controller.vehicle.driving_enabled,"Refused handoff leaves current road playable")
	game.network.active=false
	previous=game.get_instance_id()
	controller._physics_process(.02)
	if not await wait_reload(previous,"occupation"): await finish();return
	check(live_snapshots()==arrival_live and game.upgrades.points==arrival_points,"Actual destination replacement preserves exact road ammunition, progression and portable points")
	check(game.players[0].inventory==carried,"Actual destination replacement preserves collected material instead of clearing hands")
	check(game.campaign.expedition.departure==boundary,"Arrival preserves the intended secured-stop rewind boundary")
	controller=game.expedition
	spend_and_earn(17)
	game.upgrades.add_points(2)
	await clear_guards()
	var defense_live:=live_snapshots()
	var defense_points: int=game.upgrades.points
	var occupation_before: Dictionary=game.campaign.checkpoint()
	durable=disk_checkpoint()
	game.campaign.save_path="user://missing-defense-checkpoint-%d/campaign.json" % OS.get_process_id()
	controller._secure_bunker()
	check(controller.stage=="occupation" and game.campaign.checkpoint()==occupation_before and live_snapshots()==defense_live,"Failed destination save preserves live occupation rounds, progress, hands and retry metadata")
	game.campaign.save_path=isolated_path
	check(disk_checkpoint()==durable,"Unwritable defense boundary leaves the previous durable occupation intact")
	controller._secure_bunker()
	check(controller.stage=="defense" and game.campaign.snapshots==defense_live and game.campaign.expedition.tech_points==defense_points,"Secured destination commits actual occupation spend and progression into the defense retry")
	freeze()
	var deployment: Dictionary=game.campaign.expedition.deployment_cargo.duplicate()
	var physical: Dictionary=controller._capture_stock()
	# The retry checkpoint owns collected hands and the truck's delivery.
	# Uncollected guard drops belong to the encounter, which the retry resets.
	for pickup in get_nodes_in_group("pickups"):
		if pickup.game!=game or pickup.is_queued_for_deletion() or not pickup.kind in CampaignCatalog.CARGO_KINDS: continue
		physical[pickup.kind]=int(physical.get(pickup.kind,0))-int(pickup.amount)
		if int(physical[pickup.kind])==0: physical.erase(pickup.kind)
	spend_and_earn(9)
	previous=game.get_instance_id()
	check(controller.retry_defense(),"Actual defended-site retry replaces the scene from its secure deployment")
	if not await wait_reload(previous,"defense"): await finish();return
	check(live_snapshots()==defense_live and game.upgrades.points==defense_points,"Defense retry restores exact secure occupation supplies and progress rather than later transient spend")
	check(game.players[0].inventory==carried and game.campaign.expedition.deployment_cargo==deployment and game.expedition._capture_stock()==physical,"Defense retry retains personal material separately from finite vehicle delivery with no duplicate resources")
	await finish()

func finish() -> void:
	paused=false
	if is_instance_valid(game): await Cleanup.free_scene(game,self)
	for suffix: String in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(isolated_path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(isolated_path+suffix))
	print("CONVOY PERSONAL CHECKPOINT CHECKS: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
