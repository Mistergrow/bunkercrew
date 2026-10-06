extends Control
const L := preload("res://scripts/locale_text.gd")
const Plan := preload("res://scripts/research_plan_catalog.gd")
const RobotArt := preload("res://scripts/research_robot_art.gd")
const DanceCatalog := preload("res://scripts/medic_dance_catalog.gd")
## Open research navigation over the actual world. Inspection never spends
## points; the existing authoritative upgrade transaction remains unchanged.
const TREE_RECT := Rect2(480,224,420,490)
const DETAIL_RECT := Rect2(944,224,416,490)
const CARD_HEIGHT := 100.0
const GROUP_HEIGHT := 38.0
const GROUP_GAP := 18.0
const BODY_SIZE := 17
const ROW_TITLE_INSET := 48.0
const ROW_STATUS_WIDTH := 140.0
const REQUEST_TIMEOUT_MS := 8000
const ICON_BY_ID := {"bunker_workshop":"workshop", "medic_logistics":"harness", "medic_collection":"harness", "bunker_dance":"medkit", "bunker_dance_2":"craftsmanship", "bunker_dance_3":"boots", "bunker_dance_4":"harness", "bunker_dance_5":"core", "bunker_armor":"wall", "bunker_fortress":"fortress", "perimeter_automation":"rifle", "weapon_handling":"rifle", "weapon_magazines":"ammo", "weapon_bolt":"craftsmanship", "weapon_sights":"rifle", "weapon_choke":"shotgun", "weapon_capacitor":"arcgun", "weapon_pouches":"harness", "shotgun":"shotgun", "arcgun":"arcgun", "boots":"boots", "harness":"harness", "craftsmanship":"craftsmanship", "core_resilience":"core", "repair_tools":"craftsmanship", "blast_baffles":"wall", "precision_lines":"workshop", "medical_station":"medkit", "logistics_drive":"boots", "convoy_mg":"rifle", "convoy_armor":"wall", "convoy_armor_heavy":"fortress", "convoy_cargo":"harness", "convoy_tank":"core", "convoy_economy":"workshop", "convoy_handling":"boots", "convoy_transmission":"boots", "convoy_reload":"rifle", "convoy_stabilizer":"rifle", "convoy_support":"craftsmanship", "convoy_blast_lining":"wall"}
var game
var hud
var node_buttons: Array[Button] = []
var tab_buttons: Array[Button] = []
var selected_id := "bunker_workshop"
var selected_category := 0
var purchase_button: Button
var prerequisite_button: Button
var close_button: Button
var tree_scroll: ScrollContainer
var tree_content: Control
var decoration: Control
var _landscape: Dictionary = {}
var _visible_entries: Array[Dictionary] = []
var _positions: Dictionary = {}
var _card_width := 398.0
var _groups: Array[Dictionary] = []
var _sizes: Dictionary = {}
var _stage_ids: Array[String] = []
var _navigation_restore_pending := false
var _pending_id := ""
var _pending_deadline := 0
var _request_notice := ""
var _presentation_signature: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = Vector2(1440,900)
	if not bool(game.get("started")):
		var navigation: Dictionary = hud.get("_main_menu_navigation") if hud.get("_main_menu_navigation") is Dictionary else {}
		var scenario: Dictionary = hud.get("scenario_options") if hud.get("scenario_options") is Dictionary else {}
		_landscape = SocialUiArt.create_landscape(self,game,hud,str(navigation.get("environment",scenario.get("environment","sector07"))))
	decoration = Control.new()
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decoration.draw.connect(_draw_foreground)
	add_child(decoration)
	game.upgrades.changed.connect(_refresh)
	_build()
	_focus_initial.call_deferred()

func _process(_delta: float) -> void:
	SocialUiArt.layout_landscape(_landscape,hud)
	if not _pending_id.is_empty():
		if game.upgrades.has_upgrade(_pending_id):
			_pending_id = ""
			_request_notice = ""
		elif not _network_ready():
			_pending_id = ""
			_request_notice = "Verbindung unterbrochen. Wiederverbindung läuft …"
		elif Time.get_ticks_msec()>=_pending_deadline:
			_pending_id = ""
			_request_notice = "Keine Bestätigung erhalten. Du kannst die Freischaltung erneut anfragen."
	var wave: int = int(game.rounds.wave) if is_instance_valid(game.get("rounds")) else 1
	var expedition: Node = game.get("expedition")
	var garage_open: bool = is_instance_valid(expedition) and expedition.has_method("can_manage") and expedition.can_manage()
	var vehicle_unlocked: bool = game.upgrades.vehicle_unlocked()
	var signature: Array = [game.upgrades.points,game.upgrades.owned.hash(),wave,garage_open,vehicle_unlocked,game.upgrades.requirement(selected_id),_online(),_network_ready(),_pending_id,_request_notice]
	if signature!=_presentation_signature:
		_presentation_signature = signature
		_refresh()

func _draw_foreground() -> void:
	var bounds := SocialUiArt.bounds(hud)
	decoration.draw_rect(bounds,Color(.01,.015,.018,.20))
	SocialUiArt.reading_shade(decoration,bounds,420,800)
	UiArt.text(decoration,Vector2(80,112),"Technik",36,UiArt.IVORY,UiArt.TITLE_FONT)
	var intro := UiArt.wrap_text("Freischaltungen gelten für die ganze Gruppe.",300,15)
	for index in intro.size(): UiArt.text(decoration,Vector2(80,151+index*20),intro[index],15,UiArt.MUTED)
	var category := tab_buttons[selected_category]
	decoration.draw_line(Vector2(64,category.position.y+14),Vector2(64,category.position.y+category.size.y-14),UiArt.AMBER,2)
	UiArt.text(decoration,Vector2(480,160),UpgradeSystem.CATEGORIES[selected_category],30,UiArt.IVORY,UiArt.MENU_FONT)
	UiArt.text(decoration,Vector2(480,195),"FORSCHUNGSPLAN",13,UiArt.MUTED)
	var done := 0
	for entry: Dictionary in _visible_entries:
		if game.upgrades.has_upgrade(entry.id): done += 1
	var progress := L.format("%d / %d",[done,_visible_entries.size()])
	var progress_width := UiArt.FONT.get_string_size(progress,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
	UiArt.text(decoration,Vector2(TREE_RECT.end.x-progress_width-20,195),progress,15,UiArt.MUTED)
	UiArt.icon(decoration,"core",Vector2(80,530),32)
	UiArt.text(decoration,Vector2(126,559),str(game.upgrades.points),30,UiArt.IVORY,UiArt.MENU_FONT)
	UiArt.text(decoration,Vector2(80,594),"Technikpunkte",16,UiArt.MUTED)
	var salvage := UiArt.wrap_text("Bergung liefert Technikpunkte für die Gruppe.",290,14)
	for index in salvage.size(): UiArt.text(decoration,Vector2(80,628+index*20),salvage[index],14,UiArt.MUTED)
	_draw_selection()
	decoration.draw_line(Vector2(80,724),Vector2(360,724),Color(UiArt.MUTED,.22),1)
	UiArt.text(decoration,Vector2(80,819),"Pfeile / Steuerkreuz: wählen · Enter / A: bestätigen",13,UiArt.MUTED)

func _draw_selection() -> void:
	var entry: Dictionary = game.upgrades.node_data(selected_id)
	if entry.is_empty(): return
	var left := DETAIL_RECT.position.x
	_research_icon(decoration,selected_id,Vector2(left,224),58)
	var title_lines := UiArt.wrap_text(_research_title(str(entry.title)),DETAIL_RECT.size.x-76,24,UiArt.MENU_FONT)
	for index in title_lines.size():
		UiArt.text(decoration,Vector2(left+76,249+index*29),title_lines[index],24,UiArt.IVORY,UiArt.MENU_FONT)
	var scope_text := "Gilt an diesem Bunker" if selected_category==0 else "Bleibt auf der Reise erhalten"
	UiArt.text(decoration,Vector2(left,316),scope_text,14,UiArt.AMBER)
	var lines := _detail_lines(str(entry.detail))
	for index in lines.size(): UiArt.text(decoration,Vector2(left,354+index*23),lines[index],BODY_SIZE)
	UiArt.text(decoration,Vector2(left,557),"VORAUSSETZUNG",12,UiArt.MUTED)
	var parent: Dictionary = game.upgrades.node_data(str(entry.parent))
	if parent.is_empty(): UiArt.text(decoration,Vector2(left,591),"Erste Forschung in diesem Zweig",15,UiArt.MUTED)
	UiArt.text(decoration,Vector2(left,648),L.format("Kosten: %d Technikpunkte",entry.cost),18,UiArt.AMBER)
	var status := _selection_status(entry,game.upgrades.requirement(selected_id))
	var status_color := UiArt.GREEN if game.upgrades.has_upgrade(selected_id) else UiArt.AMBER if not _pending_id.is_empty() else UiArt.MUTED
	var status_lines := UiArt.wrap_text(status,DETAIL_RECT.size.x,15)
	for index in status_lines.size(): UiArt.text(decoration,Vector2(left,678+index*19),status_lines[index],15,status_color)

func _selection_status(entry: Dictionary,reason: String) -> String:
	if game.upgrades.has_upgrade(selected_id): return L.text("Freigeschaltet")
	if not _pending_id.is_empty(): return L.text("Freischaltung angefragt. Warte auf den Gastgeber.")
	if not _request_notice.is_empty(): return L.text(_request_notice)
	if _online() and not _network_ready(): return L.text("Verbindung unterbrochen. Wiederverbindung läuft …")
	if reason.is_empty(): return L.text("Bereit zur Freischaltung")
	if reason==L.text("NACH DEM ERSTEN SIEG IN WELLE 20"): return L.text("Nach dem Sieg in Welle 20 verfügbar")
	if reason==L.text("NUR IN DER FAHRZEUGVORBEREITUNG"): return L.text("Nur während der Fahrzeugvorbereitung")
	if reason==L.text("VORHERIGE TECHNIK ERFORSCHEN"): return L.text("Vorherige Forschung abschließen")
	if reason==L.format("AB WELLE %d",entry.wave): return L.format("Benötigt Welle %d",entry.wave)
	var missing := int(entry.cost)-int(game.upgrades.points)
	if missing>0: return L.format("Noch %d Technikpunkt nötig" if missing==1 else "Noch %d Technikpunkte nötig",missing)
	return reason

func _build() -> void:
	for category in UpgradeSystem.CATEGORIES.size():
		var button := _button("",Rect2(80,224+category*64,290,50),select_category.bind(category))
		SocialUiArt.button(button,24,"",0)
		button.toggle_mode = true
		button.gui_input.connect(_category_input.bind(category))
		tab_buttons.append(button)
	tree_scroll = ScrollContainer.new()
	tree_scroll.name = "ResearchChoices"
	tree_scroll.position = TREE_RECT.position
	tree_scroll.size = TREE_RECT.size
	tree_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tree_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tree_scroll.follow_focus = false
	tree_scroll.get_v_scroll_bar().focus_mode = Control.FOCUS_ALL
	add_child(tree_scroll)
	tree_content = Control.new()
	tree_content.custom_minimum_size = Vector2(_card_width,TREE_RECT.size.y)
	tree_content.draw.connect(_draw_connections)
	tree_scroll.add_child(tree_content)
	for entry: Dictionary in UpgradeSystem.NODES:
		var button := _button("",Rect2(),_select.bind(str(entry.id),false),tree_content)
		button.draw.connect(_paint_node.bind(button,entry))
		button.focus_entered.connect(_inspect_focused.bind(str(entry.id)))
		node_buttons.append(button)
	purchase_button = _button("",Rect2(DETAIL_RECT.position.x,746,DETAIL_RECT.size.x,48),func(): _purchase(selected_id))
	SocialUiArt.button(purchase_button,20,"check",0)
	prerequisite_button = _button("",Rect2(DETAIL_RECT.position.x,568,DETAIL_RECT.size.x,48),func():
		var entry: Dictionary = game.upgrades.node_data(selected_id)
		if not str(entry.parent).is_empty(): _select(str(entry.parent)))
	SocialUiArt.button(prerequisite_button,17,"back",0)
	close_button = _button("",Rect2(80,746,300,48),hud._close_upgrades)
	SocialUiArt.button(close_button,20,"back",0)
	tree_scroll.get_v_scroll_bar().visibility_changed.connect(_wire_focus)
	_layout_category()
	_refresh()

func _button(title: String,rect: Rect2,callback: Callable,parent: Node=self) -> Button:
	var button := Button.new()
	button.text = L.text(title)
	button.position = rect.position
	button.size = rect.size
	SocialUiArt.button(button,18,"",0)
	button.pressed.connect(func():
		if _can_focus(): callback.call())
	parent.add_child(button)
	return button

func _category_input(event: InputEvent,category: int) -> void:
	if not _can_focus(): return
	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		var next := category+(-1 if event.is_action_pressed("ui_up") else 1)
		if next<0 or next>=tab_buttons.size():
			close_button.grab_focus()
		else:
			select_category(next)
			tab_buttons[next].grab_focus()
		accept_event()
	elif event.is_action_pressed("ui_right"):
		select_category(category)
		_focus_selected.call_deferred(selected_id,true)
		accept_event()

func select_category(category: int) -> void:
	if category<0 or category>=UpgradeSystem.CATEGORIES.size(): return
	var previous_focus := get_viewport().gui_get_focus_owner()
	var had_row_focus := previous_focus is Button and node_buttons.has(previous_focus)
	selected_category = category
	var entries: Array[Dictionary] = game.upgrades.nodes_for_category(category)
	if not entries.is_empty(): selected_id = str(entries[0].id)
	_request_notice = ""
	_layout_category()
	tree_scroll.scroll_horizontal = 0
	tree_scroll.scroll_vertical = 0
	_refresh()
	if had_row_focus: _focus_selected.call_deferred(selected_id,true)

func _layout_category() -> void:
	_visible_entries.clear()
	_positions.clear()
	_sizes.clear()
	_stage_ids.clear()
	_groups = Plan.groups(selected_category,game.upgrades)
	var top := 0.0
	for group: Dictionary in _groups:
		group["top"] = top
		top += GROUP_HEIGHT
		for id: String in group.ids:
			if bool(group.stages): _stage_ids.append(id)
			_visible_entries.append(game.upgrades.node_data(id))
			_positions[id] = Vector2(0,top)
			_sizes[id] = Vector2(_card_width,CARD_HEIGHT)
			top += CARD_HEIGHT
		top += GROUP_GAP
	for index in node_buttons.size():
		var entry: Dictionary = UpgradeSystem.NODES[index]
		var button := node_buttons[index]
		button.visible = int(entry.branch)==selected_category
		button.position = _node_position(entry)
		button.size = _sizes.get(str(entry.id),Vector2(_card_width,CARD_HEIGHT))
	tree_content.custom_minimum_size = Vector2(_card_width,maxf(TREE_RECT.size.y,top-GROUP_GAP))
	tree_content.size = tree_content.custom_minimum_size
	tree_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if top-GROUP_GAP<=TREE_RECT.size.y else ScrollContainer.SCROLL_MODE_AUTO
	_wire_focus()
	tree_content.queue_redraw()

func _focus_controls() -> Array[Control]:
	var controls: Array[Control] = []
	controls.append_array(tab_buttons)
	for entry: Dictionary in _visible_entries: controls.append(_button_for(str(entry.id)))
	var scrollbar := tree_scroll.get_v_scroll_bar()
	if scrollbar.is_visible_in_tree() and scrollbar.focus_mode!=Control.FOCUS_NONE: controls.append(scrollbar)
	if prerequisite_button.is_visible_in_tree(): controls.append(prerequisite_button)
	if not purchase_button.disabled: controls.append(purchase_button)
	controls.append(close_button)
	return controls

func _wire_focus() -> void:
	if not is_instance_valid(close_button) or _visible_entries.is_empty(): return
	var controls := _focus_controls()
	for index in controls.size():
		var control := controls[index]
		control.focus_previous = control.get_path_to(controls[posmod(index-1,controls.size())])
		control.focus_next = control.get_path_to(controls[(index+1)%controls.size()])
	var inspector: Control = prerequisite_button if prerequisite_button.visible else purchase_button if not purchase_button.disabled else close_button
	for index in tab_buttons.size():
		var category := tab_buttons[index]
		category.focus_neighbor_top = category.get_path_to(tab_buttons[index-1] if index>0 else close_button)
		category.focus_neighbor_bottom = category.get_path_to(tab_buttons[index+1] if index<tab_buttons.size()-1 else close_button)
		category.focus_neighbor_left = NodePath(".")
		category.focus_neighbor_right = category.get_path_to(_button_for(selected_id))
	for index in _visible_entries.size():
		var button := _button_for(str(_visible_entries[index].id))
		button.focus_neighbor_top = button.get_path_to(tab_buttons[selected_category] if index==0 else _button_for(str(_visible_entries[index-1].id)))
		button.focus_neighbor_bottom = button.get_path_to(inspector if index==_visible_entries.size()-1 else _button_for(str(_visible_entries[index+1].id)))
		button.focus_neighbor_left = button.get_path_to(tab_buttons[selected_category])
		button.focus_neighbor_right = button.get_path_to(inspector)
	var selected := _button_for(selected_id)
	prerequisite_button.focus_neighbor_left = prerequisite_button.get_path_to(selected)
	prerequisite_button.focus_neighbor_right = NodePath(".")
	prerequisite_button.focus_neighbor_top = prerequisite_button.get_path_to(selected)
	prerequisite_button.focus_neighbor_bottom = prerequisite_button.get_path_to(purchase_button if not purchase_button.disabled else close_button)
	purchase_button.focus_neighbor_left = purchase_button.get_path_to(selected)
	purchase_button.focus_neighbor_right = NodePath(".")
	purchase_button.focus_neighbor_top = purchase_button.get_path_to(prerequisite_button if prerequisite_button.visible else selected)
	purchase_button.focus_neighbor_bottom = purchase_button.get_path_to(close_button)
	close_button.focus_neighbor_top = close_button.get_path_to(tab_buttons[-1])
	close_button.focus_neighbor_bottom = close_button.get_path_to(tab_buttons[0])
	close_button.focus_neighbor_left = NodePath(".")
	close_button.focus_neighbor_right = close_button.get_path_to(selected)
	var scrollbar := tree_scroll.get_v_scroll_bar()
	scrollbar.focus_neighbor_left = scrollbar.get_path_to(selected)
	scrollbar.focus_neighbor_right = scrollbar.get_path_to(inspector)
	scrollbar.focus_neighbor_top = scrollbar.get_path_to(selected)
	scrollbar.focus_neighbor_bottom = scrollbar.get_path_to(inspector)

func _button_for(id: String) -> Button:
	var entry: Dictionary = game.upgrades.node_data(id)
	var index := UpgradeSystem.NODES.find(entry)
	return node_buttons[index] if index>=0 and index<node_buttons.size() else null

func _draw_connections() -> void:
	for group: Dictionary in _groups:
		var top := float(group.top)
		UiArt.text(tree_content,Vector2(0,top+23),str(group.title),17,UiArt.IVORY)
		var done := 0
		for id: String in group.ids:
			if game.upgrades.has_upgrade(id): done += 1
		var progress := L.format("%d / %d",[done,group.ids.size()])
		var width := UiArt.FONT.get_string_size(progress,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
		UiArt.text(tree_content,Vector2(_card_width-width-4,top+23),progress,14,UiArt.MUTED)

func _paint_node(button: Button,entry: Dictionary) -> void:
	var owned: bool = game.upgrades.has_upgrade(entry.id)
	var available: bool = game.upgrades.requirement(entry.id).is_empty()
	var selected := selected_id==str(entry.id)
	var ink := UiArt.IVORY if owned or available or selected else UiArt.MUTED
	if selected: button.draw_line(Vector2(1,14),Vector2(1,button.size.y-14),UiArt.AMBER,2)
	button.draw_line(Vector2(12,button.size.y-1),Vector2(button.size.x-4,button.size.y-1),Color(UiArt.MUTED,.22),1)
	var tint := Color.WHITE if owned or available else Color("9a9f8d")
	_research_icon(button,str(entry.id),Vector2(8,16),28,tint)
	var titles := node_title_lines(entry)
	for index in titles.size(): UiArt.text(button,Vector2(ROW_TITLE_INSET,25+index*22),titles[index],_node_title_size(str(entry.title)),ink)
	var requirement_lines := UiArt.wrap_text(_row_requirement(entry),button.size.x-ROW_TITLE_INSET-6,14)
	for index in requirement_lines.size(): UiArt.text(button,Vector2(ROW_TITLE_INSET,69+index*19),requirement_lines[index],14,UiArt.MUTED)
	var status := L.text("Freigeschaltet") if owned else L.format("%d TP",entry.cost)
	var status_color := UiArt.GREEN if owned else UiArt.AMBER if available else UiArt.MUTED
	var status_width := UiArt.FONT.get_string_size(status,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
	UiArt.text(button,Vector2(button.size.x-status_width-23,25),status,13,status_color)
	UiArt.icon(button,"check" if owned else "lock" if not available else "core",Vector2(button.size.x-16,12),13,status_color)

func _row_requirement(entry: Dictionary) -> String:
	var parent: Dictionary = game.upgrades.node_data(str(entry.parent))
	var result := L.text("Erste Forschung in diesem Zweig") if parent.is_empty() else L.format("Benötigt: %s",_research_title(str(parent.title)))
	if int(entry.wave)>1: result += "  ·  "+L.format("Benötigt Welle %d",entry.wave)
	return result

func _inspect_focused(id: String) -> void:
	if _can_focus(): _select(id,false)

func _select(id: String,ensure_visible: bool=true) -> void:
	var entry: Dictionary = game.upgrades.node_data(id)
	if entry.is_empty(): return
	selected_id = id
	if not _navigation_restore_pending: _request_notice = ""
	if selected_category!=int(entry.branch):
		selected_category = int(entry.branch)
		_layout_category()
	_refresh()
	if not _navigation_restore_pending: _focus_selected.call_deferred(id,ensure_visible)

func _can_focus() -> bool:
	if not is_inside_tree() or is_queued_for_deletion() or not is_visible_in_tree(): return false
	if "overlay" in hud and str(hud.overlay)!="upgrades": return false
	if "upgrade_panel" in hud and hud.upgrade_panel!=self: return false
	if hud.has_method("has_session_action") and hud.has_session_action(): return false
	return true

func _focus_initial() -> void:
	if not _can_focus() or _navigation_restore_pending: return
	_focus_selected(selected_id,true)

func _focus_selected(id: String,request_focus: bool) -> void:
	if not _can_focus() or _navigation_restore_pending: return
	await get_tree().process_frame
	if not _can_focus() or _navigation_restore_pending or selected_id!=id: return
	var button := _button_for(id)
	if not is_instance_valid(button) or not button.is_visible_in_tree(): return
	if request_focus: button.grab_focus()
	_reveal_selected(button,true)

func _reveal_selected(button: Button,group_context: bool=false) -> void:
	var page := tree_scroll.size.y
	var context := button.get_rect()
	if group_context:
		for group: Dictionary in _groups:
			if selected_id not in group.ids: continue
			var bottom := float(group.top)+GROUP_HEIGHT
			for id: String in group.ids: bottom = maxf(bottom,_positions[id].y+_sizes[id].y)
			if bottom-float(group.top)<=page: context=Rect2(0,float(group.top),_card_width,bottom-float(group.top))
			break
	tree_scroll.scroll_horizontal = 0
	if context.position.y<tree_scroll.scroll_vertical: tree_scroll.scroll_vertical=floori(context.position.y)
	elif context.end.y>tree_scroll.scroll_vertical+page: tree_scroll.scroll_vertical=ceili(context.end.y-page)

func _refresh() -> void:
	var previous_focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if not _pending_id.is_empty() and game.upgrades.has_upgrade(_pending_id):
		_pending_id = ""
		_request_notice = ""
	for category in tab_buttons.size():
		tab_buttons[category].text = L.text(UpgradeSystem.CATEGORIES[category])
		tab_buttons[category].set_pressed_no_signal(category==selected_category)
		tab_buttons[category].add_theme_color_override("font_color",UiArt.AMBER if category==selected_category else UiArt.IVORY)
	for button: Button in node_buttons:
		button.tooltip_text = ""
		button.queue_redraw()
	var reason: String = game.upgrades.requirement(selected_id)
	purchase_button.disabled = not reason.is_empty() or not _pending_id.is_empty() or (_online() and not _network_ready())
	purchase_button.text = L.text("Warten auf Gastgeber" if not _pending_id.is_empty() else "Freischalten" if not purchase_button.disabled else "Bereits erforscht" if game.upgrades.has_upgrade(selected_id) else "Noch nicht verfügbar")
	var entry: Dictionary = game.upgrades.node_data(selected_id)
	var parent: Dictionary = game.upgrades.node_data(str(entry.get("parent","")))
	prerequisite_button.visible = not parent.is_empty()
	if not parent.is_empty(): prerequisite_button.text = _research_title(str(parent.title))
	close_button.text = L.text("Zurück  ·  T / Esc")
	_wire_focus()
	if is_instance_valid(previous_focus) and is_ancestor_of(previous_focus) and (not previous_focus.is_visible_in_tree() or (previous_focus is BaseButton and previous_focus.disabled)):
		_focus_selected.call_deferred(selected_id,true)
	tree_content.queue_redraw()
	decoration.queue_redraw()

func _online() -> bool:
	return "network" in game and is_instance_valid(game.network) and game.network.active

func _network_ready() -> bool:
	if not _online(): return true
	return game.network.state=="playing" and not bool(game.network.get("_loading")) and game.network.chat_available()

func _purchase(id: String) -> void:
	if not _can_focus() or not _pending_id.is_empty() or not game.upgrades.requirement(id).is_empty() or not _network_ready(): return
	_request_notice = ""
	if _online():
		if not game.network.is_host:
			_pending_id = id
			_pending_deadline = Time.get_ticks_msec()+REQUEST_TIMEOUT_MS
			_refresh()
		game.network.send_command("upgrade",{"id":id})
	else:
		game.upgrades.purchase(id)

func navigation_state() -> Dictionary:
	var state := {"selected_category":selected_category,"selected_id":selected_id,"scroll_vertical":tree_scroll.scroll_vertical,"focus_role":"node","focus_index":UpgradeSystem.NODES.find(game.upgrades.node_data(selected_id)),"pending_id":_pending_id,"pending_deadline":_pending_deadline,"request_notice":_request_notice}
	var focused := get_viewport().gui_get_focus_owner()
	if focused is Button:
		if node_buttons.has(focused): state.focus_index=node_buttons.find(focused)
		elif tab_buttons.has(focused): state.focus_role="category";state.focus_index=tab_buttons.find(focused)
		elif focused==prerequisite_button: state.focus_role="prerequisite"
		elif focused==purchase_button: state.focus_role="purchase"
		elif focused==close_button: state.focus_role="close"
	elif focused==tree_scroll.get_v_scroll_bar(): state.focus_role="scroll"
	return state

func restore_navigation(state: Dictionary) -> void:
	if state.is_empty(): return
	_navigation_restore_pending = true
	_restore_navigation_deferred.call_deferred(state.duplicate(true))

func _restore_navigation_deferred(state: Dictionary) -> void:
	if not _can_focus(): _navigation_restore_pending=false;return
	selected_category = clampi(int(state.get("selected_category",0)),0,tab_buttons.size()-1)
	var id := str(state.get("selected_id",""))
	var entry: Dictionary = game.upgrades.node_data(id)
	if entry.is_empty() or int(entry.branch)!=selected_category: id=str(game.upgrades.nodes_for_category(selected_category)[0].id)
	selected_id = id
	var pending := str(state.get("pending_id",""))
	_pending_id = pending if not game.upgrades.node_data(pending).is_empty() and not game.upgrades.has_upgrade(pending) else ""
	_pending_deadline = maxi(0,int(state.get("pending_deadline",0)))
	_request_notice = str(state.get("request_notice",""))
	_layout_category()
	_refresh()
	await get_tree().process_frame
	if not _can_focus(): _navigation_restore_pending=false;return
	var target: Control = _button_for(selected_id)
	var index := int(state.get("focus_index",0))
	match str(state.get("focus_role","node")):
		"category": target=tab_buttons[clampi(index,0,tab_buttons.size()-1)]
		"prerequisite":
			if prerequisite_button.visible: target=prerequisite_button
		"purchase":
			if not purchase_button.disabled: target=purchase_button
		"close": target=close_button
		"scroll":
			var scrollbar := tree_scroll.get_v_scroll_bar()
			if scrollbar.is_visible_in_tree() and scrollbar.focus_mode!=Control.FOCUS_NONE: target=scrollbar
		"node":
			if index>=0 and index<node_buttons.size() and node_buttons[index].is_visible_in_tree(): target=node_buttons[index]
	target.grab_focus()
	tree_scroll.scroll_vertical = clampi(int(state.get("scroll_vertical",0)),0,maxi(0,ceili(tree_content.size.y-tree_scroll.size.y)))
	if target is Button and node_buttons.has(target): _reveal_selected(target)
	_navigation_restore_pending = false

func refresh_locale() -> void:
	_refresh()

func _research_title(title: String) -> String:
	var translated := L.text(title)
	var result := translated.capitalize().replace("Mg ","MG ").replace("San 1","SAN-1")
	if translated.begins_with("MG-"): result="MG-"+result.substr(3)
	if translated.begins_with("BUNKERDANCE "): result="Bunkerdance "+translated.get_slice(" ",1)
	return result

func node_title_lines(entry: Dictionary) -> Array[String]:
	var title := L.text(str(DanceCatalog.LABELS[_stage_ids.find(str(entry.id))])) if str(entry.id) in _stage_ids else _research_title(str(entry.title))
	return UiArt.wrap_text(title,_node_title_width(str(entry.id)),_node_title_size(str(entry.title)))

func _node_title_width(_id: String="") -> float:
	return _card_width-ROW_TITLE_INSET-ROW_STATUS_WIDTH

func _node_title_size(_title: String) -> int:
	return 18

func _node_position(entry: Dictionary) -> Vector2:
	return _positions.get(str(entry.id),Vector2.ZERO)

func _selection_title_size(_title: String) -> int:
	return 24

func _detail_lines(detail: String) -> Array[String]:
	return UiArt.wrap_text(detail,DETAIL_RECT.size.x,BODY_SIZE)

func _research_icon(target: CanvasItem, id: String, at: Vector2, icon_size: float, tint: Color = Color.WHITE) -> void:
	if id.begins_with("bunker_dance") or id in ["medic_logistics", "medic_collection", "logistics_drive"]:
		RobotArt.draw(target, at, icon_size, tint)
		return
	if id not in ["medical_station", "convoy_tank"]:
		UiArt.icon(target, ICON_BY_ID.get(id, "workshop"), at, icon_size, tint)
		return
	var unit := icon_size / 32.0
	var base := at.round()
	target.draw_rect(Rect2(base + Vector2(3,7)*unit, Vector2(26,23)*unit), UiArt.SHADOW*tint)
	target.draw_rect(Rect2(base + Vector2(5,9)*unit, Vector2(22,18)*unit), Color("78816a")*tint)
	target.draw_rect(Rect2(base + Vector2(6,10)*unit, Vector2(20,2)*unit), Color("a5ad91")*tint)
	if id == "medical_station":
		target.draw_rect(Rect2(base + Vector2(10,3)*unit, Vector2(12,6)*unit), UiArt.SHADOW*tint)
		target.draw_rect(Rect2(base + Vector2(12,4)*unit, Vector2(8,3)*unit), Color("9aa68f")*tint)
		target.draw_rect(Rect2(base + Vector2(13,13)*unit, Vector2(6,12)*unit), UiArt.IVORY*tint)
		target.draw_rect(Rect2(base + Vector2(10,16)*unit, Vector2(12,6)*unit), UiArt.IVORY*tint)
	else:
		target.draw_rect(Rect2(base + Vector2(8,4)*unit, Vector2(13,5)*unit), UiArt.SHADOW*tint)
		target.draw_rect(Rect2(base + Vector2(22,5)*unit, Vector2(5,4)*unit), UiArt.AMBER*tint)
		target.draw_line(base + Vector2(9,15)*unit, base + Vector2(23,24)*unit, Color("535e4f")*tint, 2*unit)
		target.draw_line(base + Vector2(23,15)*unit, base + Vector2(9,24)*unit, Color("535e4f")*tint, 2*unit)
