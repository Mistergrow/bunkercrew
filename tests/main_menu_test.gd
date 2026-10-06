extends SceneTree
## Actual main scene and native controls. No hosting, UPnP, or profile writes.
## Keyboard/joypad events exercise focus routing before any match is started.

var game
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if value:
		print("PASS ",label)
	else:
		failures += 1
		push_error(label)

func frames(count: int = 3) -> void:
	for frame in count:
		await process_frame

func key(code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await frames()

func joy(button: JoyButton) -> void:
	for down in [true,false]:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = button
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await frames()

func click(button: Button) -> void:
	# Dummy display has no mouse-entered window for native hit testing. The GPU
	# run below exercises physical mouse events; headless uses the same button.
	if DisplayServer.get_name()=="headless":
		button.grab_focus()
		await key(KEY_ENTER)
		return
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await process_frame
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = point
		event.global_position = point
		Input.parse_input_event(event)
		await process_frame
	await frames()

func menu():
	return game.hud.main_menu_panel

func unopened(label: String) -> void:
	check(not game.started and not game.rounds.running and paused and game.network.state=="offline" and not game.network.active,label)

func _control_layout_clear(panel) -> bool:
	var controls: Array = []
	controls.append_array(panel.mode_buttons)
	controls.append_array(panel.utility_buttons)
	controls.append(panel.friends_button)
	controls.append(panel.preview_previous)
	controls.append(panel.preview_next)
	controls.append(panel.story_button)
	controls.append(panel.quit_button)
	var bounds := Rect2(0,0,1440,900)
	for index in controls.size():
		var rect: Rect2 = controls[index].get_global_rect()
		if not bounds.encloses(rect) or rect.size.x<30 or rect.size.y<30:
			return false
		for other in range(index+1,controls.size()):
			if rect.intersects(controls[other].get_global_rect()):
				return false
	return true

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Run with --no-profile-save to preserve player progress")
		quit(1)
		return
	# The headless window starts at 64x64; use the authored test layout explicitly.
	root.size = Vector2i(1440,900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	await frames(6)
	check(game.hud.overlay=="menu" and "main_menu_panel" in game.hud and is_instance_valid(game.hud.main_menu_panel),"Fresh main scene opens the redesigned menu")
	if not "main_menu_panel" in game.hud or not is_instance_valid(game.hud.main_menu_panel):
		await _finish()
		return
	unopened("Main menu holds the game without starting a wave or network socket")
	check(menu().mode_buttons.size()==3 and menu().utility_buttons.size()==3 and _control_layout_clear(menu()),"All three modes, utilities, and preview arrows fit without overlapping")
	check(is_instance_valid(menu().quit_button) and menu().quit_button.text == LocaleText.text("Beenden"), "The clean main menu exposes its real Quit action")
	check(menu().mode_buttons[0].has_focus(),"Solo receives initial keyboard/controller focus")
	var accept_bindings: int = InputMap.action_get_events("ui_accept").size()
	var cancel_bindings: int = InputMap.action_get_events("ui_cancel").size()
	InputSetup.install()
	InputSetup.install()
	check(InputMap.action_get_events("ui_accept").size()==accept_bindings and InputMap.action_get_events("ui_cancel").size()==cancel_bindings,"Repeated scene input setup preserves controller bindings without duplicating them")
	var elapsed: float = menu().elapsed
	var game_elapsed: float = game.elapsed
	await create_timer(0.18,true).timeout
	check(menu().elapsed>elapsed and is_equal_approx(game.elapsed,game_elapsed),"Menu animation advances while the simulation stays paused")
	await key(KEY_F3)
	var reduced_clock: float = menu().preview.elapsed
	var menu_clock: float = menu().elapsed
	await create_timer(0.18,true).timeout
	var preview_delta: float = menu().preview.elapsed-reduced_clock
	check(game.weather.reduced_effects and preview_delta>0 and preview_delta<(menu().elapsed-menu_clock)*0.4 and paused,"F3 reduces real preview movement while gameplay remains paused")
	await key(KEY_F3)
	check(not game.weather.reduced_effects and game.hud.overlay=="menu","F3 restores full menu effects without opening or starting a match")
	var selected_options: Dictionary = game.hud.scenario_options.duplicate(true)
	var world_options: Dictionary = game.scenario_options.duplicate(true)
	var initial_index: int = menu().environment_index
	var seen: Dictionary = {}
	var previews_match := true
	var preview_worlds := ScenarioCatalog.environments(true)
	for index in preview_worlds.size():
		seen[menu().environment_index] = true
		var entry: Dictionary = preview_worlds[menu().environment_index]
		previews_match = previews_match and menu().preview.environment_id==str(entry.id) and menu().preview.panorama.texture==ScenarioCatalog.texture(str(entry.get("city_path",entry.path)))
		menu().preview_next.pressed.emit()
		await frames()
	check(seen.size()==preview_worlds.size() and menu().environment_index==initial_index and previews_match,"Preview renders all bunker and strategic site worlds and wraps safely")
	menu().preview_previous.pressed.emit()
	await frames()
	check(menu().environment_index==posmod(initial_index-1,preview_worlds.size()) and game.hud.scenario_options==selected_options and game.scenario_options==world_options,"Preview arrows never overwrite the pending match setup")
	unopened("Previewing every world leaves the match and network inactive")
	menu().mode_buttons[0].grab_focus()
	var focused: Dictionary = {}
	for index in 12:
		focused[root.gui_get_focus_owner().get_instance_id()] = true
		await key(KEY_TAB)
	check(focused.size()==12 and menu().mode_buttons[0].has_focus() and game.hud.overlay=="menu","Tab reaches every mode, utility, friends, preview, story, Quit and Changes control without activating a route")
	await click(menu().story_button)
	check(game.hud.overlay=="scenario" and game.hud.selection_count==1 and game.hud.story_selected,"Story button selects the authored story before scenario and character setup")
	unopened("Story selection waits for explicit scenario and character confirmation")
	game.hud.scenario_panel.story_button.pressed.emit()
	check(not game.hud.story_selected,"Scenario setup can switch back to a free shift")
	await key(KEY_ESCAPE)
	menu().mode_buttons[0].grab_focus()
	await key(KEY_DOWN)
	check(menu().mode_buttons[1].has_focus() and game.hud.overlay=="menu","Keyboard Down moves focus to local coop without activating it")
	await key(KEY_ENTER)
	check(game.hud.overlay=="scenario" and game.hud.selection_count==2,"Enter activates the focused local coop mode rather than an unrelated shortcut")
	unopened("Local coop enters setup before spawning or starting the match")
	game.hud.scenario_panel.next_button.pressed.emit()
	await frames()
	check(game.hud.overlay=="characters" and game.hud.character_panel.player_count==2,"Local route retains two worker slots through scenario confirmation")
	await key(KEY_ESCAPE)
	check(game.hud.overlay=="scenario","Escape from workers returns to the selected scenario")
	await key(KEY_ESCAPE)
	check(game.hud.overlay=="menu" and menu().mode_buttons[1].has_focus(),"Escape from setup returns focus to the local coop action")
	menu().mode_buttons[0].grab_focus()
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(menu().mode_buttons[1].has_focus(),"Actual controller D-pad moves menu focus")
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(menu().mode_buttons[2].has_focus(),"Controller reaches Online-Koop independently of local coop")
	await joy(JOY_BUTTON_A)
	check(game.hud.overlay=="network" and is_instance_valid(game.hud.network_panel),"Controller A opens the real online lobby")
	if game.hud.overlay!="network":
		menu().mode_buttons[2].grab_focus()
		await key(KEY_ENTER)
	unopened("Opening the lobby alone does not create a room or contact a server")
	check(root.gui_get_focus_owner()==game.hud.network_panel.create_button,"Controller arrival selects the lobby Create button without activating it")
	await joy(JOY_BUTTON_B)
	check(game.hud.overlay=="menu","Controller B returns from the idle online lobby")
	if game.hud.overlay!="menu":
		await key(KEY_ESCAPE)
	menu().mode_buttons[2].grab_focus()
	await key(KEY_SPACE)
	check(game.hud.overlay=="scenario" and game.hud.selection_count==1,"Advertised Space shortcut opens solo setup even when another mode has focus")
	await key(KEY_ESCAPE)
	await key(KEY_F2)
	check(game.hud.overlay=="scenario" and game.hud.selection_count==2,"F2 shortcut still selects local coop from the redesigned menu")
	await key(KEY_ESCAPE)
	for index in 3:
		await click(menu().utility_buttons[index])
		var expected: String = ["help","audio","personal"][index]
		check(game.hud.overlay==expected,"Menu utility opens its actual %s screen"%expected)
		await key(KEY_ESCAPE)
		check(game.hud.overlay=="menu" and is_instance_valid(menu()),"Escape restores the main menu after %s"%expected)
		if game.hud.overlay!="menu":
			await _finish()
			return
		menu().utility_buttons[index].pressed.emit()
		await frames()
		await joy(JOY_BUTTON_B)
		check(game.hud.overlay=="menu","Controller B restores the main menu after %s"%expected)
		if game.hud.overlay!="menu":
			await key(KEY_ESCAPE)
	menu().utility_buttons[1].grab_focus()
	await key(KEY_F4)
	check(game.hud.overlay == "audio" and is_instance_valid(game.hud.options_panel), "F4 keeps language preferences in the actual options screen")
	game.hud.options_panel.tab_buttons[4].grab_focus()
	await key(KEY_ENTER)
	check(game.hud.options_panel.tab == 4 and game.hud.language_buttons.size() == 2 and game.hud.language_buttons[1].is_visible_in_tree(), "The options language page retains both native language controls")
	await click(game.hud.language_buttons[1])
	check(LocaleText.current_locale() == "en" and game.hud.language_buttons[1].has_focus(), "English switches through its real options control without losing focus")
	await click(game.hud.language_buttons[0])
	await key(KEY_ESCAPE)
	check(game.hud.overlay == "menu" and menu().utility_buttons[1].has_focus(), "Closing language options returns to the clean menu's Options action")
	await key(KEY_F3)
	menu().mode_buttons[0].pressed.emit()
	await frames()
	check(game.hud.overlay=="scenario" and game.hud.selection_count==1,"Solo button enters its own one-worker setup")
	game.hud.scenario_panel.choose("environment","overgrown_steelworks")
	game.hud.scenario_panel.next_button.pressed.emit()
	await frames()
	check(game.hud.overlay=="characters" and game.hud.character_panel.player_count==1,"Solo scenario confirmation requires an explicit worker selection")
	game.hud.character_panel.cards[2].pressed.emit()
	game.hud.character_panel.begin_button.pressed.emit()
	await frames(6)
	game.rounds.running = false
	check(game.started and not paused and game.players.size()==1 and game.players[0].character_id=="ivo" and game.hud.overlay.is_empty(),"Explicit Begin launches one selected worker and removes the menu")
	check(game.weather.reduced_effects,"The menu's reduced-effects preference survives selected-world construction")
	check(not is_instance_valid(game.hud.main_menu_panel),"Menu presentation is released after entering gameplay")
	await _finish()

func _finish() -> void:
	paused = false
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Main scene and menu/audio resources release cleanly")
	print("MAIN MENU: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
