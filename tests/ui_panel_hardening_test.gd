extends SceneTree
## Real routed modal input and focus, including Space before native Buttons.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const L := preload("res://scripts/locale_text.gd")
var game
var checks := 0
var failures := 0
var preview_starts := 0

func _initialize() -> void:
	node_added.connect(_watch_preview)
	run.call_deferred()

func _watch_preview(node: Node) -> void:
	if node.name=="IsolatedMusicPreview" and node.has_signal("session_started"):
		node.session_started.connect(func(_environment: String,_seed: int,_native: bool): preview_starts += 1)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int = 3) -> void:
	for unused in count: await process_frame

func press(action: String) -> void:
	for down in [true,false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await frames()

func space(down: bool, repeat: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.physical_keycode = KEY_SPACE
	event.pressed = down
	event.echo = repeat
	Input.parse_input_event(event)
	await process_frame

func options_hidden(panel: Control, except: Control) -> bool:
	# The current landscape can remain behind a modal. Every settings input
	# must be hidden, including nested page controls and both footer actions.
	var pending: Array[Node] = panel.get_children()
	while not pending.is_empty():
		var child: Node = pending.pop_back()
		if child == except: continue
		pending.append_array(child.get_children())
		if child is Control and child.focus_mode!=Control.FOCUS_NONE and child.is_visible_in_tree(): return false
	return true

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	AudioServer.set_bus_mute(0,true)
	L.set_locale("de",false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(5)
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	await press("audio_settings")
	var options: Control = game.hud.options_panel
	check(options.tab_buttons[0].has_focus(),"Opening settings supplies native keyboard/controller focus")
	options.select_tab(3)
	options.tab_buttons[3].grab_focus()
	var music_volume: float = game.audio.music_volume
	game.audio.set_music_volume(1.0)
	options._open_calibration()
	await frames()
	var calibration: Control = options.calibration_panel
	check(options.has_modal_subpanel() and options_hidden(options,calibration),"Calibration hides every underlying setting control, including footer buttons")
	check(calibration.start_button.has_focus(),"Calibration starts with its own native focus")
	check(not game.microphone.capturing and not calibration.started,"Opening calibration starts no microphone or click playback")
	for action in ["help","upgrades","personnel","achievements","restart"]:
		await press(action)
		check(game.hud.overlay=="audio" and options.calibration_panel==calibration,"Calibration blocks unrelated HUD action: "+action)
	var before_offset: float = game.audio.music_calibration_seconds
	calibration._start()
	calibration.set_process(false)
	check(calibration.tap_button.has_focus(),"Starting the click transfers focus to the tap control")
	calibration.time_seconds = 0.782
	await space(true)
	check(calibration.calibration.result().count==1,"Physical Space taps on key-down before native Button acceptance")
	calibration.time_seconds = 1.382
	await space(true,true)
	check(calibration.calibration.result().count==1,"Key repeat cannot insert another calibration sample")
	await space(false)
	check(calibration.calibration.result().count==1,"Key-up cannot trigger a duplicate native Button tap")
	check(is_equal_approx(game.audio.music_calibration_seconds,before_offset),"Unconfirmed keyboard taps never change the saved compensation")
	await press("pause")
	check(game.hud.overlay=="audio" and game.hud.options_panel==options and options.tab==3,"Escape returns to the same settings instance and rhythm tab")
	check(not options.has_modal_subpanel() and options.pages[3].visible and options.pages.filter(func(page): return page.visible).size()==1,"Closing calibration restores exactly the prior settings page")
	check(options.tab_buttons[3].has_focus() and not game.audio.calibration_active,"Closing calibration restores tab focus and normal music routing")
	options._open_calibration()
	await frames()
	await press("audio_settings")
	check(game.hud.overlay=="audio" and not options.has_modal_subpanel(),"F4 closes only the calibration subpanel")
	options._open_calibration()
	await frames()
	options.close_modal_subpanel()
	await frames()
	check(not options.has_modal_subpanel() and options.tab_buttons[3].has_focus(),"Explicit modal close uses the same restoration path")
	options._open_music_lab(false)
	await frames()
	var lab: CanvasLayer = options.music_lab
	check(preview_starts==0 and not lab.preview_session.session_active and not lab.preview_session.native_active,"Idle lab capture creates no native music session")
	check(lab.theme_choice.has_focus(),"Opening the music lab supplies its own keyboard/controller focus")
	check(lab.apply_button.visible and options_hidden(options,null),"Lab is configured before readiness and hides all underlying controls")
	options.close_modal_subpanel()
	await frames()
	check(not game.audio.calibration_active and not options.has_modal_subpanel(),"Closing an idle lab restores the original music route")
	options._open_music_lab()
	await frames()
	lab = options.music_lab
	check(preview_starts==1 and lab.preview_session.session_active and lab.preview_session.native_active,"A real audible lab opening initializes exactly one native session")
	lab.show_for_game(game)
	check(preview_starts==2 and lab.preview_session.session_active,"Reconfiguring an already ready lab starts its updated native preview once")
	var session_ref: WeakRef = weakref(lab.preview_session)
	await press("audio_settings")
	check(game.hud.overlay=="audio" and not options.has_modal_subpanel() and session_ref.get_ref()==null and not game.audio.calibration_active,"F4 closes the reconfigured root lab and releases its native session and music suspension")
	options._open_music_lab(false)
	await frames()
	var lab_ref: WeakRef = weakref(options.music_lab)
	game.hud._close_audio()
	await frames()
	check(lab_ref.get_ref()==null and not game.audio.calibration_active,"Destroying settings releases its root-parented lab and music suspension")
	await press("audio_settings")
	options = game.hud.options_panel
	options.select_tab(3)
	game.audio.set_music_volume(music_volume)
	game.hud._open_microphone()
	await frames()
	check(game.hud.microphone_panel.device_select.has_focus(),"Microphone diagnostics focus the device selector without activation")
	check(not game.microphone.capturing,"Controller focus does not acquire the physical microphone")
	await press("pause")
	check(game.hud.overlay=="audio" and game.hud.options_panel.tab==3,"Microphone back navigation preserves the rhythm page")
	await press("audio_settings")
	check(game.hud.overlay=="menu" and paused,"A second F4 returns from settings to the paused main menu")
	game.start_scenario(2,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	game.rounds.running = false
	game.rounds.set_process(false)
	await frames()
	var state: CampaignState = game.campaign
	var reward := state.complete_mission(state.mission_id,20,game.players,game.upgrades,{"steel":12,"ammo":6,"concrete":18,"scrap":8})
	check(not reward.is_empty() and state.select_destination("harbor"),"Actual completed mission prepares an actionable convoy route")
	game.hud.overlay = "expedition"
	game.hud._apply_overlay_pause()
	await frames()
	var expedition: Control = game.hud.expedition_panel
	check(expedition.route_buttons["harbor"].has_focus(),"Opening the convoy map focuses its selected destination")
	check(not game.network.active and not game.microphone.capturing,"Entire audit stays offline with microphone closed")
	check(not game.audio.persistence_enabled and not game.combat_events.persistence_enabled and not state.persistence_enabled,"Entire audit preserves the player's saved settings and progress")
	await Cleanup.free_scene(game,self)
	print("UI PANEL HARDENING: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
