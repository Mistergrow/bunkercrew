extends SceneTree
## Network deadlines use actual monotonic time, including blocked engine frames.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var session = game.network
	session.set_process(false)
	session.set_physics_process(false)
	session._process(0.0)
	var before: float = session._clock
	var before_usec := Time.get_ticks_usec()
	OS.delay_msec(350)
	session._process(0.01)
	var wall := float(Time.get_ticks_usec() - before_usec) / 1000000.0
	var elapsed: float = session._clock - before
	check(absf(elapsed - wall) < 0.03, "The room clock includes a real blocked frame despite a capped engine delta")
	print("NETWORK_WALLCLOCK_BLOCK ", JSON.stringify({"wall_seconds":wall, "room_seconds":elapsed, "engine_delta":0.01}))
	session.active = true
	session.is_host = false
	session.state = "connecting"
	session._deadline = session._clock + 2.0
	session._process(10.0)
	check(session.state == "connecting", "A large simulation delta cannot expire a network deadline before actual time has passed")
	before = session._clock
	OS.delay_msec(200)
	session.leave()
	check(session._clock - before >= 0.18 and session._deadline == 0.0, "Ending a room synchronizes idle time and clears its deadline before a new session")
	session.active = true
	session.is_host = false
	session.state = "connecting"
	session._deadline = session._clock + 0.35
	OS.delay_msec(550)
	session._process(0.01)
	check(session.state == "error" and not session.error_message.is_empty(), "A real expired connection deadline fires immediately after the stalled frame")
	session.leave()
	paused = false
	check(await Cleanup.free_scene(game, self), "Clock deadline handling frees the actual menu audio and game scene")
	print("NETWORK WALLCLOCK: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
