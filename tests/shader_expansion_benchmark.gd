extends SceneTree
## Paired frame intervals with just the three new shaders toggled, at native QHD.
const OUTPUT := "res://artifacts/shader-expansion"
const WARMUP := 90
const FRAMES := 240
const STATIONS := ["station", "glass_furnace", "alloy_furnace", "ammo_press"]
var machines: Array[Node2D] = []
var stations: Array[Node2D] = []

func _initialize() -> void: run.call_deferred()

func summarize(samples: Array[float]) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for sample in sorted: total += sample
	return {"mean_ms":snappedf(total/sorted.size(),.001),"p50_ms":snappedf(sorted[floori(sorted.size()/2.0)],.001),"p95_ms":snappedf(sorted[int(sorted.size()*.95)],.001),"max_ms":snappedf(sorted[-1],.001)}

func advance(game: Node2D, enabled: bool) -> void:
	game.scenery._process(1.0/60.0)
	for machine in machines:
		machine.age += 1.0/60.0
		if machine is SiegeMachine:
			machine.gait += 4.0/60.0
			machine.moving = true
		machine._pose_parts()
	for station in stations:
		station.elapsed += 1.0/60.0
		if enabled: station.get_node("MaterialEffects")._refresh()
		station.queue_redraw()

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Use a native QHD desktop and --no-profile-save")
		quit(1)
		return
	root.mode = Window.MODE_FULLSCREEN
	var captured_size := Vector2i.ZERO
	for frame in 120:
		await RenderingServer.frame_post_draw
		captured_size = root.get_texture().get_image().get_size()
		if captured_size==Vector2i(2560,1440): break
	if captured_size!=Vector2i(2560,1440):
		push_error("Native viewport is not 2560x1440")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var result := {"note":"Paired actual frame intervals; 18 animated enemies and four active production machines, full weather, frozen combat/player movement. Only new world lighting and station materials toggle. Three alternating off/on pairs per case, 90 warmup + 240 sampled frames per pass. VSync and FPS cap disabled. Includes presentation, not isolated GPU time.","godot":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"processor":OS.get_processor_name(),"viewport":[captured_size.x,captured_size.y],"resolution_verified_by":"Fullscreen viewport texture readback before warmup","cases":{}}
	for environment in ["ash_foundry","abandoned_harbor","overgrown_steelworks"]:
		var game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		game.start_scenario(2,{"environment":environment,"build_type":"bastion","position":"left"})
		game.rounds.running = false
		game.rounds.set_process(false)
		game.rounds.wave = 20
		game.camera.position = Vector2(720,450)
		game.camera.zoom = Vector2.ONE
		game.camera.reset_smoothing()
		game.set_process(false)
		game.scenery.set_process(false)
		game.weather.set_reduced_effects(false)
		game.weather.lightning_enabled = false
		game.notice_time = 0
		game.medic.set_physics_process(false)
		for worker in game.players: worker.set_physics_process(false)
		for index in EnemyCatalog.GROUND_CLASSES.size():
			var machine = game._entity("ground_infantry" if EnemyCatalog.is_human(EnemyCatalog.GROUND_CLASSES[index]) else "enemy",Vector2(890+index*37,430),{"kind":EnemyCatalog.GROUND_CLASSES[index],"wave":20})
			machine.set_physics_process(false)
			machines.append(machine)
		for index in AirEnemyCatalog.CLASS_ORDER.size():
			var machine = game._entity("air_enemy",Vector2(940+index*65,115+index%3*28),{"kind":AirEnemyCatalog.CLASS_ORDER[index],"wave":20})
			machine.set_physics_process(false)
			machines.append(machine)
		for index in STATIONS.size():
			var station = load("res://scenes/"+STATIONS[index]+".tscn").instantiate()
			if index==0: station.kind = "furnace"
			station.position = Vector2(180+index*180,690)
			station.game = game
			game.add_child(station)
			station.set_process(false)
			station.working = true
			station.production_time = station.duration()*.4
			stations.append(station)
		for frame in 5: await process_frame
		for station in stations: station.get_node("MaterialEffects").set_process(false)
		var passes: Array[Dictionary] = []
		for pass_index in 6:
			var enabled: bool = [false,true,true,false,false,true][pass_index]
			game.scenery.elapsed = 37.5
			game.scenery.lighting_layer.effects_enabled = enabled
			for station in stations:
				station.elapsed = 0
				if not enabled: station.material = null
			for frame in WARMUP:
				advance(game,enabled)
				await RenderingServer.frame_post_draw
			var samples: Array[float] = []
			var draw_calls: Array[float] = []
			var previous := Time.get_ticks_usec()
			for frame in FRAMES:
				advance(game,enabled)
				await RenderingServer.frame_post_draw
				var now := Time.get_ticks_usec()
				samples.append(float(now-previous)/1000.0)
				draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
				previous = now
			var draw_sum := 0.0
			for count in draw_calls: draw_sum += count
			var pass_data := {"enabled":enabled,"frames":FRAMES,"frame_intervals":summarize(samples),"mean_draw_calls":snappedf(draw_sum/draw_calls.size(),.1)}
			passes.append(pass_data)
			print("SHADER FRAME BENCHMARK ",environment," ",pass_index,": ",JSON.stringify(pass_data))
		result.cases[environment] = {"enemies":machines.size(),"production_machines":stations.size(),"passes":passes}
		root.get_texture().get_image().save_png(OUTPUT+"/"+environment+"-qhd.png")
		machines.clear()
		stations.clear()
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	var file := FileAccess.open(OUTPUT+"/performance.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	quit()
