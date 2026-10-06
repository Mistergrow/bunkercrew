extends SceneTree
## Real silhouettes for every enemy class; compare narrow phase and measure caches.
var checks := 0
var failures := 0
var measurements: Array = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func mean(samples: Array[float]) -> float:
	var total:=0.0
	for sample in samples: total+=sample
	return snappedf(total/maxi(1,samples.size()),.001)
func run() -> void:
	for environment in ["mountain_pass","ash_foundry"]:
		var game=load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene=game
		game.start_scenario(4,{"environment":environment,"build_type":"workshop","position":"middle"})
		game.rounds.set_process(false)
		game.weather.set_process(false)
		game.weather.surface_effects.set_physics_process(false)
		game.medic.set_physics_process(false)
		for worker in game.players: worker.set_physics_process(false)
		var kinds: Array=EnemyCatalog.GROUND_CLASSES.duplicate()
		kinds.append_array(AirEnemyCatalog.CLASS_ORDER)
		for index in 40:
			var kind: String=kinds[index%kinds.size()]
			var air:=AirEnemyCatalog.is_air(kind)
			var enemy=game._entity("air_enemy" if air else ("ground_infantry" if EnemyCatalog.is_human(kind) else "enemy"),Vector2(850+index*31,160 if air else 430),{"kind":kind,"wave":20})
			enemy.set_physics_process(false)
		for frame in 3: await physics_frame; await process_frame
		for wetness in get_nodes_in_group("weather_actors"): wetness.set_physics_process(false)
		var solver:=RainCollision.new()
		solver.weather=game.weather
		solver.refresh(false)
		check(solver._actor_records.is_empty() and solver._actor_segments.is_empty(),environment+": static exposure never builds actor contours")
		solver.refresh(true)
		check(solver._actor_segments.is_empty(),environment+": actor broad phase does not sample all silhouettes")
		for phase in [0.0,.7,2.1,4.9]:
			for enemy in get_nodes_in_group("enemies"):
				enemy.age=phase
				if enemy is SiegeMachine:enemy.gait=phase;enemy.moving=true
				enemy.weapon_recoil=phase
				enemy._pose_parts()
			for record: Dictionary in solver._actor_records:
				var bounds: Rect2=solver.actor_bounds(record.actor).grow(.1)
				var contours=record.wetness.rain_segments()
				check(contours.all(func(segment):return bounds.has_point(segment.from) and bounds.has_point(segment.to)),environment+": conservative bounds contain every authored contour for "+str(record.actor.name)+" at phase "+str(phase))
		var static_times: Array[float]=[]
		var actor_times: Array[float]=[]
		for frame in 120:
			await process_frame
			var start:=Time.get_ticks_usec()
			solver.refresh(false)
			var static_end:=Time.get_ticks_usec()
			solver.refresh(true)
			var actor_end:=Time.get_ticks_usec()
			static_times.append((static_end-start)/1000.0)
			actor_times.append((actor_end-static_end)/1000.0)
		check(solver._actor_segments.is_empty(),environment+": repeated cache refreshes stay lazy")
		measurements.append({"environment":environment,"players":4,"enemies":40,"frames":120,"static_refresh_mean_ms":mean(static_times),"actor_broad_phase_mean_ms":mean(actor_times)})
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	var destination:="res://artifacts/network-followup/weather-cache.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir()))
	var file:=FileAccess.open(destination,FileAccess.WRITE)
	if file==null:
		push_error("Cannot write weather cache report")
		quit(1)
		return
	file.store_string(JSON.stringify({"headless":true,"cpu":OS.get_processor_name(),"measurements":measurements,"checks":checks,"failures":failures},"  "))
	print("WEATHER CACHE FOLLOWUP: %d checks, %d failures; %s"%[checks,failures,JSON.stringify(measurements)])
	quit(1 if failures else 0)
