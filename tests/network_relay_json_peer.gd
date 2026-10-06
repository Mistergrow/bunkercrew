extends SceneTree
## Exercise actual WebSocket framing, malformed JSON and later valid admission.
const Cleanup := preload("res://tests/scene_cleanup.gd")

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args(): quit(2); return
	AudioServer.set_bus_mute(0, true)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.audio.live_music_enabled = false
	game.network.host_room(OS.get_environment("BUNKERCREW_JSON_RELAY"))
	var deadline := Time.get_ticks_msec() + 5000
	while game.network.state == "connecting" and Time.get_ticks_msec() < deadline: await process_frame
	var success: bool = game.network.state == "lobby" and game.network.room_code == "ABCDEF"
	game.network.leave()
	await Cleanup.free_scene(game, self)
	if success: print("RELAY JSON: malformed controls ignored and valid admission preserved")
	else: push_error("Malformed relay controls prevented valid admission")
	quit(0 if success else 1)
