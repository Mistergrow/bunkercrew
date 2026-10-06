extends SceneTree
## Real personnel navigation, retained rights and complete localized content.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Dances := preload("res://scripts/worker_dance_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	print("PERSONNEL %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures += 1
		push_error(label)

func frames(count: int = 2) -> void:
	for frame in count: await process_frame

func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await frames()
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await frames()

func controls_fit(panel: PersonalPanel) -> bool:
	var controls: Array[Button] = panel._content_controls()
	controls.append_array(panel.tab_buttons.values())
	controls.append(panel.close_button)
	for button in controls:
		var style := button.get_theme_stylebox("normal")
		var width := button.size.x-style.content_margin_left-style.content_margin_right
		var font := button.get_theme_font("font")
		if font.get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x>width: return false
		if not Rect2(0,0,1440,900).encloses(button.get_rect()): return false
	return true

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	await frames()
	game.hud._toggle_personnel()
	await frames()
	var panel: PersonalPanel = game.hud.personal_panel
	check(game.players.is_empty() and is_instance_valid(panel._landscape.get("preview")),"Main-menu personnel shares the options/lobby landscape without creating actors")
	check(panel.skill_buttons.values().all(func(button: Button): return button.disabled and not button.visible),"Empty roster disables and hides purchases without corresponding skill rows")
	check(panel.tab_buttons.skills.get_theme_stylebox("normal").bg_color.a==0,"Categories retain the shared transparent action style")
	await press("ui_down")
	check(panel.tab=="achievements" and panel.tab_buttons.achievements.has_focus(),"Keyboard/controller down selects and focuses the next category")
	await press("ui_right")
	check(panel.page_buttons[1].has_focus(),"Right reaches the available next page while skipping the disabled previous page")
	await press("ui_left")
	check(panel.tab_buttons.achievements.has_focus(),"Left returns from achievements to the selected category")
	panel.page_buttons[1].grab_focus()
	panel.select_tab("dances")
	await frames()
	check(panel.tab_buttons.dances.has_focus() and panel.dance_buttons.all(func(button: Button): return not button.visible),"Changing category releases hidden content focus and keeps empty dance choices inert")
	await press("ui_cancel")
	check(game.hud.overlay=="menu" and not game.started,"Personnel cancel restores the originating main menu")
	game.selected_characters.assign(["mara","branko","ivo","mara"])
	game.start_scenario(4,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.rounds.running = false
	game.rounds.set_process(false)
	for worker: Node in game.players: worker.set_physics_process(false)
	game.hud._toggle_personnel()
	await frames()
	panel = game.hud.personal_panel
	check(panel.player_buttons.size()==4 and not is_instance_valid(panel._landscape.get("preview")),"In-game personnel retains the real paused world and all four crew selections")
	for index in 4:
		panel.player_buttons[index].pressed.emit()
		check(panel.selected_player==index,"Crew selection reaches actual worker %d" % (index+1))
	game.players[3].progression.award_damage(500)
	panel.skill_buttons.engineering.grab_focus()
	panel.skill_buttons.engineering.pressed.emit()
	await frames()
	check(game.players[3].progression.skills.engineering==1 and game.players[0].progression.skills.engineering==0,"Purchase still belongs exclusively to the selected worker")
	check(panel.tab_buttons.skills.has_focus(),"Spending the final point restores focus from the now disabled purchase")
	panel.select_tab("dances")
	game.combat_events.record_character_dance_level("mara",10)
	panel.dance_buttons[-1].grab_focus()
	panel.select_player(1)
	await frames()
	check(panel.tab_buttons.dances.has_focus() and panel.dance_buttons[-1].disabled,"Selecting a crew member whose move is locked repairs the disabled focus")
	panel.select_player(0)
	panel.dance_buttons[1].grab_focus()
	await press("ui_right")
	check(panel.dance_buttons[2].has_focus(),"Shared dance moves navigate horizontally in their actual row")
	await press("ui_up")
	check(panel.dance_buttons[0].has_focus(),"Shared moves navigate up to the automatic dance choice")
	for language: String in ["de","en"]:
		LocaleText.set_locale(language,false)
		for category: String in panel.TAB_TITLES:
			panel.select_tab(category)
			panel.refresh_locale()
			check(controls_fit(panel),language+": visible native actions and four crew selections fit on the actual canvas")
		var achievements_fit := true
		for record: Dictionary in CombatEvents.ACHIEVEMENTS:
			achievements_fit = achievements_fit and UiArt.wrap_text(str(record.title),panel.ACHIEVEMENT_TITLE_WIDTH,16).size()<=2 and UiArt.wrap_text(str(record.detail),panel.ACHIEVEMENT_DETAIL_WIDTH,13).size()<=4
		check(achievements_fit,language+": every achievement retains its complete title, description and separate progress line")
		var skills_fit := true
		for spec: Dictionary in PlayerProgression.SKILL_SPECS.values():
			skills_fit = skills_fit and UiArt.wrap_text(str(spec.detail),490,16).size()<=2
		check(skills_fit,language+": full skill effects fit clear of purchase actions")
		for character: String in Dances.IDS:
			var worker = game.players[0]
			worker.configure_character(character)
			game.combat_events.record_character_dance_level(character,10)
			panel.select_player(0)
			panel.select_tab("dances")
			check(controls_fit(panel),language+": all unlocked "+character+" dance titles fit their real controls")
	LocaleText.set_locale("de",false)
	game.network.set_process(false)
	game.network.active = true
	game.network.local_player_id = 3
	game.players[2].progression.award_damage(500)
	panel.select_tab("skills")
	panel.select_player(0)
	var prior_skills: Dictionary = game.players[0].progression.skills.duplicate()
	panel.purchase("combat")
	check(panel.skill_buttons.values().all(func(button: Button): return button.disabled) and game.players[0].progression.skills==prior_skills,"Remote crew cannot be upgraded through controls or direct purchase callbacks")
	panel.select_tab("dances")
	var prior_dance: String = game.audio.dance_profiles[game.players[0].character_id].style
	check(not panel.select_dance("crew_bounce") and game.audio.dance_profiles[game.players[0].character_id].style==prior_dance,"Remote dance preferences remain read-only")
	var original_roster: Array = game.players.duplicate()
	game.players.assign([original_roster[0],original_roster[2]])
	panel.select_tab("skills")
	panel.select_player(1)
	check(not panel.skill_buttons.combat.disabled,"Sparse online roster checks actual player identity, rather than its list index")
	panel.player_buttons[1].grab_focus()
	game.players.assign([original_roster[0]])
	panel._refresh()
	game.network.active = false
	game.network.local_player_id = 1
	await frames()
	check(panel.selected_player==0 and panel.player_buttons.size()==1 and panel.tab_buttons.skills.has_focus(),"A departing selected crew member leaves a valid roster and usable category focus")
	game.players.assign(original_roster)
	game.network.set_process(true)
	check(await Cleanup.free_scene(game,self),"Personnel fixture retires UI, world and actual audio handles")
	print("PERSONNEL PRESENTATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
