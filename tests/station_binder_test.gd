extends SceneTree
## Exhausted binder must not trap a worker's remaining sand inside a dead mixer.
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ",label)
	else:
		failures += 1
		push_error(label)

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var worker: Worker = load("res://scenes/player.tscn").instantiate()
	world.add_child(worker)
	worker.set_physics_process(false)
	var mixer := ProductionStation.new()
	world.add_child(mixer)
	mixer.set_process(false)
	mixer.binder = 0
	worker.inventory = {"sand":2}
	mixer.interact(worker,0.31)
	mixer.interact(worker,0.31)
	check(worker.inventory.get("sand",0) == 2 and mixer.input_amount == 0, "An exhausted mixer cannot consume irreplaceable incoming sand")
	mixer._process(100)
	check(not mixer.working and mixer.output_amount == 0 and mixer.binder == 0, "An exhausted mixer cannot produce a free batch")
	check(mixer.action_hint(worker).contains("aufgebraucht"), "The blocked action explains the actual binder shortage")
	mixer.input_amount = 0
	mixer.binder = 1
	worker.inventory = {"sand":2}
	mixer.interact(worker,0.31)
	mixer.interact(worker,0.31)
	mixer._process(0)
	check(mixer.working and mixer.binder == 0 and worker.carried_count() == 0, "The final paid batch consumes exactly the last binder and two sand")
	mixer._process(Balance.RECIPES.mixer.time)
	check(not mixer.working and mixer.output_amount == 2, "The last batch still completes after the binder reaches zero")
	worker.inventory = {"sand":2}
	mixer.interact(worker,0.31)
	mixer.interact(worker,0.31)
	check(worker.inventory == {"sand":2,"concrete":2} and mixer.output_amount == 0, "Completed concrete remains collectible despite depleted binder")
	mixer.interact(worker,1.0)
	check(worker.inventory == {"sand":2,"concrete":2} and mixer.input_amount == 0, "Keeping the button held cannot trap the next batch's sand")
	var furnace := ProductionStation.new()
	furnace.kind = "furnace"
	furnace.binder = 0
	world.add_child(furnace)
	furnace.set_process(false)
	worker.inventory = {"ore":2}
	furnace.interact(worker,0.31)
	furnace.interact(worker,0.31)
	furnace._process(0)
	check(furnace.working and worker.carried_count() == 0, "A recipe without binder still accepts and processes its normal ingredients")
	check(await preload("res://tests/scene_cleanup.gd").free_scene(world,self), "Mixer fixtures release cleanly")
	print("STATION BINDER CHECKS: %d passed, %d failed" % [checks-failures,failures])
	quit(0 if failures == 0 else 1)
