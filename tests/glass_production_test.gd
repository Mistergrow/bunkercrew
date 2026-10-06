extends SceneTree
## Real workers, mine tiles and two-input glass production, including shared use.

class TestGame extends Node2D:
	var started := false
	var upgrades
	var focus
	var ladders: Array[Rect2] = []
	var pickups: Array = []
	func get_focus(_player): return focus if is_instance_valid(focus) else null
	func fx(_pos,_color,_count): pass
	func sound(_kind): pass
	func notify(_message): pass
	func spawn_pickup(kind,amount,pos): pickups.append([kind,amount,pos])

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(value: bool,label: String) -> void:
	checks += 1
	if value: print("PASS ",label)
	else:
		failures += 1
		push_error(label)

func release_work(player: Worker) -> void:
	Input.action_release(player.action("interact"))
	player._update_interaction(0.016)

func work_tick(player: Worker,delta: float = 0.31) -> void:
	Input.action_press(player.action("interact"))
	player._update_interaction(delta)

func run_checks() -> void:
	InputSetup.install()
	var game := TestGame.new()
	root.add_child(game)
	game.upgrades = UpgradeSystem.new()
	game.add_child(game.upgrades)
	var players: Array[Worker] = []
	for id in [1,2]:
		var worker: Worker = load("res://scenes/player.tscn").instantiate()
		worker.player_id=id
		worker.game=game
		worker.position=Vector2(340+(id-1)*90,600)
		game.add_child(worker)
		worker.set_physics_process(false)
		players.append(worker)
	var p1 := players[0]
	var p2 := players[1]
	var block: MineBlock = load("res://scenes/mine_block.tscn").instantiate()
	block.kind="limestone"
	block.game=game
	block.position=Vector2(400,576)
	game.add_child(block)
	game.focus=block
	await physics_frame
	await physics_frame
	work_tick(p1,0.5)
	check(block.mining>0 and p1.carried_count()==0, "Limestone uses the held mining progress instead of instant free resources")
	work_tick(p1,Balance.MINE_TIME)
	check(p1.inventory.get("limestone",0)==Balance.MINE_YIELD and block.is_queued_for_deletion(), "Mining real limestone creates transportable Kalk")
	release_work(p1)
	await physics_frame
	var furnace: GlassFurnace = load("res://scenes/glass_furnace.tscn").instantiate()
	furnace.game=game
	furnace.position=Vector2(400,600)
	game.add_child(furnace)
	furnace.set_process(false)
	furnace.binder=0
	game.focus=furnace
	check(furnace.kind=="glass" and furnace.input_kinds()==["sand","limestone"] and furnace.output_kind()=="glass", "Glass furnace advertises both accepted ingredients through the station interface")
	check(is_equal_approx(furnace.duration(),7.0), "Glass production time comes from the seven-second recipe setting")
	p1.add_item("sand",3)
	p1.selected_kind="limestone"
	work_tick(p1,0.2)
	check(furnace.limestone_amount==0 and p1.inventory.limestone==3 and furnace.interaction_progress(p1)>0, "Filling requires a held transfer and displays its progress")
	work_tick(p1,0.12)
	check(furnace.limestone_amount==1 and p1.inventory.limestone==2 and furnace.input_amount==0, "Selected Kalk is deposited independently into its own buffer")
	furnace._process(14.0)
	check(not furnace.working and furnace.limestone_amount==1 and furnace.output_amount==0, "A missing sand ingredient cannot start production or consume the existing Kalk")
	p2.add_item("ore",2)
	furnace.interact(p2,1.0)
	check(p2.inventory.get("ore",0)==2 and furnace.input_amount==0 and furnace.limestone_amount==1, "Wrong materials remain with the worker and never enter the recipe")
	work_tick(p1)
	furnace._process(0)
	check(furnace.input_amount==1 and not furnace.working, "The furnace waits for both required sand units")
	work_tick(p1)
	furnace._process(0)
	check(furnace.working and furnace.input_amount==0 and furnace.limestone_amount==0 and p1.inventory.sand==1 and p1.inventory.limestone==2, "Starting a batch consumes exactly two sand and one Kalk atomically")
	check(furnace.binder==0, "Glass production requires no binder, fuel or hidden consumable")
	p2.inventory={"sand":3,"limestone":3}
	furnace.interact(p2,1.0)
	check(p2.carried_count()==6 and furnace.input_amount==0 and furnace.limestone_amount==0, "An active furnace cannot accidentally eat material for another batch")
	furnace._process(furnace.duration()-0.02)
	check(furnace.output_amount==0 and furnace.working, "Glass is unavailable until the timed batch has completed")
	furnace._process(0.03)
	check(furnace.output_amount==2 and not furnace.working, "The finished recipe creates two stored glass panels")
	furnace.interact(p2,0.31)
	check(furnace.output_amount==2 and p2.carried_count()==6, "A full inventory leaves completed glass safely inside the furnace")
	p2.take_item("sand",1)
	furnace.interact(p2,0.31)
	check(furnace.output_amount==1 and p2.inventory.glass==1 and p2.inventory.limestone==3 and p2.carried_count()==6, "Collecting one fitting panel preserves the remainder and unrelated ingredients")
	p2.take_item("sand",2)
	furnace.interact(p2,0.31)
	check(furnace.output_amount==0 and p2.inventory.glass==2, "All finished glass can be carried away through normal station interaction")
	release_work(p1)
	p1.inventory={"sand":2}
	p2.inventory={"limestone":1}
	work_tick(p1)
	work_tick(p2)
	furnace._process(0)
	check(furnace.input_amount==1 and furnace.limestone_amount==1 and not furnace.working, "Two workers can contribute different ingredients to the same batch")
	work_tick(p1)
	work_tick(p2)
	furnace._process(0)
	check(furnace.working and p1.carried_count()==0 and p2.carried_count()==0, "Cooperative filling starts one batch without double consumption")
	release_work(p1)
	release_work(p2)
	game.upgrades.owned["harness"]=true
	p2.inventory={"sand":7}
	furnace._process(furnace.duration())
	furnace.interact(p2,0.31)
	check(p2.carried_count()==8 and p2.inventory.glass==1 and furnace.output_amount==1, "Glass collection respects the upgraded eight-unit carrying capacity")
	p2.take_item("sand",2)
	var glass_pile: ResourcePickup=load("res://scenes/resource_pickup.tscn").instantiate()
	glass_pile.game=game
	glass_pile.position=p2.position+Vector2(24,0)
	glass_pile.kind="glass"
	glass_pile.amount=3
	game.add_child(glass_pile)
	glass_pile.set_physics_process(false)
	glass_pile.interact(p2,0.001)
	check(p2.carried_count()==8 and p2.inventory.glass==3 and glass_pile.amount==1, "Transportable world glass obeys capacity and retains pickup overflow")
	furnace.interact(p1,0.31)
	game.upgrades.owned["bunker_workshop"]=true
	check(is_equal_approx(furnace.duration(),5.6), "The workshop production upgrade also accelerates glass production")
	var supply: Supply=load("res://scenes/supply.tscn").instantiate()
	supply.game=game
	supply.kind="limestone"
	supply.amount=2
	supply.position=p1.position+Vector2(24,0)
	game.add_child(supply)
	supply.interact(p1,0.31)
	supply.interact(p1,0.31)
	check(supply.amount==0 and p1.inventory.limestone==2, "Kalk can also be collected from a finite supply crate")
	var limited: GlassFurnace=load("res://scenes/glass_furnace.tscn").instantiate()
	limited.game=game
	game.add_child(limited)
	limited.set_process(false)
	p1.inventory={"sand":4}
	for i in 4: limited.interact(p1,0.31)
	limited._process(10)
	check(limited.input_amount==2 and p1.inventory.sand==2 and not limited.working, "A single missing-ingredient buffer cannot absorb excess sand beyond one recipe")
	check(limited.prompt(p1).contains("Sand 2/2") and limited.prompt(p1).contains("Kalkstein 0/1"), "The selected station clearly shows both ingredient counts and the missing Kalk")
	print("GLASS PRODUCTION CHECKS: %d passed, %d failed" % [checks-failures,failures])
	game.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
