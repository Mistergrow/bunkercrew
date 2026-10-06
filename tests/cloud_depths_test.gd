extends SceneTree
## Native pixels from the current WeatherSky plate in actual game scenes.
## Older atlas planes are hidden even in the classic bunker; their isolated
## wrap checks cannot establish visible gameplay cloud movement.
const DESTINATION := "res://artifacts/cloud-depths"
const Cleanup := preload("res://tests/scene_cleanup.gd")
const SCREEN := Vector2i(1440,900)
const PIXEL_THRESHOLD := 6
const MIN_VISIBLE_PIXELS := 350
const MIN_MOVING_PIXELS := 300
const COUNT_CAP := 5000
var checks := 0
var failures := 0
var measurements: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	print("CLOUD DEPTH %s: %s"%["PASS" if value else "FAIL",label])
	if not value: failures += 1

func freeze_callbacks(node: Node) -> void:
	# Keep real input routing, but stop unrelated gameplay/presentation clocks.
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze_callbacks(child)

func key(code: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event)
		await process_frame

func picture() -> Image:
	for frame in 2: await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	result.convert(Image.FORMAT_RGBA8)
	return result

func sky_frame(scenery: ScenarioScenery,seconds: float) -> Image:
	# Use the real owner's frame geometry/shader update. No texture or
	# production transform is replaced; unrelated animated layers are hidden.
	scenery.elapsed = seconds
	scenery._process(0.0)
	var depths = scenery.parallax_background
	depths.sky_traffic.hide()
	depths.mist.hide()
	depths.layers[2].material.set_shader_parameter("scene_clock",0.0)
	depths.layers[2].material.set_shader_parameter("motion_gain",0.0)
	return await picture()

func channel_difference(a: PackedByteArray,b: PackedByteArray,at: int) -> int:
	return maxi(absi(a[at]-b[at]),maxi(absi(a[at+1]-b[at+1]),absi(a[at+2]-b[at+2])))

func changed_sky(a: Image,b: Image,exposed: Image,occluded: Image) -> int:
	var first := a.get_data()
	var second := b.get_data()
	var with_sky := exposed.get_data()
	var without_sky := occluded.get_data()
	var changed := 0
	# A wide, real camera reveals the sky. Per-scene rendered contribution
	# excludes buildings/mountains covering it instead of assuming the obsolete
	# panorama's fixed measurement strip is open sky in every environment.
	for y in range(16,650):
		for x in range(16,SCREEN.x-16):
			var at := (y*a.get_width()+x)*4
			if channel_difference(with_sky,without_sky,at)<PIXEL_THRESHOLD: continue
			if channel_difference(first,second,at)>=PIXEL_THRESHOLD:
				changed += 1
				# Explicit lower bounds avoid expensive scans once far beyond
				# both acceptance thresholds; the thresholds are unchanged.
				if changed==COUNT_CAP: return changed
	return changed

func exercise(entry: Dictionary,classic: bool=false) -> void:
	var label := "classic_sector07" if classic else str(entry.id)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	if classic: game.start(1)
	else: game.start_scenario(1,{"environment":entry.id,"build_type":"bastion","position":"left"})
	# Settle scene creation and deferred drawing before holding its clocks.
	for settle in 4: await process_frame
	freeze_callbacks(game)
	game.hud.canvas.hide()
	game.weather.hide()
	# The court's work lamps use GPU TIME; freezing GDScript callbacks cannot
	# stop them. Exclude this unrelated foreground from exact sky comparisons.
	if is_instance_valid(game.perimeter):
		var courtyard: CanvasItem=game.perimeter.get_node_or_null("ServiceCourtyard")
		if is_instance_valid(courtyard): courtyard.hide()
	game.camera.position = Vector2(720,-180)
	game.camera.zoom = Vector2(.65,.65)
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	var scenery: ScenarioScenery = game.scenery
	# Classic's original room lights have a separate clock from the sky.
	if classic:
		var room_lighting: CanvasItem=scenery.get("lighting")
		if is_instance_valid(room_lighting): room_lighting.hide()
	scenery._visible_rect = scenery.get_global_transform_with_canvas().affine_inverse()*scenery.get_viewport_rect()
	scenery.set_layered_enabled(true)
	for layer in [scenery.particle_layer,scenery.mist_layer,scenery.lighting_layer,scenery.surface_layer,scenery.props_layer]: layer.hide()
	var depths = scenery.parallax_background
	check(is_instance_valid(depths),label+": real game enables its current painted depth renderer")
	if not is_instance_valid(depths):
		await Cleanup.free_scene(game,self)
		return
	check(depths.layers.size()==3 and depths.layers[0].name=="WeatherSky",label+": sky/landscape/landmarks are the actual three painted plates")
	check(not scenery.cloud_layer.is_visible_in_tree(),label+": hidden legacy atlas planes are excluded from pixel evidence")
	var traffic = depths.sky_traffic
	check(traffic.far_clouds.get_index()<traffic.light_layer.get_index() and traffic.light_layer.get_index()<traffic.near_clouds.get_index(),label+": current traffic lights sit between two terrain-occluded cloud planes")
	check(depths.layers[0].get_index()<traffic.get_index() and traffic.get_index()<depths.layers[1].get_index(),label+": actual distant terrain may correctly conceal additional traffic clouds")
	depths.layers[0].hide()
	var empty := await sky_frame(scenery,0.0)
	depths.layers[0].show()
	var first := await sky_frame(scenery,0.0)
	var second := await sky_frame(scenery,3.0)
	check(first.get_size()==SCREEN and second.get_size()==SCREEN,label+": native capture uses the requested screen dimensions")
	var contribution := changed_sky(empty,first,first,empty)
	var motion := changed_sky(first,second,first,empty)
	check(contribution>=MIN_VISIBLE_PIXELS and motion>=MIN_MOVING_PIXELS,"%s current sky: %d visible / %d moving pixels in 3 seconds (counts capped at %d)"%[label,contribution,motion,COUNT_CAP])
	# Without the selected sky, every remaining pixel must stay fixed. Mist,
	# water, lights and actors must not make a sky movement assertion pass.
	depths.layers[0].hide()
	var without_later_sky := await sky_frame(scenery,3.0)
	check(empty.get_data()==without_later_sky.get_data(),label+": sky absence leaves every remaining pixel unchanged")
	depths.layers[0].show()
	await key(KEY_F3)
	scenery.elapsed = 0.0
	scenery._process(3.0)
	check(game.weather.reduced_effects and is_equal_approx(scenery.elapsed,.75),label+": actual F3 retains the owner's quarter-speed clock")
	check(not traffic.visible and not depths.mist.visible and depths.materials.all(func(surface):return surface.get_shader_parameter("motion_gain")==0.0),label+": actual F3 disables added clouds/lights/mist and all plate animation")
	var reduced_first := await sky_frame(scenery,0.0)
	var reduced_second := await sky_frame(scenery,3.0)
	check(reduced_first.get_data()==reduced_second.get_data(),label+": F3 freezes every rendered extra sky pixel")
	await key(KEY_F3)
	var restored := await sky_frame(scenery,0.0)
	check(not game.weather.reduced_effects and restored.get_data()==first.get_data(),label+": actual F3 restores the same full-effects sky at the same clock")
	var running := await sky_frame(scenery,3.0)
	var stopped_clock := scenery.elapsed
	scenery.set_process(true)
	paused = true
	var paused_frame := await picture()
	check(scenery.elapsed==stopped_clock and running.get_data()==paused_frame.get_data(),label+": real tree pause freezes the owner clock and all sky pixels")
	scenery.set_process(false)
	paused = false
	if "--capture" in OS.get_cmdline_user_args():
		first.save_png(DESTINATION+"/%s-current-sky-t0.png"%label)
		second.save_png(DESTINATION+"/%s-current-sky-t3.png"%label)
	measurements.append({"world":label,"actual_renderer":"ParallaxLandscape.WeatherSky","visible_pixels_lower_bound":contribution,"moving_pixels_3s_lower_bound":motion,"count_cap":COUNT_CAP,"rgb_difference_threshold":PIXEL_THRESHOLD,"camera":str(game.camera.position),"zoom":game.camera.zoom.x,"sky_rect":str(depths.layer_rects[0]),"unrelated_pixels_identical":empty.get_data()==without_later_sky.get_data()})
	check(await Cleanup.free_scene(game,self),label+": real scene and presentation/audio resources release")

func run() -> void:
	if DisplayServer.get_name()=="headless" or not "--no-profile-save" in OS.get_cmdline_user_args():
		push_error("Cloud depth test requires a graphical renderer and --no-profile-save")
		quit(1)
		return
	root.size = SCREEN
	AudioServer.set_bus_mute(0,true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DESTINATION))
	var entries := ScenarioCatalog.environments(true)
	check(entries.size()==13,"all thirteen current free-play/campaign environments are measured")
	for entry: Dictionary in entries: await exercise(entry)
	await exercise(ScenarioCatalog.environment("sector07"),true)
	var report := FileAccess.open(DESTINATION+"/measurements.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"prepared":"Actual solo starts for all13 environments plus actual classic game.start(1); camera720,-180 zoom0.65; independent WeatherSky motion at0/3s; terrain-derived exposed-sky contribution mask; remaining clocks frozen; real F3 and tree pause.","historical_test":"Three legacy cloud_layers are hidden on all continuous backgrounds, including classic. Their isolated atlas wraps are not counted as current gameplay acceptance.","worlds":measurements},"\t"))
	report.close()
	print("CLOUD DEPTHS: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
