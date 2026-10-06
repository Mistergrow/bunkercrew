extends SceneTree
## Runs the same real scene under headless or rendered/Dummy audio. Measures
## decoder release instead of relying on a guessed shutdown sleep duration.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start(1)
	game.rounds.set_process(false)
	await create_timer(0.2).timeout
	paused = true
	await create_timer(0.2, true, false, true).timeout
	paused = false
	await create_timer(11.0).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/audio-teardown-running.png")
	var music_was_playing: bool = game.audio.live_music.player.playing if game.audio.live_music.native_active else game.audio.music_player.playing
	var released: bool = await preload("res://tests/scene_cleanup.gd").free_scene(game, self)
	print("AUDIO TEARDOWN: score playing=%s, real playback handles released=%s, display=%s" % [music_was_playing, released, DisplayServer.get_name()])
	quit(0 if music_was_playing and released else 1)
