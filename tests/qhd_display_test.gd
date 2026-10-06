extends SceneTree
## Real main-scene UI and world projection at 16:10, Full HD, and native QHD.
## GPU mode captures fixtures and injects mouse events in physical window pixels.

const DESTINATION := "res://artifacts/qhd-display"
var game
var checks := 0
var failures := 0
var captures: Array[Dictionary] = []
var graphical := false

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if value: print("PASS ",label)
	else:
		failures += 1
		push_error(label)

func frames(count: int = 4) -> void:
	for frame in count: await process_frame

func settle_window() -> void:
	# Native window-manager configure events arrive after the setter returns.
	if graphical: await create_timer(0.16,true).timeout
	await frames(6)

func key(code: Key,alt: bool = false) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.alt_pressed = alt
		event.pressed = down
		root.push_input(event)
		await process_frame
	await frames()

func click_physical(button: Button) -> void:
	var logical_point := button.get_global_rect().get_center()
	var physical_point := root.get_final_transform()*logical_point
	# push_input(false) uses the same stretch conversion as window input events.
	var motion := InputEventMouseMotion.new()
	motion.position = physical_point
	motion.global_position = physical_point
	root.push_input(motion,false)
	await process_frame
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = physical_point
		event.global_position = physical_point
		root.push_input(event,false)
		await process_frame
	await frames()

func capture(label: String) -> void:
	if not graphical: return
	await frames()
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(DESTINATION+"/"+label+".png")
	captures.append({"file":label+".png","window":[root.size.x,root.size.y],"rendered":[image.get_width(),image.get_height()],"logical_viewport":[root.get_visible_rect().size.x,root.get_visible_rect().size.y]})
	check(image.get_size()==root.size,label+" renders at native output resolution")

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Use --no-profile-save with an isolated XDG_DATA_HOME")
		quit(1)
		return
	graphical = DisplayServer.get_name()!="headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DESTINATION))
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	root.size = Vector2i(1440,900)
	root.position = Vector2i.ZERO
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	await frames(8)
	check(is_instance_valid(game.hud.main_menu_panel) and not is_instance_valid(game.scenery),"Main menu loads its own preview without constructing the legacy world")
	if failures:
		await finish()
		return
	root.size = Vector2i(1440,900)
	await settle_window()
	check(root.content_scale_mode==Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,"Canvas items render at the target resolution")
	check(root.content_scale_aspect==Window.CONTENT_SCALE_ASPECT_EXPAND,"Widescreen expands the world without letterboxing or distortion")
	check(game.hud.canvas.position.is_equal_approx(Vector2.ZERO),"Existing 1440×900 UI keeps its original layout")
	for output in [Vector2i(1920,1080),Vector2i(2560,1440)]:
		# A 1440-high decorated window cannot fit inside a 1440-high desktop.
		# Native fullscreen is the user path for monitor-sized QHD output.
		if graphical and output==Vector2i(2560,1440): root.mode = Window.MODE_FULLSCREEN
		else: root.size = output
		await settle_window()
		check(root.size==output,"Window accepts %d×%d"%[output.x,output.y])
		check(root.get_visible_rect().size.is_equal_approx(Vector2(1600,900)),"16:9 exposes a proportional 1600×900 logical world")
		check(game.hud.canvas.position.is_equal_approx(Vector2(80,0)),"HUD and menus stay centered with 80 logical pixels on either side")
		var full_rect: Rect2 = game.hud.screen_rect()
		check(full_rect.size.is_equal_approx(Vector2(1600,900)) and full_rect.position.is_equal_approx(Vector2(-80,0)),"Menu and modal backdrop cover the complete widescreen output")
		var controls_visible := true
		for button in game.hud.buttons:
			controls_visible = controls_visible and root.get_visible_rect().encloses(button.get_global_rect())
		check(controls_visible,"Every main-menu control remains inside the visible output")
		await capture("menu-%dx%d"%[output.x,output.y])
	if graphical:
		await click_physical(game.hud.main_menu_panel.mode_buttons[0])
		check(game.hud.overlay=="scenario","Physical QHD mouse click activates the visible Solo button")
	else:
		await key(KEY_SPACE)
	check(game.hud.overlay=="scenario","Solo setup opens at QHD")
	await capture("scenario-2560x1440")
	await key(KEY_ESCAPE)
	check(game.hud.overlay=="menu","Escape returns to the centered QHD main menu")
	if graphical:
		root.mode = Window.MODE_WINDOWED
		await settle_window()
		root.size = Vector2i(1280,720)
		await settle_window()
		await key(KEY_F11)
		await settle_window()
		check(root.mode==Window.MODE_FULLSCREEN,"F11 enters monitor-native fullscreen from the menu")
		check(root.size==DisplayServer.screen_get_size(root.current_screen),"Fullscreen uses the monitor's actual output resolution")
		await capture("menu-fullscreen")
		var previous_id: int=game.get_instance_id()
		game.restart()
		await settle_window()
		game=current_scene
		check(game.get_instance_id()!=previous_id and root.mode==Window.MODE_FULLSCREEN,"Scene reload preserves fullscreen")
		await key(KEY_F11)
		await settle_window()
		check(root.mode==Window.MODE_WINDOWED and root.size==Vector2i(1280,720),"F11 restores the previous window size")
		await key(KEY_F11)
		await settle_window()
	game.start_scenario(2,{"environment":"overgrown_steelworks","build_type":"bastion","position":"left"})
	check(game.started and game.players.size()==2 and is_instance_valid(game.core),"QHD gameplay fixture starts both real workers and the bunker")
	if failures:
		await finish()
		return
	game.rounds.running = false
	game.rounds.set_process(false)
	game.set_process(false)
	game.camera.position = Vector2(720,450)
	game.camera.zoom = Vector2.ONE
	game.camera.force_update_scroll()
	await frames(8)
	game.hud.overlay = ""
	await frames()
	var world_point := Vector2(920,340)
	var viewport_point: Vector2 = root.get_canvas_transform()*world_point
	var ui_point: Vector2 = game.hud.world_to_ui(world_point)
	check((game.hud.canvas.get_global_transform_with_canvas()*ui_point).is_equal_approx(viewport_point),"Interaction markers project back onto their actual world objects after UI centering")
	var overlay = game.hud.combat_overlay
	overlay.set_process(false)
	overlay.numbers.clear()
	overlay.banners.clear()
	overlay.boss.clear()
	overlay.handle_event("hit",{"position":world_point,"amount":12,"earned":1,"player_id":1})
	var numbers: Array = overlay.number_layout()
	check(numbers.size()==1,"QHD combat damage text is placed on screen")
	if numbers.size()==1:
		var projected: Vector2 = overlay.get_global_transform_with_canvas()*numbers[0].position
		check(projected.is_equal_approx(viewport_point+Vector2(-24,-38)),"Damage text stays over its target without a duplicated widescreen offset")
	overlay.numbers.clear()
	overlay.queue_redraw()
	if graphical:
		var physical_point: Vector2 = root.get_final_transform()*viewport_point
		DisplayServer.warp_mouse(Vector2i(physical_point))
		await settle_window()
		check(game.get_global_mouse_position().distance_to(world_point)<1,"Physical QHD mouse coordinates aim at the intended world point")
	await capture("coop-2560x1440")
	await key(KEY_ESCAPE)
	check(paused and game.hud.overlay=="pause","Pause remains functional at QHD")
	await capture("pause-2560x1440")
	if graphical:
		await key(KEY_ENTER,true)
		await settle_window()
		check(root.mode==Window.MODE_WINDOWED and paused,"Alt+Enter leaves fullscreen while the game is paused")
		await key(KEY_F11)
		await settle_window()
		check(root.mode==Window.MODE_FULLSCREEN and paused,"Returning to fullscreen preserves pause state")
	await finish()

func finish() -> void:
	paused = false
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"QHD test releases scene and audio cleanly")
	if graphical:
		var metadata := FileAccess.open(DESTINATION+"/capture-metadata.json",FileAccess.WRITE)
		metadata.store_string(JSON.stringify({"fixture":"Actual main scene; menu/setup unchanged. Coop fixture uses two players in Overgrown Steelworks/Bastion/left, rounds stopped and camera fixed at zoom 1 for reproducible HUD review.","captures":captures,"checks":checks,"failures":failures},"\t"))
	print("QHD DISPLAY: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
