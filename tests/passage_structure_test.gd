extends SceneTree
## Explicit late-room fixtures: recipes are supplied to a real worker, required
## waves and construction deltas are arranged, then each room is paid through
## ScenarioRoomSite.interact. No floor or hatch state is assigned. Physics rays,
## body sweeps and the final InputMap journey use the actual main-scene world.
var game
var worker: Worker
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("PASSAGE STRUCTURE %s: %s" % ["PASS" if value else "FAIL",label])
	if not value:
		failures += 1
		push_error(label)

func frames(count: int = 4) -> void:
	for _i in count: await physics_frame

func until(predicate: Callable, limit: int = 500) -> bool:
	for _i in limit:
		await physics_frame
		if predicate.call(): return true
	return false

func ray(from: Vector2, to: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from,to,1)
	query.hit_from_inside = true
	return worker.get_world_2d().direct_space_state.intersect_ray(query)

func physical_hatch_at(x: float, y: float, depth: float):
	var hit := ray(Vector2(x,y-2),Vector2(x,y+depth+2))
	return hit.get("collider")

func whole_worker_fits(passage: LadderPassage) -> bool:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(22,40)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1
	query.transform = Transform2D(0,passage.global_position+Vector2(0,passage.slab_depth+24))
	query.motion = Vector2(0,-passage.slab_depth-49)
	var clearance := worker.get_world_2d().direct_space_state.cast_motion(query)
	return clearance[0]>=0.999

func climb_to(floor_y: float) -> bool:
	var descending := floor_y>worker.global_position.y
	var action := "p1_down" if descending else "p1_up"
	Input.action_press(action)
	var reached := await until(func(): return worker.global_position.y>=floor_y-3 if descending else worker.global_position.y<=floor_y+3)
	Input.action_release(action)
	var standing := await until(func(): return not worker.climbing and absf(worker.global_position.y-floor_y)<1,120)
	var support := ray(worker.global_position-Vector2(0,3),worker.global_position+Vector2(0,5))
	return reached and standing and worker.collision_mask==1 and not support.is_empty()

func run() -> void:
	Engine.time_scale = 2.0
	Engine.physics_ticks_per_second = 120
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1,{"environment":"basalt_quarry","build_type":"bastion","position":"center"})
	game.rounds.running = false
	game.medic.set_physics_process(false)
	worker = game.players[0]
	worker.set_physics_process(false)
	var bunker: ScenarioBunker = game.scenario_bunker
	for index in 4:
		var site: ScenarioRoomSite = bunker.modules[index]
		site.set_process(false)
		var recipe: Dictionary = site.spec().cost.duplicate(true)
		game.rounds.wave = int(site.spec().wave)
		await preload("res://tests/scenario_excavation_fixture.gd").build_room(game,index,worker)
		await frames()
		var paid: Dictionary = site.materials.duplicate()
		for kind: String in site.support_materials: paid[kind] = int(paid.get(kind,0)) + int(site.support_materials[kind])
		check(site.built and worker.carried_count()==0 and paid==recipe and bunker.built_rooms==index+2,"Room %d excavates its floor and consumes exactly its full support plus lining recipe" % [index+1])
	var expected := [245.0,430.0,635.0,840.0,1045.0]
	var actual: Array[float] = []
	for passage in bunker.passages: actual.append(passage.global_position.y)
	actual.sort()
	check(actual==expected and game.floor_levels==[245.0,430.0,635.0,840.0,1045.0,1250.0],"All four paid extensions produce exactly five passage levels and a solid deepest landing")
	var shaft_x: float = game.ladders[0].get_center().x
	for floor_y in expected:
		var passage: LadderPassage
		for candidate in bunker.passages:
			if is_equal_approx(candidate.global_position.y,floor_y): passage = candidate
		if not is_instance_valid(passage): continue
		worker.global_position = Vector2(shaft_x+100,430)
		worker.climbing = false
		worker.collision_mask = 1
		await frames(32)
		check(physical_hatch_at(shaft_x,floor_y,passage.slab_depth)==passage,"Floor %.0f: closed central layer-1 ray hits the actual steel hatch" % floor_y)
		# Hold below the aperture, outside its occupancy volume, and request a
		# normal upward step. Opening must come from the automatic passage API.
		worker.global_position = Vector2(shaft_x,floor_y+passage.slab_depth+75)
		worker.climbing = true
		worker.collision_mask = 0
		var allowed := false
		for _frame in 60:
			allowed = LadderPassage.allow_motion(worker,worker.global_position.y-1)
			await physics_frame
			if allowed and passage.opening>=0.999: break
		await frames(2)
		var rays_clear := true
		for dx in [-12.0,0.0,12.0]:
			rays_clear = rays_clear and ray(Vector2(shaft_x+dx,floor_y-2),Vector2(shaft_x+dx,floor_y+passage.slab_depth+2)).is_empty()
		check(allowed and rays_clear,"Floor %.0f: opening removes all central slab collisions, including any obsolete concrete body" % floor_y)
		check(whole_worker_fits(passage),"Floor %.0f: the complete 22×40 worker collider fits through the open shaft" % floor_y)
		worker.global_position = Vector2(shaft_x+100,430)
		worker.climbing = false
		worker.collision_mask = 1
		await frames(40)
		check(passage.opening<=0.001 and physical_hatch_at(shaft_x,floor_y,passage.slab_depth)==passage,"Floor %.0f: leaving the opening restores a solid physical hatch" % floor_y)
	var lowest = physical_hatch_at(shaft_x,1250,20)
	check(is_instance_valid(lowest) and lowest is StaticBody2D and not lowest is LadderPassage,"The deepest floor at 1250 stays solid concrete and has no unnecessary hatch")
	# Complete uninterrupted downward and upward journeys with an ordinary
	# supported stop on each floor, using only the existing InputMap actions.
	worker.global_position = Vector2(shaft_x,245)
	worker.velocity = Vector2.ZERO
	worker._ladder = game.ladders[0]
	worker.climbing = false
	worker.collision_mask = 1
	worker.set_physics_process(true)
	await frames(6)
	for floor_y in [430.0,635.0,840.0,1045.0,1250.0]:
		check(await climb_to(floor_y),"InputMap descent reaches floor %.0f and safely stands on its real support" % floor_y)
	for floor_y in [1045.0,840.0,635.0,430.0,245.0]:
		check(await climb_to(floor_y),"InputMap ascent reaches floor %.0f and safely stands on its real support" % floor_y)
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Expanded scene and all passage references clean up normally")
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	print("PASSAGE STRUCTURE RESULT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
