extends SceneTree
## Version mismatch is rejected before a world or authenticated seat is created.
const Protocol := preload("res://scripts/network_protocol.gd")
const Messages := preload("res://scripts/network_messages.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
class RoutingProbe extends "res://scripts/network_session.gd":
	var packets: Array[Dictionary] = []
	func _send_encoded(data: PackedByteArray, _reliable: bool, _target_id: int = 0, _channel: int = -1) -> bool:
		packets.append(Protocol.decode(data))
		return true
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func legacy_packet(kind: String, fallback: Dictionary) -> Dictionary:
	var source := OS.get_environment("BUNKERCREW_COMPAT_PACKET_DIR")
	if source.is_empty(): return fallback
	var file := FileAccess.open(source.path_join(kind + ".packet"), FileAccess.READ)
	check(file != null, "Actual unchanged old export supplied its " + kind + " packet")
	return Protocol.decode(file.get_buffer(file.get_length())) if file != null else {}

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var host := RoutingProbe.new()
	game.add_child(host)
	host.game = game
	host.set_process(false)
	host.set_physics_process(false)
	host.active = true
	host.is_host = true
	host.state = "lobby"
	host.relay_url = "ws://127.0.0.1:24999/ws"
	host._peer_connected_id(80)
	var old_hello := legacy_packet("hello", {"kind":"hello", "version":Protocol.VERSION, "build":Protocol.BUILD, "resume":"", "invite":"", "name":"Old guest"})
	check(Messages.valid(old_hello, true), "A legacy Hello remains a recognizable version mismatch")
	host._packet_from(Protocol.encode(old_hello), 80)
	check(not host._peers[80]._authenticated and host._slots.is_empty(), "An old guest cannot reserve an authenticated current-world seat")
	check(host.packets.any(func(row): return row.kind == "reject" and row.message == "Die Spielversionen passen nicht zusammen."), "Old guest receives the existing clear version rejection")
	check(not game.started and host.world == null, "Mismatched Hello never allocates a gameplay world")
	await create_timer(0.25, true).timeout
	host.packets.clear()
	host._peer_connected_id(81)
	var hello := old_hello.duplicate()
	hello.world_revision = Protocol.WORLD_REVISION
	hello.content_fingerprint = preload("res://scripts/content_registry.gd").fingerprint()
	hello.voice_member_keys = true
	host._packet_from(Protocol.encode(hello), 81)
	check(host._peers[81]._authenticated and host._slots.has(2), "Matching world revision authenticates a current guest")
	var welcomes: Array[Dictionary] = []
	for row: Dictionary in host.packets:
		if row.kind == "welcome": welcomes.append(row)
	check(welcomes.size() == 1, "Matching Hello produces exactly one authoritative Welcome")
	var welcome: Dictionary = welcomes[0]
	check(welcome.world_revision == Protocol.WORLD_REVISION and welcome.size() == 19 and Messages.valid(welcome, false), "Current nineteen-field Welcome carries world revision, content identity and optional voice binding")
	host._peer_connected_id(82)
	var previous_hello := hello.duplicate(true)
	previous_hello.world_revision = Protocol.WORLD_REVISION-1
	host._packet_from(Protocol.encode(previous_hello),82)
	check(not host._peers[82]._authenticated and host._slots.size()==1,"Immediately previous aircraft world contract cannot reserve another seat")
	check(host.packets.back().kind=="reject" and host.packets.back().message=="Die Spielversionen passen nicht zusammen.","Previous explicit revision receives a clear rejection before its changed profiles reach the world")
	var malformed := hello.duplicate()
	malformed.world_revision = 2.0
	check(not Messages.valid(malformed, true), "World revision is an integer wire contract")
	malformed.world_revision = 256
	check(not Messages.valid(malformed, true), "World revision retains a bounded allocation contract")
	var guest = game.network
	guest.set_process(false)
	guest.set_physics_process(false)
	guest.active = true
	guest.is_host = false
	guest.state = "connecting"
	guest._hello_sent = true
	guest.relay_url = host.relay_url
	var old_welcome := welcome.duplicate(true)
	old_welcome.erase("world_revision")
	old_welcome.erase("voice_member_keys")
	old_welcome = legacy_packet("welcome", old_welcome)
	check(Messages.valid(old_welcome, false), "Legacy Welcome reaches clear version rejection rather than malformed-packet retries")
	guest._packet(Protocol.encode(old_welcome))
	check(guest.state == "error" and guest.error_message == "Die Spielversionen passen nicht zusammen.", "New guest immediately rejects an old host without revision")
	check(not guest._authenticated and guest.world == null and not game.started, "Old-host mismatch never installs token authentication or a campaign world")
	guest.leave()
	guest.active = true
	guest.state = "connecting"
	guest._hello_sent = true
	guest.relay_url = host.relay_url
	var previous_welcome := welcome.duplicate(true)
	previous_welcome.world_revision = Protocol.WORLD_REVISION-1
	guest._packet(Protocol.encode(previous_welcome))
	check(guest.state=="error" and not guest._authenticated and guest.world==null,"Guest rejects previous explicit world revision before allocating changed aircraft profiles")
	guest.leave()
	guest.active = true
	guest.state = "connecting"
	guest._hello_sent = true
	guest.relay_url = host.relay_url
	guest._packet(Protocol.encode(welcome))
	check(guest._authenticated and guest.peer_connected and guest.state == "lobby", "Current guest accepts the current host revision before lobby interaction")
	check(guest._voice_member_keys_supported, "World revision preserves independently negotiated voice identity binding")
	host.leave()
	guest.leave()
	paused = false
	check(await Cleanup.free_scene(game, self), "Rejected and accepted handshakes release their actual main-scene audio and nodes")
	print("NETWORK WORLD REVISION: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
