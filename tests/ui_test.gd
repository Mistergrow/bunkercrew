extends SceneTree
## Real routed input covers menus, current-mission restart and scene lifetime.
var game
var checks = 0
var failures = 0
const AUDIO_SCRIPT = preload("res://scripts/audio.gd")
var test_audio_path := "user://ui-test-audio-%d.cfg" % OS.get_process_id()

func _initialize() -> void:
	# Route each new audio node before _ready(), including after a scene reload.
	# A failed or interrupted test can never overwrite the player's settings.
	node_added.connect(_route_audio_settings)
	call_deferred("run")

func _route_audio_settings(node: Node) -> void:
	if node.get_script()==AUDIO_SCRIPT:
		node.settings_path = test_audio_path
		node.persistence_enabled = true

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("UI FAIL: " + message)
	else:
		print("UI PASS: " + message)

func press(action: String) -> void:
	var event = InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Run with --no-profile-save to preserve player progress")
		quit(1)
		return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	check(game.audio.settings_path==test_audio_path,"Audio settings are isolated before any slider changes")
	if failures>0:
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
		quit(1)
		return
	check(paused and not game.started, "Fresh scene starts in paused menu")
	await press("upgrades")
	check(paused and game.hud.overlay == "upgrades" and game.hud.upgrade_panel.node_buttons.size() == UpgradeSystem.NODES.size(), "T opens four research categories with all upgrades inspectable")
	await press("pause")
	check(paused and game.hud.overlay == "menu" and not game.started, "Closing menu research returns to the paused menu")
	await press("audio_settings")
	check(paused and game.hud.overlay == "audio" and game.hud.sliders.size() == 3, "F4 opens music, effects and voice sliders from the menu")
	game.hud.sliders[0].value = 0.21
	game.hud.sliders[1].value = 0.47
	game.hud.sliders[2].value = 0.63
	check(is_equal_approx(game.audio.music_volume, 0.21) and is_equal_approx(game.audio.sfx_volume, 0.47) and is_equal_approx(game.audio.voice_volume, 0.63), "Audio sliders independently control music, effects and character voices")
	await press("pause")
	check(paused and game.hud.overlay == "menu", "Escape from menu audio settings returns to the paused menu")
	await press("start")
	check(not game.started and paused and game.hud.overlay=="scenario", "Start input opens paused scenario setup before gameplay")
	game.hud.scenario_panel.classic_button.pressed.emit()
	await process_frame
	check(not game.started and paused and game.hud.overlay=="characters", "Scenario confirmation opens character selection without starting the round")
	game.hud.character_panel.begin_button.pressed.emit()
	await process_frame
	check(game.started and not paused, "Explicit selection confirmation begins solo")
	await press("upgrades")
	var research_time: float = game.rounds.time_left
	await create_timer(0.1, true).timeout
	check(paused and game.hud.overlay == "upgrades" and game.rounds.time_left == research_time, "Research panel freezes the active round clock")
	await press("help")
	await press("audio_settings")
	check(paused and game.hud.overlay == "upgrades", "Help and audio cannot replace an open research modal")
	game.upgrades.add_points(2)
	var purchase_button = game.hud.upgrade_panel.node_buttons[0]
	check(not purchase_button.disabled, "Research buttons become available when shared points arrive")
	purchase_button.pressed.emit()
	check(not game.upgrades.has_upgrade("bunker_workshop") and game.upgrades.points == 2, "Inspecting research never spends shared points")
	game.hud.upgrade_panel.purchase_button.pressed.emit()
	check(game.upgrades.has_upgrade("bunker_workshop") and game.upgrades.points == 0 and game.hud.upgrade_panel.purchase_button.disabled, "Explicit research confirmation buys its real upgrade once and refreshes affordability")
	await press("upgrades")
	check(not paused and game.hud.overlay.is_empty(), "T closes research and resumes the running round")
	await press("audio_settings")
	await press("upgrades")
	check(paused and game.hud.overlay == "audio", "Research cannot replace an open audio modal")
	var audio_time: float = game.rounds.time_left
	await create_timer(0.1, true).timeout
	check(paused and game.rounds.time_left == audio_time, "Audio settings suspend the live round clock")
	await press("audio_settings")
	check(not paused and game.hud.overlay.is_empty(), "F4 closes audio settings and resumes a running round")
	await press("pause")
	check(paused and game.hud.overlay == "pause", "Escape pauses world")
	await press("upgrades")
	await press("pause")
	check(paused and game.hud.overlay == "pause", "Closing research returns to the existing pause screen")
	await press("audio_settings")
	await press("pause")
	check(paused and game.hud.overlay == "pause", "Audio settings return to the existing pause screen")
	var before: float = game.rounds.time_left
	await create_timer(0.12, true).timeout
	check(game.rounds.time_left == before, "Construction clock stops while paused")
	await press("help")
	check(paused and game.hud.overlay == "help", "Help remains paused")
	await press("help")
	check(paused and game.hud.overlay=="pause", "Closing help restores its original pause menu")
	await press("pause")
	check(not paused and game.hud.overlay.is_empty(), "Escape from restored pause resumes")
	await press("join")
	check(game.players.size() == 2 and game.player_count == 2, "Join input adds exactly one second worker")
	await press("join")
	check(game.players.size() == 3, "Repeated join adds the supported third worker")
	await press("skip_build")
	check(game.rounds.phase == "warning", "Skip input starts warning before attack")
	game.rounds.defeat()
	check(paused and game.hud.overlay == "defeat", "Defeat freezes game and opens summary")
	await press("help")
	await press("pause")
	check(paused and game.hud.overlay == "defeat", "Help/pause cannot resume a finished round")
	await press("upgrades")
	await press("help")
	await press("audio_settings")
	check(paused and game.hud.overlay == "upgrades", "Research stays paused and blocks modal switching after defeat")
	await press("upgrades")
	check(paused and game.hud.overlay == "defeat", "Closing research after defeat returns to the result screen")
	await press("audio_settings")
	await press("help")
	check(paused and game.hud.overlay == "audio", "Help cannot bypass a finished round through audio settings")
	await press("pause")
	check(paused and game.hud.overlay == "defeat", "Audio settings return to the defeat summary")
	var old_id: int = game.get_instance_id()
	await press("restart")
	await process_frame
	game = current_scene
	check(is_instance_valid(game) and game.get_instance_id() != old_id and game.started and not paused and game.players.size()==3, "Routed F5 safely restarts the same three-person mission")
	check(game.upgrades.points == 0 and game.upgrades.owned.is_empty() and not game.depth_unlocked, "Restart resets run-specific research and deep expansion")
	check(is_equal_approx(game.audio.music_volume, 0.21) and is_equal_approx(game.audio.sfx_volume, 0.47) and is_equal_approx(game.audio.voice_volume, 0.63), "All three audio settings survive a complete scene restart")
	game.return_to_menu()
	for frame in 4: await process_frame
	game = current_scene
	check(not game.started and paused and game.players.is_empty(), "Returning to the main menu stays separate from restarting a mission")
	await press("start")
	game.hud.scenario_panel.next_button.pressed.emit()
	await process_frame
	game.hud.character_panel.begin_button.pressed.emit()
	await process_frame
	check(game.started and is_equal_approx(game.core.hp,game.core.max_hp) and game.players.size() == 1, "New round has a full-health scenario core and one fresh player")
	paused = false
	await create_timer(0.4, true, false, true).timeout
	await load("res://tests/scene_cleanup.gd").free_scene(game,self)
	if FileAccess.file_exists(test_audio_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_audio_path))
	print("UI CHECKS: %d passed, %d failed" % [checks-failures,failures])
	quit(0 if failures==0 else 1)
