extends SceneTree
## Selected worlds use their authored climate without altering shelter geometry.
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	print("CLIMATE %s: %s" % ["PASS" if ok else "FAIL", label])

func run() -> void:
	var dry_worlds := ["ash_foundry", "abandoned_harbor", "basalt_quarry", "overgrown_steelworks", "frozen_rail_yard", "iron_canyon"]
	for entry: Dictionary in ScenarioCatalog.environments():
		var game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		game.start_scenario(1, {"environment":entry.id, "build_type":"bastion", "position":"left"})
		game.rounds.set_process(false)
		var weather: ShiftWeather = game.weather
		weather.set_process(false)
		await physics_frame
		await process_frame
		var is_dry: bool = entry.id in dry_worlds
		check((weather.rain_strength == 0.0) == is_dry, "%s applies its own precipitation profile" % entry.id)
		check(weather.lightning_enabled == (entry.id in ["sector07", "mountain_pass"]), "%s limits lightning to storm worlds" % entry.id)
		var before := weather.contact_count
		for step in 12:
			weather._process(0.1)
		if is_dry:
			check(weather.contact_count == before, "%s creates no invisible rain impacts or wetness" % entry.id)
			weather._start_lightning()
			check(weather.bolt.is_empty() and weather.lightning_strength() == 0.0 and weather.thunder_wait < 0, "%s cannot schedule lightning or thunder" % entry.id)
		check(weather.exposure_at(Vector2(game.scenario_bunker.room_left + 300, 380)) == 0.0, "%s preserves actual bunker shelter" % entry.id)
		weather.set_reduced_effects(true)
		var stopped := weather.elapsed
		weather._process(1.0)
		check(weather.elapsed == stopped and weather.lightning_strength() == 0.0, "%s F3 stops weather motion and flashes" % entry.id)
		if not await preload("res://tests/scene_cleanup.gd").free_scene(game, self):
			failures += 1
	print("ENVIRONMENT WEATHER: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
