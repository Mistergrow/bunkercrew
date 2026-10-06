extends SceneTree
## Actual loopback UDP with ephemeral fixture ports, never the user's game port.

const Discovery := preload("res://scripts/network_lan_discovery.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const SECRET := "23456789ABCDEFGH"
const OTHER_SECRET := "ABCDEFGHJKLMNPQR"
const GAME_PORT := 39871
var checks := 0
var failures := 0
var completed_tests := 0
var nodes: Array[Node] = []
var sockets: Array[PacketPeerUDP] = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition: print("PASS ", label)
	else:
		failures += 1
		push_error(label)

func new_discovery(port: int):
	var node = Discovery.new()
	node.discovery_port = port
	node.bind_address = "127.0.0.1"
	node.discovery_targets.assign(["127.0.0.1"])
	nodes.append(node)
	root.add_child(node)
	return node

func new_socket(port: int = 0) -> PacketPeerUDP:
	var socket := PacketPeerUDP.new()
	var result := socket.bind(port, "127.0.0.1", 65536)
	check(result == OK, "Fixture binds an isolated loopback UDP socket")
	sockets.append(socket)
	return socket

func available_port() -> int:
	var socket := new_socket()
	var port := socket.get_local_port()
	socket.close()
	check(port not in [24777, 24778], "Fixture leaves the game and production discovery ports alone")
	return port

func cleanup() -> void:
	paused = false
	for node in nodes: node.close()
	for socket in sockets: socket.close()
	sockets.clear()
	for node in nodes: await Cleanup.free_scene(node, self)
	nodes.clear()

func wait_until(condition: Callable, seconds: float = 1.0) -> bool:
	var until := Time.get_ticks_usec() + roundi(seconds * 1000000.0)
	while Time.get_ticks_usec() < until:
		if condition.call(): return true
		await process_frame
	return condition.call()

func wait_seconds(seconds: float) -> void:
	var until := Time.get_ticks_usec() + roundi(seconds * 1000000.0)
	await wait_until(func(): return Time.get_ticks_usec() >= until, seconds + 0.1)

func wire(operation: String, nonce: String, game_port: int = 0, secret: String = SECRET) -> Dictionary:
	# Independent fixture producer using the documented wire string; none of the
	# discovery node's encoders or authentication helpers are called here.
	var signed := "bunkercrew-lan-2\n" + operation + "\n" + nonce
	if operation == "found": signed += "\n" + str(game_port)
	var proof := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, secret.to_ascii_buffer(), signed.to_ascii_buffer()).hex_encode()
	var message := {"v":2, "op":operation, "nonce":nonce, "proof":proof}
	if operation == "found": message.port = game_port
	return message

func send(socket: PacketPeerUDP, destination: int, packet: PackedByteArray) -> void:
	check(socket.set_dest_address("127.0.0.1", destination) == OK and socket.put_packet(packet) == OK, "Fixture sends an actual UDP datagram")

func send_json(socket: PacketPeerUDP, destination: int, message: Dictionary) -> void:
	send(socket, destination, JSON.stringify(message).to_utf8_buffer())

func drain(socket: PacketPeerUDP) -> Array[Dictionary]:
	var packets: Array[Dictionary] = []
	while socket.get_available_packet_count() > 0:
		var packet := socket.get_packet()
		packets.append({"data":packet, "address":socket.get_packet_ip(), "port":socket.get_packet_port()})
	return packets

func test_inputs_and_loopback() -> void:
	var port := available_port()
	var host_node = new_discovery(port)
	var guest = new_discovery(port)
	var errors: Array[String] = []
	var results: Array[Dictionary] = []
	host_node.failed.connect(func(message: String): errors.append(message))
	guest.found.connect(func(address: String, game_port: int): results.append({"address":address,"port":game_port}))
	for invalid in ["", "ABCDEFG", "ABCDEFGHI", "OOOOOOOO", "abcdefgh"]:
		check(host_node.host(invalid, GAME_PORT) == ERR_INVALID_PARAMETER and host_node._sockets.is_empty(), "Malformed invitation cannot open a host socket")
	check(host_node.host(SECRET, 0) == ERR_INVALID_PARAMETER, "Invalid advertised game ports cannot be hosted")
	check(host_node.host(SECRET, GAME_PORT) == OK, "Host listens on the explicitly configured discovery port")
	check(host_node.process_mode == Node.PROCESS_MODE_ALWAYS and guest.process_mode == Node.PROCESS_MODE_ALWAYS, "Discovery continues in the paused lobby")
	paused = true
	check(guest.discover(SECRET) == OK, "A matching guest starts discovery while the tree is paused")
	check(await wait_until(func(): return results.size() == 1), "Real UDP discovers the host while the tree is paused")
	check(results.size() == 1 and results[0] == {"address":"127.0.0.1","port":GAME_PORT}, "Discovery returns the packet source and authenticated game port")
	check(guest._sockets.is_empty() and guest._secret.is_empty() and host_node.sent_responses == 1, "Success clears guest sockets and secrets and emits once")
	paused = false
	host_node.close()
	var reused := new_socket(port)
	check(reused.is_bound(), "Closing the host immediately releases its UDP port")
	await cleanup()
	completed_tests += 1

func test_bad_requests() -> void:
	var port := available_port()
	var host_node = new_discovery(port)
	var sender := new_socket()
	check(host_node.host(SECRET, GAME_PORT) == OK, "Malformed-request fixture opens a host")
	var nonce := "0123456789abcdef0123456789abcdef"
	var valid := wire("find", nonce)
	var bad_nonce := valid.duplicate()
	bad_nonce.nonce = "not-a-nonce"
	var extra := valid.duplicate()
	extra.address = "1.1.1.1"
	var duplicate := JSON.stringify(valid).replace('"v":2', '"v":2,"v":2')
	var large := PackedByteArray()
	large.resize(Discovery.MAX_PACKET_BYTES + 1)
	large.fill(65)
	var malformed: Array[PackedByteArray] = [
		"not json".to_ascii_buffer(), "[1,2]".to_ascii_buffer(),
		var_to_bytes(valid), large, duplicate.to_ascii_buffer(),
		JSON.stringify(bad_nonce).to_ascii_buffer(), JSON.stringify(extra).to_ascii_buffer(),
		JSON.stringify(wire("find", nonce, 0, OTHER_SECRET)).to_ascii_buffer(),
	]
	for packet in malformed: send(sender, port, packet)
	await wait_seconds(0.08)
	check(sender.get_available_packet_count() == 0 and host_node.sent_responses == 0, "Malformed, oversized, duplicate-key and wrong-code requests receive no response")
	check(host_node.rejected_packets == malformed.size(), "Every malformed request is consumed and rejected")
	send_json(sender, port, valid)
	check(await wait_until(func(): return sender.get_available_packet_count() > 0), "The host still answers a valid invitation after rejected packets")
	var replies := drain(sender)
	var reply: Dictionary = JSON.parse_string(replies[0].data.get_string_from_ascii()) if not replies.is_empty() else {}
	check(not reply.is_empty() and replies[0].data == JSON.stringify(wire("found", nonce, GAME_PORT)).to_ascii_buffer() and replies[0].port == port, "Host reply contains the nonce and independent HMAC proof for its game port")
	check(not replies[0].data.get_string_from_ascii().contains(SECRET), "The host never sends the invitation secret in plaintext")
	await cleanup()
	completed_tests += 1

func test_spoofed_replies_and_replay() -> void:
	var fake_host := new_socket()
	var port := fake_host.get_local_port()
	var guest = new_discovery(port)
	var results: Array[Dictionary] = []
	guest.found.connect(func(address: String, game_port: int): results.append({"address":address,"port":game_port}))
	check(guest.discover(SECRET) == OK, "Guest sends to an isolated discovery endpoint")
	check(await wait_until(func(): return fake_host.get_available_packet_count() > 0), "Independent host sees the actual discovery request")
	var initial := drain(fake_host)[0]
	var request: Dictionary = JSON.parse_string(initial.data.get_string_from_ascii())
	var guest_port: int = initial.port
	check(initial.data == JSON.stringify(wire("find", request.nonce)).to_ascii_buffer() and not initial.data.get_string_from_ascii().contains(SECRET), "The broadcast protocol proves knowledge without broadcasting the invitation")
	var valid := wire("found", request.nonce, GAME_PORT)
	var claimed_address := valid.duplicate()
	claimed_address.address = "93.184.216.34"
	var fractional := valid.duplicate()
	fractional.port = 39871.5
	var bad_version := valid.duplicate()
	bad_version.v = 1
	for message in [
		wire("found", "ffffffffffffffffffffffffffffffff", GAME_PORT),
		wire("found", request.nonce, GAME_PORT, OTHER_SECRET),
		wire("found", request.nonce, 0), wire("found", request.nonce, 65536),
		claimed_address, fractional, bad_version,
	]: send_json(fake_host, guest_port, message)
	var wrong_socket := new_socket()
	send_json(wrong_socket, guest_port, valid)
	await wait_seconds(0.08)
	check(results.is_empty() and guest.rejected_packets == 8, "Wrong nonce, HMAC, source port, version, game port and claimed address cannot resolve a guest")
	guest.close()
	check(guest.discover(SECRET) == OK, "The same guest can start a fresh discovery after close")
	check(await wait_until(func(): return fake_host.get_available_packet_count() > 0), "Fresh discovery reaches the independent host")
	var fresh := drain(fake_host)[0]
	var new_request: Dictionary = JSON.parse_string(fresh.data.get_string_from_ascii())
	check(new_request.nonce != request.nonce, "Each discovery has a fresh unpredictable nonce")
	send_json(fake_host, fresh.port, valid)
	await wait_seconds(0.04)
	check(results.is_empty(), "A signed response from a closed discovery cannot resolve the next one")
	send_json(fake_host, fresh.port, wire("found", new_request.nonce, GAME_PORT))
	check(await wait_until(func(): return results.size() == 1), "A correctly authenticated current response resolves once")
	check(results.size() == 1 and results[0] == {"address":"127.0.0.1","port":GAME_PORT}, "Resolved address is the actual UDP sender with the authenticated game port")
	await cleanup()
	completed_tests += 1

func test_rate_and_frame_limits() -> void:
	var port := available_port()
	var host_node = new_discovery(port)
	var first := new_socket()
	var second := new_socket()
	check(host_node.host(SECRET, GAME_PORT) == OK, "Rate fixture opens the host")
	host_node.set_process(false)
	var request := JSON.stringify(wire("find", "0123456789abcdef0123456789abcdef")).to_ascii_buffer()
	first.set_dest_address("127.0.0.1", port)
	second.set_dest_address("127.0.0.1", port)
	for index in 48:
		var sender := first if index % 2 == 0 else second
		sender.put_packet(request)
	await wait_seconds(0.02)
	host_node._process(0)
	check(host_node.last_poll_packets == Discovery.MAX_PACKETS_PER_FRAME, "One frame consumes at most sixteen queued packets")
	check(host_node.sent_responses == int(Discovery.RESPONSE_BURST), "Authenticated senders share a global response burst limit")
	for index in 4: host_node._process(0)
	await wait_seconds(0.02)
	check(drain(first).size() + drain(second).size() == int(Discovery.RESPONSE_BURST), "Changing sender sockets cannot bypass the global response cap")
	check(host_node.rejected_packets >= 32, "The global input budget bounds JSON/HMAC work across frames")
	await wait_seconds(0.55)
	first.put_packet(request)
	await wait_seconds(0.02)
	host_node._process(0)
	check(host_node.sent_responses == int(Discovery.RESPONSE_BURST) + 1, "Response capacity recovers using elapsed monotonic time")
	await cleanup()
	completed_tests += 1

func test_timeout_retries_and_close() -> void:
	var endpoint := new_socket()
	var guest = new_discovery(endpoint.get_local_port())
	guest.timeout_seconds = 0.24
	var errors: Array[String] = []
	guest.failed.connect(func(reason: String): errors.append(reason))
	check(guest.discover(SECRET) == OK, "Timeout fixture begins without a responding host")
	check(await wait_until(func(): return errors.size() == 1), "Unanswered discovery emits a bounded timeout")
	var requests := drain(endpoint)
	check(requests.size() == 1 + Discovery.MAX_RETRIES and guest.sent_requests == requests.size(), "Discovery sends an initial query plus exactly three retries")
	check(errors[0] == Discovery.TIMED_OUT and guest._sockets.is_empty() and guest._secret.is_empty(), "Timeout clears sockets and invitation material with an actionable error")
	await wait_seconds(0.08)
	check(errors.size() == 1, "Timeout is emitted once")
	errors.clear()
	check(guest.discover(OTHER_SECRET) == OK, "The node is reusable after timeout")
	guest.close()
	await wait_seconds(0.3)
	check(errors.is_empty() and guest._sockets.is_empty(), "Closing cancels pending retries and timeout callbacks")
	check(drain(endpoint).size() == 1, "A closed discovery sends no later retries")
	await cleanup()
	completed_tests += 1

func run() -> void:
	await test_inputs_and_loopback()
	await test_bad_requests()
	await test_spoofed_replies_and_replay()
	await test_rate_and_frame_limits()
	await test_timeout_retries_and_close()
	check(completed_tests == 5, "Every test case reaches its final checks")
	print("LAN discovery: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
