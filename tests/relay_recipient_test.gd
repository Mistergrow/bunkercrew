extends SceneTree
## Inspect real WebSocket envelopes sent by the game's authenticated fanout.
const Session := preload("res://scripts/network_session.gd")
const PeerState := preload("res://scripts/network_peer_state.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("RECIPIENT PASS ",label)
func run() -> void:
	var listener := TCPServer.new()
	check(listener.listen(39851,"127.0.0.1")==OK,"A private loopback listener opens")
	var client := WebSocketPeer.new()
	check(client.connect_to_url("ws://127.0.0.1:39851")==OK,"The game socket starts a real connection")
	var receiver := WebSocketPeer.new()
	var deadline := Time.get_ticks_msec()+2000
	var accepted := false
	while Time.get_ticks_msec()<deadline:
		client.poll()
		if listener.is_connection_available() and not accepted:
			accepted = receiver.accept_stream(listener.take_connection())==OK
		if accepted: receiver.poll()
		if client.get_ready_state()==WebSocketPeer.STATE_OPEN and receiver.get_ready_state()==WebSocketPeer.STATE_OPEN: break
		await process_frame
	check(client.get_ready_state()==WebSocketPeer.STATE_OPEN,"The WebSocket handshake completes")
	if client.get_ready_state()!=WebSocketPeer.STATE_OPEN: quit(1); return
	var session := Session.new()
	session.active=true
	session.is_host=true
	session.relay_url="ws://127.0.0.1"
	session._websocket=client
	for id in [2,3,4]:
		var link := PeerState.create(0)
		link.connected=true
		link._authenticated=id!=4
		session._peers[id]=link
	var payload := PackedByteArray([19,25,31])
	check(session._send_encoded(payload,true,-1),"Shared gameplay state is queued")
	check(session._send_encoded(payload,false,-1,2),"Shared voice is queued")
	var routes: Array[int]=[]
	var packets: Array[PackedByteArray]=[]
	deadline=Time.get_ticks_msec()+1000
	while Time.get_ticks_msec()<deadline and packets.size()<4:
		client.poll(); receiver.poll()
		while receiver.get_available_packet_count()>0:
			var packet:=receiver.get_packet()
			routes.append(packet[0]); packets.append(packet.slice(1))
		await process_frame
	check(routes==[2,3,130,131],"State and voice address only completed game handshakes; no route 0 or pending seat 4")
	check(packets.size()==4 and packets.all(func(p: PackedByteArray):return p==payload),"Targeted envelopes preserve every opaque game payload")
	client.close(); receiver.close(); listener.stop()
	session._websocket=null
	session.free()
	print("RELAY RECIPIENTS: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
