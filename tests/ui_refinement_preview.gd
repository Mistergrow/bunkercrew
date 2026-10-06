extends SceneTree
## Actual menu and gameplay panels. XP, research points and two achievements
## are prepared only to show enabled, purchased and locked presentation states.

const CLEANUP := preload("res://tests/scene_cleanup.gd")
var game
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _frames(count: int=4) -> void:
	for frame in count: await process_frame

func _capture(name: String) -> void:
	await _frames(6)
	await RenderingServer.frame_post_draw
	var path := "res://artifacts/ui-refinement/%s.png"%name
	var result := root.get_texture().get_image().save_png(path)
	if result!=OK:
		failures += 1
		push_error("Could not save UI capture: "+path)
	else:
		print("UI REFINEMENT CAPTURE: ",name)

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("UI capture needs a graphical display")
		quit(1)
		return
	root.size = Vector2i(1440,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/ui-refinement"))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.combat_events.unlocked.clear()
	await _frames()
	game.hud._open_scenario_selection(2)
	await _frames()
	game.hud.scenario_panel.choose("environment","overgrown_steelworks")
	await _capture("scenario")
	game.hud.scenario_panel.next_button.pressed.emit()
	await _frames()
	var selection: CharacterSelectPanel = game.hud.character_panel
	selection.select_character("mara")
	selection.select_slot(1)
	selection.select_character("branko")
	selection.elapsed = 3.5
	await _capture("figures")
	selection.begin_button.pressed.emit()
	await _frames()
	game.rounds.running = false
	game.players[0].progression.award_damage(1100)
	game.players[0].progression.purchase_skill("engineering")
	game.players[0].progression.equip_armor(1)
	game.hud._toggle_personnel()
	await _capture("skills")
	game.combat_events.unlock("first_kill")
	game.combat_events.unlock("armor")
	game.hud.personal_panel.select_tab("achievements")
	await _capture("achievements")
	game.hud._close_personnel()
	await _frames()
	game.upgrades.add_points(12)
	game.upgrades.purchase("bunker_workshop")
	game.upgrades.purchase("boots")
	game.hud._toggle_upgrades()
	await _frames()
	game.hud.upgrade_panel._select("weapon_handling")
	await _capture("technology")
	paused = false
	await CLEANUP.free_scene(game,self)
	print("UI REFINEMENT: five actual panels, prepared progression only; %d capture failures"%failures)
	quit(1 if failures else 0)
