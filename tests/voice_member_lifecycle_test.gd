extends SceneTree
## Prepared real room packets and real playback, without opening a microphone.
const Protocol := preload("res://scripts/network_protocol.gd")
const Codec := preload("res://scripts/voice_codec.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Messages := preload("res://scripts/network_messages.gd")
class RoutingProbe extends "res://scripts/network_session.gd":
	var packets: Array[Dictionary] = []
	func _send_encoded(data: PackedByteArray, reliable: bool, target_id: int = 0, channel: int = -1) -> bool:
		packets.append({"message":Protocol.decode(data), "target":target_id, "channel":channel, "reliable":reliable})
		return true
var checks := 0
var failures := 0
var game
var network
var pcm := PackedByteArray()

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("VOICE MEMBER ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1
		push_error(label)

func join_member(wire: int, binding: bool = false) -> int:
	network._peer_connected_id(wire)
	var hello := {"kind":"hello", "version":Protocol.VERSION, "build":Protocol.BUILD, "world_revision":Protocol.WORLD_REVISION, "content_fingerprint":preload("res://scripts/content_registry.gd").fingerprint(), "resume":"", "invite":network._invite_secret, "name":"Guest %d" % wire}
	if binding: hello.voice_member_keys = true
	network._packet_from(Protocol.encode(hello), wire)
	return int(network._peers[wire].slot)

func speech(wire: int, slot: int, sequence: int) -> void:
	network._packet_from(Protocol.encode({"kind":"voice", "generation":network._generation, "seq":sequence, "rate":Codec.RATE, "pcm":pcm, "player_id":slot}), wire)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	network = game.network
	network.set_process(false)
	network.set_physics_process(false)
	network.active = true
	network.is_host = true
	network.state = "lobby"
	# The fixture uses the relay envelope so no fake ENet channel is needed.
	# No WebSocket is created, and all replies stay within this isolated room.
	network.relay_url = "ws://127.0.0.1:24999/ws"
	network._invite_secret = network.JoinCode.new_invitation()
	game.voice.set_process(false)
	game.voice.set_enabled(true)
	pcm.resize(Codec.BYTES)
	var slot := join_member(20)
	check(slot == 2 and network.is_player_connected(2), "Real hello authenticates the first room member")
	for sequence in [1000,1001,1002]: speech(20, slot, sequence)
	check(game.voice.received_frames == 3 and game.voice._queue.size() == 3, "Old member has real queued speech and an advanced replay window")
	network._peer_disconnected_id(20, "Partner hat die Sitzung verlassen.")
	check(not network._voice_sources.has(2) and game.voice._queue.is_empty(), "Final lobby departure retires only that member's replay and queued playback")
	slot = join_member(21)
	check(slot == 2, "A distinct authenticated member reuses the empty room seat")
	for sequence in [1,2,3]: speech(21, slot, sequence)
	check(game.voice.received_frames == 6 and game.voice._expected == 1 and game.voice._queue.size() == 3, "Replacement speech starts immediately at sequence one without inheriting old audio")
	var received: int = game.voice.received_frames
	speech(21, slot, 3)
	check(game.voice.received_frames == received, "Same-member replay protection remains active")
	var third_slot := join_member(30)
	for sequence in [50,51,52]: speech(30, third_slot, sequence)
	check(third_slot == 3 and game.voice._receivers.has(3), "A second speaker has a separate real playback buffer")
	var other = game.voice._receivers[3]
	network._peer_disconnected_id(21, "Partner hat die Sitzung verlassen.")
	check(other._queue.size() == 3 and network._voice_sources.has(3), "Another guest's departure preserves healthy speaker packets")
	network._compact_lobby_slots()
	check(network._slots.has(2) and not network._slots.has(3), "The remaining guest is compacted before the round")
	check(not network._voice_sources.has(3), "Old slot replay state cannot leak across roster compaction")
	var before: int = game.voice.received_frames
	speech(30, 2, 53)
	check(game.voice.received_frames == before + 1, "Compacted member continues with its next legitimate voice frame")
	var modern_slot := join_member(40, true)
	check(modern_slot == 3 and network._peers[40].voice_member_keys and not network._peers[30].voice_member_keys, "Hello negotiates binding independently for modern and existing guests")
	before = game.voice.received_frames
	speech(40, 3, 1)
	check(game.voice.received_frames == before, "A guest requesting binding cannot downgrade its own speech to an unbound frame")
	var bound := {"kind":"voice", "generation":0, "seq":1, "rate":Codec.RATE, "pcm":pcm, "player_id":3, "member_key":network._voice_members["2"]}
	network._packet_from(Protocol.encode(bound), 40)
	check(game.voice.received_frames == before and not network._voice_sources.has(3), "Authenticated guest cannot borrow another member key to poison its replay window")
	bound.member_key = network._voice_members["3"]
	network._packet_from(Protocol.encode(bound), 40)
	check(game.voice.received_frames == before + 1, "The bound guest's legitimate sequence one is accepted after rejected frames")
	var routing := RoutingProbe.new()
	game.add_child(routing)
	routing.set_process(false)
	routing.set_physics_process(false)
	routing._peers = network._peers.duplicate(true)
	routing._voice_members = network._voice_members.duplicate()
	routing._broadcast_voice({"kind":"voice", "generation":0, "seq":2, "rate":Codec.RATE, "pcm":pcm, "player_id":1})
	check(routing.packets.size() == 2 and routing.packets[0].channel == 2 and routing.packets[1].channel == 2, "Host sends one bounded voice envelope per authenticated recipient on the independent voice channel")
	var legacy_frame: Dictionary = routing.packets.filter(func(item): return item.target == 30)[0].message
	var modern_frame: Dictionary = routing.packets.filter(func(item): return item.target == 40)[0].message
	check(legacy_frame.size() == 6 and not legacy_frame.has("member_key") and Codec.valid(legacy_frame), "Guest without optional voice binding still receives its original six-field envelope")
	check(modern_frame.size() == 7 and modern_frame.member_key == network._voice_members["1"] and Codec.valid(modern_frame), "Negotiated guest receives the same audio bound to the host's identity")
	routing.packets.clear()
	routing._broadcast_voice(legacy_frame.merged({"player_id":2}, true), 30)
	check(routing.packets.size() == 1 and routing.packets[0].target == 40 and routing.packets[0].message.member_key == network._voice_members["2"], "Host binds legacy-speaker forwarding too and never echoes it to the sender")
	routing.queue_free()
	check(not game.microphone.capturing, "All lifecycle coverage leaves the microphone closed")
	await guest_roster()
	network.leave()
	paused = false
	check(await Cleanup.free_scene(game, self), "Room playback and native streams release cleanly")
	print("VOICE MEMBER LIFECYCLE: %d/%d checks passed" % [checks-failures, checks])
	quit(1 if failures else 0)

func guest_roster() -> void:
	var guest = load("res://scenes/main.tscn").instantiate()
	root.add_child(guest)
	var room = guest.network
	room.set_process(false)
	room.set_physics_process(false)
	room.active = true
	room.is_host = false
	room.local_player_id = 4
	room._authenticated = false
	room._hello_sent = true
	room.peer_connected = false
	room.state = "lobby"
	room.relay_url = network.relay_url
	guest.voice.set_process(false)
	guest.voice.set_enabled(true)
	var roster: Dictionary = network._lobby_message().duplicate(true)
	roster.count = 3
	roster.player_id = 4
	roster.slots = [1,3,4]
	roster.members = {"1":"a".repeat(48), "3":"c".repeat(48), "4":"d".repeat(48)}
	roster.names = {"1":"Host", "3":"First guest", "4":"Local guest"}
	roster.kind = "welcome"
	roster.version = Protocol.VERSION
	roster.build = Protocol.BUILD
	roster.world_revision = Protocol.WORLD_REVISION
	roster.content_fingerprint = preload("res://scripts/content_registry.gd").fingerprint()
	roster.token = "d".repeat(48)
	roster.voice_member_keys = true
	room._packet(Protocol.encode(roster))
	check(room._authenticated and room._voice_member_keys_supported and Messages.valid(roster, false), "Real nineteen-field Welcome confirms the offered member binding")
	roster.kind = "lobby"
	for key in ["version", "build", "token", "voice_member_keys", "world_revision", "content_fingerprint"]: roster.erase(key)
	var frame := {"kind":"voice", "generation":0, "seq":3000, "rate":Codec.RATE, "pcm":pcm, "player_id":3, "member_key":"c".repeat(48)}
	room._packet(Protocol.encode(frame))
	check(guest.voice.received_frames == 1, "Real guest decodes the initial host roster and authenticated speaker")
	check(room.set_player_muted(3, true), "Guest mutes the identified remote member")
	roster.player_id = 3
	roster.slots = [1,2,3]
	roster.members = {"1":"a".repeat(48), "2":"c".repeat(48), "3":"d".repeat(48)}
	roster.names = {"1":"Host", "2":"First guest", "3":"Local guest"}
	room._packet(Protocol.encode(roster))
	check(room.local_player_id == 3 and room.is_player_muted(2) and not room.is_player_muted(3), "Guest compaction keeps local identity and remote mute attached to the same people")
	check(guest.voice._muted_senders.has(2) and not guest.voice._muted_senders.has(3), "Compaction updates playback mute immediately, before the next presence refresh")
	frame.player_id = 2
	frame.seq = 3001
	room._packet(Protocol.encode(frame))
	check(guest.voice.received_frames == 1, "A compacted muted person's first speech cannot briefly become audible")
	check(room.set_player_muted(2, false), "Explicit unmute still works on the person's new seat")
	frame.seq = 3002
	room._packet(Protocol.encode(frame))
	check(guest.voice.received_frames == 2 and guest.voice._receivers.has(2), "Compacted unmuted guest has fresh real playback and accepts its next frame")
	var delayed_old := frame.duplicate(true)
	delayed_old.seq = 3003
	frame.player_id = 1
	frame.member_key = roster.members["1"]
	frame.seq = 90
	room._packet(Protocol.encode(frame))
	var healthy = guest.voice._receivers[1]
	roster.members["2"] = "e".repeat(48)
	room._packet(Protocol.encode(roster))
	check(healthy._queue.has(90), "Replacing one guest's identity preserves the host's pending speech")
	frame.player_id = 2
	frame.member_key = roster.members["2"]
	frame.seq = 1
	room._packet(Protocol.encode(frame))
	check(room._voice_sources[2].highest == 1 and guest.voice._receivers[2]._expected == 1, "A guest hears a replacement room member immediately at sequence one")
	room._packet(Protocol.encode(delayed_old))
	check(room._voice_sources[2].highest == 1, "In-flight previous-member UDP cannot poison the replacement's replay window after its roster arrives")
	frame.seq = 2
	room._packet(Protocol.encode(frame))
	check(room._voice_sources[2].highest == 2, "Replacement sequence two remains audible after a delayed old UDP frame")
	frame.player_id = 4
	frame.seq = 9999
	room._packet(Protocol.encode(frame))
	check(not room._voice_sources.has(4) and not guest.voice._receivers.has(4), "Delayed speech from a departed seat cannot recreate a stale playback stream")
	var bounded := true
	for replacement in 12:
		roster.members["2"] = Crypto.new().generate_random_bytes(24).hex_encode()
		room._packet(Protocol.encode(roster))
		frame.player_id = 2
		frame.member_key = roster.members["2"]
		frame.seq = 1
		room._packet(Protocol.encode(frame))
		await process_frame
		bounded = bounded and guest.voice._receivers.size() == 2 and guest.voice.get_child_count() == 3
	check(bounded, "Repeated member replacement keeps exactly the active receivers and one primary audio player")
	room.leave()
	room.active = true
	room._hello_sent = true
	roster.kind = "welcome"
	roster.version = Protocol.VERSION
	roster.build = Protocol.BUILD
	roster.world_revision = Protocol.WORLD_REVISION
	roster.content_fingerprint = preload("res://scripts/content_registry.gd").fingerprint()
	roster.token = "d".repeat(48)
	room._packet(Protocol.encode(roster))
	frame.player_id = 1
	frame.seq = 1
	frame.erase("member_key")
	var received: int = guest.voice.received_frames
	room._packet(Protocol.encode(frame))
	check(room._authenticated and not room._voice_member_keys_supported and guest.voice.received_frames == received + 1, "A compatible host without optional voice binding retains unbound speech")
	room.leave()
	check(await Cleanup.free_scene(guest, self), "Guest receiver replacement releases all native playback buffers")
