extends SceneTree
## Actual UDP sockets, isolated from the game's default 24777 port.
const Transport := preload("res://scripts/network_transport.gd")
const Protocol := preload("res://scripts/network_protocol.gd")
var host_node: NetworkTransport
var guest_node: NetworkTransport
var port := 39847
var checks := 0
var failures := 0
var received: Array[Dictionary] = []
var errors: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ", label)
	else:
		failures += 1
		push_error(label)

func pump_until(condition: Callable, timeout: float = 2.0) -> bool:
	var deadline := Time.get_ticks_usec() + roundi(timeout * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		if is_instance_valid(host_node): host_node._process(0)
		if is_instance_valid(guest_node): guest_node._process(0)
		if condition.call(): return true
		await process_frame
	return false

func setup_pair() -> bool:
	host_node = Transport.new()
	guest_node = Transport.new()
	root.add_child(host_node)
	root.add_child(guest_node)
	host_node.set_process(false)
	guest_node.set_process(false)
	host_node.packet.connect(func(data: PackedByteArray): received.append({"channel":host_node.last_packet_channel, "data":data}))
	host_node.error.connect(func(message: String): errors.append(message))
	host_node.peer_error.connect(func(_id: int,message: String): errors.append(message))
	guest_node.error.connect(func(message: String): errors.append(message))
	var result := host_node.host(port, false)
	if result != OK: return false
	if guest_node.join("127.0.0.1", port) != OK: return false
	return await pump_until(func(): return host_node.connected_peer != 0 and guest_node.connected_peer != 0)

func release_pair() -> void:
	for node in [host_node, guest_node]:
		if is_instance_valid(node):
			node.close()
			node.free()
	host_node = null
	guest_node = null
	received.clear()
	errors.clear()

func run() -> void:
	var configured := OS.get_environment("LASTSHIFT_HARDENING_PORT")
	if configured.is_valid_int(): port = configured.to_int()
	check(port != 24777, "Fixture uses its own UDP port")
	var budget := Transport.new()
	budget._reset_budgets()
	var catchup_ok := true
	for frame in 120:
		catchup_ok = budget._accept_packet(0, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 300) and catchup_ok
	check(catchup_ok, "Two seconds of normal 60-Hz reliable input fit the finite native catch-up allowance")
	var headroom := int(Transport.PACKET_BURSTS[0]) - 120
	for control in headroom:
		catchup_ok = budget._accept_packet(0, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 300) and catchup_ok
	check(catchup_ok and not budget._accept_packet(0, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 300), "Catch-up control headroom is finite and one excess reliable packet is rejected")
	budget._reset_budgets()
	for packet in int(Transport.PACKET_BURSTS[0]): budget._accept_packet(0, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 300)
	budget._refill_budgets(budget._budget_updated_usec + 500000)
	var refill_ok := true
	for packet in 32:
		refill_ok = budget._accept_packet(0, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 300) and refill_ok
	check(refill_ok and not budget._accept_packet(0, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 300), "Reliable allowance still refills at 64 packets per second after the burst")
	budget._reset_budgets()
	var voice_ok := true
	for index in int(Transport.PACKET_BURSTS[2]): voice_ok = budget._accept_packet(2, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, 800) and voice_ok
	check(voice_ok and not budget._accept_packet(2, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, 800), "Voice packet burst is bounded before a game decoder runs")
	check(budget._accept_packet(1, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, 300) and budget._accept_packet(0, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 300), "Voice budget exhaustion preserves independent input/control budgets")
	budget._refill_budgets(budget._budget_updated_usec + 1000000)
	check(budget._accept_packet(2, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, 1200), "Voice budget refills using monotonic elapsed time")
	check(not budget._accept_packet(2, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, 1201), "Oversized voice cannot cause reliable fragmentation")
	check(not budget._accept_packet(2, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 640), "Reliable payloads cannot masquerade as voice packets")
	check(not budget._accept_packet(1, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 20) and not budget._accept_packet(3, 0, 20), "Invalid channel/mode combinations are rejected")
	budget._reset_budgets()
	var bytes_ok := true
	for index in 4: bytes_ok = budget._accept_packet(0, MultiplayerPeer.TRANSFER_MODE_RELIABLE, Transport.MAX_PACKET_BYTES) and bytes_ok
	check(bytes_ok and not budget._accept_packet(0, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 1), "Reliable bytes have a bound independent of packet count")
	check(not Transport._valid_join_address("0.0.0.0") and not Transport._valid_join_address("224.0.0.1") and not Transport._valid_join_address("::") and not Transport._valid_join_address("ff02::1"), "Wildcard and multicast addresses cannot be used as a host invitation")
	check(Transport._valid_join_address("127.0.0.1") and Transport._valid_join_address("192.168.1.4") and Transport._valid_join_address("::1"), "Loopback and private unicast addresses remain available for LAN diagnostics")
	budget.free()
	check(await setup_pair(), "Two actual UDP peers connect on the isolated test port")
	if host_node.connected_peer == 0:
		release_pair()
		quit(1)
		return
	check(host_node.can_send_to() and guest_node.can_send_to(), "Transition readiness recognizes both actual open UDP channels")
	check(not host_node.can_send_to(999999), "Transition readiness rejects an unknown peer before any world mutation")
	check(guest_node.send(PackedByteArray([10])) == OK and guest_node.send(PackedByteArray([11]), false) == OK and guest_node.send(PackedByteArray([12]), false, 2) == OK, "The backward-compatible API sends on all three independent channels")
	check(await pump_until(func(): return received.size() == 3), "Actual ENet delivers control, input and voice")
	var channels: Array = received.map(func(item: Dictionary): return item.channel)
	check(channels.has(0) and channels.has(1) and channels.has(2), "Actual incoming channels retain their class identity")
	check(host_node.peer.host.get_max_channels() == Transport.CHANNEL_COUNT + 2, "The native host bounds channel negotiation including Godot's two reserved channels")
	# Wait past ENet's bandwidth negotiation interval: an immediate packet echo
	# misses Godot 4.7's create_server argument bug, which throttles the client
	# to five bytes/second only once the advertised bandwidth takes effect.
	var warmup_until := Time.get_ticks_usec() + 1200000
	await pump_until(func(): return Time.get_ticks_usec() >= warmup_until)
	received.clear()
	var guest_voice: Array[int] = []
	var guest_handler := func(data: PackedByteArray):
		if guest_node.last_packet_channel == 2: guest_voice.append(data[0])
	guest_node.packet.connect(guest_handler)
	var sent_ok := true
	for sequence in 50:
		var pcm := PackedByteArray()
		pcm.resize(640)
		pcm[0] = sequence
		sent_ok = host_node.send(pcm, false, 2) == OK and sent_ok
		sent_ok = guest_node.send(pcm, false, 2) == OK and sent_ok
		var next_frame := Time.get_ticks_usec() + 20000
		await pump_until(func(): return Time.get_ticks_usec() >= next_frame)
	await pump_until(func(): return received.size() == 50 and guest_voice.size() == 50)
	check(sent_ok, "Both actual UDP peers queue sustained 50-Hz PCM-sized voice frames")
	check(received.size() == 50 and guest_voice.size() == 50, "Sustained voice reaches both directions after ENet bandwidth negotiation")
	var order_ok := received.size() == 50 and guest_voice.size() == 50
	for sequence in mini(received.size(), guest_voice.size()):
		order_ok = received[sequence].data[0] == sequence and guest_voice[sequence] == sequence and order_ok
	check(order_ok, "The local sustained fixture preserves every exact voice payload")
	guest_node.packet.disconnect(guest_handler)
	var oversized := PackedByteArray()
	oversized.resize(1201)
	check(guest_node.send(oversized, false, 2) == ERR_INVALID_PARAMETER and guest_node.send(PackedByteArray([1]), true, 2) == ERR_INVALID_PARAMETER, "Sender rejects oversized/reliable voice before native ENet queuing")
	check(guest_node.send(PackedByteArray([1]), true, 1) == ERR_INVALID_PARAMETER and guest_node.send(PackedByteArray([1]), false, 0) == ERR_INVALID_PARAMETER, "Explicit overrides cannot contradict channel reliability")
	check(host_node.diagnostics().protocol == "UDP/ENet" and host_node.diagnostics().connected and host_node._active_job == null, "Diagnostics report actual UDP state without claiming public reachability or opening the router")
	received.clear()
	host_node._reset_budgets()
	var catchup_sent := true
	for frame in 120:
		var input := Protocol.encode({"kind": "input", "generation": 1, "seq": frame + 1,
			"input": {"held": {}, "pressed": ["cycle_weapon"], "released": [], "aim": [1500, 390], "mouse": true}})
		catchup_sent = guest_node.send(input) == OK and catchup_sent
	guest_node.peer.host.flush()
	await create_timer(.03).timeout
	host_node.peer.poll()
	check(catchup_sent and host_node.peer.get_available_packet_count() == 120, "Actual ENet receives the complete 120-frame normal reliable catch-up batch")
	host_node._process(0)
	check(host_node.last_poll_packets <= Transport.MAX_POLL_PACKETS and received.size() <= Transport.MAX_POLL_PACKETS, "A normal catch-up batch dispatches only the fixed per-poll budget")
	var drained := await pump_until(func(): return received.size() == 120)
	var catchup_order := drained
	for frame in received.size():
		var decoded := Protocol.decode(received[frame].data)
		catchup_order = decoded.get("kind", "") == "input" and decoded.get("seq", -1) == frame + 1 and received[frame].channel == 0 and catchup_order
	check(catchup_order and errors.is_empty() and host_node.connected_peer != 0 and not host_node._disconnecting, "Every exact normal catch-up input drains in order without a native rate-limit disconnect")
	received.clear()
	host_node._reset_budgets()
	for index in 48: guest_node.send(PackedByteArray([index]))
	guest_node.peer.host.flush()
	await create_timer(.03).timeout
	host_node.peer.poll()
	check(host_node.peer.get_available_packet_count() >= 32, "Flood fixture actually queues a substantial batch at the receiver")
	host_node._process(0)
	check(host_node.last_poll_packets <= Transport.MAX_POLL_PACKETS and received.size() <= Transport.MAX_POLL_PACKETS, "One poll never dispatches more than the fixed packet budget")
	check(await pump_until(func(): return received.size() == 48), "A legitimate bounded backlog drains across later frames")
	received.clear()
	host_node._reset_budgets()
	var costly_handler := func(_data: PackedByteArray): OS.delay_usec(3000)
	host_node.packet.connect(costly_handler)
	for index in 5: guest_node.send(PackedByteArray([index]))
	guest_node.peer.host.flush()
	await create_timer(.03).timeout
	host_node._process(0)
	check(host_node.last_poll_packets == 1 and host_node.last_poll_usec >= 3000, "A costly packet handler exhausts the time budget after one dispatch")
	host_node.packet.disconnect(costly_handler)
	await pump_until(func(): return received.size() == 5)
	received.clear()
	# Close inside packet callback: the remaining old queue must not dispatch.
	var close_handler := func(_data: PackedByteArray): host_node.close()
	host_node.packet.connect(close_handler)
	for index in 3: guest_node.send(PackedByteArray([index]))
	guest_node.peer.host.flush()
	await create_timer(.03).timeout
	host_node._process(0)
	check(host_node.peer == null and received.size() == 1, "Closing inside a packet callback safely invalidates the rest of its old poll")
	check(not host_node.can_send_to(), "Transition readiness notices the actual closed transport immediately")
	host_node.packet.disconnect(close_handler)
	check(guest_node.send(PackedByteArray()) == ERR_INVALID_PARAMETER or guest_node.peer == null, "Empty local packets are rejected")
	release_pair()
	check(await setup_pair(), "Closing releases the UDP port for an immediate fresh host")
	var epoch := host_node._signal_epoch
	host_node._peer_disconnected(host_node.connected_peer, epoch - 1)
	check(host_node.connected_peer != 0, "An old peer callback cannot disconnect a replacement connection")
	host_node._peer_budgets[host_node.connected_peer].packets[2] = 0.0
	host_node._peer_budgets[host_node.connected_peer].updated = Time.get_ticks_usec() + 1000000
	guest_node.send(PackedByteArray([33]), false, 2)
	check(await pump_until(func(): return host_node.dropped_voice_packets>0), "Excess voice after a stall is dropped within the channel budget")
	check(errors.is_empty() and received.is_empty() and not host_node._disconnecting, "Over-budget speech does not disconnect a healthy match")
	check(guest_node.send(PackedByteArray([34]))==OK, "Reliable gameplay remains available after dropping excess speech")
	check(await pump_until(func():return received.size()==1), "The next real gameplay packet survives a voice backlog")
	host_node._reset_budgets()
	var dropped_before:=host_node.dropped_voice_packets
	var speech:=PackedByteArray()
	speech.resize(320)
	for frame in 80: guest_node.send(speech,false,2)
	guest_node.peer.host.flush()
	await create_timer(.03).timeout
	host_node.peer.poll()
	check(host_node.peer.get_available_packet_count()>36,"A simulated receiver stall queues more real speech than the voice burst allowance")
	check(await pump_until(func():return host_node.peer!=null and host_node.peer.get_available_packet_count()==0),"The speech backlog drains in bounded frame batches")
	check(errors.is_empty() and host_node.dropped_voice_packets>dropped_before and host_node.connected_peer!=0,"A real queued speech burst drops stale packets while preserving the ENet link")
	release_pair()
	check(await setup_pair(), "A fresh peer starts with fresh rate budgets after a rejected guest")
	for index in int(Transport.PACKET_BURSTS[0]) + 100: guest_node.send(PackedByteArray([index % 256]))
	guest_node.peer.host.flush()
	await create_timer(.03).timeout
	host_node.peer.poll()
	check(host_node.peer.get_available_packet_count() > Transport.MAX_BACKLOG_PACKETS, "Backlog fixture reaches the actual native receive queue limit")
	host_node._process(0)
	check(errors.is_empty() and received.size()<=Transport.MAX_POLL_PACKETS and not host_node._disconnecting,"A transient loading backlog gets a bounded drain opportunity")
	check(await pump_until(func():return not errors.is_empty()),"A sustained over-budget sender is still rejected while draining")
	release_pair()
	# Two still-finishing mapping jobs must not spawn a third router worker.
	# These probes never start their threads and never access a real router.
	host_node = Transport.new()
	root.add_child(host_node)
	host_node.set_process(false)
	host_node._jobs = [Transport.RouterMappingJob.new(), Transport.RouterMappingJob.new()]
	check(host_node.host(port, true) == OK and host_node._active_job == null and host_node._jobs.size() == 2 and host_node.mapping_hint.contains("vorherige"), "Rapid host restarts bound router workers while keeping LAN hosting available")
	host_node._jobs.clear()
	release_pair()
	print("Network transport hardening: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
