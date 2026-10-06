extends SceneTree
## Isolated real-renderer scenery callback CPU timings. This is not GPU time.
## Run with -- --no-profile-save --output=res://artifacts/shaders/baseline.json.

class WeatherProbe extends Node:
	var reduced_effects := false

class WorldProbe extends Node2D:
	var weather: WeatherProbe
	var camera: Camera2D

class MeasuredScenery extends "res://scripts/scenario_scenery.gd":
	var samples: Dictionary = {}
	func record(key: String, start: int) -> void:
		if not samples.has(key): samples[key] = []
		samples[key].append(Time.get_ticks_usec()-start)
	func _process(delta: float) -> void:
		var start := Time.get_ticks_usec()
		super._process(delta)
		record("process",start)
	func _draw_cloud_depth(layer: Node2D,depth: int) -> void:
		var start := Time.get_ticks_usec()
		super._draw_cloud_depth(layer,depth)
		record("clouds",start)
	func _draw_mist() -> void:
		var start := Time.get_ticks_usec()
		super._draw_mist()
		record("mist_smoke",start)
	func _draw_particles() -> void:
		var start := Time.get_ticks_usec()
		super._draw_particles()
		record("particles",start)
	func _draw_water() -> void:
		var start := Time.get_ticks_usec()
		super._draw_water()
		record("water",start)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("The atmosphere benchmark needs the graphical renderer")
		quit(1)
		return
	root.size = Vector2i(1440,900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 120
	var result := {"note":"CPU microseconds inside scenery update/draw callbacks; isolated 1440x900 Compatibility viewport, excludes GPU execution and unrelated game systems.","renderer":ProjectSettings.get_setting("rendering/renderer/rendering_method"),"cases":{}}
	for environment in ["sector07","abandoned_harbor","frozen_rail_yard"]:
		for wide in [false,true]:
			var world := WorldProbe.new()
			world.weather = WeatherProbe.new()
			world.camera = Camera2D.new()
			world.camera.position = Vector2(720,740 if wide else 450)
			world.camera.zoom = Vector2.ONE*(.48 if wide else 1.0)
			world.add_child(world.weather)
			world.add_child(world.camera)
			root.add_child(world)
			var scenery := MeasuredScenery.new()
			scenery.game = world
			scenery.environment_id = environment
			world.add_child(scenery)
			for frame in 24: await RenderingServer.frame_post_draw
			scenery.samples.clear()
			for frame in 180: await RenderingServer.frame_post_draw
			var summary := {}
			for key: String in scenery.samples:
				var samples: Array = scenery.samples[key]
				samples.sort()
				var sum := 0.0
				for sample in samples: sum += sample
				summary[key] = {"mean_us":snappedf(sum/samples.size(),.01),"p95_us":samples[int(samples.size()*.95)],"samples":samples.size()}
			var label: String = environment+("_wide" if wide else "_normal")
			result.cases[label] = summary
			print("ATMOSPHERE BENCHMARK ",label,": ",JSON.stringify(summary))
			await preload("res://tests/scene_cleanup.gd").free_scene(world,self)
	var destination := "res://artifacts/shaders/atmosphere-cpu.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): destination = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir()))
	var file := FileAccess.open(destination,FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	quit()
