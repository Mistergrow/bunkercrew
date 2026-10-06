extends SceneTree
## Actual main scene. Wave-clear state and initial cargo are arranged explicitly;
## depth access, construction, production and dropped cargo use real InputMap
## processing. This is an integration regression, not a full combat playthrough.

var game
var worker
var partner
var checks := 0
var failures := 0
var target_floor := 1020.0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	print("EXPANSION %s: %s" % ["PASS" if value else "FAIL", label])
	if not value:
		failures += 1
		push_error(label)

func step(frames: int = 3) -> void:
	for _frame in frames:
		await physics_frame

func hold(action: String, seconds: float) -> void:
	Input.action_press(action)
	await create_timer(seconds, false, true).timeout
	Input.action_release(action)
	await step()

func tap(action: String) -> void:
	Input.action_press(action)
	await step(2)
	Input.action_release(action)
	await step()

func walk_to(target_x: float) -> bool:
	var direction := 1.0 if worker.position.x < target_x else -1.0
	var action := "p1_right" if direction > 0 else "p1_left"
	Input.action_press(action)
	for _frame in 300:
		await physics_frame
		if (target_x - worker.position.x) * direction <= 3.5:
			break
	Input.action_release(action)
	await step()
	return absf(worker.position.x - target_x) < 6 and absf(worker.position.y - target_floor) < 1

func select_target(target) -> bool:
	for _attempt in 12:
		if worker.focus == target:
			return true
		await tap("p1_cycle_target")
	return worker.focus == target

func excavate_room(room) -> bool:
	# Actual held input removes the room's earth from its accessible left face.
	worker.inventory.clear()
	var field = room.excavation
	check(not room.can_interact(worker),"A buried room cannot accept materials before excavation")
	for col in 4:
		await walk_to(field.bounds.position.x+col*48-17)
		for row in [2,1,0]:
			var block = field.cell_at(Vector2i(col,row))
			if not is_instance_valid(block): continue
			await select_target(block)
			if worker.focus != block:
				check(false,"Exposed room face is reachable with ordinary controls")
				return false
			await hold("p1_interact",0.65)
			if is_instance_valid(block):
				check(false,"Held excavation removes one real earth cell")
				return false
	check(field.is_cleared() and room.can_interact(worker),"Removing actual soil opens the room and reveals its build plan")
	worker.inventory.clear()
	return field.is_cleared()

func load_cargo(cargo: Dictionary) -> void:
	worker.inventory.clear()
	for kind: String in cargo:
		worker.add_item(kind, int(cargo[kind]))

func site(kind: String):
	for candidate in game.expansion.modules:
		if candidate.kind == kind:
			return candidate
	return null

func deep_supplies() -> Array:
	return get_nodes_in_group("supplies").filter(func(supply): return supply.position.y > 900)

func capture(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	game.notice_time = 0
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	Engine.time_scale = 3.0
	Engine.physics_ticks_per_second = 180
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	# This fixture compares shared research multipliers on neutral workers.
	# Character-specific capacity and speed are tested by player_progression_test.
	game.selected_characters.assign(["mara", "mara"])
	game.start(2)
	game.rounds.set_process(false)
	worker = game.players[0]
	partner = game.players[1]
	await step()
	var research = game.upgrades
	check(research.points == 0 and not research.purchase("boots") and not research.purchase("missing_node"), "Unaffordable and unknown research never spends points")
	worker.add_item("ore", Balance.CARRY_CAPACITY)
	game.spawn_pickup("core", 3, worker.position + Vector2(8, -1))
	await step(8)
	check(research.points == 3 and research.earned == 3 and worker.carried_count() == Balance.CARRY_CAPACITY and not worker.inventory.has("core"), "Nearby luminous cores become shared points even with a full inventory")
	check(get_nodes_in_group("pickups").is_empty(), "Two nearby workers cannot collect the same core twice")
	research.add_points(40)
	var before: int = research.points
	check(not research.purchase("harness") and not research.purchase("shotgun") and not research.purchase("bunker_fortress") and research.points == before, "Missing parents and wave gates conserve all points")
	check(research.purchase("boots") and research.purchase("harness"), "Worker branch unlocks in prerequisite order")
	check(worker.capacity() == 8 and partner.capacity() == 8 and is_equal_approx(worker.movement_multiplier(), 1.15) and is_equal_approx(partner.movement_multiplier(), 1.15), "Worker capacity and movement improvements are shared with both players")
	check(worker.add_item("ore", 3) == 2 and worker.carried_count() == 8, "Improved inventory accepts exactly eight carried units")
	worker.inventory.clear()
	check(research.purchase("weapon_handling") and research.purchase("shotgun") and is_equal_approx(research.weapon_multiplier(), 1.2), "Weapon branch unlocks handling and its shotgun prerequisite")
	before = research.points
	check(not research.purchase("arcgun") and not research.purchase("craftsmanship") and research.points == before, "Weapon and work improvements for wave six remain locked in wave one")
	check(not game.depth_unlocked and game.floor_levels.size() == 4 and game.expansion.modules.is_empty(), "Deep floor and construction slots are absent before the fifth cleared wave")
	# Arrange only cleared-wave states; verify that waves one to four never zoom.
	for early_wave in range(1,5):
		game.rounds.wave = early_wave
		game.rounds._set_phase("salvage",Balance.SALVAGE_TIME)
		check(game.view_stage==1 and not game.depth_unlocked and not game.dome.available,"Wave %d leaves the compact bunker and late dome locked" % early_wave)
	game.rounds.wave = 5
	game.rounds.phase = "attack"
	game.rounds.spawned = 5
	game.rounds.wave_total = 5
	game.rounds._process(0.0)
	await step()
	check(game.rounds.phase == "salvage" and game.depth_unlocked and game.expansion.unlocked, "Fifth-wave salvage permits excavation through the real phase-change signal")
	check(game.floor_levels.size()==4 and game.ladders.size()==2 and game.expansion.modules.is_empty(), "A milestone permits digging but does not create free completed rooms")
	worker.position = Vector2(420,800)
	worker.velocity = Vector2.ZERO
	await step()
	var shaft = get_nodes_in_group("excavation_sites")[0]
	load_cargo({"steel":1})
	await select_target(shaft)
	await hold("p1_interact",0.6)
	check(shaft.materials.get("steel",0)==1 and worker.carried_count()==0 and game.floor_levels.size()==4,"Shaft preserves a partial support deposit without opening unsafe terrain")
	load_cargo({"steel":1})
	await hold("p1_interact",4.0)
	check(game.floor_levels.count(1020.0) == 1 and game.ladders.size() == 3 and game.expansion.modules.size() == 3, "Held excavation opens one supported floor, ladder and three separate build sites")
	check(get_nodes_in_group("mine_blocks").size() == 72 and get_nodes_in_group("expansion_sites").size() == 3, "Deep excavation reveals nine rich seam cells and thirty-six room-earth cells")
	game.unlock_depth()
	game._round_phase_changed()
	check(game.floor_levels.count(1020.0) == 1 and game.ladders.size() == 3 and game.expansion.modules.size() == 3 and deep_supplies().is_empty(), "Repeated unlock signals cannot duplicate rooms, ladders or unbuilt supplies")
	check(is_equal_approx(game.camera_target_zoom, 0.62) and game.camera_target_center == Vector2(760, 525), "Camera targets the shared flak and underground view")
	game.rounds._process(Balance.SALVAGE_TIME + 0.01)
	check(game.rounds.wave == 6 and game.rounds.phase == "build", "Fifth salvage ends in the sixth construction phase")
	worker.position = Vector2(420, 800)
	worker.velocity = Vector2.ZERO
	worker.climbing = false
	await step()
	Input.action_press("p1_down")
	for _frame in 180:
		await physics_frame
		if worker.position.y >= 1019.5:
			break
	Input.action_release("p1_down")
	await step()
	check(absf(worker.position.y - target_floor) < 1 and worker.collision_mask == 1, "Real ladder input reaches the deep floor without the old fall-reset limit")
	var furnace_site = site("furnace")
	await excavate_room(furnace_site)
	check(await walk_to(550), "The excavated floor connects the ladder to the extra-furnace site")
	check(await select_target(furnace_site), "F explicitly selects the new furnace plan beside preserved mining overflow")
	load_cargo({"steel": 1})
	await hold("p1_interact", 0.5)
	check(furnace_site.materials.is_empty() and worker.inventory.get("steel", 0) == 1, "Locked workshop construction cannot take material")
	check(research.purchase("bunker_workshop"), "Workshop research unlocks physical furnace construction")
	await hold("p1_interact", 0.5)
	check(furnace_site.materials.get("steel", 0) == 1 and worker.carried_count() == 0 and not furnace_site.built, "Partial held-E deposit remains in the site's own inventory")
	await hold("p1_interact", 0.5)
	check(furnace_site.materials.get("steel", 0) == 1 and not furnace_site.built, "Empty-handed interaction cannot lose buffered material or finish construction")
	load_cargo({"steel": 1, "concrete": 2})
	await hold("p1_interact", 3.0)
	check(furnace_site.built and furnace_site.materials.get("steel", 0) == 2 and furnace_site.materials.get("concrete", 0) == 2 and worker.carried_count() == 0, "The remaining recipe completes exactly one extra furnace")
	var furnace
	for station in get_nodes_in_group("stations"):
		if station.kind == "furnace" and station.position.y > 900:
			furnace = station
	check(is_instance_valid(furnace) and await select_target(furnace) and is_equal_approx(furnace.duration(), Balance.RECIPES.furnace.time * 0.8), "Built station replaces its plan, remains selectable beside overflow and receives workshop speed")
	if is_instance_valid(furnace):
		worker.add_item("ore", 2)
		await hold("p1_interact", 0.75)
		check(furnace.working and worker.carried_count() == 0, "Deep furnace accepts actual carried ore through held E")
		await create_timer(furnace.duration() + 0.2, false, true).timeout
		await hold("p1_interact", 0.75)
		check(worker.inventory.get("steel", 0) == 2 and furnace.output_amount == 0, "Newly constructed furnace produces and returns usable steel")
		await tap("p1_drop")
		await step(55)
		var dropped
		for pile in get_nodes_in_group("pickups"):
			if pile.kind == "steel": dropped = pile
		check(is_instance_valid(dropped) and absf(dropped.position.y - 1020) < 2 and worker.inventory.get("steel", 0) == 1, "Dropped material settles safely on the new floor")
		if is_instance_valid(dropped):
			check(await select_target(dropped), "Deep-floor dropped cargo can be explicitly selected beside its station")
			await tap("p1_interact")
			check(worker.inventory.get("steel", 0) == 2 and not is_instance_valid(dropped), "Deep-floor cargo is recoverable without material loss")
	var lining = furnace_site.lining
	check(lining.tier==0 and lining.materials.is_empty(),"Workshop equipment never grants a free concrete rear wall")
	await capture("res://artifacts/room-lining-raw-input.png")
	check(await walk_to(480) and await select_target(lining),"The independent wall anchor is reachable beside the working furnace")
	var before_lining_max: float = game.core.max_hp
	var before_lining_hp: float = game.core.hp
	load_cargo({"concrete":2,"steel":1,"ore":1})
	await hold("p1_interact",3.0)
	check(lining.curing_remaining>0 and lining.tier==0 and worker.inventory=={"ore":1},"Held E pays only the rear-wall recipe and starts actual curing")
	check(game.core.max_hp==before_lining_max and game.core.hp==before_lining_hp,"Fresh rear-wall concrete grants no premature durability")
	await capture("res://artifacts/room-lining-curing-input.png")
	await create_timer(lining.curing_remaining+0.15,false,true).timeout
	check(lining.tier==1 and game.core.max_hp==before_lining_max+30 and game.core.hp==before_lining_hp+30,"Cured concrete adds thirty real core HP exactly once")
	load_cargo({"concrete":3,"steel":2,"ore":1})
	await select_target(lining)
	await hold("p1_interact",4.0)
	check(lining.curing_remaining>0 and lining.tier==1 and worker.inventory=={"ore":1},"Structural reinforcement consumes its separate second recipe without touching other cargo")
	await create_timer(lining.curing_remaining+0.15,false,true).timeout
	check(lining.tier==2 and game.core.max_hp==before_lining_max+75 and game.core.hp==before_lining_hp+75,"Finished reinforced rear wall grants only its additional forty-five HP")
	check(partner.inventory.is_empty() and not lining.can_interact(worker),"Completed lining stops taking material and does not alter the other player's cargo")
	await capture("res://artifacts/room-lining-finished-input.png")
	await excavate_room(site("ammo_press"))
	var depot = site("depot")
	await excavate_room(depot)
	check(await walk_to(1070), "The dug gallery reaches the supply-room site")
	check(await select_target(depot), "Supply-room construction can be selected beside preserved digging materials")
	load_cargo({"steel": 1, "concrete": 2})
	await hold("p1_interact", 2.8)
	var ammo
	var sand
	for supply in deep_supplies():
		if supply.kind == "ammo": ammo = supply
		if supply.kind == "sand": sand = supply
	check(depot.built and deep_supplies().size() == 2 and is_instance_valid(ammo) and is_instance_valid(sand), "Supply-room recipe creates exactly two real supply objects")
	if is_instance_valid(ammo) and is_instance_valid(sand):
		check(ammo.amount == 12 and sand.amount == 24, "New storage contains exactly twelve ammo boxes and twenty-four sand")
		await select_target(ammo)
		await hold("p1_interact", 2.7)
		check(ammo.amount == 4 and worker.inventory.get("ammo", 0) == 8, "Eight ammo boxes fit the upgraded capacity and four remain safely stored")
		worker.take_item("ammo", 8)
		await hold("p1_interact",1.4)
		worker.take_item("ammo",4)
		await hold("p1_interact", 0.8)
		depot.interact(worker, 10.0)
		depot._finish()
		game.unlock_depth()
		check(ammo.amount == 0 and sand.amount == 24 and worker.carried_count() == 0 and deep_supplies().size() == 2, "Empty storage and repeated completion or unlock calls never create extra supplies")
	game.rounds.wave = 10
	game.rounds._set_phase("salvage",Balance.SALVAGE_TIME)
	check(game.view_stage==3 and is_equal_approx(game.camera_target_zoom,0.50) and not game.dome.available,"Tenth-wave clearance widens the world while the dome remains locked")
	check((1240-game.camera_target_center.y)*game.camera_target_zoom+450<748 and (-15-game.camera_target_center.y)*game.camera_target_zoom+450>112,"Deep floor and flak upper hull both fit between the fixed HUD panels")
	check(await walk_to(420),"The deeper shaft is reachable from the first underground workshops")
	var second_shaft = get_nodes_in_group("excavation_sites")[0]
	load_cargo({"steel":2,"concrete":2})
	await select_target(second_shaft)
	await hold("p1_interact",4.8)
	check(game.expansion.open_depths==2 and game.floor_levels.count(1240.0)==1 and game.ladders.size()==3 and game.ladders[2].end.y==1245,"Paid second excavation extends one continuous ladder without overlapping climb areas")
	game.rounds._process(Balance.SALVAGE_TIME+0.1)
	target_floor = 1240.0
	await hold("p1_down",1.5)
	check(absf(worker.position.y-1240)<1 and worker.collision_mask==1,"Real ladder input reaches the deepest floor and restores terrain collision")
	check(get_nodes_in_group("mine_blocks").filter(func(block): return block.kind=="tungsten").size()==6,"Valuable tungsten veins occur only in the newly excavated deep seam")
	var core_room = site("core_room")
	await excavate_room(core_room)
	check(await walk_to(550), "The core-room site is reachable through its dug opening")
	check(await select_target(core_room),"The worker explicitly selects the core-room plan instead of nearby loose soil")
	load_cargo({"steel": 2, "concrete": 3})
	await hold("p1_interact", 0.5)
	check(core_room.materials.is_empty() and worker.carried_count() == 5, "Core protection requires its own research and preserves cargo while locked")
	check(research.purchase("bunker_armor"), "Bunker armor research unlocks the core protection room")
	game.core.take_damage(25)
	var core_hp: float = game.core.hp
	var core_max: float = game.core.max_hp
	await hold("p1_interact", 3.1)
	check(core_room.built and game.core.max_hp == core_max + 150 and game.core.hp == core_hp + 150, "Paid core-room construction adds exactly 150 durability while preserving existing damage")
	core_room.interact(worker, 10.0)
	core_room._finish()
	check(game.core.max_hp == core_max + 150 and game.core.hp == core_hp + 150, "Core-room completion cannot grant the durability bonus twice")
	check(research.purchase("arcgun") and research.purchase("craftsmanship"), "Post-expansion weapon and worker branches unlock after their prerequisites")
	check(is_equal_approx(worker.work_multiplier(), 1.25) and is_equal_approx(partner.work_multiplier(), 1.25), "Work-speed research applies equally to both workers")
	before = research.points
	check(not research.purchase("bunker_fortress") and research.points == before, "Final wall research stays locked before wave sixteen")
	game.rounds.wave = 15
	game.rounds._set_phase("salvage",Balance.SALVAGE_TIME)
	check(game.view_stage==4 and game.dome.available and is_equal_approx(game.camera_target_zoom,0.48),"Fifteenth-wave clearance reveals the full bunker perimeter and dome site")
	game.rounds._process(Balance.SALVAGE_TIME+0.1)
	check(research.purchase("bunker_fortress"), "Wave sixteen unlocks the final researched wall tier and dome")
	before = research.points
	check(not research.purchase("bunker_fortress") and research.points == before, "Research cannot be purchased or charged twice")
	var spent := 0
	var branches: Dictionary = {}
	for id: String in research.owned:
		var data: Dictionary = research.node_data(id)
		spent += int(data.cost)
		branches[int(data.branch)] = true
	check(branches.size() == 3 and research.owned.size() == 9 and research.points + spent == research.earned, "All three completed branches conserve every earned and spent upgrade point")
	game.set_camera_mode("overview") # This fixture checks the full expanded-bunker composition.
	await step(90)
	# The centered HUD can move within an expanded viewport (including the
	# square headless dummy). Compare the worker with the actual HUD space.
	for window_size in [root.size,Vector2i(1440,900),Vector2i(2560,1440)]:
		root.size = window_size
		await step(3)
		game.camera.force_update_scroll()
		var feet_ui: Vector2 = game.hud.world_to_ui(worker.global_position)
		print("EXPANSION LAYOUT: window=%s viewport=%s hud_offset=%s feet_ui=%s"%[root.size,root.get_visible_rect().size,game.hud.canvas.position,feet_ui])
		check(worker.position.y > 1239 and feet_ui.y>500 and feet_ui.y<748, "Deep-floor worker stays grounded and above the injury HUD at %s"%window_size)
	print("UPGRADE EXPANSION: %d passed, %d failed. Wave clear was arranged; traversal and work used actual InputMap input." % [checks - failures, failures])
	if not await preload("res://tests/scene_cleanup.gd").free_scene(game, self):
		failures += 1
	quit(1 if failures else 0)
