extends SceneTree
## A guest can only make the host decode small control envelopes, every
## envelope is closed, and sustained excess ends that one link.
const Protocol := preload("res://scripts/network_protocol.gd")
const Messages := preload("res://scripts/network_messages.gd")
const NetInput := preload("res://scripts/network_input.gd")
const Codec := preload("res://scripts/voice_codec.gd")
const Content := preload("res://scripts/content_registry.gd")
const SessionScript := preload("res://scripts/network_session.gd")

class SessionProbe extends "res://scripts/network_session.gd":
	var sent: Array[Dictionary] = []
	func _send_encoded(packet: PackedByteArray, _reliable: bool, _target_id: int=0, _channel: int=-1) -> bool:
		sent.append(Protocol.decode(packet))
		return true
	func _send_lobby() -> void:
		pass
	func kinds(kind: String) -> int:
		return sent.filter(func(message: Dictionary): return message.get("kind") == kind).size()
class WorldProbe extends RefCounted:
	var captures := 0
	func capture() -> Dictionary:
		captures += 1
		return {"version":1, "entities":[]}
class HudProbe extends Node:
	var overlay := ""
class AudioProbe extends Node:
	var live_music: Node
class GameProbe extends Node:
	var started := true
	var hud: HudProbe
	var audio: AudioProbe
	var combat_events: CombatEvents
	var selected_characters := ["mara", "branko", "ivo", "mara"]
	var notices: Array[String] = []
	func notify(message: String) -> void: notices.append(message)

var checks := 0
var failures := 0
var game: GameProbe

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func host_session(authenticated: bool) -> SessionProbe:
	var session := SessionProbe.new()
	session.game = game
	game.add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	session.active = true
	session.is_host = true
	session.state = "playing"
	session._generation = 3
	session._authenticated = authenticated
	session.peer_connected = authenticated
	return session

func release(session: SessionProbe) -> void:
	session.leave(false)
	session.free()
	paused = false

func guest_messages() -> Dictionary:
	var held := {}
	for action: String in NetInput.ACTIONS: held[action] = 0.123456789
	var speech := PackedByteArray()
	speech.resize(Codec.BYTES)
	for index in speech.size(): speech[index] = (index * 37 + 11) % 256
	var huge := 9007199254740991
	return {
		"hello":{"kind":"hello", "version":1, "build":Protocol.BUILD, "world_revision":Protocol.WORLD_REVISION, "content_fingerprint":"a".repeat(64), "resume":"a".repeat(48), "invite":"A".repeat(16), "name":"😀".repeat(24), "voice_member_keys":true},
		"input":{"kind":"input", "generation":huge, "seq":huge, "input":{"held":held, "pressed":NetInput.ACTIONS.duplicate(), "released":NetInput.ACTIONS.duplicate(), "aim":[1234.5678, 2345.6789], "mouse":false}},
		"voice":{"kind":"voice", "seq":huge - 1, "generation":huge, "rate":Codec.RATE, "pcm":speech, "player_id":2, "member_key":"a".repeat(48)},
		"chat_send":{"kind":"chat_send", "request":huge, "text":"😀".repeat(240), "preset":""},
		"chat_private_send":{"kind":"chat_private_send", "request":huge, "recipient_id":3, "text":"😀".repeat(240)},
		"chat_name":{"kind":"chat_name", "name":"😀".repeat(24)},
		"crew_identity":{"kind":"crew_identity", "identity":{}},
		"crew_preferences":{"kind":"crew_preferences", "blocked":[1, 3, 4]},
		"command":{"kind":"command", "command":"character", "args":{"id":"mara", "player_id":4}, "generation":huge},
		"ready":{"kind":"ready", "generation":huge},
		"resync":{"kind":"resync", "generation":huge},
		"snapshot_ack":{"kind":"snapshot_ack", "seq":huge, "generation":huge},
		"pause":{"kind":"pause", "paused":true, "generation":huge},
		"ping":{"kind":"ping", "at":123456.789},
		"pong":{"kind":"pong", "at":123456.789},
		"leave":{"kind":"leave"},
	}

func test_decode_budgets() -> void:
	var samples := guest_messages()
	var largest := 0
	var most_nodes := 0
	for kind: String in samples:
		var message: Dictionary = samples[kind]
		var packet := Protocol.encode(message)
		largest = maxi(largest, var_to_bytes(message).size())
		most_nodes = maxi(most_nodes, Protocol.wire_nodes(message))
		check(Messages.valid(message, true), "The largest legitimate guest message is valid: " + kind)
		check(Protocol.decode(packet, Protocol.GUEST_DECODED, Protocol.GUEST_NODES) == message, "It decodes unchanged under the host's guest budget: " + kind)
	check(largest * 2 <= Protocol.GUEST_DECODED and most_nodes * 2 <= Protocol.GUEST_NODES, "The guest budget leaves at least twofold headroom over real traffic (%d bytes, %d values)" % [largest, most_nodes])
	for kind: String in ["hello", "input", "voice", "chat_send", "ping"]:
		check(Protocol.decode(Protocol.encode(samples[kind]), Protocol.PENDING_DECODED, Protocol.PENDING_NODES) == samples[kind], "A handshake and a relay resume's queued traffic fit the pending budget: " + kind)
	check(Protocol.PENDING_DECODED < Protocol.GUEST_DECODED and Protocol.GUEST_DECODED * 64 <= Protocol.MAX_DECODED and Protocol.PENDING_NODES < Protocol.GUEST_NODES and Protocol.GUEST_NODES * 64 <= Protocol.VariantGuard.MAX_NODES, "Pending peers get the tightest budget and guests a small fraction of the snapshot allowance")
	var filler: Array = []
	for row in 4:
		var values: Array = []
		values.resize(15000)
		values.fill(0)
		filler.append(values)
	var bomb := {"kind":"ping", "at":0, "x":filler}
	var packet := Protocol.encode(bomb)
	check(not packet.is_empty() and packet.size() < 1024 and Protocol.wire_nodes(bomb) > 60000, "A tiny compressed packet can declare tens of thousands of values")
	var started := Time.get_ticks_usec()
	check(not Protocol.decode(packet).is_empty(), "The snapshot allowance would walk all of them")
	var full_usec := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	check(Protocol.decode(packet, Protocol.GUEST_DECODED, Protocol.GUEST_NODES).is_empty(), "The host refuses it on the declared size, before decompressing")
	var guest_usec := Time.get_ticks_usec() - started
	print("HOST BUDGET decode cost: snapshot allowance %d usec, guest budget %d usec" % [full_usec, guest_usec])
	var nils: Array = []
	nils.resize(Protocol.GUEST_NODES)
	var many := {"kind":"ping", "at":0, "x":nils}
	check(var_to_bytes(many).size() <= Protocol.GUEST_DECODED and Protocol.decode(Protocol.encode(many), Protocol.GUEST_DECODED, Protocol.GUEST_NODES).is_empty() and not Protocol.decode(Protocol.encode(many)).is_empty(), "The value budget applies independently of the byte budget")
	var exact: Array = []
	exact.resize(Protocol.GUEST_NODES - 7)
	var edge := {"kind":"ping", "at":0, "x":exact}
	check(Protocol.wire_nodes(edge) == Protocol.GUEST_NODES and not Protocol.decode(Protocol.encode(edge), Protocol.GUEST_DECODED, Protocol.GUEST_NODES).is_empty(), "Exactly the permitted number of values still decodes")
	var padded := {"kind":"ping", "at":0, "x":"a".repeat(Protocol.PENDING_DECODED)}
	check(Protocol.decode(Protocol.encode(padded), Protocol.PENDING_DECODED, Protocol.PENDING_NODES).is_empty() and not Protocol.decode(Protocol.encode(padded), Protocol.GUEST_DECODED, Protocol.GUEST_NODES).is_empty(), "The pending byte budget is tighter than the guest budget")
	var incompressible := PackedByteArray()
	incompressible.resize(Protocol.GUEST_DECODED + Protocol.FRAME_OVERHEAD + 8)
	incompressible[0] = Protocol.VERSION
	check(Protocol.decode(incompressible, Protocol.GUEST_DECODED, Protocol.GUEST_NODES).is_empty(), "A packet larger than any framed guest envelope is refused unread")

func test_closed_envelopes() -> void:
	var samples := guest_messages()
	for kind: String in samples:
		var extra: Dictionary = samples[kind].duplicate(true)
		extra.x = [1, 2, 3]
		check(not Messages.valid(extra, true), "An unknown field is refused on the host: " + kind)
	var input: Dictionary = samples.input.duplicate(true)
	input.input.x = [1, 2, 3]
	check(not Messages.valid(input, true), "An unknown field inside the input frame is refused")
	input = samples.input.duplicate(true)
	input.input.pressed = "jump"
	check(not Messages.valid(input, true), "A malformed input edge list is refused")
	var guest_bound := {
		"reject":{"kind":"reject", "message":"x"},
		"pause":{"kind":"pause", "paused":true, "generation":1},
		"ping":{"kind":"ping", "at":1.0},
		"notice":{"kind":"notice", "message":LocaleText.message_payload("Der Raum ist voll.")},
		"legacy notice":{"kind":"notice", "text":"Diese Figur ist bereits in der Crew. Wähle eine andere."},
		"effects":{"kind":"effects", "generation":1, "events":[]},
		"snapshot":{"kind":"snapshot", "generation":1, "seq":1, "paused":false, "world":{}, "achievements":[]},
		"leave":{"kind":"leave"},
	}
	for kind: String in guest_bound:
		check(Messages.valid(guest_bound[kind], false), "A host message remains valid for guests: " + kind)
		var extra: Dictionary = guest_bound[kind].duplicate(true)
		extra.x = 1
		check(not Messages.valid(extra, false), "An unknown field is refused on the guest: " + kind)
	for kind: String in ["hello", "command", "ready", "input", "snapshot_ack", "resync", "pause", "ping", "pong", "leave", "chat_send", "chat_private_send", "chat_name", "crew_identity", "crew_preferences", "welcome", "reject", "lobby", "start", "snapshot", "notice", "effects", "chat_message", "chat_history", "chat_ack"]:
		check(Messages.KEYS.has(kind), "Every non-voice envelope has a closed field list: " + kind)

func test_pending_peer() -> void:
	var session := host_session(false)
	var ping := Protocol.encode({"kind":"ping", "at":1.0})
	for index in 8: session._packet(ping)
	check(not session._rejecting and session.sent.is_empty(), "A few valid packets ahead of the Hello are dropped without a reply")
	session._packet(ping)
	check(session._rejecting and session.kinds("reject") == 1 and session.active and session.state == "playing", "A ninth one ends that unauthenticated link while the room stays open")
	var captured := session.sent.size()
	for index in 50: session._packet(ping)
	check(session.sent.size() == captured, "A rejected link is no longer decoded or answered")
	release(session)
	session = host_session(false)
	session.relay_url = "ws://127.0.0.1:1/ws"
	for index in 96: session._packet(ping)
	check(not session._rejecting, "A relay resume may race its queued input and speech ahead of the new Hello")
	session._packet(ping)
	check(session._rejecting, "The relay allowance is finite as well")
	release(session)
	session = host_session(false)
	for index in SessionScript.PENDING_STRIKES - 1: session._packet(PackedByteArray([0, 1, 2]))
	check(not session._rejecting, "A pending peer is not rejected before its strike limit")
	session._packet(PackedByteArray([0, 1, 2]))
	check(session._rejecting and SessionScript.PENDING_STRIKES < SessionScript.STRIKES, "Malformed traffic ends a pending link sooner than an authenticated one")
	release(session)
	session = host_session(false)
	var oversized := Protocol.encode({"kind":"hello", "version":1, "build":"a".repeat(Protocol.PENDING_DECODED)})
	for index in SessionScript.PENDING_STRIKES: session._packet(oversized)
	check(session._rejecting, "A handshake larger than the pending budget counts as a strike")
	release(session)

func test_authenticated_flood() -> void:
	var session := host_session(true)
	var ping := Protocol.encode({"kind":"ping", "at":1.0})
	var accepted := 0
	while not session._rejecting and accepted < 500:
		session._packet(ping)
		accepted += 1
	check(session._rejecting and accepted == 6 + 32 + 1, "Pings beyond their budget use a finite allowance, then the link is rejected (after %d)" % accepted)
	check(session.kinds("pong") == 6 and session.kinds("reject") == 1, "Only budgeted pings were answered before the rejection")
	release(session)
	session = host_session(true)
	for second in 120:
		session._clock += 1.0
		for index in 3: session._packet(ping)
		session._packet(Protocol.encode({"kind":"pause", "paused":second % 2 == 0, "generation":99}))
	check(not session._rejecting and session._invalid_packets == 0, "Two minutes of ordinary control traffic never approach the allowance")
	for second in 120:
		session._clock += 1.0
		for index in 5: session._packet(ping)
	check(not session._rejecting, "A guest slightly over one budget is forgiven as the allowance refills")
	release(session)
	session = host_session(true)
	var speech := PackedByteArray()
	speech.resize(Codec.BYTES)
	for sequence in 300:
		session._packet(Protocol.encode({"kind":"voice", "seq":sequence + 1, "generation":3, "rate":Codec.RATE, "pcm":speech, "player_id":2}))
	check(not session._rejecting, "Disposable speech beyond its budget never ends a match")
	for index in 60: session._packet(Protocol.encode({"kind":"chat_name", "name":"Name %d" % index}))
	check(not session._rejecting, "Coalesced name changes are not counted as a flood")
	release(session)

func test_resync_budget() -> void:
	var session := host_session(true)
	var world := WorldProbe.new()
	session.world = world
	var resync := Protocol.encode({"kind":"resync", "generation":3})
	for index in 20: session._packet(resync)
	check(world.captures == 2 and session.kinds("snapshot") == 2, "A resync burst costs at most two world captures")
	session._clock += 1.0
	for index in 5: session._packet(resync)
	check(world.captures == 3 and not session._rejecting, "One more full state per second, as a real guest requests after a failed apply")
	for index in 40: session._packet(resync)
	check(world.captures == 3 and session._rejecting, "A sustained resync flood ends that link without further captures")
	release(session)
	session = host_session(true)
	session.world = world
	for second in 30:
		session._clock += 1.0
		session._packet(resync)
	check(world.captures == 33 and not session._rejecting, "A guest retrying once per second always gets its full state")
	release(session)
	var buffer: int = SessionScript.RELAY_BUFFER
	var reserve: int = SessionScript.RELAY_CONTROL_RESERVE
	check(SessionScript.relay_snapshot_fits(0, Protocol.MAX_PACKET), "An empty relay send buffer takes the largest snapshot")
	check(not SessionScript.relay_snapshot_fits(Protocol.MAX_PACKET, Protocol.MAX_PACKET), "A second full snapshot is skipped while the first is still queued")
	check(SessionScript.relay_snapshot_fits(buffer - reserve - 101, 100) and not SessionScript.relay_snapshot_fits(buffer - reserve - 100, 100), "Queued snapshots always leave room for control messages")
	session = host_session(true)
	session.world = world
	session.relay_url = "ws://127.0.0.1:1/ws"
	var before := world.captures
	session._packet(resync)
	check(world.captures == before + 1 and session.kinds("snapshot") == 0 and session.active and session.state == "playing", "Without a writable relay socket the resync is skipped; the room is not closed")
	release(session)

func test_duplicate_character_notice() -> void:
	var session := host_session(true)
	game.started = false
	session.state = "lobby"
	var link: Dictionary = preload("res://scripts/network_peer_state.gd").create(0.0)
	link.slot = 2
	link._authenticated = true
	session._slots[2] = link
	session._handle_command("character", {"id":"mara"}, 2)
	var notices := session.sent.filter(func(message: Dictionary): return message.get("kind") == "notice")
	check(notices.size() == 1 and Messages.valid(notices[0], false), "The duplicate-character notice is an envelope guests accept")
	check(notices.size() == 1 and LocaleText.message_text(notices[0].message) == LocaleText.text("Diese Figur ist bereits in der Crew. Wähle eine andere."), "It carries the localized explanation")
	game.started = true
	release(session)

func run() -> void:
	game = GameProbe.new()
	root.add_child(game)
	game.hud = HudProbe.new()
	game.add_child(game.hud)
	game.audio = AudioProbe.new()
	game.add_child(game.audio)
	game.combat_events = CombatEvents.new()
	game.add_child(game.combat_events)
	game.combat_events.persistence_enabled = false
	test_decode_budgets()
	test_closed_envelopes()
	test_pending_peer()
	test_authenticated_flood()
	test_resync_budget()
	test_duplicate_character_notice()
	paused = false
	game.free()
	print("HOST BUDGET: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
