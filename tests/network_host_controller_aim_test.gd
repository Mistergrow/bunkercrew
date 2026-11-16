extends SceneTree
## Host path: a controller guest's sampled aim mode survives the real wire
## decoder and input sanitizer, and reaches the guest's own hand weapon.
const Protocol := preload("res://scripts/network_protocol.gd")
const Session := preload("res://scripts/network_session.gd")
const NetInput := preload("res://scripts/network_input.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
var sequence := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("HOST CONTROLLER AIM ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1
		push_error(label)

func deliver(session: Node, input: Dictionary) -> void:
	sequence += 1
	session._packet(Protocol.encode({"kind":"input", "generation":session._generation, "seq":sequence, "input":input}))
	session._prepare_remote_frame()

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	var base := {"held":{}, "pressed":[], "released":[], "aim":[640.0, 120.0]}
	var pad: Dictionary = base.duplicate(true)
	pad.mouse = false
	var pointer: Dictionary = base.duplicate(true)
	pointer.mouse = true
	check(Session.sanitize_input(pad).get("mouse") == false, "The sanitizer preserves a controller guest's aim mode")
	check(Session.sanitize_input(pointer).get("mouse") == true, "The sanitizer preserves a mouse guest's aim mode")
	check(Session.sanitize_input(base).get("mouse") == true, "An input without the field keeps the mouse default")
	for invalid in [0, 1, "false", null, [], {}]:
		var wrong: Dictionary = base.duplicate(true)
		wrong.mouse = invalid
		check(Session.sanitize_input(wrong).is_empty(), "A non-boolean aim mode is refused: " + str(invalid))
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	var session = game.network
	session.set_process(false)
	session.set_physics_process(false)
	session.active = true
	session.is_host = true
	session.state = "lobby"
	session._invite_secret = "23456789ABCDEFGH"
	session._packet(Protocol.encode({"kind":"hello", "version":Protocol.VERSION, "build":Protocol.BUILD, "world_revision":Protocol.WORLD_REVISION, "content_fingerprint":preload("res://scripts/content_registry.gd").fingerprint(), "resume":"", "invite":"23456789ABCDEFGH"}))
	check(session._authenticated, "The guest authenticates through the real handshake")
	session._generation = 1
	game.start_scenario(2, ScenarioCatalog.validate({}))
	game.rounds.running = false
	game.rounds.set_process(false)
	session._loading = false
	session.state = "playing"
	paused = false
	var host_worker = game.players[0]
	var guest_worker = game.players[1]
	for worker in game.players: worker.set_physics_process(false)
	var weapon = guest_worker.get_node("WorkerWeapon")
	check(is_instance_valid(weapon), "The guest worker owns a real hand weapon")
	var stick: Dictionary = pad.duplicate(true)
	stick.held = {"aim_up":0.8}
	deliver(session, stick)
	check(not session.remote_input.is_empty() and session.remote_input.mouse == false, "Decoded controller input keeps its aim mode in the host's remote frame")
	check(not NetInput.mouse_aim(guest_worker), "The host sees the remote guest aiming with a controller")
	check(is_equal_approx(NetInput.axis(guest_worker, "aim_up", "aim_down"), -0.8), "The remote stick strength reaches the guest's aim axis")
	var before: float = weapon._aim_pitch
	weapon._update_aim(0.25, false)
	check(weapon._aim_pitch < before - 0.2, "The guest's stick raises their weapon on the host instead of following a stale pointer")
	check(is_equal_approx(weapon.aim_direction.angle_to(Vector2(guest_worker.facing * cos(weapon._aim_pitch), sin(weapon._aim_pitch))), 0.0), "The host aims the remote weapon along the stick pitch")
	var turned: Dictionary = pointer.duplicate(true)
	turned.aim = [guest_worker.global_position.x + 300.0 * guest_worker.facing, guest_worker.global_position.y - 400.0]
	deliver(session, turned)
	check(NetInput.mouse_aim(guest_worker), "Switching back to the mouse is honoured on the next input")
	weapon._update_aim(0.25, false)
	check(weapon.aim_direction.y < -0.5, "A mouse guest still aims at their own pointer position")
	check(NetInput.mouse_aim(host_worker) == NetInput._primary_mouse_aim(game), "The host's own aim mode is never replaced by a guest's")
	var strikes: int = session._invalid_packets
	var wrong_mode: Dictionary = pad.duplicate(true)
	wrong_mode.mouse = "pad"
	deliver(session, wrong_mode)
	check(session._invalid_packets == strikes + 1 and session.remote_input.mouse == true, "A malformed aim mode counts as invalid and leaves the last accepted input in place")
	session.leave()
	paused = false
	check(await Cleanup.free_scene(game, self), "The host fixture releases its scene and audio handles")
	print("HOST CONTROLLER AIM: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
