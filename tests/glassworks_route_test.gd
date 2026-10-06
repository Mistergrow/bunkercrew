extends SceneTree
## Wave five's clearance is arranged. Travel, supply collection, two-ingredient
## production and recovery use real InputMap input in the actual main scene.
var game
var worker
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	print("GLASS ROUTE %s: %s" % ["PASS" if value else "FAIL",label])
	if not value:
		failures += 1
		push_error(label)

func frames(count: int=4) -> void:
	for index in count: await physics_frame

func hold(action: String,seconds: float) -> void:
	Input.action_press(action)
	await create_timer(seconds,false,true).timeout
	Input.action_release(action)
	await frames()

func walk_to(x: float) -> void:
	var direction := 1 if x>worker.position.x else -1
	var action := "p1_right" if direction>0 else "p1_left"
	Input.action_press(action)
	for index in 700:
		await physics_frame
		if (x-worker.position.x)*direction<=2.5: break
	Input.action_release(action)
	await frames()

func select(target) -> void:
	for index in 12:
		if worker.focus==target: return
		await hold("p1_cycle_target",0.025)

func run() -> void:
	Engine.time_scale = 3.0
	Engine.physics_ticks_per_second = 180
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start(2)
	game.rounds.set_process(false)
	worker = game.players[0]
	await frames()
	check(get_nodes_in_group("glass_furnaces").is_empty(),"Glassworks is absent at the beginning")
	game.rounds.wave = 5
	game.rounds._set_phase("salvage",Balance.SALVAGE_TIME)
	var kiln = game.environment_growth.glass_furnace
	check(is_instance_valid(kiln) and game.view_stage==2,"Fifth-wave clearance opens the real glassworks")
	var limestone
	var sand
	for supply in get_nodes_in_group("supplies"):
		if supply.kind=="limestone": limestone=supply
		if supply.kind=="sand" and supply.position.x>1100: sand=supply
	await walk_to(240)
	await hold("p1_down",1.2)
	check(absf(worker.position.y-600)<1,"Worker climbs from the starting floor to production using real controls")
	await walk_to(850)
	await select(limestone)
	check(worker.focus==limestone and absf(worker.position.y-600)<1,"The new limestone crate is reachable without clearing mining blocks")
	await hold("p1_interact",0.34)
	check(worker.inventory.get("limestone",0)==1 and limestone.amount==11,"Exactly one Kalk is taken from finite stock")
	await walk_to(1030)
	check(worker.focus==kiln,"A worker carrying only Kalk still selects the two-input furnace")
	await hold("p1_interact",0.34)
	check(kiln.limestone_amount==1 and not kiln.working and worker.carried_count()==0,"Limestone waits safely for sand in its own input buffer")
	await walk_to(1160)
	await select(sand)
	await hold("p1_interact",0.65)
	check(worker.inventory.get("sand",0)==2 and sand.amount==10,"Sand is carried from the far side of the accessible annex")
	await walk_to(1030)
	await hold("p1_interact",0.7)
	check(kiln.working and worker.carried_count()==0 and kiln.input_amount==0 and kiln.limestone_amount==0,"The paid two-ingredient recipe starts once through held interaction")
	check(game.players[1].inventory.is_empty() and absf(game.players[1].position.x-347)<1,"Player one's actions neither move nor fill player two")
	if DisplayServer.get_name()!="headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/glassworks-interactive.png")
	await create_timer(kiln.duration()+0.2,false,true).timeout
	await hold("p1_interact",0.7)
	check(worker.inventory.get("glass",0)==2 and kiln.output_amount==0,"Finished glass reaches the worker without duplication")
	await hold("p1_drop",0.025)
	await frames(60)
	var pile
	for candidate in get_nodes_in_group("pickups"):
		if candidate.kind=="glass": pile=candidate
	check(is_instance_valid(pile) and absf(pile.position.y-600)<2 and worker.inventory.get("glass",0)==1,"Glass can be laid safely on the new floor")
	if is_instance_valid(pile):
		await select(pile)
		await hold("p1_interact",0.025)
		check(worker.inventory.get("glass",0)==2 and not is_instance_valid(pile),"The selected glass pile is recovered beside the furnace")
	print("GLASSWORKS ROUTE: %d passed, %d failed" % [checks-failures,failures])
	game.queue_free()
	await process_frame
	await create_timer(0.25,true,false,true).timeout
	quit(1 if failures else 0)
