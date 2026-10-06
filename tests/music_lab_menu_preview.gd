extends SceneTree
## Real menu entry and native music-preview controls in both supported locales.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func capture() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	if DisplayServer.get_name() == "headless":
		push_error("Actual menu captures require native graphics")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	InputSetup.install()
	AudioServer.set_bus_mute(0,true)
	root.size=Vector2i(1440,900)
	var directory := "res://artifacts/rhythm-music"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for locale: String in ["de","en"]:
		LocaleText.set_locale(locale,false)
		var game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		await process_frame
		check(not game.started and game.hud.overlay == "menu",locale+" begins at the actual main menu")
		game.hud._toggle_audio()
		await process_frame
		await process_frame
		var options = game.hud.options_panel
		check(is_instance_valid(options) and options.tab_buttons.size() == 5,locale+" actual options expose the Takt page")
		options.tab_buttons[3].pressed.emit()
		check(options.tab == 3 and options.music_lab_button.visible and not options.music_lab_button.disabled,locale+" selecting Takt exposes an enabled native lab button")
		(await capture()).save_png(directory+"/options-takt-"+locale+".png")
		check(options.music_style_choice.item_count==5,locale+" actual options expose all four music styles and their level recommendation")
		options.music_style_choice.show_popup()
		(await capture()).save_png(directory+"/options-genre-dropdown-"+locale+".png")
		options.music_style_choice.get_popup().hide()
		options.music_lab_button.pressed.emit()
		await process_frame
		var lab = options.music_lab
		check(is_instance_valid(lab) and game.audio.calibration_active,locale+" lab opens through the actual menu and suspends the main score")
		var dances := preload("res://scripts/worker_dance_catalog.gd")
		check(lab.apply_button.visible and lab.preview_world.actors.size() == dances.IDS.size(),locale+" integrated lab exposes every real crew rig and apply settings")
		check(lab.genre_choice.item_count == 5 and lab.styles.mara.item_count == dances.styles_for("mara").size(),locale+" native lab exposes four genres, five owned moves and three shared moves")
		var named_move := -1
		for index in lab.styles.nora.item_count:
			if str(lab.styles.nora.get_item_metadata(index))=="nora_ribbon_arms": named_move = index
		check(named_move>=0 and lab.styles.nora.get_item_text(named_move).contains(LocaleText.text(dances.label("nora_ribbon_arms"))),locale+" Nora's authored ribbon move uses its selected translation")
		check(lab.preview_view.canvas_transform.get_scale().x==lab.preview_view.canvas_transform.get_scale().y,locale+" eight native rigs retain equal horizontal and vertical pixel scale")
		lab.gains.rika.grab_focus()
		await process_frame
		await process_frame
		check(lab.interface_scroll.get_global_rect().encloses(lab.gains.rika.get_global_rect()),locale+" eighth profile and gain remain completely accessible through native focus scrolling")
		check(not lab.preview_session.publish_shader_pulse,locale+" preview stays separate from the gameplay shader pulse")
		var deadline := Time.get_ticks_msec()+1200
		while Time.get_ticks_msec()<deadline:
			await process_frame
		check(lab.preview_session.native_active and lab.preview_clock.state.get("active",false),locale+" the real native audio mixer drives the preview beat")
		var expected := "Apply dance to game" if locale == "en" else "Tanz im Spiel übernehmen"
		check(lab.apply_button.text == expected,locale+" new native controls show their selected translation")
		var reduced_label := "Reduce rhythm movement" if locale == "en" else "Taktbewegung reduzieren"
		check(lab.reduced.text == reduced_label,locale+" reduced-motion control uses its selected translation")
		(await capture()).save_png(directory+"/menu-"+locale+".png")
		lab.styles.levin.show_popup()
		(await capture()).save_png(directory+"/dance-dropdown-"+locale+".png")
		lab.styles.levin.get_popup().hide()
		lab.genre_choice.show_popup()
		(await capture()).save_png(directory+"/genre-dropdown-"+locale+".png")
		lab.genre_choice.get_popup().hide()
		lab.close()
		await process_frame
		check(not game.audio.calibration_active,locale+" closing the native lab restores the menu score")
		check(await Cleanup.free_scene(game,self),locale+" complete menu/audio fixture releases cleanly")
	LocaleText.set_locale("de",false)
	var file := FileAccess.open(directory+"/menu-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"captures":["menu-de.png","menu-en.png","options-takt-de.png","options-takt-en.png","dance-dropdown-de.png","dance-dropdown-en.png","genre-dropdown-de.png","genre-dropdown-en.png","options-genre-dropdown-de.png","options-genre-dropdown-en.png"],"entry":"Actual main menu > Options > Takt > Music lab"},"\t"))
	print("MUSIC LAB MENU: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
