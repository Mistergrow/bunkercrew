extends SceneTree
## Count validation must precede native conversions even after a valid wire decode.
const Protocol := preload("res://scripts/network_protocol.gd")
const Messages := preload("res://scripts/network_messages.gd")
const Probes := preload("res://tests/network_control_validation_test.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func start_message() -> Dictionary:
	return {"kind":"start","generation":5,"characters":["mara","branko","ivo","oskar"],"count":2,"capacity":4,"options":ScenarioCatalog.validate({}),"story":false,"reset":true}

func run() -> void:
	var game := Probes.GameProbe.new()
	root.add_child(game)
	game.hud = Probes.HudProbe.new()
	game.add_child(game.hud)
	game.combat_events = CombatEvents.new()
	game.add_child(game.combat_events)
	game.combat_events.persistence_enabled = false
	var session := Probes.SessionProbe.new()
	session.game = game
	game.add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	session.active = true
	session.is_host = false
	session._authenticated = true
	session.state = "playing"
	session._generation = 4
	for invalid: Variant in [null,true,false,-1,0,1,5,2.0,"2",{},[],Vector2.ONE,Rect2(0,0,2,2)]:
		var message := start_message()
		message.count = invalid
		var encoded := Protocol.encode(message)
		var decoded := Protocol.decode(encoded)
		check(not encoded.is_empty() and not decoded.is_empty(),"Malformed count still passes the bounded data-only wire decoder")
		var accepted: Variant = Messages.valid(decoded,false)
		check(accepted == false,"Malformed count is rejected without conversion errors")
		session._invalid_packets = 0
		session._packet(encoded)
		check(session._generation == 4 and session.reloads == 0 and session.starts == 0 and session.state == "playing","Invalid count cannot reload or replace the running session")
	for count in [2,3,4]:
		var message := start_message()
		message.count = count
		check(Messages.valid(Protocol.decode(Protocol.encode(message)),false),"Legitimate two-to-four-player start remains supported")
	var legacy := start_message()
	legacy.erase("count")
	check(Messages.valid(Protocol.decode(Protocol.encode(legacy)),false),"Existing two-player envelopes retain their default count")
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("NETWORK START COUNT: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
