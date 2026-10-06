extends SceneTree
var checks := 0
var failures := 0
var game
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func frames(count: int=3) -> void:
	for frame in count: await process_frame
func run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.hud._toggle_personnel()
	await frames()
	var panel: PersonalPanel=game.hud.personal_panel
	check(is_instance_valid(panel) and game.players.is_empty(),"Main-menu personnel panel opens without constructing a worker")
	for button in panel.skill_buttons.values():
		check(button.disabled,"Menu skill purchase remains disabled")
		button.pressed.emit()
	panel.purchase("combat")
	panel.select_tab("achievements")
	check(panel.page_buttons.all(func(button):return button.visible),"Saved achievements remain accessible before starting a shift")
	for locale in ["de","en"]:
		LocaleText.set_locale(locale,false)
		panel.refresh_locale()
		await frames(5)
		check(panel.skill_buttons.values().all(func(button):return button.disabled),"Localization preserves disabled purchases without workers")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/network-followup/menu-achievements.png")
	game.hud._close_personnel()
	game.hud._open_scenario_selection(1)
	await frames()
	game.hud.scenario_panel.classic_button.pressed.emit()
	await frames()
	game.hud._close_character_selection()
	check(game.hud.overlay=="scenario" and not game.started,"Classic character Back returns to scenario selection")
	check(game.combat_events.has_method("set_achievement_provider") and game.combat_events.set_achievement_provider(null),"Documented Steam provider entry point remains available")
	game.start_scenario(1,{"environment":"sector07","build_type":"workshop","position":"left"})
	game.rounds.running=false
	paused=true
	for planned in [2,3,4]:
		game.expedition.route={"ambushes":planned}
		game.expedition._start_road(true)
		check(game.expedition.ambushes==(1 if planned==2 else 2),"Resumed route remembers every ambush before its stop")
		var before: int=game.expedition.ambushes
		game.expedition._physics_process(0)
		check(game.expedition.ambushes==before,"Resuming at midpoint never repeats an earlier ambush")
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("MENU FOLLOWUP: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
