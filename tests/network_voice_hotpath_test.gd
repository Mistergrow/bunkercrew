extends SceneTree
## Voice routing uses authentic wire bytes and preserves negotiated identity rules.
const Protocol := preload("res://scripts/network_protocol.gd")
const Codec := preload("res://scripts/voice_codec.gd")

class RoutingProbe extends "res://scripts/network_session.gd":
	var packets: Array[Dictionary] = []
	var encoded_bindings: Array[bool] = []
	var refused_targets: Array[int] = []
	func _encode_voice_packet(message: Dictionary, binding: bool) -> PackedByteArray:
		encoded_bindings.append(binding)
		return super._encode_voice_packet(message, binding)
	func _send_encoded(data: PackedByteArray, reliable: bool, target_id: int = 0, channel: int = -1) -> bool:
		packets.append({"bytes":data, "message":Protocol.decode(data), "target":target_id, "reliable":reliable, "channel":channel})
		return target_id not in refused_targets
	func clear_capture() -> void:
		packets.clear()
		encoded_bindings.clear()
		refused_targets.clear()

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("VOICE HOTPATH ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1
		push_error(label)

func peer(binding: bool, authenticated := true) -> Dictionary:
	return {"_authenticated":authenticated, "voice_member_keys":binding}

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var network := RoutingProbe.new()
	network._voice_members = {"1":"a".repeat(48), "2":"b".repeat(48)}
	var samples := PackedFloat32Array()
	samples.resize(Codec.FRAMES)
	for index in Codec.FRAMES:
		samples[index] = sin(float(index) * .08) * .2
	var message := {"kind":"voice", "seq":17, "generation":3, "rate":Codec.RATE, "pcm":Codec.encode(samples), "player_id":1, "member_key":"c".repeat(48)}
	var original := message.duplicate(true)
	network._peers = {20:peer(true), 30:peer(true), 40:peer(true)}
	check(network._broadcast_voice(message), "Three modern recipients accept the actual broadcast")
	check(network.encoded_bindings == [true] and network.packets.size() == 3, "Three modern recipients share exactly one encoded identity-bound frame")
	for packet: Dictionary in network.packets:
		check(Codec.valid(packet.message) and packet.message.member_key == network._voice_members["1"], "Decoded modern voice carries the host-owned speaker identity")
		check(packet.message.pcm == message.pcm and packet.channel == 2 and not packet.reliable, "Actual PCM, unreliable voice channel and packet timing stay unchanged")
	check(network.packets[0].bytes == network.packets[1].bytes and network.packets[1].bytes == network.packets[2].bytes, "Recipients receive identical compressed bytes for the same variant")
	check(message == original, "Identity replacement never mutates the caller's envelope")
	network.clear_capture()
	network._peers = {20:peer(false), 30:peer(false), 40:peer(false)}
	check(network._broadcast_voice(message), "Existing clients still accept their original frame")
	check(network.encoded_bindings == [false] and network.packets.size() == 3, "Three legacy recipients share exactly one encoded unbound frame")
	check(network.packets.all(func(packet): return Codec.valid(packet.message) and packet.message.size() == 6 and not packet.message.has("member_key")), "The old six-field wire format remains exact for every legacy recipient")
	network.clear_capture()
	network._peers = {20:peer(false), 30:peer(true), 40:peer(true)}
	check(network._broadcast_voice(message), "Mixed negotiated recipients all accept voice")
	check(network.encoded_bindings == [false, true] and network.packets.size() == 3, "A mixed room encodes each of its two required variants only once")
	check(not network.packets[0].message.has("member_key") and network.packets[1].message.member_key == network._voice_members["1"], "Per-peer negotiated wire shape survives reuse")
	network.clear_capture()
	message.player_id = 2
	check(network._broadcast_voice(message, 20), "A guest speaker reaches the other authenticated participants")
	check(network.encoded_bindings == [true] and network.packets.size() == 2 and network.packets.all(func(packet): return packet.target != 20), "An excluded legacy sender cannot trigger an unused legacy encoding or echo")
	check(network.packets.all(func(packet): return packet.message.player_id == 2 and packet.message.member_key == network._voice_members["2"]), "Forwarded speech uses the original speaker's actual identity")
	network.clear_capture()
	network._peers = {20:peer(false), 30:peer(true, false), 40:peer(false, false)}
	check(not network._broadcast_voice(message, 20), "No authenticated destination reports a false transport success")
	check(network.encoded_bindings.is_empty() and network.packets.is_empty(), "Sender exclusion and authentication run before any encoding")
	network.clear_capture()
	network._peers.clear()
	check(network._broadcast_voice(message), "The existing no-peer legacy transport fallback stays available")
	check(network.encoded_bindings == [false] and network.packets.size() == 1 and network.packets[0].target == -1 and not network.packets[0].message.has("member_key"), "Fallback preserves its original target and six-field envelope")
	network.clear_capture()
	network._peers = {20:peer(true), 30:peer(true), 40:peer(true)}
	network.refused_targets.assign([20, 30, 40])
	check(not network._broadcast_voice(message), "Failed sends still return false after packet reuse")
	check(network.encoded_bindings == [true] and network.packets.size() == 3, "A failed send cannot trigger another encoding of the same variant")
	network.clear_capture()
	var forbidden := Node.new()
	var malformed := message.duplicate()
	malformed.unexpected_object = forbidden
	check(not network._broadcast_voice(malformed), "Native protocol safety still rejects an Object-bearing envelope")
	check(network.encoded_bindings == [true] and network.packets.is_empty(), "A rejected encoding is cached once without sending unsafe bytes")
	forbidden.free()
	check(message.player_id == 2 and message.member_key == original.member_key and message.pcm == original.pcm, "All routing cases retain the caller's identity token and speech data")
	network.free()
	print("VOICE HOTPATH: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
