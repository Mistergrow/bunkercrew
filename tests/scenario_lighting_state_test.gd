extends SceneTree
## Initialization can happen while gameplay is paused and F3 is already enabled.
const Cleanup := preload("res://tests/scene_cleanup.gd")

class WeatherProbe extends Node:
	var reduced_effects := true

class WorldProbe extends Node2D:
	var weather: WeatherProbe

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("LIGHTING STATE %s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	paused = true
	for environment in ["ash_foundry", "abandoned_harbor", "basalt_quarry"]:
		var fixture := WorldProbe.new()
		fixture.weather = WeatherProbe.new()
		fixture.add_child(fixture.weather)
		root.add_child(fixture)
		var scenery := ScenarioScenery.new()
		scenery.environment_id = environment
		scenery.game = fixture
		scenery.elapsed = 3.7
		fixture.add_child(scenery)
		var lights = scenery.lighting_layer
		check(not lights.visible, "%s starts with additional light hidden when F3 was already active" % environment)
		lights.effects_enabled = false
		lights.effects_enabled = true
		check(not lights.visible, "%s enabling the layer still respects F3 while paused" % environment)
		check(lights.uniform_updates == 0, "%s paused F3 initialization uploads no light clock" % environment)
		var updates: int = lights.edge_uniform_updates
		var material_count: int = lights.emission_materials.size() + (1 if is_instance_valid(lights.shaft_material) else 0)
		check(updates == material_count, "%s initializes the panorama fade on every lighting material" % environment)
		for repeat in 20:
			lights.set_edge_fade(float(scenery.sky_material.get_shader_parameter("edge_fade")))
		check(lights.edge_uniform_updates == updates, "%s repeated unchanged fade values trigger no uniform uploads" % environment)
		lights.set_edge_fade(0.18)
		check(lights.edge_uniform_updates == updates + material_count, "%s camera edge-fade change reaches each material once" % environment)
		var correct_fade := true
		for surface in lights.emission_materials:
			correct_fade = correct_fade and is_equal_approx(float(surface.get_shader_parameter("edge_fade")), 0.18)
		if is_instance_valid(lights.shaft_material):
			correct_fade = correct_fade and is_equal_approx(float(lights.shaft_material.get_shader_parameter("edge_fade")), 0.18)
		check(correct_fade, "%s painted emitters and sky shafts use the same fade" % environment)
		await create_timer(0.03, true).timeout
		check(scenery.elapsed == 3.7 and lights.uniform_updates == 0 and not lights.visible, "%s remains frozen and hidden before its first unpaused frame" % environment)
		check(await Cleanup.free_scene(fixture, self), "%s initialization fixture releases cleanly" % environment)
	paused = false
	print("SCENARIO LIGHTING STATES: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
