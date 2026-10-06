extends Control
## A local field manual over the same landscape or paused world. Reading,
## navigation and advice never issue gameplay requests or write a profile.
const L := preload("res://scripts/locale_text.gd")
const Catalog := preload("res://scripts/help_manual_catalog.gd")
const READER_RECT := Rect2(456,222,904,542)
var game: Node
var hud: Node
var page_id := "first_shift"
var page_buttons: Array[Button] = []
var options_button: Button
var back_button: Button
var context_button: Button
var tutorial_content: VBoxContainer
var tutorial_status: Label
var tutorial_actions: HBoxContainer
var tutorial_start_button: Button
var tutorial_stop_button: Button
var tutorial_restart_button: Button
var reading_scroll: ScrollContainer
var reading_content: VBoxContainer
var section_content: VBoxContainer
var advice_heading: Label
var advice_body: Label
var decoration: Control
var _landscape: Dictionary = {}
var _scroll_positions: Dictionary = {}
var _advice: Dictionary = {}
var _restore_revision := 0
var _refresh_clock := 0.0
var _focus_id := ""

func _ready() -> void:
	name = "HelpManualPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = Vector2(1440,900)
	var saved: Dictionary = hud.help_navigation
	page_id = str(saved.get("page","first_shift"))
	if not _page_ids().has(page_id): page_id = "first_shift"
	var saved_scroll: Variant = saved.get("scroll",{})
	if saved_scroll is Dictionary: _scroll_positions = saved_scroll.duplicate()
	_focus_id = str(saved.get("focus","page:"+page_id))
	if not bool(game.get("started")):
		var environment := str(hud._main_menu_navigation.get("environment",hud.scenario_options.get("environment","ash_foundry")))
		_landscape = SocialUiArt.create_landscape(self,game,hud,environment)
	decoration = Control.new()
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decoration.draw.connect(_draw_foreground)
	add_child(decoration)
	for index in Catalog.PAGES.size():
		var id := str(Catalog.PAGES[index].id)
		var button := _button(str(Catalog.PAGES[index].title),Rect2(80,224+index*60,318,49),select_page.bind(id))
		SocialUiArt.button(button,24,"",0)
		button.name = "Page_"+id
		button.toggle_mode = true
		button.gui_input.connect(_page_input.bind(index))
		page_buttons.append(button)
	reading_scroll = ScrollContainer.new()
	reading_scroll.name = "ReadingArea"
	reading_scroll.position = READER_RECT.position
	reading_scroll.size = READER_RECT.size
	reading_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	reading_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	reading_scroll.focus_mode = Control.FOCUS_ALL
	reading_scroll.follow_focus = false
	reading_scroll.gui_input.connect(_reader_input)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_width_left = 2
	focus.border_color = Color(UiArt.AMBER,.65)
	reading_scroll.add_theme_stylebox_override("focus",focus)
	add_child(reading_scroll)
	reading_content = VBoxContainer.new()
	reading_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reading_content.add_theme_constant_override("separation",14)
	reading_scroll.add_child(reading_content)
	advice_heading = _label("",22,UiArt.AMBER)
	advice_heading.name = "CurrentAdviceTitle"
	reading_content.add_child(advice_heading)
	advice_body = _label("",18,UiArt.IVORY)
	advice_body.name = "CurrentAdviceBody"
	reading_content.add_child(advice_body)
	context_button = _button("Mehr dazu",Rect2(),_open_advice,reading_content)
	context_button.name = "AdviceLink"
	context_button.custom_minimum_size = Vector2(0,36)
	SocialUiArt.button(context_button,17,"",0)
	tutorial_content = VBoxContainer.new()
	tutorial_content.name = "SoloTutorialControls"
	tutorial_content.add_theme_constant_override("separation",10)
	tutorial_content.add_child(_label(L.text("Solo-Tutorial"),22,UiArt.IVORY))
	tutorial_status = _label("",18,UiArt.MUTED)
	tutorial_status.name = "TutorialStatus"
	tutorial_content.add_child(tutorial_status)
	tutorial_actions = HBoxContainer.new()
	tutorial_actions.add_theme_constant_override("separation",12)
	tutorial_content.add_child(tutorial_actions)
	tutorial_start_button = _button("Tutorial starten",Rect2(),_tutorial_action.bind("start"),tutorial_actions)
	tutorial_stop_button = _button("Tutorial beenden",Rect2(),_tutorial_action.bind("stop"),tutorial_actions)
	tutorial_restart_button = _button("Tutorial wiederholen",Rect2(),_tutorial_action.bind("restart"),tutorial_actions)
	for button: Button in [tutorial_start_button,tutorial_stop_button,tutorial_restart_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0,43)
		SocialUiArt.button(button,17,"",0)
	tutorial_start_button.name = "TutorialStart"
	tutorial_stop_button.name = "TutorialStop"
	tutorial_restart_button.name = "TutorialRestart"
	reading_content.add_child(tutorial_content)
	section_content = VBoxContainer.new()
	section_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_content.add_theme_constant_override("separation",26)
	reading_content.add_child(section_content)
	var scrollbar := reading_scroll.get_v_scroll_bar()
	scrollbar.focus_mode = Control.FOCUS_ALL
	scrollbar.gui_input.connect(_reader_input)
	scrollbar.value_changed.connect(_scroll_changed)
	options_button = _button("Optionen · F4",Rect2(80,690,318,43),hud._toggle_audio)
	SocialUiArt.button(options_button,18,"",0)
	options_button.name = "Options"
	back_button = _button("Zurück · Esc / F1",Rect2(80,756,318,48),hud._close_help)
	SocialUiArt.button(back_button,20,"back",0)
	back_button.name = "Back"
	get_viewport().size_changed.connect(_layout)
	get_viewport().gui_focus_changed.connect(_focus_changed)
	_rebuild_content()
	_layout()
	_restore_focus.call_deferred()

func _page_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry: Dictionary in Catalog.PAGES: ids.append(str(entry.id))
	return ids

func _page_index() -> int:
	return maxi(0,_page_ids().find(page_id))

func _button(title: String,rect: Rect2,callback: Callable,parent: Node=self) -> Button:
	var button := Button.new()
	button.text = L.text(title)
	button.position = rect.position
	button.size = rect.size
	SocialUiArt.button(button,18,"",0)
	button.pressed.connect(callback)
	parent.add_child(button)
	hud.buttons.append(button)
	return button

func _label(message: String,font_size: int,color: Color) -> Label:
	var label := Label.new()
	label.text = message
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_override("font",UiArt.MENU_FONT if font_size>=22 else UiArt.FONT)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.add_theme_constant_override("line_spacing",5)
	return label

func select_page(id: String) -> void:
	if not _page_ids().has(id): return
	if id==page_id:
		page_buttons[_page_index()].set_pressed_no_signal(true)
		return
	_scroll_positions[page_id] = reading_scroll.scroll_vertical
	page_id = id
	_rebuild_content()
	remember_navigation()

func _page_input(event: InputEvent,index: int) -> void:
	if not event.is_pressed(): return
	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		var next := index+(-1 if event.is_action_pressed("ui_up") else 1)
		if next<0: back_button.grab_focus()
		elif next>=page_buttons.size(): options_button.grab_focus()
		else:
			select_page(str(Catalog.PAGES[next].id))
			page_buttons[next].grab_focus()
		accept_event()
	elif event.is_action_pressed("ui_right"):
		select_page(str(Catalog.PAGES[index].id))
		reading_scroll.grab_focus()
		accept_event()

func _rebuild_content() -> void:
	for child in section_content.get_children():
		section_content.remove_child(child)
		child.queue_free()
	_advice = Catalog.current_advice(game)
	_refresh_advice()
	_refresh_tutorial_controls()
	if page_id=="controls": _build_controls()
	for section: Dictionary in Catalog.sections(page_id,game):
		var block := VBoxContainer.new()
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		block.add_theme_constant_override("separation",10)
		block.add_child(_label(str(section.title),22,UiArt.IVORY))
		block.add_child(_label(str(section.body),18,UiArt.MUTED))
		section_content.add_child(block)
	for index in page_buttons.size():
		page_buttons[index].text = L.text(str(Catalog.PAGES[index].title))
		page_buttons[index].tooltip_text = L.text(str(Catalog.PAGES[index].detail))
		page_buttons[index].set_pressed_no_signal(str(Catalog.PAGES[index].id)==page_id)
		page_buttons[index].add_theme_color_override("font_color",UiArt.AMBER if str(Catalog.PAGES[index].id)==page_id else UiArt.IVORY)
	options_button.text = L.text("Optionen · F4")
	back_button.text = L.text("Zurück · Esc / F1")
	_restore_revision += 1
	_restore_scroll(_restore_revision,maxi(0,int(_scroll_positions.get(page_id,0))))
	_wire_focus()
	decoration.queue_redraw()

func _build_controls() -> void:
	var rows: Array[Dictionary] = Catalog.controls(game)
	var online := is_instance_valid(game.get("network")) and bool(game.network.active)
	var headers := [L.text("Aktion"),L.text("Deine Tasten" if online else "Spieler 1"),L.text("Partner · eigener Rechner" if online else "Spieler 2 · Tastatur / Pad")]
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation",18)
	for index in headers.size(): heading.add_child(_control_cell(str(headers[index]),index,UiArt.AMBER))
	section_content.add_child(heading)
	for row: Dictionary in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation",18)
		for index in 3:
			var field: String = ["action","primary","secondary"][index]
			line.add_child(_control_cell(str(row.get(field,"")),index,UiArt.IVORY if index>0 else UiArt.MUTED))
		section_content.add_child(line)

func _control_cell(message: String,index: int,color: Color) -> Label:
	var cell := _label(message,18,color)
	cell.size_flags_stretch_ratio = 1.0 if index<2 else 1.18
	return cell

func _refresh_advice() -> void:
	var show_advice := page_id=="first_shift" and not _advice.is_empty()
	var link_had_focus := context_button.has_focus()
	advice_heading.visible = show_advice
	advice_body.visible = show_advice
	context_button.visible = show_advice and _page_ids().has(str(_advice.get("page",""))) and str(_advice.get("page",""))!=page_id
	advice_heading.text = str(_advice.get("title",""))
	advice_body.text = str(_advice.get("body",""))
	context_button.text = L.text("Mehr dazu")+"  →"
	if link_had_focus and not context_button.visible: reading_scroll.grab_focus()

func _open_advice() -> void:
	var target := str(_advice.get("page",""))
	if not _page_ids().has(target): return
	select_page(target)
	page_buttons[_page_index()].grab_focus()

func _tutorial_controller() -> Node:
	return game.solo_tutorial if is_instance_valid(game) and "solo_tutorial" in game and is_instance_valid(game.solo_tutorial) else null

func _refresh_tutorial_controls() -> void:
	var previous_focus := get_viewport().gui_get_focus_owner()
	tutorial_content.visible = page_id=="first_shift"
	var guide := _tutorial_controller()
	var available: bool = is_instance_valid(guide) and guide.is_available()
	var view: Dictionary = guide.get_view() if is_instance_valid(guide) else {}
	var enabled := bool(view.get("enabled",false))
	var completed := bool(view.get("completed",false))
	var learned := int(view.get("learned_count",0))
	tutorial_content.get_child(0).text = L.text("Solo-Tutorial")
	tutorial_start_button.text = L.text("Tutorial fortsetzen" if learned>0 else "Tutorial starten")
	tutorial_stop_button.text = L.text("Tutorial beenden")
	tutorial_restart_button.text = L.text("Tutorial wiederholen")
	tutorial_start_button.disabled = not available or enabled or completed
	tutorial_stop_button.disabled = not available or not enabled
	tutorial_restart_button.disabled = not available or (learned==0 and not completed)
	for button: Button in [tutorial_start_button,tutorial_stop_button,tutorial_restart_button]:
		button.focus_mode = Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL
	if not available:
		tutorial_status.text = L.text("Die geführte Anleitung ist in einer laufenden Solo-Schicht verfügbar. Im Koop bleibt das Handbuch für alle geöffnet.")
	elif completed:
		tutorial_status.text = L.text("Tutorial abgeschlossen. Du kannst die Hinweise erneut durchgehen; deine Schicht bleibt unverändert.")
	elif enabled:
		tutorial_status.text = L.format("Begleitung aktiv · %d / %d gelernt. Die Hinweise passen sich deinen tatsächlichen Aktionen an.",[learned,int(view.get("count",0))])
	else:
		tutorial_status.text = L.text("Begleitung ausgeschaltet. Fortsetzen erhält gelernte Schritte; Wiederholen beginnt nur die Anleitung von vorn.")
	for button: Button in [tutorial_start_button,tutorial_stop_button,tutorial_restart_button]:
		if previous_focus==button and (button.disabled or not tutorial_content.visible): reading_scroll.grab_focus()

func _tutorial_action(action: String) -> void:
	var guide := _tutorial_controller()
	if not is_instance_valid(guide) or not guide.is_available(): return
	# Enter/A can also be jump/interact. Quarantine held gameplay actions before
	# the reader is closed, then leave the player in this paused native menu.
	preload("res://scripts/network_input.gd").quarantine_menu_inputs(game)
	match action:
		"start": guide.set_enabled(true)
		"stop": guide.stop()
		"restart": guide.restart()
	var save_error := str(guide.records.last_error)
	if not save_error.is_empty(): game.notify(L.text(save_error))
	_refresh_tutorial_controls()
	_wire_focus()

func _reading_actions() -> Array[Control]:
	var controls: Array[Control] = []
	if context_button.visible: controls.append(context_button)
	if tutorial_content.visible:
		for button: Button in [tutorial_start_button,tutorial_stop_button,tutorial_restart_button]:
			if not button.disabled: controls.append(button)
	return controls

func _restore_scroll(revision: int,value: int) -> void:
	# Native containers need their translated label widths before scroll extents
	# are available. An older page refresh must not move the newly selected page.
	await get_tree().process_frame
	await get_tree().process_frame
	if is_queued_for_deletion() or revision!=_restore_revision: return
	reading_scroll.scroll_vertical = value
	_wire_focus()

func _scroll_changed(_value: float) -> void:
	_scroll_positions[page_id] = reading_scroll.scroll_vertical
	remember_navigation()

func _visible_controls() -> Array[Control]:
	var controls: Array[Control] = []
	controls.append_array(page_buttons)
	controls.append(reading_scroll)
	controls.append_array(_reading_actions())
	var scrollbar := reading_scroll.get_v_scroll_bar()
	if scrollbar.visible: controls.append(scrollbar)
	controls.append(options_button)
	controls.append(back_button)
	return controls

func _wire_focus() -> void:
	var controls := _visible_controls()
	for index in controls.size():
		var control := controls[index]
		control.focus_next = control.get_path_to(controls[(index+1)%controls.size()])
		control.focus_previous = control.get_path_to(controls[posmod(index-1,controls.size())])
	var navigation: Array[Control] = []
	navigation.append_array(page_buttons)
	navigation.append(options_button)
	navigation.append(back_button)
	for index in navigation.size():
		var control := navigation[index]
		control.focus_neighbor_top = control.get_path_to(navigation[posmod(index-1,navigation.size())])
		control.focus_neighbor_bottom = control.get_path_to(navigation[(index+1)%navigation.size()])
		control.focus_neighbor_left = NodePath(".")
		control.focus_neighbor_right = control.get_path_to(reading_scroll)
	var reading_actions := _reading_actions()
	var readers: Array[Control] = [reading_scroll,reading_scroll.get_v_scroll_bar()]
	readers.append_array(reading_actions)
	for control: Control in readers:
		control.focus_neighbor_left = control.get_path_to(page_buttons[_page_index()])
		control.focus_neighbor_right = control.get_path_to(options_button)
	reading_scroll.focus_neighbor_top = reading_scroll.get_path_to(page_buttons[_page_index()])
	reading_scroll.focus_neighbor_bottom = reading_scroll.get_path_to(reading_actions[0] if not reading_actions.is_empty() else options_button)
	for index in reading_actions.size():
		var control := reading_actions[index]
		control.focus_neighbor_top = control.get_path_to(reading_actions[index-1] if index>0 else reading_scroll)
		control.focus_neighbor_bottom = control.get_path_to(reading_actions[index+1] if index+1<reading_actions.size() else options_button)

func _reader_input(event: InputEvent) -> void:
	if not event.is_pressed(): return
	var handled := true
	if event.is_action_pressed("ui_up"):
		if reading_scroll.scroll_vertical<=0: page_buttons[_page_index()].grab_focus()
		else: reading_scroll.scroll_vertical -= 40
	elif event.is_action_pressed("ui_down"):
		var bar := reading_scroll.get_v_scroll_bar()
		if reading_scroll.scroll_vertical>=maxi(0,roundi(bar.max_value-bar.page)-1):
			var actions := _reading_actions()
			(actions[0] if not actions.is_empty() else options_button).grab_focus()
		else: reading_scroll.scroll_vertical += 40
	elif event.is_action_pressed("ui_left"): page_buttons[_page_index()].grab_focus()
	elif event.is_action_pressed("ui_right"): options_button.grab_focus()
	elif event is InputEventKey and event.keycode==KEY_PAGEUP: reading_scroll.scroll_vertical -= roundi(READER_RECT.size.y*.8)
	elif event is InputEventKey and event.keycode==KEY_PAGEDOWN: reading_scroll.scroll_vertical += roundi(READER_RECT.size.y*.8)
	elif event is InputEventKey and event.keycode==KEY_HOME: reading_scroll.scroll_vertical = 0
	elif event is InputEventKey and event.keycode==KEY_END: reading_scroll.scroll_vertical = roundi(reading_scroll.get_v_scroll_bar().max_value)
	else: handled = false
	if handled: reading_scroll.accept_event()

func _focus_changed(control: Control) -> void:
	if not is_instance_valid(control) or not is_ancestor_of(control): return
	if control is Button and control in page_buttons: _focus_id = "page:"+str(Catalog.PAGES[page_buttons.find(control)].id)
	elif control==reading_scroll: _focus_id = "reader"
	elif control==reading_scroll.get_v_scroll_bar(): _focus_id = "scrollbar"
	elif control==context_button:
		_focus_id = "context"
		reading_scroll.ensure_control_visible(context_button)
	elif control in [tutorial_start_button,tutorial_stop_button,tutorial_restart_button]:
		_focus_id = "tutorial:"+control.name
		reading_scroll.ensure_control_visible(control)
	elif control==options_button: _focus_id = "options"
	elif control==back_button: _focus_id = "back"
	remember_navigation()

func _restore_focus() -> void:
	var target: Control = page_buttons[_page_index()]
	if _focus_id.begins_with("page:") and _page_ids().has(_focus_id.trim_prefix("page:")): target = page_buttons[_page_ids().find(_focus_id.trim_prefix("page:"))]
	elif _focus_id=="reader": target = reading_scroll
	elif _focus_id=="scrollbar" and reading_scroll.get_v_scroll_bar().visible: target = reading_scroll.get_v_scroll_bar()
	elif _focus_id=="context" and context_button.visible: target = context_button
	elif _focus_id.begins_with("tutorial:"):
		for button: Button in [tutorial_start_button,tutorial_stop_button,tutorial_restart_button]:
			if button.name==_focus_id.trim_prefix("tutorial:") and tutorial_content.visible and not button.disabled: target = button
	elif _focus_id=="options": target = options_button
	elif _focus_id=="back": target = back_button
	if is_instance_valid(target): target.grab_focus()

func capture_navigation() -> Dictionary:
	if is_instance_valid(reading_scroll): _scroll_positions[page_id] = reading_scroll.scroll_vertical
	return {"page":page_id,"scroll":_scroll_positions.duplicate(),"focus":_focus_id}

func navigation_state() -> Dictionary:
	return capture_navigation()

func remember_navigation() -> void:
	if is_instance_valid(hud): hud.help_navigation = capture_navigation()

func _layout() -> void:
	SocialUiArt.layout_landscape(_landscape,hud)
	decoration.queue_redraw()

func _process(delta: float) -> void:
	_refresh_clock += delta
	if _refresh_clock<.25: return
	_refresh_clock = 0.0
	_refresh_tutorial_controls()
	_wire_focus()
	var next := Catalog.current_advice(game)
	if next==_advice: return
	_advice = next
	_refresh_advice()
	_wire_focus()

func _exit_tree() -> void:
	remember_navigation()

func refresh_locale() -> void:
	_scroll_positions[page_id] = reading_scroll.scroll_vertical
	_rebuild_content()
	remember_navigation()

func _draw_foreground() -> void:
	var screen: Rect2 = hud.screen_rect()
	SocialUiArt.reading_shade(decoration,screen,410,600)
	decoration.draw_rect(Rect2(432,192,952,604),Color(.024,.040,.044,.54))
	UiArt.text(decoration,Vector2(80,111),"Feldhandbuch",36,UiArt.IVORY,UiArt.MENU_FONT)
	UiArt.text(decoration,Vector2(82,151),"Deine Crew. Dein Bunker. Der nächste Schritt.",17,UiArt.MUTED)
	var entry: Dictionary = Catalog.PAGES[_page_index()]
	UiArt.text(decoration,Vector2(456,196),str(entry.title),25,UiArt.IVORY,UiArt.MENU_FONT)
	UiArt.divider(decoration,Vector2(80,663),Vector2(398,663))
	UiArt.text(decoration,Vector2(80,847),"Pfeile / Steuerkreuz wählen · Rechts lesen · Esc zurück",14,UiArt.MUTED)
	UiArt.text(decoration,Vector2(456,804),"Mausrad / oben unten: scrollen · Tab: nächstes Element",13,UiArt.MUTED)
