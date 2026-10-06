extends SceneTree
## Real SAN-1 movement plus adversarial local handoffs on the actual arena.
const Cleanup = preload("res://tests/scene_cleanup.gd")
const Logistics = preload("res://scripts/medic_logistics.gd")
var checks := 0
var failures := 0
var game
var medic
var mixer
var steel_crate
var concrete_crate
var pile
var player
var saw_climb := false
var largest_step := 0.0
var last_position := Vector2.ZERO

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("COLLECTION ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1
		push_error(label)
func frames(count := 3):
	for index in count: await physics_frame
func until(condition: Callable, timeout := 40.0) -> bool:
	var duration := 0.0
	while duration < timeout and not condition.call():
		await physics_frame
		duration += game.get_physics_process_delta_time()
	return condition.call()
func seconds(duration: float): await until(func(): return false, duration)
func observe() -> void:
	if not is_instance_valid(medic): return
	largest_step = maxf(largest_step, medic.global_position.distance_to(last_position))
	last_position = medic.global_position
	saw_climb = saw_climb or medic.climbing
func cargo_units(resource: String) -> int:
	return 1 if medic.logistics_cargo == resource else 0
func new_supply(resource: String, amount: int, point: Vector2):
	var depot := Supply.new()
	depot.game = game
	depot.kind = resource
	depot.amount = amount
	depot.position = point
	game.add_child(depot)
	return depot
func new_pile(resource: String, amount: int, point: Vector2):
	var pickup := ResourcePickup.new()
	pickup.game = game
	pickup.kind = resource
	pickup.amount = amount
	pickup.position = point
	game.add_child(pickup)
	return pickup
func fresh_player() -> void:
	player.medical.interrupt()
	player.medical.bleeding = 0
	player.medical.fractured = false
	player.medical.state = "healthy"
	player.medical.recovery_time = 0
	player.medical.recovery_kind = ""
	player.hp = player.max_hp
	player.invulnerability = 0
	player.hurt_stun = 0
	player.down_time = 0
	player.knockback = 0
	player.since_hit = 99

func run():
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start_scenario(1, {"environment":"sector07", "position":"left", "build_type":"bastion"})
	game.rounds.set_process(false)
	medic = game.medic
	player = game.players[0]
	for candidate in get_nodes_in_group("stations"):
		candidate.set_process(false)
		candidate.output_amount = 0
		if candidate.kind == "mixer": mixer = candidate
	for candidate in get_nodes_in_group("supplies"):
		if candidate.kind == "steel": steel_crate = candidate
		if candidate.kind == "concrete": concrete_crate = candidate
	pile = new_pile("steel", 2, Vector2(game.scenario_bunker.room_left+330, 430))
	var core_reward = new_pile("core", 3, Vector2(game.scenario_bunker.room_left+450, 430))
	core_reward.set_physics_process(false) # No automatic human proximity award in this fixture.
	mixer.output_amount = 2
	mixer.binder = 0 # Finished goods remain collectible with exhausted binder.
	var initial_stock: Dictionary = {}
	for depot in get_nodes_in_group("supplies"):
		initial_stock[depot.get_instance_id()] = depot.amount
	var original_inventory: Dictionary = player.inventory.duplicate(true)
	var original_steel: int = steel_crate.amount
	var original_concrete: int = concrete_crate.amount
	last_position = medic.global_position
	physics_frame.connect(observe)
	await seconds(2.5)
	check(mixer.output_amount == 2 and pile.amount == 2 and medic.logistics_cargo.is_empty(), "Neither independent task runs before research")
	game.upgrades.points = 6
	check(not game.upgrades.purchase("medic_collection"), "Collection requires workshop research")
	check(game.upgrades.purchase("bunker_workshop") and game.upgrades.purchase("medic_collection"), "Collection can be researched without machine supply")
	check(medic.logistics.collection_enabled() and not medic.logistics.enabled(), "Collection and machine supply have independent gates")
	var layout: Array[Dictionary] = []
	for depot in get_nodes_in_group("supplies"):
		var fresh: bool = not initial_stock.has(depot.get_instance_id())
		layout.append({"kind":depot.kind,"amount":depot.amount,"position":[depot.position.x,depot.position.y],"new":fresh})
		if fresh:
			check(depot.amount == 0, depot.kind+": research installs an empty container without free resources")
			check(medic.navigation.support_at(depot.global_position) and medic.navigation.body_clear(depot.global_position), depot.kind+": new storage stands on a real floor with body clearance")
			check(medic.logistics._in_reach(depot) or not medic.logistics._route_to(depot).is_empty(), depot.kind+": new storage is reachable over the actual navigation graph")
			var ladder_clear := true
			for ladder: Rect2 in game.ladders:
				if ladder.grow(22).has_point(depot.global_position): ladder_clear = false
			check(ladder_clear, depot.kind+": new storage keeps ladder access clear")
			var spaced := true
			for other in get_nodes_in_group("supplies"):
				if other != depot and other.global_position.distance_to(depot.global_position) < 54: spaced = false
			check(spaced, depot.kind+": new storage has clearance from neighboring crates")
		else:
			check(depot.amount == initial_stock[depot.get_instance_id()], depot.kind+": research preserves the existing finite stock")
	var layout_file := FileAccess.open("res://artifacts/san-logistics/storage-layout.json", FileAccess.WRITE)
	if layout_file != null:
		layout_file.store_string(JSON.stringify(layout,"\t"))
		layout_file.close()
	for resource: String in ["sand", "limestone", "ore", "tungsten", "steel", "alloy", "concrete", "glass", "ammo", "scrap"]:
		var available := false
		for depot in get_nodes_in_group("supplies"):
			if depot.kind == resource: available = true
		check(available, "Collection research provides a physical matching depot for "+resource)
	check(await until(func(): return medic.logistics_cargo == "concrete"), "SAN-1 physically collects a ready product before loose goods")
	check(mixer.output_amount == 1 and concrete_crate.amount == original_concrete and cargo_units("concrete") == 1, "Product debit precedes one-unit storage credit")
	check(pile.amount == 2 and mixer.input_amount == 0, "Collection-only never feeds the idle machine or steals a second resource")
	check(await until(func(): return concrete_crate.amount == original_concrete+1 and medic.logistics_cargo.is_empty()), "Ready product travels to the real matching crate")
	check(await until(func(): return mixer.output_amount == 0 and concrete_crate.amount == original_concrete+2 and medic.logistics_cargo.is_empty()), "All completed goods clear the machine even when binder is exhausted")
	check(await until(func(): return medic.logistics_cargo == "steel"), "After clearing outputs the assistant collects a loose ground resource")
	check(pile.amount == 1 and steel_crate.amount == original_steel and cargo_units("steel") == 1, "A loose pile loses exactly one finite unit before storage")
	var paused_position: Vector2 = medic.position
	var paused_progress: float = medic.logistics_progress
	paused = true
	await create_timer(.10, true, false, true).timeout
	check(medic.position == paused_position and medic.logistics_progress == paused_progress and cargo_units("steel") == 1, "Pause freezes collection travel, handoff and cargo")
	paused = false
	game.network.active = true
	game.network.is_host = false
	medic._physics_process(2.0)
	medic.logistics.tick(2.0)
	check(medic.position == paused_position and pile.amount == 1 and steel_crate.amount == original_steel, "A guest cannot move SAN-1 or perform collection transactions")
	game.network.active = false
	game.network.is_host = true
	player.position = Vector2(game.scenario_bunker.room_left+370, 430)
	player.velocity = Vector2.ZERO
	player.invulnerability = 0
	player.take_damage(42.0)
	player.knockback = 0
	var treatment_count: int = medic.treatments_completed
	await frames(2)
	check(medic.target == player and medic.logistics_phase == "medical" and cargo_units("steel") == 1, "Medical treatment immediately preempts collection with cargo secured")
	check(await until(func(): return medic.treatments_completed > treatment_count), "A carrying collector still physically treats the wounded player")
	check(cargo_units("steel") == 1 and pile.amount == 1 and steel_crate.amount == original_steel, "Treatment cannot duplicate or consume the carried resource")
	fresh_player()
	steel_crate.amount = Balance.PICKUP_STACK_MAX
	check(await until(func(): return medic.logistics_phase == "holding"), "A depot filled by a player causes secured holding instead of overflow")
	check(steel_crate.amount == Balance.PICKUP_STACK_MAX and cargo_units("steel") == 1 and pile.amount == 1, "A full depot retains every unit across the source, cargo and storage")
	steel_crate.queue_free()
	await frames()
	await seconds(2.5)
	check(medic.logistics_phase == "holding" and cargo_units("steel") == 1, "Removing every matching depot retains cargo without spawning a drop loop")
	var replacement = new_supply("steel", 0, Vector2(game.scenario_bunker.room_left+280, 430))
	game.upgrades.owned.erase("medic_collection")
	check(await until(func(): return replacement.amount == 1 and medic.logistics_cargo.is_empty()), "Existing cargo can finish its physical storage trip after collection research is revoked")
	await seconds(4.0)
	check(pile.amount == 1 and replacement.amount == 1, "Revoked collection does not withdraw a new unit")
	check(core_reward.amount == 3 and game.upgrades.earned == 0, "SAN-1 excludes shared technique-point controller rewards")
	check(player.inventory == original_inventory, "All collection preserves the player's owned inventory")
	check(saw_climb and largest_step < 8.0, "Actual roof storage and medical trips use ladders without teleportation")
	medic.set_physics_process(false)
	# Race probes share the live arena and normal handoff clock; only fixtures move.
	pile.queue_free()
	core_reward.queue_free()
	await frames()
	game.upgrades.owned = {"bunker_workshop":true, "medic_logistics":true, "medic_collection":true}
	mixer.position = Vector2(460, 430)
	mixer.binder = 3
	mixer.input_amount = 0
	mixer.output_amount = 1
	concrete_crate.position = Vector2(512, 430)
	medic.position = Vector2(488, 430)
	medic.velocity = Vector2.ZERO
	medic.climbing = false
	medic.logistics._clear_trip()
	await frames()
	check(medic.logistics._find_job() and medic.logistics.source == mixer and medic.logistics._job == "store", "With both unlocks a finished product has priority over new furnace or mixer inputs")
	medic.logistics_phase = "collect"
	medic.logistics._visit(mixer, .60)
	check(mixer.output_amount == 1 and medic.logistics_cargo.is_empty(), "An incomplete collection hold cannot take a product")
	player.inventory["concrete"] = 0
	var picked: int = player.add_item("concrete", 1)
	mixer.output_amount -= picked # The same finite result can already be owned by a player.
	medic.logistics._visit(mixer, .66)
	check(mixer.output_amount == 0 and medic.logistics_cargo.is_empty() and player.inventory.concrete == picked, "A player taking the reserved product prevents a second robot debit")
	medic.logistics._clear_trip()
	mixer.output_amount = 1
	check(medic.logistics._find_job(), "A new finished product creates a distinct collection task")
	medic.logistics_phase = "collect"
	var destination_before: int = concrete_crate.amount
	medic.logistics._visit(mixer, 1.25)
	check(mixer.output_amount == 0 and cargo_units("concrete") == 1 and concrete_crate.amount == destination_before, "Completed product handoff takes one unit without a remote depot credit")
	concrete_crate.amount = Balance.PICKUP_STACK_MAX
	medic.logistics._handoff(concrete_crate)
	check(concrete_crate.amount == Balance.PICKUP_STACK_MAX and cargo_units("concrete") == 1, "Storage capacity is revalidated at the final commit")
	concrete_crate.amount = destination_before
	medic.logistics._visit(concrete_crate, 1.25)
	check(concrete_crate.amount == destination_before+1 and medic.logistics_cargo.is_empty(), "A recovered depot credits the same preserved unit once")
	# A pile taken while a route is reserved must not yield negative resources.
	var race_pile = new_pile("steel", 1, Vector2(460,430))
	replacement.position = Vector2(512,430)
	medic.logistics._clear_trip()
	mixer.output_amount = 0
	game.upgrades.owned.erase("medic_logistics")
	await frames()
	check(medic.logistics._find_job() and medic.logistics.source == race_pile, "Collection-only selects the real reachable loose pile")
	medic.logistics_phase = "collect"
	medic.logistics._visit(race_pile, .70)
	race_pile.amount = 0
	medic.logistics._visit(race_pile, .55)
	check(race_pile.amount == 0 and medic.logistics_cargo.is_empty(), "A loose unit removed by a player cannot be duplicated at pickup commit")
	race_pile.amount = 1
	race_pile.kind = "core"
	medic.logistics._handoff(race_pile)
	check(race_pile.amount == 1 and medic.logistics_cargo.is_empty(), "Changing the reserved pile to a core reward cancels its collection")
	race_pile.kind = "steel"
	race_pile.queue_free()
	await frames()
	medic.logistics._handoff(null)
	check(medic.logistics_cargo.is_empty(), "A deleted reserved pickup cannot create cargo")
	for recipe_id: String in ["glass", "alloy"]:
		var machine := RecipeStation.new()
		machine.game = game
		machine.kind = recipe_id
		machine.position = Vector2(460,430)
		game.add_child(machine)
		machine.set_process(false)
		machine.output_amount = 2
		var depot: Node2D
		for candidate in get_nodes_in_group("supplies"):
			if candidate.kind == machine.output_kind(): depot = candidate
		check(is_instance_valid(depot), recipe_id+": newly researched store supports the actual recipe output")
		if is_instance_valid(depot):
			depot.position = Vector2(512,430)
			var initial_amount: int = depot.amount
			for unit in 2:
				medic.logistics._clear_trip()
				medic.position = Vector2(488,430)
				medic.velocity = Vector2.ZERO
				await frames()
				check(medic.logistics._find_job() and medic.logistics.source == machine, recipe_id+": completed multi-ingredient output is selected for storage")
				medic.logistics_phase = "collect"
				medic.logistics._visit(machine,1.25)
				check(machine.output_amount == 1-unit and cargo_units(machine.output_kind()) == 1 and depot.amount == initial_amount+unit, recipe_id+": exactly one finished unit is physically carried")
				medic.logistics._visit(depot,1.25)
				check(medic.logistics_cargo.is_empty() and depot.amount == initial_amount+unit+1, recipe_id+": depot credits the carried unit once")
			check(machine.output_amount == 0 and depot.amount == initial_amount+2, recipe_id+": both finished products cleared without changing recipe ingredients")
		machine.queue_free()
		await frames()
	# One genuine multi-ingredient batch runs through the usual station process:
	# all three inputs are finite, and SAN-1 both supplies and clears its products.
	var sand_depot: Node2D
	var lime_depot: Node2D
	var glass_depot: Node2D
	for depot in get_nodes_in_group("supplies"):
		if depot.kind == "sand": sand_depot = depot
		if depot.kind == "limestone": lime_depot = depot
		if depot.kind == "glass": glass_depot = depot
	if is_instance_valid(sand_depot) and is_instance_valid(lime_depot) and is_instance_valid(glass_depot):
		for candidate in get_nodes_in_group("stations"):
			candidate.output_amount = 0
			candidate.working = true # Isolate this finite glass batch from other recipes.
		sand_depot.amount = 2
		lime_depot.amount = 1
		sand_depot.position = Vector2(512,430)
		lime_depot.position = Vector2(548,430)
		glass_depot.position = Vector2(576,430)
		var glass_before: int = glass_depot.amount
		var glass_machine := RecipeStation.new()
		glass_machine.kind = "glass"
		glass_machine.game = game
		glass_machine.position = Vector2(460,430)
		game.add_child(glass_machine)
		game.upgrades.owned.medic_logistics = true
		medic.logistics._clear_trip()
		medic.set_physics_process(true)
		check(await until(func(): return glass_machine.working), "Real SAN-1 physically supplies both ingredients and the normal glass recipe starts")
		check(sand_depot.amount == 0 and lime_depot.amount == 0 and glass_machine.input_amount == 0 and glass_machine.amount_for("limestone") == 0, "The running glass batch consumes exactly its two sand and one limestone")
		check(await until(func(): return glass_depot.amount == glass_before+2 and glass_machine.output_amount == 0 and medic.logistics_cargo.is_empty()), "Normal crafting completes and SAN-1 clears both glass products into storage")
		check(sand_depot.amount == 0 and lime_depot.amount == 0 and glass_depot.amount == glass_before+2, "A whole automatic supply-craft-collect cycle obeys the exact finite recipe")
	# Replacing a world on the same Game must allow empty stores to be rebuilt.
	medic.set_physics_process(false)
	game.started = false
	game.start_scenario(1,{"environment":"ash_foundry","position":"right","build_type":"bastion"})
	game.rounds.set_process(false)
	medic = game.medic
	medic.set_physics_process(false)
	check(not game.has_meta("medic_storage_provisioned"), "World replacement clears the previous storage provisioning marker")
	game.upgrades.apply_world_effects()
	var replacement_count := get_nodes_in_group("supplies").size()
	check(game.has_meta("medic_storage_provisioned") and replacement_count == 10, "Existing collection research provisions exactly ten physical material stores in the replacement world")
	game.upgrades.apply_world_effects()
	check(get_nodes_in_group("supplies").size() == replacement_count, "Repeated world-effect application cannot duplicate empty depots")
	await frames()
	for depot in get_nodes_in_group("supplies"):
		check(medic.logistics._in_reach(depot) or not medic.logistics._route_to(depot).is_empty(), depot.kind+": relocated right bunker storage remains physically reachable")
	await Cleanup.free_scene(game, self)
	print("MEDIC COLLECTION: %d/%d checks passed" % [checks-failures,checks])
	quit(0 if failures == 0 else 1)
