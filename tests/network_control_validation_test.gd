extends SceneTree
## Well-formed wire packets still need control-field type validation before use.
const PROTOCOL := preload("res://scripts/network_protocol.gd")
class SessionProbe extends "res://scripts/network_session.gd":
	var starts := 0
	var reloads := 0
	var connects := 0
	func _send(_message: Dictionary, _reliable := true, _target_id: int=0) -> bool:
		return true
	func _begin_local_match() -> void:
		starts += 1
	func _reload_game() -> void:
		reloads += 1
	func _connected() -> void:
		connects += 1
class WorldProbe extends RefCounted:
	var applications := 0
	func apply(_state: Dictionary,_wire_validated: bool=false) -> bool:
		applications += 1
		return true
class HudProbe extends Node:
	var overlay := ""
class GameProbe extends Node:
	var started := true
	var hud: HudProbe
	var combat_events: CombatEvents
	var selected_characters := ["mara", "branko"]

var checks := 0
var failures := 0
func _initialize() -> void:
	run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func deliver(session: SessionProbe, message: Dictionary) -> void:
	# Each malformed field is an independent boundary probe. Sustained abuse is
	# exercised by network_session_hardening_test.gd with the counter intact.
	session._invalid_packets=0
	var packet := PROTOCOL.encode(message)
	check(not packet.is_empty(), "The fixture traverses the actual compressed wire decoder")
	session._packet(packet)
func run() -> void:
	var game := GameProbe.new()
	root.add_child(game)
	game.hud = HudProbe.new()
	game.add_child(game.hud)
	game.combat_events = CombatEvents.new()
	game.add_child(game.combat_events)
	game.combat_events.persistence_enabled = false
	var session := SessionProbe.new()
	session.game = game
	game.add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	session.active = true
	session._authenticated = true
	session.state = "playing"
	session._generation = 4
	var world := WorldProbe.new()
	session.world = world
	for invalid in [[], {}, Vector2.ONE, "false", 0, 1, null]:
		for host in [true, false]:
			session.is_host = host
			deliver(session, {"kind":"pause", "paused":invalid})
			check(not paused and not session.match_paused and game.hud.overlay.is_empty(), "Malformed pause cannot stop either peer or open its modal")
		session.is_host = false
		deliver(session, {"kind":"snapshot", "generation":4, "seq":1, "world":{}, "paused":invalid})
		check(world.applications == 0 and session.received_snapshots == 0 and session._received_seq == -1, "Invalid snapshot control is rejected before applying world state or consuming sequence")
		deliver(session, {"kind":"start", "generation":5, "characters":["ivo", "mara"], "options":{}, "reset":invalid})
		check(session._generation == 4 and session.starts == 0 and session.reloads == 0, "Malformed reset cannot replace the match generation or reload the scene")
		session._relay_control({"op":"hosted", "code":"INVALID", "resume_token":"INVALID", "peer_connected":invalid})
		check(session.room_code.is_empty() and session._relay_resume_token.is_empty() and session.connects == 0 and session.state == "playing", "Invalid relay control cannot partially replace connection state")
	deliver(session, {"kind":"snapshot", "generation":4, "seq":1, "world":{}, "paused":false})
	check(world.applications == 1 and session.received_snapshots == 1 and session._received_seq == 1, "A valid snapshot still applies after malformed packets")
	deliver(session, {"kind":"pause", "paused":true,"generation":4})
	check(paused and session.match_paused and game.hud.overlay == "pause", "Valid boolean pause still reaches the client")
	deliver(session, {"kind":"pause", "paused":false,"generation":4})
	check(not paused and not session.match_paused and game.hud.overlay.is_empty(), "Valid boolean resume restores gameplay")
	deliver(session, {"kind":"start", "generation":5, "characters":["ivo", "mara"], "options":ScenarioCatalog.validate({}), "reset":true,"story":false})
	check(session._generation == 5 and session.reloads == 1, "Valid reset reloads exactly once")
	session.is_host=false
	session.relay_url="ws://127.0.0.1:8765/ws"
	session._relay_requested=true
	session._relay_action="join"
	session._join_code="ABCDEF"
	session.state="connecting"
	var accepted:={"op":"joined","code":"ABCDEF","role":"guest","player_id":2,"resume_token":"abcdefghijklmnopqrstuvwxyz012345","started":false,"peer_connected":true}
	for field in ["code","role","resume_token","started","peer_connected"]:
		for invalid in [null,{},[],123,"oversized or invalid field"]:
			var malformed: Dictionary=accepted.duplicate(true)
			malformed[field]=invalid
			session._relay_control(malformed)
			check(session.room_code.is_empty() and session._relay_resume_token.is_empty() and session.connects==0 and session.state=="connecting","Malformed relay "+field+" cannot partly establish a room")
	session._relay_control(accepted)
	check(session.room_code == "ABCDEF" and session.connects == 1, "Valid relay control still initializes the peer")
	var old_token: String=session._relay_resume_token
	session._relay_control(accepted)
	check(session.connects==1 and session._relay_resume_token==old_token,"Duplicate admission acknowledgement cannot reset an established connection")
	session.peer_connected=true
	session._authenticated=true
	session._relay_control({"op":"peer_joined","role":"host","player_id":1,"name":"Mara","resumed":false})
	check(session.connects==1 and session._authenticated,"Peer notification after join cannot reset authentication")
	session._relay_control({"op":"peer_left","role":"guest","player_id":2,"reason":"left","reconnect_seconds":0})
	check(session.peer_connected and session._authenticated,"Wrong relay role cannot disconnect this peer")
	session.state="reconnecting"
	session._relay_action="resume"
	session.peer_connected=false
	var resumed:={"op":"resumed","code":"ABCDEF","role":"guest","player_id":2,"resume_token":"0123456789abcdefghijklmnopqrstuv","started":true,"peer_connected":true}
	var wrong_room: Dictionary=resumed.duplicate(true)
	wrong_room.code="BCDEFG"
	session._relay_control(wrong_room)
	check(session._relay_resume_token==old_token and session.connects==1,"Resume cannot substitute another room")
	session._relay_control(resumed)
	check(session._relay_resume_token==resumed.resume_token and session.connects==2,"Valid resumed session rotates token and reconnects once")
	session.is_host=true
	session.state="connecting"
	session._relay_action="host"
	session.room_code=""
	session._relay_resume_token=""
	var hosted:={"op":"hosted","code":"BCDEFG","role":"host","player_id":1,"token":"abcdefghijklmnopqrstuvwxyz012345","resume_token":"abcdefghijklmnopqrstuvwxyz012345","started":false}
	session._relay_control(hosted)
	check(session.room_code=="BCDEFG" and session.connects==2,"Hosted acknowledgement initializes only the local seat")
	await preload("res://tests/scene_cleanup.gd").free_scene(game, self)
	print("NETWORK CONTROL VALIDATION: %d/%d checks passed" % [checks-failures, checks])
	quit(1 if failures else 0)
