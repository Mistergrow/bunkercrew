extends SceneTree
## Actual thirteen-location scenes, identical camera comparisons and live fauna.
## --capture writes 1920x1080 images; --video-world=<id> records a 12-second clip.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/living-ecology"
const SIZE := Vector2i(1920,1080)
var checks := 0
var failures := 0
var records: Array[Dictionary] = []
var capture_enabled := false
var video_world := ""
var game
var view: SubViewport

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	for child in node.get_children():
		freeze(child)

func ecology_node(name: String) -> Node:
	return game.scenery.get_node_or_null(name)

func stats(node: Node) -> Dictionary:
	if not is_instance_valid(node):
		return {}
	for method in ["debug_stats","diagnostics"]:
		if node.has_method(method):
			var result: Variant = node.call(method)
			if result is Dictionary:
				return result
	return {}

func frames(count: int=3) -> void:
	for index in count:
		await process_frame

func camera_at(at: Vector2,magnification: float) -> void:
	game.camera.position = at
	game.camera.zoom = Vector2.ONE*magnification
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	game.scenery._process(0)
	await frames()

func capture(path: String) -> void:
	if not capture_enabled:
		return
	for index in 2:
		await RenderingServer.frame_post_draw
	var image: Image = view.get_texture().get_image()
	check(image.get_size()==SIZE,path+": exact rendered pixel dimensions")
	check(image.save_png(path)==OK,path+": image saved")

func set_visible(node: Node,value: bool) -> void:
	if is_instance_valid(node) and node is CanvasItem:
		node.visible = value

func prepare(id: String) -> void:
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.start_scenario(1,{"environment":id,"build_type":"bastion","position":"left"})
	game.rounds.running = false
	game.notice = ""
	game.notice_time = 0
	game.weather.lightning_enabled = false
	game.weather.reduced_effects = false
	game.players[0].position = Vector2(790,430)
	game.players[0].velocity = Vector2.ZERO
	for index in 5:
		await physics_frame
	freeze(game)
	game.camera.make_current()
	for name in ["LivingVegetation","LivingFauna"]:
		var node := ecology_node(name)
		check(is_instance_valid(node),id+": integrated "+name+" exists")
		if is_instance_valid(node):
			node.set_process(true)
	await camera_at(Vector2(720,370),1.0)
	await create_timer(.6).timeout

func exercise(entry: Dictionary) -> void:
	var id := str(entry.id)
	await prepare(id)
	var plants := ecology_node("LivingVegetation")
	var fauna := ecology_node("LivingFauna")
	if not is_instance_valid(plants) or not is_instance_valid(fauna):
		await Cleanup.free_scene(game,self)
		return
	var directory := OUTPUT+"/"+id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var captures: Array[String] = []
	for camera in [{"label":"normal","position":Vector2(720,370),"zoom":1.0},{"label":"close","position":Vector2(1090,352),"zoom":2.2}]:
		await camera_at(camera.position,float(camera.zoom))
		await create_timer(.15).timeout
		plants.set_process(false)
		fauna.set_process(false)
		set_visible(plants,false)
		set_visible(fauna,false)
		await capture(directory+"/"+str(camera.label)+"-before.png")
		set_visible(plants,true)
		set_visible(fauna,true)
		await capture(directory+"/"+str(camera.label)+"-after.png")
		captures.append(str(camera.label)+"-before.png")
		captures.append(str(camera.label)+"-after.png")
		plants.set_process(true)
		fauna.set_process(true)
	print("LIVING ECOLOGY CAPTURES "+id+": normal and close comparisons prepared")
	await camera_at(Vector2(720,370),1.0)
	var full_plants := stats(plants)
	var full_fauna := stats(fauna)
	check(int(full_fauna.get("population",0))>=1 and int(full_fauna.get("population",99))<=2,id+": wildlife stays rare and bounded")
	check(int(full_fauna.get("airborne",99))==0,id+": no flying wildlife is enabled")
	game.weather.reduced_effects = true
	await create_timer(.3).timeout
	await capture(directory+"/normal-reduced.png")
	print("LIVING ECOLOGY CAPTURES "+id+": reduced view prepared")
	captures.append("normal-reduced.png")
	var reduced_plants := stats(plants)
	var reduced_fauna := stats(fauna)
	check(int(reduced_plants.get("active_count",999))<=int(full_plants.get("active_count",0)),id+": F3 reduces undergrowth")
	game.weather.reduced_effects = false
	await frames(6)
	var before_pause := [stats(plants),stats(fauna)]
	paused = true
	await frames(4)
	var during_pause := [stats(plants),stats(fauna)]
	for index in 2:
		for key in ["clock","elapsed"]:
			if before_pause[index].has(key):
				check(before_pause[index][key]==during_pause[index].get(key),id+": ecological clock pauses")
	paused = false
	var elapsed_us: Array[float] = []
	var draw_calls: Array[float] = []
	var previous := Time.get_ticks_usec()
	for index in 30:
		await process_frame
		var now := Time.get_ticks_usec()
		elapsed_us.append(float(now-previous))
		previous = now
		draw_calls.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	elapsed_us.sort()
	draw_calls.sort()
	records.append({"id":id,"title":str(entry.title),"captures":captures if capture_enabled else [],"plants":full_plants,"fauna":full_fauna,"reduced_plants":reduced_plants,"reduced_fauna":reduced_fauna,"frozen_fixture_frame_ms_median":elapsed_us[15]/1000.0,"frozen_fixture_frame_ms_p95":elapsed_us[28]/1000.0,"frozen_fixture_draw_calls_median":draw_calls[15]})
	print("LIVING ECOLOGY LOCATION "+id+" plants="+JSON.stringify(full_plants)+" fauna="+JSON.stringify(full_fauna))
	await Cleanup.free_scene(game,self)

func movie(id: String) -> void:
	await prepare(id)
	var fauna := ecology_node("LivingFauna")
	var plants := ecology_node("LivingVegetation")
	if not is_instance_valid(fauna) or not is_instance_valid(plants):
		await Cleanup.free_scene(game,self)
		return
	var at := Vector2(1090,352)
	var target := Vector2(1090,430)
	var subject := ""
	var flee_before := 0
	var subject_index := -1
	var staged_animal := false
	if fauna.has_method("debug_snapshot"):
		var animals: Variant = fauna.call("debug_snapshot")
		if animals is Array:
			for animal: Dictionary in animals:
				flee_before += int(animal.get("flee_events",0))
				var position: Variant = animal.get("position")
				if position is Vector2 and position.y>400 and not bool(animal.get("airborne",true)) and (subject.is_empty() or str(animal.get("species",""))=="mouse"):
					target = position
					at = target+Vector2(0,-80)
					subject = str(animal.get("species",""))
					subject_index = int(animal.get("index",-1))
	if subject_index>=0 and (target.x<800 or target.x>1650) and "entries" in fauna:
		# One explicitly staged ground animal makes its subtle behaviour readable
		# in the video. Ordinary screenshot scenes keep their natural population.
		target = Vector2(1200,430)
		at = target+Vector2(0,-80)
		var animal: Dictionary = fauna.entries[subject_index]
		animal.position = target
		animal.origin = target
		animal.target = target
		animal.ground_range = Vector2(float(game.scenario_bunker.room_right)+48.0,1820.0)
		staged_animal = true
	game.players[0].position = target+Vector2(-155,0)
	await camera_at(at,2.2)
	var frame_index := 0
	var directory := OUTPUT+"/"+id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var frames_directory := directory+"/frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(frames_directory))
	var movie_start := Time.get_ticks_msec()
	while frame_index<360:
		var t := frame_index/30.0
		# A held gallery worker approaches the observed habitat, then steps away.
		if t>=3.0 and t<6.0:
			game.players[0].position = target+Vector2(lerpf(-155.0,-15.0,(t-3.0)/3.0),0)
		elif t>=6.0:
			game.players[0].position = target+Vector2(-15.0-90.0*minf(1,(t-6.0)/2.0),0)
		await process_frame
		if capture_enabled:
			await RenderingServer.frame_post_draw
			var image := view.get_texture().get_image()
			check(image.get_size()==SIZE,id+": exact video-frame dimensions")
			check(image.save_jpg(frames_directory+"/%04d.jpg"%frame_index,.98)==OK,id+": video frame saved")
		if frame_index in [30,100,160,260]:
			await capture(directory+"/motion-%03d.png"%frame_index)
		frame_index += 1
	var flee_after := 0
	if fauna.has_method("debug_snapshot"):
		for animal: Dictionary in fauna.call("debug_snapshot"):
			flee_after += int(animal.get("flee_events",0))
	var report := {"world":id,"frames":frame_index,"size":[SIZE.x,SIZE.y],"encoded_seconds":12,"wall_ms":Time.get_ticks_msec()-movie_start,"subject":subject,"staged_animal":staged_animal,"habitat_target":[target.x,target.y],"flee_events_during_clip":flee_after-flee_before,"fixture":"Actual game rendering, held waves and camera. The existing ground animal may be moved once into the right outdoor habitat for legibility. A stationary worker approaches it at 3s and retreats at 6s. Normal screenshot scenes keep natural spawns. Ecological systems use their normal _process callbacks, with fixed simulation steps of 1/30s. Direct SubViewport readback preserves exact 1920x1080 video pixels.","plants":stats(plants),"fauna":stats(fauna)}
	var file := FileAccess.open(directory+"/video-fixture.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	await Cleanup.free_scene(game,self)

func menu_capture() -> Dictionary:
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames(8)
	var panel = game.hud.main_menu_panel
	for index in panel.environments.size():
		if str(panel.environments[index].id)=="overgrown_steelworks":
			panel.environment_index = index
			panel._show_environment()
			break
	await frames(6)
	check(paused and not game.started,"Main-menu capture preserves paused gameplay")
	var plants: Node = panel.preview.get_node_or_null("LivingVegetation")
	var fauna: Node = panel.preview.get_node_or_null("LivingFauna")
	check(is_instance_valid(plants) and not plants.is_visible_in_tree(),"Main menu does not float playable ground vegetation over the panorama")
	check(is_instance_valid(fauna) and int(stats(fauna).get("population",99))==0,"Main menu has no wildlife")
	await capture(OUTPUT+"/menu-paused.png")
	var record := {"world":"overgrown_steelworks","paused":paused,"started":game.started,"plants":stats(plants),"fauna":stats(fauna),"capture":"menu-paused.png" if capture_enabled else ""}
	paused = false
	await Cleanup.free_scene(game,self)
	return record

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--video-world="):
			video_world = argument.trim_prefix("--video-world=")
	capture_enabled = DisplayServer.get_name()!="headless" and "--capture" in OS.get_cmdline_user_args()
	AudioServer.set_bus_mute(0,true)
	LocaleText.set_locale("de",false)
	if DisplayServer.get_name()!="headless":
		root.mode = Window.MODE_WINDOWED
		root.size = SIZE
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	view = SubViewport.new()
	view.size = SIZE
	view.disable_3d = true
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var preview := TextureRect.new()
	preview.texture = view.get_texture()
	preview.size = Vector2(SIZE)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(preview)
	if not video_world.is_empty():
		await movie(video_world)
	else:
		var entries := ScenarioCatalog.environments(true)
		check(entries.size()==13,"All thirteen locations are represented")
		for entry: Dictionary in entries:
			await exercise(entry)
		var menu := await menu_capture()
		var report := {"checks":checks,"failures":failures,"rendered":capture_enabled,"size":[SIZE.x,SIZE.y],"engine":Engine.get_version_info(),"fixture":"Actual solo scenarios, left bastion, held waves/player physics and all older atmosphere animation. Only the new ecological systems remain live. Before/after pairs use identical camera and frozen ecological state. Times describe this presentation fixture, not combat FPS.","locations":records,"menu":menu}
		var file := FileAccess.open(OUTPUT+"/verification-"+("rendered" if capture_enabled else "headless")+".json",FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"  "))
		file.close()
	preview.queue_free()
	view.queue_free()
	await frames()
	print("LIVING ECOLOGY GALLERY: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
