extends SceneTree
## The actual options and live session must agree on the new profile baseline.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Dance := preload("res://scripts/worker_dance_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	InputSetup.install()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	check(game.audio.music_volume == 0.5 and game.audio.sfx_volume == 0.5 and game.audio.voice_volume == 0.5, "Fresh actual game starts all three audio channels at fifty percent")
	check(game.audio.live_music_enabled and game.audio.music_style == "level_default" and not game.audio.rhythm_motion_reduced, "Fresh game inherits the chosen audible rhythm preferences")
	check(game.audio.dance_intensity == 1.5, "Fresh game inherits the current global dance strength")
	for id: String in Dance.IDS:
		check(game.audio.dance_profiles[id] == {"style":"character_default", "intensity":1.0}, "Fresh game preserves the chosen individual character profile: " + id)
	game.hud._toggle_audio()
	await process_frame
	await process_frame
	check(game.hud.sliders.size() == 3 and game.hud.sliders.all(func(slider): return is_equal_approx(slider.value, 0.5)), "All three actual options sliders show fifty percent")
	check(game.hud.options_panel.dance_gain_slider.value == 1.5, "The actual Takt slider shows the captured global dance strength")
	game.hud.sliders[0].value = 0.27
	game.hud.sliders[1].value = 0.68
	game.hud.options_panel.dance_gain_slider.value = 0.8
	check(is_equal_approx(game.audio.music_volume, 0.27) and is_equal_approx(game.audio.sfx_volume, 0.68) and is_equal_approx(game.audio.dance_intensity, 0.8), "Actual slider edits override the baseline immediately")
	game.hud._close_audio()
	game.start_scenario(1, {"environment":"ash_foundry", "build_type":"bastion", "position":"left"})
	game.rounds.running = false
	await process_frame
	check(is_equal_approx(game.audio.live_music.dance_intensity, 0.8) and is_equal_approx(game.audio.music_volume, 0.27), "An actual mission retains the player's edited dance and audio settings")
	check(await Cleanup.free_scene(game, self), "The actual audio/options/live scene releases every playback")
	print("AUDIO DEFAULTS: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
