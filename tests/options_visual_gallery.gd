extends "res://tests/ui_audit_gallery.gd"
## Focused native captures: the reported aspect ratio, real popups and paused play.
## The embedded display probe presents controls only; it never launches a window.

class EmbeddedDisplayProbe extends "res://scripts/display_settings.gd":
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
	func is_embedded() -> bool:
		return true
	func can_open_standalone() -> bool:
		return not get_parent().game.started

func _fixture(resolution: Vector2i, locale: String) -> void:
	view.size = resolution
	L.set_locale(locale,false)
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	actual_network = game.network
	await frames(5)
	game.hud._layout_viewport()
	game.hud.main_menu_panel.restore_navigation({"environment":"mountain_pass","focus":"options"})
	game.hud.audio_return_overlay = "menu"
	await overlay("audio")

func _dispose() -> void:
	check(not game.audio.persistence_enabled and not game.combat_events.persistence_enabled and not game.campaign.persistence_enabled,"Capture never saves settings or progress")
	await Cleanup.free_scene(game,self)
	game = null
	await frames()

func _popup(choice: OptionButton, id: String) -> void:
	choice.grab_focus()
	choice.show_popup()
	await capture(id)
	choice.get_popup().hide()
	await frames()

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	if capture_enabled and DisplayServer.get_name()=="headless": quit(2); return
	output_directory = "res://artifacts/options-redesign/"
	phase = "extra"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory+phase))
	AudioServer.set_bus_mute(0,true)
	Roster.persistence_enabled = false
	view = SubViewport.new()
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.gui_embed_subwindows = true
	root.add_child(view)
	await _fixture(Vector2i(1031,799),"de")
	for tab in 5:
		game.hud.options_panel.select_tab(tab)
		game.hud.options_panel.tab_buttons[tab].grab_focus()
		await capture("options-"+["display","camera","audio","rhythm","language"][tab])
	game.hud.options_panel.select_tab(0)
	await _popup(game.hud.options_panel.violence_choice,"violence-popup")
	game.hud._close_audio()
	await frames()
	var actual_display: Node = game.hud.display_settings
	var embedded := EmbeddedDisplayProbe.new()
	game.hud.add_child(embedded)
	game.hud.display_settings = embedded
	game.hud._toggle_audio()
	await frames()
	game.hud.options_panel.select_tab(0)
	game.hud.options_panel.tab_buttons[0].grab_focus()
	presentation_role = "Prepared embedded-display UI only; actual window is standalone; no fullscreen or replacement process is launched"
	check(game.hud.options_panel.standalone_button.visible,"Embedded display presents its secondary separate-window action")
	await capture("embedded-display")
	game.hud.display_settings = actual_display
	embedded.queue_free()
	presentation_role = "offline"
	await _dispose()
	await _fixture(Vector2i(960,600),"en")
	game.hud.options_panel.select_tab(3)
	await _popup(game.hud.options_panel.music_style_choice,"music-style-popup")
	game.hud.options_panel.select_tab(1)
	game.set_camera_zoom(float(game.camera_settings().min_zoom))
	await capture("camera-minimum")
	game.set_camera_zoom(float(game.camera_settings().max_zoom))
	await capture("camera-maximum")
	game.hud.options_panel.select_tab(2)
	game.audio.set_music_volume(0.0)
	game.audio.set_sfx_volume(1.0)
	game.audio.set_voice_volume(.5)
	await capture("audio-extremes")
	await _dispose()
	await _fixture(Vector2i(1440,900),"de")
	game.start_scenario(1,{"environment":"mountain_pass","position":"left","build_type":"bastion"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.story.set_process(false)
	await frames()
	game.hud.audio_return_overlay = "pause"
	await overlay("audio")
	for tab in [0,2,3]:
		game.hud.options_panel.select_tab(tab)
		game.hud.options_panel.tab_buttons[tab].grab_focus()
		check(game.hud.options_panel._landscape.is_empty(),"In-game options keep the real paused world")
		check(game.hud.options_panel.renderer_restart.disabled and game.hud.options_panel.music_lab_button.disabled,"Paused game keeps restart and music-preview gates")
		await capture("paused-"+["display","camera","audio","rhythm","language"][tab])
	await _dispose()
	var report := {"checks":checks,"failures":failures,"rendered":capture_enabled,"findings":findings,"screens":entries,"fixture":"Disposable actual main scene. Native 1031×799, 960×600 and 1440×900 outputs; all persistence disabled, no transport, no microphone, muted master. Embedded controls use a display-presentation subclass only. Paused mountain_pass has one actual player; round and story held. Native embedded PopupMenus are captured without changing selection."}
	var file := FileAccess.open(output_directory+phase+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	view.queue_free()
	await process_frame
	print("OPTIONS VISUAL: %d/%d checks passed; %d captures; %d label findings" % [checks-failures,checks,entries.size(),findings.size()])
	quit(1 if failures or not findings.is_empty() else 0)
