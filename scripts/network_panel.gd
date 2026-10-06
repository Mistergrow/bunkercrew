extends Control
const L := preload("res://scripts/locale_text.gd")
const SocialArt := preload("res://scripts/social_ui_art.gd")
## A real room, an open crew list and one shared living landscape.
var game
var hud
var elapsed := 0.0
var show_server_options := false
var direct_mode := false
var server_field: LineEdit
var connection_mode_button: Button
var public_address_field: LineEdit
var code_field: LineEdit
var create_button: Button
var join_button: Button
var copy_button: Button
var copy_direct_button: Button
var copy_internet_button: Button
var capacity_button: Button
var scene_button: Button
var start_button: Button
var resume_button: Button
var leave_button: Button
var character_buttons: Array[Button] = []
var character_scroll: ScrollContainer
var character_content: VBoxContainer
var friends_button: Button
var chat_button: Button
var server_options_button: Button
var crew_buttons: Array[Button] = []
var crew_rows: Dictionary = {}
var member_menu: PopupMenu
var decoration: Control
var _saved_available := false
var _landscape: Dictionary = {}
var _refresh_clock := 0.0
var _visual_clock := 0.0
var _context_slot := 0
var _context_identity: Dictionary = {}
var _focus_signature := ""
var _notice := ""
var _notice_until := 0.0
var _friend_request_code := ""

func _ready() -> void:
	name = "NetworkPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = Vector2(1440, 900)
	_landscape = SocialArt.create_landscape(self, game, hud, str(hud.scenario_options.get("environment", "sector07")))
	decoration = Control.new()
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decoration.draw.connect(_draw_foreground)
	add_child(decoration)
	friends_button = _button("Freunde · F7", Rect2(962, 102, 190, 43), hud._open_social, 16, "friends")
	chat_button = _button("Crew-Chat", Rect2(1156, 102, 190, 43), func(): hud.chat_panel.open(), 16, "chat")
	server_options_button = _button("Serveroptionen", Rect2(82, 177, 270, 36), _toggle_server_options, 14, "settings")
	direct_mode = _transport_fixed() and str(game.network.relay_url).is_empty()
	server_field = _field(Rect2(100, 219, 486, 40), "Relay-Server", str(game.network.relay_url) if _transport_fixed() else _default_relay_url())
	server_field.text_changed.connect(func(value: String):
		if _transport_fixed(): return
		direct_mode = value.strip_edges().is_empty()
		_refresh())
	public_address_field = _field(Rect2(602, 219, 306, 40), "Öffentliche IPv4 (optional)", str(game.network.advertised_address) if "advertised_address" in game.network else "")
	public_address_field.max_length = 15
	public_address_field.tooltip_text = L.text("Nur bei manueller Router-Freigabe: öffentliche IPv4 dieses Anschlusses. UDP 24777 muss an diesen Rechner weitergeleitet sein. Leer lassen für automatische Freigabe.")
	connection_mode_button = _button("", Rect2(368, 177, 420, 36), _toggle_connection_mode, 16, "settings")
	capacity_button = _button("", Rect2(432, 275, 256, 48), _change_capacity, 17, "crew")
	create_button = _button("Raum erstellen", Rect2(82, 269, 334, 54), _host, 23, "host")
	code_field = _field(Rect2(100, 344, 526, 46), "Beitrittscode", "")
	code_field.max_length = 64
	code_field.text_submitted.connect(func(_value: String): _join())
	code_field.text_changed.connect(func(value: String):
		var normalized := value.to_upper().replace(" ", "")
		if normalized != value:
			var caret := code_field.caret_column
			code_field.text = normalized
			code_field.caret_column = mini(caret, normalized.length())
		_refresh())
	join_button = _button("Beitreten", Rect2(644, 344, 224, 46), _join, 19, "join")
	copy_button = _button("Code kopieren", Rect2(82, 318, 262, 42), _copy_room_code, 15, "copy")
	copy_direct_button = _button("Direktcode kopieren", Rect2(352, 318, 246, 42), _copy_direct_code, 15, "copy")
	copy_direct_button.tooltip_text = L.text("Falls der kurze LAN-Code nicht gefunden wird: diesen vollständigen Code im selben Netzwerk verwenden.")
	copy_internet_button = _button("Internetcode kopieren", Rect2(604, 318, 254, 42), _copy_internet_code, 15, "copy")
	for slot in 4:
		var button := _button("", Rect2(82, 526 + slot * 55, 612, 52), func(): _open_member(slot + 1), 20)
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		SocialArt.button(button, 20, "", 74, 20)
		button.draw.connect(func(): _draw_member(button, slot + 1))
		crew_buttons.append(button)
	character_scroll = ScrollContainer.new()
	character_scroll.name = "CharacterChoices"
	character_scroll.position = Vector2(1022,257)
	character_scroll.size = Vector2(324,446)
	character_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	character_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	character_scroll.follow_focus = false
	add_child(character_scroll)
	character_content = VBoxContainer.new()
	character_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_content.add_theme_constant_override("separation",4)
	character_scroll.add_child(character_content)
	for index in CharacterCatalog.CHARACTERS.size():
		var entry: Dictionary = CharacterCatalog.CHARACTERS[index]
		var button := _button(CharacterCatalog.selection_title(str(entry.id)), Rect2(0,0,306,61), func(): _select(str(entry.id)), 20,"",character_content)
		button.custom_minimum_size = Vector2(0,61)
		SocialArt.button(button, 20, "", 18, 23)
		button.draw.connect(func(): _draw_character(button, entry))
		button.focus_entered.connect(_reveal_character.bind(button))
		character_buttons.append(button)
	scene_button = _button("Schauplatz wählen", Rect2(82, 795, 342, 54), func(): hud._open_scenario_selection(maxi(2, _member_count())), 20, "location")
	leave_button = _button("Zurück", Rect2(710, 803, 252, 46), _leave, 17, "back")
	start_button = _button("Gemeinsam starten", Rect2(984, 793, 378, 58), _primary_action, 23, "play")
	resume_button = _button("Fortsetzen", Rect2(1196, 793, 166, 58), func(): game.network.resume_campaign(), 19, "play")
	resume_button.tooltip_text = L.text("Gespeicherte Crew, Fahrzeug und Fracht des Gastgebers fortsetzen. Die gesamte Crew beginnt am letzten gesicherten Punkt.")
	_saved_available = "expedition" in game and is_instance_valid(game.expedition) and game.expedition.has_saved_campaign()
	member_menu = PopupMenu.new()
	member_menu.name = "CrewActions"
	member_menu.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	SocialArt.popup(member_menu)
	member_menu.id_pressed.connect(_member_action)
	member_menu.popup_hide.connect(_member_menu_closed)
	add_child(member_menu)
	if game.network.has_signal("changed"): game.network.changed.connect(_refresh)
	_refresh()
	_focus_initial.call_deferred()

func _focus_initial() -> void:
	# The room can be rebuilt behind a session question. Recheck at the actual
	# deferred callback, since a modal may also open after this panel's _ready.
	if not is_inside_tree() or not is_visible_in_tree() or is_queued_for_deletion(): return
	if is_instance_valid(hud) and hud.has_method("has_session_action") and hud.has_session_action(): return
	var target: Button = create_button if create_button.is_visible_in_tree() and not create_button.disabled else leave_button
	if is_instance_valid(target) and target.is_visible_in_tree() and not target.disabled: target.grab_focus()

func _process(delta: float) -> void:
	elapsed += delta
	_refresh_clock += delta
	if _refresh_clock >= .1:
		_refresh_clock = fmod(_refresh_clock, .1)
		_refresh()
		if _landscape.get("bounds", Rect2()) != SocialArt.bounds(hud): SocialArt.layout_landscape(_landscape, hud)
	_visual_clock += delta
	var reduced: bool = "weather" in game and is_instance_valid(game.weather) and game.weather.reduced_effects
	var interval := 1.0 / (12.0 if reduced else 30.0)
	if _visual_clock < interval: return
	_visual_clock = fmod(_visual_clock, interval)
	decoration.queue_redraw()
	for button in crew_buttons: button.queue_redraw()

func _field(rect: Rect2, placeholder: String, value: String) -> LineEdit:
	var field := LineEdit.new()
	field.position = rect.position
	field.size = rect.size
	field.placeholder_text = L.text(placeholder)
	field.set_meta("placeholder_source", placeholder)
	field.text = value
	SocialArt.field(field)
	add_child(field)
	return field

func _button(label: String, rect: Rect2, callback: Callable, font_size: int = 18, glyph: String = "", parent: Node=self) -> Button:
	var button := Button.new()
	button.text = L.text(label)
	button.set_meta("source_text", label)
	button.position = rect.position
	button.size = rect.size
	SocialArt.button(button, font_size, glyph)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _reveal_character(button: Button) -> void:
	character_scroll.ensure_control_visible(button)
	var top := floori(button.position.y)
	var bottom := ceili(button.position.y+button.size.y)
	var page := floori(character_scroll.size.y)
	if top<character_scroll.scroll_vertical: character_scroll.scroll_vertical = top
	elif bottom>character_scroll.scroll_vertical+page: character_scroll.scroll_vertical = bottom-page

func _toggle_server_options() -> void:
	show_server_options = not show_server_options
	_refresh()

func _default_relay_url() -> String:
	if game.network.has_method("default_relay_url"): return str(game.network.default_relay_url())
	return preload("res://scripts/social_hub.gd").default_server().trim_suffix("/social") + "/ws"

func _transport_fixed() -> bool:
	return game.network.active and game.network.state not in ["offline", "error"]

func _toggle_connection_mode() -> void:
	if _transport_fixed() or game.started: return
	direct_mode = not direct_mode
	server_field.text = "" if direct_mode else _default_relay_url()
	_refresh()

func connection_preferences() -> Dictionary:
	return {"server":server_field.text, "connection_mode":"direct" if direct_mode else "relay"}

func restore_connection_preferences(draft: Dictionary) -> void:
	# A live room keeps its actual transport. The old empty RAM draft was the
	# implicit default, whereas the new explicit Direct choice must survive.
	if _transport_fixed():
		direct_mode = str(game.network.relay_url).is_empty()
		server_field.text = str(game.network.relay_url)
	else:
		direct_mode = str(draft.get("connection_mode", "")) == "direct"
		var stored_server := str(draft.get("server", "")).strip_edges()
		server_field.text = "" if direct_mode else stored_server if not stored_server.is_empty() else _default_relay_url()
	_refresh()

func _member_count() -> int:
	if not _roster_confirmed(): return 0
	return game.network.connected_player_count() if game.network.has_method("connected_player_count") else (2 if game.network.peer_connected else 1)

func _roster_confirmed() -> bool:
	var network = game.network
	if not network.active or network.state in ["offline", "error", "connecting"]: return false
	# A relay seat can exist before the game's welcome. Cached slot/name data
	# likewise survives a retry; neither is an authenticated crew connection.
	if network.is_host: return network.state in ["lobby", "playing", "reconnecting"]
	if network.state not in ["lobby", "playing"] or not network.peer_connected: return false
	return bool(network.get("_authenticated")) if "_authenticated" in network else true

func _connection_pending() -> bool:
	var network = game.network
	return network.active and network.state not in ["offline", "error"] and (network.state in ["connecting", "reconnecting"] or not _roster_confirmed())

func crew_status() -> String:
	if not game.network.active or game.network.state in ["offline", "error"]:
		return L.text("Kein aktiver Raum")
	if not _roster_confirmed(): return L.text("Verbindung noch nicht bestätigt")
	return L.format("%d / %d verbunden", [_member_count(), _capacity()])

func _capacity() -> int:
	return int(game.network.max_players) if "max_players" in game.network else 2

func _change_capacity() -> void:
	if not "max_players" in game.network or game.started or _connection_pending() or (_transport_fixed() and not game.network.is_host): return
	var capacity := maxi(_member_count(), 2 if _capacity() >= 4 else _capacity() + 1)
	if game.network.has_method("set_capacity"): game.network.set_capacity(capacity)
	else: game.network.max_players = capacity
	_refresh()

func _host() -> void:
	if game.started or _transport_fixed(): return
	var relay := server_field.text.strip_edges()
	game.network.host_room(relay)
	if relay.is_empty() and not public_address_field.text.strip_edges().is_empty(): game.network.set_advertised_address(public_address_field.text.strip_edges())
	_refresh()

func _join() -> void:
	if game.started or _transport_fixed() or code_field.text.strip_edges().is_empty(): return
	var code := code_field.text.strip_edges().to_upper()
	var relay := server_field.text.strip_edges()
	# Full destination invitations explicitly identify a direct route, even
	# when the panel otherwise defaults to online relay rooms.
	var join_code := preload("res://scripts/network_join_code.gd")
	if join_code.is_lan_code(code) or bool(join_code.decode(code).get("ok", false)): relay = ""
	game.network.join_room(relay, code)
	_refresh()

func _select(id: String) -> void:
	if not _roster_confirmed() or game.network.state != "lobby" or not CharacterCatalog.is_unlocked(id): return
	if game.network.character_owner(id,int(game.network.local_player_id))>0: return
	var slot := clampi(int(game.network.local_player_id) - 1, 0, 3)
	if slot >= game.selected_characters.size(): return
	game.selected_characters[slot] = id
	game.network.send_command("character", {"id":id})
	_refresh()

func _start() -> void:
	if _roster_confirmed() and game.network.is_host and game.network.peer_connected and game.network.state == "lobby" and not game.started: game.network.start_match(ScenarioCatalog.validate(hud.scenario_options), game.selected_characters)

func _primary_action() -> void:
	if game.network.state == "error" and not game.started: _join()
	else: _start()

func _leave() -> void:
	var was_started: bool = game.started
	game.network.leave()
	if was_started: game.return_to_menu()
	hud.overlay = "menu"
	get_tree().paused = true

func _refresh() -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.network) or not is_instance_valid(create_button): return
	_update_friend_request_notice()
	var network = game.network
	var social_unread: int = hud.social_pending_count() if hud.has_method("social_pending_count") else 0
	friends_button.text = L.format("Freunde · %d", social_unread) if social_unread > 0 else L.text("Freunde · F7")
	chat_button.disabled = not _roster_confirmed() or not is_instance_valid(hud.chat_panel) or not hud.chat_panel.available()
	chat_button.text = L.format("Chat · %d", hud.chat_panel.unread) if is_instance_valid(hud.chat_panel) and hud.chat_panel.unread > 0 else L.text("Crew-Chat")
	var in_room: bool = _roster_confirmed() and not str(network.room_code).is_empty()
	var busy := _connection_pending()
	create_button.visible = not in_room and not game.started
	join_button.visible = not in_room and not game.started
	code_field.visible = not in_room and not game.started
	create_button.disabled = busy
	join_button.disabled = busy or code_field.text.strip_edges().is_empty()
	capacity_button.visible = not show_server_options and not game.started
	capacity_button.position.x = 682 if in_room else 432
	capacity_button.disabled = busy or (_transport_fixed() and not network.is_host)
	capacity_button.text = L.format("Spielerplätze: %d", _capacity())
	server_field.visible = show_server_options
	server_field.editable = not in_room and not busy and not game.started
	connection_mode_button.visible = show_server_options
	connection_mode_button.disabled = _transport_fixed() or game.started
	connection_mode_button.text = L.text("LAN · Direkt" if direct_mode else "Online · Relay")
	connection_mode_button.tooltip_text = L.text("Online-Räume laufen über den Relay-Server. Für LAN oder manuelle Router-Freigabe zu Direkt wechseln.")
	public_address_field.visible = show_server_options
	public_address_field.editable = not in_room and not busy and not game.started and server_field.text.strip_edges().is_empty()
	code_field.editable = not in_room and not busy and not game.started
	copy_button.visible = in_room
	var has_short_code := not _network_code("short_room_code").is_empty()
	copy_direct_button.visible = in_room and not _network_code("direct_code").is_empty() and (show_server_options or not has_short_code)
	copy_internet_button.visible = in_room and not _network_code("internet_code").is_empty() and (show_server_options or not has_short_code)
	copy_button.text = L.text("LAN-Code kopieren" if _primary_code_label() == "LAN-Code" else "Code kopieren")
	scene_button.disabled = not (_roster_confirmed() and network.is_host and network.state == "lobby" and not game.started)
	var retry_join: bool = network.state == "error" and not game.started
	start_button.visible = not game.started and (in_room or busy or retry_join)
	start_button.disabled = code_field.text.strip_edges().is_empty() if retry_join else not (_roster_confirmed() and network.is_host and network.peer_connected and network.state == "lobby")
	resume_button.visible = _roster_confirmed() and not game.started and network.is_host and network.state == "lobby" and _saved_available
	resume_button.disabled = not (network.peer_connected and network.state == "lobby")
	start_button.text = L.text("Erneut beitreten" if retry_join else ("Neue Schicht" if resume_button.visible else "Gemeinsam starten") if network.is_host else "Verbindung abwarten" if not _roster_confirmed() else "Warten auf Gastgeber")
	start_button.size.x = 204 if resume_button.visible else 378
	leave_button.text = L.text("Zum Hauptmenü" if game.started and network.state == "error" else "Abbrechen" if busy and not in_room else "Raum verlassen" if in_room else "Zurück")
	for index in character_buttons.size():
		var button := character_buttons[index]
		var id := str(CharacterCatalog.CHARACTERS[index].id)
		var occupying_player: int = network.character_owner(id,int(network.local_player_id))
		button.disabled = not _roster_confirmed() or network.state != "lobby" or not CharacterCatalog.is_unlocked(id) or occupying_player>0
		button.text = CharacterCatalog.selection_title(id)
		button.tooltip_text = L.format("Bereits von Spieler %d gewählt",occupying_player) if occupying_player>0 and CharacterCatalog.is_unlocked(id) else CharacterCatalog.selection_detail(id)
		button.add_theme_color_override("font_color", UiArt.AMBER if _local_character() == id else UiArt.IVORY)
		button.queue_redraw()
	_refresh_crew()
	_refresh_member_menu()
	var environment := str(hud.scenario_options.get("environment", "sector07"))
	if environment != str(_landscape.get("environment", "")):
		var old_clip: Variant = _landscape.get("clip")
		if is_instance_valid(old_clip):
			old_clip.hide()
			old_clip.queue_free()
		_landscape = SocialArt.create_landscape(self, game, hud, environment)
		if is_instance_valid(_landscape.get("clip")): move_child(_landscape.clip, 0)
	_wire_focus()

func _local_character() -> String:
	if game.selected_characters.is_empty(): return "mara"
	return str(game.selected_characters[clampi(int(game.network.local_player_id) - 1, 0, game.selected_characters.size() - 1)])

func _refresh_crew() -> void:
	crew_rows.clear()
	var confirmed := _roster_confirmed()
	var pending := _connection_pending() and not confirmed
	if confirmed and game.network.has_method("crew_members"):
		for member: Dictionary in game.network.crew_members(): crew_rows[int(member.get("player_id", 0))] = member
	var local_slot := maxi(1, int(game.network.local_player_id))
	for index in crew_buttons.size():
		var slot := index + 1
		if not crew_rows.has(slot):
			var connected: bool = confirmed and (game.network.is_player_connected(slot) if game.network.has_method("is_player_connected") else slot == 1 or slot == 2 and game.network.peer_connected)
			var selected := str(game.selected_characters[mini(index, game.selected_characters.size() - 1)]) if not game.selected_characters.is_empty() else "mara"
			var player_name := "P%d" % slot
			if "chat_names" in game.network: player_name = str(game.network.chat_names.get(str(slot), player_name))
			if slot == local_slot and "display_name" in game.network and not str(game.network.display_name).is_empty(): player_name = str(game.network.display_name)
			crew_rows[slot] = {"player_id":slot, "name":player_name, "character_id":selected, "connected":connected, "is_local":slot == local_slot, "is_host":slot == 1, "friend_code":""}
		var row: Dictionary = crew_rows[slot]
		var button := crew_buttons[index]
		button.visible = slot <= _capacity()
		button.disabled = not bool(row.get("connected", false))
		button.text = str(row.get("name", "P%d" % slot)) if not button.disabled else L.text("Gastgeber wird verbunden …" if pending and slot == 1 else "Dein Platz wird bestätigt …" if pending and slot == local_slot else "Freier Platz")
		button.tooltip_text = "" if button.disabled else L.text("Figur wählen" if bool(row.get("is_local", false)) else "Spieleraktionen")
		button.queue_redraw()
	if is_instance_valid(member_menu) and member_menu.visible and not _context_matches(crew_rows.get(_context_slot, {})): member_menu.hide()

func _open_member(slot: int) -> void:
	if not crew_rows.has(slot): return
	var member: Dictionary = crew_rows[slot]
	if not bool(member.get("connected", false)): return
	if bool(member.get("is_local", false)):
		for index in character_buttons.size():
			if str(CharacterCatalog.CHARACTERS[index].id) == _local_character() and not character_buttons[index].disabled:
				character_buttons[index].grab_focus()
				break
		return
	_context_slot = slot
	_context_identity = member.duplicate(true)
	member_menu.clear()
	member_menu.add_item(str(member.get("name", "P%d" % slot)), -1)
	member_menu.set_item_disabled(0, true)
	member_menu.add_separator()
	var muted := _member_flag("is_player_muted", slot)
	var blocked := _member_flag("is_player_blocked", slot)
	member_menu.add_icon_item(SocialArt.icon("mute" if not muted else "voice"), L.text("Stummschaltung aufheben" if muted else "Stummschalten"), 1)
	member_menu.set_item_disabled(member_menu.item_count - 1, not game.network.has_method("set_player_muted"))
	member_menu.add_icon_item(SocialArt.icon("block"), L.text("Blockierung aufheben" if blocked else "Blockieren"), 2)
	member_menu.set_item_disabled(member_menu.item_count - 1, not game.network.has_method("set_player_blocked"))
	member_menu.add_icon_item(SocialArt.icon("chat"), L.text("Nachricht schreiben"), 3)
	var can_chat: bool = game.network.private_chat_available(slot) if game.network.has_method("private_chat_available") else is_instance_valid(hud.chat_panel) and hud.chat_panel.available()
	member_menu.set_item_disabled(member_menu.item_count - 1, not can_chat)
	member_menu.add_icon_item(SocialArt.icon("add"), L.text("Freundesanfrage senden" if _can_add_member(member) else _add_member_reason(member)), 4)
	member_menu.set_item_disabled(member_menu.item_count - 1, not _can_add_member(member))
	var anchor := crew_buttons[slot - 1].get_screen_transform() * Vector2(crew_buttons[slot - 1].size.x, 0)
	member_menu.popup(Rect2i(Vector2i(anchor), Vector2i(278, 0)))

func _member_flag(method: String, slot: int) -> bool:
	return bool(game.network.call(method, slot)) if game.network.has_method(method) else false

func _can_add_member(member: Dictionary) -> bool:
	var slot := int(member.get("player_id", 0))
	if not bool(member.get("connected", false)) or bool(member.get("is_local", false)) or _member_flag("is_player_blocked", slot): return false
	if not "social" in game or not is_instance_valid(game.social) or str(game.social.connection_state) != "online": return false
	var code := str(member.get("friend_code", ""))
	if code.is_empty() or code == str(game.social.friend_code) or bool(member.get("identity_pending", false)) or _friend_request_pending(code): return false
	if not str(member.get("friend_service", "")).is_empty() and "server_url" in game.social and str(member.friend_service) != str(game.social.server_url): return false
	for collection in [game.social.friends, game.social.requests, game.social.blocked]:
		for friend: Dictionary in collection:
			if str(friend.get("code", "")) == code: return false
	for request: Dictionary in _outgoing_friend_requests():
		if str(request.get("code", "")) == code: return false
	return true

func _friend_request_pending(code: String) -> bool:
	return bool(game.social.is_friend_request_pending(code)) if game.social.has_method("is_friend_request_pending") else false

func _update_friend_request_notice() -> void:
	if _friend_request_code.is_empty(): return
	if not "social" in game or not is_instance_valid(game.social) or str(game.social.connection_state) != "online":
		_notice = str(game.social.error_message) if "social" in game and is_instance_valid(game.social) else ""
		if _notice.is_empty(): _notice = "Freundesdienst nicht verbunden."
		_friend_request_code = ""
	elif _friend_request_pending(_friend_request_code):
		_notice = "Freundesanfrage wird gesendet …"
	else:
		var confirmed := _outgoing_friend_requests().any(func(row): return str(row.get("code", "")) == _friend_request_code)
		var mutual: bool = game.social.friends.any(func(row): return str(row.get("code", "")) == _friend_request_code)
		_notice = "Freundesanfrage gesendet." if confirmed else "Freundschaft besteht bereits." if mutual else str(game.social.error_message)
		_friend_request_code = ""
	_notice_until = elapsed + 6.0

func _outgoing_friend_requests() -> Array:
	var value: Variant = game.social.get("outgoing_requests") if "outgoing_requests" in game.social else []
	return value if value is Array else []

func _add_member_reason(member: Dictionary) -> String:
	if not "social" in game or not is_instance_valid(game.social) or str(game.social.connection_state) != "online": return "Freundesdienst nicht verbunden."
	if bool(member.get("identity_pending", false)): return "Identität wird geprüft …"
	var code := str(member.get("friend_code", ""))
	if code.is_empty(): return "Kein gemeinsamer Freundesdienst."
	for friend: Dictionary in game.social.friends:
		if str(friend.get("code", "")) == code: return "Freundschaft besteht bereits."
	if _member_flag("is_player_blocked", int(member.get("player_id", 0))): return "Blockiert"
	for person: Dictionary in game.social.blocked:
		if str(person.get("code", "")) == code: return "Blockiert"
	for request: Dictionary in game.social.requests:
		if str(request.get("code", "")) == code: return "Freundesanfrage offen."
	for request: Dictionary in _outgoing_friend_requests():
		if str(request.get("code", "")) == code: return "Freundesanfrage offen."
	if _friend_request_pending(code): return "Freundesanfrage wird gesendet …"
	return "Freundesanfrage senden"

func _context_matches(member: Dictionary) -> bool:
	if not bool(member.get("connected", false)) or bool(member.get("is_local", false)) or _context_identity.is_empty(): return false
	var key := str(_context_identity.get("member_key", ""))
	if not key.is_empty(): return str(member.get("member_key", "")) == key
	for field in ["player_id", "name", "friend_code", "friend_service"]:
		if str(member.get(field, "")) != str(_context_identity.get(field, "")): return false
	return true

func _member_menu_closed() -> void:
	if is_instance_valid(hud.chat_panel) and "composing" in hud.chat_panel and hud.chat_panel.composing: return
	if _context_slot >= 1 and _context_slot <= crew_buttons.size() and not crew_buttons[_context_slot - 1].disabled:
		crew_buttons[_context_slot - 1].grab_focus.call_deferred()
	else: leave_button.grab_focus.call_deferred()

func _refresh_member_menu() -> void:
	if not is_instance_valid(member_menu) or not member_menu.visible: return
	var member: Dictionary = crew_rows.get(_context_slot, {})
	if not _context_matches(member):
		member_menu.hide()
		return
	var muted := _member_flag("is_player_muted", _context_slot)
	var blocked := _member_flag("is_player_blocked", _context_slot)
	var mute_index := member_menu.get_item_index(1)
	member_menu.set_item_text(mute_index, L.text("Stummschaltung aufheben" if muted else "Stummschalten"))
	member_menu.set_item_icon(mute_index, SocialArt.icon("voice" if muted else "mute"))
	member_menu.set_item_disabled(mute_index, not game.network.has_method("set_player_muted"))
	var block_index := member_menu.get_item_index(2)
	member_menu.set_item_text(block_index, L.text("Blockierung aufheben" if blocked else "Blockieren"))
	member_menu.set_item_disabled(block_index, not game.network.has_method("set_player_blocked"))
	var can_chat: bool = game.network.private_chat_available(_context_slot) if game.network.has_method("private_chat_available") else is_instance_valid(hud.chat_panel) and hud.chat_panel.available()
	member_menu.set_item_disabled(member_menu.get_item_index(3), not can_chat)
	var friend_index := member_menu.get_item_index(4)
	var can_add := _can_add_member(member)
	member_menu.set_item_text(friend_index, L.text("Freundesanfrage senden" if can_add else _add_member_reason(member)))
	member_menu.set_item_disabled(friend_index, not can_add)

func _member_action(action: int) -> void:
	_refresh_crew()
	var member: Dictionary = crew_rows.get(_context_slot, {})
	if not _context_matches(member): return
	match action:
		1:
			if game.network.has_method("set_player_muted"): game.network.set_player_muted(_context_slot, not _member_flag("is_player_muted", _context_slot))
		2:
			if game.network.has_method("set_player_blocked"): game.network.set_player_blocked(_context_slot, not _member_flag("is_player_blocked", _context_slot))
		3:
			if is_instance_valid(hud.chat_panel):
				if hud.chat_panel.has_method("open_private"): hud.chat_panel.open_private(_context_slot)
				else: hud.chat_panel.open()
		4:
			if _can_add_member(member):
				_friend_request_code = ""
				if game.social.add_friend(str(member.friend_code)):
					_friend_request_code = str(member.friend_code)
					_notice = "Freundesanfrage wird gesendet …"
				else: _notice = str(game.social.error_message)
				_notice_until = elapsed + 6.0
	_refresh()

func _wire_focus() -> void:
	var all: Array[Control] = [friends_button, chat_button, server_options_button, server_field, public_address_field, connection_mode_button, create_button, capacity_button, code_field, join_button, copy_button, copy_direct_button, copy_internet_button]
	all.append_array(crew_buttons)
	all.append_array(character_buttons)
	var character_bar := character_scroll.get_v_scroll_bar()
	character_bar.focus_mode = Control.FOCUS_ALL
	all.append(character_bar)
	all.append_array([scene_button, leave_button, start_button, resume_button])
	var controls: Array[Control] = []
	for control in all:
		if control.visible and control.focus_mode != Control.FOCUS_NONE and (not control is BaseButton or not control.disabled): controls.append(control)
	var signature := str(controls.map(func(control): return [control.get_instance_id(), control.get_global_rect()]))
	if signature == _focus_signature: return
	_focus_signature = signature
	for index in controls.size():
		var control := controls[index]
		control.focus_next = control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_previous = control.get_path_to(controls[posmod(index - 1, controls.size())])
		for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			var nearest := _nearest_control(control, controls, direction)
			var property: String = "focus_neighbor_" + str({Vector2.UP:"top", Vector2.DOWN:"bottom", Vector2.LEFT:"left", Vector2.RIGHT:"right"}[direction])
			control.set(property, control.get_path_to(nearest))
	var enabled_characters: Array[Button] = []
	for button: Button in character_buttons:
		if not button.disabled: enabled_characters.append(button)
	for index in enabled_characters.size():
		var button := enabled_characters[index]
		button.focus_neighbor_top = button.get_path_to(enabled_characters[index-1] if index>0 else create_button if create_button.visible and not create_button.disabled else leave_button)
		button.focus_neighbor_bottom = button.get_path_to(enabled_characters[index+1] if index<enabled_characters.size()-1 else start_button if start_button.visible and not start_button.disabled else leave_button)

func _nearest_control(origin: Control, controls: Array[Control], direction: Vector2) -> Control:
	var nearest := origin
	var score := INF
	var center := origin.get_global_rect().get_center()
	for candidate in controls:
		if candidate == origin: continue
		var difference := candidate.get_global_rect().get_center() - center
		var advance := difference.dot(direction)
		if advance <= 1: continue
		var transverse := absf(difference.cross(direction))
		var candidate_score := advance + transverse * 2.0
		if candidate_score < score:
			nearest = candidate
			score = candidate_score
	return nearest

func _draw() -> void:
	draw_rect(SocialArt.bounds(hud), Color("111c20"))

func _draw_foreground() -> void:
	SocialArt.reading_shade(decoration, SocialArt.bounds(hud), 570, 990)
	UiArt.text(decoration, Vector2(100, 118), "Online-Koop", 34, UiArt.IVORY, UiArt.MENU_FONT)
	UiArt.text(decoration, Vector2(100, 156), "Erstelle einen Raum auf deinem Rechner oder tritt deinem Partner mit einem Code bei.", 13, UiArt.MUTED)
	var network = game.network
	if not show_server_options: UiArt.text(decoration, Vector2(100, 244), connection_route_text(), 13, UiArt.MUTED)
	if copy_button.visible:
		UiArt.text(decoration, Vector2(100, 268), _primary_code_label(), 12, UiArt.MUTED)
		var code := _primary_code()
		var code_size := 22
		while code_size > 12 and UiArt.FONT.get_string_size(code, HORIZONTAL_ALIGNMENT_LEFT, -1, code_size).x > 762: code_size -= 1
		UiArt.text(decoration, Vector2(100, 302), code, code_size, UiArt.AMBER)
	var status := L.text(_notice) if elapsed < _notice_until else _status_text()
	var lines := UiArt.wrap_text(status, 650, 14)
	for index in mini(lines.size(), 2): UiArt.text(decoration, Vector2(100, 424 + index * 18), lines[index], 14, UiArt.RED if network.state == "error" else UiArt.MUTED)
	var hints := UiArt.wrap_text(_connection_hint_text(), 650, 12)
	for index in mini(hints.size(), 2): UiArt.text(decoration, Vector2(100, 465 + index * 16), hints[index], 12, UiArt.MUTED)
	UiArt.text(decoration, Vector2(100, 512), "Deine Crew", 15, UiArt.IVORY)
	UiArt.text(decoration, Vector2(375, 512), crew_status(), 13, UiArt.GREEN if _roster_confirmed() and network.peer_connected else UiArt.MUTED)
	var character_heading := character_heading_text()
	UiArt.text(decoration, Vector2(1040, 236), character_heading, 14, UiArt.MUTED)
	var chosen := _local_character()
	CharacterSelectPanel.draw_selection_portrait(decoration, chosen, Rect2(795, 492, 160, 160), elapsed)
	UiArt.text(decoration, Vector2(765, 685), CharacterCatalog.selection_title(chosen), 24, UiArt.IVORY, UiArt.MENU_FONT)
	var detail := UiArt.wrap_text(CharacterCatalog.selection_detail(chosen), 243, 13)
	for index in mini(detail.size(), 3): UiArt.text(decoration, Vector2(765, 710 + index * 18), detail[index], 13, UiArt.MUTED)
	var environment := ScenarioCatalog.environment(str(hud.scenario_options.get("environment", "sector07")))
	UiArt.text(decoration, Vector2(100, 765), L.format("Schauplatz: %s", L.text(str(environment.title)).capitalize()), 14, UiArt.MUTED)
	UiArt.text(decoration, Vector2(1040, 726), "Story: Das letzte Signal" if hud.story_selected else "Freie Schicht", 13, UiArt.MUTED)
	decoration.draw_line(Vector2(100, 781), Vector2(1346, 781), Color(UiArt.MUTED, .18), 1)
	UiArt.text(decoration, Vector2(100, 879), "Pfeile / Steuerkreuz: wählen · Enter / A: bestätigen", 12, UiArt.MUTED)

func _draw_member(button: Button, slot: int) -> void:
	var member: Dictionary = crew_rows.get(slot, {})
	if bool(member.get("connected", false)):
		CharacterSelectPanel.draw_selection_portrait(button, str(member.get("character_id", "mara")), Rect2(19, 6, 35, 35), elapsed)
		var role := L.text("Du" if bool(member.get("is_local", false)) else "Gastgeber" if bool(member.get("is_host", false)) else "Gast")
		var character := CharacterCatalog.selection_title(str(member.get("character_id", "mara")))
		UiArt.text(button, Vector2(74, 43), "P%d · %s · %s" % [slot, role, character], 12, UiArt.MUTED)
		if _member_flag("is_player_blocked", slot): button.draw_texture(SocialArt.icon("block"), Vector2(558, 18), UiArt.RED)
		elif _member_flag("is_player_muted", slot): button.draw_texture(SocialArt.icon("mute"), Vector2(558, 18), UiArt.MUTED)
	else:
		button.draw_texture(SocialArt.icon("crew"), Vector2(28, 19), Color(UiArt.MUTED, .35))

func _draw_character(button: Button, entry: Dictionary) -> void:
	var available := CharacterCatalog.is_unlocked(str(entry.id))
	if available:
		var occupying_player: int = game.network.character_owner(str(entry.id),int(game.network.local_player_id))
		UiArt.text(button, Vector2(18, 48), L.format("Bereits von Spieler %d gewählt",occupying_player) if occupying_player>0 else L.format("%d LP  /  %d", [int(entry.hp), int(entry.capacity)]), 13, UiArt.MUTED)
	else: UiArt.text(button, Vector2(18, 48), CharacterCatalog.unlock_hint(str(entry.id)), 12, UiArt.MUTED)
	if _local_character() == str(entry.id): button.draw_rect(Rect2(0, 13, 2, 23), UiArt.AMBER)

func _network_code(property: String) -> String:
	return str(game.network.get(property)) if property in game.network else ""

func _primary_code_label() -> String:
	if not _network_code("short_room_code").is_empty(): return "Raumcode"
	var room_code := str(game.network.room_code)
	return "LAN-Code" if not room_code.is_empty() and room_code == _network_code("lan_code") else "Raumcode"

func _primary_code() -> String:
	var short_code := _network_code("short_room_code")
	return short_code if not short_code.is_empty() else str(game.network.room_code)

func _status_text() -> String:
	var network = game.network
	if _connection_pending() and not network.is_host and network.state != "reconnecting":
		return L.text("Verbindung wird aufgebaut …")
	var status := "Raum erstellen oder den Code deines Partners eingeben."
	match str(network.state):
		"connecting": status = "Verbindung wird aufgebaut …"
		"lobby": status = "Crew verbunden. Der Gastgeber wählt den Schauplatz." if network.peer_connected else "Raum bereit. Teile den Code mit deiner Crew."
		"reconnecting": status = "Verbindung unterbrochen. Wiederverbindung läuft …"
		"playing": status = "Schicht läuft."
		"error": status = str(network.error_message)
	return L.text(status)

func _connection_hint_text() -> String:
	if game.network.state == "error":
		var failure := str(game.network.error_message)
		var direct_failure := failure == "Der Gastgeber konnte nicht kontaktiert werden." or failure.begins_with("Keine Antwort. Prüfe den Code") or failure.begins_with("Keine Verbindung. Gastgeber, Code und UDP")
		if not game.started and not game.network.is_host and str(game.network.relay_url).is_empty() and direct_failure:
			return L.text("Der Gastgeber kann einen neuen Online-Raum über Relay erstellen. Direkte Internetverbindungen benötigen eine Router-Freigabe.")
		return ""
	var source_hint := str(game.network.connection_hint) if "connection_hint" in game.network else ""
	var hint := L.text(source_hint)
	if _roster_confirmed() and game.network.peer_connected and game.network.state in ["lobby", "playing"]:
		for pending_hint: String in ["Raumcode wird über den Freundeserver aufgelöst …", "Gastgeber im lokalen Netzwerk wird gesucht …", "Direkte Verbindung zum Gastgeber wird aufgebaut.", "Gastgeber gefunden. Verbindung wird aufgebaut …"]:
			if source_hint == pending_hint or source_hint == L.text(pending_hint):
				hint = connection_route_text()
				break
	if "ping_ms" in game.network and _roster_confirmed() and game.network.peer_connected: hint += " · " + L.format("Höchster Ping: %d ms" if game.network.is_host and _member_count() > 2 else "Ping: %d ms", maxi(0, int(game.network.ping_ms)))
	return hint

func connection_route_text() -> String:
	var network = game.network
	if network.active or network.state == "error":
		if "_short_resolution" in network and not str(network.get("_short_resolution")).is_empty():
			return L.text("Verbindungsweg wird ermittelt …")
		return L.text("Direkte Verbindung" if str(network.relay_url).is_empty() else "Verbindung über Relay")
	return L.text("Direkte Verbindung" if server_field.text.strip_edges().is_empty() else "Verbindung über Relay")

func character_heading_text() -> String:
	if not game.network.is_host and not _roster_confirmed() and (game.network.active or game.network.state == "error"):
		return L.text("Deine Figur · Platz noch offen")
	return L.format("Deine Figur · Spieler %d", maxi(1, int(game.network.local_player_id)))

func _copy_room_code() -> void: _write_clipboard(_primary_code())
func _copy_lan_code() -> void: _write_clipboard(_network_code("lan_code"))
func _copy_direct_code() -> void: _write_clipboard(_network_code("direct_code"))
func _copy_internet_code() -> void: _write_clipboard(_network_code("internet_code"))

func _write_clipboard(value: String) -> void:
	if value.is_empty(): return
	DisplayServer.clipboard_set(value)
	# The newer explicit action owns the notice; pending requests stay on the hub.
	_friend_request_code = ""
	_notice = "Raumcode kopiert."
	_notice_until = elapsed + 5.0
	decoration.queue_redraw()

func refresh_locale() -> void:
	for control in [server_field, public_address_field, code_field]: control.placeholder_text = L.text(str(control.get_meta("placeholder_source", "")))
	for button in [create_button, join_button, scene_button, resume_button, server_options_button]: button.text = L.text(str(button.get_meta("source_text", "")))
	_refresh()
	decoration.queue_redraw()
