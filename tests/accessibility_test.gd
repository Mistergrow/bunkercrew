extends SceneTree
## Regression for the blocked furnace: the actual main scene, its terrain and
## its player are traversed through InputMap movement. No tiles are removed and
## the route uses no teleports. Safe-drop cases below use explicit edge setups.

var game
var worker
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	print("ACCESS %s: %s" % ["PASS" if value else "FAIL", message])
	if not value:
		failures.append(message)
		push_error(message)

func settle(frames: int = 3) -> void:
	for _frame in frames:
		await physics_frame

func walk_to(target_x: float) -> bool:
	var direction := 1.0 if worker.position.x < target_x else -1.0
	var action_name := "p1_right" if direction > 0.0 else "p1_left"
	Input.action_press(action_name)
	for _frame in 240:
		await physics_frame
		if (target_x - worker.position.x) * direction <= 3.5:
			break
	Input.action_release(action_name)
	await settle()
	return absf(worker.position.x - target_x) <= 6.0

func descend_to(target_y: float) -> bool:
	Input.action_press("p1_down")
	for _frame in 240:
		await physics_frame
		if worker.position.y >= target_y - 0.5:
			break
	Input.action_release("p1_down")
	await settle()
	return absf(worker.position.y - target_y) < 1.0 and worker.collision_mask == 1

func tap_drop() -> void:
	Input.action_press("p1_drop")
	await settle(2)
	Input.action_release("p1_drop")
	await settle(75)

func pile_for(kind: String):
	for pile in get_nodes_in_group("pickups"):
		if pile.kind == kind and not pile.is_queued_for_deletion():
			return pile
	return null

func pile_is_clear(pile) -> bool:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(24, 22)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0, pile.global_position + Vector2(0, -12))
	query.collision_mask = 1 | 2
	return pile.get_world_2d().direct_space_state.intersect_shape(query).is_empty()

func pickup_focused() -> void:
	Input.action_press("p1_interact")
	await settle(2)
	Input.action_release("p1_interact")
	await settle()

func check_safe_drops() -> void:
	# Explicit edge setups isolate the drop-placement behavior. These teleports
	# are unrelated to the fully traversed route above.
	worker.position = Vector2(742, 245)
	worker.velocity = Vector2.ZERO
	worker.climbing = false
	worker.facing = 1.0
	worker.add_item("steel", 2)
	await settle()
	await tap_drop()
	var roof_pile = pile_for("steel")
	check(is_instance_valid(roof_pile) and int(worker.inventory.get("steel", 0)) == 1,
		"Q tap at roof edge transfers exactly one selected item")
	if is_instance_valid(roof_pile):
		check(absf(roof_pile.position.y - 245) < 2.0 and roof_pile.position.x < 738,
			"Roof-edge drop remains supported on the reachable roof")
		check(pile_is_clear(roof_pile), "Roof drop has no terrain overlap after physics settling")
		check(worker.focus == roof_pile, "Fresh roof drop is the selected nearby interaction")
		await pickup_focused()
		check(int(worker.inventory.get("steel", 0)) == 2 and not is_instance_valid(roof_pile),
			"One E tap retrieves the roof drop without losing material")
	worker.inventory.clear()
	worker.position = Vector2(290, 800)
	worker.velocity = Vector2.ZERO
	worker.climbing = false
	worker.facing = -1.0
	worker.add_item("ore", 2)
	await settle()
	await tap_drop()
	var mine_pile = pile_for("ore")
	check(is_instance_valid(mine_pile) and int(worker.inventory.get("ore", 0)) == 1,
		"Q tap beside untouched mine rock transfers exactly one item")
	if is_instance_valid(mine_pile):
		check(absf(mine_pile.position.y - 800) < 2.0 and pile_is_clear(mine_pile),
			"Drop beside mine rock settles on open floor without embedding in a tile")
		check(worker.focus == mine_pile, "Fresh mine drop remains directly selectable")
		await pickup_focused()
		check(int(worker.inventory.get("ore", 0)) == 2 and not is_instance_valid(mine_pile),
			"One E tap retrieves the mine drop instead of mining adjacent rock")

func run() -> void:
	# Accelerate wall-clock execution while retaining the normal 1/60 simulation
	# step; this still exercises CharacterBody2D collisions and ladder behavior.
	Engine.time_scale = 3.0
	Engine.physics_ticks_per_second = 180
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start(1)
	worker = game.players[0]
	await settle()
	var initial_blocks: int = get_nodes_in_group("mine_blocks").size()
	check(initial_blocks == 27, "The compact mine retains all twenty-seven blocks in its three-row resource pockets")
	check(await walk_to(240.0), "Spawn reaches the first ladder by walking")
	check(await descend_to(600.0), "Held down climbs from bunker entrance to production floor")
	check(await walk_to(342.0), "Production floor connects to the mine ladder")
	check(await descend_to(800.0), "Held down reaches the mine floor and restores terrain collision")
	check(await walk_to(660.0), "Untouched mine leaves a continuous walking route to the furnace")
	var furnace
	for station in get_nodes_in_group("stations"):
		if station.kind == "furnace":
			furnace = station
	check(is_instance_valid(furnace) and worker.focus == furnace, "Furnace is the focused interaction when reached")
	check(await walk_to(342.0), "The return route to the ladder is also unobstructed")
	check(get_nodes_in_group("mine_blocks").size() == initial_blocks, "Both journeys required no mining or removed resource blocks")
	check(worker.carried_count() == 0 and game.core.hp == Balance.CORE_HP, "Traversal leaves inventory empty and bunker core intact")
	await check_safe_drops()
	check(get_nodes_in_group("mine_blocks").size() == initial_blocks, "Picking up beside rock leaves every mine block intact")
	print("ACCESSIBILITY: %d passed, %d failed. Traversal used actual InputMap movement in the main scene." % [checks - failures.size(), failures.size()])
	await create_timer(0.3, true, false, true).timeout
	game.queue_free()
	await process_frame
	await process_frame
	# Playback releases are processed by the audio thread after the scene exits.
	await create_timer(0.25, true, false, true).timeout
	quit(0 if failures.is_empty() else 1)
