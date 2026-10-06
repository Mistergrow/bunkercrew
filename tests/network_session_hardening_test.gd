extends SceneTree
const Protocol:=preload("res://scripts/network_protocol.gd")
const Messages:=preload("res://scripts/network_messages.gd")
const Codes:=preload("res://scripts/network_join_code.gd")
const Codec:=preload("res://scripts/voice_codec.gd")
var checks:=0
var failures:=0

func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func _run() -> void:
	var first:=Codes.new_invitation()
	var second:=Codes.new_invitation()
	check(first.length()==16 and first!=second,"Room invitations use independent random values")
	for port in [24777,24891]:
		var invitation:=Codes.invite("127.0.0.1",port,first)
		var decoded:=Codes.decode(invitation)
		check(decoded.get("ok",false) and decoded.invite==first and decoded.port==port and decoded.code==invitation,"Address and invitation round-trip, including custom ports")
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	var session=game.network
	session.set_process(false)
	session.set_physics_process(false)
	for address in ["ws://example.com/ws","ws://127.0.0.1:8765@example.com/ws","ws://[2001:db8::1]/ws"]:
		session.relay_url=address
		session._connect_relay("host")
		check(session.state=="error" and session._websocket==null,"External plaintext relay is rejected before opening a socket")
		session.leave()
	session.relay_url=""
	session.active=true
	session.is_host=true
	session.state="lobby"
	session._invite_secret=first
	session._guest_token="a".repeat(48)
	for i in 12: session._packet(PackedByteArray([0,1,2]))
	check(session.state=="lobby" and session._rejecting and session.active,"Unauthenticated malformed traffic rejects the guest without closing the host room")
	session._rejecting=false
	session._invalid_packets=0
	var hello:={"kind":"hello","version":Protocol.VERSION,"build":Protocol.BUILD,"world_revision":Protocol.WORLD_REVISION, "content_fingerprint":preload("res://scripts/content_registry.gd").fingerprint(),"resume":"","invite":second}
	session._packet(Protocol.encode(hello))
	check(not session._authenticated and session._rejecting,"Knowing the address cannot authenticate with a wrong invitation")
	session._rejecting=false
	hello.invite=first
	session._packet(Protocol.encode(hello))
	check(session._authenticated and session.peer_connected,"The copied invitation authenticates the guest")
	session._generation=2
	game.start_scenario(2,ScenarioCatalog.validate({}))
	session._loading=false
	session.state="playing"
	paused=false
	session._packet(Protocol.encode({"kind":"pause","paused":true,"generation":1}))
	check(not session.match_paused and not paused,"Previous-match pause cannot affect the new match")
	session._packet(Protocol.encode({"kind":"pause","paused":true,"generation":2}))
	check(session.match_paused and paused,"Current-match pause still works")
	session._packet(Protocol.encode({"kind":"pause","paused":false,"generation":2}))
	check(not session.match_paused and not paused,"Current-match resume still works")
	var before_generation:int=session._generation
	var start:={"kind":"start","generation":3,"options":game.scenario_options,"characters":["mara","branko"],"story":false,"reset":true}
	session._packet(Protocol.encode(start))
	check(session._generation==before_generation,"A guest cannot send a host-only start command")
	session.is_host=false
	session._receive_start({"generation":1,"options":game.scenario_options,"characters":["mara","branko"],"story":false,"reset":true})
	check(session._generation==2,"Old start command cannot roll back a generation or reload the scene")
	session._receive_start({"generation":2,"options":game.scenario_options,"characters":["mara","branko"],"story":false,"reset":true})
	check(session._generation==2 and not session._reload_match,"Duplicate start is idempotent")
	var capacity:=0
	for i in 30:
		if session._allow_message("voice"): capacity+=1
	check(capacity==10,"Voice bursts consume a dedicated bounded budget")
	check(session._allow_message("input"),"A voice burst cannot consume the independent input budget")
	session._clock+=1.0
	check(session._allow_message("voice"),"Voice rate tokens recover with elapsed time")
	var pcm:=PackedFloat32Array()
	pcm.resize(Codec.FRAMES)
	var voice:={"kind":"voice","generation":2,"seq":1,"rate":Codec.RATE,"pcm":Codec.encode(pcm)}
	check(Messages.valid(voice,true),"A fixed-size speech frame is a valid authenticated message")
	for invalid in [true,0,-1,INF,"1"]:
		var bad:=voice.duplicate()
		bad.seq=invalid
		check(not Messages.valid(bad,true),"Invalid speech sequence is rejected")
	var oversized:=voice.duplicate()
	oversized.pcm=PackedByteArray()
	oversized.pcm.resize(Codec.BYTES+2)
	check(not Messages.valid(oversized,true),"Speech packet cannot request arbitrary buffer sizes")
	session._invalid_packets=0
	session._packet_budgets.clear()
	session._last_packet_at=-50
	for i in 11: session._packet(PackedByteArray([0,1,2]))
	check(session.state=="playing" and session._last_packet_at==-50,"Invalid packets never refresh connection liveness")
	session._packet(PackedByteArray([0,1,2]))
	check(session.state=="error" and not session._authenticated,"Sustained malformed traffic closes the session")
	session.leave()
	paused=false
	# SceneTree shutdown exits the root-owned session while its game still exists.
	# Cleanup must not try to reparent from inside the parent's removal callback.
	session._reload_match=true
	session.reparent(root)
	session._reload_match=false
	session.active=true
	session.state="lobby"
	root.remove_child(session)
	check(session.get_parent()==null and not session.active and session.state=="offline","Root removal closes the session without reparenting during tree exit")
	session.free()
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Session and audio teardown completes")
	print("SESSION HARDENING: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
