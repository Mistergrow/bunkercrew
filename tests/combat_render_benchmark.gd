extends SceneTree
## Repeatable 1080p renderer measurement, four crew, forty animated enemies.
var warmup := 120
var frames := 600
var enemies: Array[Node2D] = []
var manual_weather := false
var weather_cpu: Array[float] = []
var surface_cpu: Array[float] = []
var wet_cpu: Array[float] = []

func weather_step(game) -> void:
	if not manual_weather: return
	var before := Time.get_ticks_usec()
	for wet in get_nodes_in_group("weather_actors"): wet.advance(1.0/60)
	var after_wet := Time.get_ticks_usec()
	game.weather._process(1.0/60)
	var after_rain := Time.get_ticks_usec()
	game.weather.surface_effects.advance(1.0/60)
	wet_cpu.append((after_wet-before)/1000.0)
	weather_cpu.append((after_rain-after_wet)/1000.0)
	surface_cpu.append((Time.get_ticks_usec()-after_rain)/1000.0)
func _initialize() -> void: run.call_deferred()
func summary(samples: Array[float]) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted: total+=value
	return {"mean":total/samples.size(),"p95":sorted[ceili(sorted.size()*.95)-1],"max":sorted[-1]}
func poses(delta: float) -> void:
	for enemy in enemies:
		enemy.age+=delta
		if enemy is SiegeMachine:
			enemy.gait+=delta*4
			enemy.moving=true
		enemy._pose_parts()
func scene_counts(game: Node2D) -> Dictionary:
	var population := {"enemies":0,"players":0}
	for enemy in get_nodes_in_group("enemies"):
		if enemy.get("game")==game and enemy.is_inside_tree() and not enemy.is_queued_for_deletion() and not enemy.dead:
			population.enemies+=1
	for worker in game.players:
		if is_instance_valid(worker) and worker.game==game and worker.is_inside_tree() and not worker.is_queued_for_deletion():
			population.players+=1
	return population
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2);return
	root.mode=Window.MODE_WINDOWED
	root.size=Vector2i(1920,1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	manual_weather = "--manual-weather" in OS.get_cmdline_user_args()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--warmup="): warmup = argument.trim_prefix("--warmup=").to_int()
		elif argument.begins_with("--frames="): frames = argument.trim_prefix("--frames=").to_int()
	if warmup < 60 or frames < 120:
		push_error("Performance capture requires at least 60 warmup and 120 measured frames")
		quit(2)
		return
	var cases := {}
	for environment in ["ash_foundry","mountain_pass"]:
		var game=load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene=game
		game.start_scenario(4,{"environment":environment,"build_type":"bastion","position":"left"})
		if "--reduced-effects" in OS.get_cmdline_user_args(): game.weather.set_reduced_effects(true)
		game.weather.collision.profiling="--collision-profile" in OS.get_cmdline_user_args()
		game.rounds.running=false
		game.rounds.set_process(false)
		game.rounds.wave=20
		game.set_process(false)
		game.camera.set_process(false)
		game.camera.position=Vector2(1120,70)
		game.camera.zoom=Vector2.ONE*.75
		game.camera.reset_smoothing()
		game.camera.force_update_scroll()
		game.medic.set_physics_process(false)
		for player in game.players: player.set_physics_process(false)
		enemies.clear()
		for index in 40:
			var kind: String=EnemyCatalog.CLASS_ORDER[index%EnemyCatalog.CLASS_ORDER.size()]
			var at := Vector2(650+index%34*32,430)
			var type := "enemy"
			if EnemyCatalog.is_human(kind): type="ground_infantry"
			elif AirEnemyCatalog.is_air(kind):type="air_enemy";at.y=180+index%3*40
			var enemy=game._entity(type,at,{"kind":kind,"wave":20})
			enemy.set_physics_process(false)
			if is_instance_valid(enemy.get("wetness")):enemy.wetness.amount=.85 if environment=="mountain_pass" else 0.0
			enemies.append(enemy)
		if "--no-wet-materials" in OS.get_cmdline_user_args():
			for wetness in get_nodes_in_group("weather_actors"):
				for item in wetness._material_items: item.material=null
		if manual_weather:
			game.weather.set_process(false)
			game.weather.surface_effects.set_physics_process(false)
			for wet in get_nodes_in_group("weather_actors"): wet.set_physics_process(false)
		for frame in warmup:
			poses(1.0/60)
			weather_step(game)
			await RenderingServer.frame_post_draw
		var measured_size := root.get_texture().get_image().get_size()
		var population := scene_counts(game)
		if measured_size != Vector2i(1920,1080) or population!={"enemies":40,"players":4} or game.scenery.environment_id!=environment or game.scenario_options.environment!=environment:
			push_error("Performance capture differs from requested 1080p environment/four players/forty enemies")
			quit(2)
			return
		var previous := Time.get_ticks_usec()
		var intervals: Array[float]=[]
		var calls: Array[float]=[]
		var physics: Array[float]=[]
		var process_times: Array[float]=[]
		weather_cpu.clear();surface_cpu.clear();wet_cpu.clear()
		game.weather.collision.profile_us=[0,0,0,0,0]
		for frame in frames:
			poses(1.0/60)
			weather_step(game)
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			intervals.append((now-previous)/1000.0)
			calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
			process_times.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
			previous=now
		if scene_counts(game)!=population:
			push_error("Performance capture population changed during measurement")
			quit(2)
			return
		cases[environment]={"frame_ms":summary(intervals),"draw_calls":summary(calls),"physics_ms":summary(physics),"engine_process_ms":summary(process_times),"viewport":[measured_size.x,measured_size.y],"enemies":population.enemies,"players":population.players,"environment_id":game.scenery.environment_id,"wetness":.85 if environment=="mountain_pass" else 0.0,"reduced_effects":game.weather.reduced_effects,"warmup_frames":warmup,"measured_frames":frames}
		cases[environment].mean_fps = 1000.0 / float(cases[environment].frame_ms.mean)
		cases[environment].meets_frame_target = cases[environment].mean_fps >= 60.0 and cases[environment].frame_ms.p95 <= 16.7
		print("COMBAT RENDER ",environment,": ",JSON.stringify(cases[environment]))
		if game.weather.collision.profiling:print("RAIN TRACE TOTAL US [refresh,fallback,physics,static,actors]: ",game.weather.collision.profile_us)
		if manual_weather:
			print("WEATHER_SCOPES ",environment," ",JSON.stringify({"wet":summary(wet_cpu),"rain":summary(weather_cpu),"surface":summary(surface_cpu),"particles":game.weather.surface_effects.particles.size(),"patches":game.weather.surface_effects.patches.size(),"footprints":game.weather.surface_effects.footprints.size()}))
			cases[environment].manual_weather_cpu_ms = {"wet":summary(wet_cpu),"rain":summary(weather_cpu),"surface":summary(surface_cpu)}
		cases[environment].frame_samples_ms = intervals
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--capture-dir="):
				var directory := argument.trim_prefix("--capture-dir=")
				DirAccess.make_dir_recursive_absolute(directory)
				root.get_texture().get_image().save_png(directory.path_join(environment+".png"))
		enemies.clear()
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	var destination := "res://artifacts/combat-performance/after.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):destination=arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	var file:=FileAccess.open(destination,FileAccess.WRITE)
	file.store_string(JSON.stringify({"note":"Prepared 1920x1080, VSync disabled, four stationary crew and forty animated enemies, combat frozen, weather profile recorded per case, enemies initially .85 wet on mountain_pass. Frame timings include presentation; not a GPU-only measurement.","godot":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"processor":OS.get_processor_name(),"cases":cases},"  "))
	file.close()
	quit()
