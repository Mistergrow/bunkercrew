extends SceneTree
## Real finite inventory, recipe buffers, victory commits and deployment stores.
const Cleanup = preload("res://tests/scene_cleanup.gd")
const Schema = preload("res://scripts/network_replication_schema.gd")
const World = preload("res://scripts/network_world.gd")
const CargoCrate = preload("res://scripts/convoy_supply.gd")
var game
var checks := 0
var failures := 0
var save_path := "res://artifacts/gameplay-hardening/ledger-%d.json" % OS.get_process_id()

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("LEDGER ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1
		push_error(label)

func stores(kind := "") -> Array:
	return get_nodes_in_group("supplies").filter(func(crate): return crate.game == game and not crate.is_queued_for_deletion() and (kind.is_empty() or crate.kind == kind))

func total(kind: String) -> int:
	var result := 0
	for crate in stores(kind): result += crate.amount
	return result

func add_crate(kind: String, amount: int, position: Vector2) -> Supply:
	var crate := CargoCrate.new()
	crate.game = game
	crate.kind = kind
	crate.amount = amount
	crate.position = position
	game.add_child(crate)
	crate.set_physics_process(false)
	return crate

func add_recipe(kind: String, position: Vector2) -> RecipeStation:
	var station := RecipeStation.new()
	station.game = game
	station.kind = kind
	station.position = position
	game.add_child(station)
	station.set_process(false)
	return station

func machine_state(station: ProductionStation) -> Dictionary:
	return {"input":station.input_amount, "output":station.output_amount, "working":station.working, "time":station.production_time, "binder":station.binder, "ingredients":station.ingredient_amounts.duplicate() if station is RecipeStation else {}, "donors":station.batch_donors.duplicate(), "transfer":station.transfer.duplicate()}

func clean_files() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(save_path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path+suffix))

func restored_storage_probe(preparation: Dictionary):
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	var stock := {"sand":20001, "limestone":1, "tungsten":1, "alloy":2, "glass":2, "scrap":1, "ore":0, "steel":0, "concrete":0, "ammo":0}
	var checkpoint: Dictionary=preparation.duplicate(true)
	checkpoint.options.position="right"
	checkpoint.expedition.garage_stock=stock.duplicate()
	check(game.expedition.restore({"checkpoint":checkpoint, "mode":"preparation", "options":checkpoint.options}), "Actual preparation restore constructs and mirrors a new right-side scenario immediately")
	game.rounds.set_process(false)
	game.rounds.running = false
	game.expedition.set_physics_process(false)
	game.medic.set_physics_process(false)
	for worker in game.players: worker.set_physics_process(false)
	for station in get_nodes_in_group("stations"): station.set_process(false)
	for index in 3: await physics_frame
	paused = true
	check(game.expedition._capture_stock() == stock and stores("sand").size() == 3, "Restore splits 20001 sand into three real containers and preserves every rare material")
	for crate in stores().filter(func(candidate): return Schema.kind(candidate) == "convoy_supply"):
		check(crate.position.x >= game.world_left+24 and crate.position.x <= game.world_right-24 and game.medic.navigation.support_at(crate.position) and game.medic.navigation.body_clear(crate.position), "Restored "+crate.kind+" crate has real support inside the playable world")
		check(not game.medic.navigation.route_to(crate).is_empty(), "SAN-1 can physically reach the restored "+crate.kind+" storage")
		check(game.ladders.all(func(ladder): return not ladder.grow(22).has_point(crate.position)), "Restored "+crate.kind+" storage keeps ladder passages clear")
	var count_before: int=stores().size()
	game.expedition._mirror_stock()
	check(game.expedition._capture_stock() == stock and stores().size() == count_before, "Repeated restoration neither spawns duplicate crates nor loses overflow")
	var host_world := World.new()
	host_world.bind(game)
	var snapshot: Dictionary=host_world.capture()
	var guest = load("res://scenes/main.tscn").instantiate()
	root.add_child(guest)
	guest.network.set_physics_process(false)
	guest.network.active=true
	guest.network.is_host=false
	guest.start_scenario(1,checkpoint.options)
	paused=true
	var guest_world := World.new()
	guest_world.bind(guest)
	check(guest_world.apply(snapshot), "Real guest accepts a full host snapshot with split aggregate stores: "+guest_world.last_error)
	check(guest.expedition._capture_stock() == stock and get_nodes_in_group("supplies").filter(func(crate): return crate.game == guest and not crate.is_queued_for_deletion()).size() == count_before, "Guest reconstructs every finite material and all split physical containers")
	check(guest_world.apply(snapshot) and guest.expedition._capture_stock() == stock, "Repeating the aggregate host snapshot preserves resources without creating additional storage")
	paused=false
	await Cleanup.free_scene(guest,self)
	host_world=null
	guest_world=null
	paused = false
	await Cleanup.free_scene(game,self)

func run():
	if not "--no-profile-save" in OS.get_cmdline_user_args() or not "--no-upnp" in OS.get_cmdline_user_args():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/gameplay-hardening"))
	clean_files()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start_scenario(1, {"environment":"ash_foundry", "position":"left", "build_type":"bastion"})
	game.rounds.set_process(false)
	game.rounds.running = false
	game.expedition.set_physics_process(false)
	game.medic.set_physics_process(false)
	for worker in game.players: worker.set_physics_process(false)
	for crate in stores(): crate.set_physics_process(false)
	var mixer: ProductionStation
	var furnace: ProductionStation
	for station in get_nodes_in_group("stations"):
		station.set_process(false)
		if station.kind == "mixer": mixer = station
		if station.kind == "furnace": furnace = station
	for index in 3: await physics_frame
	paused = true
	var player = game.players[0]
	var steel: Supply = stores("steel")[0]
	var steel_start: int = steel.amount
	player.position = steel.position + Vector2(-28, 0)
	player.inventory = {"steel":2, "glass":1}
	player.selected_kind = "steel"
	steel.amount = Balance.PICKUP_STACK_MAX
	steel.deposit_transfer[player.player_id] = 0.2
	steel.deposit(player, Balance.TRANSFER_TIME)
	check(steel.amount == Balance.PICKUP_STACK_MAX and player.inventory == {"steel":2, "glass":1}, "A full physical crate rejects a player deposit before debiting mixed cargo")
	check(not steel.deposit_transfer.has(player.player_id), "Full storage clears stale deposit progress")
	steel.amount = Balance.PICKUP_STACK_MAX-1
	steel.deposit(player, Balance.TRANSFER_TIME)
	check(steel.amount == Balance.PICKUP_STACK_MAX and player.inventory == {"steel":1, "glass":1}, "The last free storage slot accepts exactly one matching unit")
	steel.deposit(player, Balance.TRANSFER_TIME)
	check(steel.amount == Balance.PICKUP_STACK_MAX and player.inventory == {"steel":1, "glass":1}, "Holding the deposit control cannot overfill the now-full crate")
	steel.interact(player, Balance.TRANSFER_TIME)
	check(steel.amount == Balance.PICKUP_STACK_MAX-1 and player.inventory == {"steel":2, "glass":1}, "A full crate still permits explicit withdrawal without changing other cargo")
	var snapshotter := World.new()
	snapshotter.game = game
	check(Schema.valid_state("supply", snapshotter._capture_fields(steel, Schema.fields("supply"))), "Player storage remains inside the actual network amount contract")
	steel.amount = steel_start
	player.inventory.clear()
	var sand: Supply = stores("sand")[0]
	sand.amount = Balance.PICKUP_STACK_MAX
	var second_sand := add_crate("sand", Balance.PICKUP_STACK_MAX, Vector2(840,430))
	var limestone := add_crate("limestone", 1, Vector2(910,430))
	var tungsten := add_crate("tungsten", 1, Vector2(980,430))
	var glass := add_recipe("glass", Vector2(530,430))
	var alloy := add_recipe("alloy", Vector2(470,430))
	var ore: Supply = stores("ore")[0]
	# These finite inputs leave physical crates before entering the real recipe API.
	sand.amount -= 4
	mixer.input_amount = 2
	mixer._process(0.0)
	mixer.production_time = 0.75
	glass.set_amount("sand", 2)
	glass.set_amount("limestone", 1)
	limestone.amount -= 1
	glass._process(0.0)
	glass.production_time = 1.25
	ore.amount -= 2
	furnace.input_amount = 2
	furnace._process(0.0)
	furnace._process(furnace.duration())
	alloy.set_amount("tungsten", 1)
	alloy.set_amount("steel", 1)
	tungsten.amount -= 1
	steel.amount -= 1
	sand.amount -= 1
	player.inventory = {"sand":1, "jaw_trap":1}
	second_sand.amount -= 1
	game.medic.logistics_cargo = "sand"
	game.medic.logistics_phase = "deliver"
	var removed := add_crate("sand", 7, Vector2(1050,430))
	removed.queue_free()
	var controller = game.expedition
	var expected: Dictionary = {"sand":20000, "ore":10, "steel":10, "concrete":8, "ammo":18, "limestone":1, "tungsten":1}
	check(mixer.working and glass.working and furnace.output_amount == 2 and not alloy.working, "Fixture uses two real in-flight batches, completed steel and separate incomplete alloy ingredients")
	check(controller._capture_stock() == expected, "Read-only campaign capture includes machine buffers, in-flight inputs, finished products and finite carried units, excluding removed crates")
	check(CampaignState.valid_stock(expected), "Two legal full crates are a valid aggregate campaign stock")
	var machines := [mixer, furnace, glass, alloy]
	var machine_before: Array = machines.map(func(station): return machine_state(station))
	var binder_before: int = mixer.binder
	for repeat in 3:
		check(controller._capture_stock() == expected and machines.map(func(station): return machine_state(station)) == machine_before, "Repeated stock capture leaves every machine transaction untouched, pass %d" % repeat)
	var campaign: CampaignState = game.campaign
	campaign.persistence_enabled = true
	campaign.save_path = "res://artifacts/gameplay-hardening/missing-%d/never-created/save.json" % OS.get_process_id()
	game.rounds.wave = Balance.TOTAL_WAVES
	var campaign_before: Dictionary = campaign.checkpoint()
	check(not controller.on_victory(), "A failed durable commit rejects victory with finite machine stock")
	check(campaign.checkpoint() == campaign_before and machines.map(func(station): return machine_state(station)) == machine_before and controller._capture_stock() == expected and game.medic.logistics_cargo == "sand", "Failed persistence preserves all ingredient ownership, working progress, cargo and campaign state")
	campaign.save_path = save_path
	check(controller.on_victory(), "Verified victory commits two full legal crates and machine cargo through the real campaign callback")
	check(campaign.expedition.garage_stock == expected and CampaignState.valid_checkpoint(campaign.checkpoint()), "Durable garage stock preserves every finite resource in a valid checkpoint")
	check(controller._capture_stock() == expected and player.inventory == {"jaw_trap":1} and game.medic.logistics_cargo.is_empty(), "Successful mirror changes physical ownership once while preserving non-cargo player items")
	check(machines.all(func(station): return station.input_amount == 0 and station.output_amount == 0 and not station.working and is_zero_approx(station.production_time) and station.transfer.is_empty() and station.batch_donors.is_empty()), "Committed machine goods cannot remain live or resume an already-recovered batch")
	check(glass.ingredient_amounts.is_empty() and alloy.ingredient_amounts.is_empty() and mixer.binder == binder_before+1, "Committed mirror clears all multi-ingredient buffers and refunds only the cancelled batch's finite binder")
	check(stores().all(func(crate): return crate.amount >= 0 and crate.amount <= Balance.PICKUP_STACK_MAX), "Aggregate storage is completely distributed across individually valid physical crates")
	check(total("sand") == 20000 and stores("sand").filter(func(crate): return crate.amount > 0).size() == 2, "Two full stores keep 20000 sand without overfilling a single crate")
	var reader := CampaignState.new(save_path, false)
	reader.persistence_enabled = true
	var loaded := reader.load_checkpoint()
	var loaded_stock: Dictionary=reader.expedition.garage_stock.duplicate()
	for kind in loaded_stock: loaded_stock[kind]=int(loaded_stock[kind])
	check(loaded and loaded_stock == expected, "Fresh isolated disk reload restores the actual aggregate stock: "+reader.last_error)
	var preparation: Dictionary=campaign.checkpoint()
	var count_before: int = stores().size()
	for repeat in 3:
		controller._mirror_stock()
		check(controller._capture_stock() == expected and stores().size() == count_before and mixer.binder == binder_before+1, "Repeated mirror cannot duplicate material, crates or binder, pass %d" % repeat)
	check(not controller.on_victory() and controller._capture_stock() == expected, "A completed mission cannot re-credit any recovered machine inventory")
	# Deployment is additive, bounded, once per freshly constructed world.
	sand = stores("sand")[0]
	sand.amount = Balance.PICKUP_STACK_MAX-1
	for other in stores("sand"):
		if other != sand: other.amount = 0
	campaign.expedition.stage = "defense"
	campaign.expedition.deployment_cargo = {"sand":3}
	if game.has_meta("expedition_delivery"): game.remove_meta("expedition_delivery")
	controller._apply_delivery()
	check(total("sand") == Balance.PICKUP_STACK_MAX+2 and stores("sand").all(func(crate): return crate.amount <= Balance.PICKUP_STACK_MAX), "Deployment fills the last free slot and puts overflow in another real crate")
	var delivery_count: int = stores().size()
	controller._apply_delivery()
	check(total("sand") == Balance.PICKUP_STACK_MAX+2 and stores().size() == delivery_count, "Repeated delivery does not replay finite deployment cargo")
	var queued: Supply = stores("sand")[0]
	var retained: int = total("sand")-queued.amount
	queued.queue_free()
	campaign.expedition.deployment_cargo = {"sand":4}
	game.remove_meta("expedition_delivery")
	controller._apply_delivery()
	check(total("sand") == retained+4, "Deployment never deposits into a removed crate and silently loses the delivered material")
	check(stores().all(func(crate): return Schema.valid_state(Schema.kind(crate), snapshotter._capture_fields(crate, Schema.fields(Schema.kind(crate))))), "Every real post-transaction storage record passes network validation")
	for crate in stores().filter(func(candidate): return Schema.kind(candidate) == "convoy_supply"):
		check(crate.position.x >= game.world_left and crate.position.x <= game.world_right, "Dynamic "+crate.kind+" storage remains within actual playable world bounds")
	paused = false
	await Cleanup.free_scene(game,self)
	snapshotter = null
	await restored_storage_probe(preparation)
	clean_files()
	print("RESOURCE LEDGER CHECKS: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
