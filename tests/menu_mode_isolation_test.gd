extends SceneTree
## Cancelled solo setup must not silently turn a new local co-op into story mode.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
var game: Node

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func settle() -> void:
	await process_frame
	await process_frame

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await settle()
	game.hud.main_menu_panel.story_button.pressed.emit()
	await settle()
	check(game.hud.story_selected and game.hud.selection_count == 1, "The Solo-Story button selects the one-player story")
	game.hud.scenario_panel.next_button.pressed.emit()
	await settle()
	check(game.hud.overlay == "characters" and game.hud.story_selected, "Advancing keeps the explicit story selection")
	game.hud._close_character_selection()
	await settle()
	check(game.hud.overlay == "scenario" and game.hud.story_selected, "Back from characters preserves the current setup choice")
	game.hud.scenario_panel.back_button.pressed.emit()
	await settle()
	check(game.hud.overlay == "menu" and not game.hud.story_selected, "Cancelling to the main menu discards the abandoned story selection")
	game.hud.main_menu_panel.mode_buttons[1].pressed.emit()
	await settle()
	check(game.hud.selection_count == 2 and not game.hud.story_selected, "A new local co-op starts as a free shift after cancelled Solo-Story")
	check(game.hud.scenario_panel.story_button.text == LocaleText.text("Freie Schicht"), "The new co-op setup displays its free-shift mode")
	game.hud.scenario_panel.story_button.pressed.emit()
	check(game.hud.story_selected, "Players can still explicitly select cooperative story in the setup")
	game.hud.scenario_panel.back_button.pressed.emit()
	await settle()
	check(not game.hud.story_selected and game.hud.overlay == "menu", "Cancelling cooperative story also clears that pending choice")
	game.hud._unhandled_input(action("join"))
	await settle()
	check(game.hud.selection_count == 2 and not game.hud.story_selected, "The F2 co-op shortcut also starts a free shift")
	check(await Cleanup.free_scene(game, self), "The real menu and score release their resources")
	print("MENU MODE ISOLATION: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func action(name: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = true
	return event
