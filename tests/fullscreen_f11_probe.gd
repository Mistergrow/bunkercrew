extends SceneTree
## Real scene and actual input path, in a standalone or owned embedded window.
const CLEANUP := preload("res://tests/scene_cleanup.gd")
const DIRECTORY := "res://artifacts/fullscreen-f11"
const OPTIONS := {"environment":"ash_foundry","build_type":"workshop","position":"left"}
var game: Node
var checks := 0
var failures := 0
var embedded_probe := false
var events: Array[Dictionary] = []
var embedded_frames := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("F11_CHECK ",label)
	else:
		failures += 1
		push_error(label)

func frames(count: int = 12) -> void:
	for index in count: await process_frame

func record(name: String) -> void:
	var state := {"name":name,"pid":OS.get_process_id(),"mode":root.mode,"size":[root.size.x,root.size.y],"position":[root.position.x,root.position.y],"embedded":game.hud.display_settings.is_embedded(),"engine_embedded":Engine.call("is_embedded_in_editor") if Engine.has_method("is_embedded_in_editor") else false,"debugger":EngineDebugger.is_active(),"started":game.started,"paused":paused,"menu_audio":game.audio.menu_music.playing,"live_audio":game.audio.live_music.session_active,"clock_seconds":game.audio.menu_rhythm_frame().get("audible_seconds",-1.0)}
	events.append(state)
	var file := FileAccess.open(DIRECTORY+("/embedded-events.json" if embedded_probe else "/standalone-events.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"events":events},"\t"))
	file.close()
	print("F11_STATE ",JSON.stringify(state))

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(DIRECTORY+"/"+name+".png")==OK,"Actual rendered viewport captures "+name)

func key(code: Key, alt: bool = false) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		event.alt_pressed = alt
		Input.parse_input_event(event)
		await process_frame
	await frames(30)

func embedded_tick() -> void:
	embedded_frames += 1
	if embedded_frames==2:
		var release := InputEventKey.new()
		release.keycode = KEY_F11
		release.physical_keycode = KEY_F11
		release.pressed = false
		Input.parse_input_event(release)
	if embedded_frames==30: record("after-embedded-f11")
	if embedded_frames==840:
		process_frame.disconnect(embedded_tick)
		check(false,"The embedded process should complete its acknowledged fullscreen handoff")
		finish.call_deferred()

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		push_error("Use a graphical display and --no-profile-save --no-upnp")
		quit(2)
		return
	embedded_probe = "--embedded-probe" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	LocaleText.set_locale("de",false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--baseline-display="):
			var source := FileAccess.get_file_as_string(argument.trim_prefix("--baseline-display="))
			var script := GDScript.new()
			script.source_code = source
			if script.reload()!=OK:
				quit(2)
				return
			var old: Node = game.hud.display_settings
			game.hud.remove_child(old)
			old.queue_free()
			game.hud.display_settings = script.new()
			game.hud.add_child(game.hud.display_settings)
	await frames(30)
	record("initial-menu")
	check(not game.started and paused and game.audio.menu_music.playing,"Actual menu starts safely with its rave playing")
	if embedded_probe:
		check(game.hud.display_settings.is_embedded(),"Owned child is recognized as embedded")
		if "--wait-handoff" in OS.get_cmdline_user_args():
			# Finish this coroutine before the process quits: keep the observation
			# alive through a regular signal instead of retaining a SceneTree wait.
			process_frame.connect(embedded_tick)
			var pressed := InputEventKey.new()
			pressed.keycode = KEY_F11
			pressed.physical_keycode = KEY_F11
			pressed.pressed = true
			Input.parse_input_event(pressed)
			return
		await key(KEY_F11)
		record("after-embedded-f11")
		await capture("embedded-after-f11")
		check(is_instance_valid(game) and not game.started,"F11 keeps the actual embedded menu scene alive")
		await finish()
		return
	check(not game.hud.display_settings.is_embedded(),"The independent game uses its actual standalone window")
	var original_scene: int = game.get_instance_id()
	var original_size := root.size
	var original_position := root.position
	await capture("01-windowed-menu")
	await key(KEY_F11)
	record("fullscreen-menu")
	check(root.mode==Window.MODE_FULLSCREEN and game.get_instance_id()==original_scene,"F11 enters native fullscreen without replacing or quitting the actual menu")
	check(root.size==DisplayServer.screen_get_size(root.current_screen) and game.audio.menu_music.playing,"Fullscreen fills the actual monitor and keeps menu playback alive")
	await capture("02-fullscreen-menu")
	await key(KEY_F11)
	record("restored-window-menu")
	check(root.mode==Window.MODE_WINDOWED and root.size==original_size,"F11 restores the original window size")
	check(root.position.distance_to(original_position)<4.0,"F11 restores the original window position")
	await capture("03-restored-menu")
	game.start_scenario(1,OPTIONS)
	game.rounds.set_process(false)
	await frames(30)
	game.hud._toggle_match_pause()
	await frames(12)
	await key(KEY_F11)
	check(root.mode==Window.MODE_FULLSCREEN and paused and game.started,"F11 remains safe during a paused actual scenario")
	await capture("04-fullscreen-paused-game")
	await key(KEY_ENTER,true)
	check(root.mode==Window.MODE_WINDOWED and root.size==original_size and paused,"Alt+Enter restores the window while preserving paused gameplay")
	record("restored-paused-game")
	await capture("05-restored-paused-game")
	await finish()

func finish() -> void:
	paused = false
	check(await CLEANUP.free_scene(game,self),"Actual display scenario and all playback release cleanly")
	var file := FileAccess.open(DIRECTORY+("/embedded-verification.json" if embedded_probe else "/standalone-verification.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"events":events},"\t"))
	file.close()
	print("F11 ACTUAL GAME: ",checks-failures,"/",checks," passed")
	quit(0 if failures==0 else 1)
