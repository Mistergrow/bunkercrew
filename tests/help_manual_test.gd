extends SceneTree
## Native F1 routing, six complete reading pages, local advice and input focus.
## The online case arranges session ownership only; it never opens a transport.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Catalog := preload("res://scripts/help_manual_catalog.gd")
const L := preload("res://scripts/locale_text.gd")
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	print("MANUAL %s: %s" % ["PASS" if ok else "FAIL",message])

func frames(count: int=4) -> void:
	for unused in count: await process_frame

func key(code: Key,shift: bool=false) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.shift_pressed = shift
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await frames()

func joy(code: JoyButton) -> void:
	for down in [true,false]:
		var event := InputEventJoypadButton.new()
		event.button_index = code
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await frames()

func _fixture() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(6)
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false

func _dispose() -> void:
	game.network.active = false
	game.network.state = "offline"
	paused = false
	check(await Cleanup.free_scene(game,self),"Actual main scene and audio handles release cleanly")
	game = null

func _tab_cycle(panel: Control,label: String) -> void:
	var controls: Array[Control] = panel._visible_controls()
	panel.page_buttons[panel._page_index()].grab_focus()
	await frames()
	var initial := root.gui_get_focus_owner()
	var reached: Dictionary = {}
	var only_panel := true
	for unused in controls.size():
		var focus := root.gui_get_focus_owner()
		only_panel = only_panel and is_instance_valid(focus) and focus.is_visible_in_tree() and panel.is_ancestor_of(focus)
		if is_instance_valid(focus): reached[focus.get_instance_id()] = true
		await key(KEY_TAB)
	var all_controls := reached.size()==controls.size()
	for control: Control in controls: all_controls = all_controls and reached.has(control.get_instance_id())
	check(only_panel,label+" Tab stays in the visible manual")
	check(all_controls and root.gui_get_focus_owner()==initial,label+" Tab reaches pages, reader, scrollbar and actions once")
	await key(KEY_TAB,true)
	check(root.gui_get_focus_owner()!=initial,label+" Shift-Tab moves backwards")
	await key(KEY_TAB)
	check(root.gui_get_focus_owner()==initial,label+" Forward Tab reverses Shift-Tab")

func _pages(panel: Control,locale: String) -> void:
	for index in Catalog.PAGES.size():
		var id := str(Catalog.PAGES[index].id)
		panel.page_buttons[index].grab_focus()
		await joy(JOY_BUTTON_A)
		check(panel.page_id==id and panel.page_buttons[index].button_pressed,locale+" controller selects "+id)
		check(panel.page_buttons[index].text!=str(Catalog.PAGES[index].title) if locale=="en" else panel.page_buttons[index].text==str(Catalog.PAGES[index].title),locale+" native page title uses the selected language")
		check(panel.page_buttons.filter(func(button): return button.button_pressed).size()==1,locale+" only one manual page is selected")
		var sections: Array[Dictionary] = Catalog.sections(id,game)
		check(not sections.is_empty() and sections.all(func(section): return not str(section.title).is_empty() and not str(section.body).is_empty()),locale+" "+id+" has complete translated sections")
		await key(KEY_RIGHT)
		check(panel.reading_scroll.has_focus(),locale+" Right enters the reader for "+id)
		await key(KEY_END)
		var bar: VScrollBar = panel.reading_scroll.get_v_scroll_bar()
		check(panel.reading_scroll.scroll_vertical>=maxi(0,roundi(bar.max_value-bar.page)-1),locale+" End reaches the complete "+id+" page")
		check(panel.reading_content.size.x<=panel.reading_scroll.size.x+1,locale+" "+id+" wraps inside the reading column")
		await key(KEY_HOME)
		check(panel.reading_scroll.scroll_vertical==0,locale+" Home returns "+id+" to the first section")
		await joy(JOY_BUTTON_DPAD_UP)
		check(panel.page_buttons[index].has_focus(),locale+" Up at the beginning returns to the page navigation")
		await key(KEY_RIGHT)
		await joy(JOY_BUTTON_DPAD_LEFT)
		check(panel.page_buttons[index].has_focus(),locale+" Left returns to the current page "+id)
		await _tab_cycle(panel,locale+" "+id)
	panel.page_buttons[0].grab_focus()
	panel.select_page("first_shift")
	await frames()
	for index in range(1,Catalog.PAGES.size()):
		await joy(JOY_BUTTON_DPAD_DOWN)
		check(panel.page_buttons[index].has_focus() and panel.page_id==str(Catalog.PAGES[index].id),locale+" D-pad Down selects page "+str(index))
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(panel.options_button.has_focus(),locale+" D-pad reaches Options after the last page")
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(panel.back_button.has_focus(),locale+" D-pad reaches Back after Options")
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(panel.page_buttons[0].has_focus(),locale+" D-pad wraps Back to the first page")

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	AudioServer.set_bus_mute(0,true)
	L.set_locale("de",false)
	await _fixture()
	check(game.players.is_empty() and paused and not game.started,"Initial main menu has no hidden workers")
	await key(KEY_F1)
	var panel: Control = game.hud.help_panel
	check(game.hud.overlay=="help" and is_instance_valid(panel),"Actual F1 opens the native field manual")
	check(panel.page_buttons.size()==6 and game.players.is_empty() and paused,"Six reading pages work before starting a shift")
	for locale: String in ["de","en"]:
		L.set_locale(locale,false)
		await frames()
		await _pages(panel,locale)
	panel.select_page("controls")
	await frames()
	var native_scrollbar: VScrollBar = panel.reading_scroll.get_v_scroll_bar()
	native_scrollbar.grab_focus()
	await key(KEY_HOME)
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(native_scrollbar.has_focus() and panel.reading_scroll.scroll_vertical>0,"Focused native scrollbar responds to the actual controller")
	await joy(JOY_BUTTON_DPAD_LEFT)
	check(panel.page_buttons[1].has_focus(),"Controller Left leaves the native scrollbar for its selected page")
	panel.reading_scroll.grab_focus()
	await frames()
	await key(KEY_PAGEDOWN)
	var saved_scroll: int = panel.reading_scroll.scroll_vertical
	check(saved_scroll>0,"Long control reference scrolls with Page Down")
	L.set_locale("de",false)
	await frames()
	check(game.hud.help_panel==panel and panel.page_id=="controls" and panel.reading_scroll.has_focus(),"Locale refresh keeps the same panel, page and reading focus")
	check(panel.reading_scroll.scroll_vertical==saved_scroll,"Locale refresh preserves the reading position")
	panel.options_button.grab_focus()
	await key(KEY_ENTER)
	check(game.hud.overlay=="audio" and is_instance_valid(game.hud.options_panel) and paused,"Manual Options opens the real settings without resuming the menu")
	await key(KEY_ESCAPE)
	panel = game.hud.help_panel
	check(game.hud.overlay=="help" and panel.page_id=="controls" and panel.options_button.has_focus(),"Settings Back restores the original manual page and opener focus")
	check(panel.reading_scroll.scroll_vertical==saved_scroll,"Settings Back restores the same scroll position")
	await key(KEY_F1)
	check(game.hud.overlay=="menu" and paused,"F1 returns to the original main menu")
	await key(KEY_F1)
	panel = game.hud.help_panel
	check(panel.page_id=="controls" and panel.reading_scroll.scroll_vertical==saved_scroll,"Reopening F1 remembers its last page and scroll")
	panel.select_page("first_shift")
	await frames()
	var advice := Catalog.current_advice(game)
	if panel.context_button.visible:
		var before: Dictionary = game.combat_events.session_records()
		panel.context_button.grab_focus()
		await key(KEY_ENTER)
		check(panel.page_id==str(advice.page),"Current advice opens its corresponding reference page")
		check(game.combat_events.session_records()==before and game.players.is_empty(),"Advice link does not start a shift or modify cosmetic progress")
	await key(KEY_ESCAPE)
	check(game.hud.overlay=="menu" and not game.started,"Escape returns from the manual without starting the world")
	await _dispose()
	await _fixture()
	game.start_scenario(2,{"environment":"ash_foundry","position":"center","build_type":"bastion"})
	game.rounds.running = false
	game.rounds.set_process(false)
	await frames()
	await key(KEY_F1)
	check(game.hud.overlay=="help" and paused and game.hud.help_panel._landscape.is_empty(),"In-game F1 pauses locally and retains the actual bunker behind the manual")
	panel = game.hud.help_panel
	var source_worker: Worker = game.players[0]
	source_worker.inventory["ore"] = source_worker.capacity()
	panel.select_page("first_shift")
	panel._process(.3)
	await frames()
	check(panel.context_button.visible and panel._advice.id=="inventory_full","Prepared full inventory produces its real production advice and reference link")
	panel.reading_scroll.grab_focus()
	await key(KEY_END)
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(panel.context_button.has_focus(),"Controller Down at the end reaches the current advice link")
	check(panel.reading_scroll.get_global_rect().encloses(panel.context_button.get_global_rect()),"Focusing the advice link scrolls it fully into view")
	var actual_inventory: Dictionary = source_worker.inventory.duplicate()
	var actual_points: int = game.upgrades.points
	var actual_wave: int = game.rounds.wave
	await key(KEY_ENTER)
	check(panel.page_id=="workshop" and panel.page_buttons[2].has_focus(),"Advice Enter navigates to Production and its native category")
	check(source_worker.inventory==actual_inventory and game.upgrades.points==actual_points and game.rounds.wave==actual_wave,"Following advice leaves materials, research and wave state unchanged")
	panel.reading_scroll.grab_focus()
	await key(KEY_END)
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(panel.options_button.has_focus(),"Controller Down at the end reaches Options when no contextual link is present")
	await key(KEY_ESCAPE)
	check(game.hud.overlay.is_empty() and not paused,"Escape from direct gameplay help resumes only its original route")
	await key(KEY_ESCAPE)
	check(game.hud.overlay=="pause" and paused,"Escape opens the actual pause menu")
	await key(KEY_F1)
	check(game.hud.overlay=="help" and paused,"F1 from pause opens the manual without resuming")
	await key(KEY_ESCAPE)
	check(game.hud.overlay=="pause" and paused,"Back from paused help returns to pause")
	await key(KEY_ESCAPE)
	for worker in game.players: worker.set_physics_process(false)
	game.network.set_process(false)
	game.network.active = true
	game.network.is_host = false
	game.network.local_player_id = 2
	game.network.state = "playing"
	game.network.peer_connected = true
	game.network.match_paused = false
	await key(KEY_F1)
	panel = game.hud.help_panel
	check(game.hud.overlay=="help" and not paused,"Guest F1 is a local reader and does not pause the other players")
	check(panel._advice.id!="inventory_full","Guest advice reads the guest's own worker instead of the full host inventory")
	game.players[1].inventory["ore"] = game.players[1].capacity()
	panel._process(.3)
	check(panel._advice.id=="inventory_full","Guest advice responds to that guest's real carried load")
	var guest_rows: Array[Dictionary] = Catalog.controls(game)
	check(not guest_rows.is_empty() and guest_rows.all(func(row): return str(row.primary)==str(row.secondary)),"Online controls describe each player's own keyboard instead of offline P2 bindings")
	check(game.network.transport==null and not game.microphone.capturing,"Prepared guest manual opens neither transport nor microphone")
	game.network.match_paused = true
	paused = true
	await key(KEY_ESCAPE)
	check(game.hud.overlay=="pause" and paused,"Closing local help respects a shared pause received while reading")
	await _dispose()
	await _fixture()
	game.start(1)
	game.rounds.running = false
	game.rounds.set_process(false)
	await frames()
	await key(KEY_F1)
	panel = game.hud.help_panel
	for entry: Dictionary in Catalog.PAGES:
		panel.select_page(str(entry.id))
		await frames()
		check(not Catalog.sections(str(entry.id),game).is_empty(),"Classic bunker provides the complete "+str(entry.id)+" reference safely")
	check(not game.microphone.capturing and not game.network.active,"Every offline manual page leaves online services and microphone inactive")
	for path: String in ["user://audio.cfg","user://language.cfg","user://achievements.cfg",CampaignState.SAVE_PATH,"user://camera.cfg","user://display.cfg"]:
		check(not FileAccess.file_exists(path),"Manual never writes "+path)
	await _dispose()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/archive-review/guide"))
	var report := {"checks":checks,"failures":failures,"fixture":"Actual F1, keyboard and controller routing in disposable main scenes: menu with no worker, scenario, classic bunker, arranged guest local-player ownership without sockets. All persistence disabled; master muted."}
	FileAccess.open("res://artifacts/archive-review/guide/manual-test.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("HELP MANUAL: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
