class_name NetworkTransport
extends Node
## Manually-polled host and three independent UDP/ENet guests. Packets stay opaque.

signal packet(data: PackedByteArray)
signal packet_from(data: PackedByteArray, sender: int)
signal peer_joined(id: int)
signal peer_left(id: int, reason: String)
signal peer_error(id: int, message: String)
signal connected
signal disconnected(reason: String)
signal error(message: String)
signal public_address_ready(address: String, hint: String)

const JOIN_CODE = preload("res://scripts/network_join_code.gd")
const VoiceGuard := preload("res://scripts/network_voice_guard.gd")
const DEFAULT_PORT := 24777
const MAX_PACKET_BYTES := 512 * 1024
const CONNECT_TIMEOUT := 10.0
const CHANNEL_COUNT := 3
const BANDWIDTH_BYTES := 2097152
const VOICE_CHANNEL := 2
const MAX_VOICE_BYTES := 1200
const MAX_POLL_PACKETS := 32
const MAX_POLL_SCANNED := 256
const MAX_VOICE_PER_POLL := 4
const MAX_POLL_BYTES := 512 * 1024
const MAX_POLL_USEC := 2000
const MAX_BACKLOG_PACKETS := 128
const MAX_MAPPING_JOBS := 2
# Reliable state/control, sequenced input, and independent voice have separate
# budgets. Voice cannot consume the input/control allowance.
# Reliable input can catch up after two seconds at 60 physics ticks/second,
# alongside small control messages. Sustained and voice limits stay separate.
const PACKET_BURSTS := [192.0, 96.0, 36.0]
const PACKET_RATES := [64.0, 90.0, 195.0]
const BYTE_BURSTS := [2097152.0, 131072.0, 43200.0]
const BYTE_RATES := [2097152.0, 131072.0, 234000.0]
var peer: ENetMultiplayerPeer
var is_host := false
var connected_peer := 0
var port := DEFAULT_PORT
var lan_address := "127.0.0.1"
var public_address := ""
var mapping_confirmed := false
var mapping_hint := ""
var _connecting := false
var _connect_started := 0
static var _mapping_cleanup: Node
var _jobs: Array = []
var _active_job: RouterMappingJob
var _packet_tokens: Array = PACKET_BURSTS.duplicate()
var _byte_tokens: Array = BYTE_BURSTS.duplicate()
var _budget_updated_usec := 0
var last_packet_channel := -1
var last_poll_packets := 0
var last_poll_scanned := 0
var last_poll_bytes := 0
var last_poll_usec := 0
var rejected_packets := 0
var _backlog_started := 0
var _signal_epoch := 0
var _disconnecting := false
var remote_peers: Dictionary = {}
var _disconnecting_peers: Dictionary = {}
var _peer_budgets: Dictionary = {}
var dropped_voice_packets := 0

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	if not is_instance_valid(_mapping_cleanup):
		_mapping_cleanup = preload("res://scripts/router_mapping_cleanup.gd").new()
		_mapping_cleanup.name = "RouterMappingCleanup"
		get_tree().root.add_child.call_deferred(_mapping_cleanup)

func host(server_port: int = DEFAULT_PORT, auto_map: bool = true) -> Error:
	close()
	if server_port < 1024 or server_port > 65535:
		error.emit("Bitte einen UDP-Port zwischen 1024 und 65535 wählen.")
		return ERR_INVALID_PARAMETER
	peer = ENetMultiplayerPeer.new()
	var result := peer.create_server(server_port, 3, CHANNEL_COUNT, BANDWIDTH_BYTES*3, BANDWIDTH_BYTES*3)
	if result != OK:
		peer = null
		error.emit(LocaleText.format("UDP-Port %d ist nicht verfügbar. Bitte einen anderen Port wählen.",server_port))
		return result
	# Godot 4.7 create_server forwards max_channels into the native incoming
	# bandwidth argument. Reapply both settings explicitly: otherwise a host
	# advertises only five bytes/second and drops nearly all incoming voice.
	peer.host.bandwidth_limit(BANDWIDTH_BYTES*3, BANDWIDTH_BYTES*3)
	peer.host.channel_limit(CHANNEL_COUNT + 2) # ENetMultiplayerPeer reserves two.
	is_host = true
	port = server_port
	lan_address = _local_address()
	_attach_signals()
	mapping_hint = "Im selben Netzwerk bereit. Internetfreigabe wird geprüft." if auto_map else "Im selben Netzwerk bereit. Routerfreigabe nicht angefordert."
	var cleanup := _mapping_cleanup
	var pending: int = cleanup.jobs.size() if is_instance_valid(cleanup) else 0
	if auto_map and _jobs.size()+pending < MAX_MAPPING_JOBS:
		_active_job = RouterMappingJob.new()
		_active_job.port = server_port
		_jobs.append(_active_job)
		var thread_result := _active_job.thread.start(_active_job.run)
		if thread_result != OK:
			_jobs.erase(_active_job)
			_active_job = null
			mapping_hint = "LAN bereit. Routerprüfung konnte nicht gestartet werden; UDP-Freigabe manuell prüfen."
			public_address_ready.emit("", mapping_hint)
	else:
		if auto_map: mapping_hint = "LAN bereit. Eine vorherige Routerprüfung wird noch beendet; Internetfreigabe manuell prüfen."
		public_address_ready.emit("", mapping_hint)
	return OK

func join(address: String, server_port: int = DEFAULT_PORT) -> Error:
	close()
	if not _valid_join_address(address) or server_port < 1 or server_port > 65535:
		error.emit("Die Beitrittsadresse ist ungültig.")
		return ERR_INVALID_PARAMETER
	peer = ENetMultiplayerPeer.new()
	var result := peer.create_client(address, server_port, CHANNEL_COUNT, BANDWIDTH_BYTES, BANDWIDTH_BYTES)
	if result != OK:
		peer = null
		error.emit("Die Verbindung konnte nicht geöffnet werden.")
		return result
	port = server_port
	_connecting = true
	lan_address = _local_address()
	_connect_started = Time.get_ticks_msec()
	_attach_signals()
	return OK

func can_send_to(target_id: int = 0) -> bool:
	var target := target_id if target_id>0 else connected_peer
	if peer == null or target == 0 or _disconnecting_peers.has(target) or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	var remote: ENetPacketPeer=remote_peers.get(target)
	if remote == null or not remote.is_active() or remote.get_state() != ENetPacketPeer.STATE_CONNECTED or remote.get_channels() == 0:
		return false
	return true

func send(data: PackedByteArray, reliable: bool = true, channel_override: int = -1, target_id: int = 0) -> Error:
	var target := target_id if target_id>0 else connected_peer
	if not can_send_to(target): return ERR_UNCONFIGURED
	var channel := (0 if reliable else 1) if channel_override == -1 else channel_override
	if channel < 0 or channel >= CHANNEL_COUNT or (channel != 0 and reliable) or (channel == 0 and not reliable): return ERR_INVALID_PARAMETER
	if data.is_empty() or data.size() > _channel_max_bytes(channel): return ERR_INVALID_PARAMETER
	peer.set_target_peer(target)
	peer.transfer_channel = channel
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	if channel == VOICE_CHANNEL: peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	return peer.put_packet(data)

func flush_departure() -> void:
	if peer!=null and is_instance_valid(_mapping_cleanup):
		_mapping_cleanup.retire_peer(peer)
		peer=null

func close() -> void:
	_signal_epoch += 1
	_backlog_started=0
	if peer != null:
		peer.close()
		peer = null
	if _active_job != null:
		_active_job.stop()
		_active_job = null
	is_host = false
	remote_peers.clear()
	_disconnecting_peers.clear()
	_peer_budgets.clear()
	connected_peer = 0
	_disconnecting = false
	_connecting = false
	public_address = ""
	mapping_confirmed = false
	mapping_hint = ""
	_reset_budgets()
	last_packet_channel = -1
	last_poll_packets = 0
	last_poll_bytes = 0
	last_poll_usec = 0
	rejected_packets = 0

func disconnect_guest(id: int = 0) -> void:
	var target := id if id>0 else connected_peer
	if peer == null or not is_host or not remote_peers.has(target): return
	_disconnecting_peers[target]=true
	_disconnecting=_disconnecting_peers.has(connected_peer)
	peer.disconnect_peer(target)

func round_trip_ms(id: int=0) -> float:
	var remote: ENetPacketPeer=remote_peers.get(id if id>0 else connected_peer)
	return remote.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) if remote != null and remote.is_active() else 0.0

func _attach_signals() -> void:
	peer.peer_connected.connect(_peer_connected.bind(_signal_epoch))
	peer.peer_disconnected.connect(_peer_disconnected.bind(_signal_epoch))

func _peer_connected(id: int, epoch: int) -> void:
	if epoch != _signal_epoch or peer == null: return
	if remote_peers.has(id): return
	if remote_peers.size()>=(3 if is_host else 1):
		peer.disconnect_peer(id,true)
		return
	var remote: ENetPacketPeer=peer.get_peer(id)
	remote_peers[id]=remote
	_peer_budgets[id]={"packets":PACKET_BURSTS.duplicate(),"bytes":BYTE_BURSTS.duplicate(),"updated":Time.get_ticks_usec(),"voice":VoiceGuard.new()}
	if connected_peer==0:
		connected_peer=id
	_connecting=false
	_disconnecting_peers.erase(id)
	_disconnecting=false
	if remote != null:
		remote.set_timeout(32,15000,30000)
		remote.ping_interval(500)
		# Scene loads briefly inflate RTT. Recover the unreliable voice/input
		# allowance promptly, while retaining loss control on congested links.
		remote.throttle_configure(1000, 8, 1)
	_announce_connected.call_deferred(_signal_epoch,id)

func _peer_disconnected(id: int, epoch: int) -> void:
	if epoch != _signal_epoch or not remote_peers.has(id): return
	remote_peers.erase(id)
	_peer_budgets.erase(id)
	_disconnecting_peers.erase(id)
	connected_peer=int(remote_peers.keys()[0]) if not remote_peers.is_empty() else 0
	_disconnecting=_disconnecting_peers.has(connected_peer)
	_connecting=false
	_announce_peer_left.call_deferred(_signal_epoch,id,"Die Verbindung zum anderen Spieler wurde getrennt.")

func _announce_connected(epoch: int, id: int) -> void:
	if epoch == _signal_epoch and peer != null and remote_peers.has(id):
		peer_joined.emit(id)
		connected.emit()

func _announce_peer_left(epoch: int, id: int, reason: String) -> void:
	if epoch == _signal_epoch and not remote_peers.has(id):
		peer_left.emit(id,reason)
		if connected_peer==0: disconnected.emit(reason)

func _process(_delta: float) -> void:
	_poll_mapping_jobs()
	if peer == null:
		return
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		var was_connecting := _connecting
		var had_peer := connected_peer != 0
		close()
		if was_connecting:
			error.emit("Der Gastgeber ist nicht erreichbar. Code und UDP-Freigabe prüfen.")
		elif had_peer:
			disconnected.emit("Die Verbindung zum anderen Spieler wurde getrennt.")
		return
	last_poll_packets = 0
	last_poll_scanned = 0
	last_poll_bytes = 0
	var started := Time.get_ticks_usec()
	var poll_epoch := _signal_epoch
	var voice_counts := {}
	peer.poll()
	# Connected/disconnected callbacks may close the peer from the session.
	if peer == null or poll_epoch != _signal_epoch:
		return
	if _connecting:
		if Time.get_ticks_msec() - _connect_started > int(CONNECT_TIMEOUT * 1000) or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			close()
			error.emit("Keine Verbindung. Gastgeber, Code und UDP-Freigabe prüfen; ein LAN-Code funktioniert nur im selben Netzwerk.")
			return
	if peer.get_available_packet_count() > MAX_BACKLOG_PACKETS and remote_peers.size()==1:
		if _backlog_started==0: _backlog_started=Time.get_ticks_usec()
		elif Time.get_ticks_usec()-_backlog_started>1000000:
			_reject_limit(connected_peer)
			return
	else:
		_backlog_started=0
	while peer != null and poll_epoch == _signal_epoch and peer.get_available_packet_count() > 0:
		if last_poll_packets >= MAX_POLL_PACKETS or last_poll_scanned >= MAX_POLL_SCANNED or last_poll_bytes >= MAX_POLL_BYTES: break
		# Always allow one packet; packet handlers can themselves exceed the
		# remaining budget, but a heavy snapshot never multiplies into 240 decodes.
		if last_poll_scanned > 0 and Time.get_ticks_usec() - started >= MAX_POLL_USEC: break
		var sender := peer.get_packet_peer()
		var channel := peer.get_packet_channel()
		var mode := peer.get_packet_mode()
		var data := peer.get_packet()
		last_poll_scanned += 1
		last_poll_bytes += data.size()
		if not remote_peers.has(sender) or _disconnecting_peers.has(sender): continue
		var budget: Dictionary=_peer_budgets[sender]
		if channel == VOICE_CHANNEL and _valid_packet_envelope(channel,mode,data.size()):
			if not budget.voice.observe(Time.get_ticks_usec(),1 if is_host else 3):
				_reject_limit(sender)
				continue
		_packet_tokens=budget.packets
		_byte_tokens=budget.bytes
		_budget_updated_usec=int(budget.updated)
		_refill_budgets(Time.get_ticks_usec())
		budget.updated=_budget_updated_usec
		if not _accept_packet(channel, mode, data.size()):
			if channel == VOICE_CHANNEL and _valid_packet_envelope(channel,mode,data.size()):
				# Speech is disposable: a rendering stall must not terminate a match.
				_packet_tokens[channel]=maxf(0.0,float(_packet_tokens[channel]))
				_byte_tokens[channel]=maxf(0.0,float(_byte_tokens[channel]))
				dropped_voice_packets+=1
				continue
			_reject_limit(sender)
			continue
		if channel == VOICE_CHANNEL:
			var count: int = int(voice_counts.get(sender,0))
			voice_counts[sender] = count+1
			if count >= MAX_VOICE_PER_POLL*(1 if is_host else 3):
				dropped_voice_packets += 1
				continue
		last_poll_packets += 1
		last_packet_channel = channel
		packet_from.emit(data,sender)
		packet.emit(data)
	if poll_epoch == _signal_epoch: last_poll_usec = Time.get_ticks_usec() - started

func _reset_budgets() -> void:
	_packet_tokens = PACKET_BURSTS.duplicate()
	_byte_tokens = BYTE_BURSTS.duplicate()
	_budget_updated_usec = Time.get_ticks_usec()
	for budget: Dictionary in _peer_budgets.values():
		budget.packets=PACKET_BURSTS.duplicate()
		budget.bytes=BYTE_BURSTS.duplicate()
		budget.updated=_budget_updated_usec
		budget.voice=VoiceGuard.new()

func _refill_budgets(now_usec: int) -> void:
	var elapsed := clampf(float(now_usec - _budget_updated_usec) / 1000000.0, 0.0, 1.0)
	_budget_updated_usec = now_usec
	for channel in CHANNEL_COUNT:
		_packet_tokens[channel] = minf(PACKET_BURSTS[channel], float(_packet_tokens[channel]) + elapsed * PACKET_RATES[channel])
		_byte_tokens[channel] = minf(BYTE_BURSTS[channel], float(_byte_tokens[channel]) + elapsed * BYTE_RATES[channel])

func _accept_packet(channel: int, mode: int, size: int) -> bool:
	if not _valid_packet_envelope(channel,mode,size): return false
	_packet_tokens[channel] = float(_packet_tokens[channel]) - 1.0
	_byte_tokens[channel] = float(_byte_tokens[channel]) - size
	return float(_packet_tokens[channel]) >= 0.0 and float(_byte_tokens[channel]) >= 0.0

func _valid_packet_envelope(channel: int, mode: int, size: int) -> bool:
	if channel < 0 or channel >= CHANNEL_COUNT or size <= 0 or size > _channel_max_bytes(channel): return false
	if channel == VOICE_CHANNEL and mode != MultiplayerPeer.TRANSFER_MODE_UNRELIABLE: return false
	if channel == 0 and mode != MultiplayerPeer.TRANSFER_MODE_RELIABLE: return false
	if channel == 1 and mode != MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED: return false
	return true

static func _channel_max_bytes(channel: int) -> int:
	if channel == VOICE_CHANNEL: return MAX_VOICE_BYTES
	return MAX_PACKET_BYTES if channel == 0 else 16384

func _reject_limit(sender: int=0) -> void:
	rejected_packets += 1
	if is_host:
		disconnect_guest(sender)
		peer_error.emit(sender,"Die Gegenstelle hat das Netzwerkdatenlimit überschritten.")
	else:
		close()
		error.emit("Die Gegenstelle hat das Netzwerkdatenlimit überschritten.")

func diagnostics() -> Dictionary:
	return {"protocol":"UDP/ENet", "port":port, "lan_address":lan_address,
		"public_address":public_address, "connected":connected_peer != 0 and not _disconnecting,
		"rtt_ms":round_trip_ms(), "mapping_hint":mapping_hint,
		"last_poll_packets":last_poll_packets, "last_poll_bytes":last_poll_bytes,
		"last_poll_usec":last_poll_usec, "rejected_packets":rejected_packets}

static func _valid_join_address(address: String) -> bool:
	if not address.is_valid_ip_address(): return false
	if ":" in address: return address != "::" and not address.to_lower().begins_with("ff")
	var first := address.get_slice(".", 0).to_int()
	return first > 0 and first < 224

func _poll_mapping_jobs() -> void:
	for job in _jobs.duplicate():
		var report: Dictionary = job.take_report()
		if job == _active_job and not report.is_empty():
			public_address = str(report.get("address", ""))
			mapping_confirmed = bool(report.get("mapped", false))
			mapping_hint = LocaleText.format(str(report.hint),report.args) if report.has("args") else LocaleText.text(str(report.get("hint", "")))
			public_address_ready.emit(public_address, mapping_hint)
		if not job.thread.is_alive():
			job.thread.wait_to_finish()
			_jobs.erase(job)

func _exit_tree() -> void:
	close()
	var cleanup := _mapping_cleanup
	if is_instance_valid(cleanup):
		cleanup.adopt(_jobs)
	else:
		for job in _jobs:
			job.stop()
			if job.thread.is_started(): job.thread.wait_to_finish()
	_jobs.clear()

static func _local_address() -> String:
	var addresses := lan_addresses()
	return addresses[0] if not addresses.is_empty() else "127.0.0.1"

static func lan_addresses(interfaces: Array = []) -> PackedStringArray:
	# Godot enumerates VPNs and container bridges before the user's Wi-Fi on
	# some systems. Prefer physical adapters instead of the first private IP.
	if interfaces.is_empty(): interfaces = IP.get_local_interfaces()
	var physical := PackedStringArray()
	var virtual := PackedStringArray()
	for interface: Dictionary in interfaces:
		var interface_name := str(interface.get("name", "")).to_lower()
		var friendly := str(interface.get("friendly", "")).to_lower()
		var is_virtual := interface_name in ["lo", "lo0"]
		for prefix in ["docker", "br-", "veth", "virbr", "tun", "tap", "wg", "tailscale", "zerotier", "zt", "vbox", "vmnet", "vethernet"]:
			if interface_name.begins_with(prefix): is_virtual = true
		for marker in ["loopback", "vpn", "virtual", "hyper-v", "vmware", "virtualbox", "tailscale", "zerotier", "tunnel", "wireguard", "wintun"]:
			if marker in friendly: is_virtual = true
		for raw_address in interface.get("addresses", []):
			var address := str(raw_address)
			if ":" in address or not _valid_join_address(address) or address.begins_with("127.") or address.begins_with("169.254."): continue
			if is_virtual:
				if not address in virtual: virtual.append(address)
			elif not address in physical:
				physical.append(address)
	return physical if not physical.is_empty() else virtual

class RouterMappingJob extends RefCounted:
	var port := DEFAULT_PORT
	var thread := Thread.new()
	var _mutex := Mutex.new()
	var _stopped := false
	var _report: Dictionary = {}
	var _description := "Bunkercrew-" + Crypto.new().generate_random_bytes(8).hex_encode()

	func stop() -> void:
		_mutex.lock()
		_stopped = true
		_mutex.unlock()

	func stopped() -> bool:
		_mutex.lock()
		var value := _stopped
		_mutex.unlock()
		return value

	func take_report() -> Dictionary:
		_mutex.lock()
		var value := _report
		_report = {}
		_mutex.unlock()
		return value

	func report(address: String, hint: String, args: Variant=null, mapped: bool=false) -> void:
		_mutex.lock()
		_report = {"address":address, "hint":hint, "mapped":mapped}
		if args!=null: _report.args=args
		_mutex.unlock()

	func run() -> void:
		var upnp := UPNP.new()
		var discovered := upnp.discover(2000, 2, "InternetGatewayDevice")
		if stopped():
			return
		if discovered != UPNP.UPNP_RESULT_SUCCESS or upnp.get_gateway() == null or not upnp.get_gateway().is_valid_gateway():
			report("", "LAN bereit. Routerfreigabe nicht verfügbar: für Internet UDP %d am Router auf diesen PC weiterleiten.", port)
			return
		var gateway := upnp.get_gateway()
		var address := gateway.query_external_address()
		if not JOIN_CODE.is_public_address(address):
			report("", "LAN bereit. Der Router meldet keine öffentliche IPv4-Adresse (z. B. DS-Lite/CGNAT). Internet benötigt eine öffentliche IPv4 oder einen Relay.")
			return
		# Never overwrite an existing manual or third-party router rule.
		var existing := _query_mapping(gateway)
		if existing.get("state", "unknown") != "absent":
			report(address, "Öffentliche Adresse erkannt. Automatische Freigabe nicht bestätigt; bestehende Regeln bleiben unverändert. UDP %d am Router prüfen.", port)
			return
		if stopped():
			return
		var mapped := gateway.add_port_mapping(port, port, _description, "UDP", 600)
		if mapped != UPNP.UPNP_RESULT_SUCCESS:
			report(address, "Öffentliche Adresse erkannt. Automatische Freigabe fehlgeschlagen; UDP %d manuell auf diesen PC weiterleiten.", port)
			return
		report(address, "Router hat UDP %d freigegeben. Der Gast kann den Internetcode testen.", port, true)
		var renewed_at := Time.get_ticks_msec()
		while not stopped():
			OS.delay_msec(100)
			if Time.get_ticks_msec() - renewed_at < 300000:
				continue
			var renewal_mapping := _query_mapping(gateway)
			if renewal_mapping.get("description", "") != _description:
				report(address, "Routerfreigabe wurde verändert. UDP %d am Router prüfen.", port)
				break
			if gateway.add_port_mapping(port, port, _description, "UDP", 600) != UPNP.UPNP_RESULT_SUCCESS:
				report(address, "Routerfreigabe konnte nicht verlängert werden. UDP %d am Router prüfen.", port)
				break
			renewed_at = Time.get_ticks_msec()
		# Delete only a rule that still carries this session's random owner marker.
		var current := _query_mapping(gateway)
		if current.get("description", "") == _description and current.get("client", "") == gateway.igd_our_addr:
			gateway.delete_port_mapping(port, "UDP")

	func _query_mapping(gateway: UPNPDevice) -> Dictionary:
		var pattern := RegEx.new()
		pattern.compile("^http://([^/:]+)(?::([0-9]+))?(/.*)$")
		var url := pattern.search(gateway.igd_control_url)
		if url == null:
			return {}
		var client := HTTPClient.new()
		var http_port := url.get_string(2).to_int() if not url.get_string(2).is_empty() else 80
		if client.connect_to_host(url.get_string(1), http_port) != OK:
			return {}
		var deadline := Time.get_ticks_msec() + 2500
		while client.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING] and Time.get_ticks_msec() < deadline:
			client.poll()
			OS.delay_msec(5)
		if client.get_status() != HTTPClient.STATUS_CONNECTED:
			client.close()
			return {}
		var action := "GetSpecificPortMappingEntry"
		var body := '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:%s xmlns:u="%s"><NewRemoteHost></NewRemoteHost><NewExternalPort>%d</NewExternalPort><NewProtocol>UDP</NewProtocol></u:%s></s:Body></s:Envelope>' % [action, gateway.igd_service_type.xml_escape(), port, action]
		var headers := PackedStringArray(['Content-Type: text/xml; charset="utf-8"', 'SOAPAction: "%s#%s"' % [gateway.igd_service_type, action]])
		if client.request(HTTPClient.METHOD_POST, url.get_string(3), headers, body) != OK:
			client.close()
			return {}
		var bytes := PackedByteArray()
		while Time.get_ticks_msec() < deadline:
			client.poll()
			if client.get_status() == HTTPClient.STATUS_BODY:
				bytes.append_array(client.read_response_body_chunk())
			elif client.get_status() not in [HTTPClient.STATUS_REQUESTING]:
				break
			if bytes.size() > 32768:
				break
			OS.delay_msec(5)
		client.close()
		var parser := XMLParser.new()
		if bytes.size() > 32768 or parser.open_buffer(bytes) != OK:
			return {}
		var values: Dictionary = {}
		var tag := ""
		while parser.read() == OK:
			if parser.get_node_type() == XMLParser.NODE_ELEMENT:
				tag = parser.get_node_name().get_slice(":", parser.get_node_name().get_slice_count(":") - 1)
			elif parser.get_node_type() == XMLParser.NODE_TEXT and tag in ["errorCode", "NewPortMappingDescription", "NewInternalClient"]:
				values[tag] = parser.get_node_data()
		if str(values.get("errorCode", "")) == "714":
			return {"state":"absent"}
		if values.has("NewInternalClient"):
			return {"state":"present", "description":str(values.get("NewPortMappingDescription", "")), "client":str(values.NewInternalClient)}
		return {}
