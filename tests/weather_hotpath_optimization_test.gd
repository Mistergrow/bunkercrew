extends SceneTree
## CPU-only prepared main worlds; separate hotloop timings and unchanged actual
## polygon/candidate geometry. No GPU/FPS or comparative-hardware claim.
const Cleanup:=preload("res://tests/scene_cleanup.gd")
const OUTPUT:="res://artifacts/code-optimization-20261004/presentation/"
var checks:=0
var failures:=0
var measurements: Dictionary={}
class CountedWetness extends ActorWetness:
	var feet_reads:=0
	func feet() -> Array[Vector2]:
		feet_reads+=1
		return super.feet()
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(label)
func stats(values: Array[float]) -> Dictionary:
	var sorted:=values.duplicate();sorted.sort()
	var total:=0.0
	for value in sorted: total+=value
	return {"mean_ms":total/maxi(values.size(),1),"median_ms":sorted[floori(sorted.size()/2.0)],"min_ms":sorted[0],"max_ms":sorted[-1],"samples":values.size()}
func geometry() -> void:
	var props:=WeatherPropSurfaces.new();root.add_child(props)
	var node:=Node2D.new();props.add_child(node)
	var polygon:=PackedVector2Array([Vector2(-11,-7),Vector2(19,-2),Vector2(23,8),Vector2(-4,17)])
	var same:=true
	for index in 64:
		node.position=Vector2(index*1.25,-index*.75);node.rotation=index*.137;node.scale=Vector2(-.8 if index%2 else 1.3,.64+index*.012)
		props._segments.clear();props._add_polygon(node,polygon,node,"metal")
		for point in polygon.size():
			var a:=node.to_global(polygon[point]);var b:=node.to_global(polygon[(point+1)%polygon.size()])
			var edge:=b-a
			var entry: Dictionary=props._segments[point]
			same=same and a.is_equal_approx(entry.from) and b.is_equal_approx(entry.to) and Vector2(edge.y,-edge.x).normalized().is_equal_approx(entry.normal) and entry.collider==node and entry.material=="metal"
	check(same,"Transformed polygon endpoints/normals/material/owner stay native-exact for rotation, shear-free mirrors and nonuniform scale")
	var polygon_times: Array[float]=[]
	for repeat in 7:
		var begin:=Time.get_ticks_usec()
		for index in 6000:
			props._segments.clear();props._add_polygon(node,polygon,node,"metal")
		polygon_times.append((Time.get_ticks_usec()-begin)/1000.0)
	measurements.polygon_6000=stats(polygon_times)
	var solver:=RainCollision.new();var cells: Dictionary={}
	for index in 96: solver._index_segment(cells,{"from":Vector2(65,70+index*.2),"to":Vector2(110,70+index*.2)},index)
	var source: Array=cells[Vector2i(1,1)]
	var selection:=solver._candidate_indices(cells,Vector2(80,80),Vector2(81,85))
	check(selection==source and selection.size()==96,"Same-cell short sweeps retain every populated candidate in original order")
	var before:=source.duplicate()
	var cell_times: Array[float]=[];var consumed:=0
	for repeat in 7:
		var begin:=Time.get_ticks_usec()
		for index in 30000:
			var candidates:=solver._candidate_indices(cells,Vector2(80,80),Vector2(81,85))
			consumed+=candidates.size()
		cell_times.append((Time.get_ticks_usec()-begin)/1000.0)
	check(source==before and consumed==7*30000*96,"Repeated read-only weather sweeps leave source index unchanged")
	measurements.single_cell_30000=stats(cell_times)
	measurements.single_cell_30000["same_backing_array"]=is_same(selection,cells[Vector2i(1,1)])
	await Cleanup.free_scene(props,self)

func arranged_world(environment: String) -> void:
	var game=load("res://scenes/main.tscn").instantiate();root.add_child(game);current_scene=game
	game.start_scenario(4,{"environment":environment,"build_type":"workshop","position":"middle"})
	game.set_process(false);game.rounds.set_process(false);game.weather.set_process(false);game.weather.surface_effects.set_physics_process(false);game.medic.set_physics_process(false)
	for worker in game.players: worker.set_physics_process(false)
	var kinds: Array=EnemyCatalog.GROUND_CLASSES.duplicate();kinds.append_array(AirEnemyCatalog.CLASS_ORDER)
	for index in 40:
		var kind: String=kinds[index%kinds.size()];var air:=AirEnemyCatalog.is_air(kind)
		var enemy=game._entity("air_enemy" if air else ("ground_infantry" if EnemyCatalog.is_human(kind) else "enemy"),Vector2(850+index*31,160 if air else 430),{"kind":kind,"wave":20})
		enemy.set_physics_process(false)
	for frame in 3: await physics_frame;await process_frame
	for wetness in get_nodes_in_group("weather_actors"): wetness.set_physics_process(false)
	var solver:=RainCollision.new();solver.weather=game.weather
	var static_times: Array[float]=[];var actor_times: Array[float]=[];var prop_times: Array[float]=[]
	for frame in 40:
		await process_frame
		var start:=Time.get_ticks_usec();solver.refresh(false);var static_end:=Time.get_ticks_usec();solver.refresh(true);var actor_end:=Time.get_ticks_usec()
		static_times.append((static_end-start)/1000.0);actor_times.append((actor_end-static_end)/1000.0)
		game.weather.prop_surfaces.invalidate()
		start=Time.get_ticks_usec();game.weather.prop_surfaces.rain_segments();prop_times.append((Time.get_ticks_usec()-start)/1000.0)
	check(solver._actor_records.size()>=44 and solver._actor_segments.is_empty(),environment+": real four-player/forty-enemy broad phase stays lazy")
	var short_same:=0;var traces:=0
	for drop in game.weather.rain:
		var a: Vector2=drop.point;var b:=a+Vector2(.5,6)
		if Vector2i(floori(a.x/RainCollision.CELL_SIZE),floori(a.y/RainCollision.CELL_SIZE))==Vector2i(floori(b.x/RainCollision.CELL_SIZE),floori(b.y/RainCollision.CELL_SIZE)): short_same+=1
		traces+=1
	if environment=="ash_foundry":
		var worker=game.players[0]
		var wetness:=CountedWetness.new();worker.add_child(wetness);wetness.set_physics_process(false)
		wetness._stationary_time=0.0;wetness._last_step_time=wetness.age
		worker.hide()
		var hidden_times: Array[float]=[]
		for repeat in 7:
			var begin:=Time.get_ticks_usec()
			for index in 12000: wetness._foot_contacts(game.weather,Vector2(1,0))
			hidden_times.append((Time.get_ticks_usec()-begin)/1000.0)
		measurements.hidden_foot_contacts_12000=stats(hidden_times)
		measurements.hidden_foot_contacts_12000["feet_reconstructions"]=wetness.feet_reads
		check(wetness.steps_emitted==0 and wetness._previous_contacts.all(func(contact):return not contact) and wetness._pending_contacts.all(func(contact):return not contact),"Moving hidden real worker never emits or retains a walking contact")
		worker.show()
		wetness.feet_reads=0
		worker.medical.state="downed"
		wetness._foot_contacts(game.weather,Vector2(1,0))
		measurements.downed_feet_reconstructions=wetness.feet_reads
		check(wetness.steps_emitted==0,"Actual downed worker discards walking contacts without changing medical state")
		worker.medical.state="healthy"
		worker.position=Vector2(100000,430)
		wetness.feet_reads=0
		wetness._foot_contacts(game.weather,Vector2(1,0))
		measurements.offscreen_feet_reconstructions=wetness.feet_reads
		check(wetness.steps_emitted==0,"Actual offscreen worker preserves absence of cosmetic footsteps")
		worker.position=Vector2(1000,430)
		game.camera.position=worker.position;game.camera.zoom=Vector2.ONE;game.camera.force_update_scroll()
		await physics_frame;await process_frame
		wetness.feet_reads=0;wetness._was_airborne=true;worker._airborne=false
		wetness._foot_contacts(game.weather,Vector2(1,0))
		check(wetness.feet_reads==1,"Visible available actual worker still reconstructs its exact animated feet")
		check(not wetness._was_airborne and wetness._landing_deadline>=wetness.age,"Available worker retains its brief real landing contact window")
	measurements[environment]={"players":4,"enemies":40,"actors":solver._actor_records.size(),"static_segments":solver._static_segments.size(),"frames":40,"static_refresh":stats(static_times),"actor_broad_phase":stats(actor_times),"props_rebuild":stats(prop_times),"arranged_short_sweeps":traces,"same_cell_short_sweeps":short_same}
	check(await Cleanup.free_scene(game,self),environment+": actual scene retires without lingering audio handles")

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args(): quit(2);return
	await geometry()
	await arranged_world("mountain_pass")
	await arranged_world("ash_foundry")
	var label:="run"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label=argument.trim_prefix("--label=").validate_filename()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var file:=FileAccess.open(OUTPUT+"weather-hotpaths-"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"cpu":OS.get_processor_name(),"headless":DisplayServer.get_name()=="headless","measurements":measurements,"note":"CPU timings with no quality/budget/frequency reductions; frozen AI, actual main worlds, own XDG/no profile/no UPnP. Median hotloop microbenchmarks are attribution proof, not real-frame FPS."},"\t")+"\n")
	print("WEATHER HOTPATHS: %d/%d passed; %s"%[checks-failures,checks,JSON.stringify(measurements)])
	quit(1 if failures else 0)
