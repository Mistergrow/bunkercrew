extends Node
## Host owns the simulation. A guest sends input and permitted purchase requests.
signal changed
signal chat_received(message: Dictionary)
signal chat_changed
signal chat_send_completed(text: String,accepted: bool)
const PeerState := preload("res://scripts/network_peer_state.gd")
const Protocol := preload("res://scripts/network_protocol.gd")
const Registry := preload("res://scripts/content_registry.gd")
const NetInput := preload("res://scripts/network_input.gd")
const JoinCode := preload("res://scripts/network_join_code.gd")
const Transport := preload("res://scripts/network_transport.gd")
const WebSocketDrain := preload("res://scripts/network_websocket_drain.gd")
const LanDiscovery := preload("res://scripts/network_lan_discovery.gd")
const Messages := preload("res://scripts/network_messages.gd")
const VoiceCodec := preload("res://scripts/voice_codec.gd")
const Chat := preload("res://scripts/network_chat.gd")
const Social := preload("res://scripts/network_social.gd")
const INPUT_INTERVAL := 1.0/30.0
const SNAPSHOT_INTERVAL := 1.0/20.0
const RECONNECT_SECONDS := 30.0
var game
var active := false
var is_host := false
var local_player_id := 1
var state := "offline"
var room_code := ""
var lan_code := ""
var direct_code := ""
var internet_code := ""
var listen_port := Transport.DEFAULT_PORT
var lan_discovery_port := 24778
var lan_discovery_targets: Array[String] = []
var lan_discovery
var advertised_address := ""
var error_message := ""
var connection_hint := ""
var peer_connected := false
var relay_url := ""
var remote_input: Dictionary = {}
var ping_ms := 0
var received_snapshots := 0
var sent_snapshots := 0
var match_paused := false
var _requested_pause := false
var transport
var world
var _decoder
var _websocket: WebSocketPeer
var _relay_requested := false
var _relay_action := ""
var _relay_resume_token := ""
var _join_code := ""
var _address := ""
var _port := 24777
var _client_token := ""
var _guest_token := ""
var _invite_secret := ""
var _authenticated := false
var _closing := false
var _deadline := 0.0
var _reconnect_deadline := 0.0
var _retry_at := 0.0
var _clock := 0.0
var _clock_updated_usec := Time.get_ticks_usec()
var _input_clock := 0.0
var _snapshot_clock := 0.0
var _ping_clock := 0.0
var _last_input_at := -100.0
var _last_packet_at := 0.0
var _input_seq := 0
var _remote_seq := -1
var _snapshot_seq := 0
var _received_seq := -1
var _shared_snapshot_sequence := 0
var _snapshot_failures := 0
var _last_resync_at := -100.0
var _snapshot_ack := 0
var _ack_clock := 0.0
const MAX_PENDING_SNAPSHOTS := 4
const MAX_PENDING_INPUT_EDGES := 128
var _pending_remote: Dictionary = {}
# PeerState swaps this Array through Object.set(); keep its Variant type so
# each link retains its own backing array rather than a typed conversion.
var _input_edges: Array = []
var _pressed: Array = []
var _released: Array = []
var _local_pressed: Array = []
var _local_released: Array = []
var _ready_for_snapshots := false
var _loading := false
var _match_options: Dictionary = {}
var _match_characters: Array = []
var _match_story := false
var _expedition_payload: Dictionary = {}
var _last_lobby := ""
var _command_window := 0.0
var _command_count := 0
var _reload_match := false
var _reload_preferences: Dictionary = {}
var _hello_sent := false
var _handshake_deadline := 0.0
var _load_deadline := 0.0
var _generation := 0
var _rejecting := false
var _events: Array = []
var _gore_generation:=-1
var _gore_highest:=0
var _gore_seen: Dictionary={}
var _event_clock := 0.0
var _voice_seq := 0
var _voice_highest := -1
var _voice_seen: Dictionary = {}
var _voice_sources: Dictionary = {}
var _voice_members: Dictionary = {}
var _voice_member_keys_supported := false
var _packet_budgets: Dictionary = {}
var _invalid_packets := 0
var _pong_at := -1.0
var max_players := 4
var _peers: Dictionary = {}
var _slots: Dictionary = {}
var _context_peer := 0
var _connected_slots: Array = [1]
var _match_player_count := 2
var display_name := ""
var room_social_service := ""
var short_room_code := ""
var observed_public_address := ""
var _short_resolution := ""
var _short_hub: Node
var _short_fallback_relay := ""
var chat_history: Array[Dictionary] = []
var chat_error := ""
var chat_pending := false
var chat_draft := ""
var chat_pending_text := ""
var chat_pending_draft := ""
var chat_names: Dictionary = {}
var _chat := Chat.new()
var _chat_request := 0
var _chat_waiting: Dictionary = {}
var _chat_reject_at: Dictionary = {}
var _deferred_room_packets: Array[Dictionary] = []
var _social := Social.new()

func refresh_social_identity(hub: Node) -> void:
	_social.session = self
	_social.refresh(hub)

func crew_members() -> Array[Dictionary]:
	_social.session = self
	return _social.crew_members()

func is_player_muted(slot: int) -> bool:
	return _social.muted.has(slot)

func set_player_muted(slot: int, value: bool) -> bool:
	_social.session = self
	return _social.set_muted(slot, value)

func is_player_blocked(slot: int) -> bool:
	return _social.is_blocked(slot)

func set_player_blocked(slot: int, value: bool) -> bool:
	_social.session = self
	return _social.set_blocked(slot, value)

func private_chat_available(slot: int) -> bool:
	return chat_available() and slot != local_player_id and slot >= 1 and slot <= 4 and is_player_connected(slot) and not is_player_blocked(slot)

func send_private_chat(slot: int, text: String) -> bool:
	if Chat.forbidden_controls(text): return _chat_failure("controls")
	if not private_chat_available(slot): return _chat_failure("blocked" if is_player_blocked(slot) else "unavailable")
	return _send_chat_content(Chat.clean_text(text), "", text, slot)

func chat_available() -> bool:
	var room_open: bool=state in ["lobby","playing"]
	if is_host and state=="reconnecting":
		room_open=(is_instance_valid(transport) and transport.is_host and transport.peer!=null) if relay_url.is_empty() else (_websocket!=null and _websocket.get_ready_state()==WebSocketPeer.STATE_OPEN)
	return active and not _closing and room_open and (is_host or (peer_connected and _authenticated))

func set_display_name(value: String) -> bool:
	if Chat.forbidden_controls(value): return false
	value=Chat.clean_text(value)
	if not Chat.valid_name(value,true): return false
	if value==display_name: return true
	if active and not is_host and _authenticated:
		if not _send({"kind":"chat_name","name":value},true): return false
	display_name=value
	if active and is_host: _send_lobby()
	chat_changed.emit()
	return true

func send_chat(text: String) -> bool:
	if Chat.forbidden_controls(text): return _chat_failure("controls")
	return _send_chat_content(Chat.clean_text(text),"",text)

func send_chat_preset(id: String) -> bool:
	if id not in Chat.PRESETS: return _chat_failure("preset")
	return _send_chat_content("",id)

func _chat_failure(code: String) -> bool:
	chat_error=Chat.error_text(code)
	chat_changed.emit()
	return false

func _send_chat_content(text: String,preset: String,original_draft: String="",recipient: int=0) -> bool:
	if not chat_available(): return _chat_failure("unavailable")
	if not Chat.valid_content(text,preset): return _chat_failure("invalid")
	if chat_pending: return _chat_failure("pending")
	if _chat_request>=Chat.MAX_SEQUENCE or _chat.highest_id>=Chat.MAX_SEQUENCE: return _chat_failure("unavailable")
	chat_error=""
	if is_host:
		if recipient > 0 and _private_chat_error(1, recipient) != "": return _chat_failure(_private_chat_error(1, recipient))
		if not _chat.allow_sender("slot:1",_clock): return _chat_failure("rate")
		chat_pending_text=text
		chat_pending_draft=original_draft
		if recipient > 0: _accept_private_chat(1, recipient, text)
		else: _accept_chat(1,text,preset)
		_clear_confirmed_chat_draft(original_draft)
		chat_send_completed.emit(text,true)
		chat_pending_text=""
		chat_pending_draft=""
		return true
	if not _chat.allow_sender("local",_clock): return _chat_failure("rate")
	_chat_request+=1
	var request := {"kind":"chat_send","request":_chat_request,"text":text,"preset":preset}
	if recipient > 0: request = {"kind":"chat_private_send", "request":_chat_request, "recipient_id":recipient, "text":text}
	# Install the pending state before sending: a loopback fixture can ACK in
	# the same call. The reliable room stream carries history/message/ACK order.
	_chat_waiting={"request":_chat_request,"text":text,"preset":preset,"deadline":_clock+8.0}
	chat_pending=true
	chat_pending_text=text
	chat_pending_draft=original_draft
	if not _send(request,true):
		_chat.refund_sender("local")
		_chat_waiting.clear()
		chat_pending=false
		chat_pending_text=""
		chat_pending_draft=""
		return _chat_failure("transport")
	chat_changed.emit()
	return true

func _chat_author_name(slot: int) -> String:
	var chosen: String=display_name if slot==1 else str(_slots.get(slot,{}).get("chat_name",""))
	if Chat.valid_name(chosen): return chosen
	if is_instance_valid(game) and "selected_characters" in game and slot<=game.selected_characters.size():
		var id: String=str(game.selected_characters[slot-1])
		if CharacterCatalog.contains(id): return str(CharacterCatalog.data(id).title)
	return "P%d"%slot

func _accept_chat(slot: int,text: String,preset: String) -> Dictionary:
	if _chat.highest_id>=Chat.MAX_SEQUENCE: return {}
	var row := {"id":_chat.highest_id+1,"player_id":slot,"name":_chat_author_name(slot),"text":text,"preset":preset,"time":_clock}
	_receive_chat(row)
	_send({"kind":"chat_message","message":row},true,-1)
	return row

func _private_chat_error(sender: int, recipient: int) -> String:
	if sender == recipient or not is_player_connected(sender) or not is_player_connected(recipient): return "unavailable"
	if (sender == 1 and is_player_blocked(recipient)) or (recipient == 1 and is_player_blocked(sender)): return "blocked"
	if sender > 1 and recipient in _slots.get(sender, {}).get("blocked_slots", []): return "blocked"
	if recipient > 1 and sender in _slots.get(recipient, {}).get("blocked_slots", []): return "blocked"
	return ""

func _accept_private_chat(sender: int, recipient: int, text: String) -> Dictionary:
	var row := {"id":_chat.highest_id + 1, "player_id":sender, "recipient_id":recipient, "private":true, "sender_key":str(_social.member_keys.get(str(sender), "")), "recipient_key":str(_social.member_keys.get(str(recipient), "")), "name":_chat_author_name(sender), "text":text, "preset":"", "time":_clock}
	_receive_chat(row)
	for slot in [sender, recipient]:
		if slot > 1 and _slots.has(slot): _send({"kind":"chat_message", "message":row}, true, int(_slots[slot].wire))
	return row

func _chat_row_visible(row: Dictionary, viewer: int) -> bool:
	if bool(row.get("private", false)):
		var member_key: String = str(_social.member_keys.get(str(viewer), ""))
		if member_key.is_empty() or member_key not in [str(row.get("sender_key", "")), str(row.get("recipient_key", ""))]: return false
	return viewer != local_player_id or not is_player_blocked(int(row.player_id))

func _refresh_chat_history() -> void:
	chat_history.clear()
	for row in _chat.history:
		if _chat_row_visible(row, local_player_id): chat_history.append(row.duplicate(true))
	chat_changed.emit()

func _receive_chat(row: Dictionary) -> void:
	if not is_host and bool(row.get("private", false)) and local_player_id not in [int(row.player_id), int(row.recipient_id)]: return
	if not _chat.append_authoritative(row): return
	_refresh_chat_history()
	if _chat_row_visible(row, local_player_id): chat_received.emit(row.duplicate(true))

func _receive_chat_history(messages: Array) -> void:
	var updated := false
	for row: Dictionary in messages:
		if not is_host and bool(row.get("private", false)) and local_player_id not in [int(row.player_id), int(row.recipient_id)]: continue
		updated=_chat.append_authoritative(row) or updated
	if not updated: return
	_refresh_chat_history()
	# Restored conversation is one history update. Broadcasting eighty live
	# receipt signals would rebuild the UI repeatedly and mark old text unread.
	chat_changed.emit()

func _handle_chat_request(message: Dictionary) -> void:
	if not is_host or not _peers.has(_context_peer): return
	var link: Dictionary=_peers[_context_peer]
	var slot: int=int(link.slot)
	if slot<2 or slot>4 or not link._authenticated or not link.connected: return
	var receipt: Dictionary=link.get("chat_receipt",{})
	var request_id: int=int(message.request)
	var recipient := int(message.get("recipient_id", 0))
	var preset := str(message.get("preset", ""))
	if request_id<=int(receipt.get("request",0)):
		var repeated: bool=request_id==int(receipt.get("request",0)) and message.text==receipt.get("text") and preset==receipt.get("preset") and recipient==int(receipt.get("recipient_id", 0))
		_send_chat_ack(request_id,repeated and bool(receipt.get("accepted",false)),str(receipt.get("error_code","stale")) if repeated else "stale")
		return
	var error := ""
	if not chat_available() or _chat.highest_id>=Chat.MAX_SEQUENCE: error="unavailable"
	elif recipient > 0 and not _private_chat_error(slot, recipient).is_empty(): error = _private_chat_error(slot, recipient)
	elif not _chat.allow_sender("slot:%d"%slot,_clock): error="rate"
	link.chat_receipt={"request":request_id,"text":message.text,"preset":preset,"recipient_id":recipient,"accepted":error.is_empty(),"error_code":error}
	if error.is_empty():
		if recipient > 0: _accept_private_chat(slot, recipient, str(message.text))
		else: _accept_chat(slot,str(message.text),preset)
	_send_chat_ack(request_id,error.is_empty(),error)

func _send_chat_ack(request_id: int,accepted: bool,error: String) -> void:
	_send({"kind":"chat_ack","request":request_id,"accepted":accepted,"error_code":"" if accepted else error},true)

func _receive_chat_ack(message: Dictionary) -> void:
	if not chat_pending or message.request!=_chat_waiting.get("request"): return
	_finish_chat_send(bool(message.accepted),str(message.error_code))

func _finish_chat_send(accepted: bool,error: String) -> void:
	var text: String=str(_chat_waiting.get("text",""))
	var original: String=chat_pending_draft
	_chat_waiting.clear()
	chat_pending=false
	chat_error="" if accepted else Chat.error_text(error)
	if accepted: _clear_confirmed_chat_draft(original)
	chat_send_completed.emit(text,accepted)
	# A completion listener may submit the next draft synchronously. Its new
	# pending metadata belongs to that send and must survive this completion.
	if not chat_pending:
		chat_pending_text=""
		chat_pending_draft=""
	chat_changed.emit()

func _clear_confirmed_chat_draft(original: String) -> void:
	# The session may receive the ACK while no mission UI exists. It owns the
	# persisted draft too, and clears only that unchanged, confirmed text.
	if not original.is_empty() and chat_draft==original: chat_draft=""

func _apply_chat_name(link: Dictionary,value: String) -> bool:
	link.chat_pending_name=null
	link.chat_pending_name_at=0.0
	if link.chat_name==value: return false
	link.chat_name=value
	_social.refresh_name(int(link.get("slot", 0)))
	return true

func _queue_chat_name(link: Dictionary,value: String) -> void:
	if value==link.chat_name:
		link.chat_pending_name=null
		link.chat_pending_name_at=0.0
		return
	if not link.get("chat_pending_name") is String: link.chat_pending_name_at=_clock+2.0
	# Coalesce to the latest validated name without extending the deadline.
	link.chat_pending_name=value

func _flush_chat_names() -> void:
	if not active or not is_host or not is_instance_valid(game) or game.is_queued_for_deletion(): return
	var updated := false
	for id in _peers.keys():
		var link: Dictionary=_peers[id]
		if not link.connected or not link._authenticated or not link.get("chat_pending_name") is String or _clock<float(link.get("chat_pending_name_at",0.0)): continue
		_enter_peer(int(id))
		if _allow_message("chat_name"):
			updated=_apply_chat_name(link,str(link.chat_pending_name)) or updated
		else:
			link.chat_pending_name_at=_clock+0.25
		_leave_peer()
	if updated: _send_lobby()

func _replay_chat() -> void:
	var viewer: int = int(_peers.get(_context_peer, {}).get("slot", 2))
	var history: Array = _chat.history.filter(func(row): return _chat_row_visible(row, viewer))
	_send({"kind":"chat_history","messages":history},true)
	if _peers.has(_context_peer):
		var receipt: Dictionary=_peers[_context_peer].get("chat_receipt",{})
		if not receipt.is_empty(): _send_chat_ack(int(receipt.request),bool(receipt.accepted),str(receipt.error_code))

func set_capacity(value: int) -> bool:
	if value<2 or value>4 or (is_instance_valid(game) and game.started) or (active and not is_host) or value<connected_player_count(): return false
	max_players=value
	if active: _send_lobby()
	changed.emit()
	return true

func connected_player_count() -> int:
	if not active: return int(game.player_count) if is_instance_valid(game) and game.started else 1
	if not is_host: return _connected_slots.size()
	var count:=1
	for link: Dictionary in _slots.values():
		if link.connected and link._authenticated: count+=1
	return count

func is_player_connected(id: int) -> bool:
	if not active: return is_instance_valid(game) and id>=1 and id<=game.player_count
	if not is_host: return id in _connected_slots
	return id==1 or (_slots.has(id) and _slots[id].connected and _slots[id]._authenticated)

func character_owner(id: String, excluding_player: int=0) -> int:
	for slot in range(1,PartyConfig.MAX_PLAYERS+1):
		if slot != excluding_player and is_player_connected(slot) and slot <= game.selected_characters.size() and game.selected_characters[slot-1] == id:
			return slot
	return 0

func remote_input_for(id: int) -> Dictionary:
	return _slots[id].remote_input if _slots.has(id) and _slots[id].connected else (remote_input if id==2 and _slots.is_empty() else {})

func _enter_peer(id: int) -> void:
	_context_peer=id
	for field in PeerState.FIELDS: set(field,_peers[id][field])

func _leave_peer() -> void:
	if _peers.has(_context_peer):
		for field in PeerState.FIELDS: _peers[_context_peer][field]=get(field)
	_context_peer=0
	var primary: Dictionary=_slots.get(2,{})
	if primary.is_empty() and not _peers.is_empty(): primary=_peers.values()[0]
	if not primary.is_empty():
		for field in PeerState.FIELDS: set(field,primary[field])
	peer_connected=connected_player_count()>1
	if is_host:
		ping_ms=0
		for link: Dictionary in _slots.values():
			if link.connected and link._authenticated: ping_ms=maxi(ping_ms,int(link.get("ping_ms",0)))

func _all_ready() -> bool:
	if _slots.is_empty(): return true
	for link: Dictionary in _slots.values():
		if not link.connected or not link._authenticated or not link._ready_for_snapshots: return false
	return true

func _retire_worker(worker: Node) -> void:
	if is_instance_valid(worker.mounted_turret): worker.mounted_turret.exit()
	worker.set_meta("network_departed",true)
	worker.visible=false
	worker.collision_layer=0
	worker.set_process(false)
	worker.set_physics_process(false)

func _expire_missing_slots() -> void:
	var expired := false
	for slot in _slots.keys():
		var link: Dictionary=_slots[slot]
		if link.connected or _clock<float(link.get("reconnect_until",_reconnect_deadline)): continue
		_slots.erase(slot)
		_social.remove_member(int(slot))
		expired = true
		for worker in game.players:
			if worker.player_id!=int(slot): continue
			_retire_worker(worker)
		connection_hint=LocaleText.format("Spieler %d ist ausgeschieden. Die übrige Crew spielt weiter.",int(slot))
	if not expired: return
	_leave_peer()
	if _all_ready():
		state="playing"
		_reconnect_deadline=0
		_loading=false
		_set_pause(false)
		_send({"kind":"pause","generation":_generation,"paused":match_paused},true,-1)
	_send_lobby()
	changed.emit()

func _peer_connected_id(id: int) -> void:
	if not is_host:
		_connected()
		return
	if _peers.has(id): return
	var link: Dictionary=PeerState.create(_clock)
	link.wire=id
	_peers[id]=link

func _peer_disconnected_id(id: int,reason: String) -> void:
	if not is_host:
		_disconnected(reason)
		return
	if not _peers.has(id): return
	var link: Dictionary=_peers[id]
	link.connected=false
	link.reconnect_until=_clock+RECONNECT_SECONDS
	link._authenticated=false
	link._ready_for_snapshots=false
	link.remote_input={}
	link._pending_remote={}
	link._pressed=[]
	link._released=[]
	link._input_edges=[]
	_peers.erase(id)
	if int(link.slot)>0 and is_instance_valid(game) and game.started:
		state="reconnecting"
		_reconnect_deadline=_clock+RECONNECT_SECONDS
		_set_pause(true)
		_send({"kind":"pause","generation":_generation,"paused":true},true,-1)
		connection_hint=LocaleText.format("Spieler %d getrennt. Die Schicht wartet auf die Wiederverbindung.",int(link.slot))
	elif int(link.slot)>0:
		_slots.erase(int(link.slot))
		_social.remove_member(int(link.slot))
		state="lobby"
	_leave_peer()
	_send_lobby()
	changed.emit()

func _peer_error(id: int,reason: String) -> void:
	if is_host: _peer_disconnected_id(id,reason)
	else: _transport_error(reason)

func _packet_from(data: PackedByteArray,id: int) -> void:
	if not is_host:
		_packet(data)
		return
	if not _peers.has(id):
		if is_instance_valid(transport) and transport.remote_peers.has(id): _peer_connected_id(id)
		else: return
	_enter_peer(id)
	_packet(data)
	_leave_peer()

func _send_lobby() -> void:
	if not is_host: return
	var lobby:=_lobby_message()
	for id in _peers.keys():
		var link: Dictionary=_peers[id]
		if not link._authenticated: continue
		var message:=lobby.duplicate()
		message.player_id=int(link.slot)
		_send(message,true,int(id))

func _compact_lobby_slots() -> void:
	var old_characters: Array=game.selected_characters.duplicate()
	var ordered: Array=_slots.keys()
	ordered.sort()
	var replacement: Dictionary={}
	var mapping: Dictionary = {}
	var next_slot:=2
	for old_slot in ordered:
		var link: Dictionary=_slots[old_slot]
		if not link.connected or not link._authenticated: continue
		game.selected_characters[next_slot-1]=old_characters[int(old_slot)-1]
		link.slot=next_slot
		mapping[int(old_slot)] = next_slot
		replacement[next_slot]=link
		next_slot+=1
	_slots=replacement
	_social.remap_slots(mapping)
	for link: Dictionary in _slots.values():
		var next_blocks: Array = []
		for old_slot in link.get("blocked_slots", []):
			if int(old_slot) == 1 or mapping.has(int(old_slot)): next_blocks.append(1 if int(old_slot) == 1 else mapping[int(old_slot)])
		link.blocked_slots = next_blocks
	_send_lobby()

func _ready() -> void:
	_social.session = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100

func bind_game(value: Node) -> void:
	game = value
	_gore_generation=-1
	_gore_highest=0
	_gore_seen.clear()
	if is_instance_valid(game.combat_events) and not game.combat_events.event.is_connected(_combat_event):
		game.combat_events.event.connect(_combat_event)
	if _reload_match:
		_reload_match = false
		game.restore_session_preferences(_reload_preferences)
		_reload_preferences.clear()
		_begin_local_match.call_deferred()

func default_relay_url() -> String:
	var service: String = Social.Hub.default_server()
	if is_instance_valid(game) and "social" in game and is_instance_valid(game.social) and "server_url" in game.social:
		var configured := Social.Hub.normalize_url(str(game.social.server_url))
		if not configured.is_empty(): service = configured
	return service.trim_suffix("/social") + "/ws"

func host_room(url := "") -> void:
	leave()
	_promote()
	game.selected_characters = PartyConfig.unique_characters(game.selected_characters)
	active = true
	is_host = true
	local_player_id = 1
	relay_url = str(url).strip_edges()
	error_message = ""
	state = "connecting"
	_guest_token = Crypto.new().generate_random_bytes(24).hex_encode()
	_invite_secret = JoinCode.new_invitation()
	if relay_url.is_empty():
		_make_transport()
		var auto_map := not ("--no-upnp" in OS.get_cmdline_user_args())
		if transport.host(listen_port,auto_map)!=OK:
			_fail("Der Netzwerkport ist belegt. Beende eine andere gehostete Sitzung und versuche es erneut.")
			return
		direct_code = JoinCode.invite(transport.lan_address,transport.port,_invite_secret)
		room_code = JoinCode.lan(_invite_secret)
		lan_code = room_code
		connection_hint = "Kurzer LAN-Code: Dein Partner wird im selben Netzwerk automatisch gefunden."
		state = "lobby"
		_make_lan_discovery()
		if lan_discovery.host(_invite_secret,transport.port) != OK:
			connection_hint = "LAN-Suche nicht verfügbar. Bitte den Direktcode kopieren."
	else:
		_connect_relay("host")
	changed.emit()

func join_room(url: String,code: String) -> void:
	_join_room(url, code)

func _join_room(url: String, code: String, resolved: bool = false) -> void:
	leave()
	_promote()
	relay_url = url.strip_edges()
	_join_code = code.strip_edges().to_upper()
	active = true
	is_host = false
	local_player_id = 2
	state = "connecting"
	error_message = ""
	_deadline = _clock+12.0
	if not resolved and Social.Hub.valid_room_alias(JoinCode.compact(_join_code)):
		if is_instance_valid(game) and "social" in game and is_instance_valid(game.social):
			if not relay_url.is_empty() and game.social.has_method("connect_for_room"): game.social.connect_for_room(relay_url)
			_short_hub = game.social
			if not _short_hub.room_resolved.is_connected(_resolved_short_room): _short_hub.room_resolved.connect(_resolved_short_room)
			_short_resolution = _short_hub.resolve_short_code(_join_code)
			if not _short_resolution.is_empty():
				_short_fallback_relay = relay_url
				_deadline = _clock + 18.0
				connection_hint = "Raumcode wird über den Freundeserver aufgelöst …"
				changed.emit()
				return
			_cancel_short_resolution()
		if relay_url.is_empty():
			_fail("Für kurze Raumcodes muss der Freundeserver erreichbar sein.")
			return
	if relay_url.is_empty():
		if JoinCode.is_lan_code(_join_code):
			_invite_secret = JoinCode.compact(_join_code)
			room_code = JoinCode.lan(_invite_secret)
			connection_hint = "Gastgeber im lokalen Netzwerk wird gesucht …"
			_make_lan_discovery()
			lan_discovery.found.connect(_lan_found)
			lan_discovery.failed.connect(_lan_failed)
			if lan_discovery.discover(_invite_secret) != OK and state != "error":
				_fail("LAN-Suche nicht verfügbar. Bitte den Direktcode vom Gastgeber verwenden.")
			changed.emit()
			return
		var decoded: Dictionary = JoinCode.decode(_join_code)
		if not decoded.get("ok",false):
			_fail(str(decoded.get("error","Der Beitrittscode ist ungültig.")))
			return
		_address = decoded.address
		_port = int(decoded.port)
		_invite_secret=str(decoded.get("invite",""))
		if _invite_secret.is_empty():
			_fail("Bitte den neuen vollständigen Raumcode vom Gastgeber kopieren.")
			return
		room_code = decoded.code
		connection_hint = "Direkte Verbindung zum Gastgeber wird aufgebaut."
		_make_transport()
		if transport.join(_address,_port)!=OK:
			_fail("Der Gastgeber konnte nicht kontaktiert werden.")
	else:
		_connect_relay("join")
	changed.emit()

func _cancel_short_resolution() -> void:
	if is_instance_valid(_short_hub):
		if _short_hub.room_resolved.is_connected(_resolved_short_room): _short_hub.room_resolved.disconnect(_resolved_short_room)
		if not _short_resolution.is_empty(): _short_hub.cancel_room_resolution(_short_resolution)
	_short_hub = null
	_short_resolution = ""
	_short_fallback_relay = ""

func _resolved_short_room(request: String, route: Dictionary) -> void:
	if request != _short_resolution or not active or is_host or state != "connecting": return
	var alias := JoinCode.compact(_join_code)
	var fallback := _short_fallback_relay
	_cancel_short_resolution()
	if not bool(route.get("ok", false)):
		# Old six-character relay invitations remain usable when the broker
		# does not own that code, including a temporarily unavailable service.
		if not fallback.is_empty() and route.get("error_code") in ["room_unavailable", "service_unavailable"]:
			_join_room(fallback, alias, true)
			return
		_fail(str(Social.Hub.ERRORS.get(str(route.get("error_code", "room_unavailable")), Social.Hub.ERRORS.room_unavailable)))
		return
	_join_room(str(route.relay_url), str(route.room_code), true)
	short_room_code = alias
	changed.emit()

func observe_public_address(address: String) -> void:
	if not address.is_empty() and not JoinCode.is_public_address(address): return
	if address == observed_public_address: return
	observed_public_address = address
	if active and is_host and relay_url.is_empty() and is_instance_valid(transport) and not address.is_empty():
		if advertised_address == address or (transport.mapping_confirmed and transport.public_address == address):
			internet_code = JoinCode.invite(address, transport.port, _invite_secret)
	changed.emit()

func _make_lan_discovery() -> void:
	_close_lan_discovery()
	lan_discovery = LanDiscovery.new()
	lan_discovery.discovery_port = lan_discovery_port
	lan_discovery.discovery_targets.assign(lan_discovery_targets)
	add_child(lan_discovery)

func _close_lan_discovery() -> void:
	if is_instance_valid(lan_discovery):
		lan_discovery.close()
		lan_discovery.queue_free()
	lan_discovery = null

func _lan_found(address: String, port: int) -> void:
	if not active or is_host or state != "connecting": return
	_address = address
	_port = port
	_deadline = _clock+12.0
	connection_hint = "Gastgeber gefunden. Verbindung wird aufgebaut …"
	_make_transport()
	if transport.join(_address,_port) != OK:
		_fail("Der Gastgeber konnte nicht kontaktiert werden.")
	changed.emit()

func _lan_failed(reason: String) -> void:
	if active and not is_host and state == "connecting": _fail(reason)

func _promote() -> void:
	# Active sessions live above the game scene so a rematch keeps the socket.
	_closing = true
	if get_parent()!=get_tree().root:
		reparent(get_tree().root)
	_closing = false

func _make_transport() -> void:
	if is_instance_valid(transport):
		transport.close()
		transport.queue_free()
	transport = Transport.new()
	add_child(transport)
	transport.packet_from.connect(_packet_from)
	transport.peer_joined.connect(_peer_connected_id)
	transport.peer_left.connect(_peer_disconnected_id)
	transport.disconnected.connect(func(reason):
		if not is_host and state!="reconnecting": _disconnected(reason))
	transport.peer_error.connect(_peer_error)
	transport.error.connect(_transport_error)
	transport.public_address_ready.connect(_public_address)

func _public_address(address: String,hint: String) -> void:
	if not active or not is_host: return
	if not advertised_address.is_empty():
		connection_hint = LocaleText.format("Manuelle Internetadresse: %s. UDP %d muss auf diesen Rechner zeigen.",[advertised_address,transport.port])
		changed.emit()
		return
	if not address.is_empty() and JoinCode.is_public_address(address) and transport.mapping_confirmed:
		internet_code = JoinCode.invite(address,transport.port,_invite_secret)
	elif advertised_address.is_empty(): internet_code = ""
	connection_hint = hint
	changed.emit()

func set_advertised_address(address: String) -> bool:
	if not active or not is_host or not relay_url.is_empty() or not is_instance_valid(transport): return false
	address = address.strip_edges()
	if not address.is_valid_ip_address() or ":" in address or not JoinCode.is_public_address(address):
		connection_hint = "Bitte eine gültige öffentliche IPv4 eingeben. Der LAN-Code bleibt weiter nutzbar."
		changed.emit()
		return false
	advertised_address = address
	internet_code = JoinCode.invite(address,transport.port,_invite_secret)
	connection_hint = LocaleText.format("Manuelle Internetadresse: %s. UDP %d muss auf diesen Rechner zeigen.",[address,transport.port])
	changed.emit()
	return true

func _transport_error(message: String) -> void:
	if _closing or not active: return
	if state=="reconnecting":
		connection_hint = message
	else:
		_fail(message)

func _connected() -> void:
	if _closing or not active or state=="error": return
	_last_packet_at = _clock
	_packet_budgets.clear()
	_invalid_packets=0
	_voice_seen.clear()
	_voice_highest=-1
	if is_host:
		_handshake_deadline = _clock+5.0
	elif not _hello_sent:
		_hello_sent = true
		_send({"kind":"hello","version":Protocol.VERSION,"build":Protocol.BUILD,"world_revision":Protocol.WORLD_REVISION,"content_fingerprint":Registry.fingerprint(),"resume":_client_token,"invite":_invite_secret,"name":display_name,"voice_member_keys":true})

func _disconnected(reason: String) -> void:
	if _closing or not active or state=="offline": return
	# A silent but still-open relay link must be replaced too. Otherwise old
	# queued bytes keep the client attached to a host link that already expired.
	if _websocket != null:
		WebSocketDrain.retire(_websocket, get_tree())
		_websocket = null
	if is_host and not relay_url.is_empty():
		for link: Dictionary in _slots.values():
			link.connected=false
			link._authenticated=false
			link._ready_for_snapshots=false
			link.remote_input={}
			link._pending_remote={}
			link._input_edges=[]
		_peers.clear()
	peer_connected = false
	_authenticated = false
	_hello_sent = false
	_rejecting = false
	_ready_for_snapshots = false
	remote_input.clear()
	_pending_remote.clear()
	_pressed.clear()
	_released.clear()
	_input_edges.clear()
	_events.clear()
	if is_instance_valid(game) and is_instance_valid(game.get("voice")): game.voice.reset()
	if is_instance_valid(game) and game.started:
		match_paused = true
		get_tree().paused = true
		state = "reconnecting"
		if _reconnect_deadline==0: _reconnect_deadline = _clock+RECONNECT_SECONDS
		_retry_at = _clock+1.0
		connection_hint = "Die Schicht wartet auf die Verbindung. Eingaben wurden angehalten."
	elif is_host:
		state = "lobby"
		connection_hint = "Partner getrennt. Teile den Code, um erneut zu verbinden."
	elif not relay_url.is_empty() and not _relay_resume_token.is_empty():
		# A brief host relay outage can happen before the first match too.
		# Keep this authenticated room identity available for the same handshake.
		state = "reconnecting"
		if _reconnect_deadline==0: _reconnect_deadline = _clock+RECONNECT_SECONDS
		_retry_at = _clock+1.0
		connection_hint = "Die Schicht wartet auf die Verbindung. Eingaben wurden angehalten."
	else:
		_fail(LocaleText.format("Verbindung zum Gastgeber verloren. %s",reason))
	changed.emit()

func _connect_relay(action: String) -> void:
	if not (relay_url.begins_with("ws://") or relay_url.begins_with("wss://")):
		_fail("Der optionale Server benötigt eine ws://- oder wss://-Adresse.")
		return
	var relay_authority:=relay_url.trim_prefix("ws://").trim_prefix("wss://").get_slice("/",0).to_lower()
	var local_relay:=RegEx.new()
	local_relay.compile("^(localhost|127\\.0\\.0\\.1|\\[::1\\])(?::[0-9]{1,5})?$")
	if relay_url.begins_with("ws://") and local_relay.search(relay_authority)==null:
		_fail("Für externe Vermittlungsserver ist eine verschlüsselte wss://-Adresse erforderlich.")
		return
	_websocket = WebSocketPeer.new()
	_websocket.inbound_buffer_size = Protocol.MAX_PACKET*2
	_websocket.outbound_buffer_size = Protocol.MAX_PACKET*2
	_websocket.max_queued_packets = 64
	_relay_requested = false
	_relay_action = action
	if _websocket.connect_to_url(relay_url)!=OK:
		_fail("Der Vermittlungsserver konnte nicht kontaktiert werden.")
	_deadline = _clock+12.0

func _poll_relay() -> void:
	if _websocket==null: return
	_websocket.poll()
	var socket_state := _websocket.get_ready_state()
	if socket_state==WebSocketPeer.STATE_OPEN:
		if not _relay_requested:
			_relay_requested = true
			var message := {"op":_relay_action,"version":Protocol.VERSION,"build":Protocol.BUILD,"name":"Gastgeber" if is_host else "Partner"}
			if _relay_action=="join": message.code = _join_code
			if _relay_action=="resume": message.token = _relay_resume_token
			_relay_text(message)
		var handled:=0
		var started_poll:=Time.get_ticks_usec()
		while _websocket!=null and _websocket.get_available_packet_count()>0 and handled<32 and Time.get_ticks_usec()-started_poll<2000:
			handled+=1
			var packet := _websocket.get_packet()
			if _websocket.was_string_packet():
				if packet.size()>8192: continue
				var decoder := JSON.new()
				if decoder.parse(packet.get_string_from_utf8()) == OK and decoder.data is Dictionary: _relay_control(decoder.data)
			else:
				if packet.size()<2: continue
				var sender:=int(packet[0])
				if sender not in [1,2,3,4] or (not is_host and sender!=1) or (is_host and sender==1): continue
				_packet_from(packet.slice(1),sender)
	elif socket_state==WebSocketPeer.STATE_CLOSED:
		_websocket = null
		if _relay_resume_token.is_empty():
			_fail("Der Vermittlungsserver ist nicht erreichbar.")
		else:
			_disconnected("Vermittlungsserver getrennt.")
			state = "reconnecting"
			if _reconnect_deadline==0: _reconnect_deadline = _clock+RECONNECT_SECONDS
			_retry_at = _clock+1.0
			changed.emit()

func _relay_text(message: Dictionary) -> void:
	if _websocket!=null and _websocket.get_ready_state()==WebSocketPeer.STATE_OPEN:
		_websocket.send_text(JSON.stringify(message))

func _relay_control(message: Dictionary) -> void:
	if not _valid_relay_control(message): return
	match message.op:
		"hosted","joined","resumed":
			room_code = message.code
			_relay_resume_token = message.resume_token
			_relay_action = ""
			_deadline = 0
			if state!="reconnecting": state = "lobby"
			connection_hint = "Verbindung über den gewählten Vermittlungsserver."
			if not is_host and message.get("peer_connected",false) and not peer_connected: _connected()
			changed.emit()
		"peer_joined":
			if is_host:
				var sender:=int(message.player_id)
				if not _peers.has(sender): _peer_connected_id(sender)
			elif not peer_connected: _connected()
		"peer_left":
			if is_host:
				_peer_disconnected_id(int(message.player_id),"Partner getrennt.")
			elif message.reason=="left" or message.reconnect_seconds==0:
				_fail("Der Gastgeber hat die Sitzung geschlossen.")
			elif peer_connected: _disconnected("Partner getrennt.")
		"room_closed":
			_fail("Der Gastgeber hat die Sitzung geschlossen.")
		"error":
			_fail(message.message)

func _valid_relay_control(message: Dictionary) -> bool:
	if not active or relay_url.is_empty() or not _relay_requested or state not in ["connecting","reconnecting","lobby","playing"]: return false
	if not message.get("op") is String: return false
	var op: String=message.op
	var keys: Dictionary={
		"hosted":["op","code","role","token","resume_token","started","player_id"],
		"joined":["op","code","role","resume_token","started","peer_connected","player_id"],
		"resumed":["op","code","role","resume_token","started","peer_connected","player_id"],
		"peer_joined":["op","role","name","resumed","player_id"],
		"peer_left":["op","role","reason","reconnect_seconds","player_id"],
		"room_closed":["op","reason"],"error":["op","code","message"],
		"status":["op","started"],"pong":["op","id"],"left":["op"],"kicked":["op"]}
	if not keys.has(op): return false
	for key in message:
		if not key in keys[op]: return false
	if op in ["hosted","joined","resumed","peer_joined","peer_left"]:
		var slot=message.get("player_id",0)
		if not (slot is int or slot is float) or not is_finite(float(slot)) or float(slot)!=floorf(float(slot)) or slot<1 or slot>4: return false
	if op in ["hosted","joined","resumed"]:
		if (is_host and message.player_id!=1) or (not is_host and message.player_id==1): return false
		if not message.get("code") is String or message.code.length()!=6: return false
		for character in message.code:
			if character not in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789": return false
		if not message.get("resume_token") is String or message.resume_token.length()!=32: return false
		for character in message.resume_token:
			if character not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-": return false
		if not message.get("started") is bool or not message.get("role") is String or message.role!=("host" if is_host else "guest"): return false
		if op=="hosted":
			if not is_host or _relay_action!="host" or state!="connecting" or not message.get("token") is String or message.token!=message.resume_token or message.started: return false
		elif op=="joined":
			if is_host or _relay_action!="join" or state!="connecting": return false
			if message.code!=_join_code.replace("-","").replace(" ",""): return false
			if not message.get("peer_connected") is bool or not message.peer_connected: return false
		else:
			if _relay_action!="resume" or state!="reconnecting" or not message.get("peer_connected") is bool: return false
			if room_code.is_empty() or message.code!=room_code or message.resume_token==_relay_resume_token: return false
		return true
	if op in ["peer_joined","peer_left"]:
		if (is_host and message.player_id==1) or (not is_host and message.player_id!=1): return false
		if room_code.is_empty() or not message.get("role") is String or message.role!=("guest" if is_host else "host"): return false
		if op=="peer_joined":
			if not message.get("name") is String or message.name.is_empty() or message.name.length()>24 or not message.get("resumed") is bool: return false
		else:
			if not message.get("reason") in ["left","connection_lost","timeout","host_rejected"]: return false
			var seconds=message.get("reconnect_seconds")
			if not (seconds is int or seconds is float) or not is_finite(float(seconds)) or seconds<0 or seconds>120: return false
		return true
	if op=="room_closed": return not room_code.is_empty() and message.get("reason") in ["host_left","host_timeout","host_rejected"]
	if op=="error":
		if not message.get("code") is String or message.code.is_empty() or message.code.length()>48: return false
		return message.get("message") is String and not message.message.is_empty() and message.message.length()<=240
	if op=="status": return not room_code.is_empty() and message.get("started") is bool
	if op=="pong": return (message.get("id") is int and message.id>=-9007199254740992 and message.id<=9007199254740992) or (message.get("id") is String and message.id.length()<=64)
	return true

func _send(message: Dictionary,reliable := true,target_id: int=0) -> bool:
	if not active: return false
	var packet:=Protocol.encode(message)
	if packet.is_empty(): return false
	return _send_encoded(packet,reliable,target_id)

func _send_encoded(packet: PackedByteArray,reliable: bool,target_id: int=0,channel: int=-1) -> bool:
	var targets: Array=[]
	if not is_host: targets=[1]
	elif target_id>0: targets=[target_id]
	elif target_id==0 and _context_peer>0: targets=[_context_peer]
	else:
		for id in _peers:
			if _peers[id].connected and _peers[id]._authenticated: targets.append(id)
	# Retain the direct single-link fixture path used by low-level regressions.
	if targets.is_empty() and _peers.is_empty() and is_instance_valid(transport) and transport.connected_peer>0: targets=[transport.connected_peer]
	# Keep the authenticated recipient list in relay mode as well. A room seat
	# alone does not mean the game handshake has completed.
	var accepted:=false
	for target in targets:
		if relay_url.is_empty():
			var use_reliable:=reliable or (channel!=2 and packet.size()>1200)
			accepted=(is_instance_valid(transport) and transport.send(packet,use_reliable,channel,int(target))==OK) or accepted
		else:
			if _websocket==null or _websocket.get_ready_state()!=WebSocketPeer.STATE_OPEN: continue
			if not reliable and _websocket.get_current_outbound_buffered_amount()>(8192 if channel==2 else Protocol.MAX_PACKET): continue
			var routed:=PackedByteArray([int(target)|(128 if channel==2 else 0)])
			routed.append_array(packet)
			var result := _websocket.send(routed,WebSocketPeer.WRITE_MODE_BINARY)
			accepted=(result==OK) or accepted
			if result!=OK and reliable:
				_websocket.close()
				_disconnected("Vermittlungsserver getrennt.")
	return accepted

func send_voice(pcm: PackedByteArray) -> bool:
	if not active or (not is_host and not _authenticated) or not peer_connected or state not in ["lobby","playing"] or pcm.size()!=VoiceCodec.BYTES: return false
	_voice_seq+=1
	var message:={"kind":"voice","seq":_voice_seq,"generation":_generation,"rate":VoiceCodec.RATE,"pcm":pcm,"player_id":local_player_id}
	if is_host: return _broadcast_voice(message)
	if _voice_member_keys_supported:
		message.member_key = str(_voice_members.get(str(local_player_id), ""))
	var packet:=Protocol.encode(message)
	return not packet.is_empty() and packet.size()<=1200 and _send_encoded(packet,false,-1,2)

func _broadcast_voice(message: Dictionary, except_peer: int = 0) -> bool:
	# Keep existing net-20 peers usable: only a guest that offered this feature
	# receives the added field. The host always supplies the speaker's own key.
	# Most rooms need only one version. Encode each required variant once,
	# after authentication and sender exclusion select an actual recipient.
	var packets: Dictionary = {}
	var accepted := false
	for peer_id in _peers:
		var link: Dictionary = _peers[peer_id]
		if peer_id == except_peer or not link._authenticated: continue
		var binding: bool = bool(link.get("voice_member_keys", false))
		if not packets.has(binding): packets[binding]=_encode_voice_packet(message,binding)
		var packet: PackedByteArray = packets[binding]
		if not packet.is_empty() and packet.size() <= 1200:
			accepted = _send_encoded(packet, false, int(peer_id), 2) or accepted
	if _peers.is_empty():
		var packet := _encode_voice_packet(message,false)
		return not packet.is_empty() and packet.size() <= 1200 and _send_encoded(packet,false,-1,2)
	return accepted

func _encode_voice_packet(message: Dictionary,binding: bool) -> PackedByteArray:
	var envelope := message.duplicate()
	envelope.erase("member_key")
	if binding: envelope.member_key=str(_voice_members.get(str(message.player_id),""))
	return Protocol.encode(envelope)

func _allow_message(kind: String) -> bool:
	var rate:=15.0
	var capacity:=20.0
	if kind.begins_with("voice"):
		rate=55.0
		capacity=10.0
	elif kind in ["input","snapshot","snapshot_ack","effects"]:
		rate=40.0
		capacity=30.0
		if kind=="input":
			# At most one sampled input per physics tick. Accommodate the
			# supported two-second reliable catch-up without discarding taps.
			rate=60.0
			capacity=160.0
	elif kind in ["ping","pong","pause"]:
		rate=4.0
		capacity=6.0
	elif kind in ["hello","welcome","start","ready"]:
		rate=1.0
		capacity=4.0
	elif kind in ["chat_send", "chat_private_send"]:
		rate=4.0
		capacity=6.0
	elif kind in ["chat_name", "crew_identity", "crew_preferences"]:
		rate=0.5
		capacity=2.0
	elif kind=="chat_history":
		rate=1.0
		capacity=4.0
	var bucket:Dictionary=_packet_budgets.get(kind,{"at":_clock,"tokens":capacity})
	bucket.tokens=minf(capacity,float(bucket.tokens)+maxf(0.0,_clock-float(bucket.at))*rate)
	bucket.at=_clock
	var allowed:bool=bucket.tokens>=1.0
	if allowed: bucket.tokens-=1.0
	_packet_budgets[kind]=bucket
	return allowed

func _packet(packet: PackedByteArray) -> void:
	if not active or state=="error": return
	var channel: int=transport.last_packet_channel if relay_url.is_empty() and is_instance_valid(transport) else -1
	if not is_host and _decoder!=null:
		if not _decoder.submit(packet,channel): _fail("Der Spielstand konnte nicht synchronisiert werden. Bitte erneut verbinden.")
		return
	_receive_packet_message(Protocol.decode(packet),channel)

func _receive_packet_message(message: Dictionary, channel: int) -> void:
	if not active or state=="error": return
	if message.is_empty() or not Messages.valid(message,is_host):
		_invalid_packet()
		return
	var kind := str(message.kind)
	# The room node outlives the mission scene. Keep room chat flowing while
	# high-frequency world updates wait for the newly bound scene. A small
	# reliable-control queue preserves handshakes and lobby changes in that gap.
	if not is_instance_valid(game) or game.is_queued_for_deletion():
		if kind not in ["chat_send","chat_private_send","chat_message","chat_history","chat_ack","ping","pong","reject"]:
			if kind in ["hello","welcome","lobby","start","ready","pause","chat_name","crew_identity","crew_preferences","leave"] and _deferred_room_packets.size()<32:
				_deferred_room_packets.append({"message":message.duplicate(true),"channel":channel,"peer":_context_peer})
			return
	if relay_url.is_empty() and is_instance_valid(transport) and ((kind=="voice")!=(channel==2)):
		_invalid_packet()
		return
	if (kind.begins_with("chat_") or kind.begins_with("crew_")) and relay_url.is_empty() and is_instance_valid(transport) and channel!=0:
		_invalid_packet()
		return
	if kind.begins_with("chat_") and (not _authenticated or _rejecting): return
	if kind.begins_with("crew_") and (not _authenticated or _rejecting): return
	if not _allow_message("voice:"+str(message.get("player_id",0)) if kind=="voice" else kind):
		# A malformed or unauthenticated source receives no chat response. A
		# valid sender gets bounded feedback while its gameplay channel remains
		# independent of this control-message budget.
		if kind=="chat_name" and is_host and _peers.has(_context_peer):
			_queue_chat_name(_peers[_context_peer],str(message.name))
		elif kind in ["chat_send", "chat_private_send"] and is_host and _authenticated and not _rejecting and _peers.has(_context_peer):
			var link: Dictionary=_peers[_context_peer]
			var slot: int=int(link.slot)
			var receipt: Dictionary=link.get("chat_receipt",{})
			var request_id: int=int(message.request)
			if request_id>int(receipt.get("request",0)):
				link.chat_receipt={"request":request_id,"text":message.text,"preset":str(message.get("preset", "")),"recipient_id":int(message.get("recipient_id", 0)),"accepted":false,"error_code":"rate"}
				receipt=link.chat_receipt
			if _clock>=float(_chat_reject_at.get(slot,-1.0)):
				_chat_reject_at[slot]=_clock+0.5
				var repeated: bool=request_id==int(receipt.get("request",0)) and message.text==receipt.get("text") and str(message.get("preset", ""))==receipt.get("preset") and int(message.get("recipient_id", 0))==int(receipt.get("recipient_id", 0))
				_send_chat_ack(request_id,repeated and bool(receipt.get("accepted",false)),str(receipt.get("error_code","stale")) if repeated else "stale")
		return
	if kind=="hello" and is_host:
		_accept_hello(message)
		return
	if kind=="welcome" and not is_host:
		if _authenticated or not _hello_sent: return
		if message.get("version",0)!=Protocol.VERSION or message.get("build","")!=Protocol.BUILD or message.get("world_revision",0)!=Protocol.WORLD_REVISION:
			_fail("Die Spielversionen passen nicht zusammen.")
			return
		var content_error := _content_error(message)
		if not content_error.is_empty():
			_fail(content_error)
			return
		local_player_id=int(message.get("player_id",2))
		_client_token = str(message.get("token",""))
		_voice_member_keys_supported = bool(message.get("voice_member_keys", false))
		_authenticated = true
		_social._local_identity.clear()
		_social._last_preferences = [-1]
		peer_connected = true
		_deadline = 0
		# Welcome may consume this poll's time budget before Start is received.
		# Keep the existing reconnect deadline until a live world is re-bound.
		if not game.started:
			_reconnect_deadline = 0
			state = "lobby"
		_apply_lobby(message)
		changed.emit()
		return
	if kind=="reject" and not is_host:
		_fail(str(message.get("message","Verbindung abgelehnt.")))
		return
	if not _authenticated or _rejecting: return
	_last_packet_at = _clock
	match kind:
		"chat_send", "chat_private_send":
			_handle_chat_request(message)
		"crew_identity":
			if is_host and _peers.has(_context_peer):
				var identity: Dictionary = message.identity
				var link: Dictionary = _peers[_context_peer]
				if not identity.is_empty() and identity.context != str(link._guest_token).sha256_text().left(48): return
				_social.accept(int(link.slot), identity)
				_send_lobby()
		"crew_preferences":
			if is_host and _peers.has(_context_peer): _peers[_context_peer].blocked_slots = message.blocked.duplicate()
		"chat_name":
			if is_host and _peers.has(_context_peer):
				if _apply_chat_name(_peers[_context_peer],str(message.name)): _send_lobby()
		"chat_message":
			_receive_chat(message.message)
		"chat_history":
			_receive_chat_history(message.messages)
		"chat_ack":
			_receive_chat_ack(message)
		"voice":
			var speaker: int=int(message.get("player_id",0))
			if speaker<1 or speaker>4 or speaker==local_player_id or message.generation!=_generation: return
			if is_host and (not _peers.has(_context_peer) or speaker!=int(_peers[_context_peer].slot)): return
			if not is_host and not is_player_connected(speaker): return
			var needs_key: bool = bool(_peers[_context_peer].get("voice_member_keys", false)) if is_host else _voice_member_keys_supported
			if needs_key or message.has("member_key"):
				var member: String = str(_voice_members.get(str(speaker), ""))
				if member.is_empty() or message.get("member_key", "") != member: return
			var stream: Dictionary=_voice_sources.get(speaker,{"highest":-1,"seen":{}})
			if message.seq<=int(stream.highest)-10 or stream.seen.has(message.seq): return
			stream.received=int(stream.get("received",0))+1
			stream.seen[message.seq]=true
			stream.highest=maxi(int(stream.highest),message.seq)
			for sequence in stream.seen.keys():
				if sequence<int(stream.highest)-10: stream.seen.erase(sequence)
			_voice_sources[speaker]=stream
			_voice_seen=stream.seen
			_voice_highest=int(stream.highest)
			if is_instance_valid(game.get("voice")):
				var audio_ok: bool=game.voice.receive(message)
				stream.audio_accepted=int(stream.get("audio_accepted",0))+(1 if audio_ok else 0)
			if is_host:
				_broadcast_voice(message, _context_peer)
		"lobby":
			if not is_host: _apply_lobby(message)
		"command":
			if is_host and message.generation==_generation:
				_handle_command(str(message.get("command","")),message.get("args",{}),int(_peers[_context_peer].slot) if _peers.has(_context_peer) else 2)
		"start":
			if not is_host: _receive_start(message)
		"ready":
			if is_host and game.started and message.get("generation",-1)==_generation:
				_ready_for_snapshots=true
				if _peers.has(_context_peer): _peers[_context_peer]._ready_for_snapshots=true
				if _all_ready():
					state="playing"
					_loading=false
					_reconnect_deadline=0
					_set_pause(false)
					_send({"kind":"pause","generation":_generation,"paused":match_paused},true,-1)
				_send_snapshot(true)
				changed.emit()
		"input":
			if is_host: _receive_input(message)
		"snapshot":
			if not is_host and world!=null and message.get("world",null) is Dictionary and message.get("generation",-1)==_generation:
				if not message.get("seq",null) is int: return
				if not message.get("paused",false) is bool: return
				var seq := int(message.get("seq",-1))
				if seq<=_received_seq: return
				if world.apply(message.world,true):
					if message.has("music") and is_instance_valid(game.audio.live_music): game.audio.live_music.apply_music_state(message.music)
					_snapshot_failures=0
					_receive_achievements(message.get("achievements",[]))
					_received_seq = seq
					_send({"kind":"snapshot_ack","seq":seq,"generation":_generation},false)
					received_snapshots += 1
					_loading = false
					state = "playing"
					_set_pause(bool(message.get("paused",false)))
				else:
					_snapshot_failures+=1
					_set_pause(true)
					connection_hint=LocaleText.text("Weltabgleich fehlgeschlagen. Neuer vollständiger Spielstand wird angefordert.")
					if _clock-_last_resync_at>=1.0:
						_last_resync_at=_clock
						_send({"kind":"resync","generation":_generation})
					if _snapshot_failures>=5:
						_fail("Der Spielstand konnte nicht synchronisiert werden. Bitte erneut verbinden.")
		"resync":
			if is_host and message.generation==_generation: _send_snapshot(true)
		"snapshot_ack":
			if is_host and message.generation==_generation and message.seq<=_snapshot_seq:
				_snapshot_ack=maxi(_snapshot_ack,message.seq)
		"pause":
			if message.generation!=_generation: return
			if not message.get("paused",false) is bool: return
			if is_host:
				pause_match(bool(message.get("paused",false)))
			else:
				_set_pause(bool(message.get("paused",false)))
		"ping":
			_send({"kind":"pong","at":message.get("at",0.0)},false)
		"pong":
			var at = message.get("at",null)
			if float(at)==_pong_at and at<=_clock:
				ping_ms = clampi(roundi((_clock-float(at))*1000),0,9999)
				_pong_at=-1.0
		"notice":
			if not is_host:
				game.notify(LocaleText.message_text(message.message) if message.has("message") else LocaleText.text(str(message.get("text","")).left(180)))
		"effects":
			if not is_host and game.started and message.get("generation",-1)==_generation and message.get("events",null) is Array:
				_receive_events(message.events)
		"leave":
			if is_host and _peers.has(_context_peer):
				var leaving_peer:=_context_peer
				if is_instance_valid(transport): transport.disconnect_guest(leaving_peer)
				_peer_disconnected_id(leaving_peer,"Partner hat die Sitzung verlassen.")
			else: _fail("Der Gastgeber hat die Sitzung geschlossen.")

func _invalid_packet() -> void:
	_invalid_packets+=1
	if _invalid_packets<12: return
	if is_host:
		if not _rejecting: _reject_guest("Ungültige Netzwerkdaten. Die Verbindung wurde beendet.")
	else:
		_fail("Ungültige Netzwerkdaten. Die Verbindung wurde beendet.")

func _content_error(message: Dictionary) -> String:
	if not Registry.diagnostics().is_empty():
		return "Die Spielinhalte dieser Installation sind ungültig. Installiere die passende Spielversion erneut."
	if not message.has("content_fingerprint"):
		return "Die Gegenstelle prüft Spielinhalte noch nicht. Beide Spieler benötigen die aktuelle Spielversion und dieselben Inhaltspakete."
	if not Messages.valid_content_fingerprint(message.content_fingerprint) or message.content_fingerprint!=Registry.fingerprint():
		return "Die Spielinhalte passen nicht zusammen. Beide Spieler benötigen dieselbe Spielversion und dieselben Inhaltspakete."
	return ""

func _accept_hello(message: Dictionary) -> void:
	if _authenticated or _rejecting: return
	if message.get("version",0)!=Protocol.VERSION or message.get("build","")!=Protocol.BUILD or message.get("world_revision",0)!=Protocol.WORLD_REVISION:
		_reject_guest("Die Spielversionen passen nicht zusammen.")
		return
	var content_error := _content_error(message)
	if not content_error.is_empty():
		_reject_guest(content_error)
		return
	var assigned:=0
	var recovered_receipt: Dictionary={}
	var resume: String=str(message.get("resume",""))
	for slot in _slots:
		var saved: Dictionary=_slots[slot]
		if not resume.is_empty() and Crypto.new().constant_time_compare(resume.to_utf8_buffer(),str(saved._guest_token).to_utf8_buffer()):
			var old_wire: int=int(saved.get("wire",0))
			if old_wire!=_context_peer and _peers.has(old_wire):
				_peers.erase(old_wire)
				if is_instance_valid(transport): transport.disconnect_guest(old_wire)
			assigned=int(slot)
			_guest_token=saved._guest_token
			recovered_receipt=saved.get("chat_receipt",{}).duplicate(true)
			break
	if game.started and assigned==0:
		_reject_guest("Die Schicht läuft bereits. Nur die bisherige Crew kann wieder beitreten.")
		return
	if not game.started and relay_url.is_empty() and (_invite_secret.is_empty() or not Crypto.new().constant_time_compare(str(message.get("invite","")).to_utf8_buffer(),_invite_secret.to_utf8_buffer())):
		_reject_guest("Der Raumcode ist abgelaufen oder unvollständig. Aktuellen Code vom Gastgeber kopieren.")
		return
	if assigned==0 and connected_player_count()>=max_players:
		_reject_guest("Der Raum ist voll.")
		return
	if assigned==0:
		for slot in range(2,max_players+1):
			if not _slots.has(slot): assigned=slot; break
	if assigned==0:
		_reject_guest("Der Raum ist voll.")
		return
	_handshake_deadline=0
	_authenticated=true
	peer_connected=true
	_remote_seq=-1
	_snapshot_ack=_snapshot_seq
	_last_input_at=_clock
	_ready_for_snapshots=false
	if _peers.has(_context_peer):
		var link: Dictionary=_peers[_context_peer]
		link.slot=assigned
		link._authenticated=true
		link._guest_token=_guest_token
		link.chat_name=str(message.get("name",""))
		link.chat_receipt=recovered_receipt
		link.voice_member_keys = bool(message.get("voice_member_keys", false))
		_slots[assigned]=link
	if not game.started and character_owner(str(game.selected_characters[assigned-1]),assigned)>0:
		for starter: String in PartyConfig.DEFAULT_CHARACTERS:
			if character_owner(starter,assigned)==0:
				game.selected_characters[assigned-1] = starter
				break
	var welcome:=_lobby_message()
	welcome.kind="welcome"
	welcome.version=Protocol.VERSION
	welcome.build=Protocol.BUILD
	welcome.world_revision=Protocol.WORLD_REVISION
	welcome.content_fingerprint=Registry.fingerprint()
	welcome.token=_guest_token
	welcome.player_id=assigned
	if bool(message.get("voice_member_keys", false)): welcome.voice_member_keys = true
	_send(welcome)
	_replay_chat()
	if game.started:
		_load_deadline=_clock+15.0
		_send_start(false)
	else:
		state="lobby"
	_send_lobby()
	changed.emit()

func _reject_guest(message: String) -> void:
	_rejecting = true
	_pending_remote.clear()
	remote_input.clear()
	_pressed.clear()
	_released.clear()
	_input_edges.clear()
	_send({"kind":"reject","message":message})
	_handshake_deadline = 0
	if is_instance_valid(transport):
		var rejected = transport
		var peer_id := _context_peer if _context_peer>0 else int(transport.connected_peer)
		get_tree().create_timer(0.2,true).timeout.connect(func():
			if is_instance_valid(rejected) and rejected.remote_peers.has(peer_id): rejected.disconnect_guest(peer_id))
	else:
		_relay_text({"op":"kick","player_id":_context_peer})

func _lobby_message() -> Dictionary:
	var slots: Array=[1]+_slots.keys().filter(func(slot):return is_player_connected(int(slot)))
	var names: Dictionary={}
	for slot in slots: names[str(slot)]=_chat_author_name(int(slot))
	if names!=chat_names:
		chat_names=names
		chat_changed.emit()
	var service := ""
	if _social._host_context.is_empty(): _social._host_context = Crypto.new().generate_random_bytes(24).hex_encode()
	var members := {"1":_social._host_context}
	for slot in _slots: members[str(slot)] = str(_slots[slot]._guest_token).sha256_text().left(48)
	_sync_voice_members(members)
	_social.member_keys = members.duplicate()
	if "social" in game and is_instance_valid(game.social) and game.social.connection_state == "online": service = str(game.social.server_url)
	return {"kind":"lobby","characters":game.selected_characters.duplicate(),"options":ScenarioCatalog.validate(game.hud.scenario_options),"story":game.hud.story_selected,"count":connected_player_count(),"capacity":max_players,"slots":slots,"names":chat_names.duplicate(),"identities":_social.identities.duplicate(true),"social_service":service,"members":members,"short_code":short_room_code}

func _apply_lobby(message: Dictionary) -> void:
	short_room_code = str(message.get("short_code", ""))
	var previous_names: Dictionary = chat_names.duplicate()
	room_social_service = str(message.get("social_service", ""))
	if message.get("characters",null) is Array and message.characters.size() in [2,3,4]:
		for index in message.characters.size():
			var id := str(message.characters[index])
			if CharacterCatalog.contains(id): game.selected_characters[index] = id
	if message.has("player_id"): local_player_id=int(message.player_id)
	if message.has("slots"): _connected_slots=message.slots.duplicate()
	if message.has("capacity"): max_players=int(message.capacity)
	if message.has("names"):
		chat_names=message.names.duplicate()
		chat_changed.emit()
	_sync_voice_members(message.get("members", {}))
	_social.apply_roster(message.get("identities", {}), message.get("members", {}))
	for slot in chat_names:
		if previous_names.get(slot) != chat_names[slot]: _social.refresh_name(int(slot))
	_social.preferences()
	if message.get("options",null) is Dictionary:
		game.hud.scenario_options = ScenarioCatalog.validate(message.options)
	if message.get("story") is bool: game.hud.story_selected=message.story
	changed.emit()

func _sync_voice_members(members: Dictionary) -> void:
	# Replay protection and buffered speech belong to a member, not a reusable
	# player number. This also covers guests receiving a compacted lobby roster.
	for slot in range(1, 5):
		var key := str(slot)
		if _voice_members.get(key, "") == members.get(key, ""): continue
		_voice_sources.erase(slot)
		_packet_budgets.erase("voice:" + key)
		if is_instance_valid(game) and is_instance_valid(game.get("voice")) and game.voice.has_method("retire_sender"):
			game.voice.retire_sender(slot)
	_voice_members = members.duplicate()

func start_match(options: Dictionary,characters: Array) -> void:
	if not active or not is_host or not peer_connected or state!="lobby": return
	if not _transition_transport_ready(false): return
	_requested_pause = false
	_compact_lobby_slots()
	_match_player_count=connected_player_count()
	_expedition_payload.clear()
	_match_options = ScenarioCatalog.validate(options)
	_match_characters = PartyConfig.unique_characters(_valid_characters(characters))
	_match_story=game.hud.story_selected
	_generation += 1
	_begin_local_match()
	_send_start(true)

func resume_campaign() -> bool:
	if not active or not is_host or not peer_connected or not _authenticated or state!="lobby" or _loading or game.started: return false
	if not _transition_transport_ready(false): return false
	_compact_lobby_slots()
	_match_player_count=connected_player_count()
	var payload: Dictionary=game.expedition.saved_resume_payload(game.selected_characters.slice(1,_match_player_count))
	if payload.is_empty():
		connection_hint=game.campaign.last_error if not game.campaign.last_error.is_empty() else LocaleText.text("Gespeicherte Kampagne konnte nicht geladen werden.")
		game.notify(connection_hint)
		changed.emit()
		return false
	_expedition_payload=payload.duplicate(true)
	_requested_pause = false
	_match_options=payload.options.duplicate()
	_match_characters=payload.checkpoint.character_ids.duplicate()
	_match_story=false
	_generation+=1
	_begin_local_match()
	if state!="playing": return false
	_send_start(true)
	return true

func _valid_characters(characters: Array) -> Array:
	return PartyConfig.normalize_characters(characters,4)

func _begin_local_match() -> void:
	if is_host:
		for link: Dictionary in _peers.values():
			link._ready_for_snapshots=false
			link._snapshot_seq=0
			link._snapshot_ack=0
			link._remote_seq=-1
			link.remote_input={}
			link._pending_remote={}
			link._pressed=[]
			link._released=[]
			link._input_edges=[]
	_loading = true
	# The host's campaign is a replica here. Never replace the guest's separate
	# local campaign when restore() starts a defense or writes a checkpoint.
	if not is_host: game.campaign.persistence_enabled=false
	_events.clear()
	_voice_sources.clear()
	_load_deadline = _clock+15.0
	_snapshot_seq = 0
	_snapshot_ack = 0
	_ack_clock=0.0
	_received_seq = -1
	_ready_for_snapshots = false
	# Same-generation reconnects may already have sent input after Welcome.
	# Keep the outgoing counter monotonic across scene/rebind handshakes.
	_remote_seq = -1
	_input_clock = 0.0
	_last_input_at = -100.0
	remote_input.clear()
	_pending_remote.clear()
	_pressed.clear()
	_released.clear()
	_local_pressed.clear()
	_local_released.clear()
	_input_edges.clear()
	for index in _match_characters.size(): game.selected_characters[index] = str(_match_characters[index])
	if not game.started:
		game.story_mode=_match_story
		if not _expedition_payload.is_empty():
			if not game.expedition.restore(_expedition_payload):
				_fail("Kampagnenstand konnte nicht wiederhergestellt werden.")
				return
		else:
			game.start_scenario(_match_player_count,_match_options)
	if is_host:
		for worker in game.players:
			if worker.player_id>1 and not _slots.has(worker.player_id): _retire_worker(worker)
	if not is_host and _decoder==null:
		_decoder=preload("res://scripts/network_decode_worker.gd").new()
		if _decoder.start()!=OK: _decoder=null
	world = load("res://scripts/network_world.gd").new()
	world.bind(game)
	state = "playing"
	game.hud.overlay = ""
	match_paused = true
	get_tree().paused = true
	if not is_host:
		_reconnect_deadline = 0
		world.freeze_client()
		_send({"kind":"ready","generation":_generation})
	elif _slots.is_empty():
		# An already started host may continue after the last guest leaves.
		# There is no remote ready packet to finish this reload's handshake.
		_loading=false
		_load_deadline=0
		_ready_for_snapshots=true
		_set_pause(false)
	changed.emit()

func _send_start(reset: bool) -> void:
	var message := {"kind":"start","options":_match_options,"characters":_match_characters,"story":_match_story,"reset":reset,"generation":_generation,"count":_match_player_count,"capacity":max_players,"slots":[1]+_slots.keys() if is_host else _connected_slots}
	if not _expedition_payload.is_empty(): message.expedition=_expedition_payload.duplicate(true)
	_send(message)

func _receive_start(message: Dictionary) -> void:
	if not message.get("options",null) is Dictionary or not message.get("characters",null) is Array: return
	if not message.get("generation",null) is int: return
	if not message.get("reset",false) is bool: return
	if not message.get("story",false) is bool: return
	if message.generation<_generation or (message.generation==_generation and state!="reconnecting"): return
	if message.generation>_generation+1: return
	if not Messages.valid(message,false): return
	_expedition_payload=message.get("expedition",{}).duplicate(true)
	_generation = int(message.generation)
	_match_player_count=int(message.get("count",2))
	_match_options = ScenarioCatalog.validate(message.options)
	_match_characters = _valid_characters(message.characters)
	_match_story=bool(message.get("story",false))
	if game.started and bool(message.get("reset",false)):
		_reload_game()
	else:
		_begin_local_match()

func send_command(kind: String,args: Dictionary={}) -> void:
	if not active: return
	if is_host:
		_handle_command(kind,args,1)
	elif peer_connected:
		_send({"kind":"command","command":kind,"args":args,"generation":_generation})

func _handle_command(kind: String,args: Dictionary,player_id: int) -> void:
	if _clock-_command_window>=1.0:
		_command_window = _clock
		_command_count = 0
	_command_count += 1
	if _command_count>30: return
	if kind=="character" and not game.started:
		var id := str(args.get("id",""))
		if state != "lobby" or not is_player_connected(player_id) or player_id<1 or player_id>PartyConfig.MAX_PLAYERS: return
		if CharacterCatalog.contains(id) and character_owner(id,player_id)==0:
			game.selected_characters[player_id-1] = id
			_send_lobby()
			changed.emit()
		elif CharacterCatalog.contains(id):
			if player_id==1: game.notify(LocaleText.text("Diese Figur ist bereits in der Crew. Wähle eine andere."))
			else: _send({"kind":"notice","text":"Diese Figur ist bereits in der Crew. Wähle eine andere."})
			_send_lobby()
			changed.emit()
		return
	if not game.started or _loading: return
	match kind:
		"craft":
			if match_paused or args.size()!=2 or not args.get("action") in ["supply","collect"] or not CraftingCatalog.valid_reference(args.get("recipe")): return
			if player_id<1 or player_id>game.players.size() or not is_player_connected(player_id): return
			if is_instance_valid(game.workshop): game.workshop.request(game.players[player_id-1],str(args.action),args.recipe)
		"skill":
			if args.get("player_id",player_id)==player_id and game.players.size()>=player_id:
				game.players[player_id-1].progression.purchase_skill(str(args.get("id","")))
		"upgrade":
			game.upgrades.purchase(str(args.get("id","")))
		"skip_build":
			if player_id==1: game.rounds.begin_warning()
		"restart":
			if player_id==1: restart_match()
		"expedition":
			if args.size()==2 and args.get("action") is String and args.get("data") is Dictionary:
				game.expedition.handle_command(args.action,args.data,player_id)

func pause_match(paused: bool) -> void:
	if not active or not game.started: return
	if is_host:
		# Explicit crew/preparation pause is distinct from automatic transport
		# waiting. Keep it through Ready or expiry of an absent guest.
		_requested_pause = paused
		_set_pause(paused)
		if not _loading: _send({"kind":"pause","paused":match_paused,"generation":_generation},true,-1)
	elif not _loading:
		_send({"kind":"pause","paused":paused,"generation":_generation})

func _set_pause(value: bool) -> void:
	var terminal_phase := ""
	if is_instance_valid(game) and "rounds" in game and is_instance_valid(game.rounds):
		if game.rounds.phase in ["victory", "defeat"]:
			terminal_phase = game.rounds.phase
	var waiting_for_crew: bool=is_host and not _slots.is_empty() and is_instance_valid(game) and game.started and not _all_ready()
	match_paused = value or (is_host and _requested_pause) or waiting_for_crew or not terminal_phase.is_empty()
	if match_paused:
		_input_edges.clear()
		for link: Dictionary in _peers.values(): link._input_edges=[]
	if _loading: return
	get_tree().paused = match_paused
	if not terminal_phase.is_empty():
		game.hud.overlay = "campaign_victory" if terminal_phase=="victory" and game.campaign.active and CampaignCatalog.all_complete(game.campaign.completed) else terminal_phase
	elif game.hud.overlay in ["","pause","network"]:
		game.hud.overlay = "pause" if match_paused else ""

func restart_match() -> bool:
	if not active or not is_host or not is_instance_valid(game) or not game.started or _loading or state!="playing": return false
	if is_instance_valid(game.expedition) and game.expedition.transitioning: return false
	if not _transition_transport_ready(): return false
	_requested_pause = false
	_expedition_payload=game.expedition.restart_payload()
	if not _expedition_payload.is_empty():
		_match_options=_expedition_payload.options.duplicate()
		_match_characters=_expedition_payload.checkpoint.character_ids.duplicate()
	else:
		_match_options=ScenarioCatalog.validate(game.scenario_options)
		_match_characters=_valid_characters(game.selected_characters)
	_match_story=game.story_mode
	_loading=true
	_generation += 1
	_send_start(true)
	_reload_game()
	return true

func expedition_transition(payload: Dictionary) -> bool:
	if not active or not is_host or _loading or state!="playing" or not is_instance_valid(game) or not game.started: return false
	if not preload("res://scripts/expedition_controller.gd").valid_transition(payload) or payload.checkpoint.player_count!=_match_player_count: return false
	# The socket may close before its next poll updates the session flags.
	# Refuse before changing a generation or committing the old world's stock.
	if not _transition_transport_ready(): return false
	_requested_pause = false
	_expedition_payload=payload.duplicate(true)
	_match_options=payload.options.duplicate()
	_match_characters=payload.checkpoint.character_ids.duplicate()
	_generation+=1
	_loading=true
	_load_deadline=_clock+15.0
	_ready_for_snapshots=false
	world=null
	_send_start(true)
	_reload_game.call_deferred()
	return true

func _transition_transport_ready(require_snapshots: bool = true) -> bool:
	if _slots.is_empty(): return true
	for link: Dictionary in _slots.values():
		if not link.connected or not link._authenticated or (require_snapshots and not link._ready_for_snapshots): return false
		if relay_url.is_empty() and (not is_instance_valid(transport) or not transport.can_send_to(int(link.wire))): return false
	return relay_url.is_empty() or (_websocket != null and _websocket.get_ready_state() == WebSocketPeer.STATE_OPEN)

func _reload_game() -> void:
	for link: Dictionary in _peers.values(): link._ready_for_snapshots=false
	_reload_preferences=game.session_preferences()
	_reload_match = true
	world = null
	_loading = true
	# Scene binding starts the next match on a deferred call. Arm its deadline
	# now so a long-running previous match cannot time out in that frame gap.
	_load_deadline = _clock+15.0
	_ready_for_snapshots = false
	var tree := get_tree()
	name = "NetworkSession"
	tree.paused = false
	tree.reload_current_scene()

func _receive_input(message: Dictionary) -> void:
	if not is_instance_valid(game) or game.is_queued_for_deletion() or _loading or not game.started or not message.get("input",null) is Dictionary: return
	if not message.get("generation",null) is int or message.generation != _generation: return
	if not message.get("seq",null) is int: return
	var seq := int(message.get("seq",-1))
	if seq<=_remote_seq: return
	var clean := sanitize_input(message.input)
	if clean.is_empty(): return
	_remote_seq = seq
	_last_input_at = _clock
	_pending_remote = clean
	if match_paused or (clean.pressed.is_empty() and clean.released.is_empty()): return
	if _input_edges.size() >= MAX_PENDING_INPUT_EDGES:
		_reject_guest("Zu viele Netzwerkdaten. Bitte erneut verbinden.")
		return
	# Preserve independently numbered taps received in one poll. Latest held
	# directions/aim still apply immediately; only action edges use this FIFO.
	_input_edges.append({"pressed":clean.pressed,"released":clean.released})

static func sanitize_input(input: Dictionary) -> Dictionary:
	if not input.get("held",null) is Dictionary or not input.get("pressed",null) is Array or not input.get("released",null) is Array: return {}
	if input.held.size()>NetInput.ACTIONS.size() or input.pressed.size()>NetInput.ACTIONS.size() or input.released.size()>NetInput.ACTIONS.size(): return {}
	if input.has("mouse") and not input.mouse is bool: return {}
	var aim = input.get("aim",null)
	if not aim is Array or aim.size()!=2 or not (aim[0] is float or aim[0] is int) or not (aim[1] is float or aim[1] is int): return {}
	if not is_finite(float(aim[0])) or not is_finite(float(aim[1])): return {}
	var result := {"held":{},"pressed":[],"released":[],"aim":[clampf(float(aim[0]),-4096,4096),clampf(float(aim[1]),-4096,8192)],"mouse":true}
	for action: String in NetInput.ACTIONS:
		var value = input.held.get(action,0.0)
		if value is float or value is int:
			if is_finite(float(value)) and float(value)>0: result.held[action] = clampf(float(value),0,1)
		if action in input.pressed: result.pressed.append(action)
		if action in input.released: result.released.append(action)
	return result

func _physics_process(delta: float) -> void:
	if not active or not is_instance_valid(game) or not game.started: return
	if is_host:
		if _peers.is_empty():
			_prepare_remote_frame()
		else:
			for id in _peers.keys():
				_enter_peer(int(id))
				_prepare_remote_frame()
				_leave_peer()
	else:
		var input := NetInput.sample_local(game)
		for action in input.pressed:
			if not action in _local_pressed: _local_pressed.append(action)
		for action in input.released:
			if not action in _local_released: _local_released.append(action)
		_input_clock += delta
		if peer_connected and (not _local_pressed.is_empty() or not _local_released.is_empty() or _input_clock>=(.5 if match_paused else INPUT_INTERVAL)):
			_input_clock = 0
			input.pressed = _local_pressed.duplicate()
			input.released = _local_released.duplicate()
			_input_seq += 1
			# Reliable small input packets preserve single-tick action edges.
			_send({"kind":"input","generation":_generation,"seq":_input_seq,"input":input})
			_local_pressed.clear()
			_local_released.clear()

func _prepare_remote_frame() -> void:
	remote_input = _pending_remote.duplicate(true) if _authenticated and _clock-_last_input_at<0.5 and not match_paused else {}
	if not remote_input.is_empty():
		var edges: Dictionary = _input_edges.pop_front() if not _input_edges.is_empty() else {"pressed":[],"released":[]}
		remote_input.pressed=edges.pressed
		remote_input.released=edges.released
	else:
		_input_edges.clear()
	_pressed.clear()
	_released.clear()

func _flush_room_packets() -> void:
	if not is_instance_valid(game) or game.is_queued_for_deletion() or _deferred_room_packets.is_empty(): return
	var pending: Array[Dictionary]=_deferred_room_packets.duplicate()
	_deferred_room_packets.clear()
	for packet: Dictionary in pending:
		if is_host:
			if not _peers.has(int(packet.peer)): continue
			_enter_peer(int(packet.peer))
		_receive_packet_message(packet.message,int(packet.channel))
		if is_host: _leave_peer()

func _advance_clock() -> void:
	# Godot caps simulation delta after stalls. Transport deadlines and budgets
	# must still measure real elapsed time, independently of gameplay speed.
	var now := Time.get_ticks_usec()
	_clock += float(maxi(0, now - _clock_updated_usec)) / 1000000.0
	_clock_updated_usec = now

func _process(delta: float) -> void:
	_advance_clock()
	_flush_room_packets()
	if _decoder!=null:
		for decoded in _decoder.take(): _receive_packet_message(decoded.message,int(decoded.channel))
	if chat_pending:
		if not active or state=="error": _finish_chat_send(false,"transport")
		elif _clock>float(_chat_waiting.get("deadline",0.0)): _finish_chat_send(false,"timeout")
	if not active or state=="error": return
	_poll_relay()
	if state=="error" or not is_instance_valid(game): return
	_flush_chat_names()
	if _loading and _clock>_load_deadline:
		_fail("Der gemeinsame Spielstart wurde nicht bestätigt. Bitte die Sitzung neu öffnen.")
		return
	if state=="connecting" and _deadline>0 and _clock>_deadline:
		_fail("Keine Antwort. Prüfe den Code und ob Gastgeber, Firewall und Router die Verbindung zulassen.")
		return
	if state=="reconnecting":
		if is_host and relay_url.is_empty():
			_expire_missing_slots()
		elif is_host and _websocket!=null and _websocket.get_ready_state()==WebSocketPeer.STATE_OPEN:
			_expire_missing_slots()
		elif _clock>_reconnect_deadline:
			_fail("Die Verbindung konnte innerhalb von 30 Sekunden nicht wiederhergestellt werden.")
			return
		if _clock>=_retry_at:
			_retry_at=_clock+4.0
			if relay_url.is_empty() and not is_host and not _authenticated:
				_closing=true
				_make_transport()
				_closing=false
				_hello_sent=false
				transport.join(_address,_port)
			elif not relay_url.is_empty() and _websocket==null: _connect_relay("resume")
	_ping_clock+=delta
	var ping_due:=_ping_clock>=1.0
	if ping_due: _ping_clock=0
	if is_host:
		for id in _peers.keys():
			_enter_peer(int(id))
			if not _authenticated and _handshake_deadline>0 and _clock>_handshake_deadline:
				_reject_guest("Der Verbindungsaufbau wurde nicht abgeschlossen.")
			if _authenticated:
				if ping_due:
					_pong_at=_clock
					_send({"kind":"ping","at":_clock},false)
				if _clock-_last_packet_at>(35.0 if _loading else 5.0):
					if is_instance_valid(transport): transport.disconnect_guest(int(id))
					_peer_disconnected_id(int(id),"Zeitüberschreitung.")
			_leave_peer()
		if peer_connected:
			_event_clock+=delta
			if _event_clock>=0.05 and not _events.is_empty() and _all_ready():
				_event_clock=0
				var batch: Array=_events.slice(0,64)
				if _send({"kind":"effects","generation":_generation,"events":batch},true,-1): _events=_events.slice(batch.size())
			if state=="lobby":
				var signature:=JSON.stringify(_lobby_message())
				if signature!=_last_lobby:
					_last_lobby=signature
					_send_lobby()
			elif game.started and world!=null:
				_snapshot_clock+=delta
				if _snapshot_clock>=(.5 if match_paused else SNAPSHOT_INTERVAL):
					_snapshot_clock=0
					_send_snapshot_batch()
	else:
		if peer_connected:
			if _received_seq>0:
				_ack_clock+=delta
				if _ack_clock>=.2:
					_ack_clock=0
					_send({"kind":"snapshot_ack","seq":_received_seq,"generation":_generation},false)
			if ping_due:
				_pong_at=_clock
				_send({"kind":"ping","at":_clock},false)
			if _clock-_last_packet_at>(35.0 if _loading else 5.0): _disconnected("Zeitüberschreitung.")
		if world!=null and game.started and world.has_method("interpolate"): world.interpolate(delta)

func _send_snapshot_batch() -> void:
	var targets: Array=[]
	for id in _peers:
		var link: Dictionary=_peers[id]
		if link._authenticated and link._ready_for_snapshots and int(link._snapshot_seq)-int(link._snapshot_ack)<MAX_PENDING_SNAPSHOTS:
			targets.append(id)
	if targets.is_empty(): return
	_shared_snapshot_sequence+=1
	var message := {"kind":"snapshot","seq":_shared_snapshot_sequence,"generation":_generation,"paused":match_paused,"world":world.capture(),"achievements":_earned_achievement_ids()}
	if is_instance_valid(game.audio.live_music): message.music=game.audio.live_music.get_music_state()
	var encoded := Protocol.encode_trusted(message)
	for id in targets:
		if _send_encoded(encoded,false,int(id)):
			_peers[id]._snapshot_seq=_shared_snapshot_sequence
			sent_snapshots+=1
	_leave_peer()

func _send_snapshot(reliable := false,captured: Dictionary={}) -> void:
	if world==null or not peer_connected: return
	# Limit unacknowledged full states. Slow/lossy peers receive the current
	# world when ready, rather than an ever-growing reliable history.
	if not reliable and _snapshot_seq-_snapshot_ack>=MAX_PENDING_SNAPSHOTS: return
	_shared_snapshot_sequence=maxi(_shared_snapshot_sequence,_snapshot_seq)+1
	var next_sequence:=_shared_snapshot_sequence
	var message := {"kind":"snapshot","seq":next_sequence,"generation":_generation,"paused":match_paused,"world":world.capture() if captured.is_empty() else captured,"achievements":_earned_achievement_ids()}
	if is_instance_valid(game.audio.live_music): message.music=game.audio.live_music.get_music_state()
	if _send(message,reliable):
		_snapshot_seq=next_sequence
		sent_snapshots += 1

func _earned_achievement_ids() -> Array:
	var result: Array = []
	if not is_instance_valid(game) or not is_instance_valid(game.combat_events): return result
	for entry in CombatEvents.ACHIEVEMENTS:
		if game.combat_events.earned_this_shift.has(entry.id): result.append(entry.id)
	return result

func _receive_achievements(ids) -> void:
	if not ids is Array or ids.size()>CombatEvents.ACHIEVEMENTS.size(): return
	for id in ids:
		if id is String: game.combat_events.unlock(id)

func queue_event(category: String,payload: Dictionary) -> void:
	if not active or not is_host or not peer_connected or not is_instance_valid(game) or not game.started: return
	if not Protocol._safe(payload,0): return
	if _events.size()>=128: _events.pop_front()
	_events.append({"category":category,"payload":payload})

func _combat_event(kind: String,payload: Dictionary) -> void:
	var texts: Dictionary={}
	for field in ["title","detail","subtitle"]:
		if payload.get(field) is String: texts[field]=LocaleText.message_payload(payload[field])
	queue_event("combat",{"kind":kind,"data":payload,"texts":texts})

func _receive_events(events: Array) -> void:
	if events.size()>64: return
	for event in events:
		if not event is Dictionary or not event.get("payload",null) is Dictionary: continue
		var payload: Dictionary = event.payload
		match str(event.get("category","")):
			"sound":
				if payload.get("kind",null) is String:
					if payload.get("at") is Vector2 and payload.at.is_finite(): game.sound_at(payload.kind.left(48),payload.at)
					else: game.sound(payload.kind.left(48))
			"dialogue":
				if payload.get("generation")==_generation and payload.get("id") is String and payload.get("speaker") is String and payload.get("player") is int and payload.get("serial") is int and is_instance_valid(game.get("dialogue")):
					game.dialogue.enqueue(payload.id,payload.speaker,payload.player,payload.serial)
			"gore":
				_receive_gore(payload)
			"impact":
				if payload.get("at",null) is Vector2 and payload.get("direction",null) is Vector2 and payload.get("power",null) is float:
					game.impact(payload.at,str(payload.get("material","metal")),payload.direction,clampf(payload.power,0.25,2.0))
			"fx":
				if payload.get("at",null) is Vector2 and payload.get("color",null) is Color and payload.get("count",null) is int:
					game.fx(payload.at,payload.color,clampi(payload.count,0,32))
			"combat":
				var kind := str(payload.get("kind",""))
				if payload.get("data",null) is Dictionary and _valid_combat_event(kind,payload.data):
					var texts=payload.get("texts",{})
					if not texts is Dictionary or texts.size()>3: continue
					var valid:=true
					for field in texts:
						if field not in ["title","detail","subtitle"] or not LocaleText.valid_message_payload(texts[field]): valid=false
					if not valid: continue
					for field in texts: payload.data[field]=LocaleText.message_text(texts[field])
					if kind=="achievement":
						game.combat_events.unlock(str(payload.data.get("id","")))
					else:
						game.combat_events.event.emit(kind,payload.data)

func _receive_gore(payload: Dictionary) -> void:
	if not preload("res://scripts/combat_gore_protocol.gd").valid_event(payload) or not is_instance_valid(game.get("combat_gore")): return
	if _gore_generation!=_generation:
		_gore_generation=_generation
		_gore_highest=0
		_gore_seen.clear()
	var serial: int=payload.serial
	if serial<=_gore_highest-128 or _gore_seen.has(serial): return
	_gore_highest=maxi(_gore_highest,serial)
	_gore_seen[serial]=true
	for old in _gore_seen.keys():
		if old<=_gore_highest-128: _gore_seen.erase(old)
	var actor=world.entities.get(payload.actor) if world!=null else null
	if not is_instance_valid(actor): actor=null
	game.combat_gore.present(payload.data,actor,payload.actor)

static func _valid_combat_event(kind: String,data: Dictionary) -> bool:
	if kind not in ["hit","kill","level_up","armor","craft","deploy","boss","boss_phase","achievement","support"]: return false
	if data.has("final_boss") and not data.final_boss is bool: return false
	for field in ["player_id","enemy_id","level","kills","combo","skill_points","armor_tier","rank"]:
		if data.has(field) and not data[field] is int: return false
	for field in ["amount","damage","earned","xp","current_xp","required"]:
		if data.has(field):
			if not (data[field] is float or data[field] is int): return false
			if not is_finite(float(data[field])): return false
	for field in ["id","title","detail","subtitle","portrait","recipe","kind","skill"]:
		if data.has(field) and (not data[field] is String or data[field].length()>512): return false
	if data.has("player_id") and (data.player_id<1 or data.player_id>4): return false
	if data.has("position") and (not data.position is Vector2 or not data.position.is_finite()): return false
	if kind in ["hit","kill"] and not data.get("position",null) is Vector2: return false
	if kind=="level_up" and not data.get("level",null) is int: return false
	if kind=="achievement" and not data.get("id",null) is String: return false
	if kind=="support" and (data.get("action","") not in ["team","repair","production","supply","aid","drive","craft"] or float(data.get("earned",-1))<0 or float(data.get("earned",100001))>100000): return false
	return true

func _fail(message: String) -> void:
	_cancel_short_resolution()
	short_room_code = ""
	_closing = true
	_close_lan_discovery()
	if is_instance_valid(transport):
		transport.close()
		transport.queue_free()
	transport = null
	if _websocket!=null: WebSocketDrain.retire(_websocket, get_tree())
	_websocket = null
	_closing = false
	error_message = message.left(240)
	state = "error"
	peer_connected = false
	_authenticated = false
	_hello_sent = false
	_loading = false
	remote_input.clear()
	_pending_remote.clear()
	_input_edges.clear()
	if is_instance_valid(game) and game.started:
		get_tree().paused = true
	changed.emit()

func leave(restore_parent: bool = true) -> void:
	if _closing: return
	_advance_clock()
	_cancel_short_resolution()
	short_room_code = ""
	if chat_pending: _finish_chat_send(false,"transport")
	_chat.clear()
	_social.session = self
	_social.clear()
	chat_history.clear()
	chat_names.clear()
	_chat_reject_at.clear()
	_deferred_room_packets.clear()
	_chat_request=0
	chat_error=""
	chat_changed.emit()
	var graceful := active and peer_connected and _send({"kind":"leave"})
	_closing = true
	if _decoder!=null:
		_decoder.stop()
		_decoder=null
	active = false
	_close_lan_discovery()
	if is_instance_valid(transport):
		if graceful: transport.flush_departure()
		transport.close()
		transport.queue_free()
	transport = null
	if _websocket!=null:
		_relay_text({"op":"leave"})
		WebSocketDrain.retire(_websocket, get_tree(), true)
	_websocket = null
	state = "offline"
	room_code = ""
	room_social_service = ""
	lan_code = ""
	direct_code = ""
	internet_code = ""
	advertised_address = ""
	error_message = ""
	connection_hint = ""
	peer_connected = false
	_authenticated = false
	_hello_sent = false
	_handshake_deadline = 0
	_rejecting = false
	_ready_for_snapshots = false
	_loading = false
	_deadline = 0
	_reconnect_deadline = 0
	_relay_resume_token = ""
	_client_token = ""
	_guest_token = ""
	_invite_secret = ""
	_voice_seq=0
	_voice_highest=-1
	_voice_seen.clear()
	_voice_sources.clear()
	_voice_members.clear()
	_voice_member_keys_supported = false
	_packet_budgets.clear()
	_invalid_packets=0
	_generation=0
	_input_seq=0
	_shared_snapshot_sequence=0
	_snapshot_failures=0
	_last_resync_at=-100.0
	_expedition_payload.clear()
	if is_instance_valid(game) and is_instance_valid(game.get("voice")): game.voice.reset()
	remote_input.clear()
	_pending_remote.clear()
	_pressed.clear()
	_released.clear()
	_local_pressed.clear()
	_local_released.clear()
	_input_edges.clear()
	_events.clear()
	world = null
	_peers.clear()
	_slots.clear()
	_context_peer=0
	_connected_slots=[1]
	match_paused = false
	_requested_pause = false
	if restore_parent and is_inside_tree() and is_instance_valid(game) and not game.is_queued_for_deletion() and get_parent()==get_tree().root:
		reparent(game)
	_closing = false
	changed.emit()

func _exit_tree() -> void:
	# Reparenting for a rematch retains the live transport and authentication.
	if not _reload_match and not _closing: leave(false)
