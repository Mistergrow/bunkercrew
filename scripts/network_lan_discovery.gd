extends Node
## A short invitation resolves only on the local network. ENet still authenticates
## the invitation after discovery; this socket never carries game state.

signal found(address: String, port: int)
signal failed(reason: String)

const Transport := preload("res://scripts/network_transport.gd")
const JoinCode := preload("res://scripts/network_join_code.gd")
const DEFAULT_PORT := 24778
const VERSION := 2
const DOMAIN := "bunkercrew-lan-2"
const MAX_PACKET_BYTES := 256
const MAX_PACKETS_PER_FRAME := 16
const MAX_INTERFACES := 8
const MAX_RETRIES := 3
const RECEIVE_BUFFER_BYTES := 65536
const PACKET_BURST := 16.0
const PACKET_RATE := 8.0
const RESPONSE_BURST := 4.0
const RESPONSE_RATE := 2.0
const INVALID_CODE := "Bitte einen gültigen LAN-Code eingeben."
const OPEN_FAILED := "Die LAN-Suche konnte nicht geöffnet werden. Netzwerk und Firewall prüfen."
const HOST_FAILED := "Der Port für die LAN-Suche ist nicht verfügbar. Verwende den vollständigen Verbindungscode."
const TIMED_OUT := "Kein Gastgeber im LAN gefunden. Code, gemeinsames Netzwerk und Firewall prüfen oder den vollständigen Verbindungscode verwenden."

# Tests can choose isolated ports and explicit loopback targets. Normal callers
# leave targets empty: each selected adapter gets its own bound broadcast socket.
var discovery_port := DEFAULT_PORT
var timeout_seconds := 6.0
var bind_address := "0.0.0.0"
var discovery_targets: Array[String] = []
var last_poll_packets := 0
var sent_responses := 0
var sent_requests := 0
var rejected_packets := 0

var _sockets: Array[PacketPeerUDP] = []
var _targets: Array[String] = []
var _mode := ""
var _secret := ""
var _nonce := ""
var _game_port := 0
var _deadline_usec := 0
var _next_retry_usec := 0
var _retry_interval_usec := 0
var _retries := 0
var _next_socket := 0
var _packet_tokens := PACKET_BURST
var _response_tokens := RESPONSE_BURST
var _budget_updated_usec := 0

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func host(secret: String, game_port: int) -> Error:
	close()
	if not _valid_secret(secret) or game_port < 1 or game_port > 65535 or not _valid_port():
		failed.emit(INVALID_CODE)
		return ERR_INVALID_PARAMETER
	var socket := PacketPeerUDP.new()
	var result := socket.bind(discovery_port, bind_address, RECEIVE_BUFFER_BYTES)
	if result != OK:
		socket.close()
		failed.emit(HOST_FAILED)
		return result
	_sockets.append(socket)
	_secret = secret
	_game_port = game_port
	_mode = "host"
	_reset_counters()
	return OK

func discover(secret: String) -> Error:
	close()
	if not _valid_secret(secret) or not _valid_port() or not is_finite(timeout_seconds) or timeout_seconds <= 0.0:
		failed.emit(INVALID_CODE)
		return ERR_INVALID_PARAMETER
	if discovery_targets.is_empty():
		var count := 0
		for address in Transport.lan_addresses():
			if address.begins_with("127."): continue
			if count >= MAX_INTERFACES: break
			if _open_query_socket(address, "255.255.255.255") == OK: count += 1
		_open_query_socket("127.0.0.1", "127.0.0.1")
	else:
		for target in discovery_targets.slice(0, MAX_INTERFACES):
			if not _valid_source(target): continue
			_open_query_socket("127.0.0.1" if target.begins_with("127.") else "0.0.0.0", target)
	if _sockets.is_empty():
		failed.emit(OPEN_FAILED)
		return ERR_CANT_OPEN
	_secret = secret
	_nonce = Crypto.new().generate_random_bytes(16).hex_encode()
	_mode = "discover"
	_reset_counters()
	var duration_usec := maxi(1, roundi(minf(timeout_seconds, 60.0) * 1000000.0))
	_deadline_usec = Time.get_ticks_usec() + duration_usec
	_retry_interval_usec = maxi(1, roundi(float(duration_usec) / (MAX_RETRIES + 1)))
	_next_retry_usec = Time.get_ticks_usec() + _retry_interval_usec
	_send_queries()
	return OK

func close() -> void:
	for socket in _sockets: socket.close()
	_sockets.clear()
	_targets.clear()
	_mode = ""
	_secret = ""
	_nonce = ""
	_game_port = 0
	_deadline_usec = 0
	_next_retry_usec = 0
	_next_socket = 0
	_retries = 0

func _open_query_socket(address: String, target: String) -> Error:
	var socket := PacketPeerUDP.new()
	var result := socket.bind(0, address, RECEIVE_BUFFER_BYTES)
	if result == OK:
		socket.set_broadcast_enabled(true)
		result = socket.set_dest_address(target, discovery_port)
	if result != OK:
		socket.close()
		return result
	_sockets.append(socket)
	_targets.append(target)
	return OK

func _send_queries() -> void:
	var packet := _encode("find", _nonce)
	for index in _sockets.size():
		var socket := _sockets[index]
		if socket.set_dest_address(_targets[index], discovery_port) == OK and socket.put_packet(packet) == OK:
			sent_requests += 1

func _process(_delta: float) -> void:
	last_poll_packets = 0
	if _mode.is_empty(): return
	var now := Time.get_ticks_usec()
	_refill_budgets(now)
	if _mode == "discover":
		if now >= _deadline_usec:
			close()
			failed.emit(TIMED_OUT)
			return
		if _retries < MAX_RETRIES and now >= _next_retry_usec:
			_retries += 1
			_next_retry_usec = now + _retry_interval_usec
			_send_queries()
	# Round-robin across adapters: a busy adapter cannot starve the others.
	var empty_visits := 0
	while last_poll_packets < MAX_PACKETS_PER_FRAME and empty_visits < _sockets.size():
		var socket := _sockets[_next_socket]
		_next_socket = (_next_socket + 1) % _sockets.size()
		if socket.get_available_packet_count() == 0:
			empty_visits += 1
			continue
		empty_visits = 0
		var packet := socket.get_packet()
		var address := socket.get_packet_ip()
		var port := socket.get_packet_port()
		last_poll_packets += 1
		if _packet_tokens < 1.0:
			rejected_packets += 1
			continue
		_packet_tokens -= 1.0
		if not _valid_source(address):
			rejected_packets += 1
			continue
		var message := _decode(packet)
		if message.is_empty():
			rejected_packets += 1
			continue
		if _mode == "host":
			_respond(socket, address, port, message)
		elif _accept_reply(address, port, message):
			return # found listeners may free or reuse this node.

func _respond(socket: PacketPeerUDP, address: String, port: int, message: Dictionary) -> void:
	if message.op != "find" or not _matches(message):
		rejected_packets += 1
		return
	if _response_tokens < 1.0: return
	_response_tokens -= 1.0
	if socket.set_dest_address(address, port) == OK and socket.put_packet(_encode("found", message.nonce, _game_port)) == OK:
		sent_responses += 1

func _accept_reply(address: String, source_port: int, message: Dictionary) -> bool:
	if source_port != discovery_port or message.op != "found" or message.nonce != _nonce or not _matches(message):
		rejected_packets += 1
		return false
	var game_port: int = message.port
	close()
	found.emit(address, game_port) # Use the UDP sender, never a claimed JSON address.
	return true

func _encode(operation: String, nonce: String, game_port: int = 0) -> PackedByteArray:
	var message := {"v": VERSION, "op": operation, "nonce": nonce, "proof": _proof(_secret, operation, nonce, game_port)}
	if operation == "found": message.port = game_port
	return JSON.stringify(message).to_utf8_buffer()

static func _proof(secret: String, operation: String, nonce: String, game_port: int = 0) -> String:
	var payload := DOMAIN + "\n" + operation + "\n" + nonce
	if operation == "found": payload += "\n" + str(game_port)
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, secret.to_ascii_buffer(), payload.to_ascii_buffer()).hex_encode()

func _matches(message: Dictionary) -> bool:
	var expected := _proof(_secret, message.op, message.nonce, int(message.get("port", 0)))
	return Crypto.new().constant_time_compare(expected.to_ascii_buffer(), str(message.proof).to_ascii_buffer())

static func _decode(packet: PackedByteArray) -> Dictionary:
	if packet.is_empty() or packet.size() > MAX_PACKET_BYTES: return {}
	# Only the small ASCII protocol is accepted; no Variant/object decoding.
	for value in packet:
		if value < 32 or value > 126: return {}
	var raw := packet.get_string_from_ascii()
	var parser := JSON.new()
	if parser.parse(raw) != OK or not parser.data is Dictionary: return {}
	var message: Dictionary = parser.data
	if message.get("v") != VERSION or message.get("op") not in ["find", "found"]: return {}
	var reply: bool = message.op == "found"
	if message.size() != (5 if reply else 4): return {}
	if not _hex_string(message.get("nonce"), 32) or not _hex_string(message.get("proof"), 64): return {}
	if reply:
		var port = message.get("port")
		if not (port is float or port is int) or not is_finite(float(port)) or port < 1 or port > 65535 or port != int(port): return {}
		message.port = int(port)
	message.v = VERSION
	# Canonical JSON also rejects duplicate keys, extra keys and alternate numeric
	# spellings that the generic JSON parser would otherwise silently normalize.
	if JSON.stringify(message) != raw: return {}
	return message

static func _hex_string(value, length: int) -> bool:
	if not value is String or value.length() != length: return false
	for character in value:
		if character not in "0123456789abcdef": return false
	return true

static func _valid_secret(secret: String) -> bool:
	if secret.length() != NetworkJoinCode.SECRET_SYMBOLS: return false
	for character in secret:
		if character not in JoinCode.ALPHABET: return false
	return true

static func _valid_source(address: String) -> bool:
	if not address.is_valid_ip_address() or ":" in address: return false
	var first := address.get_slice(".", 0).to_int()
	return first > 0 and first < 224 and address != "255.255.255.255"

func _valid_port() -> bool:
	return discovery_port >= 1 and discovery_port <= 65535

func _reset_counters() -> void:
	last_poll_packets = 0
	sent_responses = 0
	sent_requests = 0
	rejected_packets = 0
	_packet_tokens = PACKET_BURST
	_response_tokens = RESPONSE_BURST
	_budget_updated_usec = Time.get_ticks_usec()

func _refill_budgets(now_usec: int) -> void:
	var elapsed := clampf(float(now_usec - _budget_updated_usec) / 1000000.0, 0.0, 1.0)
	_budget_updated_usec = now_usec
	_packet_tokens = minf(PACKET_BURST, _packet_tokens + elapsed * PACKET_RATE)
	_response_tokens = minf(RESPONSE_BURST, _response_tokens + elapsed * RESPONSE_RATE)

func _exit_tree() -> void:
	close()
