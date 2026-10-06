extends SceneTree
## Prepared 1080p combat-art fixture: ecology on/off, with full and F3 weather.
## Combat and positions are held; native music and weather keep running.
const CLEANUP := preload("res://tests/scene_cleanup.gd")
const FLORA := preload("res://scripts/living_ecology_catalog.gd")
const FAUNA := preload("res://scripts/fauna_catalog.gd")
const WARMUP_FRAMES := 60
const MEASURED_FRAMES := 180
const OUTPUT := "res://artifacts/living-ecology/performance.json"
const SIZE := Vector2i(1920,1080)
var checks := 0
var failures := 0
var enemies: Array[Node2D] = []
var plants: Node2D
var wildlife: Node2D
var flora_baseline: Array[Dictionary] = []
var fauna_baseline: Array[Dictionary] = []
var flora_time := 0.0
var fauna_time := 0.0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func summary(samples: Array[float]) -> Dictionary:
	if samples.is_empty(): return {}
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for sample: float in sorted: total += sample
	return {"mean":snappedf(total/sorted.size(),.0001),"p50":snappedf(sorted[floori(sorted.size()*.5)],.0001),"p95":snappedf(sorted[mini(sorted.size()-1,floori(sorted.size()*.95))],.0001),"max":snappedf(sorted[-1],.0001)}

func pose_enemies() -> void:
	for enemy: Node2D in enemies:
		enemy.age += 1.0/60.0
		if enemy is SiegeMachine:
			enemy.gait += 4.0/60.0
			enemy.moving = true
		enemy._pose_parts()

func step_ecology(enabled: bool) -> void:
	flora_time = 0.0
	fauna_time = 0.0
	if not enabled: return
	var before := Time.get_ticks_usec()
	plants._process(1.0/60.0)
	var after_plants := Time.get_ticks_usec()
	wildlife._process(1.0/60.0)
	flora_time = (after_plants-before)/1000.0
	fauna_time = (Time.get_ticks_usec()-after_plants)/1000.0

func set_ecology(enabled: bool) -> void:
	plants.visible = enabled
	wildlife.visible = enabled
	# The callback is measured directly, once per rendered frame, to capture its
	# actual CPU work including frames where a throttled presentation tick skips.
	plants.set_process(false)
	wildlife.set_process(false)
	plants.entries = flora_baseline.duplicate(true)
	wildlife.entries = fauna_baseline.duplicate(true)
	plants.elapsed = 37.5
	wildlife.elapsed = 37.5
	plants._clock = 1.0
	wildlife._threat_clock = 0.0
	wildlife._redraw_clock = 1.0
	wildlife.refresh_presentation()
	plants._update_presentation()
	if enabled: step_ecology(true)

func prepare(environment: String,reduced: bool) -> Node2D:
	var game := load("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(game)
	current_scene = game
	game.start_scenario(4,{"environment":environment,"build_type":"bastion","position":"left"})
	game.rounds.running = false
	game.rounds.wave = 20
	game.rounds.set_process(false)
	game.set_process(false)
	game.notice = ""
	game.notice_time = 0.0
	game.camera.set_process(false)
	game.player_camera.set_process(false)
	game.camera.position = Vector2(1120,70)
	game.camera.zoom = Vector2.ONE*.75
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	game.weather.set_reduced_effects(reduced)
	game.weather.lightning_enabled = false
	game.weather.elapsed = 37.5
	game.scenery.elapsed = 37.5
	game.medic.set_physics_process(false)
	game.turret.set_physics_process(false)
	for player: Node in game.players: player.set_physics_process(false)
	enemies.clear()
	for index in 40:
		var kind: String = EnemyCatalog.CLASS_ORDER[index%EnemyCatalog.CLASS_ORDER.size()]
		var position := Vector2(650+index%34*32,430)
		var entity_type := "enemy"
		if EnemyCatalog.is_human(kind): entity_type = "ground_infantry"
		elif AirEnemyCatalog.is_air(kind):
			entity_type = "air_enemy"
			position.y = 180+index%3*40
		var enemy: Node2D = game._entity(entity_type,position,{"kind":kind,"wave":20})
		enemy.set_physics_process(false)
		if is_instance_valid(enemy.get("wetness")):
			enemy.wetness.amount = .85 if environment=="mountain_pass" else 0.0
		enemies.append(enemy)
	plants = game.scenery.get_node("LivingVegetation")
	wildlife = game.scenery.get_node("LivingFauna")
	# Rare animals naturally often inhabit the quiet western verge. Arrange the
	# benchmark subjects on the visible eastern outdoor slab, still using their
	# normal habitat range, threat response, rest and movement state machines.
	for index in wildlife.entries.size():
		var animal: Dictionary = wildlife.entries[index]
		var range_index: int = wildlife._ground_ranges.size()-1
		var bounds: Vector2 = wildlife._ground_ranges[range_index]
		var at := Vector2(clampf(1750.0+index*30,bounds.x+20,bounds.y-20),FAUNA.GROUND_Y)
		animal.position = at
		animal.origin = at
		animal.target = at
		animal.ground_range = bounds
		animal.range_index = range_index
	flora_baseline = plants.entries.duplicate(true)
	fauna_baseline = wildlife.entries.duplicate(true)
	plants.set_process(false)
	wildlife.set_process(false)
	check(game.players.size()==4 and enemies.size()==40,environment+": fixture has four crew and forty mixed enemies")
	return game

func measure(game: Node2D,enabled: bool) -> Dictionary:
	set_ecology(enabled)
	for index in WARMUP_FRAMES:
		pose_enemies()
		step_ecology(enabled)
		await RenderingServer.frame_post_draw
	var captured_size := root.get_texture().get_image().get_size()
	check(captured_size==SIZE,"performance fixture renders actual1920x1080pixels")
	var intervals: Array[float] = []
	var calls: Array[float] = []
	var flora_cpu: Array[float] = []
	var fauna_cpu: Array[float] = []
	var previous := Time.get_ticks_usec()
	for index in MEASURED_FRAMES:
		pose_enemies()
		step_ecology(enabled)
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var interval := (now-previous)/1000.0
		check(is_finite(interval) and interval>0,"frame measurement is finite and positive")
		intervals.append(interval)
		calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		flora_cpu.append(flora_time)
		fauna_cpu.append(fauna_time)
		previous = now
	var plant_stats: Dictionary = plants.debug_stats()
	var fauna_stats: Dictionary = wildlife.debug_stats()
	check(int(plant_stats.entries)<=FLORA.MAX_PLANTS and int(plant_stats.mesh_batches)<=3 and int(plant_stats.materials)==1,"vegetation stays inside its population and material budgets")
	check(int(fauna_stats.population)<=FAUNA.MAX_POPULATION and int(fauna_stats.collision_queries)==0,"wildlife stays bounded and does not add physics queries")
	check(not enabled or int(fauna_stats.visible)>0,"enabled ecology includes visible wildlife in the actual renderer workload")
	var native: Node = game.audio.live_music
	return {"ecology_enabled":enabled,"reduced_effects":bool(game.weather.reduced_effects),"frames":MEASURED_FRAMES,"warmup_frames":WARMUP_FRAMES,"viewport":[captured_size.x,captured_size.y],"frame_ms":summary(intervals),"draw_calls":summary(calls),"flora_update_ms":summary(flora_cpu),"fauna_update_ms":summary(fauna_cpu),"plants":plant_stats,"fauna":fauna_stats,"weather_at_end":{"elapsed":game.weather.elapsed,"rain_strength":game.weather.rain_strength},"native_music":{"native_active":bool(native.native_active),"session_active":bool(native.session_active),"music_enabled":bool(native.music_enabled),"playback_running":is_instance_valid(native.player) and native.player.playing}}

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Use graphical rendering and --no-profile-save for this performance fixture")
		quit(2)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = SIZE
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var report := {"fixture":"Actual1920x1080 Compatibility rendering, VSync and FPS cap disabled. Four held crew and forty mixed animated enemies at wave20; camera(1120,70),zoom0.75. Combat and actor movement are frozen. Rare wildlife is placed on the visible eastern outdoor slab using its actual habitat and normal behavior. Weather and native music retain their normal callbacks; wetness initially0.85 on mountain_pass. Ecology callbacks and enemy poses advance by1/60second once per rendered frame. Ecology state restored between comparisons; complete native audio and world rendering remain present. Each case has60warmup and180measured frames. Full and F3 fixtures are separate scenes. Order alternates on/off to reduce systematic warmup effects.","limitation":"Frame intervals include CPU draw building, GPU execution and presentation; these are not isolated GPU timings. Weather/music continue through each comparison, so small frame deltas include timing noise. Direct flora/fauna update costs exclude their _draw command generation, which is reflected in total frames/draw calls. No machine-specific FPS target is asserted. Throttled engine TIME_PROCESS monitors are excluded because short cases can retain scene-load samples.","godot":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"processor":OS.get_processor_name(),"cases":{},"comparisons":{}}
	var fixture_index := 0
	for environment in ["ash_foundry","mountain_pass"]:
		for reduced in [false,true]:
			var game := prepare(environment,reduced)
			var prefix: String = environment+("_reduced" if reduced else "_full")
			var order := [false,true] if fixture_index%2==0 else [true,false]
			for enabled: bool in order:
				var label := prefix+("_on" if enabled else "_off")
				var result := await measure(game,enabled)
				report.cases[label] = result
				print("LIVING ECOLOGY PERFORMANCE "+label+" "+JSON.stringify(result))
			var on: Dictionary = report.cases[prefix+"_on"]
			var off: Dictionary = report.cases[prefix+"_off"]
			report.comparisons[prefix] = {"mean_frame_delta_ms":snappedf(float(on.frame_ms.mean)-float(off.frame_ms.mean),.0001),"p95_frame_delta_ms":snappedf(float(on.frame_ms.p95)-float(off.frame_ms.p95),.0001),"mean_draw_call_delta":snappedf(float(on.draw_calls.mean)-float(off.draw_calls.mean),.01),"mean_direct_ecology_update_ms":snappedf(float(on.flora_update_ms.mean)+float(on.fauna_update_ms.mean),.0001),"flora_update_p95_ms":on.flora_update_ms.p95,"fauna_update_p95_ms":on.fauna_update_ms.p95}
			enemies.clear()
			check(await CLEANUP.free_scene(game,self),prefix+": performance fixture leaves no retained scene")
			fixture_index += 1
	report.checks = checks
	report.failures = failures
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var file := FileAccess.open(OUTPUT,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("LIVING ECOLOGY PERFORMANCE: %d/%d checks passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
