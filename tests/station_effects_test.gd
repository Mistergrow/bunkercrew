extends SceneTree
## Real production nodes retain pause/F3 behavior; electric paths stay pixel-aligned
## and inside the chamber while changing between shared animation phases.
const Effects := preload("res://scripts/station_surface_art.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")

class WeatherStub extends Node:
	var reduced_effects := false

class TestGame extends Node2D:
	var weather: WeatherStub
	func sound(_kind): pass
	func fx(_position, _color, _count): pass

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func run() -> void:
	var game := TestGame.new()
	root.add_child(game)
	game.weather = WeatherStub.new()
	game.add_child(game.weather)
	var stations: Array[Node2D] = []
	for scene_path in ["res://scenes/station.tscn", "res://scenes/glass_furnace.tscn", "res://scenes/alloy_furnace.tscn"]:
		var station = load(scene_path).instantiate()
		if scene_path.ends_with("/station.tscn"):
			station.kind = "furnace"
		station.game = game
		game.add_child(station)
		station.working = true
		stations.append(station)
	await create_timer(0.06).timeout
	var elapsed_before: Array[float] = []
	for station in stations:
		check(station.elapsed > 0.0, "%s advances its real production visual clock" % station.kind)
		check(not Effects.reduced_effects(station), "%s uses full effects normally" % station.kind)
		elapsed_before.append(station.elapsed)
	paused = true
	await create_timer(0.06, true).timeout
	for index in stations.size():
		check(is_equal_approx(stations[index].elapsed, elapsed_before[index]), "%s freezes its furnace visual clock while paused" % stations[index].kind)
	game.weather.reduced_effects = true
	for station in stations:
		check(Effects.reduced_effects(station), "%s reads the game's F3 option" % station.kind)
	paused = false
	await create_timer(0.06).timeout
	for index in stations.size():
		check(stations[index].elapsed > elapsed_before[index], "%s keeps production and basic heat moving in reduced mode" % stations[index].kind)
	var chamber := Rect2(-25, -66, 43, 27)
	check(Effects.electric_paths(chamber, 1.001, false) == Effects.electric_paths(chamber, 1.030, false), "One pixel animation phase is independent of display refresh")
	var shapes := {}
	var saw_branch := false
	for phase in 96:
		var elapsed := float(phase) / Effects.EFFECT_FPS + 0.001
		var full := Effects.electric_paths(chamber, elapsed, false)
		var reduced := Effects.electric_paths(chamber, elapsed, true)
		check(reduced.size() == 1 and reduced[0].size() == 6, "Reduced effects retain one unbranched live arc")
		check(full.size() >= 1 and full.size() <= 4, "Arc bursts stay bounded and preserve visible production feedback")
		shapes[str(full)] = true
		for path in full:
			if path.size() == 3:
				saw_branch = true
			for point in path:
				check(chamber.has_point(point), "Electricity remains inside the furnace chamber")
				check(point == point.round(), "Electricity uses whole pixels at its native size")
	check(shapes.size() > 60, "Electricity changes its routes instead of repeating two straight strokes")
	check(saw_branch, "Full effects contain short secondary discharge branches")
	check(await Cleanup.free_scene(game, self), "Furnace effects release their real station fixtures cleanly")
	print("STATION EFFECT CHECKS: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
