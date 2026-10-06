extends SceneTree
## Invalid construction controls must fail before freezing or changing the world.
const WORLD := preload("res://scripts/network_world.gd")
const CLEANUP := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.start_scenario(2, {"environment":"sector07", "build_type":"workshop", "position":"left"})
	var world := WORLD.new()
	world.bind(game)
	var snapshot := world.capture()
	var original_wave: int = game.rounds.wave
	var original_stage: int = game.view_stage
	var original_rooms: int = game.scenario_bunker.open_depths
	var original_processing: bool = game.is_processing()
	for invalid in [[], {}, Vector2.ONE, "false", 0, 1, null]:
		var packet: Dictionary = snapshot.duplicate(true)
		packet.structure.dome_available = invalid
		packet.structure.wave = 2
		packet.structure.view_stage = 2
		check(not world.apply(packet), "Malformed dome flag rejects the entire snapshot")
		check(not world.last_error.is_empty(), "Rejected construction controls report an error")
		check(game.rounds.wave == original_wave and game.view_stage == original_stage and game.scenario_bunker.open_depths == original_rooms, "Invalid dome flag cannot partially change the wave, view, or rooms")
		check(game.is_processing() == original_processing and not world.client, "Invalid dome flag cannot freeze the world before rejection")
	var missing: Dictionary = snapshot.duplicate(true)
	missing.structure.erase("dome_available")
	check(not world.apply(missing), "Required dome construction flag cannot be omitted")
	check(world.apply(snapshot), "Valid boolean construction state still applies after rejected frames")
	check(world.last_error.is_empty() and world.client, "Valid state activates the presentation-only replica")
	check(await CLEANUP.free_scene(game, self), "Validation scene releases cleanly")
	print("NETWORK STRUCTURE VALIDATION: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
