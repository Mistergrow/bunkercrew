extends SceneTree
## Native QHD: 18 animated machines and two walking players. Combat is held;
## feet move across physical ground with full or F3-reduced weather/effects.
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

func pose_machines(game: Node2D, delta: float) -> void:
	for worker in game.players:
		worker.velocity = Vector2(90,0)
		worker.position.x += 90*delta
		worker._airborne = false
		worker._landing_time = 0
		worker.get_node("PixelVisual")._process(delta)
		worker.wetness.advance(delta)
	for machine in machines:
		machine.age += delta
		if machine is SiegeMachine:
			machine.gait += delta*4.0
			machine.moving = true
			machine.position.x -= float(machine.move_speed)*delta
		machine._pose_parts()
		machine.wetness.advance(delta)

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
	var result := {"note":"Actual QHD frame intervals in a prepared scene: two walking players and 18 posed enemies, of which 12 walk with floor contacts; combat held. Full effects compared with F3 (all reduced weather, not isolated new-effect cost). VSync/FPS cap disabled. Fixed 1/60 s movement steps, real presentation intervals, not isolated GPU time. Footstep playback active on Dummy driver.","godot":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"processor":OS.get_processor_name(),"viewport":[captured_size.x,captured_size.y],"resolution_verified_by":"Fullscreen viewport texture readback before warmup","cases":{}}
	var fixtures: Array = [["ash_foundry",false],["ash_foundry",true],["abandoned_harbor",false],["abandoned_harbor",true],["frozen_rail_yard",false],["frozen_rail_yard",true],["overgrown_steelworks",false,"fire"]]
	for fixture in fixtures:
		var game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		game.start_scenario(2,{"environment":fixture[0],"build_type":"bastion","position":"left"})
		game.rounds.running = false
		game.rounds.set_process(false)
		game.rounds.wave = 20
		game.camera.position = Vector2(1000,450)
		game.camera.zoom = Vector2.ONE
		game.camera.reset_smoothing()
		game.set_process(false)
		game.scenery.elapsed = 37.5
		game.weather.set_reduced_effects(fixture[1])
		game.weather.lightning_enabled = false
		var props: Node2D = game.scenery.props_layer
		if fixture.size()>2:
			# Deliberate nearby simultaneous fires exercise the complete four-light
			# pool, its shadow receivers and the new foliage alongside moving actors.
			for entry: Dictionary in props.entries:
				if entry.position.x>=820 and entry.position.x<=1400 and entry.kind in ["tree","grass","vines"]:
					props.reactions.damage_entry(int(entry.index),1.0,"fire")
		game.medic.set_physics_process(false)
		for worker in game.players:
			worker.set_physics_process(false)
			worker.get_node("PixelVisual").set_process(false)
			worker.wetness.set_physics_process(false)
			worker.position = Vector2(820+worker.player_id*48,430)
			worker.wetness._last_position = worker.position
		machines.clear()
		for index in EnemyCatalog.GROUND_CLASSES.size():
			var machine = game._entity("ground_infantry" if EnemyCatalog.is_human(EnemyCatalog.GROUND_CLASSES[index]) else "enemy",Vector2(1180+index*34,430),{"kind":EnemyCatalog.GROUND_CLASSES[index],"wave":20})
			machine.set_physics_process(false)
			machine.wetness.set_physics_process(false)
			machines.append(machine)
		for index in AirEnemyCatalog.CLASS_ORDER.size():
			var machine = game._entity("air_enemy",Vector2(1260+index*60,105+index%3*30),{"kind":AirEnemyCatalog.CLASS_ORDER[index],"wave":20})
			machine.set_physics_process(false)
			machine.wetness.set_physics_process(false)
			machines.append(machine)
		for frame in WARMUP:
			pose_machines(game,1.0/60.0)
			await RenderingServer.frame_post_draw
		var previous := Time.get_ticks_usec()
		var samples: Array[float] = []
		var draw_calls: Array[float] = []
		var peak_fire_lights := 0
		var slow_frames: Array[Dictionary] = []
		for frame in FRAMES:
			pose_machines(game,1.0/60.0)
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			var interval := float(now-previous)/1000.0
			samples.append(interval)
			if interval>25.0:
				slow_frames.append({"frame":frame,"ms":interval,"scenery_time":props.elapsed,
					"fall_fragments":props.debris._fall_fragments.size(),"lights":props.debris.fire_lighting.active_entries.size()})
			draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			peak_fire_lights = maxi(peak_fire_lights,props.debris.fire_lighting.active_entries.size())
			previous = now
		var label: String = str(fixture[0])+("_reduced" if fixture[1] else "_full")
		if fixture.size()>2: label += "_fire"
		var draw_sum := 0.0
		for count in draw_calls: draw_sum += count
		result.cases[label] = {"frames":FRAMES,"machines":machines.size(),"frame_intervals":summarize(samples),"mean_draw_calls":snappedf(draw_sum/draw_calls.size(),.1),"foot_contacts":game.weather.surface_effects.footstep_count,"spatial_steps":game.audio.movement.steps_played,"ground_chips":game.weather.surface_effects.ground.chips.size(),"wind":game.weather.world_wind.diagnostics(),"peak_fire_lights":peak_fire_lights,"fire_lighting":props.debris.fire_lighting.diagnostics(),"scenery_particles":props.debris.particles.size()}
		result.cases[label].slow_frames = slow_frames
		if fixture.size()>2 and peak_fire_lights!=4:
			push_error("Fire benchmark did not exercise all four light slots")
			quit(1)
			return
		root.get_texture().get_image().save_png("res://artifacts/movement-effects/"+label+"-qhd.png")
		print("MOVEMENT FRAME BENCHMARK ",label,": ",JSON.stringify(result.cases[label]))
		machines.clear()
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	var destination := "res://artifacts/movement-effects/performance.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): destination = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir()))
	var file := FileAccess.open(destination,FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	quit()
