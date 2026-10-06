extends SceneTree
## Exercise actual selection, physical pickup queries and allocation-free best focus.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

class Arena extends "res://scripts/game.gd":
	var ordered_searches := 0
	func _ready() -> void:
		upgrades = UpgradeSystem.new()
		add_child(upgrades)
	func focus_candidates(worker) -> Array:
		ordered_searches += 1
		return super.focus_candidates(worker)

class PileProbe extends ResourcePickup:
	var access_calls := 0
	func can_interact(worker) -> bool:
		access_calls += 1
		return super.can_interact(worker)

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func pile(game: Arena, at: Vector2) -> PileProbe:
	var result := PileProbe.new()
	result.game = game
	result.position = at
	result.kind = "ore"
	result.amount = 3
	game.add_child(result)
	result.set_process(false)
	result.set_physics_process(false)
	return result

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	InputSetup.install()
	var game := Arena.new()
	root.add_child(game)
	var workers: Array[Worker] = []
	for slot in 4:
		var worker: Worker = load("res://scenes/player.tscn").instantiate()
		worker.game = game
		worker.player_id = slot + 1
		worker.position = Vector2(100 + slot * 12, 100)
		game.add_child(worker)
		worker.set_physics_process(false)
		worker.get_node("WorkerWeapon").set_physics_process(false)
		workers.append(worker)
	var nearby: Array[PileProbe] = []
	for at in [Vector2(124, 100), Vector2(165, 100), Vector2(74, 100)]:
		nearby.append(pile(game, at))
	var distant: Array[PileProbe] = []
	for index in 320:
		distant.append(pile(game, Vector2(5000 + index * 52, 100)))
	await physics_frame
	await physics_frame
	for worker in workers:
		for direction in [-1.0, 1.0]:
			worker.facing = direction
			var candidates := game.focus_candidates(worker)
			check(not candidates.is_empty() and candidates[0] == game.get_focus(worker), "Best focus preserves the ordered candidate priority for either facing direction")
	workers[0].inventory = {"ore": workers[0].capacity()}
	check(game.get_focus(workers[0]) == null, "A full inventory has no selectable cargo")
	workers[0].inventory.clear()
	nearby[0].queue_free()
	check(game.get_focus(workers[0]) != nearby[0], "Queued cargo cannot be selected in the current tick")
	var barrier := StaticBody2D.new()
	barrier.collision_layer = 1
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(12, 80)
	collision.shape = rectangle
	barrier.position = Vector2(144, 80)
	barrier.add_child(collision)
	game.add_child(barrier)
	await physics_frame
	await physics_frame
	check(not game.valid_focus(workers[0], nearby[1]), "The cheap range gate still runs actual physical obstruction checks for nearby cargo")
	barrier.queue_free()
	await process_frame
	await physics_frame
	for target in distant:
		target.access_calls = 0
	game.ordered_searches = 0
	game.get_focus(workers[0])
	var outside_calls := 0
	for target in distant:
		outside_calls += target.access_calls
	if "--measure-only" not in OS.get_cmdline_user_args():
		check(outside_calls == 0, "Unreachable cargo is rejected before any pickup ray query")
		check(game.ordered_searches == 0, "Choosing one best target never builds or sorts the cycling list")
	var samples: Array[float] = []
	for repeat_index in 7:
		var started := Time.get_ticks_usec()
		for iteration in 300:
			game.get_focus(workers[iteration % workers.size()])
		samples.append(float(Time.get_ticks_usec() - started) / 300.0)
	samples.sort()
	var destination := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			destination = argument.trim_prefix("--output=")
	var measurement := {"median_usec_per_selection":samples[3],"samples_usec":samples,"distant_pickup_queries_per_selection":outside_calls,"workers":4,"distant_piles":320,"prepared_state":"Real Worker/ResourcePickup scenes in one physics world, nearby accessible and blocked cargo, stable ownership, held rendering/gameplay clocks; synchronous CPU selection only, no FPS claim."}
	print("FOCUS SEARCH MEASUREMENT: ", JSON.stringify(measurement))
	if not destination.is_empty():
		var file := FileAccess.open(destination, FileAccess.WRITE)
		file.store_string(JSON.stringify(measurement, "\t"))
	var tied: Array[PileProbe] = []
	for index in 20:
		tied.append(pile(game, Vector2(126, 100)))
	check(game.get_focus(workers[0]) == tied[0] and game.focus_candidates(workers[0])[0] == tied[0], "Twenty equal priorities retain the same first choice in direct selection and cycling")
	tied[0].queue_free()
	check(game.get_focus(workers[0]) == tied[1], "Removing the first tied target updates selection without a stale frame cache")
	var edge := pile(game, Vector2(183, 93))
	check(game.valid_focus(workers[0], edge), "Cargo at exactly83px remains reachable")
	edge.position.x += 0.001
	check(not game.valid_focus(workers[0], edge), "Cargo beyond83px remains outside reach")
	check(await Cleanup.free_scene(game, self), "Selection fixture retires all real workers, cargo and physics")
	print("FOCUS SEARCH PERFORMANCE: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
