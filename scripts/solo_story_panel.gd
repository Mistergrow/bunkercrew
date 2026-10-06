extends Control
## Native story reading over the current place. Browsing never advances a
## mission; the separate recruitment button owns the only campaign action.
const L := preload("res://scripts/locale_text.gd")
const Portraits := preload("res://scripts/character_select_panel.gd")
const JOURNAL_RECT := Rect2(80,238,328,488)
const READER_RECT := Rect2(464,238,896,500)
var game: Node
var hud: Node
var mode := "journal"
var encounter_id := ""
var selected_site := ""
var site_buttons: Array[Button] = []
var journal_scroll: ScrollContainer
var journal_content: VBoxContainer
var reading_scroll: ScrollContainer
var reading_content: VBoxContainer
var close_button: Button
var recruit_button: Button
var decoration: Control
var _entries: Array[Dictionary] = []
var _encounter: Dictionary = {}
var _objective: Dictionary = {}
var _landscape: Dictionary = {}
var _scroll_positions: Dictionary = {}
var _restore_revision := 0
var _elapsed := 0.0
var _focus_id := ""
var _target_entry := ""

func _ready() -> void:
	name = "SoloStoryPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = Vector2(1440,900)
	if not bool(game.get("started")):
		var environment := str(hud._main_menu_navigation.get("environment","ash_foundry"))
		_landscape = SocialUiArt.create_landscape(self,game,hud,environment)
	decoration = Control.new()
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decoration.draw.connect(_draw_foreground)
	add_child(decoration)
	journal_scroll = _scroll(JOURNAL_RECT,"Places")
	journal_content = VBoxContainer.new()
	journal_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	journal_content.add_theme_constant_override("separation",7)
	journal_scroll.add_child(journal_content)
	reading_scroll = _scroll(READER_RECT,"StoryReader")
	reading_content = VBoxContainer.new()
	reading_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reading_content.add_theme_constant_override("separation",24)
	reading_scroll.add_child(reading_content)
	for container: ScrollContainer in [journal_scroll,reading_scroll]:
		container.gui_input.connect(_reader_input.bind(container))
		container.get_v_scroll_bar().gui_input.connect(_reader_input.bind(container))
	close_button = _button("Schließen · Esc / B",Rect2(80,780,328,46),_close)
	SocialUiArt.button(close_button,20,"back",0)
	close_button.name = "Close"
	recruit_button = _button("Crew aufnehmen",Rect2(980,780,380,46),_recruit)
	SocialUiArt.button(recruit_button,22,"",0)
	recruit_button.name = "Recruit"
	get_viewport().size_changed.connect(_layout)
	get_viewport().gui_focus_changed.connect(_focus_changed)
	var saved: Dictionary = hud.solo_story_navigation
	_target_entry = str(saved.get("entry",""))
	selected_site = str(saved.get("site",""))
	var positions: Variant = saved.get("scroll",{})
	if positions is Dictionary: _scroll_positions = positions.duplicate()
	_focus_id = str(saved.get("focus","close" if mode=="encounter" else "")) if str(saved.get("mode",""))==mode else ""
	refresh_view()
	_restore_revision += 1
	_restore_scroll(_restore_revision,maxi(0,int(saved.get("list_scroll",0))),maxi(0,int(_scroll_positions.get(_reading_key(),0))))
	_layout()
	_restore_focus.call_deferred()

func _scroll(rect: Rect2,id: String) -> ScrollContainer:
	var container := ScrollContainer.new()
	container.name = id
	container.position = rect.position
	container.size = rect.size
	container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	container.focus_mode = Control.FOCUS_ALL
	container.follow_focus = false
	var outline := StyleBoxFlat.new()
	outline.draw_center = false
	outline.border_width_left = 2
	outline.border_color = Color(UiArt.AMBER,.65)
	container.add_theme_stylebox_override("focus",outline)
	add_child(container)
	container.get_v_scroll_bar().focus_mode = Control.FOCUS_ALL
	return container

func _button(title: String,rect: Rect2,callback: Callable,parent: Node=self) -> Button:
	var button := Button.new()
	button.text = L.text(title)
	button.position = rect.position
	button.size = rect.size
	SocialUiArt.button(button,19,"",0)
	button.pressed.connect(callback)
	parent.add_child(button)
	hud.buttons.append(button)
	return button

func _label(message: String,font_size: int,color: Color) -> Label:
	var label := Label.new()
	label.text = L.text(message)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_override("font",UiArt.MENU_FONT if font_size>=22 else UiArt.FONT)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.add_theme_constant_override("line_spacing",5)
	return label

func _section(title: String,body: String,color: Color=UiArt.IVORY) -> VBoxContainer:
	var block := VBoxContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_theme_constant_override("separation",10)
	if not title.is_empty(): block.add_child(_label(title,22,color))
	if not body.is_empty(): block.add_child(_label(body,18,UiArt.MUTED))
	reading_content.add_child(block)
	return block

func _close() -> void:
	hud._close_solo_story()

func _recruit() -> void:
	var controller := _controller()
	if not is_instance_valid(controller) or recruit_button.disabled or encounter_id.is_empty(): return
	controller.recruit(encounter_id)
	# Show the outcome in this conversation. Reading never dismisses the NPC;
	# only the player's Close action leaves the encounter.
	refresh_view()
	if recruit_button.disabled: close_button.grab_focus()

func _controller() -> Node:
	if not is_instance_valid(game) or not "solo_story" in game: return null
	var controller: Variant = game.get("solo_story")
	return controller if is_instance_valid(controller) else null

func refresh_view() -> void:
	var controller := _controller()
	if is_instance_valid(reading_scroll): _scroll_positions[_reading_key()] = reading_scroll.scroll_vertical
	_objective = controller.objective() if is_instance_valid(controller) else {}
	_encounter = controller.encounter_view() if is_instance_valid(controller) and mode=="encounter" else {}
	if not _encounter.is_empty(): encounter_id = str(_encounter.get("id",""))
	_entries.clear()
	if is_instance_valid(controller):
		for entry: Dictionary in controller.journal_entries(): _entries.append(entry)
	if selected_site.is_empty() or _entry(selected_site).is_empty():
		selected_site = str(_objective.get("site",""))
		if _entry(selected_site).is_empty(): selected_site = str(_entries[0].id) if not _entries.is_empty() else ""
	_rebuild_places()
	_rebuild_reading()
	recruit_button.visible = mode=="encounter" and not str(_encounter.get("character","")).is_empty()
	recruit_button.disabled = not bool(_encounter.get("can_recruit",false))
	recruit_button.tooltip_text = L.text(str(_encounter.get("reason","")))
	recruit_button.text = L.text("Crew aufnehmen")
	close_button.text = L.text("Schließen · Esc / B")
	journal_scroll.visible = mode=="journal"
	_wire_focus()
	decoration.queue_redraw()

func _entry(id: String) -> Dictionary:
	for entry: Dictionary in _entries:
		if str(entry.get("id",""))==id: return entry
	return {}

func _rebuild_places() -> void:
	var list_position := journal_scroll.scroll_vertical
	for child in journal_content.get_children():
		journal_content.remove_child(child)
		child.queue_free()
	for button: Button in site_buttons: hud.buttons.erase(button)
	site_buttons.clear()
	for index in _entries.size():
		var entry: Dictionary = _entries[index]
		var row := VBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation",2)
		journal_content.add_child(row)
		var button := _button(str(entry.get("title","")),Rect2(),select_site.bind(str(entry.id)),row)
		button.custom_minimum_size = Vector2(0,42)
		button.name = "Place_"+str(entry.id)
		button.gui_input.connect(_site_input.bind(index))
		button.focus_entered.connect(_site_focused.bind(button))
		button.add_theme_color_override("font_color",UiArt.AMBER if str(entry.id)==selected_site else UiArt.IVORY)
		button.tooltip_text = L.text(str(entry.get("summary","")))
		site_buttons.append(button)
		var status := _label(str(entry.get("status","")),14,UiArt.MUTED)
		row.add_child(status)
	_restore_revision += 1
	_restore_scroll(_restore_revision,list_position,maxi(0,int(_scroll_positions.get(_reading_key(),0))))

func _rebuild_reading() -> void:
	for child in reading_content.get_children():
		reading_content.remove_child(child)
		child.queue_free()
	if mode=="encounter":
		for paragraph: String in _encounter.get("paragraphs",[]): _section("",paragraph)
		var reason := str(_encounter.get("reason",""))
		if not reason.is_empty(): _section("Nächster Schritt",reason,UiArt.AMBER)
	else:
		if not _objective.is_empty(): _section("Aktueller Auftrag",str(_objective.get("body","")),UiArt.AMBER)
		var entry := _entry(selected_site)
		if not entry.is_empty():
			_section(str(entry.get("title","")),str(entry.get("summary","")))
			for detail: Dictionary in entry.get("details",[]):
				var block := _section(str(detail.get("title","")),str(detail.get("body","")))
				block.set_meta("entry_id",str(detail.get("id","")))
		else: _section("Noch keine Aufzeichnungen","Beginne die Solo-Geschichte, um Orte und Menschen zu entdecken.")
	_restore_revision += 1
	_restore_scroll(_restore_revision,journal_scroll.scroll_vertical,maxi(0,int(_scroll_positions.get(_reading_key(),0))))

func select_site(id: String) -> void:
	if _entry(id).is_empty() or id==selected_site: return
	_scroll_positions[_reading_key()] = reading_scroll.scroll_vertical
	selected_site = id
	for index in site_buttons.size(): site_buttons[index].add_theme_color_override("font_color",UiArt.AMBER if str(_entries[index].id)==id else UiArt.IVORY)
	_rebuild_reading()
	_wire_focus()
	remember_navigation()

func _reading_key() -> String:
	return "encounter:"+encounter_id if mode=="encounter" else selected_site

func _selected_button() -> Button:
	for index in _entries.size():
		if str(_entries[index].id)==selected_site: return site_buttons[index]
	return site_buttons[0] if not site_buttons.is_empty() else null

func _site_focused(button: Button) -> void:
	journal_scroll.ensure_control_visible(button)

func _site_input(event: InputEvent,index: int) -> void:
	if not event.is_pressed(): return
	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		var next := index+(-1 if event.is_action_pressed("ui_up") else 1)
		if next<0 or next>=site_buttons.size(): close_button.grab_focus()
		else:
			select_site(str(_entries[next].id))
			site_buttons[next].grab_focus()
		accept_event()
	elif event.is_action_pressed("ui_right"):
		select_site(str(_entries[index].id))
		reading_scroll.grab_focus()
		accept_event()

func _visible_controls() -> Array[Control]:
	var controls: Array[Control] = []
	if mode=="journal":
		controls.append_array(site_buttons)
		if journal_scroll.get_v_scroll_bar().visible: controls.append(journal_scroll.get_v_scroll_bar())
	controls.append(reading_scroll)
	if reading_scroll.get_v_scroll_bar().visible: controls.append(reading_scroll.get_v_scroll_bar())
	if recruit_button.visible and not recruit_button.disabled: controls.append(recruit_button)
	controls.append(close_button)
	return controls

func _wire_focus() -> void:
	var controls := _visible_controls()
	journal_scroll.focus_mode = Control.FOCUS_NONE
	for index in controls.size():
		var control := controls[index]
		control.focus_next = control.get_path_to(controls[(index+1)%controls.size()])
		control.focus_previous = control.get_path_to(controls[posmod(index-1,controls.size())])
	for index in site_buttons.size():
		var button := site_buttons[index]
		button.focus_neighbor_top = button.get_path_to(site_buttons[index-1] if index>0 else close_button)
		button.focus_neighbor_bottom = button.get_path_to(site_buttons[index+1] if index<site_buttons.size()-1 else close_button)
		button.focus_neighbor_right = button.get_path_to(reading_scroll)
		button.focus_neighbor_left = NodePath(".")
	var first: Control = _selected_button() if mode=="journal" and is_instance_valid(_selected_button()) else close_button
	for control: Control in [reading_scroll,reading_scroll.get_v_scroll_bar()]:
		control.focus_neighbor_left = control.get_path_to(first)
		control.focus_neighbor_right = control.get_path_to(recruit_button if recruit_button.visible and not recruit_button.disabled else close_button)
	var close_right: Control = reading_scroll
	if recruit_button.visible and not recruit_button.disabled: close_right = recruit_button
	var close_above: Control = reading_scroll
	if first!=close_button: close_above = first
	var close_below: Control = reading_scroll
	if not site_buttons.is_empty() and mode=="journal": close_below = site_buttons[0]
	close_button.focus_neighbor_right = close_button.get_path_to(close_right)
	close_button.focus_neighbor_top = close_button.get_path_to(close_above)
	close_button.focus_neighbor_bottom = close_button.get_path_to(close_below)
	recruit_button.focus_neighbor_left = recruit_button.get_path_to(close_button)
	recruit_button.focus_neighbor_top = recruit_button.get_path_to(reading_scroll)
	recruit_button.focus_neighbor_bottom = recruit_button.get_path_to(close_button)

func _reader_input(event: InputEvent,container: ScrollContainer) -> void:
	if not event.is_pressed(): return
	var handled := true
	var scrollbar := container.get_v_scroll_bar()
	if event.is_action_pressed("ui_up"):
		if container.scroll_vertical>0: container.scroll_vertical -= 40
		elif mode=="journal" and is_instance_valid(_selected_button()): _selected_button().grab_focus()
		else: close_button.grab_focus()
	elif event.is_action_pressed("ui_down"):
		if container.scroll_vertical<maxi(0,roundi(scrollbar.max_value-scrollbar.page)-1): container.scroll_vertical += 40
		else: (recruit_button if recruit_button.visible and not recruit_button.disabled else close_button).grab_focus()
	elif event.is_action_pressed("ui_left"):
		if mode=="journal" and is_instance_valid(_selected_button()): _selected_button().grab_focus()
		else: close_button.grab_focus()
	elif event.is_action_pressed("ui_right"): (recruit_button if recruit_button.visible and not recruit_button.disabled else close_button).grab_focus()
	elif event is InputEventKey and event.keycode==KEY_PAGEUP: container.scroll_vertical -= 360
	elif event is InputEventKey and event.keycode==KEY_PAGEDOWN: container.scroll_vertical += 360
	elif event is InputEventKey and event.keycode==KEY_HOME: container.scroll_vertical = 0
	elif event is InputEventKey and event.keycode==KEY_END: container.scroll_vertical = roundi(scrollbar.max_value)
	else: handled = false
	if handled: container.accept_event()

func _focus_changed(control: Control) -> void:
	if not is_instance_valid(control) or not is_ancestor_of(control): return
	if control is Button and control in site_buttons: _focus_id = "site:"+str(_entries[site_buttons.find(control)].id)
	elif control==reading_scroll: _focus_id = "reader"
	elif control==reading_scroll.get_v_scroll_bar(): _focus_id = "reader_bar"
	elif control==journal_scroll.get_v_scroll_bar(): _focus_id = "places_bar"
	elif control==recruit_button: _focus_id = "recruit"
	elif control==close_button: _focus_id = "close"
	remember_navigation()

func _restore_focus() -> void:
	var target: Control = close_button if mode=="encounter" else _selected_button()
	if _focus_id=="reader": target = reading_scroll
	elif _focus_id=="reader_bar" and reading_scroll.get_v_scroll_bar().visible: target = reading_scroll.get_v_scroll_bar()
	elif _focus_id=="places_bar" and journal_scroll.visible and journal_scroll.get_v_scroll_bar().visible: target = journal_scroll.get_v_scroll_bar()
	elif _focus_id=="recruit" and recruit_button.visible and not recruit_button.disabled: target = recruit_button
	elif _focus_id=="close": target = close_button
	elif _focus_id.begins_with("site:"):
		for index in _entries.size():
			if str(_entries[index].id)==_focus_id.trim_prefix("site:"): target = site_buttons[index]
	if not is_instance_valid(target): target = close_button
	target.grab_focus()

func _restore_scroll(revision: int,places_position: int,reading_position: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_queued_for_deletion() or revision!=_restore_revision: return
	journal_scroll.scroll_vertical = places_position
	reading_scroll.scroll_vertical = reading_position
	# The native scrollbar updates descendant transforms on the following frame.
	# Reveal the focused item only after those transforms match restored offsets.
	await get_tree().process_frame
	if is_queued_for_deletion() or revision!=_restore_revision: return
	var focused := get_viewport().gui_get_focus_owner()
	if mode=="journal" and focused is Button and focused in site_buttons:
		journal_scroll.ensure_control_visible(focused)
	if not _target_entry.is_empty() and mode=="journal":
		for block: Control in reading_content.get_children():
			if str(block.get_meta("entry_id",""))==_target_entry:
				reading_scroll.ensure_control_visible(block.get_child(0) if block.size.y>reading_scroll.size.y else block)
				break
		_target_entry = ""
		remember_navigation()
	_wire_focus()

func navigation_state() -> Dictionary:
	if is_instance_valid(reading_scroll): _scroll_positions[_reading_key()] = reading_scroll.scroll_vertical
	return {"mode":mode,"site":selected_site,"scroll":_scroll_positions.duplicate(),"list_scroll":journal_scroll.scroll_vertical,"focus":_focus_id}

func restore_navigation(state: Dictionary) -> void:
	if not is_node_ready(): return
	_target_entry = str(state.get("entry",""))
	var saved_positions: Variant = state.get("scroll",{})
	if saved_positions is Dictionary: _scroll_positions = saved_positions.duplicate()
	var site := str(state.get("site",""))
	if not _entry(site).is_empty(): selected_site = site
	if str(state.get("mode",""))==mode: _focus_id = str(state.get("focus",""))
	_rebuild_places()
	_rebuild_reading()
	_restore_revision += 1
	_restore_scroll(_restore_revision,maxi(0,int(state.get("list_scroll",0))),maxi(0,int(_scroll_positions.get(_reading_key(),0))))
	_restore_focus.call_deferred()

func remember_navigation() -> void:
	if is_instance_valid(hud): hud.solo_story_navigation = navigation_state()

func _exit_tree() -> void:
	remember_navigation()

func refresh_locale() -> void:
	var current_focus := _focus_id
	refresh_view()
	_focus_id = current_focus
	_restore_focus.call_deferred()

func _layout() -> void:
	SocialUiArt.layout_landscape(_landscape,hud)
	decoration.queue_redraw()

func _process(delta: float) -> void:
	_elapsed += delta
	if mode=="encounter": decoration.queue_redraw()

func _draw_foreground() -> void:
	var screen: Rect2 = hud.screen_rect()
	SocialUiArt.reading_shade(decoration,screen,410,600)
	decoration.draw_rect(Rect2(440,218,944,540),Color(.024,.040,.044,.54))
	UiArt.text(decoration,Vector2(80,111),"Begegnung" if mode=="encounter" else "Missionslogbuch",36,UiArt.IVORY,UiArt.MENU_FONT)
	UiArt.text(decoration,Vector2(82,151),"Menschen finden. Orte sichern. Das Signal weitertragen.",17,UiArt.MUTED)
	if mode=="encounter":
		UiArt.text(decoration,Vector2(80,220),str(_encounter.get("name","")),28,UiArt.AMBER,UiArt.MENU_FONT)
		var character := str(_encounter.get("character",""))
		if CharacterCatalog.contains(character): Portraits.draw_portrait(decoration,character,Rect2(94,282,278,278),_elapsed)
		else: UiArt.icon(decoration,"radio",Vector2(161,328),128,UiArt.MUTED)
		var subtitle := UiArt.wrap_text(str(_encounter.get("subtitle","")),328,17)
		for index in subtitle.size(): UiArt.text(decoration,Vector2(80,605+index*23),subtitle[index],17,UiArt.MUTED)
	else:
		UiArt.text(decoration,Vector2(80,217),L.format("%d Orte",_entries.size()),16,UiArt.MUTED)
	UiArt.divider(decoration,Vector2(80,757),Vector2(1360,757))
	UiArt.text(decoration,Vector2(80,861),"Pfeile / Steuerkreuz wählen · Rechts lesen · Esc zurück",14,UiArt.MUTED)
