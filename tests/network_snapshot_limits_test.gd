extends SceneTree
## The host checks an outgoing world against the same limits its guests
## enforce while decoding, and reports an oversized world instead of sending it.
const Protocol := preload("res://scripts/network_protocol.gd")
const Guard := preload("res://scripts/network_variant_guard.gd")
const Messages := preload("res://scripts/network_messages.gd")
const Schema := preload("res://scripts/network_replication_schema.gd")
const World := preload("res://scripts/network_world.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")

class SessionProbe extends "res://scripts/network_session.gd":
	var sent: Array[Dictionary] = []
	func _send_encoded(packet: PackedByteArray, _reliable: bool, _target_id: int=0, _channel: int=-1) -> bool:
		sent.append(Protocol.decode(packet))
		return true
	func kinds(kind: String) -> int:
		return sent.filter(func(message: Dictionary): return message.get("kind") == kind).size()
class WorldProbe extends RefCounted:
	var entities := 0
	func capture() -> Dictionary:
		var records: Array = []
		for index in entities: records.append({"id":"dynamic:%d" % (index + 1)})
		return {"version":Schema.VERSION, "entities":records}
class AudioProbe extends Node:
	var live_music: Node
class GameProbe extends Node:
	var started := true
	var audio: AudioProbe
	var combat_events: CombatEvents
	var notices: Array[String] = []
	func notify(message: String) -> void: notices.append(message)

var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("SNAPSHOT LIMITS PASS ", label)
	else:
		failures += 1
		push_error(label)

func sized(nodes: int) -> Dictionary:
	# Root, "kind" and its value, "d" and its outer array are five values.
	var rows: Array = []
	var remaining := nodes - 5
	while remaining > 0:
		var row: Array = []
		row.resize(mini(remaining - 1, Guard.MAX_ARRAY))
		row.fill(0)
		rows.append(row)
		remaining -= row.size() + 1
	return {"kind":"snapshot", "d":rows}

func nested(depth: int) -> Dictionary:
	var value: Array = [0]
	for level in depth - 2: value = [value]
	return {"kind":"snapshot", "d":value}

func agrees(message: Dictionary, accepted: bool, expected_error: String, label: String) -> void:
	# One verdict from the sender's preflight and from the receiver's decoder.
	var bounded := Protocol.encode_bounded(message)
	var trusted := Protocol.encode_trusted(message)
	check(bounded.error == expected_error and bounded.packet.is_empty() != accepted, "Sender preflight: " + label)
	check(not trusted.is_empty() and Protocol.decode(trusted).is_empty() != accepted, "Receiver decoder: " + label)

func counted(value: Dictionary, label: String) -> void:
	var nodes := Protocol.wire_nodes(value)
	var raw := var_to_bytes(value)
	check(nodes > 0 and Guard.new().validate(raw, nodes) and not Guard.new().validate(raw, nodes - 1), "The byte-level guard counts exactly as the sender does: " + label)
	check(Protocol._safe_value(value, 0, [nodes]) and not Protocol._safe_value(value, 0, [nodes - 1]), "The decoded-value audit counts exactly as the sender does: " + label)

func test_shared_limits() -> void:
	counted({"kind":"x"}, "smallest envelope")
	counted({"kind":"x", "a":[1, 2.5, "s", null, true, Vector2(1, 2), Vector2i(3, 4), Rect2(0, 0, 1, 1), Color.RED], "b":{Vector2i.LEFT:true, "n":{"deep":[[], {}, [[1]]]}}, "c":PackedByteArray([1, 2, 3]), "d":PackedInt32Array([1, 2, 3]), "e":PackedVector2Array([Vector2.ONE, Vector2.ZERO]), "f":PackedStringArray(["a", "b"]), "g":PackedFloat32Array([0.5])}, "every container form")
	agrees(sized(Guard.MAX_NODES), true, "", "exactly the value limit is sent and accepted")
	agrees(sized(Guard.MAX_NODES + 1), false, "nodes", "one value more is withheld and would be refused")
	var entries := {}
	for index in Guard.MAX_DICTIONARY: entries[index] = 0
	agrees({"kind":"snapshot", "d":entries}, true, "", "a dictionary at its size limit")
	entries[Guard.MAX_DICTIONARY] = 0
	agrees({"kind":"snapshot", "d":entries}, false, "containers", "a dictionary one entry over")
	var items: Array = []
	items.resize(Guard.MAX_ARRAY)
	items.fill(0)
	agrees({"kind":"snapshot", "d":items}, true, "", "an array at its size limit")
	items.append(0)
	agrees({"kind":"snapshot", "d":items}, false, "containers", "an array one element over")
	var packed := PackedInt32Array()
	packed.resize(Guard.MAX_ARRAY)
	agrees({"kind":"snapshot", "d":packed}, true, "", "a packed array at its size limit")
	packed.append(0)
	agrees({"kind":"snapshot", "d":packed}, false, "containers", "a packed array one element over")
	agrees(nested(Guard.MAX_DEPTH), true, "", "nesting at the depth limit")
	agrees(nested(Guard.MAX_DEPTH + 1), false, "containers", "nesting one level deeper")
	var blob := PackedByteArray()
	blob.resize(Protocol.MAX_DECODED)
	var too_many_bytes := Protocol.encode_bounded({"kind":"snapshot", "d":blob})
	check(too_many_bytes.error == "bytes" and too_many_bytes.packet.is_empty() and Protocol.encode_trusted({"kind":"snapshot", "d":blob}).is_empty(), "A world above the decoded-size limit is withheld")
	var noise := Crypto.new().generate_random_bytes(Protocol.MAX_PACKET + 1024)
	var too_large := Protocol.encode_bounded({"kind":"snapshot", "d":noise})
	check(too_large.error == "packet" and too_large.packet.is_empty(), "A world that does not compress into one packet is withheld")
	var protocol_source := FileAccess.get_file_as_string("res://scripts/network_protocol.gd")
	for limit in ["MAX_NODES", "MAX_DICTIONARY", "MAX_ARRAY", "MAX_DEPTH"]:
		check(protocol_source.contains("VariantGuard." + limit) and not protocol_source.contains("const " + limit), "The protocol uses the guard's %s instead of declaring its own" % limit)
	check(FileAccess.get_file_as_string("res://scripts/network_session.gd").contains("WorldSchema.MAX_ENTITIES") and FileAccess.get_file_as_string("res://scripts/network_world.gd").contains("Schema.MAX_ENTITIES"), "Sender and receiver read the entity limit from the replication schema")
	check(Schema.MAX_ENTITIES <= Guard.MAX_ARRAY and Schema.MAX_BYTES <= Protocol.MAX_DECODED, "The schema limits lie within the wire limits")

func test_session_report() -> void:
	var game := GameProbe.new()
	root.add_child(game)
	game.audio = AudioProbe.new()
	game.add_child(game.audio)
	game.combat_events = CombatEvents.new()
	game.add_child(game.combat_events)
	game.combat_events.persistence_enabled = false
	var session := SessionProbe.new()
	session.game = game
	game.add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	session.active = true
	session.is_host = true
	session.state = "playing"
	session.peer_connected = true
	session._authenticated = true
	session._generation = 2
	var link: Dictionary = preload("res://scripts/network_peer_state.gd").create(0.0)
	link.slot = 2
	link.wire = 2
	link._authenticated = true
	link._ready_for_snapshots = true
	session._slots[2] = link
	session._peers[2] = link
	var world := WorldProbe.new()
	session.world = world
	world.entities = Schema.MAX_ENTITIES
	session._send_snapshot_batch()
	check(session.kinds("snapshot") == 1 and session.sent_snapshots == 1 and session.connection_hint.is_empty(), "A world at the entity limit is sent")
	check(Messages.valid(session.sent[0], false) and session.sent[0].world.entities.size() == Schema.MAX_ENTITIES, "Guests decode and accept that envelope")
	world.entities = Schema.MAX_ENTITIES + 1
	session._peers[2]._snapshot_ack = session._peers[2]._snapshot_seq
	session.sent.clear()
	session._send_snapshot_batch()
	check(session.kinds("snapshot") == 0 and session.sent_snapshots == 1, "One entity more is withheld instead of failing on every guest")
	var expected := LocaleText.text(session.SNAPSHOT_LIMIT_MESSAGE)
	check(session.connection_hint == expected and game.notices.size() == 1 and game.notices[0] == expected and session._snapshot_limit == "entities", "The host is told why the crew's world stands still")
	var notices := session.sent.filter(func(message: Dictionary): return message.get("kind") == "notice")
	check(notices.size() == 1 and Messages.valid(notices[0], false) and LocaleText.message_text(notices[0].message) == expected, "The crew receives the same explanation in their own language")
	for index in 10: session._send_snapshot_batch()
	session._enter_peer(2)
	session._send_snapshot(true)
	session._leave_peer()
	check(session.sent.size() == 1 and game.notices.size() == 1, "The report is not repeated for every withheld snapshot, including a reliable one")
	session._clock += 5.1
	session._send_snapshot_batch()
	check(game.notices.size() == 2 and session.kinds("notice") == 2, "It is repeated while the condition lasts")
	world.entities = 12
	session._send_snapshot_batch()
	check(session.kinds("snapshot") == 1 and session.connection_hint.is_empty() and session._snapshot_limit.is_empty(), "Snapshots resume and the notice clears once the world fits again")
	session.leave(false)
	paused = false
	game.free()

func test_real_world() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	game.start_scenario(4, {"environment":"ash_foundry", "build_type":"bastion", "position":"left"})
	game.rounds.set_process(false)
	for index in 12:
		var enemy = game._entity("enemy", Vector2(1000 + index * 12, 430), {"kind":"strider", "wave":16})
		enemy.set_physics_process(false)
	var world := World.new()
	world.bind(game)
	var message := {"kind":"snapshot", "seq":1, "generation":1, "paused":false, "world":world.capture(), "achievements":[]}
	counted(message, "a real four-player world")
	var bounded := Protocol.encode_bounded(message)
	check(bounded.error.is_empty() and bounded.packet == Protocol.encode_trusted(message), "The preflight sends a real world byte-for-byte as before")
	check(Protocol.decode(bounded.packet) == message, "Guests decode the checked snapshot unchanged")
	print("SNAPSHOT LIMITS real world: %d entities, %d of %d values, %d of %d decoded bytes" % [message.world.entities.size(), Protocol.wire_nodes(message), Guard.MAX_NODES, var_to_bytes(message).size(), Protocol.MAX_DECODED])
	paused = false
	check(await Cleanup.free_scene(game, self), "The real world fixture releases its scene and audio handles")

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	test_shared_limits()
	test_session_report()
	await test_real_world()
	print("SNAPSHOT LIMITS: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
