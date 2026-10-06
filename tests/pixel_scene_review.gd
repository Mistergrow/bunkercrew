extends SceneTree
## Prepared real scenes, rendered at the actual window resolution. No mock
## actors, enlarged post-capture pixels, saved progress or simulated playthrough.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/pixel-animation-pass-20261005/scenes/"
const HD_WORLDS := ["sector07","mountain_pass","flooded_power_station","frozen_rail_yard"]
var game
var entries: Array[Dictionary] = []
var failures := 0
var window_only := false

func _initialize() -> void:
	_run.call_deferred()

func _frames(count: int = 3) -> void:
	for unused in count: await process_frame

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): _freeze(child)

func _world(environment: String, classic: bool = false) -> void:
	seed(194603)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await _frames()
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	var crew: Array[String] = ["mara","branko","ivo","oskar"]
	game.selected_characters = crew
	if classic: game.start(4)
	else: game.start_scenario(4,{"environment":environment,"build_type":"bastion","position":"center"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.notice_time = 0.0
	for unused in 4: await physics_frame
	_freeze(game)
	game.hud._layout_viewport()
	game.weather.set_reduced_effects(false)

func _capture(label: String, magnification: float) -> void:
	game.camera.position = game.camera_target_center
	game.camera.zoom = Vector2.ONE * magnification
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	await _frames()
	game.scenery.elapsed = 6.0
	game.scenery._process(0.0)
	game.hud._layout_viewport()
	await _frames()
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var path := "%s%d-%s.png" % [OUTPUT,root.size.x,label]
	if picture.get_size()!=root.size or picture.save_png(path)!=OK:
		failures += 1
		push_error("Native scene capture failed: " + label)
	var view: Rect2 = game.scenery.get_global_transform_with_canvas().affine_inverse()*root.get_visible_rect()
	var sky_view := Rect2(view.position,Vector2(view.size.x,maxf(0.0,430.0-view.position.y)))
	if not game.scenery.panorama_rect.encloses(sky_view):
		failures += 1
		push_error("Panorama edge visible: " + label)
	var records := {"file":path.trim_prefix(OUTPUT),"label":label,"resolution":[root.size.x,root.size.y],"logical_view":[root.get_visible_rect().size.x,root.get_visible_rect().size.y],"zoom":magnification,"camera":[game.camera.position.x,game.camera.position.y],"players":game.players.size(),"wave":game.rounds.wave,"reduced":game.weather.reduced_effects,"prepared_scene":true,"waves_enabled":false,"native_capture":true,"layers":game.scenery.parallax_background.layers.size() if is_instance_valid(game.scenery.parallax_background) else 0}
	records.window_mode = root.mode
	var native_size := DisplayServer.window_get_size()
	records.native_window_size = [native_size.x,native_size.y]
	var monitor_size := DisplayServer.screen_get_size(root.current_screen)
	records.monitor_size = [monitor_size.x,monitor_size.y]
	entries.append(records)
	print("PIXEL SCENE CAPTURE " + path)

func _dispose() -> void:
	if not await Cleanup.free_scene(game,self): failures += 1
	game = null
	await _frames()

func _run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Pixel scene review needs rendering and --no-profile-save")
		quit(2)
		return
	AudioServer.set_bus_mute(0,true)
	CrewRoster.persistence_enabled = false
	LocaleText.set_locale("de",false)
	window_only = "--window-only" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1440,900)
	await _frames()
	for entry: Dictionary in ScenarioCatalog.environments(true):
		await _world(str(entry.id))
		await _capture(str(entry.id)+"-normal",1.0)
		await _capture(str(entry.id)+"-wide",.6)
		await _dispose()
	await _world("sector07",true)
	await _capture("classic-normal",1.0)
	await _capture("classic-wide",.6)
	await _dispose()
	root.size = Vector2i(1920,1080)
	await _frames()
	for environment: String in HD_WORLDS:
		await _world(environment)
		await _capture(environment+"-normal",1.0)
		await _capture(environment+"-close",2.1)
		await _dispose()
	for dimensions: Vector2i in [Vector2i(960,600),Vector2i(2560,1440)]:
		root.size = dimensions
		await _frames()
		await _world("sector07")
		await _capture("sector07-normal",1.0)
		await _capture("sector07-wide",.6)
		await _dispose()
	# The previous QHD capture can equal the entire monitor. Use a settled,
	# smaller standalone client for the window -> fullscreen -> window check;
	# preserve the actual pre-toggle mode instead of assuming the WM's mode.
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,720)
	await _frames(30)
	await _world("sector07")
	var window_size := root.size
	var window_mode := root.mode
	await _capture("sector07-before-fullscreen",1.0)
	if not window_only:
		game.hud.display_settings.toggle_fullscreen()
		# Native X11 geometry arrives after the mode request; do not capture only
		# the optimistic Window.mode before the window manager resizes the client.
		await _frames(30)
		if root.mode not in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN]:
			failures += 1
			push_error("Standalone fullscreen did not open")
		if root.size!=DisplayServer.screen_get_size(root.current_screen) or root.size!=DisplayServer.window_get_size():
			failures += 1
			push_error("Fullscreen framebuffer does not fill the native monitor: %s / window %s / monitor %s" % [root.size,DisplayServer.window_get_size(),DisplayServer.screen_get_size(root.current_screen)])
		await _capture("sector07-fullscreen",1.0)
		game.hud.display_settings.toggle_fullscreen()
		await _frames(30)
		if root.mode!=window_mode or root.size!=window_size:
			failures += 1
			push_error("Fullscreen did not restore the original window geometry: mode %d -> %d; size %s -> %s" % [window_mode,root.mode,window_size,root.size])
		await _capture("sector07-returned-window",1.0)
	await _dispose()
	var report := FileAccess.open(OUTPUT+"report.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"success":failures==0,"failures":failures,"window_only":window_only,"fullscreen_attempted":not window_only,"fullscreen_accepted":not window_only and failures==0,"scope":"Prepared, frozen real four-player scenes; all 13 worlds plus classic bunker. Native window framebuffers, unchanged project stretch. Waves disabled; no user profile writes. Readability/camera/coverage review, not FPS or playthrough acceptance. Explicit --window-only excludes physical fullscreen acceptance; default still requires real monitor fill and restored window geometry.","captures":entries},"\t")+"\n")
	report.close()
	print("PIXEL SCENE REVIEW: %d native captures, %d failures" % [entries.size(),failures])
	quit(1 if failures else 0)
