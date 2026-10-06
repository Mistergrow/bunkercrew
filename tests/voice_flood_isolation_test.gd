extends SceneTree
## Real ENet: one abusive voice sender and an independent healthy input sender.
const Transport := preload("res://scripts/network_transport.gd")
const Guard := preload("res://scripts/network_voice_guard.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("VOICE FLOOD PASS ",label)
func run() -> void:
	var guard := Guard.new()
	var burst_ok := true
	for packet in 400: burst_ok=guard.observe(0) and burst_ok
	for step in range(1,151): burst_ok=guard.observe(step*20000) and burst_ok
	check(burst_ok,"A large one-off burst followed by normal speech does not become persistent abuse")
	guard=Guard.new()
	var rejected_at := -1
	for step in range(1201):
		if not guard.observe(step*2000): rejected_at=step*2000; break
	check(rejected_at>=2000000 and rejected_at<=2250000,"Threefold excess must persist for two seconds before rejection")
	guard=Guard.new()
	var crew_ok := true
	for step in 1500: crew_ok=guard.observe(roundi(step*1000000.0/150),3) and crew_ok
	check(crew_ok,"Receiving all three other speakers remains within the guest allowance")
	var host := Transport.new()
	var flood := Transport.new()
	var healthy := Transport.new()
	for node in [host,flood,healthy]: root.add_child(node); node.set_process(false)
	var received: Array[int]=[]
	var rejected: Array[int]=[]
	host.packet_from.connect(func(data: PackedByteArray,sender: int):
		if host.last_packet_channel==0 and data==PackedByteArray([77]): received.append(sender))
	host.peer_error.connect(func(id: int,_message: String): rejected.append(id))
	check(host.host(39849,false)==OK and flood.join("127.0.0.1",39849)==OK and healthy.join("127.0.0.1",39849)==OK,"Three private UDP peers open")
	var deadline := Time.get_ticks_usec()+2000000
	while Time.get_ticks_usec()<deadline and host.remote_peers.size()<2:
		for node in [host,flood,healthy]: node._process(0)
		await process_frame
	check(host.remote_peers.size()==2,"Both guests connect to the same actual host")
	if host.remote_peers.size()<2:
		for node in [host,flood,healthy]: node.close();node.free()
		quit(1);return
	var attacker_id := flood.peer.get_unique_id()
	var healthy_id := healthy.peer.get_unique_id()
	var speech := PackedByteArray()
	speech.resize(640)
	var started := Time.get_ticks_usec()
	var next_voice := started
	var next_input := started
	var scan_bounded := true
	var max_voice_dispatch := 0
	var voice_in_poll := [0]
	host.packet_from.connect(func(_data: PackedByteArray,_sender: int):
		if host.last_packet_channel==2: voice_in_poll[0]+=1)
	while Time.get_ticks_usec()-started<3000000 and rejected.is_empty():
		var now := Time.get_ticks_usec()
		if now>=next_voice:
			next_voice=now+20000
			for packet in 10: flood.send(speech,false,2)
			if flood.peer!=null: flood.peer.host.flush()
		if now>=next_input:
			next_input=now+50000
			healthy.send(PackedByteArray([77]))
		voice_in_poll[0]=0
		for node in [host,flood,healthy]: node._process(0)
		max_voice_dispatch=maxi(max_voice_dispatch,voice_in_poll[0])
		scan_bounded=scan_bounded and host.last_poll_scanned<=Transport.MAX_POLL_SCANNED and host.last_poll_packets<=Transport.MAX_POLL_PACKETS
		await process_frame
	check(rejected==[attacker_id],"Only the sustained voice attacker is rejected")
	check(host.remote_peers.has(healthy_id) and healthy.connected_peer!=0,"The healthy guest keeps its connection")
	check(received.size()>=25 and received.all(func(id:int):return id==healthy_id),"Healthy input continues throughout the attack (%d packets)"%received.size())
	check(scan_bounded and max_voice_dispatch<=Transport.MAX_VOICE_PER_POLL,"Voice cannot occupy the whole dispatch budget; scanning remains bounded")
	check(host.dropped_voice_packets>0,"Excess voice is discarded before game decoding")
	for node in [host,flood,healthy]: node.close();node.free()
	print("VOICE FLOOD ISOLATION: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
