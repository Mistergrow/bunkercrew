extends SceneTree
## Small headless performance audit, not a GPU/FPS benchmark. All 18 machine
## classes occupy the late scene; AI combat is frozen and poses still animate.
## Fixed 1/60 updates measure weather, saturation and surface CPU work directly.
const DT := 1.0/60.0
const FRAMES := 180
const WARMUP := 30
var game
var machines:Array=[]
var wet_actors:Array=[]

func _initialize(): run.call_deferred()

func summarize(samples:Array[float])->Dictionary:
	var sorted:=samples.duplicate()
	sorted.sort()
	var total:=0.0
	for sample in sorted: total+=sample
	return {"mean_ms":snappedf(total/maxi(1,sorted.size()),0.001),"p50_ms":snappedf(sorted[floori(sorted.size()/2.0)],0.001),"p95_ms":snappedf(sorted[int(sorted.size()*0.95)],0.001),"max_ms":snappedf(sorted[-1],0.001)}

func poses():
	for machine in machines:
		machine.age+=DT
		if machine is SiegeMachine:
			machine.gait+=DT*4.0
			machine.moving=true
		else:
			machine.position.y+=sin(machine.age*1.4+machine.position.x)*DT*2.0
		machine._pose_parts()

func micro():
	var covers:Array[float]=[]
	var refreshes:Array[float]=[]
	var traces:Array[float]=[]
	for sample in 20:
		await process_frame
		var begin:=Time.get_ticks_usec()
		for index in 120:
			game.weather.rain_surface(-550.0+float(index)*2800.0/120.0)
		var after_cover:=Time.get_ticks_usec()
		game.weather.collision.invalidate()
		game.weather.collision.refresh()
		var after_refresh:=Time.get_ticks_usec()
		for drop in game.weather.rain:
			game.weather.trace_rain(drop.point,Vector2(drop.point)+Vector2(0.5,6))
		var finish:=Time.get_ticks_usec()
		covers.append(float(after_cover-begin)/1000.0)
		refreshes.append(float(after_refresh-after_cover)/1000.0)
		traces.append(float(finish-after_refresh)/1000.0)
	print("RAIN PERF MICRO ",JSON.stringify({"architectural_cover_120":summarize(covers),"all_contours_refresh":summarize(refreshes),"short_sweeps_120":summarize(traces)}))

func phase(label:String,reduced:bool)->Dictionary:
	game.weather.set_reduced_effects(reduced)
	var wet_samples:Array[float]=[]
	var rain_samples:Array[float]=[]
	var surface_samples:Array[float]=[]
	var all_samples:Array[float]=[]
	var query_begin:int=game.weather.collision.physics_queries
	for frame in WARMUP+FRAMES:
		await process_frame
		poses()
		var begin:=Time.get_ticks_usec()
		for actor in wet_actors: actor.advance(DT)
		var after_wet:=Time.get_ticks_usec()
		game.weather._process(DT)
		var after_rain:=Time.get_ticks_usec()
		game.weather.surface_effects.advance(DT)
		var finish:=Time.get_ticks_usec()
		if frame<WARMUP: continue
		wet_samples.append(float(after_wet-begin)/1000.0)
		rain_samples.append(float(after_rain-after_wet)/1000.0)
		surface_samples.append(float(finish-after_rain)/1000.0)
		all_samples.append(float(finish-begin)/1000.0)
	var result:Dictionary={"phase":label,"frames":FRAMES,"warmup":WARMUP,"dt":DT,"actors":wet_actors.size(),"machines":machines.size(),"actor_contour_segments":game.weather.collision._actor_segments.size(),"prop_contour_segments":game.weather.collision._static_segments.size(),"primary_drops":game.weather.rain.size(),"rain_cpu":summarize(rain_samples),"actor_wetness_cpu":summarize(wet_samples),"surface_cpu":summarize(surface_samples),"combined_weather_cpu":summarize(all_samples),"physics_queries_including_warmup":game.weather.collision.physics_queries-query_begin,"active_surface_drops":game.weather.surface_effects.particles.size()}
	print("RAIN PERF ",JSON.stringify(result))
	return result

func run():
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start(2)
	game.rounds.running=false
	game.rounds.set_process(false)
	game.rounds.wave=20
	game.set_view_stage(4)
	game.camera.position=Vector2(850,630)
	game.camera.zoom=Vector2.ONE*0.48
	game.set_process(false)
	game.weather.set_process(false)
	game.weather.surface_effects.set_physics_process(false)
	game.medic.set_physics_process(false)
	for worker in game.players: worker.set_physics_process(false)
	for pane in game.dome.segments:
		pane.set_frame()
		pane.glaze()
	for index in EnemyCatalog.GROUND_CLASSES.size():
		var machine=game._entity("ground_infantry" if EnemyCatalog.is_human(EnemyCatalog.GROUND_CLASSES[index]) else "enemy",Vector2(1350+index*42,430),{"kind":EnemyCatalog.GROUND_CLASSES[index],"wave":20})
		machine.set_physics_process(false)
		machines.append(machine)
	for index in AirEnemyCatalog.CLASS_ORDER.size():
		var machine=game._entity("air_enemy",Vector2(1370+index*83,95+index%3*30),{"kind":AirEnemyCatalog.CLASS_ORDER[index],"wave":20})
		machine.set_physics_process(false)
		machines.append(machine)
	for actor in get_nodes_in_group("weather_actors"):
		actor.set_physics_process(false)
		wet_actors.append(actor)
	for frame in 5: await process_frame
	print("RAIN PERF CONTEXT ",JSON.stringify({"godot":Engine.get_version_info().string,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"processor":OS.get_processor_name(),"logical_cpus":OS.get_processor_count(),"note":"CPU scopes in an arranged main scene; headless, 18 frozen-combat machines with animated poses, no GPU/FPS claim; fixed 1/60 manual weather steps."}))
	if "--micro" in OS.get_cmdline_user_args():
		await micro()
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
		quit()
		return
	await phase("rain_enabled_a",false)
	await phase("F3_reduced",true)
	await phase("rain_enabled_b",false)
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	quit()
