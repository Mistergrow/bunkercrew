extends SceneTree
## Real QHD frame intervals with 18 animated machines. The scene is arranged;
## enemy combat and player movement are frozen, while weather remains active.
const WARMUP := 60
const FRAMES := 240
var machines: Array[Node2D] = []

func _initialize() -> void: run.call_deferred()

func summarize(samples: Array[float]) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for sample in sorted: total += sample
	return {"mean_ms":snappedf(total/sorted.size(),.001),"p50_ms":snappedf(sorted[floori(sorted.size()/2.0)],.001),"p95_ms":snappedf(sorted[int(sorted.size()*.95)],.001),"max_ms":snappedf(sorted[-1],.001)}

func pose_machines(delta: float) -> void:
	for machine in machines:
		machine.age += delta
		if machine is SiegeMachine:
			machine.gait += delta*4.0
			machine.moving = true
		machine._pose_parts()

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("The frame benchmark requires the graphical renderer")
		quit(1)
		return
	root.mode = Window.MODE_FULLSCREEN
	var captured_size := Vector2i.ZERO
	for frame in 120:
		await RenderingServer.frame_post_draw
		captured_size = root.get_texture().get_image().get_size()
		if captured_size==Vector2i(2560,1440): break
	if captured_size!=Vector2i(2560,1440):
		push_error("The frame benchmark requires a native 2560x1440 display")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var result := {"note":"Actual frame intervals in a prepared QHD scene; 18 machines retain animated poses, combat and player movement are frozen, full weather active. VSync and FPS cap disabled. Includes GPU presentation but is not isolated GPU time.","godot":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"processor":OS.get_processor_name(),"viewport":[captured_size.x,captured_size.y],"resolution_verified_by":"Fullscreen viewport texture readback before warmup","cases":{}}
	var fixtures: Array = [["sector07",false],["sector07",true],["frozen_rail_yard",true]]
	if "--water" in OS.get_cmdline_user_args():
		fixtures = [["abandoned_harbor",false],["abandoned_harbor",true],["flooded_power_station",false],["flooded_power_station",true]]
	for fixture in fixtures:
		var game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		game.start_scenario(2,{"environment":fixture[0],"build_type":"bastion","position":"left"})
		game.rounds.running = false
		game.rounds.set_process(false)
		game.rounds.wave = 20
		game.set_view_stage(4 if fixture[1] else 0)
		game.camera.position = Vector2(850,630) if fixture[1] else Vector2(720,450)
		game.camera.zoom = Vector2.ONE*(.48 if fixture[1] else 1.0)
		game.camera.reset_smoothing()
		game.set_process(false)
		game.scenery.elapsed = 37.5
		game.weather.set_reduced_effects(false)
		game.medic.set_physics_process(false)
		for worker in game.players: worker.set_physics_process(false)
		machines.clear()
		for index in EnemyCatalog.GROUND_CLASSES.size():
			var machine = game._entity("ground_infantry" if EnemyCatalog.is_human(EnemyCatalog.GROUND_CLASSES[index]) else "enemy",Vector2(1350+index*42,430),{"kind":EnemyCatalog.GROUND_CLASSES[index],"wave":20})
			machine.set_physics_process(false)
			machines.append(machine)
		for index in AirEnemyCatalog.CLASS_ORDER.size():
			var machine = game._entity("air_enemy",Vector2(1370+index*83,95+index%3*30),{"kind":AirEnemyCatalog.CLASS_ORDER[index],"wave":20})
			machine.set_physics_process(false)
			machines.append(machine)
		for frame in WARMUP:
			pose_machines(1.0/60.0)
			await RenderingServer.frame_post_draw
		var previous := Time.get_ticks_usec()
		var samples: Array[float] = []
		var draw_calls: Array[float] = []
		for frame in FRAMES:
			pose_machines(1.0/60.0)
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			samples.append(float(now-previous)/1000.0)
			draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			previous = now
		var label: String = str(fixture[0])+("_wide" if fixture[1] else "_normal")
		var draw_sum := 0.0
		for count in draw_calls: draw_sum += count
		result.cases[label] = {"frames":FRAMES,"machines":machines.size(),"frame_intervals":summarize(samples),"mean_draw_calls":snappedf(draw_sum/draw_calls.size(),.1)}
		print("GRAPHICS FRAME BENCHMARK ",label,": ",JSON.stringify(result.cases[label]))
		machines.clear()
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	var destination := "res://artifacts/graphics-refresh/frames.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): destination = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir()))
	var file := FileAccess.open(destination,FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	quit()
