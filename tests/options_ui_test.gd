extends SceneTree
## Real UI routing, local settings and safe back navigation; physical mic stays off.
const L:=preload("res://scripts/locale_text.gd")
const Cleanup:=preload("res://tests/scene_cleanup.gd")
var game
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)
	print("OPTIONS %s: %s"%["PASS" if value else "FAIL",label])
func frames(count: int=3) -> void:
	for unused in count: await process_frame
func press(action: String) -> void:
	for down in [true,false]:
		var event:=InputEventAction.new()
		event.action=action
		event.pressed=down
		Input.parse_input_event(event)
		await process_frame
	await frames()
func widths(panel: Node) -> void:
	var pending: Array[Node]=[panel]
	var fits:=true
	while not pending.is_empty():
		var current: Node=pending.pop_back()
		pending.append_array(current.get_children())
		if not current is Button or not current.is_visible_in_tree() or current.text.is_empty(): continue
		var text: String=current.tr(current.text)
		var font: Font=current.get_theme_font("font")
		var extent: float=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,current.get_theme_font_size("font_size")).x
		if extent>current.size.x-24:
			fits=false
			print("OVERFLOW ",text," ",extent," / ",current.size.x)
	check(fits,"Visible localized controls fit: "+L.current_locale())
func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	L.set_locale("de",false)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.combat_events.persistence_enabled=false
	await frames()
	await press("audio_settings")
	var options=game.hud.options_panel
	check(is_instance_valid(options) and options.tab_buttons.size()==5,"F4 opens five real option categories")
	check(options.tab==0 and paused,"Display tab starts with the world paused")
	check(not game.microphone.capturing,"Options never open the microphone")
	for locale in ["de","en"]:
		L.set_locale(locale,false)
		for index in options.tab_buttons.size():
			options.tab_buttons[index].pressed.emit()
			await frames()
			check(options.pages[index].visible and options.pages.filter(func(page): return page.visible).size()==1,"Exactly one page is visible after tab activation")
			widths(options)
	var panel_id: int=options.get_instance_id()
	var tab_before: int=options.tab
	game.hud.language_buttons[0].pressed.emit()
	check(options.get_instance_id()==panel_id and options.tab==tab_before,"Language changes preserve panel and selected tab")
	options.select_tab(2)
	game.hud.sliders[0].value=.32
	game.hud.sliders[1].value=.57
	game.hud.sliders[2].value=.68
	check(is_equal_approx(game.audio.music_volume,.32) and is_equal_approx(game.audio.sfx_volume,.57) and is_equal_approx(game.audio.voice_volume,.68),"Audio controls still reach the three independent buses")
	options.select_tab(0)
	var previous: bool=game.weather.reduced_effects
	options.effects.button_pressed=not previous
	check(game.weather.reduced_effects!=previous,"Weather option reaches the real effects controller")
	options.effects.button_pressed=previous
	if game.has_method("camera_settings"):
		options.select_tab(1)
		options.camera_mode.item_selected.emit(1)
		check(game.camera_settings().mode=="overview","Camera mode selector updates actual camera settings")
		options.camera_mode.item_selected.emit(0)
		options.zoom_slider.value=1.15
		check(is_equal_approx(float(game.camera_settings().zoom),1.15),"Zoom slider updates actual camera settings")
	game.hud._open_microphone()
	await frames()
	check(game.hud.overlay=="microphone" and not game.microphone.capturing,"Microphone submenu starts inactive")
	await press("pause")
	check(game.hud.overlay=="audio" and game.hud.options_panel.tab==1,"Escape restores the selected options tab")
	await press("audio_settings")
	check(game.hud.overlay=="menu" and paused,"F4 returns to the paused main menu")
	game.start_scenario(2,{"environment":"ash_foundry","position":"center","build_type":"bastion"})
	await frames()
	await press("audio_settings")
	var remaining: float=game.rounds.time_left
	await create_timer(.08,true).timeout
	check(paused and is_equal_approx(game.rounds.time_left,remaining),"In-game options freeze the offline round timer")
	check(game.hud.options_panel.renderer_restart.disabled,"Renderer restart is unavailable during a match")
	await press("audio_settings")
	check(game.hud.overlay.is_empty() and not paused,"Closing options resumes the match")
	await Cleanup.free_scene(game,self)
	print("Options UI: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
