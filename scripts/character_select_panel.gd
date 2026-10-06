class_name CharacterSelectPanel
extends Control
const L := preload("res://scripts/locale_text.gd")

const IdentityArt := preload("res://scripts/worker_identity_art.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
## Open crew navigation and actual animated side portraits over the panorama.
## Every choice remains a native Button; gameplay and unlock APIs are unchanged.
const ROW_HEIGHT := 78.0
const LIST_RECT := Rect2(480,226,354,468)
const DETAIL_RECT := Rect2(940,152,420,562)
var game
var hud
var player_count := 1
var active_slot := 0
var cards: Array[Button] = []
var slot_buttons: Array[Button] = []
var count_buttons: Array[Button] = []
var begin_button: Button
var back_button: Button
var elapsed := 0.0
var card_scroll: ScrollContainer
var card_content: Control
var preview_character_id := ""
var decoration: Control
var _landscape: Dictionary = {}
var _navigation_restore_pending := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = Vector2(1440,900)
	if not bool(game.get("started")):
		var navigation: Dictionary = hud.get("_main_menu_navigation") if hud.get("_main_menu_navigation") is Dictionary else {}
		var scenario: Dictionary = hud.get("scenario_options") if hud.get("scenario_options") is Dictionary else {}
		var environment: String = str(scenario.get("environment","sector07")) if bool(hud.get("scenario_selected")) else str(navigation.get("environment",scenario.get("environment","sector07")))
		_landscape = SocialUiArt.create_landscape(self,game,hud,environment)
	decoration = Control.new()
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decoration.draw.connect(_draw_foreground)
	add_child(decoration)
	game.selected_characters = PartyConfig.normalize_characters(game.selected_characters)
	for slot in game.selected_characters.size():
		if not CharacterCatalog.is_unlocked(game.selected_characters[slot]):
			game.selected_characters[slot] = PartyConfig.DEFAULT_CHARACTERS[slot]
	game.selected_characters = PartyConfig.unique_characters(game.selected_characters)
	preview_character_id = str(game.selected_characters[active_slot])
	for count in [2,3,4]:
		var count_button := _button(L.format("%d Spieler",count),Rect2(80+(count-2)*100,224,96,42),func(): set_player_count(count))
		SocialUiArt.button(count_button,16,"",0)
		count_buttons.append(count_button)
	for slot in PartyConfig.MAX_PLAYERS:
		var button := _button(L.format("P%d AUSWÄHLEN", (slot+1)),Rect2(80,302+slot*78,300,54),func(): select_slot(slot))
		SocialUiArt.button(button,18,"",0)
		button.toggle_mode = true
		button.disabled = slot>=player_count
		slot_buttons.append(button)
	card_scroll = ScrollContainer.new()
	card_scroll.name = "CharacterChoices"
	card_scroll.position = LIST_RECT.position
	card_scroll.size = LIST_RECT.size
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	card_scroll.follow_focus = false
	add_child(card_scroll)
	card_content = Control.new()
	card_content.custom_minimum_size = Vector2(332,CharacterCatalog.CHARACTERS.size()*ROW_HEIGHT)
	card_scroll.add_child(card_content)
	for index in CharacterCatalog.CHARACTERS.size():
		var entry: Dictionary = CharacterCatalog.CHARACTERS[index]
		var card := _button("",Rect2(0,index*ROW_HEIGHT,332,72),func(): select_character(entry.id),card_content)
		card.tooltip_text = CharacterCatalog.selection_title(entry.id) + " · " + CharacterCatalog.selection_detail(entry.id)
		card.draw.connect(func(): _draw_card(card,entry,index))
		card.focus_entered.connect(_reveal_card.bind(card))
		card.focus_entered.connect(_preview_character.bind(str(entry.id)))
		card.mouse_entered.connect(_preview_character.bind(str(entry.id)))
		card.mouse_exited.connect(_restore_preview)
		cards.append(card)
	back_button = _button("Zurück  ·  Esc / B",Rect2(80,746,300,48),hud._close_character_selection)
	SocialUiArt.button(back_button,20,"back",0)
	begin_button = _button("Schicht beginnen",Rect2(1070,746,290,48),begin_session)
	SocialUiArt.button(begin_button,20,"play",0)
	card_scroll.get_v_scroll_bar().visibility_changed.connect(_wire_focus)
	_refresh()
	_focus_initial.call_deferred()

func _process(delta: float) -> void:
	elapsed += delta
	for card in cards: card.queue_redraw()
	SocialUiArt.layout_landscape(_landscape,hud)
	decoration.queue_redraw()

func set_player_count(count: int) -> void:
	if player_count == 1 or (hud.has_method("_online") and hud._online()): return
	var previous_focus := get_viewport().gui_get_focus_owner()
	var had_panel_focus := is_instance_valid(previous_focus) and is_ancestor_of(previous_focus)
	player_count = clampi(count,2,PartyConfig.MAX_PLAYERS)
	hud.selection_count = player_count
	active_slot = mini(active_slot,player_count-1)
	preview_character_id = str(game.selected_characters[active_slot])
	_refresh()
	var current_focus := get_viewport().gui_get_focus_owner()
	if had_panel_focus and (not is_instance_valid(current_focus) or not previous_focus.is_visible_in_tree() or (previous_focus is BaseButton and previous_focus.disabled)):
		_focus_active_slot.call_deferred()

func select_slot(slot: int) -> void:
	if slot<0 or slot>=player_count: return
	active_slot = slot
	preview_character_id = str(game.selected_characters[active_slot])
	_refresh()

func select_character(id: String) -> void:
	if not CharacterCatalog.is_unlocked(id): return
	var previous: String = game.selected_characters[active_slot]
	for slot in game.selected_characters.size():
		if slot != active_slot and game.selected_characters[slot] == id:
			game.selected_characters[slot] = previous
			break
	game.selected_characters[active_slot] = id
	preview_character_id = id
	_refresh()

func begin_session() -> void:
	if game.selected_characters != PartyConfig.unique_characters(game.selected_characters): return
	for slot in player_count:
		if not CharacterCatalog.is_unlocked(game.selected_characters[slot]): return
	if hud.has_method("_online") and hud._online():
		hud.overlay = "network"
		return
	if hud.scenario_selected:
		game.story_mode=hud.story_selected
		game.start_scenario(player_count,hud.scenario_options)
	else:
		game.start(player_count)

func _refresh() -> void:
	var local_coop: bool = player_count > 1 and not (hud.has_method("_online") and hud._online())
	for index in count_buttons.size():
		count_buttons[index].visible = local_coop
		count_buttons[index].disabled = player_count == index+2
		count_buttons[index].text = L.format("%d Spieler",index+2)
		count_buttons[index].add_theme_color_override("font_disabled_color",UiArt.AMBER)
	for slot in slot_buttons.size():
		slot_buttons[slot].disabled = slot >= player_count
		slot_buttons[slot].visible = slot < player_count
		var entry: Dictionary = CharacterCatalog.data(game.selected_characters[slot])
		slot_buttons[slot].text = L.format("Spieler %d · %s%s", [slot+1,CharacterCatalog.selection_title(entry.id),"  ✓" if slot==active_slot else ""])
		slot_buttons[slot].set_pressed_no_signal(slot==active_slot)
		slot_buttons[slot].add_theme_color_override("font_color",UiArt.AMBER if slot==active_slot else UiArt.IVORY)
	for index in cards.size():
		var entry: Dictionary = CharacterCatalog.CHARACTERS[index]
		cards[index].tooltip_text = L.format("%s · %s", [entry.title,entry.detail]) if CharacterCatalog.is_unlocked(entry.id) else CharacterCatalog.selection_title(entry.id) + " · " + CharacterCatalog.selection_detail(entry.id)
		cards[index].queue_redraw()
	_wire_focus()
	if is_instance_valid(back_button): back_button.text = L.text("Zurück  ·  Esc / B")
	if is_instance_valid(begin_button): begin_button.text = L.text("Schicht beginnen")
	if is_instance_valid(decoration): decoration.queue_redraw()

func _button(title: String,rect: Rect2,callback: Callable,parent: Node=self) -> Button:
	var button := Button.new()
	button.text = L.text(title)
	button.position = rect.position
	button.size = rect.size
	SocialUiArt.button(button,18,"",0)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _reveal_card(card: Button) -> void:
	card_scroll.ensure_control_visible(card)
	# Native focus scrolling rounds transformed pixel bounds. The authored
	# local card rectangle preserves its entire footer at fractional UI scales.
	var top := floori(card.position.y)
	var bottom := ceili(card.position.y+card.size.y)
	var page := floori(card_scroll.size.y)
	if top<card_scroll.scroll_vertical: card_scroll.scroll_vertical = top
	elif bottom>card_scroll.scroll_vertical+page: card_scroll.scroll_vertical = bottom-page

func _preview_character(id: String) -> void:
	if not CharacterCatalog.contains(id): return
	preview_character_id = id
	if is_instance_valid(decoration): decoration.queue_redraw()

func _restore_preview() -> void:
	for index in cards.size():
		if cards[index].has_focus():
			_preview_character(str(CharacterCatalog.CHARACTERS[index].id))
			return
	_preview_character(str(game.selected_characters[active_slot]))

func _selected_card_index() -> int:
	for index in CharacterCatalog.CHARACTERS.size():
		if str(CharacterCatalog.CHARACTERS[index].id)==str(game.selected_characters[active_slot]): return index
	return 0

func _focus_initial() -> void:
	if not is_inside_tree() or not is_visible_in_tree() or is_queued_for_deletion(): return
	if _navigation_restore_pending: return
	if hud.has_method("has_session_action") and hud.has_session_action(): return
	if not cards.is_empty(): cards[_selected_card_index()].grab_focus()

func navigation_state() -> Dictionary:
	var state := {"active_slot":active_slot,"preview_character_id":preview_character_id,"scroll_vertical":card_scroll.scroll_vertical,"focus_role":"card","focus_index":_selected_card_index()}
	var focused := get_viewport().gui_get_focus_owner()
	if focused is Button:
		for role: String in ["card","slot","count"]:
			var controls: Array = cards if role=="card" else slot_buttons if role=="slot" else count_buttons
			var index := controls.find(focused)
			if index>=0:
				state.focus_role = role
				state.focus_index = index
				return state
	if focused==begin_button: state.focus_role = "begin"
	elif focused==back_button: state.focus_role = "back"
	elif focused==card_scroll.get_v_scroll_bar(): state.focus_role = "scroll"
	return state

func restore_navigation(state: Dictionary) -> void:
	if state.is_empty(): return
	_navigation_restore_pending = true
	_restore_navigation_deferred.call_deferred(state.duplicate(true))

func _navigation_index(value: Variant,fallback: int) -> int:
	return int(value) if value is int else fallback

func _restore_navigation_deferred(state: Dictionary) -> void:
	_navigation_restore_pending = false
	if not is_inside_tree() or is_queued_for_deletion() or cards.is_empty(): return
	active_slot = clampi(_navigation_index(state.get("active_slot"),active_slot),0,player_count-1)
	var saved_preview: String = str(state.get("preview_character_id",game.selected_characters[active_slot]))
	preview_character_id = saved_preview if CharacterCatalog.contains(saved_preview) else str(game.selected_characters[active_slot])
	_refresh()
	var page := floori(card_scroll.size.y)
	var maximum := maxi(0,ceili(card_content.custom_minimum_size.y)-page)
	var saved_scroll := clampi(_navigation_index(state.get("scroll_vertical"),0),0,maximum)
	card_scroll.scroll_vertical = saved_scroll
	if not is_visible_in_tree() or (hud.has_method("has_session_action") and hud.has_session_action()): return
	var target: Control = cards[_selected_card_index()]
	var index := _navigation_index(state.get("focus_index"),_selected_card_index())
	match str(state.get("focus_role","card")):
		"card": target = cards[clampi(index,0,cards.size()-1)]
		"slot": target = slot_buttons[clampi(index,0,player_count-1)]
		"count": target = count_buttons[clampi(index,0,count_buttons.size()-1)]
		"begin": target = begin_button
		"back": target = back_button
		"scroll": target = card_scroll.get_v_scroll_bar()
	if not target.is_visible_in_tree() or (target is BaseButton and target.disabled): target = slot_buttons[active_slot]
	target.grab_focus()
	# Native ensure_control_visible adds theme margins during focus_entered.
	# Restore the exact reading position, only shifting if the row is outside it.
	if target is Button and cards.has(target):
		var top := floori(target.position.y)
		var bottom := ceili(target.position.y+target.size.y)
		if top<saved_scroll: saved_scroll = top
		elif bottom>saved_scroll+page: saved_scroll = bottom-page
	card_scroll.scroll_vertical = clampi(saved_scroll,0,maximum)
	# Revealing a focused row may scroll it fully into view. Hover-only preview
	# state is restored separately and never changes the chosen crew identities.
	preview_character_id = saved_preview if CharacterCatalog.contains(saved_preview) else str(game.selected_characters[active_slot])
	decoration.queue_redraw()

func _wire_focus() -> void:
	var header: Array[Control] = []
	for button: Button in count_buttons:
		if button.visible and not button.disabled: header.append(button)
	for button: Button in slot_buttons:
		if button.visible and not button.disabled: header.append(button)
	var controls: Array[Control] = header.duplicate()
	controls.append_array(cards)
	controls.append_array([back_button,begin_button])
	var scrollbar := card_scroll.get_v_scroll_bar()
	scrollbar.focus_mode = Control.FOCUS_ALL
	if scrollbar.visible: controls.append(scrollbar)
	for index in controls.size():
		var control := controls[index]
		control.focus_next = control.get_path_to(controls[(index+1)%controls.size()])
		control.focus_previous = control.get_path_to(controls[posmod(index-1,controls.size())])
	for index in cards.size():
		var card := cards[index]
		card.focus_neighbor_top = card.get_path_to(cards[index-1] if index>0 else slot_buttons[active_slot])
		card.focus_neighbor_bottom = card.get_path_to(cards[index+1] if index+1<cards.size() else begin_button)
		card.focus_neighbor_left = card.get_path_to(slot_buttons[active_slot])
		card.focus_neighbor_right = card.get_path_to(begin_button)
	var counts: Array[Button] = []
	for button: Button in count_buttons:
		if button.visible and not button.disabled: counts.append(button)
	for index in counts.size():
		var control := counts[index]
		control.focus_neighbor_bottom = control.get_path_to(slot_buttons[0])
		control.focus_neighbor_top = control.get_path_to(back_button)
		control.focus_neighbor_left = control.get_path_to(counts[posmod(index-1,counts.size())])
		control.focus_neighbor_right = control.get_path_to(counts[(index+1)%counts.size()])
	for index in player_count:
		var control := slot_buttons[index]
		control.focus_neighbor_top = control.get_path_to(slot_buttons[index-1] if index>0 else counts[0] if not counts.is_empty() else back_button)
		control.focus_neighbor_bottom = control.get_path_to(slot_buttons[index+1] if index+1<player_count else back_button)
		control.focus_neighbor_left = NodePath(".")
		control.focus_neighbor_right = control.get_path_to(cards[_selected_card_index()])
	back_button.focus_neighbor_right = back_button.get_path_to(begin_button)
	back_button.focus_neighbor_left = back_button.get_path_to(begin_button)
	back_button.focus_neighbor_top = back_button.get_path_to(slot_buttons[player_count-1])
	back_button.focus_neighbor_bottom = back_button.get_path_to(header[0] if not header.is_empty() else cards[0])
	begin_button.focus_neighbor_left = begin_button.get_path_to(back_button)
	begin_button.focus_neighbor_right = begin_button.get_path_to(back_button)
	begin_button.focus_neighbor_top = begin_button.get_path_to(cards[cards.size()-1])
	begin_button.focus_neighbor_bottom = begin_button.get_path_to(header[0] if not header.is_empty() else cards[0])
	scrollbar.focus_neighbor_left = scrollbar.get_path_to(cards[cards.size()-1])
	scrollbar.focus_neighbor_bottom = scrollbar.get_path_to(begin_button)
	var focused := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused) and is_ancestor_of(focused) and (not focused.is_visible_in_tree() or (focused is BaseButton and focused.disabled)):
		_focus_active_slot.call_deferred()

func _focus_active_slot() -> void:
	if not is_inside_tree() or not is_visible_in_tree() or is_queued_for_deletion(): return
	if hud.has_method("has_session_action") and hud.has_session_action(): return
	slot_buttons[active_slot].grab_focus()

func _draw_foreground() -> void:
	if not is_instance_valid(game): return
	var bounds := SocialUiArt.bounds(hud)
	decoration.draw_rect(bounds,Color(.01,.015,.018,.20))
	SocialUiArt.reading_shade(decoration,bounds,420,800)
	UiArt.text(decoration,Vector2(80,112),"Wähle deine Figur",36,UiArt.IVORY,UiArt.TITLE_FONT)
	UiArt.text(decoration,Vector2(80,184),L.format("Lokaler Koop · %d Spieler",player_count) if player_count>1 else "Allein spielen",15,UiArt.MUTED)
	UiArt.text(decoration,Vector2(80,286),"Deine Crew",15,UiArt.MUTED)
	UiArt.text(decoration,Vector2(480,160),"Figuren",30,UiArt.IVORY,UiArt.MENU_FONT)
	var hint := UiArt.wrap_text("Weitere Figuren werden auf der Reise gerettet.",880,13)
	for line in hint.size(): UiArt.text(decoration,Vector2(480,190+line*18),hint[line],13,UiArt.MUTED)
	var active_button := slot_buttons[active_slot]
	decoration.draw_line(Vector2(64,active_button.position.y+12),Vector2(64,active_button.position.y+active_button.size.y-12),UiArt.AMBER,2)
	decoration.draw_line(Vector2(80,724),Vector2(360,724),Color(UiArt.MUTED,.22),1)
	decoration.draw_line(Vector2(480,724),Vector2(1360,724),Color(UiArt.MUTED,.22),1)
	UiArt.text(decoration,Vector2(80,819),"Pfeile / Steuerkreuz: wählen · Enter / A: bestätigen",13,UiArt.MUTED)
	_draw_details()

func _draw_details() -> void:
	var id := preview_character_id if CharacterCatalog.contains(preview_character_id) else str(game.selected_characters[active_slot])
	var entry := CharacterCatalog.data(id)
	var available := CharacterCatalog.is_unlocked(id)
	var accent := Color(entry.accent) if available else UiArt.MUTED
	draw_selection_portrait(decoration,id,Rect2(DETAIL_RECT.position+Vector2(50,0),Vector2(320,320)),elapsed)
	UiArt.text(decoration,Vector2(940,495),CharacterCatalog.selection_title(id),30,accent,UiArt.MENU_FONT)
	var lines := UiArt.wrap_text(CharacterCatalog.selection_detail(id),DETAIL_RECT.size.x,15)
	for index in lines.size(): UiArt.text(decoration,Vector2(940,524+index*21),lines[index],15,UiArt.MUTED)
	if available:
		UiArt.text(decoration,Vector2(940,582),L.format("%d LP",int(entry.hp)),17)
		UiArt.text(decoration,Vector2(1140,582),L.format("Traglast %d",int(entry.capacity)),17)
		UiArt.text(decoration,Vector2(940,613),L.format("Tempo %d %%",roundi(float(entry.speed)*100)),15,UiArt.MUTED)
		UiArt.text(decoration,Vector2(940,642),L.format("Arbeit %d %% · Schaden %d %%",[roundi(float(entry.work)*100),roundi(float(entry.damage)*100)]),14,UiArt.MUTED)
		if entry.has("special"):
			var special := UiArt.wrap_text(str(entry.special),DETAIL_RECT.size.x,13)
			for index in special.size(): UiArt.text(decoration,Vector2(940,669+index*18),special[index],13,UiArt.MUTED)
	else:
		UiArt.text(decoration,Vector2(940,593),CharacterCatalog.unlock_hint(id),15,UiArt.MUTED)
	UiArt.text(decoration,Vector2(940,710),_selection_caption(id),13,UiArt.AMBER if available else UiArt.MUTED)

func _selection_caption(id: String) -> String:
	if not CharacterCatalog.is_unlocked(id): return L.text("Auf der Reise retten")
	if game.selected_characters[active_slot]==id: return L.format("✓ Für Spieler %d gewählt",active_slot+1)
	for slot in player_count:
		if game.selected_characters[slot]==id: return L.format("Mit Spieler %d tauschen",slot+1)
	return L.format("Für Spieler %d auswählen",active_slot+1)

func _draw_card(card: Button, entry: Dictionary, _index: int) -> void:
	var selected: bool = game.selected_characters[active_slot] == entry.id
	var available := CharacterCatalog.is_unlocked(str(entry.id))
	var accent := Color(entry.accent) if available else UiArt.MUTED
	if card.has_focus() or card.is_hovered(): card.draw_rect(Rect2(0,0,card.size.x,card.size.y),Color(.025,.04,.043,.28))
	if selected: card.draw_line(Vector2(1,13),Vector2(1,59),UiArt.AMBER,2)
	draw_selection_portrait(card,entry.id,Rect2(8,3,66,66),elapsed)
	UiArt.text(card,Vector2(87,28),CharacterCatalog.selection_title(entry.id),21,accent,UiArt.MENU_FONT)
	var detail: String = L.text(str(entry.detail)).split(" · ")[0] if available else CharacterCatalog.unlock_hint(str(entry.id))
	var lines := UiArt.wrap_text(detail,220,12)
	for index in mini(2,lines.size()): UiArt.text(card,Vector2(87,48+index*16),lines[index],12,UiArt.MUTED)
	if available:
		for slot in player_count:
			if game.selected_characters[slot]==entry.id: UiArt.text(card,Vector2(285,28),L.format("P%d",slot+1),12,UiArt.AMBER)
	else:
		UiArt.icon(card,"lock",Vector2(308,18),15,UiArt.MUTED)

static func draw_selection_portrait(node: CanvasItem, id: String, rect: Rect2, time: float) -> void:
	if CharacterCatalog.is_unlocked(id):
		draw_portrait(node, id, rect, time)
	else:
		draw_missing_portrait(node, rect)

static func draw_missing_portrait(node: CanvasItem, rect: Rect2) -> void:
	# Every missing slot uses the same anonymous marks: no equipment, profile,
	# personal colour or animation can identify an undiscovered character.
	var center := rect.get_center()
	var unit := rect.size.x / 96.0
	for row in 16:
		var width := float(19 + (row * 13) % 29) * unit
		var alpha := .13 + float((row * 7) % 5) * .024
		node.draw_rect(Rect2(center + Vector2(-width * .5, (row - 8) * 4.0 * unit), Vector2(width, 2.0 * unit)), Color(.30, .35, .33, alpha))
	UiArt.centered(node, center + Vector2(0, 13 * unit), "?", maxi(15, roundi(36 * unit)), Color(.57, .59, .52, .65))

static func draw_portrait(node: CanvasItem,id: String,rect: Rect2,time: float) -> void:
	var performance := portrait_performance(id,time)
	if not str(performance.gesture).is_empty():
		var pose := PoseArt.sample(performance.gesture,float(performance.progress),0.0,Vector2(24,-13),id)
		var scale_factor := minf(rect.size.x/77.0,rect.size.y/77.0)
		var origin := rect.get_center()-Vector2(38.5,38.5)*scale_factor
		node.draw_set_transform(origin+Vector2(32,73)*scale_factor,0,Vector2.ONE*scale_factor)
		PoseArt.draw_identity_pose(node,pose,id)
		node.draw_set_transform(Vector2.ZERO)
		return
	var frame := int(time*3.0*Personality.playback_rate(id,"idle"))%6
	var region := Rect2(frame*112+16,17,77,77)
	# These are the exact runtime body and hand frames, including silhouette,
	# face, clothes and headwear. Local player slots do not change identity.
	node.draw_texture_rect_region(IdentityArt.body(id),rect,region)
	node.draw_texture_rect_region(IdentityArt.arms(id),rect,region)

static func portrait_performance(id: String,time: float) -> Dictionary:
	# The same authored gestures appear in the menu, selection and online lobby.
	# Preview timing is deterministic and never drives a live worker's idle clock.
	var gestures := Personality.gestures(id)
	var cycle := 0.0
	for gesture in gestures:
		cycle += 2.4+Personality.duration(gesture)
	var identity_index := 0
	for index in CharacterCatalog.CHARACTERS.size():
		if str(CharacterCatalog.CHARACTERS[index].id)==id: identity_index = index
	var offset := float(identity_index)*1.1
	var clock := fposmod(maxf(0,time)+offset,cycle)
	for gesture in gestures:
		if clock<2.4:
			return {"gesture":"","progress":0.0}
		clock -= 2.4
		var duration := Personality.duration(gesture)
		if clock<duration:
			return {"gesture":gesture,"progress":clock/duration}
		clock -= duration
	return {"gesture":"","progress":0.0}

func refresh_locale() -> void:
	_refresh()
	queue_redraw()
