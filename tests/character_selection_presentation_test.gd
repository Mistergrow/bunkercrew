extends SceneTree
## Real input ownership, native scroll/focus and actual local actor spawning.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Roster := preload("res://scripts/crew_roster.gd")
var game
var view: SubViewport
var checks := 0
var failures := 0
var presses := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	print("CHARACTER PRESENTATION %s: %s"%["PASS" if ok else "FAIL",label])

func frames(count: int = 3) -> void:
	for unused in count:
		await process_frame

func key(code: Key,shift: bool = false) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.shift_pressed = shift
		event.pressed = down
		view.push_input(event,true)
		await process_frame
	await frames()

func joy(code: JoyButton) -> void:
	for down in [true,false]:
		var event := InputEventJoypadButton.new()
		event.button_index = code
		event.pressed = down
		view.push_input(event,true)
		await process_frame
	await frames()

func move_mouse(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point-view.get_mouse_position()
	view.push_input(event,true)
	await frames()

func mouse_button(point: Vector2,button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button
		event.pressed = down
		view.push_input(event,true)
		await process_frame
	await frames()

func mouse_center(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas()*(control.size*.5)

func focused_inside(panel: Control) -> bool:
	var control := view.gui_get_focus_owner()
	return is_instance_valid(control) and control.is_visible_in_tree() and panel.is_ancestor_of(control) and not (control is BaseButton and control.disabled)

func focusable(panel: Control) -> Array[Control]:
	var result: Array[Control] = []
	var pending: Array[Node] = [panel]
	while not pending.is_empty():
		var child: Node = pending.pop_back()
		# ScrollContainer owns its native scrollbar as an internal child.
		pending.append_array(child.get_children(true))
		if not child is Control or not child.is_visible_in_tree() or child.focus_mode==Control.FOCUS_NONE:
			continue
		if child is BaseButton and child.disabled:
			continue
		result.append(child)
	return result

func tab_cycle(panel: CharacterSelectPanel,label: String) -> void:
	panel.cards[0].grab_focus()
	await frames()
	var initial := view.gui_get_focus_owner()
	var expected := focusable(panel)
	var visited: Dictionary = {}
	var sequence: Array[String] = []
	var valid := true
	for unused in expected.size():
		var focused := view.gui_get_focus_owner()
		valid = valid and focused_inside(panel)
		if is_instance_valid(focused):
			visited[focused.get_instance_id()] = true
		sequence.append(_focus_label(panel,focused))
		await key(KEY_TAB)
	if not valid or view.gui_get_focus_owner()!=initial or not expected.all(func(control: Control): return visited.has(control.get_instance_id())):
		print("TAB STATE ",label," expected=",expected.map(func(control: Control): return _focus_label(panel,control))," sequence=",sequence," final=",_focus_label(panel,view.gui_get_focus_owner()))
	check(valid and view.gui_get_focus_owner()==initial,label+": native Tab stays inside selection and wraps")
	check(expected.all(func(control: Control): return visited.has(control.get_instance_id())),label+": Tab reaches every enabled control including the native scrollbar")
	await key(KEY_TAB,true)
	check(focused_inside(panel) and view.gui_get_focus_owner()!=initial,label+": Shift-Tab traverses backward without a hidden focus")
	await key(KEY_TAB)
	check(view.gui_get_focus_owner()==initial,label+": forward Tab reverses the backward step")

func _focus_label(panel: CharacterSelectPanel,control: Control) -> String:
	if not is_instance_valid(control): return "none"
	if control is Button:
		for role: String in ["card","slot","count"]:
			var controls: Array = panel.cards if role=="card" else panel.slot_buttons if role=="slot" else panel.count_buttons
			var index := controls.find(control)
			if index>=0: return role+str(index)
	if control==panel.begin_button: return "begin"
	if control==panel.back_button: return "back"
	if control==panel.card_scroll.get_v_scroll_bar(): return "scrollbar"
	return control.get_class()+":"+str(control.name)

func _text_fits(panel: CharacterSelectPanel) -> bool:
	for control: Control in focusable(panel):
		if not control is Button or control.text.is_empty():
			continue
		var font := control.get_theme_font("font")
		var style := control.get_theme_stylebox("normal")
		var available := control.size.x-style.get_content_margin(SIDE_LEFT)-style.get_content_margin(SIDE_RIGHT)
		if font.get_string_size(control.text,HORIZONTAL_ALIGNMENT_LEFT,-1,control.get_theme_font_size("font_size")).x>available+1.0:
			return false
	for entry: Dictionary in CharacterCatalog.CHARACTERS:
		var id := str(entry.id)
		if UiArt.MENU_FONT.get_string_size(CharacterCatalog.selection_title(id),HORIZONTAL_ALIGNMENT_LEFT,-1,30).x>panel.DETAIL_RECT.size.x:
			return false
		if UiArt.wrap_text(CharacterCatalog.selection_detail(id),panel.DETAIL_RECT.size.x,15).size()>2:
			return false
		if not CharacterCatalog.is_unlocked(id):
			if UiArt.FONT.get_string_size(CharacterCatalog.unlock_hint(id),HORIZONTAL_ALIGNMENT_LEFT,-1,15).x>panel.DETAIL_RECT.size.x:
				return false
		elif entry.has("special") and UiArt.wrap_text(str(entry.special),panel.DETAIL_RECT.size.x,13).size()>2:
			return false
		if UiArt.FONT.get_string_size(panel._selection_caption(id),HORIZONTAL_ALIGNMENT_LEFT,-1,13).x>panel.DETAIL_RECT.size.x:
			return false
	return true

func _new_game() -> void:
	Roster._loaded = true
	Roster.unlocked.clear()
	game = load("res://scenes/main.tscn").instantiate()
	view = SubViewport.new()
	view.size = Vector2i(1280,720)
	view.world_2d = World2D.new()
	view.process_mode = Node.PROCESS_MODE_ALWAYS
	view.gui_embed_subwindows = true
	root.add_child(view)
	view.add_child(game)
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	await frames(5)

func _fresh_focus() -> void:
	game.selected_characters.assign(["ivo","branko","mara","nora"])
	game.hud._open_character_selection(1)
	await frames()
	var panel: CharacterSelectPanel = game.hud.character_panel
	check(panel.cards[2].has_focus() and panel.preview_character_id=="ivo","Fresh Solo selection focuses the actual saved Ivo instead of the first catalog row")
	check(panel.player_count==1 and panel.count_buttons.all(func(button: Button): return not button.visible) and focused_inside(panel),"Actual Solo setup has one crew slot and no cooperative count controls")
	await joy(JOY_BUTTON_B)
	check(game.hud.overlay=="menu" and not game.started,"Fresh Solo returns to the menu without starting or changing the saved identity")
	game.selected_characters.assign(PartyConfig.DEFAULT_CHARACTERS)

func _friends_roundtrip(panel: CharacterSelectPanel,label: String) -> CharacterSelectPanel:
	var selected: Array = game.selected_characters.duplicate()
	var scenario: Dictionary = game.hud.scenario_options.duplicate(true)
	var count := panel.player_count
	var slot := panel.active_slot
	var preview := panel.preview_character_id
	var scroll := panel.card_scroll.scroll_vertical
	var focused := view.gui_get_focus_owner()
	var row := panel.cards.find(focused) if focused is Button else -1
	var began := focused==panel.begin_button
	var scrollbar := focused==panel.card_scroll.get_v_scroll_bar()
	await key(KEY_F7)
	check(game.hud.overlay=="friends" and not game.started,label+": native F7 opens friends without constructing the world")
	await joy(JOY_BUTTON_B)
	var restored: CharacterSelectPanel = game.hud.character_panel
	if restored.preview_character_id!=preview or restored.card_scroll.scroll_vertical!=scroll:
		print("FRIENDS STATE ",label," before=",[preview,scroll]," after=",[restored.preview_character_id,restored.card_scroll.scroll_vertical])
	check(game.hud.overlay=="characters" and is_instance_valid(restored) and paused and not game.started,label+": native B returns to the actual paused character setup")
	check(restored.player_count==count and restored.active_slot==slot and game.selected_characters==selected and game.hud.scenario_options==scenario,label+": friend roundtrip preserves party size, active player, identities and scenario")
	check(restored.preview_character_id==preview and restored.card_scroll.scroll_vertical==scroll,label+": friend roundtrip restores the exact inspected preview and native list scroll")
	var focus_restored: bool = restored.cards.find(view.gui_get_focus_owner())==row if row>=0 else restored.begin_button.has_focus() if began else restored.card_scroll.get_v_scroll_bar().has_focus() if scrollbar else false
	check(focus_restored and focused_inside(restored),label+": friend roundtrip restores the real inspected control focus")
	check(not game.network.active and not game.microphone.capturing and game.players.is_empty(),label+": native friends navigation starts no transport, microphone or actors")
	return restored

func _selection(locale: String,resolution: Vector2i) -> void:
	view.size = resolution
	LocaleText.set_locale(locale,false)
	game.hud._open_character_selection(4)
	await frames()
	var panel: CharacterSelectPanel = game.hud.character_panel
	var label := "%s %dx%d"%[locale,resolution.x,resolution.y]
	check(panel.cards.size()==8 and panel.slot_buttons.size()==4 and panel.count_buttons.size()==3,label+": all actual identities and party controls are present")
	check(is_instance_valid(panel._landscape.get("preview")),label+": real menu landscape uses the same presentation service as options and lobby")
	check(panel.cards.all(func(button: Button): return button.get_theme_stylebox("normal").bg_color.a==0.0),label+": every native selection row uses shared transparent actions")
	check(_text_fits(panel),label+": actual localized button labels fit their authored widths")
	var selected: Array = game.selected_characters.duplicate()
	panel.select_slot(3)
	panel.cards[2].grab_focus()
	await frames()
	panel = await _friends_roundtrip(panel,label+" P4 Ivo")
	panel.cards[0].grab_focus()
	await frames()
	for index in range(1,8):
		await joy(JOY_BUTTON_DPAD_DOWN)
		check(panel.cards[index].has_focus(),label+": D-pad visits vertical character row "+str(index+1))
		check(panel.card_scroll.get_global_rect().grow(.5).encloses(panel.cards[index].get_global_rect()),label+": focused row "+str(index+1)+" is fully revealed")
		check(panel.preview_character_id==CharacterCatalog.CHARACTERS[index].id and game.selected_characters==selected,label+": browsing previews row "+str(index+1)+" without silently changing the party")
	check(panel.card_scroll.scroll_vertical>0,label+": reaching Rika scrolls the real eight-row list")
	check(not panel.cards[-1].tooltip_text.to_lower().contains("rika"),label+": locked Rika stays anonymous in the accessible description")
	panel = await _friends_roundtrip(panel,label+" P4 locked last row")
	panel.cards[-1].pressed.connect(func(): presses += 1)
	var before_presses := presses
	await joy(JOY_BUTTON_A)
	check(presses==before_presses+1 and game.selected_characters==selected,label+": one native A emits one locked-row action and preserves the selected identity")
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(panel.begin_button.has_focus(),label+": Down from the last character reaches Begin")
	panel = await _friends_roundtrip(panel,label+" Begin from scrolled last row")
	await joy(JOY_BUTTON_DPAD_LEFT)
	check(panel.back_button.has_focus(),label+": Left reaches Back without beginning a round")
	panel.cards[-1].grab_focus()
	panel.select_slot(2)
	await frames()
	check(panel.active_slot==2 and panel.preview_character_id==game.selected_characters[2],label+": changing slots restores the actual third identity after a scrolled locked preview")
	panel.slot_buttons[3].grab_focus()
	panel.select_slot(3)
	panel.set_player_count(2)
	await frames()
	check(panel.active_slot==1 and panel.player_count==2 and focused_inside(panel),label+": four-to-two party change repairs focus from the retired fourth slot")
	check(not panel.slot_buttons[2].visible and not panel.slot_buttons[3].visible,label+": hidden party slots remain outside visible input ownership")
	panel.count_buttons[1].grab_focus()
	await joy(JOY_BUTTON_A)
	check(panel.player_count==3 and focused_inside(panel),label+": native controller selection expands to three players with valid focus")
	panel.count_buttons[2].grab_focus()
	await key(KEY_ENTER)
	check(panel.player_count==4 and focused_inside(panel),label+": native Enter expands to four players with valid focus")
	panel.slot_buttons[3].grab_focus()
	panel.select_slot(3)
	await move_mouse(mouse_center(panel.count_buttons[0]))
	await mouse_button(mouse_center(panel.count_buttons[0]))
	check(panel.player_count==2 and panel.active_slot==1 and focused_inside(panel),label+": native count-button click shrinks four to two and repairs its now-disabled focus")
	panel.count_buttons[2].grab_focus()
	await key(KEY_ENTER)
	await tab_cycle(panel,label)
	panel.select_slot(3)
	panel.cards[2].grab_focus()
	before_presses = presses
	panel.cards[2].pressed.connect(func(): presses += 1)
	await key(KEY_ENTER)
	check(presses==before_presses+1 and game.selected_characters==["mara","branko","nora","ivo"],label+": one Enter swaps the third teammate into the fourth slot exactly once")
	panel.select_slot(0)
	panel.cards[0].grab_focus()
	panel._reveal_card(panel.cards[0])
	await frames()
	selected = game.selected_characters.duplicate()
	await move_mouse(mouse_center(panel.cards[1]))
	check(panel.preview_character_id=="branko" and game.selected_characters==selected,label+": native hover previews Branko without selecting or swapping")
	panel.cards[1].pressed.connect(func(): presses += 1)
	before_presses = presses
	await mouse_button(mouse_center(panel.cards[1]))
	check(presses==before_presses+1 and game.selected_characters==["branko","mara","nora","ivo"],label+": one native mouse click performs exactly one teammate swap")
	await move_mouse(mouse_center(panel.card_scroll))
	var initial_scroll := panel.card_scroll.scroll_vertical
	for unused in 4:
		await mouse_button(mouse_center(panel.card_scroll),MOUSE_BUTTON_WHEEL_DOWN)
	check(panel.card_scroll.scroll_vertical>initial_scroll and game.selected_characters==["branko","mara","nora","ivo"],label+": native mouse wheel scrolls choices without selecting a different crew member")
	panel.card_scroll.get_v_scroll_bar().grab_focus()
	await frames()
	panel = await _friends_roundtrip(panel,label+" Native scrollbar")
	check(Roster.unlock("rika"),label+": the real local rescue entitlement enables Rika")
	panel.refresh_locale()
	panel.cards[-1].grab_focus()
	panel._reveal_card(panel.cards[-1])
	await frames()
	panel.cards[-1].pressed.connect(func(): presses += 1)
	before_presses = presses
	await joy(JOY_BUTTON_A)
	check(presses==before_presses+1 and game.selected_characters[0]=="rika" and panel.preview_character_id=="rika",label+": one native A selects the newly rescued eighth character")
	check(_text_fits(panel),label+": rescued-row and selected-slot labels still fit in both languages")
	panel.cards[0].grab_focus()
	for shortcut: Key in [KEY_F4,KEY_T,KEY_P,KEY_F1,KEY_F2]:
		await key(shortcut)
		check(game.hud.overlay=="characters" and not game.started,label+": modal selection remains owned after shortcut "+str(shortcut))
	await joy(JOY_BUTTON_B)
	check(game.hud.overlay=="menu" and not game.started,label+": native B returns to the original main menu without starting")
	await frames()
	game.selected_characters.assign(PartyConfig.DEFAULT_CHARACTERS)
	Roster.unlocked.clear()

func _back_and_start() -> void:
	game.hud._open_scenario_selection(2)
	await frames()
	game.hud.scenario_panel.confirm()
	await frames()
	check(game.hud.overlay=="characters","Actual scenario confirmation enters the character modal")
	await key(KEY_ESCAPE)
	check(game.hud.overlay=="scenario" and not game.started,"Native Escape restores the actual scenario selection")
	game.hud.scenario_panel.classic_button.pressed.emit()
	await frames()
	check(game.hud.overlay=="characters" and not game.hud.scenario_selected,"Classic bunker also enters the actual character modal")
	await joy(JOY_BUTTON_B)
	check(game.hud.overlay=="scenario" and not game.started,"Classic bunker returns to the originating scenario screen on B")
	game.hud.scenario_panel.confirm()
	await frames()
	var panel: CharacterSelectPanel = game.hud.character_panel
	panel.set_player_count(4)
	panel.select_slot(3)
	panel.cards[2].grab_focus()
	await joy(JOY_BUTTON_A)
	var choices: Array = game.selected_characters.duplicate()
	panel.begin_button.grab_focus()
	await key(KEY_ENTER)
	await frames(5)
	check(game.started and game.players.size()==4 and not paused,"Native Begin starts four actual local workers and releases menu pause")
	var actual: Array[String] = []
	for worker: Worker in game.players:
		actual.append(worker.character_id)
		worker.set_physics_process(false)
	check(actual==choices and actual==PartyConfig.unique_characters(actual),"Spawned actor identities exactly match the native selection with no duplicate character")
	game.rounds.running = false
	game.rounds.set_process(false)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	AudioServer.set_bus_mute(0,true)
	Roster.persistence_enabled = false
	await _new_game()
	await _fresh_focus()
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(960,600)]:
		for locale: String in ["de","en"]:
			await _selection(locale,resolution)
	LocaleText.set_locale("de",false)
	await _back_and_start()
	check(await Cleanup.free_scene(game,self),"Real character selection, actors, menu previews and native audio retire with the scene")
	view.queue_free()
	await frames()
	print("CHARACTER SELECTION PRESENTATION: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
