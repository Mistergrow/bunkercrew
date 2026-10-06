extends SceneTree
## VISUAL FIXTURE ONLY: arranged wave/research/cargo, direct construction calls.
## Produces actual rendered game screenshots; this is not a campaign playthrough.
var game

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("PRESENTATION FIXTURE skipped: run with an actual display to capture rendered screenshots.")
		quit()
		return
	call_deferred("run")

func settle(seconds: float = 1.0) -> void:
	await create_timer(seconds).timeout
	await RenderingServer.frame_post_draw

func capture(path: String) -> void:
	game.notice_time = 0
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(path)
	print("PRESENTATION FIXTURE saved %s (result %d)" % [path, result])

func build_site(site, worker) -> void:
	# Feed real finite worker cargo through the site's production/build API.
	var recipe: Dictionary = site.SPECS[site.kind].cost
	for kind: String in recipe:
		worker.inventory.clear()
		worker.add_item(kind, int(recipe[kind]))
		for item in int(recipe[kind]):
			site.interact(worker, Balance.TRANSFER_TIME + 0.01)
	site.interact(worker, 1.5)
	assert(site.built, "Fixture construction did not complete: " + str(site.kind))

func mine_room(site, worker, limit: int = 100) -> void:
	# Adjacent positions are deliberately arranged for this visual fixture.
	# Each real tile still enforces its exposed face/range and pays its own yield.
	var blocks: Array = site.excavation.blocks.duplicate()
	blocks.sort_custom(func(a,b): return a.grid_cell.x < b.grid_cell.x if a.grid_cell.x != b.grid_cell.x else a.grid_cell.y > b.grid_cell.y)
	worker.set_physics_process(false)
	var mined := 0
	for block in blocks:
		if mined >= limit:
			break
		worker.position = block.global_position + Vector2(-38,20)
		worker.velocity = Vector2.ZERO
		worker.facing = 1
		await physics_frame
		await physics_frame
		assert(block.can_interact(worker), "Fixture mining position must reach a real exposed tile face")
		block.interact(worker,Balance.MINE_TIME + 0.1)
		assert(block.depleted, "Room excavation must remove its real solid block")
		mined += 1
		await process_frame
	worker.set_physics_process(true)

func line_room(site, worker, target: int) -> void:
	# Visually arranged cargo; all deposits and curing still use the real component.
	var lining = site.lining
	for tier in range(1,target+1):
		for kind: String in lining.spec().cost:
			worker.inventory.clear()
			worker.add_item(kind,int(lining.spec().cost[kind]))
			for item in int(lining.spec().cost[kind]):
				lining.interact(worker,Balance.TRANSFER_TIME+0.01)
		lining.interact(worker,float(lining.spec().build_time)+0.01)
		await create_timer(lining.curing_remaining+0.05).timeout
		assert(lining.tier==tier)

func run() -> void:
	Engine.time_scale = 3.0
	Engine.physics_ticks_per_second = 180
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start(2)
	game.rounds.set_process(false)
	game.rounds.wave = 6
	game.rounds.phase = "build"
	game.rounds.time_left = 60
	game._round_phase_changed()
	game.players[1].position = Vector2(1085,600)
	await settle(5)
	await capture("res://artifacts/presentation-wave06-sealed.png")
	game.rounds.wave = 16
	game._round_phase_changed()
	game.upgrades.owned["bunker_workshop"] = true
	game.upgrades.owned["bunker_armor"] = true
	game.upgrades.owned["bunker_fortress"] = true
	var worker = game.players[0]
	for depth in [1,2]:
		for shaft in get_nodes_in_group("excavation_sites"):
			if shaft.depth != depth:
				continue
			for kind: String in shaft.cost():
				worker.inventory.clear()
				worker.add_item(kind,int(shaft.cost()[kind]))
				for item in int(shaft.cost()[kind]):
					shaft.interact(worker,Balance.TRANSFER_TIME+0.01)
			shaft.interact(worker,3.1)
			assert(shaft.completed)
		await process_frame
	assert(game.expansion.open_depths == 2)
	var dome = game.dome
	for kind: String in dome.COST:
		var remaining: int = dome.COST[kind]
		while remaining > 0:
			worker.inventory.clear()
			var amount := mini(remaining,worker.capacity())
			worker.add_item(kind,amount)
			for item in amount:
				dome.interact(worker,Balance.TRANSFER_TIME+0.01)
			remaining -= amount
		if kind == "alloy":
			dome.interact(worker,dome.FRAME_TIME+0.01)
	dome.interact(worker,dome.GLAZE_TIME+0.01)
	assert(dome.built)
	# One finished room beside a partly dug cavity shows the new excavation flow.
	await mine_room(game.expansion.modules[0],worker)
	build_site(game.expansion.modules[0],worker)
	await line_room(game.expansion.modules[0],worker,1)
	await mine_room(game.expansion.modules[1],worker,6)
	worker.position = Vector2(380,430)
	game.players[1].position = Vector2(795,1020)
	await settle(5)
	await capture("res://artifacts/presentation-wave16-excavating.png")
	for site in game.expansion.modules:
		if site.built:
			continue
		await mine_room(site,worker)
		build_site(site,worker)
	for room in game.expansion.modules:
		# Finish only the missing paid stages, including the first room's second tier.
		while room.lining.tier<2:
			var lining = room.lining
			for kind: String in lining.spec().cost:
				worker.inventory.clear()
				worker.add_item(kind,int(lining.spec().cost[kind]))
				for item in int(lining.spec().cost[kind]):
					lining.interact(worker,Balance.TRANSFER_TIME+0.01)
			lining.interact(worker,float(lining.spec().build_time)+0.01)
			await create_timer(lining.curing_remaining+0.05).timeout
	worker.inventory.clear()
	worker.position = Vector2(380,430)
	game.players[1].position = Vector2(675,1240)
	await settle(5)
	# Give each real machine one batch for an animated, readable working scene.
	for station in get_nodes_in_group("stations"):
		if station.has_method("set_amount"):
			for kind: String in station.recipe().inputs:
				station.set_amount(kind,station.recipe().inputs[kind])
		elif station is ProductionStation:
			station.input_amount = station.input_cost(station.input_kind())
	await settle(0.35)
	await capture("res://artifacts/presentation-wave16-complete.png")
	print("PRESENTATION: wave/research/cargo and adjacent mining positions arranged; two shafts, 72 real room tiles, six sites, twelve paid rear-wall stages with actual curing and dome completed through direct interaction APIs; three real rendered screenshots. No campaign completion claimed.")
	var released: bool = await preload("res://tests/scene_cleanup.gd").free_scene(game, self)
	quit(0 if released else 1)
