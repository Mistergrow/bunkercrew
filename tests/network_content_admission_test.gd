extends SceneTree
## Real decoded admission cannot displace an existing player before content agrees.
const Content := preload("res://scripts/content_registry.gd")
const Protocol := preload("res://scripts/network_protocol.gd")
const Messages := preload("res://scripts/network_messages.gd")
const Peer := preload("res://scripts/network_peer_state.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
var game

class RecordingTransport extends Node:
	var connected_peer := 20
	var last_packet_channel := 0
	var remote_peers: Dictionary = {}
	var packets: Array[Dictionary] = []
	var disconnected: Array[int] = []
	func send(packet: PackedByteArray,_reliable: bool,_channel: int,peer: int) -> Error:
		packets.append({"peer":peer,"message":Protocol.decode(packet)})
		return OK
	func close() -> void: remote_peers.clear()
	func disconnect_guest(peer: int) -> void: disconnected.append(peer)
	func flush_departure() -> void: pass

func _initialize() -> void: _run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func hello() -> Dictionary:
	return {"kind":"hello","version":Protocol.VERSION,"build":Protocol.BUILD,"world_revision":Protocol.WORLD_REVISION,"content_fingerprint":Content.fingerprint(),"resume":"a".repeat(48),"invite":"b".repeat(16),"name":"Returning crew"}

func host_fixture() -> RecordingTransport:
	var session = game.network
	session.leave()
	session.active = true
	session.is_host = true
	session.state = "lobby"
	session._invite_secret = "b".repeat(16)
	var existing: Dictionary = Peer.create(0)
	existing.slot = 2
	existing.wire = 10
	existing._authenticated = true
	existing._guest_token = "a".repeat(48)
	session._slots[2] = existing
	session._peers[10] = existing
	var incoming: Dictionary = Peer.create(0)
	incoming.wire = 20
	session._peers[20] = incoming
	session._enter_peer(20)
	var recorder := RecordingTransport.new()
	root.add_child(recorder)
	session.transport = recorder
	return recorder

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	check(Content.diagnostics().is_empty(),"Local bundled registry is valid")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.campaign.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.network.set_process(false)
	game.network.set_physics_process(false)
	var session = game.network
	var absent := hello()
	absent.erase("content_fingerprint")
	check(Messages.valid(absent,true),"Legacy envelope reaches an explicit update error instead of a generic malformed-packet rejection")
	for fingerprint: Variant in [null,0,"","f".repeat(63),"f".repeat(65),"F".repeat(64),"g".repeat(64)]:
		var malformed := hello()
		malformed.content_fingerprint = fingerprint
		check(not Messages.valid(malformed,true),"Malformed content fingerprint is refused before session state changes: "+str(fingerprint))
	var different := hello()
	different.content_fingerprint = "0".repeat(64) if Content.fingerprint()!="0".repeat(64) else "1".repeat(64)
	for message: Dictionary in [absent,different]:
		var recorder := host_fixture()
		var original_link: Dictionary = session._slots[2]
		session._packet(Protocol.encode(message))
		check(session._rejecting and not session._authenticated,"Host rejects absent/mismatched contents before authentication")
		check(session._slots.size()==1 and session._slots[2]==original_link and session._slots[2].wire==10 and session._peers.has(10) and recorder.disconnected.is_empty(),"Rejected resume cannot remove the existing authenticated link or claim its slot")
		check(recorder.packets.size()==1 and recorder.packets[0].message.kind=="reject" and "Spielinhalte" in str(recorder.packets[0].message.message),"Host sends a specific content-installation error over the existing binary control path")
	var accepted_transport := host_fixture()
	session._packet(Protocol.encode(hello()))
	check(session._authenticated and session._slots[2].wire==20 and not session._peers.has(10),"Matching content still permits the existing authenticated resume handover")
	var welcomes := accepted_transport.packets.filter(func(row): return row.message.get("kind")=="welcome")
	check(welcomes.size()==1 and welcomes[0].message.content_fingerprint==Content.fingerprint() and Messages.valid(welcomes[0].message,false),"Actual host Welcome carries a valid matching content identity including the full lobby schema")
	var welcome: Dictionary = welcomes[0].message.duplicate(true) if welcomes.size()==1 else {}
	for mismatch: bool in [false,true]:
		session.leave()
		session.active = true
		session.is_host = false
		session.state = "connecting"
		session._hello_sent = true
		var message := welcome.duplicate(true)
		if mismatch: message.content_fingerprint = different.content_fingerprint
		else: message.erase("content_fingerprint")
		session._packet(Protocol.encode(message))
		check(session.state=="error" and not session._authenticated and session._client_token.is_empty() and "Spielinhalte" in session.error_message,"Guest rejects legacy/mismatched host before accepting its resume token or lobby")
	session.leave()
	session.active = true
	session.is_host = false
	session.state = "connecting"
	session._hello_sent = true
	session._packet(Protocol.encode(welcome))
	check(session._authenticated and session.state=="lobby" and session._client_token==welcome.token,"Guest accepts a matching current host without changing protocol/relay wire identity")
	session.leave()
	paused = false
	check(await Cleanup.free_scene(game,self),"Content admission fixture releases the actual scene, decoder and audio")
	print("NETWORK CONTENT ADMISSION: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
