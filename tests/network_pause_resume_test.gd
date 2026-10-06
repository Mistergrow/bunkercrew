extends SceneTree
## Explicit pause survives reconnect readiness and expiry of an absent guest.
const Protocol := preload("res://scripts/network_protocol.gd")
const PeerState := preload("res://scripts/network_peer_state.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
class RecordingSession extends "res://scripts/network_session.gd":
	var controls: Array[Dictionary] = []
	func _send_encoded(data: PackedByteArray, _reliable: bool, _target_id: int = 0, _channel: int = -1) -> bool:
		controls.append(Protocol.decode(data))
		return true
var checks := 0
var failures := 0
var game
var session

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func prepare() -> void:
	session.leave()
	paused = false
	session.set_process(false)
	session.set_physics_process(false)
	session.active = true
	session.is_host = true
	session.state = "playing"
	session._generation = 7
	session._clock = 0
	session._loading = false
	session.controls.clear()
	game.rounds.phase = "build"
	game.hud.overlay = ""
	for slot: int in [2, 3]:
		var link: Dictionary = PeerState.create(0)
		link.slot = slot
		link.wire = slot * 10
		link._authenticated = true
		link._ready_for_snapshots = true
		session._slots[slot] = link
		session._peers[slot * 10] = link
	session._leave_peer()

func reconnect_ready() -> void:
	session.state = "reconnecting"
	session._loading = true
	session._slots[2]._ready_for_snapshots = false
	session._set_pause(true)
	session._packet_from(Protocol.encode({"kind":"ready", "generation":7}), 20)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	game.start_scenario(3, {"environment":"ash_foundry", "build_type":"workshop", "position":"left"})
	game.rounds.running = false
	game.network.leave()
	game.network.set_process(false)
	game.network.set_physics_process(false)
	session = RecordingSession.new()
	game.add_child(session)
	session.game = game
	prepare()
	session.pause_match(true)
	check(paused and session.match_paused, "Real pause API pauses the live host before reconnect")
	reconnect_ready()
	check(session.state == "playing" and not session._loading, "Real decoded Ready completes the recovered session")
	check(paused and session.match_paused, "Recovered Ready preserves the previously explicit pause")
	session.pause_match(false)
	check(not paused and not session.match_paused, "Crew can explicitly resume after a paused reconnect")
	prepare()
	reconnect_ready()
	check(not paused and not session.match_paused, "Automatic reconnect waiting still resumes a previously running match")
	prepare()
	session.pause_match(true)
	session._peer_disconnected_id(20, "Pause regression")
	session._clock = 31
	session._expire_missing_slots()
	check(session.state == "playing" and not session._slots.has(2) and session._slots.has(3), "Expired guest leaves the authenticated surviving crew playable")
	check(paused and session.match_paused, "Expired guest recovery preserves the explicit shared pause")
	var controls: Array = session.controls.filter(func(row): return row.get("kind") == "pause")
	check(not controls.is_empty() and controls.back().paused == true, "Surviving guests receive the actual retained pause instead of a false resume packet")
	session.pause_match(false)
	check(not paused and not session.match_paused, "Remaining crew can explicitly resume after expiry")
	prepare()
	session._peer_disconnected_id(20, "Automatic pause regression")
	session._clock = 31
	session._expire_missing_slots()
	check(not paused and not session.match_paused, "Expiry clears only automatic waiting for a missing guest")
	session.leave()
	paused = false
	check(await Cleanup.free_scene(game, self), "Pause-state fixture releases actual game and audio")
	print("NETWORK PAUSE RESUME: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
