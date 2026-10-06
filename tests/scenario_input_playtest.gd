extends SceneTree
## Starts a normal solo scenario. All movement, cargo, construction, mining and
## production below use InputMap actions, finite world stock and real timers.
## No actor positions, inventories, room state or campaign phase are assigned.
var game
var worker
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	print("SCENARIO INPUT %s: %s" % ["PASS" if value else "FAIL",label])
	if not value:
		failures += 1
		push_error(label)

func frames(count: int=4) -> void:
	for i in count:
		await physics_frame

func wait_for(predicate: Callable,limit: int=600) -> bool:
	for i in limit:
		await physics_frame
		if predicate.call():
			return true
	return false

func hold_until(action: String,predicate: Callable,limit: int=600) -> bool:
	Input.action_press(action)
	var reached := await wait_for(predicate,limit)
	Input.action_release(action)
	await frames()
	return reached

func walk_to(x: float) -> bool:
	var direction := 1.0 if x>worker.global_position.x else -1.0
	var reached := await hold_until("p1_right" if direction>0 else "p1_left",func(): return (x-worker.global_position.x)*direction<=3.0,600)
	return reached and absf(worker.global_position.x-x)<18

func climb_to(y: float) -> bool:
	var direction := 1.0 if y>worker.global_position.y else -1.0
	var reached := await hold_until("p1_down" if direction>0 else "p1_up",func(): return (y-worker.global_position.y)*direction<=3.0,600)
	# The new retracting floor cover needs its real closing animation before
	# ladder mode hands the worker back to a supported standing pose.
	var landed := await wait_for(func(): return not worker.climbing and worker.collision_mask==1,90)
	return reached and landed and absf(worker.global_position.y-y)<2

func choose(target: Node) -> bool:
	await frames()
	if not game.valid_focus(worker,target):
		return false
	for i in 16:
		if worker.focus==target:
			return true
		Input.action_press("p1_cycle_target")
		await frames(2)
		Input.action_release("p1_cycle_target")
		await frames(2)
	return false

func supply(kind: String):
	for node in get_nodes_in_group("supplies"):
		if node.kind==kind:
			return node
	return null

func choose_material(kind: String) -> bool:
	for index in 12:
		if worker.selected_material()==kind:
			return true
		Input.action_press("p1_cycle_material")
		await frames(2)
		Input.action_release("p1_cycle_material")
		await frames(2)
	return false

func store_cargo(kind: String) -> bool:
	var crate=supply(kind)
	if int(worker.inventory.get(kind,0))==0:
		return true
	if not await walk_to(crate.global_position.x) or not await choose(crate) or not await choose_material(kind):
		return false
	return await hold_until("p1_craft_next",func(): return int(worker.inventory.get(kind,0))==0,300)

func clear_earth(field: DiggableTerrain) -> bool:
	for column in int(field.bounds.size.x/DiggableTerrain.CELL):
		# Take out the floor-height face, step into that opening, then dig upward.
		# All three rows remain within the same tool's physical 88px reach.
		if not await walk_to(field.bounds.position.x+column*48-18):
			return false
		for row in [2,1,0]:
			var cell:=Vector2i(column,row)
			var block=field.cell_at(cell)
			if not is_instance_valid(block):
				continue
			if row<2 and not await walk_to(block.global_position.x):
				return false
			if not await choose(block):
				print("UNREACHABLE CELL ",column,",",row," at ",worker.global_position)
				return false
			if not await hold_until("p1_interact",func(): return field.cell_at(cell)==null,240):
				return false
		print("SCENARIO INPUT excavated column ",column+1,"/10; remaining ",field.remaining_count())
	return field.is_cleared()

func recovered_materials() -> Dictionary:
	var amounts: Dictionary={}
	for kind:String in ["ore","sand"]:
		amounts[kind]=int(worker.inventory.get(kind,0))
	for pile in get_nodes_in_group("pickups"):
		if pile.kind in amounts and not pile.is_queued_for_deletion():
			amounts[pile.kind]+=pile.amount
	return amounts

func ore_pile():
	var best
	var nearest:=INF
	for pile in get_nodes_in_group("pickups"):
		if pile.kind!="ore" or pile.amount<=0 or pile.is_queued_for_deletion():
			continue
		var distance:float=pile.global_position.distance_squared_to(worker.global_position)
		if distance<nearest:
			best=pile
			nearest=distance
	return best

func screenshot(path: String) -> void:
	if DisplayServer.get_name()=="headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	# Twice the wall-clock speed, with a doubled physics rate to retain the
	# normal movement step. Campaign and construction clocks continue normally.
	Engine.time_scale=2.0
	Engine.physics_ticks_per_second=120
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(1,{"build_type":"bastion","position":"left","environment":"ash_foundry"})
	worker=game.players[0]
	await frames(5)
	var bunker: ScenarioBunker=game.scenario_bunker
	var site: ScenarioRoomSite=bunker.modules[0]
	var steel=supply("steel")
	var concrete=supply("concrete")
	var initial_steel: int=steel.amount
	var initial_concrete: int=concrete.amount
	var initial_hp: float=game.core.max_hp
	var ladder_x: float=game.ladders[0].get_center().x
	check(worker.inventory.is_empty() and game.players.size()==1 and bunker.built_rooms==1,"Normal solo start has empty hands, one inhabited room and the live preparation clock")
	check(await walk_to(ladder_x) and absf(worker.global_position.y-430)<2,"Worker reaches the starting-room ladder by walking from the normal spawn")
	check(await climb_to(245),"Up input climbs the real ladder and exits safely on the roof")
	check(await walk_to(steel.global_position.x) and await choose(steel),"The finite steel crate can be selected from the reachable roof")
	check(await hold_until("p1_interact",func(): return int(worker.inventory.get("steel",0))>=3,180),"Held interaction collects three steel bars")
	check(worker.inventory.get("steel",0)==3 and steel.amount==initial_steel-3,"The first trip takes exactly three real bars from the initial stock")
	check(await walk_to(ladder_x) and await climb_to(635),"The carried steel reaches the actual raw excavation through the continuous shaft")
	check(await walk_to(site.global_position.x) and await choose(site),"The unfinished room's survey panel remains inspectable beside the earth")
	Input.action_press("p1_interact")
	await frames(45)
	Input.action_release("p1_interact")
	await frames()
	check(site.materials.is_empty() and site.support_materials.is_empty() and worker.inventory.get("steel",0)==3,"Trying the build panel before excavation consumes no steel and starts no construction")
	var field:DiggableTerrain=bunker.fields[0]
	check(field.remaining_count()==30 and site.prompt(worker).contains(LocaleText.text("AUSHUB")),"The future room starts as thirty real cells and explains digging before construction")
	var expected:Dictionary={"ore":0,"sand":0}
	for deposit:Dictionary in field.resource_map.values():
		expected[deposit.kind]+=int(deposit.yield)
	var excavated:=await clear_earth(field)
	check(excavated,"Normal walking and held tools remove all thirty cells from bottom to top")
	if not excavated:
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
		quit(1)
		return
	await frames(10)
	check(recovered_materials()==expected and worker.carried_count()<=worker.capacity(),"Every mined resource is conserved in the worker inventory or real overflow piles")
	check(not get_nodes_in_group("pickups").is_empty() and not site.supported and not site.built,"A full worker leaves recoverable material behind and empty earth does not become a finished room")
	await screenshot("res://artifacts/scenario-input-excavated.png")
	check(await walk_to(site.global_position.x) and await choose(site),"The worker can walk back across the excavation to its support panel")
	check(await hold_until("p1_interact",func(): return site.supported,500),"Held input pays two steel and performs the complete support assembly")
	check(site.support_materials=={"steel":2} and site.materials.is_empty() and worker.inventory.get("steel",0)==1,"Installed supports own exactly two steel and preserve the last bar for fitting the room")
	check(await hold_until("p1_interact",func(): return int(site.materials.get("steel",0))==1,180),"The next held interaction pays the remaining room steel separately")
	check(site.materials=={"steel":1} and not site.curing and not site.built,"Paid steel alone cannot fit out the room without concrete")
	await screenshot("res://artifacts/scenario-input-supported.png")
	check(await walk_to(ladder_x) and await climb_to(245),"The unfinished but supported room preserves the escape route back to the roof")
	var ore_crate=supply("ore")
	var sand_crate=supply("sand")
	var ore_before:int=ore_crate.amount
	var sand_before:int=sand_crate.amount
	var carried_ore:int=int(worker.inventory.get("ore",0))
	var carried_sand:int=int(worker.inventory.get("sand",0))
	check(await store_cargo("ore") and await store_cargo("sand"),"The first recovered ore and soil can be stored through material selection and the actual deposit control")
	check(worker.inventory.is_empty() and ore_crate.amount==ore_before+carried_ore and sand_crate.amount==sand_before+carried_sand,"Storing excavation cargo frees the carrying slots without deleting its resource yield")
	check(await walk_to(concrete.global_position.x) and await choose(concrete),"After storing the mined cargo, the worker reaches the actual concrete crate")
	check(await hold_until("p1_interact",func(): return int(worker.inventory.get("concrete",0))>=4,240),"Held interaction collects four concrete units within carrying capacity")
	check(worker.inventory.get("concrete",0)==4 and concrete.amount==initial_concrete-4,"The second trip consumes exactly four finite concrete units")
	check(await walk_to(ladder_x) and await climb_to(635) and await walk_to(site.global_position.x) and await choose(site),"Concrete reaches the excavated floor through normal walking and climbing")
	check(await hold_until("p1_interact",func(): return site.curing,600),"One continuous held interaction pays concrete and completes assembly")
	check(site.support_materials=={"steel":2} and site.materials=={"steel":1,"concrete":4} and worker.carried_count()==0 and bunker.built_rooms==1,"The original seven-unit price is split between supports and fitting while concrete cures")
	await screenshot("res://artifacts/scenario-input-curing.png")
	check(await wait_for(func(): return site.built,650),"The live construction clock finishes the first room without direct state changes")
	check(bunker.built_rooms==2 and game.core.max_hp==initial_hp+40,"The completed room awards its structural benefit once")
	var press
	for station in get_nodes_in_group("stations"):
		if station.kind=="ammo_press": press=station
	check(is_instance_valid(press) and await walk_to(press.global_position.x) and await choose(press),"The paid ammunition press is reachable inside the newly fitted room")
	check(field.is_cleared() and absf(worker.global_position.y-635)<2,"Fitting preserves the excavated room and never creates replacement ore inside its walls")
	await screenshot("res://artifacts/scenario-input-room.png")
	# The ore earned during excavation remains useful after the room is fitted.
	var ore=ore_pile()
	check(is_instance_valid(ore) and await walk_to(ore.global_position.x) and await choose(ore),"An excavation overflow pile remains reachable after room construction")
	check(await hold_until("p1_interact",func(): return int(worker.inventory.get("ore",0))>=2,180),"Recovered excavation ore can be picked up through the normal contextual input")
	var recovered_ore:int=int(worker.inventory.get("ore",0))
	check(await walk_to(ladder_x) and await climb_to(430),"Ore is carried upstairs using the same physical shaft")
	var furnace
	for station in get_nodes_in_group("stations"):
		if station.kind=="furnace": furnace=station
	check(await walk_to(furnace.global_position.x) and await choose(furnace),"Carried ore targets the original furnace without mining interference")
	check(await hold_until("p1_interact",func(): return furnace.working,240),"The furnace consumes its actual recipe through held input")
	var paid_ore: int=int(furnace.recipe().inputs.ore)
	check(worker.inventory.get("ore",0)==recovered_ore-paid_ore,"Only the furnace's displayed ore cost leaves the player's inventory")
	check(await wait_for(func(): return furnace.output_amount>0,1000),"The real furnace timer produces transportable steel")
	check(await hold_until("p1_interact",func(): return int(worker.inventory.get("steel",0))==int(furnace.recipe().amount),240),"Fresh steel is collected through the same contextual input")
	check(furnace.output_amount==0 and worker.carried_count()<=worker.capacity(),"Production and collection preserve capacity without duplicating output")
	check(game.rounds.running and worker.can_act(),"The regular round and player remain active after the full excavation, construction and production route")
	await screenshot("res://artifacts/scenario-input-steel.png")
	print("SCENARIO INPUT RESULT: %d checks, %d failures; wave %d, phase %s, %.1f phase seconds remain" % [checks,failures,game.rounds.wave,game.rounds.phase,game.rounds.time_left])
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	Engine.time_scale=1.0
	Engine.physics_ticks_per_second=60
	quit(1 if failures else 0)
