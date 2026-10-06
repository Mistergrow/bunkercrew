extends SceneTree
## Real main-scene physics and InputMap motion. Actor placement isolates
## individual hatch transitions; rooms, floor collisions and hatch clocks are
## the ordinary scenario nodes. SAN-1 plans and executes its own rescue route.
var game
var p1: Worker
var p2: Worker
var ladder: Rect2
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("PASSAGE MOTION %s: %s" % ["PASS" if value else "FAIL", label])
	if not value:
		failures += 1
		push_error(label)

func frames(count: int = 4) -> void:
	for _i in count:
		await physics_frame

func until(predicate: Callable, limit: int = 600) -> bool:
	for _i in limit:
		await physics_frame
		if predicate.call(): return true
	return false

func release_inputs() -> void:
	for id in [1,2]:
		for suffix in ["up","down","left","right","jump"]:
			Input.action_release("p%d_%s" % [id,suffix])

func place(worker: Worker, point: Vector2, on_ladder: bool = false) -> void:
	worker.global_position = point
	worker.velocity = Vector2.ZERO
	worker.climbing = on_ladder
	worker._ladder = ladder
	worker.collision_mask = 0 if on_ladder else 1
	worker._passage_jump_exit = false

func floor_supported(worker: Worker) -> bool:
	var query := PhysicsRayQueryParameters2D.create(worker.global_position + Vector2(0,-3),worker.global_position + Vector2(0,5),1)
	query.exclude = [worker.get_rid()]
	var hit := worker.get_world_2d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.normal.y < -0.5

func climb_to(worker: Worker, floor_y: float) -> bool:
	var descending := floor_y > worker.global_position.y
	var action := worker.action("down" if descending else "up")
	Input.action_press(action)
	var reached := await until(func(): return worker.global_position.y >= floor_y-3 if descending else worker.global_position.y <= floor_y+3)
	Input.action_release(action)
	return reached and await until(func(): return not worker.climbing and absf(worker.global_position.y-floor_y)<1,120)

func run() -> void:
	Engine.time_scale = 2.0
	Engine.physics_ticks_per_second = 120
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(2,{"environment":"ash_foundry","build_type":"bastion","position":"center"})
	game.rounds.running = false
	game.medic.set_physics_process(false)
	p1 = game.players[0]
	p2 = game.players[1]
	ladder = game.ladders[0]
	await frames(6)
	check(get_nodes_in_group("ladder_passages").size()>=2,"Scenario creates physical passages at the roof and inhabited-floor transitions")
	# The first roof ascent begins from the normal spawn and walks to the shaft.
	Input.action_press("p1_left")
	var walked := await until(func(): return p1.global_position.x<=ladder.get_center().x+2)
	Input.action_release("p1_left")
	check(walked and absf(p1.global_position.y-430)<1,"Normal walking reaches the shaft without falling through the closed floor cover")
	check(await climb_to(p1,245),"Up input opens the roof hatch, passes through its opening and lands on the closed cover")
	check(floor_supported(p1) and p1.collision_mask==1,"Roof exit restores terrain collisions only after real support is present")
	await frames(40)
	check(absf(p1.global_position.y-245)<1,"Standing on the roof passage remains stable after the climb finishes")
	check(await climb_to(p1,430),"Down input crosses the roof opening and release at the next floor safely closes that cover")
	check(floor_supported(p1) and not p1.climbing,"Releasing input near an intermediate floor restores supported standing")
	check(await climb_to(p1,635),"Descending from the room crosses its floor opening to the raw mining gallery")
	Input.action_press("p1_up")
	var below_floor := await until(func(): return p1.global_position.y<=460)
	Input.action_release("p1_up")
	Input.action_press("p1_right")
	var side_exit := await until(func(): return not p1.climbing and p1.global_position.x>ladder.get_center().x+38,150)
	Input.action_release("p1_right")
	check(below_floor and side_exit and absf(p1.global_position.y-430)<1,"Side exit from an open floor passage waits for support before walking onto the deck")
	# Mid-shaft release and free side exit retain the previous gravity behavior.
	place(p1,Vector2(ladder.get_center().x,340),true)
	await frames(30)
	check(p1.climbing and absf(p1.global_position.y-340)<0.01,"Releasing both axes midway holds the ladder without moving a floor hatch")
	Input.action_press("p1_right")
	await frames(18)
	Input.action_release("p1_right")
	var landed := await until(func(): return not p1.climbing and absf(p1.global_position.y-430)<1,150)
	check(landed and p1.collision_mask==1,"A side exit between floors still falls naturally onto the real room floor")
	# A standing partner has priority over an automatic hatch opening.
	place(p1,Vector2(ladder.get_center().x,335),true)
	place(p2,Vector2(ladder.get_center().x,245))
	await frames(20)
	Input.action_press("p1_up")
	await frames(120)
	check(p1.climbing and p1.global_position.y>275,"An occupied closed hatch stops upward motion before the climber clips through it")
	check(absf(p2.global_position.y-245)<1 and not p2.climbing and floor_supported(p2),"The standing coop partner keeps physical support while the climber waits")
	Input.action_press("p2_right")
	var vacated := await until(func(): return p2.global_position.x>ladder.get_center().x+65,150)
	Input.action_release("p2_right")
	var resumed := await until(func(): return p1.global_position.y<=245 and not p1.climbing,220)
	Input.action_release("p1_up")
	check(vacated and resumed,"The same held climb resumes automatically when the partner leaves the hatch")
	await frames(20)
	check(absf(p1.global_position.y-245)<1 and floor_supported(p1),"The formerly blocked climber finishes with a closed, load-bearing roof cover")
	# Both characters may actively use one opening without one being dropped.
	place(p1,Vector2(ladder.get_center().x,335),true)
	place(p2,Vector2(ladder.get_center().x,245))
	await frames(20)
	Input.action_press("p1_up")
	Input.action_press("p2_down")
	var crossed := await until(func(): return p2.global_position.y>=425,300)
	Input.action_release("p2_down")
	var upper_exit := await until(func(): return not p1.climbing and absf(p1.global_position.y-245)<1,180)
	Input.action_release("p1_up")
	var lower_exit := await until(func(): return not p2.climbing and absf(p2.global_position.y-430)<1,180)
	check(crossed and upper_exit and lower_exit,"Opposite coop climbs share a passage and independently finish on their destination floors")
	check(floor_supported(p1) and floor_supported(p2),"Both coop destinations retain physical support after opposing traversal")
	place(p2,Vector2(game.scenario_bunker.core_x+90,430))
	place(p1,Vector2(ladder.get_center().x,335),true)
	Input.action_press("p1_up")
	var jump_approach := await until(func(): return p1.global_position.y<=280,180)
	Input.action_release("p1_up")
	await physics_frame
	Input.action_press("p1_jump")
	await frames(2)
	Input.action_release("p1_jump")
	var jumped := await until(func(): return not p1.climbing and p1.velocity.y< -100,150)
	check(jump_approach and jumped,"A short jump press while crossing the roof waits for hatch closure and still launches afterward")
	check(not p1._passage_jump_exit and p1.collision_mask==1,"The deferred jump is consumed once and restores ordinary terrain collision")
	check(await until(func(): return not p1.climbing and absf(p1.global_position.y-245)<1 and p1.velocity.y>=0,180),"The jump returns naturally to the closed roof cover")
	# New scenario is an explicit rescue fixture: an injured solo worker is
	# placed in the raw gallery; SAN-1 receives no route or position overrides.
	release_inputs()
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Coop fixture cleans up before the separate solo rescue scenario")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1,{"environment":"ash_foundry","build_type":"workshop","position":"right"})
	game.rounds.running = false
	p1 = game.players[0]
	ladder = game.ladders[0]
	place(p1,Vector2(ladder.get_center().x+50,635))
	await frames(8)
	p1.take_damage(45,Vector2.RIGHT)
	var medic: FieldMedic = game.medic
	var saw_climb := false
	var healed := false
	for _i in 1800:
		await physics_frame
		saw_climb = saw_climb or medic.climbing
		if medic.treatments_completed>0:
			healed = true
			break
	check(saw_climb and healed,"SAN-1 independently routes through the floor passage and treats a solo worker in the lower gallery")
	check(not p1.medical.fractured and p1.medical.bleeding==0 and medic.medical_supplies==MedicalCatalog.MAX_CHARGES-1,"The rescue completes normal treatment with exactly one real medical charge")
	var returned := await until(func(): return medic.global_position.distance_to(medic._home())<10 and not medic.climbing,1300)
	check(returned and absf(medic.global_position.y-430)<1,"SAN-1 climbs back through the hatch and walks to its ordinary home station")
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Scene and audio retire without leaked passage or actor references")
	release_inputs()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	print("PASSAGE MOTION RESULT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
