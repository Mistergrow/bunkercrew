extends SceneTree
## Real production scenes. The elevated co-op fixture exposes sky/soil at the
## widest follow zoom; overview and normal follow views use the same actors.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var failures := 0
var records: Array[Dictionary] = []
var view: SubViewport
var output := "res://artifacts/wide-world/after"
var benchmarks: Array[Dictionary] = []
var motion_checks: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func frames(count: int = 8) -> void:
	for unused in count:
		await process_frame

func timing_summary(samples: Array[float]) -> Dictionary:
	samples.sort()
	return {"median_ms":samples[int(samples.size()*.5)],"p95_ms":samples[int(samples.size()*.95)],"samples":samples.size()}

func measure(game: Node, environment: String) -> void:
	var sky: Node2D = game.scenery.get_node_or_null("UpperSky")
	if sky == null:
		return
	# Freeze this node so visibility stays under test control. All other render
	# systems are the same in the paired observations; no production file changes.
	game.scenery.set_process(false)
	for enabled in [true, false, true]:
		sky.visible = enabled
		await frames(24)
		var gpu: Array[float] = []
		var cpu: Array[float] = []
		for unused in 90:
			await RenderingServer.frame_post_draw
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid()))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid()))
		benchmarks.append({"environment":environment,"upper_sky_visible":enabled,"gpu":timing_summary(gpu),"cpu":timing_summary(cpu)})
	game.scenery.set_process(true)

func check_motion(game: Node, environment: String) -> void:
	var previous_mode: Node.ProcessMode = game.process_mode
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.scenery._process(0)
	await frames(3)
	await RenderingServer.frame_post_draw
	var first := view.get_texture().get_image()
	first.convert(Image.FORMAT_RGBA8)
	game.scenery._process(8.0)
	await frames(3)
	await RenderingServer.frame_post_draw
	var second := view.get_texture().get_image()
	second.convert(Image.FORMAT_RGBA8)
	var before := first.get_data()
	var after := second.get_data()
	var changed := 0
	var touched: Dictionary = {}
	# No HUD, horizon, actors, water or scenery emitters enter this high-sky ROI.
	for y in range(120, 520):
		for x in range(64, 2496):
			var offset := (y * 2560 + x) * 4
			var difference := 0
			for channel in 3:
				difference = maxi(difference, absi(int(before[offset + channel]) - int(after[offset + channel])))
			if difference >= 6:
				changed += 1
				touched[Vector2i(floori(x/100.0), floori(y/100.0))] = true
	var passed := changed >= 2500 and touched.size() >= 12
	if not passed:
		failures += 1
	motion_checks.append({"environment":environment,"seconds":8,"changed_pixels":changed,"active_100px_blocks":touched.size(),"passed":passed})
	print("WIDE_WORLD_MOTION ", environment, " pixels=", changed, " blocks=", touched.size(), " passed=", passed)
	if environment == "ash_foundry":
		first.save_png(output + "/upper-cloud-motion-0s.png")
		second.save_png(output + "/upper-cloud-motion-8s.png")
	game.process_mode = previous_mode

func record_clouds(game: Node) -> void:
	var previous_mode: Node.ProcessMode = game.process_mode
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var directory := output + "/ash-foundry-frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for frame in 240:
		# Eight seconds at the production clock rate, a fixed camera and no actor
		# motion. JPEG frames are temporary inputs to the local video encoder.
		game.scenery._process(1.0/30.0)
		await RenderingServer.frame_post_draw
		view.get_texture().get_image().save_jpg(directory + "/%04d.jpg" % frame, .94)
	game.process_mode = previous_mode

func capture(game: Node, environment: String, mode: String, magnification: float) -> void:
	game.player_camera.mode = mode
	game.player_camera.view_zoom = magnification
	game.player_camera.update_view(0, true)
	await frames(12)
	await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	var filename := "%s-%s-%.2f.png" % [environment, mode, magnification]
	if picture.get_size() != view.size or picture.save_png(output + "/" + filename) != OK:
		failures += 1
	var visible: Rect2 = view.get_canvas_transform().affine_inverse() * view.get_visible_rect()
	records.append({"file":filename,"environment":environment,"mode":mode,"requested_zoom":magnification,"actual_zoom":game.camera.zoom.x,"camera":[game.camera.position.x,game.camera.position.y],"visible_world":[visible.position.x,visible.position.y,visible.size.x,visible.size.y],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"rendered_objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)})
	print("WIDE_WORLD_CAPTURE ", filename, " actual_zoom=", game.camera.zoom.x)

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	root.size = Vector2i(320, 180)
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	var quick := baseline or "--quick" in OS.get_cmdline_user_args()
	var benchmark := "--benchmark" in OS.get_cmdline_user_args()
	if benchmark:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 120
	if baseline:
		output = "res://artifacts/wide-world/before"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	view = SubViewport.new()
	view.size = Vector2i(2560, 1440)
	view.size_2d_override = Vector2i(1600, 900)
	view.size_2d_override_stretch = true
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	if benchmark:
		RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), true)
	LocaleText.set_locale("en", false)
	for entry: Dictionary in ScenarioCatalog.environments():
		if quick and entry.id not in ["ash_foundry", "abandoned_harbor", "frozen_rail_yard"]:
			continue
		var game = load("res://scenes/main.tscn").instantiate()
		view.add_child(game)
		game.start_scenario(2, {"environment":entry.id,"build_type":"bastion","position":"center"})
		game.rounds.set_process(false)
		game.rounds.wave = 9
		game.set_process(false)
		game.medic.set_physics_process(false)
		game.flak_station.unlock()
		game.flak_station._complete()
		game.notice_time = 0
		game.dialogue.reset()
		for worker in game.players:
			worker.set_physics_process(false)
			worker.focus = null
		game.players[0].position = game.flak_station.gun_position + Vector2(-20, 0)
		game.players[1].position = Vector2(game.scenario_bunker.room_right - 130, 245)
		game.scenery.elapsed = 6.0
		await capture(game, str(entry.id), "follow", .45)
		if "--motion" in OS.get_cmdline_user_args():
			await check_motion(game, str(entry.id))
		if "--record" in OS.get_cmdline_user_args() and entry.id == "ash_foundry":
			await record_clouds(game)
		if benchmark:
			await measure(game, str(entry.id))
		if not quick:
			# Late expanded overview reaches the supported .25 lower clamp.
			game.camera_target_center = Vector2(720, 460)
			game.camera_target_zoom = .50
			await capture(game, str(entry.id), "overview", .45)
			if entry.id in ["ash_foundry", "abandoned_harbor", "frozen_rail_yard"]:
				game.players[0].position = Vector2(720, 245)
				game.players[1].position = Vector2(820, 245)
				await capture(game, str(entry.id), "follow", 1.25)
		if not await Cleanup.free_scene(game, self):
			failures += 1
	view.queue_free()
	await frames()
	var file := FileAccess.open(output + "/captures.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"resolution":[2560,1440],"logical_resolution":[1600,900],"renderer":RenderingServer.get_current_rendering_driver_name(),"fixture":"Production scenarios, center/bastion, local co-op, prepared wave 9 and built Flak I, P1 on tower/P2 on roof, stopped wave/actor/game processing, live scenery/weather. No simulated gameplay progression. Overview manually prepared to supported .25 zoom; normal follow workers together on roof. Empty transient notice and dialogue.","captures":records,"failures":failures}, "\t"))
	if benchmark:
		var measurement := FileAccess.open(output + "/sky-timings.json", FileAccess.WRITE)
		measurement.store_string(JSON.stringify({"note":"Viewport GPU/CPU milliseconds reported by Godot, QHD full game, 90 frames after 24 warmup frames, upper sky visible/hidden/visible. Scenery callbacks are frozen during each paired observation. Zero values mean renderer does not expose timing. This machine has other open GPU applications; numbers are indicative and are not minimum hardware claims.","cases":benchmarks}, "\t"))
	if not motion_checks.is_empty():
		var motion := FileAccess.open(output + "/upper-cloud-motion.json", FileAccess.WRITE)
		motion.store_string(JSON.stringify({"note":"Actual QHD rendered pixels with a fixed wide camera, actors/game disabled and only ScenarioScenery advanced by 8 seconds. ROI x64..2496,y120..520 excludes HUD, horizon, actors and water. A pixel counts when any RGB channel changes by at least6/255.","checks":motion_checks}, "\t"))
	print("WIDE_WORLD_PREVIEW ", records.size(), " captures, failures=", failures)
	quit(1 if failures else 0)
