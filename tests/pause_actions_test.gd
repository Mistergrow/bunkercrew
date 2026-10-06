extends SceneTree
## Real routed pause/modal input, safe cancellation and separate menu exit.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func frames(count: int=3) -> void:
	for frame in count: await process_frame

func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await frames(2)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	LocaleText.set_locale("de",false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	game.start(2)
	await frames()
	await press("pause")
	check(paused and game.hud.overlay=="pause","Escape opens the paused action menu")
	check(game.hud.pause_buttons.size()==8,"Pause exposes continue, restart, options, personnel, research, controls, friends and menu exit")
	check(root.gui_get_focus_owner()==game.hud.pause_buttons.continue_match,"Opening pause focuses the safe continue action")
	await press("ui_down")
	check(root.gui_get_focus_owner()==game.hud.pause_buttons.options,"Navigation reaches settings before the separate destructive actions")
	for unused in 5: await press("ui_down")
	check(root.gui_get_focus_owner()==game.hud.pause_buttons.restart,"Controller/keyboard navigation reaches visible restart")
	game.hud.pause_buttons.restart.pressed.emit()
	await frames()
	var dialog: Control = game.hud.restart_dialog
	check(dialog.visible and paused and dialog.cancel_button.has_focus(),"Restart opens the in-game confirmation with Cancel focused")
	check(not dialog.is_class("Window") and dialog.get_parent()==game.hud.canvas,"Restart confirmation uses the existing canvas UI")
	for action in ["restart","audio_settings","upgrades","personnel","help","join","friends"]:
		await press(action)
		check(dialog.visible and game.hud.overlay=="pause" and game.players.size()==2,"Confirmation blocks underlying shortcut: "+action)
	await press("ui_cancel")
	check(not dialog.visible and paused and game.hud.overlay=="pause","B/Escape cancellation preserves the original pause")
	check(game.hud.pause_buttons.restart.has_focus(),"Cancellation restores the originating button focus")
	await press("ui_cancel")
	check(not paused and game.hud.overlay.is_empty(),"B also resumes from the pause menu")
	await press("restart")
	Input.action_press("p1_left")
	Input.action_press("p1_fire")
	Input.action_press("p1_drop")
	var sampled: Dictionary = preload("res://scripts/network_input.gd").sample_local(game)
	check(game.hud.blocks_gameplay_input() and sampled.held.is_empty() and sampled.pressed.is_empty(),"A confirmation from active play blocks polled movement, fire and drop")
	Input.action_release("p1_left")
	Input.action_release("p1_fire")
	Input.action_release("p1_drop")
	await press("restart")
	await press("pause")
	check(not paused and not dialog.visible,"Repeated F5 cannot overwrite the original running state")
	await press("pause")
	game.hud.pause_buttons.options.pressed.emit()
	await frames()
	await press("ui_cancel")
	check(paused and game.hud.overlay=="pause","Options returns to its original pause")
	game.hud.pause_buttons.help.pressed.emit()
	await frames()
	await press("ui_cancel")
	check(paused and game.hud.overlay=="pause","Controls returns to its original pause")
	for locale in ["de","en"]:
		LocaleText.set_locale(locale,false)
		game.hud.pause_buttons.main_menu.pressed.emit()
		await frames()
		check(dialog.visible and game.hud._session_action=="menu","Menu exit uses a separate confirmation in "+locale)
		check(LocaleText.text(dialog.confirm_button.text)==LocaleText.text("Zum Hauptmenü"),"Menu confirmation label translates in "+locale)
		await press("ui_cancel")
		check(paused and game.hud.overlay=="pause","Cancel menu exit retains the current mission in "+locale)
	game.hud.pause_buttons.main_menu.pressed.emit()
	await frames()
	dialog.confirm_button.pressed.emit()
	await frames(6)
	game = current_scene
	check(not game.started and paused and game.players.is_empty() and game.hud.overlay=="menu","Confirmed menu exit releases the mission and opens a clean main menu")
	await Cleanup.free_scene(game,self)
	print("PAUSE ACTIONS: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
