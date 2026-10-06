extends SceneTree
const Protocol := preload("res://scripts/network_protocol.gd")
const PeerState := preload("res://scripts/network_peer_state.gd")
class RejectWorld extends RefCounted:
	var last_error := "Rejected fixture state"
	func apply(_world: Dictionary,_validated: bool=false) -> bool: return false
class CapturedWorld extends RefCounted:
	var captures := 0
	func capture() -> Dictionary:
		captures+=1
		return {"fixture":captures}
class RecordingTransport extends Node:
	var connected_peer := 1
	var packets: Array = []
	func send(packet: PackedByteArray,_reliable: bool,_channel: int,peer: int) -> Error:
		packets.append({"peer":peer,"packet":packet})
		return OK
var checks := 0
var failures := 0
var game
var network
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func prepare() -> void:
	network.leave()
	network.active=true
	network.is_host=true
	network.state="playing"
	network._generation=1
	network._clock=0
	network._match_player_count=3
	network._match_options=game.scenario_options.duplicate()
	network._match_characters=game.selected_characters.duplicate()
	network._loading=false
	for slot in [2,3]:
		var link: Dictionary=PeerState.create(0)
		link.slot=slot
		link.wire=slot*10
		link._authenticated=true
		link._ready_for_snapshots=true
		network._slots[slot]=link
		network._peers[slot*10]=link
	network._leave_peer()
func run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(3,{"environment":"sector07","build_type":"workshop","position":"left"})
	game.rounds.set_process(false)
	network=game.network
	prepare()
	network._slots[2].ping_ms=45
	network._slots[3].ping_ms=120
	network._enter_peer(20)
	network._leave_peer()
	check(network.ping_ms==120,"Host ping represents the highest authenticated guest latency")
	var old_transport=network.transport
	var recorder=RecordingTransport.new()
	root.add_child(recorder)
	network.transport=recorder
	var captured=CapturedWorld.new()
	network.world=captured
	network._send_snapshot_batch()
	check(captured.captures==1 and recorder.packets.size()==2,"Host captures a shared tick only once for multiple guests")
	check(recorder.packets[0].packet==recorder.packets[1].packet,"Every guest receives the same encoded snapshot and sequence")
	network.transport=old_transport
	network.world=null
	recorder.queue_free()
	network._peer_disconnected_id(20,"fixture departure")
	check(network.state=="reconnecting" and paused,"One lost guest initially pauses all participants")
	var grace_changes: Array=[]
	var listener:=func(): grace_changes.append(true)
	network.changed.connect(listener)
	network._clock=1
	network._expire_missing_slots()
	network._expire_missing_slots()
	check(grace_changes.is_empty() and network._slots.has(2),"Waiting grace does not broadcast unchanged lobby state every frame")
	network.changed.disconnect(listener)
	network._clock=31
	network._slots[3]._last_packet_at=31
	network._process(0)
	check(network.active and network.state=="playing" and not paused,"Expired guest grace resumes the surviving match")
	check(network.is_player_connected(3) and not network._slots.has(2),"Other links survive while only the missing slot is retired")
	check(game.players[1].is_downed() and not game.players[1].can_act() and not game.players[1].visible,"Retired avatar cannot block defeat, act or occupy the map")
	prepare()
	var old: Dictionary=network._slots[3]
	var token: String=old._guest_token
	network._peers[300]=PeerState.create(0)
	network._peers[300].wire=300
	network._enter_peer(300)
	network._accept_hello({"kind":"hello","version":Protocol.VERSION,"build":Protocol.BUILD,"world_revision":Protocol.WORLD_REVISION, "content_fingerprint":preload("res://scripts/content_registry.gd").fingerprint(),"resume":token,"invite":""})
	network._leave_peer()
	check(network._slots[3].wire==300 and network._slots[3]._authenticated and not network._peers.has(30),"Known resume token replaces a still-connected stale link")
	prepare()
	network.is_host=false
	network._authenticated=true
	network._packet(Protocol.encode({"kind":"leave"}))
	check(network.state=="error" and network._reconnect_deadline==0,"Intentional host leave terminates immediately without retry")
	prepare()
	network.is_host=false
	network.relay_url="ws://127.0.0.1:1/ws"
	network._relay_resume_token="fixture"
	network._disconnected("fixture outage")
	var deadline: float=network._reconnect_deadline
	for at in [5.0,15.0,25.0,31.0]:
		network._clock=at
		network._websocket=WebSocketPeer.new()
		network._poll_relay()
		check(network._reconnect_deadline==deadline,"Repeated failed relay attempts do not extend the deadline")
	network._process(0)
	check(network.state=="error","Relay reconnect terminates when its original deadline expires")
	prepare()
	network.is_host=false
	network._authenticated=true
	network.world=RejectWorld.new()
	for sequence in range(1,6):
		network._packet(Protocol.encode({"kind":"snapshot","generation":1,"seq":sequence,"paused":false,"world":{}}))
	check(network.state=="error" and not network.error_message.is_empty(),"Persistent snapshot rejection ends with an actionable error")
	check(network._snapshot_failures==5 and network._last_resync_at==0,"Snapshot rejection requests resync and counts failures")
	network.leave()
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("NETWORK FOLLOWUP: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
