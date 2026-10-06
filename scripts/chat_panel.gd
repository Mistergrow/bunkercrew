extends Control
## Native plain-text chat. No rich-text parser, profile write or match pause.
const L := preload("res://scripts/locale_text.gd")
const SocialArt := preload("res://scripts/social_ui_art.gd")
const Focus := preload("res://scripts/ui_focus_navigation.gd")
const NetInput := preload("res://scripts/network_input.gd")
const Chat := preload("res://scripts/network_chat.gd")
const MAX_LENGTH := 240
const MAX_HISTORY := preload("res://scripts/network_chat.gd").MAX_HISTORY
const PRESETS := Chat.PRESET_TEXTS
const SHORT_PRESETS := Chat.PRESET_LABELS
const SLOT_COLORS := [Color("d9ac60"),Color("8cbabc"),Color("a8b976"),Color("bf96a6")]
var game
var hud
var network: Node
var composing := false
var feed_visible := true
var unread := 0
var input_field: LineEdit
var send_button: Button
var close_button: Button
var feed_button: Button
var dock_button: Button
var preset_buttons: Array[Button] = []
var history_scroll: ScrollContainer
var history_box: VBoxContainer
var history_rows: Dictionary = {}
var editor: Control
var panel_rect := Rect2()
var _feed: Array[Dictionary] = []
var _history_signature := ""
var _history_revision := 0
var _submitted := ""
var _submitted_original := ""
var _error := ""
var _last_available := false
var _release_until := 0
var private_target := 0
var _private_identity: Dictionary = {}
var _previous_focus: WeakRef
var _focus_signature := ""

func _ready() -> void:
	name = "ChatPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(1440,900)
	network = game.network
	editor = Control.new()
	editor.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(editor)
	history_scroll = ScrollContainer.new()
	history_scroll.position = Vector2(16,49)
	history_scroll.size = Vector2(534,147)
	history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	history_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	editor.add_child(history_scroll)
	history_box = VBoxContainer.new()
	history_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_box.add_theme_constant_override("separation",8)
	history_scroll.add_child(history_box)
	feed_button = _button("Feed ausblenden",Rect2(292,12,166,30),_toggle_feed,editor,12)
	close_button = _button("Schließen",Rect2(468,12,82,30),close,editor,12)
	for index in PRESETS.size():
		var id: String = PRESETS.keys()[index]
		var button := _button(SHORT_PRESETS[id],Rect2(16+index*90,207,84,31),func(): send_preset(id),editor,11)
		button.tooltip_text = L.text(PRESETS[id])
		preset_buttons.append(button)
	input_field = LineEdit.new()
	input_field.position = Vector2(16,253)
	input_field.size = Vector2(416,42)
	input_field.max_length = MAX_LENGTH
	input_field.placeholder_text = L.text("Nachricht an die Crew …")
	input_field.text = str(network.get("chat_draft")) if is_instance_valid(network) else ""
	SocialArt.field(input_field, 15)
	input_field.text_submitted.connect(func(_value: String): send_message())
	input_field.text_changed.connect(func(value: String):
		if is_instance_valid(network): network.set("chat_draft",value))
	editor.add_child(input_field)
	send_button = _button("Senden",Rect2(442,253,108,42),send_message,editor,14)
	dock_button = _button("Chat · Enter",Rect2(),open,self,12)
	var session: Node = network
	network = null
	bind_network(session)
	_layout()
	editor.hide()
	_refresh_history()
	refresh_locale()

func bind_network(session: Node) -> void:
	if network==session: return
	if composing: close()
	private_target = 0
	_private_identity.clear()
	_submitted = ""
	_submitted_original = ""
	_error = ""
	_feed.clear()
	unread = 0
	_last_available = false
	if is_instance_valid(network):
		for pair in [["chat_received",_received],["chat_changed",_chat_changed],["chat_send_completed",_send_completed],["changed",_connection_changed]]:
			if network.has_signal(pair[0]) and network.is_connected(pair[0],pair[1]): network.disconnect(pair[0],pair[1])
	network = session
	if not is_instance_valid(network): return
	for pair in [["chat_received",_received],["chat_changed",_chat_changed],["chat_send_completed",_send_completed],["changed",_connection_changed]]:
		if network.has_signal(pair[0]): network.connect(pair[0],pair[1])
	input_field.text = str(network.get("chat_draft"))
	if bool(network.get("chat_pending")) and "chat_pending_text" in network:
		_submitted = str(network.get("chat_pending_text"))
		_submitted_original = str(network.get("chat_pending_draft"))
	_history_signature = ""
	_refresh_history()

func _button(title: String,rect: Rect2,callback: Callable,parent: Node,font_size: int) -> Button:
	var button := Button.new()
	button.text = L.text(title)
	button.set_meta("source_text",title)
	button.position = rect.position
	button.size = rect.size
	SocialArt.button(button, font_size, "chat" if title == "Chat · Enter" else "join" if title == "Senden" else "", 8)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func available() -> bool:
	return is_instance_valid(network) and network.has_method("chat_available") and bool(network.chat_available())

func blocks_input() -> bool:
	return composing or Time.get_ticks_msec()<_release_until

func open() -> void:
	if not available() or hud.has_session_action() or hud.overlay not in ["","network","pause"]: return
	private_target = 0
	_private_identity.clear()
	_open_composer()

func open_private(slot: int) -> void:
	if not available() or not network.has_method("private_chat_available") or not network.private_chat_available(slot) or hud.has_session_action() or hud.overlay not in ["", "network", "pause"]: return
	private_target = slot
	_private_identity.clear()
	if network.has_method("crew_members"):
		for member: Dictionary in network.crew_members():
			if int(member.get("player_id", 0)) == slot: _private_identity = member.duplicate(true)
	_open_composer()

func _recipient_available() -> bool:
	if not available(): return false
	if private_target == 0: return true
	if not network.has_method("send_private_chat") or not network.has_method("private_chat_available") or not network.private_chat_available(private_target): return false
	if not network.has_method("crew_members"): return true
	for member: Dictionary in network.crew_members():
		if int(member.get("player_id", 0)) != private_target or not bool(member.get("connected", false)): continue
		var key := str(_private_identity.get("member_key", ""))
		if not key.is_empty(): return str(member.get("member_key", "")) == key
		return str(member.get("name", "")) == str(_private_identity.get("name", "")) and str(member.get("friend_code", "")) == str(_private_identity.get("friend_code", ""))
	return false

func _open_composer() -> void:
	if not composing:
		var opener := get_viewport().gui_get_focus_owner()
		_previous_focus = weakref(opener) if is_instance_valid(opener) else null
	composing = true
	unread = 0
	_error = str(network.get("chat_error"))
	_refresh_placeholder()
	editor.show()
	_layout()
	_wire_focus()
	input_field.grab_focus.call_deferred()
	_scroll_bottom.call_deferred()
	queue_redraw()

func close() -> void:
	if not composing: return
	NetInput.quarantine_menu_inputs(game)
	composing = false
	if is_instance_valid(network): network.set("chat_draft",input_field.text)
	input_field.release_focus()
	editor.hide()
	_release_until = Time.get_ticks_msec()+100
	var opener: Object = _previous_focus.get_ref() if _previous_focus != null else null
	if is_instance_valid(opener) and opener is Control and opener.is_visible_in_tree() and not (opener is BaseButton and opener.disabled): opener.grab_focus.call_deferred()
	elif hud.overlay=="network" and is_instance_valid(hud.network_panel): hud.network_panel.leave_button.grab_focus.call_deferred()
	elif hud.overlay=="pause" and hud.pause_buttons.has("continue_match"): hud.pause_buttons.continue_match.grab_focus.call_deferred()
	_previous_focus = null
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not composing or event.is_echo(): return
	if event is InputEventMouseButton and not editor.get_global_rect().has_point(get_global_mouse_position()):
		# A chat draft owns input until explicitly closed; an outside click must
		# not start a match, change the lobby, or accept a pause-menu action.
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func _focus_controls() -> Array[Control]:
	var candidates: Array[Control] = [input_field, send_button]
	candidates.append_array(preset_buttons)
	candidates.append_array([feed_button, close_button])
	var bar := history_scroll.get_v_scroll_bar()
	bar.focus_mode = Control.FOCUS_ALL
	candidates.append(bar)
	return Focus.available(editor, candidates)

func _wire_focus() -> void:
	if not composing: return
	var controls := _focus_controls()
	var signature := Focus.signature(controls)
	if signature == _focus_signature: return
	_focus_signature = signature
	Focus.wire(controls)
	var focus_owner := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus_owner) and editor.is_ancestor_of(focus_owner) and not focus_owner in controls: input_field.grab_focus.call_deferred()

func send_message() -> void:
	if not composing or not available() or _pending(): return
	if not _recipient_available():
		_error = "Diese Person ist nicht mehr erreichbar."
		return
	var text_value := input_field.text.strip_edges()
	if text_value.is_empty(): return
	_submitted = text_value
	_submitted_original = input_field.text
	network.set("chat_draft",input_field.text)
	_error = ""
	var accepted: bool = network.send_private_chat(private_target, input_field.text) if private_target > 0 and network.has_method("send_private_chat") else network.send_chat(input_field.text)
	if not accepted:
		_submitted = ""
		_submitted_original = ""
		_error = str(network.get("chat_error")) if not str(network.get("chat_error")).is_empty() else "Nachricht konnte nicht gesendet werden."
	elif not network.has_signal("chat_send_completed"):
		_send_completed(text_value,true)
	input_field.grab_focus.call_deferred()
	queue_redraw()

func send_preset(id: String) -> void:
	if id not in PRESETS or not available() or _pending(): return
	if not _recipient_available():
		_error = "Diese Person ist nicht mehr erreichbar."
		return
	_error = ""
	var accepted: bool = network.send_private_chat(private_target, L.text(PRESETS[id])) if private_target > 0 and network.has_method("send_private_chat") else network.send_chat_preset(id)
	if not accepted:
		_error = str(network.get("chat_error"))
	queue_redraw()

func _chat_changed() -> void:
	_refresh_history()
	if is_instance_valid(network) and not str(network.get("chat_error")).is_empty():
		_error = str(network.get("chat_error"))
	queue_redraw()

func _send_completed(text_value: String,accepted: bool) -> void:
	if _submitted.is_empty() or text_value!=_submitted: return
	if accepted:
		if input_field.text==_submitted_original: input_field.text=""
		network.set("chat_draft",input_field.text)
		_error = ""
	else:
		_error = str(network.get("chat_error")) if not str(network.get("chat_error")).is_empty() else "Nachricht wurde nicht bestätigt. Entwurf bleibt erhalten."
	_submitted = ""
	_submitted_original = ""
	queue_redraw()

func _received(row: Dictionary) -> void:
	if not composing: unread = mini(99,unread+1)
	_feed.append({"row":row.duplicate(),"age":0.0,"lines":_plain_lines(_message_text(row),412,12)})
	while _feed.size()>4: _feed.pop_front()
	_refresh_history()
	queue_redraw()

func _connection_changed() -> void:
	if not available():
		close()
		# Reconnection may still replay the pending receipt. Keep its identity
		# until the session explicitly completes/rejects it or ends the send.
		if not is_instance_valid(network) or not bool(network.get("chat_pending")):
			_submitted = ""
			_submitted_original = ""
		_feed.clear()
		unread = 0
	_refresh_history()

func _pending() -> bool:
	return not _submitted.is_empty() or (is_instance_valid(network) and bool(network.get("chat_pending")))

func _plain_lines(value: String,width: float,font_size: int) -> Array[String]:
	# Player text must never pass through the source-key translation catalog.
	return [] if value.is_empty() else UiArt.wrap_plain_text(value,width,font_size)

func _message_text(row: Dictionary) -> String:
	var preset := str(row.get("preset",""))
	return L.text(str(PRESETS[preset])) if PRESETS.has(preset) else str(row.get("text",""))

func _feed_heading(row: Dictionary) -> String:
	var slot := clampi(int(row.get("player_id",1)),1,4)
	var privacy := " · " + L.text("Privat") if bool(row.get("private", false)) else ""
	return "P%d%s %s" % [slot,privacy,str(row.get("name",""))]

func _visible_feed() -> Array[Dictionary]:
	# The pause status begins below the two-message area. Keep every delivered
	# row in history and storage; only the compact presentation uses this limit.
	return _feed.slice(maxi(0,_feed.size()-2)) if hud.overlay=="pause" else _feed

func _at_bottom() -> bool:
	var bar := history_scroll.get_v_scroll_bar()
	return bar.value>=bar.max_value-bar.page-3.0

func _history_anchor() -> Dictionary:
	for child in history_box.get_children():
		if child is Control and child.position.y+child.size.y>history_scroll.scroll_vertical:
			return {"id":int(child.get_meta("chat_id",-1)),"offset":history_scroll.scroll_vertical-child.position.y}
	return {}

func _refresh_history() -> void:
	if not is_instance_valid(history_box) or not is_instance_valid(network) or not "chat_history" in network: return
	var records: Array = network.chat_history
	var signature := JSON.stringify(records)+L.current_locale()
	if signature==_history_signature: return
	_history_signature = signature
	var bottom := _at_bottom()
	var anchor := _history_anchor()
	for child in history_box.get_children():
		history_box.remove_child(child)
		child.queue_free()
	history_rows.clear()
	for index in range(maxi(0,records.size()-MAX_HISTORY),records.size()):
		var row: Dictionary = records[index]
		var label := Label.new()
		label.set_meta("chat_id",int(row.get("id",index)))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_override("font",UiArt.FONT)
		label.add_theme_font_size_override("font_size",13)
		var slot := clampi(int(row.get("player_id",1))-1,0,3)
		label.add_theme_color_override("font_color",SLOT_COLORS[slot])
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var sent := maxi(0,int(row.get("time",0)))
		var stamp := "%02d:%02d" % [floori(float(sent)/60.0)%60,sent%60]
		var privacy := " · " + L.text("Privat") if bool(row.get("private", false)) else ""
		label.text = "%s  P%d %s%s\n%s" % [stamp,slot+1,str(row.get("name","")),privacy,_message_text(row)]
		history_box.add_child(label)
		history_rows[int(row.get("id",index))] = label
	_history_revision += 1
	_finish_scroll.call_deferred(bottom,anchor,_history_revision)

func _finish_scroll(bottom: bool,anchor: Dictionary,revision: int) -> void:
	if revision!=_history_revision or not is_inside_tree(): return
	if bottom:
		_scroll_bottom()
	elif history_rows.has(int(anchor.get("id",-1))):
		var row: Control = history_rows[int(anchor.id)]
		history_scroll.scroll_vertical = roundi(row.position.y+float(anchor.offset))

func _scroll_bottom() -> void:
	if not is_instance_valid(history_scroll): return
	history_scroll.scroll_vertical = ceili(history_scroll.get_v_scroll_bar().max_value)

func _toggle_feed() -> void:
	feed_visible = not feed_visible
	refresh_locale()

func _layout() -> void:
	var screen: Rect2 = hud.screen_rect()
	panel_rect = Rect2(screen.end.x-584,screen.end.y-468,566,350)
	editor.position = panel_rect.position
	editor.size = panel_rect.size
	dock_button.position = Vector2(screen.end.x-138,screen.position.y+13)
	dock_button.size = Vector2(120,30)

func _process(delta: float) -> void:
	if not is_instance_valid(network) and is_instance_valid(game.network): bind_network(game.network)
	var can_chat := available()
	if _last_available and not can_chat: _connection_changed()
	_last_available = can_chat
	if composing and hud.overlay not in ["","network","pause"]: close()
	visible = can_chat and not (hud.has_method("has_session_action") and hud.has_session_action())
	dock_button.visible = can_chat and not composing and hud.overlay in ["","pause"]
	dock_button.focus_mode=Control.FOCUS_NONE if hud.overlay.is_empty() else Control.FOCUS_ALL
	dock_button.text = L.format("Chat · %d",unread) if unread>0 else L.text("Chat · Enter")
	var recipient_available := _recipient_available()
	send_button.disabled = not recipient_available or input_field.text.strip_edges().is_empty() or _pending()
	for button in preset_buttons: button.disabled = not recipient_available or _pending()
	if composing and private_target > 0 and not recipient_available and _error.is_empty(): _error = "Diese Person ist nicht mehr erreichbar."
	for entry: Dictionary in _feed: entry.age = float(entry.age)+delta
	while not _feed.is_empty() and float(_feed[0].age)>8.0: _feed.pop_front()
	_layout()
	_wire_focus()
	queue_redraw()

func _draw() -> void:
	if composing:
		SocialArt.sheet(self, panel_rect)
		var title := L.text("Crew-Chat")
		if private_target > 0:
			title = L.text("Privat · %s") % str(_private_identity.get("name", "P%d" % private_target))
		var title_size := 18
		while title_size > 11 and UiArt.FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > 264: title_size -= 1
		draw_string(UiArt.FONT, panel_rect.position + Vector2(16, 34), title, HORIZONTAL_ALIGNMENT_LEFT, 264, title_size, UiArt.IVORY)
		var error_lines := UiArt.wrap_text(_error if not _error.is_empty() else "Enter: senden · Esc: schließen",532,11)
		for index in mini(error_lines.size(),2): UiArt.text(self,panel_rect.position+Vector2(16,318+index*15),error_lines[index],11,UiArt.RED if not _error.is_empty() else UiArt.MUTED)
	elif feed_visible and hud.overlay in ["","pause","network"]:
		var screen: Rect2 = hud.screen_rect()
		var y := screen.position.y+56.0
		for entry: Dictionary in _visible_feed():
			var row: Dictionary = entry.row
			var lines: Array = entry.lines
			var height := 34+mini(2,lines.size())*16
			var rect := Rect2(screen.end.x-466,y,448,height)
			SocialArt.sheet(self, rect)
			var slot := clampi(int(row.get("player_id",1))-1,0,3)
			draw_string(UiArt.FONT,rect.position+Vector2(12,19),_feed_heading(row),HORIZONTAL_ALIGNMENT_LEFT,412,12,SLOT_COLORS[slot])
			for index in mini(2,lines.size()): draw_string(UiArt.FONT,rect.position+Vector2(12,37+index*16),lines[index],HORIZONTAL_ALIGNMENT_LEFT,412,12,UiArt.IVORY)
			y += height+6

func refresh_locale() -> void:
	for button: Button in [send_button,close_button]: button.text = L.text(str(button.get_meta("source_text","")))
	feed_button.text = L.text("Feed ausblenden" if feed_visible else "Feed einblenden")
	_refresh_placeholder()
	for index in preset_buttons.size():
		var id: String = PRESETS.keys()[index]
		preset_buttons[index].text = L.text(SHORT_PRESETS[id])
		preset_buttons[index].tooltip_text = L.text(PRESETS[id])
	_history_signature = ""
	_refresh_history()
	for entry: Dictionary in _feed: entry.lines = _plain_lines(_message_text(entry.row),412,12)
	queue_redraw()

func _refresh_placeholder() -> void:
	input_field.placeholder_text = L.text("Nachricht an %s …") % str(_private_identity.get("name", "P%d" % private_target)) if private_target > 0 else L.text("Nachricht an die Crew …")
