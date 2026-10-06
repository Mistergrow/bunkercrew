extends SceneTree
## Real station scenes, worker inventories and usable ammunition. These checks
## cover conservation when materials arrive separately or two workers share a job.

class TestGame extends Node2D:
	var started := false
	var upgrades
	var focus
	var ladders: Array[Rect2] = []
	var pickups: Array = []
	func get_focus(_player): return focus if is_instance_valid(focus) else null
	func fx(_pos, _color, _count): pass
	func sound(_kind): pass
	func notify(_message): pass
	func spawn_pickup(kind, amount, pos): pickups.append([kind, amount, pos])

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(value: bool, label: String) -> void:
	checks += 1
	if value:
		print("PASS ", label)
	else:
		failures += 1
		push_error(label)

func release_work(player: Worker) -> void:
	Input.action_release(player.action("interact"))
	player._update_interaction(0.016)

func work_tick(player: Worker, delta: float = 0.31) -> void:
	Input.action_press(player.action("interact"))
	player._update_interaction(delta)

func run_checks() -> void:
	InputSetup.install()
	var game := TestGame.new()
	root.add_child(game)
	game.upgrades = UpgradeSystem.new()
	game.add_child(game.upgrades)
	var players: Array[Worker] = []
	for id in [1, 2]:
		var worker: Worker = load("res://scenes/player.tscn").instantiate()
		worker.player_id = id
		worker.game = game
		worker.position = Vector2(340 + (id-1)*90, 600)
		game.add_child(worker)
		worker.set_physics_process(false)
		worker.get_node("WorkerWeapon").set_physics_process(false)
		players.append(worker)
	var p1 := players[0]
	var p2 := players[1]
	var block: MineBlock = load("res://scenes/mine_block.tscn").instantiate()
	block.kind = "tungsten"
	block.game = game
	block.position = Vector2(400, 576)
	game.add_child(block)
	game.focus = block
	await physics_frame
	await physics_frame
	work_tick(p1, Balance.MINE_TIME)
	check(block.is_queued_for_deletion() and p1.inventory.get("tungsten", 0) == Balance.MINE_YIELD, "A real deep-mine tungsten tile yields carried Wolframerz through held mining")
	release_work(p1)
	await physics_frame
	check(p1.selected_material() == "tungsten" and Worker.MATERIAL_ORDER.has("alloy"), "Both deep materials participate in explicit inventory selection")

	var alloy: DeepProductionStation = load("res://scenes/alloy_furnace.tscn").instantiate()
	alloy.game = game
	alloy.position = Vector2(400, 600)
	game.add_child(alloy)
	alloy.set_process(false)
	alloy.binder = 0
	game.focus = alloy
	check(alloy.kind == "alloy" and alloy.input_kinds() == ["tungsten", "steel"] and alloy.output_kind() == "alloy", "The alloy scene exposes both distinct ingredients and Panzerstahl output")
	check(is_equal_approx(alloy.duration(), 8.0), "The alloy batch uses the central eight-second recipe")
	work_tick(p1, 0.15)
	check(alloy.input_amount == 0 and alloy.interaction_progress(p1) > 0, "A tap cannot bypass the held transfer timer")
	work_tick(p1, 0.16)
	work_tick(p1)
	work_tick(p1)
	check(alloy.input_amount == 2 and p1.inventory.get("tungsten", 0) == 1, "The ore buffer accepts exactly one batch and leaves spare ore with its worker")
	alloy._process(10)
	check(not alloy.working and alloy.input_amount == 2 and alloy.output_amount == 0, "Missing steel cannot consume the stored tungsten or create output")
	p2.inventory = {"ore": 2, "scrap": 2}
	alloy.interact(p2, 1.0)
	check(p2.carried_count() == 4 and alloy.amount_for("steel") == 0, "Raw iron and scrap cannot substitute for refined steel in the alloy recipe")
	p2.inventory = {"steel": 2}
	work_tick(p2)
	check(alloy.amount_for("steel") == 1 and p2.inventory.steel == 1, "A second worker can contribute the separate steel ingredient")
	alloy._process(0)
	check(alloy.working and alloy.input_amount == 0 and alloy.amount_for("steel") == 0 and alloy.binder == 0, "Starting consumes exactly two tungsten and one steel, without binder or fuel")
	work_tick(p1)
	work_tick(p2)
	check(p1.inventory.tungsten == 1 and p2.inventory.steel == 1, "An active alloy batch does not take extra inputs from either worker")
	alloy._process(7.99)
	check(alloy.working and alloy.output_amount == 0, "Alloy remains unavailable until its production time has elapsed")
	alloy._process(0.02)
	check(not alloy.working and alloy.output_amount == 2, "A completed batch retains two armor plates for collection")
	p2.inventory = {"sand": 6}
	alloy.interact(p2, 0.31)
	check(alloy.output_amount == 2 and p2.carried_count() == 6, "A full worker cannot discard completed alloy")
	p2.take_item("sand", 1)
	alloy.interact(p2, 0.31)
	check(alloy.output_amount == 1 and p2.inventory.alloy == 1 and p2.carried_count() == 6, "One fitting armor plate transfers while the second stays in its station")
	p1.inventory = {}
	alloy.interact(p1, 0.31)
	check(p1.inventory.alloy == 1 and alloy.output_amount == 0, "Cooperative output collection cannot duplicate or lose an armor plate")
	release_work(p1)
	release_work(p2)

	var press: DeepProductionStation = load("res://scenes/ammo_press.tscn").instantiate()
	press.game = game
	press.position = Vector2(400, 600)
	game.add_child(press)
	press.set_process(false)
	game.focus = press
	check(press.kind == "ammo_press" and press.input_kinds() == ["steel"] and press.output_kind() == "ammo" and is_equal_approx(press.duration(), 6.0), "The press scene advertises two steel to two ammo boxes in six seconds")
	p1.inventory = {"scrap": 2, "alloy": 2}
	work_tick(p1)
	check(p1.carried_count() == 4 and press.input_amount == 0, "The press preserves wrong materials instead of treating all metals as steel")
	p1.inventory = {"steel": 1}
	p2.inventory = {"steel": 1}
	work_tick(p1, 0.17)
	work_tick(p2, 0.16)
	check(press.input_amount == 0, "Two workers cannot combine partial hold timers into a free transfer")
	work_tick(p1, 0.15)
	press._process(0)
	check(press.input_amount == 1 and not press.working, "The press stores a partial recipe until the other steel unit arrives")
	work_tick(p2, 0.15)
	press._process(0)
	check(press.working and p1.carried_count() == 0 and p2.carried_count() == 0, "Cooperative steel deposits start exactly one ammunition batch")
	press._process(5.99)
	check(press.output_amount == 0, "Pressing ammunition has a real production delay")
	press._process(0.02)
	check(press.output_amount == 2 and not press.working, "The press finishes two transportable ammunition boxes")
	p1.inventory = {"steel": 2}
	press.interact(p1, 0.31)
	check(p1.inventory.ammo == 1 and p1.inventory.steel == 2 and press.input_amount == 0, "Completed ammunition is collected before another deposit, with no silent steel consumption")
	p2.inventory = {"sand": 6}
	press.interact(p2, 0.31)
	check(press.output_amount == 1, "A full second worker preserves the remaining ammo box")
	p1.take_item("steel", 2)
	var gun: WorkerWeapon = p1.get_node("WorkerWeapon")
	gun.loaded = {"rifle": 0, "shotgun": 0, "arcgun": 0}
	gun.reserve = 0
	check(gun.start_reload() and p1.carried_count() == 0 and gun.reserve == 20, "A freshly produced ammo box replenishes the real handheld weapon by twenty rounds")
	game.started = true
	gun._physics_process(1.1)
	game.started = false
	check(gun.current_ammo() == 20 and gun.reserve == 0, "The normal reload timer moves the crafted ammunition into the rifle")
	release_work(p1)
	release_work(p2)
	p1.inventory = {"sand": 5}
	game.upgrades.owned["harness"] = true
	press.interact(p1, 0.31)
	check(p1.carried_count() == 6 and p1.inventory.ammo == 1 and press.output_amount == 0, "The final box is still available after the other worker reloads")
	game.upgrades.owned["bunker_workshop"] = true
	check(is_equal_approx(alloy.duration(), 6.4) and is_equal_approx(press.duration(), 4.8), "The workshop upgrade accelerates both new production chains")
	check(alloy.prompt(p1).contains("Wolframerz 0/2") and alloy.prompt(p1).contains("Stahl 0/1"), "The selected alloy station states both missing ingredient amounts")
	check(press.prompt(p1).contains("2 Stahl → 2 Munition"), "The ammunition recipe is visible through the existing station prompt")
	for item in ["tungsten", "alloy"]:
		var pile: ResourcePickup = load("res://scenes/resource_pickup.tscn").instantiate()
		pile.game = game
		pile.position = p2.position + Vector2(22, 0)
		pile.kind = item
		pile.amount = 3
		game.add_child(pile)
		pile.set_physics_process(false)
		p2.inventory = {"sand": 7}
		pile.interact(p2, 0.01)
		check(p2.inventory.get(item, 0) == 1 and pile.amount == 2 and p2.carried_count() == 8, "%s loose piles preserve overflow at the upgraded carrying limit" % item)
	print("DEEP PRODUCTION CHECKS: %d passed, %d failed" % [checks-failures, failures])
	game.queue_free()
	await process_frame
	await create_timer(0.25, true, false, true).timeout
	quit(0 if failures == 0 else 1)
