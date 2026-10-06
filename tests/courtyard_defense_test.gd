extends SceneTree
## Real main scenes and existing physical gates. Layout fixtures disable waves;
## the breach uses unmodified enemy attack rays and actual wall damage.
const Cleanup=preload("res://tests/scene_cleanup.gd")
const World=preload("res://scripts/network_world.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool,label: String) -> void:
	checks+=1
	print("COURTYARD %s: %s"%["PASS" if value else "FAIL",label])
	if not value:
		failures+=1
		push_error(label)

func scene(environment_id: String,mode: String,classic: bool=false) -> Node:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.combat_events.persistence_enabled=false
	if classic: game.start(1)
	else: game.start_scenario(1,{"environment":environment_id,"position":mode,"build_type":"workshop"})
	game.rounds.running=false
	game.rounds.set_process(false)
	game.medic.set_physics_process(false)
	for player in game.players: player.set_physics_process(false)
	for site in game.perimeter.sites: site.set_physics_process(false)
	return game

func fence_for(game: Node,side: int) -> Node:
	return game.perimeter.sites.filter(func(site):return site.role=="fence" and site.side==side)[0]

func inspect_layout(game: Node,label: String,front_count: int) -> void:
	var controller: Node=game.perimeter
	check(controller.sites.size()==front_count*3,label+" keeps exactly three stable sites per active approach")
	check(controller.sites.filter(func(site):return site.role=="fence").all(func(site):return site.tier==1 and site.hp==120 and site.max_hp==120 and site.builder_player_id==0 and site.materials.is_empty() and site.ammo==0 and site.collision_layer==3),label+" starts with real catalog mesh HP and no cargo or construction credit")
	check(controller.sites.filter(func(site):return site.role=="ground").all(func(site):return site.tier==0 and site.hp==0 and site.ammo==0),label+" keeps both paid sentries unbuilt")
	check(controller.sites.all(func(site):return controller.layout.field_position_allowed(site.position.x,44) and site.position.y==430),label+" positions the courtyard defenses on existing reachable ground")
	check(game.players[0].progression.xp==0 and game.players[0].inventory.is_empty(),label+" infrastructure gives no starting inventory or XP")
	var initial_sites: Array=controller.sites.duplicate()
	controller.bootstrap(game)
	check(controller.sites==initial_sites,label+" repeated bootstrap never creates duplicate gates")

func breach_front(game: Node,side: int) -> void:
	var fence: Node=fence_for(game,side)
	var enemy=game._entity("enemy",fence.position+Vector2(side*130,0),{"kind":"strider","wave":1,"attack_direction":-float(side)})
	enemy.set_physics_process(false)
	check(enemy.nearest_obstacle()==fence,"Ground AI on front %d selects the installed outer fence first"%side)
	enemy.position=fence.position+Vector2(side*enemy.attack_reach,0)
	enemy.target=fence
	await physics_frame
	var hp_before: float=fence.hp
	var core_before: float=game.core.hp
	var inner: Array=get_nodes_in_group("walls").filter(func(wall):return wall.get("game")==game and wall is DefenseWall and wall.is_blocking())
	var inner_hp: Array=inner.map(func(wall):return wall.hp)
	check(enemy.attack_obstacle() and fence.hp<hp_before,"Actual enemy contact ray damages front %d mesh"%side)
	for strike in 40:
		if not fence.is_blocking(): break
		enemy.attack_obstacle()
	check(fence.tier==0 and fence.ruined and fence.hp==0 and fence.collision_layer==0,"Real attacks breach front %d and remove its physical collision"%side)
	check(game.core.hp==core_before and inner.map(func(wall):return wall.hp)==inner_hp,"Outer breach does not also damage inner bunker defenses")
	var next_target: Node=enemy.nearest_obstacle()
	check(next_target is DefenseWall and next_target.is_blocking(),"After front %d is breached AI must attack an intact inner bunker wall"%side)
	var sites_before: int=game.perimeter.sites.size()
	game.perimeter.bootstrap(game)
	check(fence.tier==0 and fence.ruined and game.perimeter.sites.size()==sites_before,"Bootstrap never repairs or resurrects a breached front")
	game.players[0].position=fence.position
	game.players[0].inventory.clear()
	for action in 30: fence.interact(game.players[0],.1)
	check(fence.tier==0 and fence.materials.is_empty(),"A destroyed starter requires real payment for reconstruction")
	enemy.queue_free()
	await process_frame

func snapshot_restore() -> void:
	var host:=scene("sector07","center")
	var authority:=World.new()
	authority.bind(host)
	var west: Node=fence_for(host,-1)
	var east: Node=fence_for(host,1)
	west.take_damage(37)
	east.take_damage(10000)
	var snapshot: Dictionary=authority.capture()
	check(authority._validate(snapshot),"Catalog damage and destroyed starter states validate without wire changes")
	var builder: Node=host.players[0]
	builder.position=west.position-Vector2(35,0)
	builder.inventory={"steel":1}
	for action in 10: west.interact(builder,.1)
	host.rounds.wave=11
	host.upgrades.owned.bunker_armor=true
	for target_tier in [2,3]:
		builder.inventory=west.next_spec().cost.duplicate()
		for action in 80:
			if west.tier>=target_tier: break
			west.interact(builder,.1)
		if west.cure>0: west._physics_process(8)
	builder.position=host.core.position
	west._physics_process(1)
	west.take_damage(37)
	var upgraded: Dictionary=authority.capture()
	check(west.tier==3 and west.hp==583 and builder.inventory.values().all(func(value):return int(value)==0) and authority._validate(upgraded),"Paid repaired, cured and upgraded fence yields a valid existing-schema snapshot")
	check(await Cleanup.free_scene(host,self),"Authoritative snapshot fixture releases")
	var guest:=scene("sector07","center")
	var replica:=World.new()
	replica.bind(guest)
	guest.network.world=replica
	check(replica.apply(snapshot),"Fresh guest starter accepts authoritative existing defense state: "+replica.last_error)
	check(fence_for(guest,-1).hp==83 and fence_for(guest,1).tier==0 and fence_for(guest,1).ruined and fence_for(guest,1).collision_layer==0,"Reconnect never resets damage or a destroyed fence to its new-round defaults")
	var unbuilt:=snapshot.duplicate(true)
	for record: Dictionary in unbuilt.entities:
		if record.type=="perimeter_site" and record.state.role=="fence" and record.state.side==1:
			record.state.ruined=false
			record.state.materials={"steel":1}
	check(replica.apply(unbuilt),"Old unbuilt paid-deposit state still applies to the same fixed gate identity")
	check(fence_for(guest,1).tier==0 and not fence_for(guest,1).ruined and fence_for(guest,1).materials=={"steel":1},"Unbuilt snapshot retains its finite previously deposited material")
	guest.perimeter.bootstrap(guest)
	check(fence_for(guest,1).tier==0 and fence_for(guest,1).materials=={"steel":1},"An already restored controller never grants another starter")
	check(replica.apply(upgraded),"Existing tier-3 authoritative defense state applies over a new-round starter")
	check(fence_for(guest,-1).tier==3 and fence_for(guest,-1).hp==583 and fence_for(guest,-1).max_hp==620 and fence_for(guest,-1).builder_player_id==1,"Previously paid upgrade, damage and builder ownership remain authoritative")
	check(await Cleanup.free_scene(guest,self),"Guest snapshot fixture releases")

func road_retirement() -> void:
	var game:=scene("sector07","center")
	var fence: Node=fence_for(game,1)
	var gun: Node=game.perimeter.sites.filter(func(site):return site.role=="ground" and site.side==1)[0]
	var builder: Node=game.players[0]
	game.rounds.wave=20
	game.upgrades.owned.perimeter_automation=true
	builder.position=gun.position-Vector2(35,0)
	builder.inventory=gun.next_spec().cost.duplicate()
	for action in 60: gun.interact(builder,.1)
	builder.inventory={"ammo":1}
	for action in 12: gun.interact(builder,.1)
	check(gun.tier==1 and gun.ammo==20,"Road fixture owns one real paid, supplied sentry beside its starter fence")
	check(game.expedition.on_victory() and game.campaign.select_destination("harbor"),"Prepared wave20 boundary opens the actual first campaign route")
	var departure: Dictionary=game.campaign.begin_journey()
	check(not departure.is_empty(),"Actual departure commits valid finite crew and vehicle ownership")
	game.expedition.set_physics_process(false)
	game.expedition.route=CampaignCatalog.journey("harbor")
	game.expedition._start_road()
	paused=false
	check(game.expedition.road_open and not game.perimeter.visible and game.perimeter.sites.all(func(site):return not site.is_visible_in_tree() and not site.is_physics_processing() and not site.is_blocking() and not site.can_be_targeted() and site.collision_layer==0),"Actual road transition retires every old courtyard drawing, site clock and collider")
	check(gun.head_hurtbox.collision_layer==0 and not fence.can_interact(builder) and fence.action_for(builder).is_empty(),"Retired sentry hurtbox and old courtyard interaction cannot affect the road")
	var retained: Array=[fence.hp,fence.tier,gun.hp,gun.ammo,gun.shot_serial]
	for site: Node in game.perimeter.sites:
		site._physics_process(1)
		site.take_damage(100)
		site.interact(builder,.2)
		site.sync_replica()
	check(retained==[fence.hp,fence.tier,gun.hp,gun.ammo,gun.shot_serial] and not gun.fire() and game.perimeter.sites.all(func(site):return site.collision_layer==0),"Late simulation, damage and replica synchronization cannot resurrect old road cover or spend its ammunition")
	var truck: Node=game.expedition.vehicle
	truck.set_physics_process(false)
	truck.journey_state=ConvoyJourney.new_state("driving",true)
	truck.driving_enabled=true
	truck.position=Vector2(fence.position.x-200,430)
	var initial_x: float=truck.position.x
	for step in 240:
		await physics_frame
		truck.advance_motion(1.0/60.0,1.0)
		for seat: Node in truck.seats: seat.sync_operator()
		if truck.position.x>fence.position.x+140: break
	check(truck.position.x>fence.position.x+140 and truck.position.x-initial_x>340,"Actual convoy physics drives through the old closed-fence location without invisible obstruction")
	var authority:=World.new()
	authority.bind(game)
	var snapshot: Dictionary=authority.capture()
	check(authority._validate(snapshot),"Retired fixed defenses remain valid persistent road records: "+authority.last_error)
	check(await Cleanup.free_scene(game,self),"Authoritative road fixture releases")
	var guest:=scene("sector07","center")
	guest.expedition.set_physics_process(false)
	guest.expedition.ensure_road()
	var replica:=World.new()
	replica.bind(guest)
	guest.network.world=replica
	check(replica.apply(snapshot),"Actual road snapshot applies to a replica with the same retired fixed sites: "+replica.last_error)
	for site: Node in guest.perimeter.sites: site.sync_replica()
	check(not guest.perimeter.visible and guest.perimeter.sites.all(func(site):return site.collision_layer==0 and not site.can_be_targeted()) and fence_for(guest,1).hp==retained[0],"Snapshot restoration preserves site durability while keeping source courtyard collision and drawing inactive")
	check(await Cleanup.free_scene(guest,self),"Guest road fixture releases")

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	for entry: Dictionary in ScenarioCatalog.environments(true):
		for mode: String in ["left","center","right"]:
			var game:=scene(str(entry.id),mode)
			inspect_layout(game,str(entry.id)+"/"+mode,2 if mode=="center" else 1)
			check(await Cleanup.free_scene(game,self),str(entry.id)+"/"+mode+" closes its fixture")
	var classic:=scene("sector07","left",true)
	inspect_layout(classic,"classic",1)
	check(classic.scenario_combat==null and classic.perimeter.layout!=null,"Classic courtyard leaves original spawn and air rules intact")
	await breach_front(classic,1)
	check(await Cleanup.free_scene(classic,self),"Classic breach fixture releases")
	var center:=scene("sector07","center")
	await breach_front(center,-1)
	await breach_front(center,1)
	check(await Cleanup.free_scene(center,self),"Two-front physical breach fixture releases")
	await snapshot_restore()
	await road_retirement()
	print("COURTYARD DEFENSE: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
