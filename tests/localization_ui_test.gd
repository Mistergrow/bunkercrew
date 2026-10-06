extends SceneTree
## Real UI controls; --capture adds native 2560x1440 screenshots. Prepared wave,
## inventory and progression values exercise layouts, not a full playthrough.
const L := preload("res://scripts/locale_text.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Objectives := preload("res://scripts/story_objective_panel.gd")
const OUTPUT := "res://artifacts/localization-ui/"
var game
var capture_view: SubViewport
var capture_images := false
var checks := 0
var failures := 0
var captures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("LOCALE UI %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures += 1
		push_error(label)
func frames(count: int=3) -> void:
	for frame in count: await process_frame
func capture(label: String) -> void:
	if not capture_images: return
	await frames()
	await RenderingServer.frame_post_draw
	var picture := capture_view.get_texture().get_image()
	check(picture.get_size()==Vector2i(2560,1440),label+" native QHD dimensions")
	check(picture.save_png(OUTPUT+label+".png")==OK,label+" saved")
	captures.append(label)
func overlay(value: String) -> void:
	game.hud.overlay = value
	game.hud._apply_overlay_pause()
	await frames()
func visible_button_widths(node: Node,label: String) -> void:
	var fit := true
	var count := 0
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var item: Node = pending.pop_back()
		pending.append_array(item.get_children())
		if not item is Button or not item.is_visible_in_tree() or item.text.is_empty(): continue
		count += 1
		var value: String = item.tr(item.text)
		var width: float = item.get_theme_font("font").get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,item.get_theme_font_size("font_size")).x
		if width>item.size.x-12:
			fit = false
			print("OVERFLOW ",label," ",value," ",width," > ",item.size.x-12)
	check(fit and count>0,label+" visible native labels fit their buttons")

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Use --no-profile-save")
		quit(1)
		return
	L.set_locale("de",false)
	capture_images = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	root.size = Vector2i(1440,900)
	root.content_scale_size = Vector2i(1440,900)
	if capture_images:
		capture_view = SubViewport.new()
		capture_view.size = Vector2i(2560,1440)
		capture_view.size_2d_override = Vector2i(1600,900)
		capture_view.size_2d_override_stretch = true
		capture_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		capture_view.world_2d = World2D.new()
		root.add_child(capture_view)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	game = load("res://scenes/main.tscn").instantiate()
	if capture_images: capture_view.add_child(game)
	else:
		root.add_child(game)
		current_scene = game
	game.combat_events.persistence_enabled = false
	await frames(6)
	var menu = game.hud.main_menu_panel
	menu.browse_environment(2)
	var preview_index: int = menu.environment_index
	var elapsed_before: float = game.elapsed
	var menu_player: AudioStreamPlayer = game.audio.menu_music.player
	var menu_playback: WeakRef = weakref(menu_player.get_stream_playback())
	menu.utility_buttons[1].pressed.emit()
	await frames()
	game.hud.options_panel.select_tab(4)
	check(game.hud.language_buttons.size()==2 and game.hud.language_buttons[0].button_pressed and game.hud.language_buttons[0].is_visible_in_tree(),"Options language page exposes current German choice")
	var options_id: int = game.hud.options_panel.get_instance_id()
	game.hud.language_buttons[1].pressed.emit()
	await frames()
	check(L.current_locale()=="en" and game.hud.language_buttons[1].button_pressed and game.hud.options_panel.get_instance_id()==options_id,"Actual options English control switches locale immediately in place")
	check(menu_player.playing and menu_player.get_stream_playback()==menu_playback.get_ref(),"Options language switching preserves the actual menu music decoder")
	game.hud._close_audio()
	await frames()
	menu = game.hud.main_menu_panel
	check(menu.environment_index==preview_index and not game.started and is_equal_approx(game.elapsed,elapsed_before),"Returning from language options preserves menu preview and paused match")
	check(menu.utility_buttons[0].tr(menu.utility_buttons[0].text)=="Help · F1","Native controls translate through the registered catalog")
	visible_button_widths(menu,"main menu")
	await capture("en-main-menu")
	await overlay("audio")
	var slider_id: int = game.hud.sliders[0].get_instance_id()
	var volume_before: float = game.audio.music_volume
	game.hud.language_buttons[0].pressed.emit()
	await frames()
	check(L.current_locale()=="de" and game.hud.language_buttons[0].button_pressed,"F4 German control switches immediately")
	game.hud.language_buttons[1].pressed.emit()
	await frames()
	check(L.current_locale()=="en" and game.hud.sliders[0].get_instance_id()==slider_id and is_equal_approx(game.audio.music_volume,volume_before),"F4 language switch retains sliders and volume")
	visible_button_widths(game.hud.canvas,"settings")
	await capture("en-settings")
	game.hud._open_scenario_selection(2)
	await frames()
	var setup = game.hud.scenario_panel
	setup.choose("environment","mountain_pass")
	setup.choose("position","center")
	var options: Dictionary = setup.options.duplicate(true)
	L.set_locale("de",false)
	L.set_locale("en",false)
	check(setup.options==options and not game.started,"Scenario choices survive a round-trip language change")
	visible_button_widths(setup,"scenario selection")
	await capture("en-scenario-selection")
	setup.confirm()
	await frames()
	var characters = game.hud.character_panel
	characters.select_slot(1)
	characters.select_character("ivo")
	var selected: Array = game.selected_characters.duplicate()
	L.set_locale("de",false)
	L.set_locale("en",false)
	check(characters.active_slot==1 and game.selected_characters==selected and characters.slot_buttons[1].text.begins_with("Player 2"),"Character slot, selection and formatted labels update in place")
	check(characters.cards[0].tooltip_text==L.format("%s · %s",[CharacterCatalog.CHARACTERS[0].title,CharacterCatalog.CHARACTERS[0].detail]),"Character tooltip uses current language")
	visible_button_widths(characters,"character selection")
	await capture("en-character-selection")
	await overlay("network")
	var network = game.hud.network_panel
	network.show_server_options = true
	network.code_field.text = "ABCDEF"
	network.server_field.text = "wss://relay.example.invalid"
	network.public_address_field.text = "203.0.113.5"
	network.code_field.caret_column = 3
	var network_id: int = network.get_instance_id()
	L.set_locale("de",false)
	L.set_locale("en",false)
	await frames()
	check(network.get_instance_id()==network_id and network.code_field.text=="ABCDEF" and network.server_field.text=="wss://relay.example.invalid" and network.public_address_field.text=="203.0.113.5" and network.code_field.caret_column==3,"Online fields, caret and panel survive language switching unchanged")
	check(game.network.state=="offline" and not game.network.active,"Language switching opens no connection or room")
	visible_button_widths(network,"online lobby")
	await capture("en-online-lobby")
	game.story_mode = true
	game.start_scenario(2,{"environment":"mountain_pass","position":"center","build_type":"bastion"})
	game.rounds.running = false
	game.rounds.set_process(false)
	await frames()
	var player = game.players[0]
	player.progression.skill_points = 3
	player.inventory.ore = 4
	player.hp = 67
	game.upgrades.points = 12
	var player_id: int = player.get_instance_id()
	var health: float = player.hp
	var inventory: Dictionary = player.inventory.duplicate()
	await overlay("personal")
	var personal = game.hud.personal_panel
	personal.select_player(1)
	personal.select_tab("skills")
	L.set_locale("de",false)
	L.set_locale("en",false)
	check(personal.selected_player==1 and personal.tab=="skills" and personal.player_buttons[1].text.begins_with("Player 2"),"Personal panel retains player and tab while updating dynamic labels")
	visible_button_widths(personal,"skills")
	await capture("en-skills")
	personal.select_tab("achievements")
	game.combat_events.unlock("first_kill")
	await frames()
	visible_button_widths(personal,"achievements")
	await capture("en-achievements")
	await overlay("upgrades")
	game.hud.upgrade_panel._select("bunker_armor")
	L.set_locale("de",false)
	L.set_locale("en",false)
	check(game.hud.upgrade_panel.selected_id=="bunker_armor","Technology selection survives language switch")
	for language in ["de","en"]:
		L.set_locale(language,false)
		var titles_fit := true
		for category in UpgradeSystem.CATEGORIES.size():
			game.hud.upgrade_panel.select_category(category)
			for entry: Dictionary in game.upgrades.nodes_for_category(category):
				titles_fit = titles_fit and game.hud.upgrade_panel.node_title_lines(entry).size() <= 2
				titles_fit = titles_fit and game.hud.upgrade_panel._node_title_size(str(entry.title)) >= 14
		check(titles_fit,language+" technology labels retain internal card margins")
	visible_button_widths(game.hud.upgrade_panel,"technology")
	await capture("en-technology")
	await overlay("help")
	visible_button_widths(game.hud.canvas,"help")
	await capture("en-help")
	await overlay("pause")
	await capture("en-pause")
	check(player.get_instance_id()==player_id and is_equal_approx(player.hp,health) and player.inventory==inventory and game.story.stage==0,"Repeated locale changes preserve active players, health, cargo and objective state")
	for stage in range(10):
		game.story.stage = stage
		var lines: PackedStringArray = Objectives._wrap_lines(game.story.objective(),342,12)
		check(lines.size()<=2,"English objective stage %d fits its two-line panel"%stage)
	game.story.stage = 0
	for state in [DefenseWall.State.EMPTY,DefenseWall.State.FORM,DefenseWall.State.FRESH]:
		game.story.wall.state = state
		check(Objectives._wrap_lines(game.story.objective(),342,12).size()<=2,"English construction objective state %d fits"%state)
	game.story.wall.state = DefenseWall.State.EMPTY
	game.story.set_process(false)
	game.hud.combat_overlay.banners.clear()
	game.hud.overlay = ""
	await frames()
	player.focus = game.story.wall
	var details: Dictionary = game.hud.context_details(player)
	check(details.title==L.text("Bunkerwand") and details.action_lines.size()>0,"Interaction title and measured instructions use English")
	check(L.format("WELLE %02d /%02d",[4,20])=="WAVE 04 /20" and L.format("%d LP",67)=="67 HP","HUD numbers use translated templates")
	var number: Dictionary = {"amount":24.0,"earned":9.0,"kind":"kill"}
	check(game.hud.combat_overlay._number_lines(number)[0]=="24 · KILL","Combat text is localized before collision measurement")
	await capture("en-story-objective")
	var combat = game.hud.combat_overlay
	combat.handle_event("boss",{"title":"CUSTOM TRANSLATED NAME","final_boss":true})
	check(bool(combat.boss.final_boss),"Boss portrait decoration follows a stable flag, independent of translated title")
	combat.handle_event("boss",{"title":"MUTTERMASCHINE","subtitle":"VERTEIDIGUNGSSTELLEN BESETZEN","portrait":"siege","final_boss":true})
	combat.handle_event("kill",{"position":player.global_position+Vector2(-170,-80),"amount":24.0,"earned":9.0,"player_id":1})
	await capture("en-combat")
	combat.boss.clear()
	combat.numbers.clear()
	game.rounds.wave = 20
	game.rounds.phase = "victory"
	game.elapsed = 2183
	await overlay("victory")
	await capture("en-story-victory")
	game.rounds.phase = "defeat"
	game.core.hp = 0
	await overlay("defeat")
	await capture("en-story-defeat")
	L.set_locale("de",false)
	check(L.format("%d LP",67)=="67 LP" and game.hud._wrap("Wähle deine Figur",30)[0].begins_with("Wähle"),"German templates and wrapping restore immediately")
	check(await Cleanup.free_scene(game,self),"Localized real UI and audio resources release cleanly")
	if is_instance_valid(capture_view): capture_view.queue_free()
	print("LOCALIZATION UI: %d/%d checks passed; %d rendered views"%[checks-failures,checks,captures.size()])
	quit(1 if failures else 0)
