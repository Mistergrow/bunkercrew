extends SceneTree
## Real setup controls and same-state before/after images at native output sizes.
const L := preload("res://scripts/locale_text.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/scenario-ui/"
const RESOLUTIONS := [Vector2i(960,600),Vector2i(1920,1080),Vector2i(2560,1440)]
var checks := 0
var failures := 0
var game
var view: SubViewport
var captures: Array[Dictionary] = []
var capture_enabled := false

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS ",label)
	else:
		failures += 1
		push_error(label)

func frames(count: int = 3) -> void:
	for unused in count: await process_frame

func press_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	view.push_input(event,true)
	await frames(2)
	event.pressed = false
	view.push_input(event,true)
	await frames(2)

func press_pad(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	view.push_input(event,true)
	await frames(2)
	event.pressed = false
	view.push_input(event,true)
	await frames(2)

func click(button: Button) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = button.get_global_rect().get_center()
	event.global_position = event.position
	event.pressed = true
	view.push_input(event,true)
	await frames(2)
	event.pressed = false
	view.push_input(event,true)
	await frames(2)

func controls(panel: Control) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for child in panel.get_children():
		if not child is Button or not child.visible: continue
		var button: Button = child
		var rect := button.get_global_rect()
		var label := L.text(button.text)
		var style := button.get_theme_stylebox("normal")
		var available := button.size.x-style.get_content_margin(SIDE_LEFT)-style.get_content_margin(SIDE_RIGHT)
		var width := button.get_theme_font("font").get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x
		result.append({"label":label,"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"label_width":width,"available":available,"fits":width<=available+1.0,"focused":button.has_focus()})
	return result

func capture(panel: Control,phase: String,id: String) -> void:
	await frames(3)
	if phase=="after":
		check(panel.preview.environment_id==panel.options.environment,"Preview shows the currently selected actual landscape: "+id)
		check(is_equal_approx(panel.preview.transform.x.length(),panel.preview.transform.y.length()),"Panorama retains its aspect ratio: "+id)
		check(panel.preview_clip.get_global_rect().grow(1).encloses(Rect2(Vector2.ZERO,Vector2(view.size))),"Selected landscape fills the native viewport: "+id)
	var filename := "%s-%s-%dx%d-%s.png" % [phase,L.current_locale(),view.size.x,view.size.y,id]
	if capture_enabled:
		await RenderingServer.frame_post_draw
		var picture := view.get_texture().get_image()
		check(picture.get_size()==view.size,"Actual native capture size: "+filename)
		check(picture.save_png(OUTPUT+filename)==OK,"Saved actual rendered setup: "+filename)
	captures.append({"file":filename,"phase":phase,"locale":L.current_locale(),"resolution":[view.size.x,view.size.y],"environment":panel.options.environment,"build_type":panel.options.build_type,"position":panel.options.position,"players":game.hud.selection_count,"story":game.hud.story_selected,"started":game.started,"paused":paused,"controls":controls(panel)})

func review_locale_and_size(resolution: Vector2i,locale: String) -> void:
	view.size = resolution
	L.set_locale(locale,false)
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames(5)
	game.hud._layout_viewport()
	game.hud._open_scenario_selection(2)
	await frames(4)
	var panel: ScenarioSelectPanel = game.hud.scenario_panel
	panel.choose("environment","ash_foundry")
	panel.choose("build_type","bastion")
	panel.choose("position","left")
	panel.cards[1].grab_focus()
	await frames()
	var options := panel.options.duplicate(true)
	var menu_decoder: WeakRef = weakref(game.audio.menu_music.player.get_stream_playback())
	check(panel.cards.size()==15,"Every original location, construction and position remains selectable: "+locale)
	check(paused and not game.started and game.players.is_empty(),"Setup remains a paused menu without world players: "+locale)
	for control: Dictionary in controls(panel):
		check(control.fits,"Translated native button label fits: "+str(control.label))
		var values: Array = control.rect
		var bounds := Rect2(float(values[0]),float(values[1]),float(values[2]),float(values[3]))
		check(Rect2(Vector2.ZERO,Vector2(resolution)).grow(1).encloses(bounds),"Visible setup control stays inside native viewport: "+str(control.label))
	for index in panel.cards.size():
		for other in range(index):
			check(not panel.cards[index].get_rect().intersects(panel.cards[other].get_rect()),"Independent setup hit areas %d/%d" % [index,other])
	for index in 9:
		var style: StyleBox = panel.cards[index].get_theme_stylebox("normal")
		check(style is StyleBoxEmpty or style is StyleBoxFlat and style.bg_color.a<0.15,"Location row has no opaque card backing: %d" % index)
	var opposite := "en" if locale=="de" else "de"
	L.set_locale(opposite,false)
	L.set_locale(locale,false)
	await frames()
	check(panel.options==options,"Language changes preserve setup choices and controls")
	check(game.audio.menu_music.player.get_stream_playback()==menu_decoder.get_ref(),"Scene and language selection preserve the actual menu decoder")
	if capture_enabled:
		var old_script := load(OUTPUT+"baseline_scenario_panel.gd")
		var old_panel: Control = old_script.new()
		old_panel.game = game
		old_panel.hud = game.hud
		game.hud.canvas.add_child(old_panel)
		await frames(2)
		old_panel.choose("environment","ash_foundry")
		old_panel.choose("build_type","bastion")
		old_panel.choose("position","left")
		panel.visible = false
		old_panel.cards[1].grab_focus()
		await capture(old_panel,"before","ash-foundry")
		old_panel.queue_free()
		await frames()
		panel.visible = true
		panel.cards[1].grab_focus()
	await capture(panel,"after","ash-foundry")
	if resolution==Vector2i(1920,1080):
		for configuration in [{"environment":"mountain_pass","build_type":"workshop","position":"center"},{"environment":"overgrown_steelworks","build_type":"stronghold","position":"right"}]:
			for key in configuration: panel.choose(key,configuration[key])
			panel.cards[9+(1 if configuration.build_type=="workshop" else 2)].grab_focus()
			await capture(panel,"after",configuration.environment)
		if locale=="de":
			var entries := ScenarioCatalog.environments()
			for index in entries.size():
				var entry: Dictionary = entries[index]
				if entry.id in ["ash_foundry","mountain_pass","overgrown_steelworks"]: continue
				panel.choose("environment",entry.id)
				panel.choose("build_type","bastion")
				panel.choose("position","left")
				panel.cards[index].grab_focus()
				await capture(panel,"after",entry.id)
		panel.choose("environment","ash_foundry")
		panel.choose("build_type","bastion")
		panel.choose("position","left")
		panel.cards[0].grab_focus()
		await press_key(KEY_DOWN)
		check(panel.cards[1].has_focus(),"Physical keyboard moves down the location list")
		await press_key(KEY_ENTER)
		check(panel.options.environment=="ash_foundry","Keyboard Enter chooses its focused location")
		await press_key(KEY_RIGHT)
		check(panel.cards[9].has_focus(),"Keyboard Right reaches the configuration column")
		await press_key(KEY_DOWN)
		check(panel.cards[10].has_focus(),"Keyboard Down follows construction choices in screen order")
		await press_key(KEY_ENTER)
		check(panel.options.build_type=="workshop","Keyboard Enter chooses its focused construction")
		await press_pad(JOY_BUTTON_DPAD_DOWN)
		check(panel.cards[11].has_focus(),"Controller D-pad reaches the third construction choice")
		await press_pad(JOY_BUTTON_A)
		check(panel.options.build_type=="stronghold","Controller A chooses its focused construction")
		await press_pad(JOY_BUTTON_DPAD_DOWN)
		check(panel.cards[12].has_focus(),"Controller moves from construction to position choices")
		await press_pad(JOY_BUTTON_DPAD_DOWN)
		await press_pad(JOY_BUTTON_A)
		check(panel.options.position=="center","Controller A chooses the center bunker position")
		await press_key(KEY_TAB)
		check(panel.cards[14].has_focus(),"Tab moves between actual setup choices")
		panel.cards[1].grab_focus()
		await press_pad(JOY_BUTTON_DPAD_DOWN)
		check(panel.cards[2].has_focus(),"Physical controller D-pad moves down the location list")
		await press_pad(JOY_BUTTON_A)
		check(panel.options.environment=="abandoned_harbor","Controller A chooses its focused location")
		await click(panel.cards[4])
		check(panel.options.environment=="overgrown_steelworks" and panel.cards[4].has_focus(),"Actual mouse click selects and focuses its location row")
		await click(panel.cards[2])
		panel.story_button.pressed.emit()
		check(game.hud.story_selected,"Story mode remains selectable")
		panel.story_button.pressed.emit()
		check(not game.hud.story_selected,"Free shift remains selectable")
		panel.next_button.pressed.emit()
		await frames(4)
		check(game.hud.overlay=="characters" and game.hud.selection_count==2,"Continue opens two-player character selection")
		game.hud.character_panel.back_button.pressed.emit()
		await frames(4)
		check(game.hud.overlay=="scenario" and game.hud.scenario_panel.options.environment=="abandoned_harbor","Character Back returns to the chosen setup")
		game.hud.scenario_panel.classic_button.pressed.emit()
		await frames(4)
		check(game.hud.overlay=="characters" and not game.hud.scenario_selected,"Classic bunker remains reachable")
		game.hud.character_panel.back_button.pressed.emit()
		await frames(4)
		check(game.hud.overlay=="scenario","Classic character Back returns to scenario setup")
		game.hud.scenario_panel.back_button.pressed.emit()
		await frames(4)
		check(game.hud.overlay=="menu" and not game.started,"Setup Back returns safely to main menu")
	check(not game.network.active and not game.microphone.capturing,"UI review starts neither a connection nor microphone capture")
	check(await Cleanup.free_scene(game,self),"Actual scene and music handles release")
	game = null

func run() -> void:
	capture_enabled = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	view = SubViewport.new()
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.handle_input_locally = true
	root.add_child(view)
	for resolution: Vector2i in RESOLUTIONS:
		for locale: String in ["de","en"]: await review_locale_and_size(resolution,locale)
	L.set_locale("de",false)
	view.queue_free()
	await frames()
	var report := {"checks":checks,"failures":failures,"capture":capture_enabled,"actual_main_scene":true,"prepared_state":"Paused pre-match setup, two local players, free shift; no profile writes, no network/microphone, same authored choices for before and after.","resolutions":[[960,600],[1920,1080],[2560,1440]],"captures":captures,"references":[{"game":"God of War Ragnarök","url":"https://www.playstation.com/en-us/games/god-of-war-ragnarok/accessibility/"},{"game":"The Last of Us Part II","url":"https://www.playstation.com/en-us/games/the-last-of-us-part-ii/accessibility/"}]}
	var output := FileAccess.open(OUTPUT+("render-verification.json" if capture_enabled else "review-verification.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	output.close()
	print("SCENARIO UI REVIEW: %d/%d checks passed" % [checks-failures,checks])
	quit(0 if failures==0 else 1)
