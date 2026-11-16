extends SceneTree
## Real ENet on a private port: joining peers wait in spare slots, so a
## connection that never authenticates cannot block joins or reconnects.
const Transport := preload("res://scripts/network_transport.gd")
const PeerState := preload("res://scripts/network_peer_state.gd")
const PORT := 39857

class SessionProbe extends "res://scripts/network_session.gd":
	var rejections: Array[String] = []
	func _send(message: Dictionary, _reliable := true, _target_id: int=0) -> bool:
		if message.get("kind") == "reject": rejections.append(str(message.message))
		return true
	func _send_lobby() -> void:
		pass
class HudProbe extends Node:
	var overlay := ""
class GameProbe extends Node:
	var started := false
	var hud: HudProbe

var host: NetworkTransport
var guests: Array[NetworkTransport] = []
var left: Array[int] = []
var errors: Array[int] = []
var received: Dictionary = {}
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("ADMISSION PASS ", label)
	else:
		failures += 1
		push_error(label)

func pump_until(condition: Callable, timeout: float = 2.0) -> bool:
	var deadline := Time.get_ticks_usec() + roundi(timeout * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		if is_instance_valid(host): host._process(0)
		for guest in guests:
			if is_instance_valid(guest): guest._process(0)
		if condition.call(): return true
		await process_frame
	return condition.call()

func pump(seconds: float) -> void:
	var until := Time.get_ticks_usec() + roundi(seconds * 1000000.0)
	await pump_until(func(): return Time.get_ticks_usec() >= until, seconds + 0.2)

func join() -> NetworkTransport:
	var guest := Transport.new()
	root.add_child(guest)
	guest.set_process(false)
	guests.append(guest)
	check(guest.join("127.0.0.1", PORT) == OK, "A guest opens its own UDP connection")
	return guest

func wire(guest: NetworkTransport) -> int:
	return guest.peer.get_unique_id() if guest.peer != null and guest.peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED else 0

func linked() -> Array[NetworkTransport]:
	var result: Array[NetworkTransport] = []
	for guest in guests:
		if guest.peer != null and guest.connected_peer != 0 and host.remote_peers.has(wire(guest)): result.append(guest)
	return result

func test_transport() -> void:
	check(Transport.MAX_GUESTS == 3, "The authenticated player cap stays at three guests")
	check(Transport.MAX_PENDING_PER_ADDRESS >= Transport.MAX_GUESTS and Transport.MAX_PENDING_PEERS >= Transport.MAX_PENDING_PER_ADDRESS * 2, "A whole crew behind one address can join together, and one address cannot take every waiting slot")
	host = Transport.new()
	root.add_child(host)
	host.set_process(false)
	host.admission_control = true
	host.peer_left.connect(func(id: int, _reason: String): left.append(id))
	host.peer_error.connect(func(id: int, _message: String): errors.append(id))
	host.packet_from.connect(func(_data: PackedByteArray, sender: int): received[sender] = int(received.get(sender, 0)) + 1)
	check(host.host(PORT, false) == OK, "The host opens its private port with admission control")
	for index in Transport.MAX_PENDING_PER_ADDRESS + 2: join()
	check(await pump_until(func(): return host.pending_peer_count() == Transport.MAX_PENDING_PER_ADDRESS and host.refused_peers == 2), "One address holds at most three waiting slots; further connections are refused at once")
	await pump(0.3)
	var crew := linked()
	check(crew.size() == Transport.MAX_PENDING_PER_ADDRESS and host.admitted_peer_count() == 0, "The refused connections are released while the waiting ones stay linked")
	if crew.size() != 3:
		return
	for guest in crew: check(host.admit_peer(wire(guest)), "An authenticated handshake promotes the waiting peer to a player link")
	check(host.admitted_peer_count() == 3 and host.pending_peer_count() == 0, "Three admitted players occupy no waiting slot")
	var silent := join()
	var noisy := join()
	check(await pump_until(func(): return host.pending_peer_count() == 2 and silent.connected_peer != 0 and noisy.connected_peer != 0), "With a full crew, new connections still reach the handshake in spare slots")
	var silent_id := wire(silent)
	var noisy_id := wire(noisy)
	var joined_at := Time.get_ticks_usec()
	check(not host.admit_peer(silent_id) and host.admitted_peer_count() == 3 and host.pending_peer_count() == 2, "A fourth guest cannot be admitted: the player cap is unchanged")
	check(host.admit_peer(wire(crew[0])), "Admitting an existing player again is harmless")
	# A waiting peer has a small, never refilled allowance.
	for index in 9: noisy.send(PackedByteArray([index]))
	for index in 100: crew[0].send(PackedByteArray([index]))
	check(await pump_until(func(): return not host.remote_peers.has(noisy_id) and int(received.get(wire(crew[0]), 0)) == 100), "A waiting peer that floods is dropped while an admitted player's burst is delivered")
	check(int(received.get(noisy_id, 0)) == int(Transport.PENDING_PACKET_BURSTS[0]) and errors.has(noisy_id), "Only its small handshake allowance was ever dispatched")
	check(await pump_until(func(): return noisy.connected_peer == 0 or noisy.peer == null, 1.0), "Its native slot is released immediately, without waiting for an acknowledgement")
	# Stalled host frames are not the waiting peer's delay.
	host._pending_updated_usec -= 60000000
	host._expire_pending()
	check(host.remote_peers.has(silent_id) and host._pending.has(silent_id), "A blocked host frame does not expire a waiting peer")
	check(await pump_until(func(): return not host.remote_peers.has(silent_id), Transport.PENDING_SECONDS + 2.0), "A connection that never authenticates is dropped")
	var held := float(Time.get_ticks_usec() - joined_at) / 1000000.0
	check(held >= Transport.PENDING_SECONDS - Transport.PENDING_STALL - 0.6 and held <= Transport.PENDING_SECONDS + 1.5, "It held its slot for about four seconds (%.2f s)" % held)
	check(await pump_until(func(): return left.has(silent_id) and left.has(noisy_id), 1.0), "The session is told that both waiting links are gone")
	check(host.admitted_peer_count() == 3 and linked().size() == 3 and host.pending_peer_count() == 0, "The three players are untouched")
	# The freed slots are immediately usable again.
	var before := host.refused_peers
	for index in Transport.MAX_PENDING_PER_ADDRESS: join()
	check(await pump_until(func(): return host.pending_peer_count() == Transport.MAX_PENDING_PER_ADDRESS) and host.refused_peers == before, "Released waiting slots accept the next joiners")
	for id in host._pending.keys(): host.disconnect_guest(int(id))
	check(host.pending_peer_count() == 0 and host.admitted_peer_count() == 3, "Rejecting a waiting peer frees its slot at once")
	# Every waiting slot taken by other addresses: nobody else may enter.
	for index in Transport.MAX_PENDING_PEERS: host._pending[900000 + index] = {"address":"10.0.0.%d" % index, "age":0.0}
	before = host.refused_peers
	var late_id := wire(join())
	check(await pump_until(func(): return host.refused_peers == before + 1) and late_id != 0 and not host.remote_peers.has(late_id), "The total number of waiting peers is bounded as well")
	for index in Transport.MAX_PENDING_PEERS: host._pending.erase(900000 + index)

func release_transport() -> void:
	for guest in guests:
		if is_instance_valid(guest):
			guest.close()
			guest.free()
	guests.clear()
	if is_instance_valid(host):
		host.close()
		host.free()
	host = null

func stalled(session: SessionProbe, seconds: float) -> void:
	session._clock_updated_usec -= roundi(seconds * 1000000.0)
	session._process(0.016)

func test_session_deadline() -> void:
	check(PeerState.HANDSHAKE_SECONDS <= 3.0 and PeerState.HANDSHAKE_SECONDS < Transport.PENDING_SECONDS, "An unanswered handshake is rejected with a reason before the transport's hard limit")
	var game := GameProbe.new()
	root.add_child(game)
	game.hud = HudProbe.new()
	game.add_child(game.hud)
	var session := SessionProbe.new()
	session.game = game
	game.add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	session.active = true
	session.is_host = true
	session.state = "lobby"
	session._process(0.016)
	session._peer_connected_id(7)
	check(session._peers.has(7) and is_equal_approx(float(session._peers[7]._handshake_deadline), session._clock + PeerState.HANDSHAKE_SECONDS), "A new link gets the short handshake window")
	for frame in 29: stalled(session, 0.1)
	check(not session._peers[7]._rejecting and session.rejections.is_empty(), "A link is not rejected before its window ends")
	for frame in 3: stalled(session, 0.1)
	check(session._peers[7]._rejecting and session.rejections.size() == 1, "An unanswered link is rejected after three seconds")
	session._peer_connected_id(8)
	stalled(session, 10.0)
	check(not session._peers[8]._rejecting, "A blocked host frame does not use up the peer's handshake window")
	for frame in 29: stalled(session, 0.1)
	check(not session._peers[8]._rejecting, "After the stall the peer still has its whole window")
	for frame in 3: stalled(session, 0.1)
	check(session._peers[8]._rejecting and session.rejections.size() == 2, "The window then ends as usual")
	session.leave(false)
	paused = false
	game.free()

func run() -> void:
	await test_transport()
	release_transport()
	test_session_deadline()
	print("ADMISSION: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
