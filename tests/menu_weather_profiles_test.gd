extends SceneTree
## Actual paused menu at twelve campaign sites, plus GPU-only cloud shapes with
## translation held fixed. All clocks and checkpoints are disposable fixtures.
const OUT := "res://artifacts/menu-weather/"
var checks := 0
var failures := 0
var view: SubViewport
var game
var menu
var preview
var measurements: Array = []
var gpu := false
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("PASS ", label)
func frames(count: int = 3) -> void:
	for unused in count: await process_frame
func pose(at: float, reduced := false) -> void:
	game.weather.reduced_effects = reduced
	preview.elapsed = at
	preview._redraw_clock = 1.0
	preview._process(0.0)
func shot(label: String) -> Image:
	if not gpu: return null
	await frames()
	await RenderingServer.frame_post_draw
	var result := view.get_texture().get_image()
	check(result.save_png(OUT + label + ".png") == OK, label + " QHD capture")
	return result
func pixels_changed(first: Image, second: Image, region: Rect2i, threshold := 3) -> int:
	var a := first.get_data()
	var b := second.get_data()
	var count := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var at := (y * first.get_width() + x) * 4
			if maxi(absi(a[at]-b[at]),maxi(absi(a[at+1]-b[at+1]),absi(a[at+2]-b[at+2]))) >= threshold: count += 1
	return count
func cloud_shape_capture() -> void:
	var isolated := SubViewport.new()
	isolated.size = Vector2i(960,400)
	isolated.transparent_bg = true
	isolated.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	isolated.world_2d = World2D.new()
	root.add_child(isolated)
	var plane := Sprite2D.new()
	plane.centered = false
	plane.texture = preview.cloud_depth_texture
	plane.region_enabled = true
	plane.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	plane.scale = Vector2(960.0/1536.0, 400.0/(1024.0/3.0))
	isolated.add_child(plane)
	for depth in 3:
		plane.region_rect = Rect2(0,depth*1024.0/3.0,1536,1024.0/3.0)
		var shader: ShaderMaterial = preview.cloud_layers[depth].material.duplicate()
		shader.set_shader_parameter("mask_landmarks",false)
		shader.set_shader_parameter("mask_extended_land",false)
		shader.set_shader_parameter("cloud_tint",Color.WHITE)
		plane.material = shader
		var images: Array[Image] = []
		for at in [0.0,14.0]:
			shader.set_shader_parameter("cloud_clock",at)
			await frames()
			await RenderingServer.frame_post_draw
			var picture := isolated.get_texture().get_image()
			picture.convert(Image.FORMAT_RGBA8)
			images.append(picture)
			picture.save_png(OUT + "cloud-fixed-layer%d-t%d.png" % [depth,int(at)])
		var changed := pixels_changed(images[0],images[1],Rect2i(0,0,960,400),2)
		check(changed>250,"Layer%d changes shape with fixed geometry and UV origin"%depth)
		var border_clear := true
		for y in 400:
			border_clear = border_clear and images[1].get_pixel(0,y).a<.005 and images[1].get_pixel(959,y).a<.005
		check(border_clear,"Layer%d morph never exposes a rectangular atlas edge"%depth)
		shader.set_shader_parameter("cloud_clock",14.0)
		await frames()
		await RenderingServer.frame_post_draw
		check(isolated.get_texture().get_image().get_data()==images[1].get_data(),"Layer%d exact same scene clock freezes every cloud pixel"%depth)
		measurements.append({"cloud_depth":depth,"fixed_geometry_changed_pixels_14s":changed})
	isolated.queue_free()
	await frames()
func water_surface_capture() -> void:
	var isolated := SubViewport.new()
	isolated.size = Vector2i(960,320)
	isolated.world_2d = World2D.new()
	isolated.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(isolated)
	var surface := Sprite2D.new()
	surface.centered = false
	surface.texture = preview.panorama.texture
	surface.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	surface.scale = Vector2(960,320) / surface.texture.get_size()
	var shader: ShaderMaterial = preview.sky_material.duplicate()
	surface.material = shader
	isolated.add_child(surface)
	var pictures: Array[Image] = []
	for at in [0.0,2.0]:
		shader.set_shader_parameter("sky_clock",at)
		await frames()
		await RenderingServer.frame_post_draw
		var frame := isolated.get_texture().get_image()
		frame.convert(Image.FORMAT_RGBA8)
		frame.save_png(OUT+"water-isolated-t%d.png"%int(at))
		pictures.append(frame)
	var changed := pixels_changed(pictures[0],pictures[1],Rect2i(16,210,928,80),3)
	check(changed>300,"Painted harbor reflections move with all clouds and foreground removed")
	measurements.append({"isolated_water_changed_pixels_2s":changed})
	isolated.queue_free()
	await frames()

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	gpu = DisplayServer.get_name() != "headless" and "--capture" in OS.get_cmdline_user_args()
	AudioServer.set_bus_mute(0,true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
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
	menu = game.hud.main_menu_panel
	menu.set_process(false)
	var game_clock: float = game.elapsed
	for environment: Dictionary in ScenarioCatalog.environments(true):
		if environment.id == "sector07": continue
		for index in menu.environments.size():
			if menu.environments[index].id == environment.id: menu.environment_index = index
		menu._show_environment()
		menu.decoration.queue_redraw()
		preview = menu.preview
		preview.set_process(false)
		var air = preview.atmosphere
		pose(12.0-air.phase)
		var normal_count: int = air.precipitation_count()+air.ash_count()
		check(air.weather_profile == air.MENU_PROFILES[environment.id],environment.id+" has its own weather profile")
		check(normal_count>0 and normal_count<=156,environment.id+" particles remain finite and resolution-independent")
		check(preview.cloud_speed(0)<preview.cloud_speed(1) and preview.cloud_speed(1)<preview.cloud_speed(2),environment.id+" retains three different cloud speeds")
		check(preview.props_layer.presentation_weather==air,environment.id+" trees share menu wind without touching game weather")
		if not environment.get("water_regions",[]).is_empty():
			check(air.water_mist!=null and is_instance_valid(air.water_mist_layer),environment.id+" uses the imported generated mist atlas")
			check(air.water_mist_layer.material.shader.resource_path=="res://shaders/menu_water_mist.gdshader",environment.id+" mist uses clean alpha edges and biome tint")
		if gpu and environment.id=="abandoned_harbor": await water_surface_capture()
		var first: Image
		if gpu: first = await shot(environment.id+"-t12")
		pose(23.0-air.phase)
		if gpu and environment.id in ["ash_foundry","abandoned_harbor","frozen_rail_yard","storm_dam","radar_highlands","flooded_power_station"]:
			var second: Image = await shot(environment.id+"-t23")
			var changed := pixels_changed(first,second,Rect2i(1540,290,940,750))
			check(changed>200,environment.id+" actual scene changes over eleven seconds")
			measurements.append({"environment":environment.id,"animated_pixels":changed})
		if bool(environment.get("lightning",false)):
			pose(20.2-air.phase)
			check(air.storm_strength(preview.elapsed)>.6,environment.id+" has a distant storm pulse")
			if gpu: await shot(environment.id+"-storm")
		var started := Time.get_ticks_usec()
		for frame in 240: preview._process(1.0/60.0)
		var update_ms := (Time.get_ticks_usec()-started)/1000.0
		measurements.append({"environment":environment.id,"normal_particle_limit":normal_count,"cpu_240_steps_ms":update_ms})
		pose(20.2-air.phase,true)
		check(air.precipitation_count()+air.ash_count()<=ceili(normal_count/4.0),environment.id+" F3 quarters particles")
		check(air.storm_strength(preview.elapsed)==0.0,environment.id+" F3 disables lightning")
		check(preview.cloud_layers.all(func(layer):return is_equal_approx(float(layer.material.get_shader_parameter("cloud_morph_strength")),.16)),environment.id+" F3 reduces shape deformation")
		if gpu and environment.id in ["storm_dam","frozen_rail_yard"]: await shot(environment.id+"-reduced")
		game.weather.reduced_effects = false
	pose(0)
	if gpu: await cloud_shape_capture()
	check(paused and game.elapsed==game_clock and not game.started and not game.network.active,"All twelve menu scenes leave paused gameplay and network untouched")
	var report := FileAccess.open(OUT+"measurements.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"gpu":gpu,"prepared_states":true,"measurements":measurements},"  "))
	report.close()
	paused = false
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	view.queue_free()
	await process_frame
	print("MENU WEATHER PROFILES: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
