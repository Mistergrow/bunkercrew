extends SceneTree
## Exact JSON-limit checkpoint, reachable crates and finite reserve access.
const Storage = preload("res://scripts/medic_storage.gd")
const Schema = preload("res://scripts/network_replication_schema.gd")
const World = preload("res://scripts/network_world.gd")
const Cleanup = preload("res://tests/scene_cleanup.gd")
var game
var checks := 0
var failures := 0
var path := "res://artifacts/gameplay-hardening/warehouse-%d.json" % OS.get_process_id()

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	print("WAREHOUSE ","PASS " if ok else "FAIL ",label)
	if not ok: failures+=1; push_error(label)
func stores(owner = null) -> Array:
	var arena = game if owner == null else owner
	return get_nodes_in_group("supplies").filter(func(crate): return crate.game == arena and not crate.is_queued_for_deletion())
func freeze() -> void:
	game.rounds.running=false
	game.rounds.set_process(false)
	game.expedition.set_physics_process(false)
	game.medic.set_physics_process(false)
	for player in game.players: player.set_physics_process(false)
	for station in get_nodes_in_group("stations"):
		if station.game==game: station.set_process(false)
	paused=true
func clean_files() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
func run():
	if not "--no-profile-save" in OS.get_cmdline_user_args() or not "--no-upnp" in OS.get_cmdline_user_args(): quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/gameplay-hardening"))
	clean_files()
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	game.start_scenario(1,{"environment":"ash_foundry","position":"right","build_type":"bastion"})
	freeze()
	for index in 3: await physics_frame
	game.rounds.wave=Balance.TOTAL_WAVES
	check(game.expedition.on_victory(),"A real verified victory prepares a valid warehouse campaign")
	var maximum: Dictionary={}
	for kind: String in Storage.MATERIALS: maximum[kind]=CampaignState.MAX_STOCK_PER_KIND
	game.campaign.expedition.garage_stock=maximum.duplicate()
	check(CampaignState.valid_checkpoint(game.campaign.checkpoint()),"Ten materials at the exact JSON integer limit are a valid bounded checkpoint")
	var host_world:=World.new()
	host_world.bind(game)
	game.expedition._mirror_stock()
	var depot_count: int=stores().size()
	check(depot_count>=10 and depot_count<100,"Maximum stock uses available physical slots instead of forcing 100 overlapping chests")
	check(not Storage.reserved(game).is_empty() and Storage.reserved(game).size()<=Storage.MATERIALS.size(),"The finite overflow remains in a bounded material reserve")
	check(game.expedition._capture_stock()==maximum,"Physical containers plus reserve preserve every exact maximum stock amount once")
	var positions: Array[Vector2]=[]
	for crate in stores():
		check(crate.amount>0 and crate.amount<=Balance.PICKUP_STACK_MAX and Schema.valid_state(Schema.kind(crate),host_world._capture_fields(crate,Schema.fields(Schema.kind(crate)))),crate.kind+": physical storage is nonempty and individually valid on the network")
		check(crate.position.x>=game.world_left+24 and crate.position.x<=game.world_right-24 and game.medic.navigation.support_at(crate.position) and game.medic.navigation.body_clear(crate.position),crate.kind+": storage has a supported free floor inside the playable arena")
		check(positions.all(func(point): return absf(point.y-crate.position.y)>=45 or absf(point.x-crate.position.x)>=58),crate.kind+": storage does not overlap another chest")
		check(not game.medic.navigation.route_to(crate).is_empty(),crate.kind+": SAN-1 can reach the physical storage")
		positions.append(crate.position)
	var player=game.players[0]
	for kind: String in Storage.MATERIALS:
		var choices: Array=stores().filter(func(fixture_crate): return fixture_crate.kind==kind)
		check(not choices.is_empty(),kind+": overflow cannot consume the slot needed for this material's own chest")
		if choices.is_empty(): continue
		var crate: Supply=choices[0]
		player.position=crate.position+Vector2(-28,0)
		player.inventory.clear()
		player.selected_kind=kind
		crate.interact(player,Balance.TRANSFER_TIME)
		check(player.inventory.get(kind,0)==1 and game.expedition._capture_stock()==maximum,kind+": ordinary player interaction accesses one finite unit without changing total ownership")
		crate.deposit(player,Balance.TRANSFER_TIME)
		check(player.inventory.is_empty() and game.expedition._capture_stock()==maximum and Storage.stored_amount(game,kind)==CampaignState.MAX_STOCK_PER_KIND,kind+": a returned unit fits in warehouse storage even if its visible chest was refilled")
		if Storage.reserve_amount(game,kind)>0: check(crate.prompt(player).contains("Lagerreserve"),kind+": focused storage explains its finite reserve")
	player.inventory={"steel":1,"glass":1}
	player.selected_kind="steel"
	var full_steel: Supply=stores().filter(func(crate): return crate.kind=="steel")[0]
	player.position=full_steel.position+Vector2(-28,0)
	var pool_before: Dictionary=Storage.reserved(game)
	full_steel.deposit(player,Balance.TRANSFER_TIME)
	check(player.inventory=={"steel":1,"glass":1} and Storage.reserved(game)==pool_before,"An aggregate-full warehouse rejects excess mixed cargo before debiting it")
	player.inventory.clear()
	# Normal SAN-1 pickup must refill the actual source, then permit a physical
	# return when the machine disappears. No abandoned cargo or resource grant.
	var source: Supply
	var station: ProductionStation
	for candidate in stores():
		if candidate.kind in ["sand","ore"] and Storage.reserve_amount(game,candidate.kind)>0: source=candidate; break
	for candidate in get_nodes_in_group("stations"):
		if candidate.game==game and is_instance_valid(source) and candidate.input_kind()==source.kind: station=candidate
	check(is_instance_valid(source) and is_instance_valid(station),"Maximum fixture includes a reserved real ingredient and its real machine")
	if is_instance_valid(source) and is_instance_valid(station):
		game.upgrades.owned={"bunker_workshop":true,"medic_logistics":true}
		var medic=game.medic
		medic.position=source.position+Vector2(-28,0)
		medic.velocity=Vector2.ZERO
		medic.climbing=false
		medic.logistics.source=source
		medic.logistics.station=station
		medic.logistics._resource=source.kind
		medic.logistics_phase="collect"
		var reserve_before: int=Storage.reserve_amount(game,source.kind)
		medic.logistics._handoff(source)
		check(medic.logistics_cargo==source.kind and source.amount==Balance.PICKUP_STACK_MAX and Storage.reserve_amount(game,source.kind)==reserve_before-1 and game.expedition._capture_stock()==maximum,"SAN-1's real debit replenishes its physical source from exactly one finite reserve unit")
		game.remove_child(station)
		medic.logistics_phase="return"
		medic.logistics._handoff(source)
		check(medic.logistics_cargo.is_empty() and Storage.reserve_amount(game,source.kind)==reserve_before and game.expedition._capture_stock()==maximum,"Removed machine returns SAN-1 cargo into the bounded warehouse without a full-crate deadlock")
		# Fixed machines must exist on both ends of the separately tested world
		# snapshot. Restore this fixture after exercising its genuine absence.
		game.add_child(station)
		medic.position=medic._home()
	var checkpoint_before: Dictionary=game.campaign.checkpoint()
	for repeat in 3:
		game.expedition._mirror_stock()
		check(stores().size()==depot_count and game.expedition._capture_stock()==maximum,"Repeated maximal mirror preserves reserve and chest count, pass %d" % repeat)
	game.campaign.save_path=path
	game.campaign.persistence_enabled=true
	check(game.campaign.save_checkpoint(),"Maximal warehouse stock is saved only into the isolated test file")
	var reader:=CampaignState.new(path,false)
	reader.persistence_enabled=true
	check(reader.load_checkpoint() and reader.expedition.garage_stock.size()==10 and reader.expedition.garage_stock.values().all(func(amount): return int(amount)==CampaignState.MAX_STOCK_PER_KIND),"Isolated disk reload keeps every reserve-backed material total")
	var snapshot: Dictionary=host_world.capture()
	var guest=load("res://scenes/main.tscn").instantiate()
	root.add_child(guest)
	guest.network.set_physics_process(false)
	guest.network.active=true
	guest.network.is_host=false
	guest.start_scenario(1,game.scenario_options)
	paused=true
	var guest_world:=World.new()
	guest_world.bind(guest)
	check(guest_world.apply(snapshot),"Existing host snapshot applies the maximal reserve-backed warehouse without a new protocol: "+guest_world.last_error)
	check(guest.expedition._capture_stock()==maximum and stores(guest).size()==depot_count and Storage.reserved(guest).is_empty(),"Guest derives the complete reserve from the existing ledger without owning authoritative reserve quantities")
	check(guest_world.apply(snapshot) and guest.expedition._capture_stock()==maximum,"Repeated maximal snapshot cannot duplicate resources or containers")
	var first_reserve: String=Storage.reserved(game).keys()[0]
	var guest_crate: Supply=stores(guest).filter(func(crate): return crate.kind==first_reserve)[0]
	check(guest_crate.prompt(guest.players[0]).contains("Lagerreserve"),"Guest storage explains its synchronized reserve in the ordinary tooltip")
	var guest_amount: int=guest_crate.amount
	Storage.refill(guest_crate)
	check(guest_crate.amount==guest_amount and Storage.reserved(guest).is_empty(),"Guest cannot debit or independently replenish authoritative reserve material")
	paused=false
	await Cleanup.free_scene(guest,self)
	guest_world=null
	host_world=null
	game.campaign.persistence_enabled=false
	game.started=false
	game.start_scenario(1,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	freeze()
	check(Storage.reserved(game).is_empty() and not game.has_meta(Storage.RESERVE_ACTIVE_META),"Same Game scenario replacement clears both old reserve quantities and activation")
	var restored: Dictionary=checkpoint_before.duplicate(true)
	restored.options.position="left"
	game.started=false
	check(game.expedition.restore({"checkpoint":restored,"mode":"preparation","options":restored.options}),"Real preparation restore reconstructs reserve-backed stock after clearing the former world")
	freeze()
	check(game.expedition._capture_stock()==maximum and stores().size()<100,"Fresh physical world plus restored reserve contains the full maximum exactly once")
	paused=false
	await Cleanup.free_scene(game,self)
	clean_files()
	print("WAREHOUSE RESERVE CHECKS: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
