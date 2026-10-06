extends SceneTree
## Prepared main-menu states rendered by the actual shaders. Gameplay remains
## paused throughout; --capture writes QHD frames and measured atmosphere data.
const OUTPUT := "res://artifacts/expedition/menu-atmosphere/"
var checks := 0
var failures := 0
var view: SubViewport
var game
var preview
var samples: Array = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ", label)
	else:
		failures += 1
		push_error(label)

func frames(count: int = 4) -> void:
	for frame in count: await process_frame

func pose(at: float, is_reduced: bool = false) -> void:
	game.weather.reduced_effects = is_reduced
	preview.elapsed = at
	preview._redraw_clock = 1.0
	preview._process(0.0)

func capture(label: String, at: float, is_reduced: bool = false) -> void:
	pose(at, is_reduced)
	await frames()
	var air = preview.atmosphere
	var offset: Vector2 = air.smoke_offset(at, 6.0)
	var lamp_values: Array = []
	for lamp in air.lamp_materials: lamp_values.append(float(lamp.get_shader_parameter("illumination")))
	samples.append({"label":label, "seconds":at, "reduced":is_reduced, "wind":air.wind_at(at), "six_second_smoke_offset":[offset.x,offset.y], "angle_from_horizontal":rad_to_deg(atan2(absf(offset.y),absf(offset.x))), "lamp_levels":lamp_values, "near_ash_count":air.ash_count(), "total_particle_limit":air.ash_count()+air.precipitation_count()})
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(view.get_texture().get_image().save_png(OUTPUT + label + ".png") == OK, "Saved actual QHD " + label + " frame")

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	view = SubViewport.new()
	view.world_2d = World2D.new()
	view.size = Vector2i(2560,1440)
	view.size_2d_override = Vector2i(1600,900)
	view.size_2d_override_stretch = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames(8)
	var menu = game.hud.main_menu_panel
	for index in menu.environments.size():
		if str(menu.environments[index].id) == "ash_foundry": menu.environment_index = index
	menu._show_environment()
	preview = menu.preview
	var before: float = preview.elapsed
	var game_clock: float = game.elapsed
	await create_timer(.18, true).timeout
	check(paused and preview.elapsed > before and game.elapsed == game_clock and not game.rounds.running, "Menu atmosphere advances independently while the game remains paused")
	menu.set_process(false)
	preview.set_process(false)
	var air = preview.atmosphere
	var calm: float = 28.0 - air.phase
	var gust: float = 12.0 - air.phase
	var reverse: float = 76.0 - air.phase
	var calm_offset: Vector2 = air.smoke_offset(calm,6)
	var gust_offset: Vector2 = air.smoke_offset(gust,6)
	var reverse_offset: Vector2 = air.smoke_offset(reverse,6)
	check(absf(gust_offset.x) > absf(calm_offset.x)*4 and absf(gust_offset.y) < absf(calm_offset.y), "A sustained gust bends older smoke visibly flatter")
	check(gust_offset.x > 0 and reverse_offset.x < 0 and air.wind_at(gust)>0 and air.wind_at(reverse)<0, "Plumes follow rightward and occasional leftward gusts")
	check(air.smoke_offset(gust,0) == Vector2.ZERO and air.smoke_offset(reverse,0) == Vector2.ZERO, "Fresh smoke stays attached to the chimney during direction changes")
	var lamp_min := 10.0
	var lamp_max := 0.0
	var individual := false
	var bounded := true
	for step in 240:
		var at := step*.5
		var level: float = air.lamp_level(0,at)
		lamp_min = minf(lamp_min,level)
		lamp_max = maxf(lamp_max,level)
		individual = individual or absf(level-air.lamp_level(1,at))>.3
		for emitter in preview.smoke_nodes.size():
			var smoke: Vector2 = air.smoke_offset(at,14.1,emitter)
			bounded = bounded and preview.smoke_nodes[emitter].mesh.custom_aabb.has_point(Vector3(smoke.x,smoke.y,0))
	check(lamp_min>=.34 and lamp_max<=1.45 and lamp_max-lamp_min>.65 and individual, "Each painted lamp dims independently within bounded local brightness")
	check(bounded, "Smoke culling bounds include both wind directions throughout the full cycle")
	var clocks: Array[float] = []
	for rate in [30,60,144]:
		preview.elapsed = 0
		for frame in rate*8: preview._process(1.0/rate)
		clocks.append(preview.elapsed)
	check(absf(clocks[0]-clocks[2])<.00001 and air.smoke_offset(clocks[0],6).distance_to(air.smoke_offset(clocks[2],6))<.001, "30, 60 and 144 Hz produce the same timed gust and plume position")
	await capture("calm",calm)
	await capture("gust-right",gust)
	await capture("gust-left",reverse)
	await capture("reduced",gust,true)
	check(air.ash_count()==7 and not preview.lighting_layer.visible and air.lamp_materials.all(func(lamp): return is_equal_approx(float(lamp.get_shader_parameter("illumination")),1.0)), "Reduced effects limit near ash to seven and disable lamp flicker")
	check(preview.smoke_nodes.all(func(smoke):return bool(smoke.material.get_shader_parameter("reduced_effects"))), "Reduced effects also reach every actual smoke shader")
	game.weather.reduced_effects = false
	for id: String in ["ash_foundry","frozen_rail_yard","abandoned_harbor","mountain_pass","overgrown_steelworks"]:
		for index in menu.environments.size():
			if str(menu.environments[index].id)==id: menu.environment_index=index
		menu._show_environment()
		var atmosphere=menu.preview.atmosphere
		check(menu.preview.smoke_nodes.all(func(smoke):return is_equal_approx(float(smoke.material.get_shader_parameter("gust_strength")),float(atmosphere.weather_profile.get("gust",1.0)))),id+" smoke uses the same gust strength as precipitation")
		check(menu.preview.atmosphere.ash_count()==(28 if id=="ash_foundry" else 0), id+" receives the appropriate particle family")
	check(not game.started and not game.network.active and game.elapsed==game_clock, "Preview effects never start a match or alter gameplay time")
	var report := FileAccess.open(OUTPUT+"measurements.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"prepared_states":true,"checks":checks,"failures":failures,"samples":samples},"  "))
	report.close()
	paused=false
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	view.queue_free()
	await process_frame
	print("MENU ATMOSPHERE: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
