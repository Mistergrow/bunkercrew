extends SceneTree
## A fresh real game process reads only an isolated user directory.
var game
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func frames(count: int = 4) -> void:
	for frame in count: await process_frame

func run() -> void:
	if OS.get_environment("BUNKERCREW_MENU_ISOLATED") != "1":
		push_error("Use the isolated tests/menu_progression_restart_test.py runner")
		quit(2)
		return
	root.size = Vector2i(1440, 900)
	# Last setup is not campaign progress and must not decide the next menu.
	ScenarioCatalog.last_selection.environment = "iron_canyon"
	var expected := OS.get_environment("BUNKERCREW_MENU_EXPECTED")
	var has_save := OS.get_environment("BUNKERCREW_MENU_HAS_SAVE") == "1"
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(8)
	var menu = game.hud.main_menu_panel
	check(game.hud.overlay == "menu" and menu.preview.environment_id == expected, "Fresh startup displays its current checkpoint world")
	check(is_instance_valid(menu.continue_button) == has_save, "Continue requires a valid primary or backup checkpoint")
	check(not game.campaign.active and not game.started and not game.rounds.running and not game.network.active, "Preview never loads an active campaign or starts gameplay/network")
	var world_options: Dictionary = game.scenario_options.duplicate(true)
	var pending_options: Dictionary = game.hud.scenario_options.duplicate(true)
	menu.preview_next.pressed.emit()
	await frames()
	check(menu.preview.environment_id != expected, "Browse control changes only the visible scene")
	var browsed_environment: String = menu.preview.environment_id
	check(game.scenario_options == world_options and game.hud.scenario_options == pending_options, "Preview does not change the next match setup")
	check(not game.campaign.active, "Browsing does not create campaign progress")
	game.hud._rebuild_buttons()
	await frames()
	check(game.hud.main_menu_panel.preview.environment_id == browsed_environment, "Reopening menu preserves the browsed scene within the current session")
	check(ScenarioCatalog.last_selection.environment == "iron_canyon", "Background selection leaves explicit scenario selection alone")
	check(game.hud.main_menu_panel.environments.size() == ScenarioCatalog.environments(true).size(), "Strategic sites are available to the same animated presentation")
	paused = false
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game, self), "Main scene resources release cleanly")
	print("MENU RESTART: %d/%d passed" % [checks-failures, checks])
	quit(1 if failures else 0)
