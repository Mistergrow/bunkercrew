extends SceneTree
## Genuine HUD, campaign/NPC and eight-character selection paths. All story,
## crew and music settings stay in the isolated, unsaved test process.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const L := preload("res://scripts/locale_text.gd")
const Dance := preload("res://scripts/worker_dance_catalog.gd")
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
	print("SOLO UI %s: %s" % ["PASS" if ok else "FAIL",message])

func frames(count: int=5) -> void:
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
	await frames(7)
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	game.solo_story.records.persistence_enabled = false

func _dispose() -> void:
	game.network.active = false
	game.network.state = "offline"
	paused = false
	check(not game.microphone.capturing,"Microphone remains closed")
	check(await Cleanup.free_scene(game,self),"Real scene and all audio handles release")
	game = null

func _tab_cycle(panel: Control,label: String) -> void:
	var controls: Array[Control] = panel._visible_controls()
	controls[0].grab_focus()
	await frames()
	var initial := root.gui_get_focus_owner()
	var seen: Dictionary = {}
	var valid := true
	for unused in controls.size():
		var focus := root.gui_get_focus_owner()
		valid = valid and is_instance_valid(focus) and panel.is_ancestor_of(focus) and focus.is_visible_in_tree()
		if is_instance_valid(focus): seen[focus.get_instance_id()] = true
		await key(KEY_TAB)
	check(valid and seen.size()==controls.size() and root.gui_get_focus_owner()==initial,label+" Tab reaches the complete native focus loop")
	await key(KEY_TAB,true)
	check(root.gui_get_focus_owner()!=initial,label+" Shift-Tab reverses the reading focus")

func _journal() -> void:
	# Deliberate renderer fixture: menu entry stays gated until a solo story is active.
	game.hud._open_solo_story("journal")
	check(game.hud.overlay=="menu", "Inactive main-menu J route stays gated")
	game.hud._solo_story_return_overlay = "menu"
	game.hud.overlay = "story_journal"
	await frames()
	var panel: Control = game.hud.solo_story_panel
	check(is_instance_valid(panel) and panel.site_buttons.size()==12,"Menu journal has twelve real native place buttons")
	check(game.players.is_empty() and not game.started and paused,"Reading from the menu creates no player or mission")
	check(not panel.recruit_button.visible,"Journal has no recruitment action")
	var unknown := L.text("Unbekannte Station")
	check(panel.site_buttons.all(func(button): return button.text==unknown),"Undiscovered stations reveal neither authored title nor NPC identity")
	var before: Dictionary = game.solo_story.records.capture()
	for locale: String in ["de","en"]:
		L.set_locale(locale,false)
		await frames()
		panel = game.hud.solo_story_panel
		panel.site_buttons[0].grab_focus()
		for index in range(1,panel.site_buttons.size()):
			await joy(JOY_BUTTON_DPAD_DOWN)
			check(panel.site_buttons[index].has_focus() and panel.selected_site==str(CampaignCatalog.NODES[index].id),locale+" D-pad selects journal station "+str(index))
		check(panel.journal_scroll.scroll_vertical>0 and panel.journal_scroll.get_global_rect().encloses(panel.site_buttons[-1].get_global_rect()),locale+" last station scrolls fully into view")
		await joy(JOY_BUTTON_DPAD_RIGHT)
		check(panel.reading_scroll.has_focus(),locale+" Right enters the native story reader")
		await key(KEY_END)
		await joy(JOY_BUTTON_DPAD_DOWN)
		check(panel.close_button.has_focus(),locale+" Down at the end reaches Close")
		await _tab_cycle(panel,locale+" journal")
	check(game.solo_story.records.capture()==before and not game.campaign.active,"Reading all twelve stations never advances narrative or campaign state")
	panel.select_site("mountain_pass")
	panel.reading_scroll.grab_focus()
	await frames()
	var state: Dictionary = panel.navigation_state()
	await key(KEY_ESCAPE)
	check(game.hud.overlay=="menu" and paused,"Escape returns journal to its original menu")
	game.hud._solo_story_return_overlay = "menu"
	game.hud.overlay = "story_journal"
	await frames()
	panel = game.hud.solo_story_panel
	check(panel.selected_site==state.site and panel.reading_scroll.has_focus(),"Reopening remembers selected place and actual native focus")
	L.set_locale("de",false)
	await frames()
	check(game.hud.solo_story_panel==panel and panel.selected_site==state.site and panel.reading_scroll.has_focus(),"Locale refresh preserves panel, place and reading focus")
	await key(KEY_ESCAPE)

func _characters() -> void:
	game.hud._open_character_selection(1)
	await frames()
	var panel: CharacterSelectPanel = game.hud.character_panel
	check(panel.cards.size()==8,"Character selection constructs all eight existing worker identities")
	check(panel.card_scroll.get_v_scroll_bar().visible,"Eight cards use a visible native scrollbar")
	for index in [6,7]:
		var id := str(CharacterCatalog.CHARACTERS[index].id)
		check(not CharacterCatalog.is_unlocked(id) and not panel.cards[index].tooltip_text.to_lower().contains(id),"Locked "+id+" remains anonymous in its accessible description")
	panel.cards[0].grab_focus()
	for unused in 6: await joy(JOY_BUTTON_DPAD_DOWN)
	check(panel.cards[6].has_focus() and panel.card_scroll.get_global_rect().encloses(panel.cards[6].get_global_rect()),"D-pad reaches seventh character and scrolls its entire selection row into view")
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(panel.cards[7].has_focus(),"D-pad reaches the eighth character in the vertical list")
	var selected := str(game.selected_characters[0])
	await joy(JOY_BUTTON_A)
	check(game.selected_characters[0]==selected,"Confirming an undiscovered character cannot select or unlock it")
	check(CrewRoster.unlock("rika"),"Prepared isolated crew entitlement unlocks Rika without writing a profile")
	panel._refresh()
	panel.cards[7].grab_focus()
	await joy(JOY_BUTTON_A)
	check(game.selected_characters[0]=="rika","Eighth character becomes selectable after real roster unlock")
	check(panel.card_scroll.get_global_rect().encloses(panel.cards[7].get_global_rect()),"Newly selected eighth character remains completely visible")
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(panel.begin_button.has_focus(),"Down from the final row reaches Start outside the scrolling cards")
	await joy(JOY_BUTTON_DPAD_LEFT)
	check(panel.back_button.has_focus(),"Footer D-pad reaches Back")
	await key(KEY_ESCAPE)
	game.selected_characters[0] = "mara"
	CrewRoster.unlocked.clear()

func _network_characters() -> void:
	for id: String in CrewRoster.RECRUITS: CrewRoster.unlock(id)
	game.hud._open_network()
	await frames()
	var panel: Control = game.hud.network_panel
	check(panel.character_buttons.size()==8,"Actual lobby constructs eight native character choices")
	check(not game.network.active,"Lobby inspection never creates a public or local network transport")
	# Only authentication state is arranged: there is no peer, socket or hub request.
	game.network.set_process(false)
	game.social_bridge.set_process(false)
	game.network.active = true
	game.network.is_host = true
	game.network.state = "lobby"
	panel._refresh()
	await frames()
	panel.character_buttons[0].grab_focus()
	await frames()
	for index in range(1,8):
		await joy(JOY_BUTTON_DPAD_DOWN)
		check(panel.character_buttons[index].has_focus(),"Lobby D-pad reaches character "+str(index+1))
	check(panel.character_scroll.scroll_vertical>0 and panel.character_scroll.get_global_rect().encloses(panel.character_buttons[7].get_global_rect()),"Lobby last identity scrolls into view above mission actions")
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(panel.leave_button.has_focus() or panel.start_button.has_focus(),"Lobby last identity reaches an available footer action")
	game.network.active = false
	game.network.state = "offline"
	game.hud.overlay = "menu"
	await frames()
	CrewRoster.unlocked.clear()

func _music_profiles() -> void:
	var lab = load("res://scripts/music_dev_dashboard.gd").new()
	lab.audition_enabled = false
	root.add_child(lab)
	await frames(8)
	check(lab.preview_world.actors.size()==8 and lab.styles.size()==8 and lab.gains.size()==8,"Music lab exposes all eight actual worker rigs and complete native profiles")
	var bounds := Rect2(0,0,1440,620)
	var rows: Dictionary = {}
	for actor: Worker in lab.preview_world.actors:
		check(bounds.has_point(actor.position),"Music rig "+actor.character_id+" stays inside the two-row preview")
		rows[actor.position.y] = true
	check(rows.size()==2 and lab.profile_grid.columns==4,"Eight rigs and controls use two balanced rows of four")
	lab.gains.rika.grab_focus()
	await frames()
	check(lab.interface_scroll.get_global_rect().encloses(lab.gains.rika.get_global_rect()),"Focusing Rika's lower-row slider scrolls it fully into view")
	var amount: float = lab.gains.rika.value
	await key(KEY_RIGHT)
	check(lab.gains.rika.value>amount and is_equal_approx(lab.configuration.dance_profiles.rika.intensity,lab.gains.rika.value),"Slider arrow still changes Rika's original dance intensity semantics")
	check(not lab.preview_session.native_active and not lab._owns_calibration,"Silent isolated lab opens neither audible preview nor gameplay calibration")
	lab.close()
	await frames(8)

func _prepare_quarry() -> void:
	var options := {"environment":"basalt_quarry","position":"center","build_type":"bastion"}
	check(game.campaign.begin_new(options,["mara"],1),"Prepared unsaved campaign initializes its genuine state")
	game.campaign.completed.assign(["last_shift","harbor"])
	check(game.campaign.select_destination("quarry") and not game.campaign.mission_start().is_empty(),"Prepared secured ancestors authorize the real quarry mission")
	game.story_mode = true
	game.start_scenario(1,options)
	game.rounds.running = false
	game.rounds.set_process(false)
	game.solo_story.set_process(false)
	await frames()
	check(game.solo_story.enabled and game.solo_story.npcs.has("oskar"),"Real solo quarry world creates its physical Oskar encounter")
	var objectives := get_nodes_in_group("story_objective_panels").filter(func(panel): return panel.director==game.story)
	check(objectives.size()==1 and objectives[0].is_visible_in_tree() and not objectives[0].objective_layout().is_empty(),"Genuine solo story creates one visible populated objective panel")
	var npc: Node2D = game.solo_story.npcs.oskar
	game.players[0].position = npc.position+Vector2(16,0)
	game.players[0].set_physics_process(false)
	game.players[0].inventory.clear()
	game.rounds.phase = "build"

func _encounter() -> void:
	await _prepare_quarry()
	var worker: Worker = game.players[0]
	var npc: Node2D = game.solo_story.npcs.oskar
	check(npc.interact(worker,0.0),"Physical nearby E interaction opens the genuine authored encounter")
	await frames()
	var panel: Control = game.hud.solo_story_panel
	check(panel.mode=="encounter" and panel.encounter_id=="oskar" and paused and panel.close_button.has_focus(),"Encounter opens paused with a safe Close default focus")
	check(panel.recruit_button.disabled and str(panel._encounter.reason).contains("3"),"Before three defended waves the disabled CTA explains the missing requirement")
	var before_inventory: Dictionary = worker.inventory.duplicate()
	panel._recruit()
	check(not CharacterCatalog.is_unlocked("oskar") and worker.inventory==before_inventory,"Disabled recruit cannot bypass mission progress or consume materials")
	await _tab_cycle(panel,"Locked encounter")
	await key(KEY_ESCAPE)
	check(game.hud.overlay.is_empty() and not paused,"Escape resumes the actual quarry after dialogue")
	game.solo_story._cleared_wave = 3 # Prepared UI fixture; combat trigger is covered by controller regression.
	check(npc.interact(worker,0.0),"The same physical NPC reopens after prepared defended-wave evidence")
	await frames()
	panel = game.hud.solo_story_panel
	check(panel.recruit_button.disabled and str(panel._encounter.reason).contains("2"),"Safe encounter with missing concrete gives its exact material requirement")
	await key(KEY_ESCAPE)
	worker.inventory.concrete = 2
	check(npc.interact(worker,0.0),"Physical NPC opens with the required two concrete in the worker's hands")
	await frames()
	panel = game.hud.solo_story_panel
	check(not panel.recruit_button.disabled,"Safe encounter and real carried materials enable explicit recruitment")
	await _tab_cycle(panel,"Ready encounter")
	panel.close_button.grab_focus()
	await joy(JOY_BUTTON_DPAD_RIGHT)
	check(panel.recruit_button.has_focus(),"D-pad Right reaches the explicit recruitment choice")
	var current_panel := panel
	var campaign_before: Dictionary = game.campaign.checkpoint()
	var player_count_before: int = game.players.size()
	await joy(JOY_BUTTON_A)
	check(game.hud.solo_story_panel==current_panel and game.hud.overlay=="story_encounter" and paused,"Recruitment displays its outcome without automatically dismissing the dialogue")
	check(CharacterCatalog.is_unlocked("oskar") and "oskar" in game.solo_story.records.recruited and int(worker.inventory.get("concrete",0))==0,"Real recruitment commits Oskar and consumes exactly his two concrete")
	check(panel.recruit_button.disabled and panel.close_button.has_focus() and not str(panel._encounter.reason).is_empty(),"After recruitment CTA is disabled, outcome is readable and Close owns focus")
	check(game.players.size()==player_count_before and game.campaign.checkpoint()==campaign_before,"Recruitment creates no duplicate worker or campaign mission reward")
	panel._recruit()
	check(int(worker.inventory.get("concrete",0))==0,"Repeating the disabled CTA never consumes another material")
	L.set_locale("en",false)
	await frames()
	check(panel.recruit_button.text=="Welcome to the crew" and panel.close_button.has_focus(),"English dialogue keeps the accepted outcome and native Close focus")
	await key(KEY_ESCAPE)
	await key(KEY_J)
	panel = game.hud.solo_story_panel
	check(game.hud.overlay=="story_journal" and panel.mode=="journal" and paused,"Actual in-game J routes to the solo journal")
	panel.select_site("quarry")
	await frames()
	check(panel._entry("quarry").details.any(func(detail): return str(detail.title).to_lower().contains("oskar")),"Journal includes the genuinely contacted and rescued NPC")
	check(panel._entry("power_station").details.is_empty() and panel._entry("power_station").title==L.text("Unbekannte Station"),"Future Rika station stays anonymous after Oskar recruitment")
	var recorded: Dictionary = game.solo_story.records.capture()
	await key(KEY_J)
	check(game.hud.overlay.is_empty() and not paused and game.solo_story.records.capture()==recorded,"J returns to the shift without changing journal evidence")

func _finds() -> void:
	check(game.solo_story.finds.size()==2,"Genuine quarry world contains both physical field records")
	var worker: Worker = game.players[0]
	var inventory_before: Dictionary = worker.inventory.duplicate()
	var campaign_before: Dictionary = game.campaign.checkpoint()
	for id: String in ["quarry:find_1","quarry:find_2"]:
		var find: Node2D = game.solo_story.finds[id]
		worker.position = find.position+Vector2(8,0)
		check(find.interact(worker,0.0),"Physical nearby field record opens "+id)
		await frames(8)
		var panel: Control = game.hud.solo_story_panel
		check(panel.mode=="journal" and panel.selected_site=="quarry" and panel.reading_scroll.has_focus(),id+" opens its real journal site with reader focus")
		var matches: Array = panel.reading_content.get_children().filter(func(block): return str(block.get_meta("entry_id",""))==id)
		check(matches.size()==1 and panel.reading_scroll.get_global_rect().encloses(matches[0].get_child(0).get_global_rect()),id+" locator scrolls the actual authored section into view")
		check(panel._target_entry.is_empty() and not game.hud.solo_story_navigation.has("entry"),id+" locator is consumed once after native layout")
		var amount: int = game.solo_story.records.events.count(id)
		check(amount==1 and worker.inventory==inventory_before and game.campaign.checkpoint()==campaign_before,id+" records exactly one discovery and grants no resources or campaign reward")
		var position: int = panel.reading_scroll.scroll_vertical
		var locale := "de" if L.current_locale()=="en" else "en"
		L.set_locale(locale,false)
		await frames(8)
		check(panel.reading_scroll.has_focus() and panel.reading_scroll.scroll_vertical==mini(position,roundi(panel.reading_scroll.get_v_scroll_bar().max_value-panel.reading_scroll.get_v_scroll_bar().page)),id+" locale refresh preserves reading focus and its clamped scroll")
		await key(KEY_ESCAPE)
		check(find.interact(worker,0.0),"Already-read physical record can be reread "+id)
		await frames(8)
		check(game.solo_story.records.events.count(id)==amount,"Rereading "+id+" never duplicates progress")
		await key(KEY_ESCAPE)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size = Vector2i(1440,900)
	AudioServer.set_bus_mute(0,true)
	CrewRoster.persistence_enabled = false
	CrewRoster._loaded = true
	CrewRoster.unlocked.clear()
	L.set_locale("de",false)
	await _fixture()
	await _journal()
	await _characters()
	await _network_characters()
	await _music_profiles()
	await _dispose()
	CrewRoster.unlocked.clear()
	L.set_locale("de",false)
	await _fixture()
	await _encounter()
	await _finds()
	await _dispose()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/solo-story/ui/"))
	FileAccess.open("res://artifacts/solo-story/ui/ui-test.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"fixture":"Actual main scene, native keyboard/joypad events, genuine offline quarry controller/NPC and eight existing worker identities. Quarry ancestors and three defended-wave evidence are prepared for UI inspection; controller tests own combat provenance. Master muted, isolated unsaved profiles, no transports or microphone."},"  "))
	print("SOLO STORY UI: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
