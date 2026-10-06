extends Control
## Real friend-service state, explicit actions and the existing industrial skin.
const L := preload("res://scripts/locale_text.gd")
const SocialArt := preload("res://scripts/social_ui_art.gd")
const Focus := preload("res://scripts/ui_focus_navigation.gd")
const TABS := {"friends":"Freunde","requests":"Anfragen","invitations":"Einladungen","blocked":"Blockiert"}
var game
var hud
var social: Node
var tab := "friends"
var name_field: LineEdit
var server_field: LineEdit
var friend_field: LineEdit
var code_field: LineEdit
var save_name_button: Button
var connect_button: Button
var retry_button: Button
var add_button: Button
var copy_button: Button
var close_button: Button
var tab_buttons: Dictionary = {}
var list_scroll: ScrollContainer
var list_box: VBoxContainer
var row_buttons: Dictionary = {}
var confirmation: Control
var _pending_action := ""
var _pending_id := ""
var _pending_service := ""
var _previous_focus: WeakRef
var _signature := ""
var _clock := 0.0
var _notice := ""
var _friend_request_code := ""
var decoration: Control
var contact_menu: PopupMenu
var contact_buttons: Dictionary = {}
var _landscape: Dictionary = {}
var _contact_id := ""
var _contact_service := ""
var show_service_options := false
var server_options_button: Button
var _focus_signature := ""

func _ready() -> void:
	name = "SocialPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = Vector2(1440,900)
	_landscape = SocialArt.create_landscape(self, game, hud, str(hud.scenario_options.get("environment", "sector07")))
	decoration = Control.new()
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decoration.draw.connect(_draw_foreground)
	add_child(decoration)
	if not is_instance_valid(social): social = game.social if "social" in game and is_instance_valid(game.social) else get_node_or_null("/root/SocialHub")
	name_field = _field(Rect2(140,203,406,42),"Dein Anzeigename",str(social.get("display_name")) if is_instance_valid(social) else "",24)
	save_name_button = _button("Name übernehmen",Rect2(140,256,406,36),_save_name)
	code_field = _field(Rect2(140,337,282,40),"Freundescode",str(social.get("friend_code")) if is_instance_valid(social) else "",32)
	code_field.editable = false
	code_field.focus_mode = Control.FOCUS_NONE
	copy_button = _button("Kopieren",Rect2(434,337,112,40),_copy_code)
	friend_field = _field(Rect2(140,464,406,42),"Freundescode eingeben", "",64)
	friend_field.text_submitted.connect(func(_value: String): _add_friend())
	add_button = _button("Freund hinzufügen",Rect2(140,516,406,38),_add_friend)
	server_field = _field(Rect2(140,610,406,40),"Adresse des Freundesdienstes",str(social.get("server_url")) if is_instance_valid(social) else "",512)
	connect_button = _button("Speichern & verbinden",Rect2(140,664,212,36),_connect)
	retry_button = _button("Erneut verbinden",Rect2(364,664,182,36),_retry)
	server_options_button = _button("Serveroptionen", Rect2(140, 570, 292, 36), _toggle_service_options)
	SocialArt.button(server_options_button, 15, "settings")
	close_button = _button("Zurück · Esc / F7",Rect2(1070,93,230,40),hud._close_social)
	for index in TABS.size():
		var id: String = TABS.keys()[index]
		var button := _button(TABS[id],Rect2(588+index*179,160,166,40),func(): select_tab(id))
		button.toggle_mode = true
		tab_buttons[id] = button
	list_scroll = ScrollContainer.new()
	list_scroll.position = Vector2(588,219)
	list_scroll.size = Vector2(712,530)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	list_scroll.follow_focus = true
	add_child(list_scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation",10)
	list_scroll.add_child(list_box)
	contact_menu = PopupMenu.new()
	contact_menu.name = "FriendActions"
	contact_menu.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	SocialArt.popup(contact_menu)
	contact_menu.id_pressed.connect(_contact_action)
	contact_menu.popup_hide.connect(_contact_menu_closed)
	add_child(contact_menu)
	var service: Node = social
	social = null
	bind_social(service)
	friend_field.text_changed.connect(func(_value: String): _refresh())
	_refresh()
	close_button.grab_focus.call_deferred()

func bind_social(service: Node) -> void:
	if social==service: return
	if is_instance_valid(social):
		if social.has_signal("changed") and social.is_connected("changed",_refresh): social.disconnect("changed",_refresh)
		if social.has_signal("invite_received") and social.is_connected("invite_received",_invite_received): social.disconnect("invite_received",_invite_received)
	social = service
	if is_instance_valid(social):
		if social.has_signal("changed"): social.changed.connect(_refresh)
		if social.has_signal("invite_received"): social.invite_received.connect(_invite_received)
	_signature = ""
	_refresh()

func _invite_received(_invite: Dictionary) -> void:
	_refresh()

func _field(rect: Rect2,placeholder: String,value: String,limit: int) -> LineEdit:
	var field := LineEdit.new()
	field.position = rect.position
	field.size = rect.size
	field.max_length = limit
	field.text = value
	field.placeholder_text = L.text(placeholder)
	field.set_meta("placeholder_source",placeholder)
	SocialArt.field(field, 16)
	add_child(field)
	return field

func _button(title: String,rect: Rect2,callback: Callable,parent: Node = self,font_size: int = 13) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.text = L.text(title)
	button.set_meta("source_text",title)
	var glyph := "invite" if title == "Einladen" else "copy" if title == "Kopieren" else "back" if title.begins_with("Zurück") else "add" if title == "Freund hinzufügen" else ""
	SocialArt.button(button, font_size, glyph)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _online_service() -> bool:
	return is_instance_valid(social) and str(social.get("connection_state"))=="online"

func _save_name() -> void:
	if not is_instance_valid(social): return
	if social.set_display_name(name_field.text):
		_notice = "Name übernommen."
		name_field.text = str(social.display_name)
	else: _notice = str(social.error_message)
	_refresh()

func _connect() -> void:
	if not is_instance_valid(social): return
	if social.configure_server(server_field.text):
		server_field.text = str(social.server_url)
		social.connect_service()
	_notice = ""
	_refresh()

func _retry() -> void:
	if not is_instance_valid(social): return
	if str(social.connection_state)=="online": social.disconnect_service()
	else: social.connect_service()
	_notice = ""
	_refresh()

func _toggle_service_options() -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	var closing_focused_options := show_service_options and focus_owner in [server_field, connect_button]
	show_service_options = not show_service_options
	_refresh()
	if closing_focused_options: server_options_button.grab_focus.call_deferred()

func _add_friend() -> void:
	if not _online_service() or friend_field.text.strip_edges().is_empty(): return
	if social.add_friend(friend_field.text.strip_edges()):
		_friend_request_code = friend_field.text.strip_edges().to_upper().replace("-", "").replace(" ", "")
		friend_field.text = ""
		_notice = "Freundesanfrage wird gesendet …"
	else: _notice = str(social.error_message)
	_refresh()

func _copy_code() -> void:
	if is_instance_valid(social) and not str(social.friend_code).is_empty():
		DisplayServer.clipboard_set(str(social.friend_code))
		_notice = "Freundescode kopiert."
		queue_redraw()

func select_tab(id: String) -> void:
	if id not in TABS: return
	tab = id
	_signature = ""
	_refresh()
	list_scroll.scroll_vertical = 0

func _can_invite() -> bool:
	var session: Node = game.network
	if not _online_service() or game.started or not is_instance_valid(session) or not session.active or not session.is_host or str(session.state)!="lobby" or bool(session.get("_loading")): return false
	return session.has_method("connected_player_count") and int(session.connected_player_count())<int(session.max_players)

func _can_join() -> bool:
	return _online_service() and not game.started and (not is_instance_valid(game.network) or not game.network.active or game.network.state in ["offline", "error"])

func _action(action: String,id: String) -> void:
	if not _online_service(): return
	if action in ["accept", "decline"] and not social.requests.any(func(row): return str(row.get("code", "")) == id): return
	if action == "cancel_request" and not _rows("requests").any(func(row): return row.get("direction") == "outgoing" and str(row.get("code", "")) == id): return
	var success := false
	match action:
		"accept": success = bool(social.accept_friend(id))
		"decline": success = bool(social.decline_friend(id))
		"invite":
			var friend := _friend_row(id)
			if not _can_invite() or friend.is_empty() or str(friend.get("status", "offline")) == "offline": return
			success = bool(social.invite_friend(id))
		"decline_invite": success = bool(social.decline_invite(id))
		"unblock": success = bool(social.unblock_friend(id))
		"remove": success = bool(social.remove_friend(id))
		"cancel_request": success = bool(social.remove_friend(id))
		"block": success = bool(social.block_friend(id))
	if not success: _notice = str(social.error_message)
	else: _notice = "Einladung gesendet." if action=="invite" else ""
	_signature = ""
	_refresh()

func _confirm(action: String,id: String) -> void:
	if is_instance_valid(confirmation) and confirmation.visible: return
	_pending_action = action
	_pending_id = id
	_pending_service = str(social.server_url) if is_instance_valid(social) else ""
	var focus := get_viewport().gui_get_focus_owner()
	_previous_focus = weakref(focus) if is_instance_valid(focus) else null
	if not is_instance_valid(confirmation):
		confirmation = preload("res://scripts/session_action_panel.gd").new()
		confirmation.hud = hud
		confirmation.confirmed.connect(_confirmed)
		confirmation.canceled.connect(_cancel_confirmation)
		add_child(confirmation)
	confirmation.open("Freund entfernen?" if action=="remove" else "Freund blockieren?","Die Freundschaft wird entfernt." if action=="remove" else "Diese Person kann dir keine Anfragen oder Einladungen mehr senden.","Du kannst später wieder eine Anfrage senden." if action=="remove" else "Unter Blockiert kannst du die Sperre wieder aufheben.","Entfernen" if action=="remove" else "Blockieren")

func _confirmed() -> void:
	var action := _pending_action
	var id := _pending_id
	var same_service: bool = is_instance_valid(social) and str(social.server_url) == _pending_service
	_cancel_confirmation()
	if same_service: _action(action,id)

func _cancel_confirmation() -> void:
	var contact_id := _pending_id
	if is_instance_valid(confirmation): confirmation.hide()
	_pending_action = ""
	_pending_id = ""
	_pending_service = ""
	var focus: Object = _previous_focus.get_ref() if _previous_focus!=null else null
	if not is_instance_valid(focus) or not focus is Control or not focus.is_visible_in_tree() or (focus is BaseButton and focus.disabled):
		focus = contact_buttons.get(contact_id, tab_buttons[tab])
	if is_instance_valid(focus): focus.grab_focus.call_deferred()

func _join(id: String) -> void:
	if not _can_join():
		_notice = "Verlasse zuerst deine laufende Schicht oder deinen Online-Raum."
		queue_redraw()
		return
	var invitation: Dictionary = social.take_invite(id)
	if invitation.is_empty():
		_notice = "Die Einladung ist abgelaufen oder nicht mehr verfügbar."
		_signature = ""
		_refresh()
		return
	game.network.join_room(str(invitation.get("relay_url","")),str(invitation.get("room_code","")))
	hud._open_network()

func _refresh() -> void:
	if not is_instance_valid(list_box): return
	var online := _online_service()
	if not _friend_request_code.is_empty() and is_instance_valid(social):
		if social.has_method("is_friend_request_pending") and social.is_friend_request_pending(_friend_request_code):
			_notice = "Freundesanfrage wird gesendet …"
		else:
			var confirmed := _rows("requests").any(func(row): return row.get("direction") == "outgoing" and str(row.get("code", "")) == _friend_request_code)
			_notice = "Freundesanfrage gesendet." if confirmed else str(social.error_message)
			_friend_request_code = ""
	add_button.disabled = not online or friend_field.text.strip_edges().is_empty()
	copy_button.disabled = not is_instance_valid(social) or str(social.get("friend_code")).is_empty()
	connect_button.disabled = not is_instance_valid(social) or str(social.get("connection_state"))=="connecting"
	retry_button.disabled = not is_instance_valid(social) or str(social.get("connection_state"))=="connecting" or str(social.get("server_url")).is_empty()
	retry_button.text = L.text("Trennen" if online else "Erneut verbinden")
	server_field.visible = show_service_options
	connect_button.visible = show_service_options
	if is_instance_valid(social): code_field.text = _display_code(str(social.friend_code))
	for id: String in TABS:
		var count := _rows(id).size()
		tab_buttons[id].text = L.format("%s · %d",[TABS[id],count]) if count>0 else L.text(TABS[id])
		tab_buttons[id].set_pressed_no_signal(id==tab)
	var rows := _rows(tab)
	var expiry_bucket := floori(Time.get_unix_time_from_system()/10.0) if tab=="invitations" else 0
	var signature := JSON.stringify(rows)+tab+L.current_locale()+str(online)+str(_can_invite())+str(_can_join())+str(expiry_bucket)
	if signature!=_signature:
		_signature = signature
		var scroll_before := list_scroll.scroll_vertical
		var focus := get_viewport().gui_get_focus_owner()
		var focus_key := str(focus.get_meta("social_focus_key","")) if is_instance_valid(focus) else ""
		for child in list_box.get_children():
			list_box.remove_child(child)
			child.queue_free()
		row_buttons.clear()
		contact_buttons.clear()
		for row: Dictionary in rows: _make_row(row)
		if not focus_key.is_empty():
			var restored_focus := false
			for controls: Array in row_buttons.values():
				for button: Button in controls:
					if str(button.get_meta("social_focus_key",""))==focus_key and not button.disabled:
						button.grab_focus.call_deferred()
						restored_focus = true
			if not restored_focus: tab_buttons[tab].grab_focus.call_deferred()
		list_scroll.set_deferred("scroll_vertical",scroll_before)
	queue_redraw()
	if is_instance_valid(decoration): decoration.queue_redraw()
	_refresh_contact_menu()
	_wire_focus()

func _focus_controls() -> Array[Control]:
	var candidates: Array[Control] = [close_button, name_field, save_name_button, copy_button, friend_field, add_button, server_options_button, server_field, connect_button, retry_button]
	for id: String in TABS: candidates.append(tab_buttons[id])
	for controls: Array in row_buttons.values():
		# The contact name precedes its invitation action in reading order.
		for control: Control in controls: candidates.append(control)
	var bar := list_scroll.get_v_scroll_bar()
	bar.focus_mode = Control.FOCUS_ALL
	candidates.append(bar)
	return Focus.available(self, candidates)

func _wire_focus() -> void:
	if is_instance_valid(confirmation) and confirmation.visible: return
	var controls := _focus_controls()
	var signature := Focus.signature(controls)
	if signature == _focus_signature: return
	_focus_signature = signature
	Focus.wire(controls)
	var focus_owner := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus_owner) and is_ancestor_of(focus_owner) and not focus_owner in controls: tab_buttons[tab].grab_focus.call_deferred()

func _rows(id: String) -> Array:
	if not is_instance_valid(social): return []
	if id == "requests":
		var rows: Array[Dictionary] = []
		for incoming: Dictionary in social.requests:
			var row := incoming.duplicate()
			row["direction"] = "incoming"
			rows.append(row)
		if "outgoing_requests" in social:
			for outgoing: Dictionary in social.outgoing_requests:
				var row := outgoing.duplicate()
				row["direction"] = "outgoing"
				row["id"] = "outgoing/" + str(row.get("code", ""))
				rows.append(row)
		return rows
	var value: Variant = social.get(id)
	return value if value is Array else []

func _display_code(value: String) -> String:
	return value.substr(0,4)+"-"+value.substr(4,4)+"-"+value.substr(8,4) if value.length()==12 else value

func _label(parent: Node,value: String,rect: Rect2,font_size: int,color: Color = UiArt.IVORY) -> Label:
	var label := Label.new()
	label.text = value
	label.position = rect.position
	label.size = rect.size
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_override("font",UiArt.FONT)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label

func _make_row(data: Dictionary) -> void:
	var row := Control.new()
	row.custom_minimum_size = Vector2(690,108)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.draw.connect(func(): row.draw_line(Vector2(12,107),Vector2(678,107),Color(UiArt.MUTED,.12),1))
	list_box.add_child(row)
	var id := str(data.get("id",data.get("code","")))
	var contact_name := str(data.get("name",data.get("code","")))
	if tab != "friends": _label(row,contact_name,Rect2(12,10,424,26),19)
	var online := _online_service()
	var controls: Array[Button] = []
	match tab:
		"friends":
			var contact := _button("", Rect2(0, 2, 482, 35), func(): _open_contact(id), row, 20)
			contact.text = contact_name
			contact.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			SocialArt.button(contact, 20, "crew", 12)
			contact.set_meta("social_focus_key", id + "/contact")
			contact_buttons[id] = contact
			var status: String = str({"offline":"Offline","menu":"Im Hauptmenü","lobby":"Im Online-Raum","playing":"Spielt gerade"}.get(str(data.get("status","offline")),"Offline"))
			if not online: status = "Status unbekannt · Dienst offline"
			var location := str(data.get("environment",""))
			if online and not location.is_empty() and str(ScenarioCatalog.environment(location).id)==location: status = L.text(status)+" · "+L.text(str(ScenarioCatalog.environment(location).title)).capitalize()
			else: status = L.text(str(status))
			_label(row,status,Rect2(12,43,470,21),13,UiArt.GREEN if online and str(data.get("status","offline"))!="offline" else UiArt.MUTED)
			_label(row,_display_code(str(data.get("code",""))),Rect2(12,74,340,19),11,UiArt.MUTED)
			var invite := _button("Einladen",Rect2(500,9,176,32),func(): _action("invite",id),row,12)
			invite.disabled = not _can_invite() or str(data.get("status","offline"))=="offline"
			invite.tooltip_text = L.text("Erstelle als Gastgeber einen Online-Raum mit einem freien Platz.") if not _can_invite() else L.text("In deinen Online-Raum einladen.")
			controls.append(invite)
			controls.append(contact)
		"requests":
			var outgoing := str(data.get("direction", "incoming")) == "outgoing"
			_label(row,L.text("Von dir gesendet · offen" if outgoing else "An dich gesendet"),Rect2(12,43,390,24),13,UiArt.AMBER if outgoing else UiArt.MUTED)
			_label(row,_display_code(str(data.get("code",""))),Rect2(12,75,370,19),11,UiArt.MUTED)
			if outgoing:
				var code := str(data.get("code", ""))
				controls.append(_button("Anfrage zurückziehen",Rect2(406,65,270,32),func(): _action("cancel_request",code),row,12))
			else:
				controls.append(_button("Annehmen",Rect2(406,65,128,32),func(): _action("accept",id),row,12))
				controls.append(_button("Ablehnen",Rect2(546,65,130,32),func(): _action("decline",id),row,12))
		"invitations":
			var seconds := maxi(0,ceili(float(data.get("expires",0))-Time.get_unix_time_from_system()))
			_label(row,L.format("Einladung · noch %d Sekunden",seconds),Rect2(12,42,440,24),12,UiArt.AMBER)
			var join_button := _button("Beitreten",Rect2(406,65,128,32),func(): _join(id),row,12)
			join_button.disabled = not _can_join() or seconds<=0
			join_button.tooltip_text = L.text("Verlasse zuerst deine laufende Schicht oder deinen Online-Raum.") if not _can_join() else L.text("Diesem Online-Raum beitreten.")
			controls.append(join_button)
			controls.append(_button("Ablehnen",Rect2(546,65,130,32),func(): _action("decline_invite",id),row,12))
		"blocked":
			_label(row,str(data.get("code","")),Rect2(12,43,430,24),12,UiArt.MUTED)
			controls.append(_button("Entsperren",Rect2(500,65,176,32),func(): _action("unblock",id),row,12))
	for button in controls:
		if not button.has_meta("social_focus_key"): button.set_meta("social_focus_key",id+"/"+str(button.get_meta("source_text","")))
		if str(button.get_meta("source_text","")) not in ["Einladen","Beitreten"] and button != contact_buttons.get(id): button.disabled = not online
	row_buttons[id] = controls

func _open_contact(id: String) -> void:
	var data := _friend_row(id)
	if data.is_empty(): return
	_contact_id = id
	_contact_service = str(social.server_url)
	contact_menu.clear()
	contact_menu.add_item(str(data.get("name", id)), -1)
	contact_menu.set_item_disabled(0, true)
	contact_menu.add_separator()
	contact_menu.add_icon_item(SocialArt.icon("invite"), L.text("Einladen"), 1)
	contact_menu.set_item_disabled(contact_menu.item_count - 1, not _can_invite() or str(data.get("status", "offline")) == "offline")
	contact_menu.add_icon_item(SocialArt.icon("chat"), L.text("Nachricht schreiben"), 2)
	contact_menu.set_item_disabled(contact_menu.item_count - 1, _crew_slot_for_friend(id) == 0)
	contact_menu.add_separator()
	contact_menu.add_icon_item(SocialArt.icon("friends"), L.text("Entfernen"), 3)
	contact_menu.set_item_disabled(contact_menu.item_count - 1, not _online_service())
	contact_menu.add_icon_item(SocialArt.icon("block"), L.text("Blockieren"), 4)
	contact_menu.set_item_disabled(contact_menu.item_count - 1, not _online_service())
	var button: Button = contact_buttons.get(id)
	if button != null:
		var at := button.get_screen_transform() * Vector2(button.size.x, 0)
		contact_menu.popup(Rect2i(Vector2i(at), Vector2i(248, 0)))

func _friend_row(id: String) -> Dictionary:
	for row: Dictionary in _rows("friends"):
		if str(row.get("code", "")) == id: return row
	return {}

func _refresh_contact_menu() -> void:
	if not is_instance_valid(contact_menu) or not contact_menu.visible: return
	var friend := _friend_row(_contact_id)
	if friend.is_empty() or not is_instance_valid(social) or str(social.server_url) != _contact_service:
		contact_menu.hide()
		return
	contact_menu.set_item_disabled(contact_menu.get_item_index(1), not _can_invite() or str(friend.get("status", "offline")) == "offline")
	contact_menu.set_item_disabled(contact_menu.get_item_index(2), _crew_slot_for_friend(_contact_id) == 0)
	for action in [3,4]: contact_menu.set_item_disabled(contact_menu.get_item_index(action), not _online_service())

func _crew_slot_for_friend(code: String) -> int:
	if not is_instance_valid(game.network) or not game.network.has_method("crew_members") or not game.network.has_method("private_chat_available"): return 0
	for member: Dictionary in game.network.crew_members():
		var slot := int(member.get("player_id", 0))
		if str(member.get("friend_code", "")) == code and str(member.get("friend_service", "")) == str(social.server_url) and game.network.private_chat_available(slot): return slot
	return 0

func _contact_action(action: int) -> void:
	if not is_instance_valid(social) or str(social.server_url) != _contact_service or _friend_row(_contact_id).is_empty(): return
	match action:
		1: _action("invite", _contact_id)
		2:
			var slot := _crew_slot_for_friend(_contact_id)
			if slot > 0 and is_instance_valid(hud.chat_panel) and hud.chat_panel.has_method("open_private"):
				hud._close_social()
				hud.chat_panel.open_private.call_deferred(slot)
		3:
			if _online_service(): _confirm("remove", _contact_id)
		4:
			if _online_service(): _confirm("block", _contact_id)

func _contact_menu_closed() -> void:
	if is_instance_valid(confirmation) and confirmation.visible: return
	if hud.overlay != "friends": return
	var button: Button = contact_buttons.get(_contact_id)
	if button != null and button.is_visible_in_tree(): button.grab_focus.call_deferred()
	else: tab_buttons[tab].grab_focus.call_deferred()

func _process(delta: float) -> void:
	_clock += delta
	if _landscape.get("bounds", Rect2()) != SocialArt.bounds(hud): SocialArt.layout_landscape(_landscape, hud)
	if _clock>=0.5:
		_clock = 0.0
		_refresh()

func _draw() -> void:
	draw_rect(SocialArt.bounds(hud), Color("111c20"))

func _draw_foreground() -> void:
	SocialArt.reading_shade(decoration, SocialArt.bounds(hud), 540, 760)
	UiArt.text(decoration,Vector2(140,114),"Freunde & Crew",34,UiArt.IVORY,UiArt.MENU_FONT)
	UiArt.text(decoration,Vector2(141,143),"Freundescode teilen, Crew finden und gemeinsam loslegen.",12,UiArt.MUTED)
	UiArt.text(decoration,Vector2(140,188),"Dein Anzeigename",13,UiArt.MUTED)
	UiArt.text(decoration,Vector2(140,322),"Dein Freundescode",13,UiArt.AMBER)
	UiArt.text(decoration,Vector2(140,402),"Teile diesen Code mit deinen Freunden.",12,UiArt.MUTED)
	UiArt.text(decoration,Vector2(140,449),"Neue Freundschaft",13,UiArt.MUTED)
	var state := str(social.get("connection_state")) if is_instance_valid(social) else "offline"
	var status: String = str({"offline":"Freundesdienst ist nicht verbunden.","connecting":"Verbindung zum Freundesdienst wird aufgebaut …","online":"Mit dem Freundesdienst verbunden.","error":"Freundesdienst ist nicht erreichbar."}.get(state,"Freundesdienst ist nicht verbunden."))
	if not is_instance_valid(social) or str(social.get("server_url")).is_empty(): status = "Trage die Adresse des Freundesdienstes ein und verbinde dich."
	var detail := _notice
	if detail.is_empty() and is_instance_valid(social): detail = str(social.error_message)
	var lines := UiArt.wrap_text(str(status),406,12)
	for index in mini(2,lines.size()): UiArt.text(decoration,Vector2(140,730+index*18),lines[index],12,UiArt.GREEN if state=="online" else UiArt.MUTED)
	var notes := UiArt.wrap_text(detail,406,11)
	for index in mini(2,notes.size()): UiArt.text(decoration,Vector2(140,783+index*16),notes[index],11,UiArt.AMBER)
	if _rows(tab).is_empty():
		var empty := {"friends":"Noch keine Freunde. Teile deinen Code oder sende eine Anfrage.","requests":"Keine offenen Freundesanfragen.","invitations":"Keine offenen Einladungen.","blocked":"Keine blockierten Personen."}
		var empty_lines := UiArt.wrap_text(str(empty[tab]),622,16)
		for index in empty_lines.size(): UiArt.text(decoration,Vector2(610,271+index*25),empty_lines[index],16,UiArt.MUTED)
	var hint := "Einladungen sind nur aus einem Gastgeber-Raum mit freien Plätzen möglich."
	var hint_lines := UiArt.wrap_text(hint,700,12)
	for index in mini(2,hint_lines.size()): UiArt.text(decoration,Vector2(588,783+index*18),hint_lines[index],12,UiArt.MUTED)

func refresh_locale() -> void:
	for control in [name_field,server_field,friend_field,code_field]:
		if is_instance_valid(control): control.placeholder_text = L.text(str(control.get_meta("placeholder_source","")))
	for button in [save_name_button,connect_button,add_button,copy_button,close_button,server_options_button]:
		if is_instance_valid(button): button.text = L.text(str(button.get_meta("source_text","")))
	if is_instance_valid(confirmation): confirmation.refresh_locale()
	_signature = ""
	_refresh()
