extends Node
## Persistent, service-scoped identities. Social traffic never uses game input
## channels, and opening the game alone never contacts an unconfigured service.
signal changed
signal invite_received(invite: Dictionary)
signal crew_identity_verified(request: String, result: Dictionary)
signal room_resolved(request: String, route: Dictionary)

const L := preload("res://scripts/locale_text.gd")
const JoinCode := preload("res://scripts/network_join_code.gd")
const Protocol := preload("res://scripts/network_protocol.gd")
const ServiceConfig := preload("res://scripts/social_service_config.gd")
const PROFILE_PATH := "user://social_v1.json"
# Eight service identities can each cache 256 legal Unicode contact names.
# Their full JSON exceeds 256 KiB, while this bound still caps profile parsing.
const MAX_PROFILE_BYTES := 524288
const DEFAULT_SERVER := "ws://127.0.0.1:8765/social"
const VERSION := 1
const MAX_FRIENDS := 64
const MAX_REQUESTS := 32
const MAX_INVITES := 16
const MAX_PACKET_BYTES := 49152
const FRIEND_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const ERRORS := {
	"version_mismatch": "Beide Spieler benötigen dieselbe Spielversion.",
	"invalid_request": "Die Freundesanfrage ist ungültig.",
	"invalid_name": "Der Name muss 1 bis 24 sichtbare Zeichen enthalten.",
	"not_found": "Dieser Freundescode ist nicht verfügbar.",
	"friend_limit": "Die Freundesliste ist voll (64 Freunde).",
	"request_limit": "Zu viele offene Freundesanfragen. Bitte zuerst aufräumen.",
	"not_friends": "Einladungen sind nur zwischen bestätigten Freunden möglich.",
	"not_joinable": "Dieser Raum ist nicht mehr verfügbar oder bereits voll.",
	"rate_limited": "Zu viele Anfragen. Bitte kurz warten.",
	"session_replaced": "Dieses Profil ist bereits auf einem anderen Gerät angemeldet.",
	"invite_expired": "Diese Einladung ist abgelaufen.",
	"service_unavailable": "Der Freundesdienst ist vorübergehend nicht verfügbar.",
	"room_unavailable": "Dieser Raumcode ist abgelaufen oder die Runde ist bereits voll.",
}

var connection_state := "offline"
var error_message := ""
var display_name := "Crew"
var friend_code := ""
var server_url := default_server()
var friends: Array[Dictionary] = []
var requests: Array[Dictionary] = []
var outgoing_requests: Array[Dictionary] = []
var _pending_friend_requests: Dictionary = {}
var invitations: Array[Dictionary] = []
var blocked: Array[Dictionary] = []
var settings_path := PROFILE_PATH
var persistence_enabled := true
var connect_on_start := false
var _identities: Dictionary = {}
var _secret := ""
var _peer_key := ""
var _crew_requests: Dictionary = {}
var _room_requests: Dictionary = {}
var room_alias := ""
var observed_address := ""
var _socket: WebSocketPeer
var _wanted := false
var _auth_sent := false
var _presence: Dictionary = {"status":"menu", "environment":"", "joinable":false, "room_code":"", "relay_url":""}
var _clock := 0.0
var _clock_updated_usec := Time.get_ticks_usec()
var _deadline := 0.0
var _heartbeat := 0.0
var _last_response := 0.0
var _retry_at := 0.0
var _retry_delay := 1.0
var _client_tokens := 8.0
var _seen_invites: Dictionary = {}
var _presence_dirty := true
var _desired_name := "Crew"
var _has_saved_profile := false
var _name_dirty := false
var _name_inflight := ""
var _name_retry_at := 0.0
static var _name_filter: RegEx

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_profile()
	_desired_name = display_name
	set_process(true)
	if _profile_allowed() and "--no-profile-save" not in OS.get_cmdline_user_args(): _auto_connect.call_deferred()

func _auto_connect() -> void:
	if connect_on_start or (not _has_saved_profile and not ServiceConfig.DEFAULT_URL.is_empty()): connect_service()

static func default_server() -> String:
	var configured := normalize_url(ServiceConfig.DEFAULT_URL)
	return configured if not configured.is_empty() else DEFAULT_SERVER

static func valid_name(value: String) -> bool:
	if value != value.strip_edges() or value.is_empty() or value.length() > 24 or value.to_utf8_buffer().size() > 96: return false
	if _name_filter == null:
		_name_filter = RegEx.new()
		_name_filter.compile("[\\p{C}\\p{Zl}\\p{Zp}]")
	if _name_filter.search(value) != null: return false
	for index in value.length():
		var point := value.unicode_at(index)
		if point < 32 or point in range(127,160) or point in range(0x200b,0x2010) or point in range(0x2028,0x202f) or point in range(0x2066,0x206a) or point == 0xfeff: return false
	return true

static func compact_code(value: String) -> String:
	return value.strip_edges().to_upper().replace("-", "").replace(" ", "")

static func valid_code(value: String) -> bool:
	var code := compact_code(value)
	if code.length() != 12: return false
	for character in code:
		if character not in FRIEND_ALPHABET: return false
	return true

static func valid_room_alias(value: String) -> bool:
	if value.length() != 6 or value != compact_code(value): return false
	for character in value:
		if character not in FRIEND_ALPHABET: return false
	return true

static func normalize_url(value: String) -> String:
	var url := value.strip_edges()
	if url.length() > 256 or not (url.begins_with("ws://") or url.begins_with("wss://")): return ""
	var encrypted := url.begins_with("wss://")
	var scheme := "wss://" if encrypted else "ws://"
	var rest := url.trim_prefix(scheme)
	var authority := rest.get_slice("/", 0).to_lower()
	var path := rest.substr(authority.length())
	if path not in ["", "/", "/ws", "/social"]: return ""
	var expression := RegEx.new()
	expression.compile("^(localhost|\\[::1\\]|[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?)(?::([0-9]{1,5}))?$")
	var match_value := expression.search(authority)
	if match_value == null: return ""
	var hostname := match_value.get_string(1)
	var port := match_value.get_string(2)
	if not port.is_empty() and (port.to_int() < 1 or port.to_int() > 65535): return ""
	if ".." in hostname or hostname.begins_with(".") or hostname.ends_with("."): return ""
	# Keep the same TLS rule as NetworkSession: plaintext is loopback-only.
	if not encrypted and hostname not in ["localhost", "127.0.0.1", "[::1]"]: return ""
	return scheme + authority + "/social"

func configure_server(url: String) -> bool:
	var normalized := normalize_url(url)
	if normalized.is_empty(): return _reject("Für den Freundesdienst ist eine gültige wss://-Adresse erforderlich; lokal ist ws:// erlaubt.")
	if normalized == server_url: return true
	disconnect_service()
	server_url = normalized
	friend_code = str(_identities.get(server_url, {}).get("code", ""))
	_secret = ""
	friends.clear()
	requests.clear()
	outgoing_requests.clear()
	_pending_friend_requests.clear()
	invitations.clear()
	blocked.clear()
	_restore_contacts()
	_seen_invites.clear()
	if not _save_profile(): return false
	changed.emit()
	return true

func connect_for_room(url: String) -> bool:
	var normalized := normalize_url(url)
	if normalized.is_empty(): return false
	# Never move an established profile to another service on a peer's claim.
	if normalized != server_url and (server_url != default_server() or _identities.has(server_url) or _wanted or connect_on_start): return false
	if normalized != server_url and not configure_server(normalized): return false
	return connect_service()

func connect_service() -> bool:
	if normalize_url(server_url).is_empty(): return _reject("Bitte zuerst einen gültigen Freundeserver einstellen.")
	if connection_state in ["connecting", "online"]: return true
	if not _ensure_identity(): return _reject("Das lokale Freundeprofil konnte nicht erstellt werden.")
	_wanted = true
	connect_on_start = true
	_save_profile()
	_retry_delay = 1.0
	_retry_at = 0.0
	return _open_socket()

func disconnect_service() -> void:
	_wanted = false
	connect_on_start = false
	_save_profile()
	_retry_at = 0.0
	if _socket != null: _socket.close(1000, "Offline")
	_socket = null
	_cancel_room_requests()
	room_alias = ""
	observed_address = ""
	_peer_key = ""
	_crew_requests.clear()
	_pending_friend_requests.clear()
	_auth_sent = false
	connection_state = "offline"
	error_message = ""
	invitations.clear()
	for entry in friends:
		entry.status = "offline"
		entry.joinable = false
		entry.environment = ""
	changed.emit()

func set_display_name(value: String) -> bool:
	var name_value := value.strip_edges()
	if not valid_name(name_value): return _reject(ERRORS.invalid_name)
	if name_value == display_name: return true
	display_name = name_value
	_desired_name = name_value
	_name_dirty = true
	if not _save_profile(): return false
	changed.emit()
	return true

func add_friend(code: String) -> bool:
	return _friend_command("add_friend", code)

func accept_friend(code: String) -> bool:
	return _friend_command("accept_friend", code)

func decline_friend(code: String) -> bool:
	return _friend_command("decline_friend", code)

func remove_friend(code: String) -> bool:
	return _friend_command("remove_friend", code)

func block_friend(code: String) -> bool:
	return _friend_command("block_friend", code)

func unblock_friend(code: String) -> bool:
	return _friend_command("unblock_friend", code)

func _friend_command(operation: String, value: String) -> bool:
	var code := compact_code(value)
	if not valid_code(code) or code == friend_code: return _reject("Bitte den vollständigen Freundescode einer anderen Person eingeben.")
	if not _send({"op":operation, "code":code}): return false
	if operation == "add_friend": _pending_friend_requests[code] = _clock + 8.0
	changed.emit()
	return true

func is_friend_request_pending(code: String) -> bool:
	return _pending_friend_requests.has(compact_code(code))

func crew_identity(context: String) -> Dictionary:
	if connection_state != "online" or not _valid_secret(_peer_key) or context.length() != 48 or not context.is_valid_hex_number(false): return {}
	var signer := HMACContext.new()
	if signer.start(HashingContext.HASH_SHA256, _peer_key.hex_decode()) != OK: return {}
	signer.update(("bunkercrew-crew1:" + Protocol.BUILD + ":" + context + ":" + friend_code).to_utf8_buffer())
	return {"code":friend_code, "service":server_url, "context":context, "proof":signer.finish().hex_encode()}

func verify_crew_identity(identity: Dictionary, request: String) -> bool:
	if connection_state != "online" or identity.get("service") != server_url or _crew_requests.size() >= 16: return false
	if not valid_code(str(identity.get("code", ""))) or str(identity.get("context", "")).length() != 48 or not _valid_secret(str(identity.get("proof", ""))): return false
	if not _send({"op":"verify_crew", "request":request, "code":identity.code, "context":identity.context, "proof":identity.proof}): return false
	_crew_requests[request] = {"code":identity.code, "deadline":_clock + 8.0}
	return true

func resolve_short_code(value: String) -> String:
	_advance_clock()
	var code := compact_code(value)
	if not valid_room_alias(code) or _room_requests.size() >= 4: return ""
	if connection_state not in ["connecting", "online"] and not connect_service(): return ""
	var request := Crypto.new().generate_random_bytes(16).hex_encode()
	_room_requests[request] = {"code":code, "deadline":_clock + 15.0, "sent":false}
	return request

func cancel_room_resolution(request: String) -> void:
	_room_requests.erase(request)

func _cancel_room_requests() -> void:
	var requests_copy := _room_requests.keys()
	_room_requests.clear()
	for request in requests_copy: room_resolved.emit(request, {"ok":false, "error_code":"service_unavailable"})

func set_presence(data: Dictionary) -> void:
	var next: Dictionary = {"status":str(data.get("status","menu")), "environment":str(data.get("environment","")), "joinable":bool(data.get("joinable",false)), "room_code":str(data.get("room_code","")), "relay_url":str(data.get("relay_url","")), "room_token":str(data.get("room_token",""))}
	if next.status not in ["menu", "lobby", "playing"]: next.status = "menu"
	if next.environment.length() > 48: next.environment = ""
	if next.room_code.length() > 64 or next.relay_url.length() > 256 or next.room_token.length() > 128: next.joinable = false
	if next.status != "lobby": next.joinable = false
	if not next.joinable:
		next.room_code = ""
		next.relay_url = ""
		next.room_token = ""
	if next == _presence: return
	if next.room_code != _presence.get("room_code", "") or next.relay_url != _presence.get("relay_url", "") or not next.joinable:
		room_alias = ""
	_presence = next
	_presence_dirty = true

func invite_friend(code: String) -> bool:
	var public_code := compact_code(code)
	if not bool(_presence.get("joinable", false)) or _presence.status != "lobby": return _reject(ERRORS.not_joinable)
	if not friends.any(func(entry): return entry.code == public_code and entry.status != "offline"): return _reject(ERRORS.not_friends)
	return _friend_command("invite", public_code)

func decline_invite(id: String) -> bool:
	if not _valid_invite_id(id): return false
	if not _send({"op":"decline_invite", "id":id}): return false
	invitations = invitations.filter(func(entry): return entry.id != id)
	changed.emit()
	return true

func take_invite(id: String) -> Dictionary:
	if connection_state != "online" or not _valid_invite_id(id): return {}
	for entry in invitations:
		if entry.id != id: continue
		if float(entry.expires) <= Time.get_unix_time_from_system(): return {}
		if not _send({"op":"take_invite", "id":id}): return {}
		var result := entry.duplicate(true)
		invitations = invitations.filter(func(item): return item.id != id)
		changed.emit()
		return result
	return {}

func _advance_clock() -> void:
	# Service timeouts and throttles must include stalls and stay independent
	# of the game's time scale, just like the room transport's deadlines.
	var now := Time.get_ticks_usec()
	var elapsed := float(maxi(0,now - _clock_updated_usec)) / 1000000.0
	_clock_updated_usec = now
	_clock += elapsed
	_client_tokens = minf(8.0,_client_tokens + elapsed * 2.0)

func _process(_delta: float) -> void:
	_advance_clock()
	for request in _room_requests.keys():
		var item: Dictionary = _room_requests[request]
		if _clock >= float(item.deadline):
			_room_requests.erase(request)
			room_resolved.emit(request, {"ok":false, "error_code":"service_unavailable"})
		elif connection_state == "online" and not item.sent and _client_tokens >= 1.0:
			if _send({"op":"resolve_room", "request":request, "code":item.code}): item.sent = true
	for code in _pending_friend_requests.keys():
		if _clock >= float(_pending_friend_requests[code]):
			_pending_friend_requests.erase(code)
			error_message = ERRORS.service_unavailable
			changed.emit()
	for request in _crew_requests.keys():
		if _clock >= float(_crew_requests[request].deadline):
			_crew_requests.erase(request)
			crew_identity_verified.emit(request, {"valid":false})
	if _socket == null:
		if _wanted and _retry_at > 0.0 and _clock >= _retry_at: _open_socket()
		return
	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _auth_sent:
			_auth_sent = true
			_last_response = _clock
			_send({"op":"auth", "version":VERSION, "build":Protocol.BUILD, "secret":_secret, "name":display_name}, false)
		var packets := 0
		var started := Time.get_ticks_usec()
		while _socket != null and _socket.get_available_packet_count() > 0 and packets < 8 and Time.get_ticks_usec()-started < 1500:
			packets += 1
			var packet := _socket.get_packet()
			if not _socket.was_string_packet() or packet.size() > MAX_PACKET_BYTES:
				_connection_failed("Der Freundeserver hat eine ungültige Antwort gesendet.", true)
				return
			var decoder := JSON.new()
			var decoded := decoder.parse(packet.get_string_from_utf8()) == OK
			var raw: Variant = decoder.data
			if not decoded or not raw is Dictionary or not _receive(raw):
				_connection_failed("Der Freundeserver hat eine ungültige Antwort gesendet.", true)
				return
			_last_response = _clock
		if _clock - _last_response > 30.0 or (connection_state == "connecting" and _clock > _deadline):
			_connection_failed("Der Freundeserver antwortet nicht.")
			return
		if connection_state == "online" and _clock >= _heartbeat:
			_send({"op":"ping"}, false)
			_heartbeat = _clock + 10.0
		if connection_state == "online" and _presence_dirty:
			_presence_dirty = not _send({"op":"presence", "data":_presence}, false)
		if connection_state == "online" and _name_dirty and _name_inflight.is_empty() and _clock >= _name_retry_at and _client_tokens >= 1.0:
			if _send({"op":"name", "name":_desired_name}):
				_name_inflight = _desired_name
				_name_dirty = false
	elif state == WebSocketPeer.STATE_CLOSED:
		_connection_failed("Verbindung zum Freundeserver unterbrochen.")
	elif _clock > _deadline:
		_connection_failed("Der Freundeserver ist nicht erreichbar.")
	_expire_invites()

func _open_socket() -> bool:
	_advance_clock()
	_socket = WebSocketPeer.new()
	_socket.inbound_buffer_size = MAX_PACKET_BYTES * 2
	_socket.outbound_buffer_size = 16384
	_socket.max_queued_packets = 32
	_socket.heartbeat_interval = 10.0
	_auth_sent = false
	_presence_dirty = true
	_name_inflight = ""
	_deadline = _clock + 12.0
	_retry_at = 0.0
	connection_state = "connecting"
	error_message = ""
	if _socket.connect_to_url(server_url) != OK:
		_connection_failed("Der Freundeserver konnte nicht kontaktiert werden.")
		return false
	changed.emit()
	return true

func _connection_failed(message: String, terminal: bool = false) -> void:
	_advance_clock()
	if _socket != null: _socket.close()
	_socket = null
	_cancel_room_requests()
	room_alias = ""
	observed_address = ""
	_peer_key = ""
	_crew_requests.clear()
	_pending_friend_requests.clear()
	_auth_sent = false
	connection_state = "error" if _wanted else "offline"
	error_message = message
	invitations.clear()
	for entry in friends:
		entry.status = "offline"
		entry.joinable = false
		entry.environment = ""
	if terminal: _wanted = false
	if _wanted:
		_retry_at = _clock + _retry_delay
		_retry_delay = minf(30.0, _retry_delay * 2.0)
	changed.emit()

func _send(payload: Dictionary, limited: bool = true) -> bool:
	_advance_clock()
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN or (limited and connection_state != "online"):
		return _reject("Bitte zuerst mit dem Freundeserver verbinden.") if limited else false
	if limited and _client_tokens < 1.0: return _reject(ERRORS.rate_limited)
	var result := _socket.send_text(JSON.stringify(payload))
	if result != OK: return _reject("Die Freundesanfrage konnte nicht gesendet werden.")
	if limited: _client_tokens -= 1.0
	error_message = ""
	return true

func _receive(payload: Dictionary) -> bool:
	var operation := str(payload.get("op", ""))
	if operation == "room_resolved":
		if payload.size() != 7 or not payload.get("request") is String or not _valid_invite_id(payload.request) or not payload.get("code") is String or not valid_room_alias(payload.code) or not payload.get("room_code") is String or not payload.get("relay_url") is String or not payload.get("error_code") is String: return false
		var expires: Variant = payload.get("expires")
		if not (expires is int or expires is float) or not is_finite(float(expires)) or float(expires) < 0.0: return false
		if payload.error_code.is_empty():
			if float(expires) <= Time.get_unix_time_from_system() or float(expires) > Time.get_unix_time_from_system() + 60.0: return false
			if payload.relay_url.is_empty():
				var decoded: Dictionary = JoinCode.decode(payload.room_code)
				if not decoded.get("ok", false) or not decoded.has("invite"): return false
			elif normalize_url(payload.relay_url).is_empty() or not valid_room_alias(payload.room_code): return false
		elif payload.error_code not in ["room_unavailable", "rate_limited", "service_unavailable"] or not payload.room_code.is_empty() or not payload.relay_url.is_empty() or float(expires) != 0.0: return false
		var pending: Dictionary = _room_requests.get(payload.request, {})
		if pending.is_empty(): return true
		if pending.code != payload.code: return false
		_room_requests.erase(payload.request)
		room_resolved.emit(payload.request, {"ok":payload.error_code.is_empty(), "room_code":payload.room_code, "relay_url":payload.relay_url, "error_code":payload.error_code})
		return true
	if operation == "crew_verified":
		if payload.size() != 5 or not payload.get("request") is String or not payload.get("code") is String or not valid_code(payload.code) or not payload.get("valid") is bool or not payload.get("name") is String: return false
		if payload.valid and not valid_name(payload.name): return false
		var pending: Dictionary = _crew_requests.get(payload.request, {})
		if pending.is_empty(): return true
		if pending.code != payload.code: return false
		_crew_requests.erase(payload.request)
		crew_identity_verified.emit(payload.request, {"valid":payload.valid, "code":payload.code, "name":payload.name})
		return true
	if operation == "pong": return payload.size() == 1
	if operation == "name_saved":
		if payload.size() != 2 or not payload.get("name") is String or not valid_name(payload.name) or _name_inflight.is_empty(): return false
		if _desired_name == _name_inflight:
			display_name = payload.name
			_desired_name = payload.name
			_save_profile()
		_name_inflight = ""
		changed.emit()
		return true
	if operation == "error":
		_pending_friend_requests.clear()
		var code := str(payload.get("code", "invalid_request"))
		error_message = str(ERRORS.get(code, ERRORS.invalid_request))
		if not _name_inflight.is_empty():
			_name_inflight = ""
			_name_dirty = true
			_name_retry_at = _clock + 4.0
		if code in ["session_replaced", "version_mismatch"]:
			_connection_failed(error_message, true)
		else: changed.emit()
		return true
	if operation not in ["ready", "state"]: return false
	if operation == "ready":
		if connection_state != "connecting" or not payload.get("code") is String or not valid_code(payload.code) or not payload.get("name") is String or not valid_name(payload.name): return false
		if payload.has("peer_key") and (not payload.peer_key is String or not _valid_secret(payload.peer_key)): return false
		if not payload.get("observed_address", "") is String or (not str(payload.get("observed_address", "")).is_empty() and not JoinCode.is_public_address(payload.observed_address)): return false
	elif connection_state != "online": return false
	if not payload.get("room_alias", "") is String or (not str(payload.get("room_alias", "")).is_empty() and not valid_room_alias(payload.room_alias)): return false
	var next_friends := _read_rows(payload.get("friends"), MAX_FRIENDS, true)
	var next_requests := _read_rows(payload.get("requests"), MAX_REQUESTS, false)
	var next_outgoing := _read_rows(payload.get("outgoing_requests", []), MAX_REQUESTS, false)
	var next_blocked := _read_rows(payload.get("blocked"), 128, false)
	var next_invites: Array[Dictionary] = []
	if next_friends.size() == 1 and next_friends[0].has("invalid") or next_requests.size() == 1 and next_requests[0].has("invalid") or next_blocked.size() == 1 and next_blocked[0].has("invalid"): return false
	if next_outgoing.size() == 1 and next_outgoing[0].has("invalid"): return false
	var raw_invites: Variant = payload.get("invitations")
	if not raw_invites is Array or raw_invites.size() > MAX_INVITES: return false
	for raw in raw_invites:
		if not _valid_invite(raw): return false
		if not next_friends.any(func(entry): return entry.code == raw.from_code): return false
		next_invites.append(raw.duplicate(true))
	if operation == "ready":
		friend_code = payload.code
		_peer_key = str(payload.get("peer_key", ""))
		observed_address = str(payload.get("observed_address", ""))
		_name_dirty = _desired_name != payload.name
		display_name = _desired_name if _name_dirty else payload.name
		var identity: Dictionary = _identities.get(server_url, {})
		identity.code = friend_code
		_identities[server_url] = identity
		connection_state = "online"
		_retry_delay = 1.0
		_heartbeat = _clock + 10.0
		_save_profile()
	friends = next_friends
	room_alias = str(payload.get("room_alias", ""))
	requests = next_requests
	outgoing_requests = next_outgoing
	for code in _pending_friend_requests.keys():
		if outgoing_requests.any(func(entry): return entry.code == code) or friends.any(func(entry): return entry.code == code): _pending_friend_requests.erase(code)
	blocked = next_blocked
	var identity_cache: Dictionary = _identities.get(server_url, {})
	var contacts := {"friends":_contact_names(friends), "requests":_contact_names(requests), "outgoing_requests":_contact_names(outgoing_requests), "blocked":_contact_names(blocked)}
	if identity_cache.get("contacts", {}) != contacts:
		identity_cache.contacts = contacts
		_identities[server_url] = identity_cache
		_save_profile()
	invitations = next_invites
	if operation == "ready": _presence_dirty = true
	for entry in invitations:
		if not _seen_invites.has(entry.id):
			_seen_invites[entry.id] = true
			invite_received.emit(entry.duplicate(true))
	if _seen_invites.size() > 64:
		_seen_invites.clear()
		for entry in invitations: _seen_invites[entry.id] = true
	changed.emit()
	return true

func _contact_names(rows: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in rows: result.append({"code":entry.code, "name":entry.name})
	return result

func _restore_contacts() -> void:
	var cache: Dictionary = _identities.get(server_url, {}).get("contacts", {})
	friends.clear()
	for entry in cache.get("friends", []):
		friends.append({"code":entry.code, "name":entry.name, "status":"offline", "environment":"", "joinable":false})
	requests.assign(cache.get("requests", []))
	outgoing_requests.assign(cache.get("outgoing_requests", []))
	blocked.assign(cache.get("blocked", []))

func _read_rows(raw: Variant, limit: int, with_presence: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw is Array or raw.size() > limit: return [{"invalid":true}]
	var seen: Dictionary = {}
	for entry in raw:
		if not entry is Dictionary or not entry.get("code") is String or not valid_code(entry.code) or not entry.get("name") is String or not valid_name(entry.name) or seen.has(entry.code): return [{"invalid":true}]
		if entry.size() != (5 if with_presence else 2): return [{"invalid":true}]
		seen[entry.code] = true
		if with_presence:
			if entry.get("status") not in ["offline", "menu", "lobby", "playing"] or not entry.get("joinable") is bool or not entry.get("environment") is String or entry.environment.length() > 48: return [{"invalid":true}]
		result.append(entry.duplicate(true))
	return result

static func _valid_invite_id(value: String) -> bool:
	return value.length() == 32 and value.is_valid_hex_number(false)

static func _valid_invite(raw: Variant) -> bool:
	if not raw is Dictionary: return false
	if raw.size() != 6: return false
	for key in ["id", "from_code", "name", "room_code", "relay_url"]:
		if not raw.get(key) is String: return false
	if not _valid_invite_id(raw.id) or not valid_code(raw.from_code) or not valid_name(raw.name) or raw.room_code.length() > 64: return false
	var expires: Variant = raw.get("expires")
	if not (expires is int or expires is float) or not is_finite(float(expires)) or float(expires) > Time.get_unix_time_from_system() + 180.0: return false
	if raw.relay_url.is_empty():
		var direct: Dictionary = JoinCode.decode(raw.room_code)
		if not bool(direct.get("ok", false)) or not direct.has("invite"): return false
	else:
		if normalize_url(raw.relay_url).is_empty() or not (raw.relay_url.ends_with("/ws") or raw.relay_url.trim_prefix("ws://").trim_prefix("wss://").find("/") == -1): return false
		if raw.room_code.length() != 6: return false
		for character in raw.room_code:
			if character not in FRIEND_ALPHABET: return false
	return true

func _expire_invites() -> void:
	var before := invitations.size()
	invitations = invitations.filter(func(entry): return float(entry.expires) > Time.get_unix_time_from_system())
	if invitations.size() != before: changed.emit()

func _reject(message: String) -> bool:
	error_message = message
	changed.emit()
	return false

func _profile_allowed() -> bool:
	return persistence_enabled and (settings_path != PROFILE_PATH or "--no-profile-save" not in OS.get_cmdline_user_args())

func _ensure_identity() -> bool:
	var identity: Dictionary = _identities.get(server_url, {})
	if not _valid_secret(str(identity.get("secret", ""))):
		if _identities.size() >= 8: return false
		identity = {"secret":Crypto.new().generate_random_bytes(32).hex_encode(), "code":""}
		_identities[server_url] = identity
	_secret = str(identity.secret)
	friend_code = str(identity.get("code", ""))
	return _save_profile()

static func _valid_secret(value: String) -> bool:
	return value.length() == 64 and value.is_valid_hex_number(false)

func _load_profile() -> void:
	if not _profile_allowed(): return
	var profile := _read_profile(settings_path)
	if profile.is_empty(): profile = _read_profile(settings_path + ".bak")
	if profile.is_empty(): return
	_has_saved_profile = true
	display_name = profile.name
	server_url = profile.server
	connect_on_start = profile.connect_on_start
	_identities = profile.identities.duplicate(true)
	friend_code = str(_identities.get(server_url, {}).get("code", ""))
	_restore_contacts()

func _read_profile(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_PROFILE_BYTES: return {}
	var decoder := JSON.new()
	if decoder.parse(file.get_as_text()) != OK: return {}
	var profile: Variant = decoder.data
	if not profile is Dictionary or profile.get("version") != 1 or not profile.get("name") is String or not valid_name(profile.name): return {}
	if not profile.get("server") is String or normalize_url(profile.server) != profile.server or not profile.get("connect_on_start") is bool: return {}
	if not profile.get("identities") is Dictionary or profile.identities.size() > 8: return {}
	for url in profile.identities:
		var identity: Variant = profile.identities[url]
		if not url is String or normalize_url(url) != url or not identity is Dictionary: return {}
		if not identity.get("secret") is String or not _valid_secret(identity.secret) or not identity.get("code") is String: return {}
		if not identity.code.is_empty() and not valid_code(identity.code): return {}
		if identity.has("contacts"):
			if not identity.contacts is Dictionary or identity.contacts.size() not in [3, 4]: return {}
			for key in ["friends", "requests", "outgoing_requests", "blocked"]:
				var rows := _read_rows(identity.contacts.get(key, []), MAX_FRIENDS if key == "friends" else (128 if key == "blocked" else MAX_REQUESTS), false)
				if rows.size() == 1 and rows[0].has("invalid"): return {}
	return profile

func _write_private(path: String, content: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	if OS.get_name() in ["Linux", "macOS", "FreeBSD", "OpenBSD", "NetBSD", "Android", "iOS"]:
		if FileAccess.set_unix_permissions(path, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER) != OK:
			file.close()
			return false
	file.store_string(content)
	file.flush()
	var result := file.get_error()
	file.close()
	return result == OK

func _save_profile() -> bool:
	if not _profile_allowed(): return true
	var content := JSON.stringify({"version":1, "name":display_name, "server":server_url, "identities":_identities, "connect_on_start":connect_on_start})
	var temporary := settings_path + ".tmp"
	var saved := _write_private(temporary, content)
	if saved and not _read_profile(settings_path).is_empty():
		var backup_temp := settings_path + ".bak.tmp"
		saved = _write_private(backup_temp, FileAccess.get_file_as_string(settings_path))
		if saved: saved = DirAccess.rename_absolute(backup_temp, settings_path + ".bak") == OK
	if saved: saved = DirAccess.rename_absolute(temporary, settings_path) == OK
	if not saved:
		error_message = "Das Freundeprofil konnte nicht gespeichert werden."
		changed.emit()
		return false
	_has_saved_profile = true
	return true

func _exit_tree() -> void:
	_wanted = false
	if _socket != null: _socket.close(1000, "Shutdown")
	_socket = null
