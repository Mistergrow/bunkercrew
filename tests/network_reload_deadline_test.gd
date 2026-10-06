extends SceneTree
## A real scene reload after a prepared long-running session clock. The room
## contains only its host; the separate two-process music run covers readiness.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OPTIONS := {"environment":"ash_foundry","build_type":"workshop","position":"left"}
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(2)
		return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(2, OPTIONS)
	var session: Node = game.network
	session._promote()
	session.active = true
	session.is_host = true
	session.state = "playing"
	session._match_options = OPTIONS.duplicate()
	session._match_characters = game.selected_characters.duplicate()
	session._match_player_count = 2
	session._generation = 8
	for elapsed in [90.0, 900.0]:
		var previous_scene: int = game.get_instance_id()
		session._clock = elapsed
		session._load_deadline = 15.0
		check(game.restart(), "Normal restart accepts a long-running host session")
		check(session._loading and session._load_deadline >= elapsed + 15.0, "Scene reload arms a fresh bounded loading deadline immediately")
		# This is the process frame that previously expired the old initial
		# deadline before bind_game's deferred begin_local_match could run.
		session._process(0.01)
		check(session.state != "error" and session.error_message.is_empty(), "Processing the scene gap cannot reuse the original expired deadline")
		for frame in 6:
			await process_frame
		game = current_scene
		check(is_instance_valid(game) and game.get_instance_id() != previous_scene and game.started, "Actual game scene reload starts the prepared mission")
		check(game.network == session and not session._loading and session.state == "playing", "The retained room completes readiness and rebinds to the new world")
		check(game.audio.live_music.session_active and game.audio.live_music.match_seed == session._generation, "The restarted actual game starts music on its current match seed")
	session.leave()
	check(await Cleanup.free_scene(game, self), "Reloaded world and audio release cleanly")
	if is_instance_valid(session):
		check(await Cleanup.free_scene(session, self), "Retained network room releases cleanly")
	else:
		check(true, "Inactive network room releases with its owning game")
	print("NETWORK RELOAD DEADLINE: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
