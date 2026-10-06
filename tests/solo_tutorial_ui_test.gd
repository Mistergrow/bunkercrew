extends SceneTree
## Actual solo scene, native manual controls, live device cues and HUD priority.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const L := preload("res://scripts/locale_text.gd")
const NetInput := preload("res://scripts/network_input.gd")
const InputLabels := preload("res://scripts/input_labels.gd")
const Records := preload("res://scripts/solo_tutorial_state.gd")
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
	print("TUTORIAL UI %s: %s" % ["PASS" if ok else "FAIL",message])

func frames(count: int = 4) -> void:
	for unused in count: await process_frame

func key(code: Key) -> void:
	for down: bool in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		if is_instance_valid(game): NetInput._primary_mouse_aim(game)
		await process_frame
	await frames()

func _refresh() -> void:
	game.solo_tutorial._process(.25)
	game.hud.solo_tutorial_panel.refresh_view()

func joy(code: JoyButton) -> void:
	for down: bool in [true,false]:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = code
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await frames()

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	AudioServer.set_bus_mute(0,true)
	L.set_locale("de",false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(6)
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	var card: Control = game.hud.solo_tutorial_panel
	check(card.mouse_filter==Control.MOUSE_FILTER_IGNORE and card.focus_mode==Control.FOCUS_NONE,"Passive card cannot consume walking, aiming, firing or native focus")
	await key(KEY_F1)
	var manual: Control = game.hud.help_panel
	manual.select_page("first_shift")
	check(manual.tutorial_content.visible and manual.tutorial_start_button.disabled and manual.tutorial_stop_button.disabled and manual.tutorial_restart_button.disabled,"Main menu explains unavailable solo guidance and disables all tutorial actions")
	check(not card.displays_guidance() and not game.started,"Opening the manual does not start a hidden world")
	await key(KEY_ESCAPE)
	game.start_scenario(1,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.story.set_process(false)
	game.dialogue.reset()
	game.dialogue.set_process(false)
	for worker in game.players: worker.set_physics_process(false)
	game.notice_time = 0
	game.hud.combat_overlay.banners.clear()
	game.hud.combat_overlay.boss.clear()
	await frames()
	_refresh()
	check(game.solo_tutorial.is_available() and card.displays_guidance(),"One actual offline worker receives the running solo tutorial")
	var layout: Dictionary = card.card_layout()
	check(not layout.is_empty() and game.hud.screen_rect().encloses(layout.rect),"Actual tutorial card fits the gameplay viewport")
	if not layout.is_empty():
		check(game.hud.occupied_gameplay_bounds().has(layout.rect),"Camera and markers reserve the tutorial's measured HUD rectangle")
		check(not game.hud.occupied_gameplay_bounds(false).has(layout.rect),"Card placement excludes itself and does not recurse through HUD reservations")
	var original_inventory: Dictionary = game.players[0].inventory.duplicate(true)
	var original_health: float = game.players[0].hp
	var original_wave: int = game.rounds.wave
	game.solo_tutorial.records.mark("move")
	_refresh()
	var actual_target: Vector2 = game.solo_tutorial.target_position()
	check(actual_target.is_finite(),"Prepared learned movement selects a real actionable supply target")
	if actual_target.is_finite():
		game.player_camera.set_process(false)
		var original_camera: Vector2 = game.camera.position
		var original_zoom: Vector2 = game.camera.zoom
		game.camera.position = actual_target
		game.camera.zoom = Vector2.ONE
		game.camera.force_update_scroll()
		await frames()
		var first_marker: Dictionary = card.marker_layout()
		check(not first_marker.is_empty() and not bool(first_marker.offscreen) and first_marker.point==game.hud.world_to_ui(actual_target).round(),"Onscreen tutorial marker uses the actual camera projection")
		game.camera.position += Vector2(70,0)
		game.camera.zoom = Vector2.ONE*2.0
		game.camera.force_update_scroll()
		await frames()
		var zoomed_marker: Dictionary = card.marker_layout()
		check(not zoomed_marker.is_empty() and not bool(zoomed_marker.offscreen) and zoomed_marker.point==game.hud.world_to_ui(actual_target).round() and zoomed_marker.point!=first_marker.get("point",Vector2.INF),"Panning and close zoom reproject the live target without marker drift")
		var moved_layout: Dictionary = card.card_layout()
		check(not moved_layout.is_empty() and not moved_layout.rect.grow(6).has_point(game.hud.world_to_ui(actual_target)),"The guide leaves its projected close-zoom interaction target unobscured")
		game.camera.position = original_camera
		game.camera.zoom = original_zoom
		game.camera.force_update_scroll()
		game.player_camera.set_process(true)
	var learned_before: Array = game.solo_tutorial.records.learned.duplicate()
	await key(KEY_F1)
	manual = game.hud.help_panel
	manual.select_page("first_shift")
	manual._refresh_tutorial_controls()
	check(paused and not card.displays_guidance(),"Field manual pauses solo and hides the passive card")
	check(not manual.tutorial_stop_button.disabled and manual.tutorial_start_button.disabled and not manual.tutorial_restart_button.disabled,"Running tutorial offers stop and repeat with explicit disabled start")
	manual.tutorial_stop_button.grab_focus()
	await key(KEY_ENTER)
	check(not game.solo_tutorial.enabled and game.solo_tutorial.records.learned==learned_before,"Native Enter stops guidance without forgetting learned steps")
	check(paused and game.hud.overlay=="help" and manual.reading_scroll.has_focus(),"Disabling the focused action restores reader focus and keeps gameplay paused")
	check(not manual.tutorial_start_button.disabled and manual.tutorial_stop_button.focus_mode==Control.FOCUS_NONE,"Stopped guide exposes resume and removes disabled stop from native focus")
	manual.tutorial_start_button.grab_focus()
	await joy(JOY_BUTTON_A)
	check(game.solo_tutorial.enabled and game.solo_tutorial.records.learned==learned_before,"Native controller A resumes the same tutorial progress")
	check(paused and is_zero_approx(NetInput.strength(game.players[0],"jump")) and not NetInput.just_pressed(game.players[0],"jump"),"Released controller accept stays inside the paused manual and issues no gameplay jump")
	var held_accept := InputEventJoypadButton.new()
	held_accept.device = 0
	held_accept.button_index = JOY_BUTTON_A
	held_accept.pressed = true
	Input.parse_input_event(held_accept)
	await process_frame
	check(Input.is_action_pressed("primary_pad_jump"),"Held native controller accept uses the real primary-pad jump binding")
	await key(KEY_ESCAPE)
	check(not paused and game.hud.overlay.is_empty() and is_zero_approx(NetInput.strength(game.players[0],"jump")) and not NetInput.just_pressed(game.players[0],"jump"),"Closing the manual while A is held quarantines its actual shared gameplay action")
	held_accept.pressed = false
	Input.parse_input_event(held_accept)
	await process_frame
	check(not NetInput.just_released(game.players[0],"jump"),"The release of the held menu accept does not leak a gameplay jump release")
	await key(KEY_F1)
	manual = game.hud.help_panel
	manual.select_page("first_shift")
	manual.tutorial_restart_button.grab_focus()
	await key(KEY_ENTER)
	check(game.solo_tutorial.enabled and game.solo_tutorial.records.pending("move"),"Repeat makes movement a fresh lesson while preserving the actual world's completed context")
	check(game.players[0].inventory==original_inventory and is_equal_approx(game.players[0].hp,original_health) and game.rounds.wave==original_wave,"Guide controls do not alter inventory, health or the wave")
	manual.select_page("workshop")
	check(not manual.tutorial_content.visible,"Other manual chapters retain their focused reference layout")
	await key(KEY_ESCAPE)
	_refresh()
	check(not paused and card.displays_guidance(),"Back resumes solo guidance in its original gameplay route")
	for locale: String in ["de","en"]:
		L.set_locale(locale,false)
		_refresh()
		var keyboard_body := str(card._view.body)
		check(not keyboard_body.contains("%s") and not keyboard_body.is_empty(),locale+" tutorial formats actual action labels before layout")
		var stick := InputEventJoypadMotion.new()
		stick.device = 0
		stick.axis = JOY_AXIS_LEFT_X
		stick.axis_value = .7
		Input.parse_input_event(stick)
		await process_frame
		NetInput._primary_mouse_aim(game)
		_refresh()
		check(str(card._view.body).contains(L.text("Linker Stick")),locale+" actual pad motion selects live controller guidance")
		check(str(card._view.body).contains(L.text("Pause → Handbuch")) and InputLabels.action(game.players[0],"jump")=="A",locale+" controller guidance includes its actual jump and paused manual route")
		stick.axis_value = 0
		Input.parse_input_event(stick)
		await key(KEY_D)
		NetInput._primary_mouse_aim(game)
		_refresh()
		check(not str(card._view.body).contains(L.text("Linker Stick")),locale+" actual keyboard movement restores keyboard guidance")
	game.dialogue.active = {"text":"Fixture caption"}
	check(not card.displays_guidance(),"Authored dialogue has priority over onboarding")
	game.dialogue.active.clear()
	game.speech_bubbles._visible = true
	check(not card.displays_guidance(),"Visible comic speech has priority over onboarding")
	game.speech_bubbles._visible = false
	game.network.set_process(false)
	game.network.active = true
	game.network.state = "playing"
	_refresh()
	check(not card.displays_guidance(),"Online session immediately suppresses the solo card")
	await key(KEY_F1)
	manual = game.hud.help_panel
	manual.select_page("first_shift")
	check(manual.tutorial_start_button.disabled and manual.tutorial_stop_button.disabled and manual.tutorial_restart_button.disabled,"Prepared online manual keeps every solo action disabled")
	game.network.active = false
	game.network.state = "offline"
	paused = false
	check(not FileAccess.file_exists(Records.SAVE_PATH),"UI regression writes no tutorial profile")
	check(await Cleanup.free_scene(game,self),"Tutorial HUD and actual audio/world scene release cleanly")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/solo-tutorial-20261005/"))
	FileAccess.open("res://artifacts/solo-tutorial-20261005/ui-test.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"fixture":"Actual solo main scene and F1 native Enter routing; waves, dialogue and worker physics held. Last case arranges online state without sockets. Real joypad/keyboard events select input labels. All profile writes disabled; Master muted."},"  "))
	print("SOLO TUTORIAL UI: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
