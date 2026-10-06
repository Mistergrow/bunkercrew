extends SceneTree
## Deterministic envelopes plus real main-scene rain, shelter, wind and thunder.
## --capture writes prepared gust/drizzle/flash/F3 views with no active waves.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/weather-refresh/"
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("WEATHER DYNAMICS %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func simulate(weather, seconds: float) -> void:
	for frame in ceili(seconds*60.0):
		weather._process(1.0/60.0)
		weather.world_wind._process(1.0/60.0)
		weather.surface_effects.advance(1.0/60.0)

func save_view(game, label: String, time: float, reduced: bool = false, flash: bool = false) -> void:
	var weather = game.weather
	weather.set_reduced_effects(false)
	weather.elapsed = time-1.0
	weather.world_wind.set_reduced(true)
	simulate(weather,1.0)
	game.scenery.props_layer._process(.04)
	if flash:
		weather._start_lightning()
		weather.lightning_age = .02
	weather.set_reduced_effects(reduced)
	for layer in weather.rain_layers+[weather.sky_layer,weather.wind_layer]: layer.queue_redraw()
	weather.world_wind.queue_redraw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+label+".png")

func run() -> void:
	root.size = Vector2i(2560,1440)
	AudioServer.set_bus_mute(0,true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var model := ShiftWeather.new()
	for environment: Dictionary in ScenarioCatalog.environments():
		model.configure_environment(environment)
		var quiet := 0
		var peak := 0.0
		var largest_step := 0.0
		var previous := model.gust_at(Vector2(900,350),0)
		var low_rain := 1.0
		var high_rain := 0.0
		var rain_step := 0.0
		var prior_rain := model.rain_intensity_at(0)
		for sample in 1841:
			var time := float(sample)*.05
			var value := model.gust_at(Vector2(900,350),time)
			if value<.001: quiet += 1
			peak = maxf(peak,value)
			largest_step = maxf(largest_step,absf(value-previous))
			previous = value
			var intensity := model.rain_intensity_at(time)
			low_rain = minf(low_rain,intensity)
			high_rain = maxf(high_rain,intensity)
			rain_step = maxf(rain_step,absf(intensity-prior_rain))
			prior_rain = intensity
		check(quiet>450 and peak>.95 and largest_step<.015,"%s has sustained calm, individual full gusts and smooth transitions" % environment.id)
		check(model.gust_at(Vector2(200,350),5)!=model.gust_at(Vector2(1600,350),5),"%s gust front reaches separate scene positions at different times" % environment.id)
		if model.rain_base_strength>0:
			check(low_rain<=model.rain_base_strength*.121 and high_rain>=model.rain_base_strength*.99 and rain_step<.008,"%s cycles smoothly between drizzle and authored shower strength" % environment.id)
		else:
			check(low_rain==0 and high_rain==0,"%s remains a dry climate throughout the weather cycle" % environment.id)
	model.free()
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1,{"environment":"mountain_pass","build_type":"bastion","position":"left"})
	game.rounds.running = false
	game.rounds.set_process(false)
	for frame in 5: await physics_frame
	freeze(game)
	game.notice_time = 0
	var weather = game.weather
	var wind = weather.world_wind
	weather.elapsed = 4.0
	wind.set_reduced(true)
	simulate(weather,1.0)
	check(wind.particles.size()>10 and wind.plumes.size()>0,"Actual scene emits visible bounded material during a gust")
	check(weather.contact_count>0 and weather.surface_effects.rain_contact_count>0,"Wind-driven rain reaches the existing real contact/splash simulation")
	var root_x: float = game.scenario_bunker.room_left
	check(weather.exposure_at(Vector2(root_x+300,370))==0 and not wind.outdoors(Vector2(root_x+300,370)),"Real bunker roof shelters both rain and airborne material")
	var calm: Vector2 = weather.wind_at(Vector2(900,300),50)
	var gust: Vector2 = weather.wind_at(Vector2(900,300),4)
	check(calm.x<=2.01 and gust.x>100 and gust.y==0,"Rain changes from near vertical drizzle to a substantial sideways gust")
	var drop: Dictionary = weather.rain[-1].duplicate()
	drop.point = Vector2(1200,200)
	weather.elapsed = 50
	var calm_line: PackedVector2Array = weather.rain_segment(drop)
	weather.elapsed = 7
	var slanted: PackedVector2Array = weather.rain_segment(drop)
	check(absf(slanted[1].x-slanted[0].x)>absf(calm_line[1].x-calm_line[0].x)+1.5,"Drawn near-band streaks follow the same local wind as falling drops")
	weather.elapsed = 48
	simulate(weather,5.8)
	check(wind.particles.is_empty() and wind.plumes.is_empty(),"The actual visible world clears old gust material during a sustained calm")
	check(weather.flag_panel(4)[1].x<126,"Roof flag hangs close to its pole in calm air")
	var calm_panel: PackedVector2Array = weather.flag_panel(4)
	weather.elapsed = 0
	check(weather.flag_panel(4)[1].x>calm_panel[1].x+10,"The same flag extends naturally when its local gust arrives")
	var before: float = weather.elapsed
	paused = true
	weather._process(.5)
	wind._process(.5)
	check(weather.elapsed==before,"Explicit weather updates also respect a paused SceneTree")
	paused = false
	weather._process(NAN)
	check(weather.elapsed==before,"Invalid frame duration cannot poison deterministic weather time")
	weather._start_lightning()
	var points_visible: bool = weather.bolt.size()>=4
	var view: Rect2 = weather.get_canvas_transform().affine_inverse()*weather.get_viewport_rect()
	for point: Vector2 in weather.bolt: points_visible = points_visible and view.has_point(point) and weather.is_outdoors(point)
	check(points_visible and weather.lightning_branches.size()<=3,"Ambient lightning is visible in the current camera sky with at most three bounded branches")
	check(weather.thunder_delay(Vector2(2500,250))>weather.thunder_delay(game.audio.acoustics.listener_position)+.5,"Distant thunder has a longer travel delay than a nearby strike")
	var pending: float = weather.thunder_wait
	check(pending>=.7 and pending<=2.4 and weather.thunder_origin==weather.bolt[-1],"Ambient thunder is queued at the visible bolt endpoint with a bounded delay")
	weather.set_reduced_effects(true)
	before = weather.elapsed
	weather._process(.5)
	wind._process(.5)
	check(weather.elapsed==before and wind.particles.is_empty() and wind.plumes.is_empty() and weather.thunder_wait<0 and weather.lightning_strength()==0,"F3 immediately clears airborne material/flash/thunder and freezes the weather clock")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		await save_view(game,"mountain-gust",4)
		await save_view(game,"mountain-drizzle",38)
		await save_view(game,"mountain-lightning",5,false,true)
		await save_view(game,"mountain-reduced",5,true)
	if not await Cleanup.free_scene(game,self): failures += 1
	print("WEATHER DYNAMICS: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
