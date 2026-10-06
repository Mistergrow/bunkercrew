extends SceneTree
## Actual paused game menu, real OGG decoder and native level/lab transitions.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Catalog := preload("res://scripts/menu_music_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func wait_seconds(seconds: float) -> void:
	# The frame which synchronously constructs/imports the whole game may carry
	# a large SceneTree delta. Mixer checks require actual elapsed wall time.
	var deadline := Time.get_ticks_msec() + ceili(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await create_timer(0.008, true, false, true).timeout

func pcm_energy(capture: AudioEffectCapture) -> float:
	var pcm := capture.get_buffer(capture.get_frames_available())
	print("MENU_AUDIO_PCM frames=", pcm.size(), " discarded=", capture.get_discarded_frames())
	var energy := 0.0
	for sample: Vector2 in pcm:
		if not sample.is_finite(): return INF
		energy += sample.length_squared()
	return energy / maxf(pcm.size(), 1.0)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Run this actual game fixture with --no-profile-save --no-upnp.")
		quit(1)
		return
	InputSetup.install()
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await process_frame
	var audio = game.audio
	var menu = audio.menu_music
	check(paused and not game.started and game.hud.overlay == "menu", "The actual game begins in its paused pre-match menu")
	check(menu.playing and menu.process_mode == Node.PROCESS_MODE_ALWAYS and menu.player.bus == "Music", "Dedicated recorded menu audio continues through the paused shell on the Music bus")
	check(menu.player.stream is AudioStreamOggVorbis and menu.player.stream.loop and absf(menu.player.stream.get_length() - Catalog.SECONDS) < 0.0001, "The actual menu decoder loops the sixty-second original OGG master")
	check(not audio.live_music.session_active and audio.music_players.all(func(deck): return not deck.playing), "Only the menu composition plays before a match; neither live synthesis nor fallback decks overlap")
	check(Catalog.KICK_SAMPLES.size() == 128 and Catalog.KICK_STRENGTHS.size() == 128 and Catalog.KICK_SAMPLES[0] == 0, "The runtime contains all 128 actual authored kick markers")
	var decoder_id: int = menu.player.get_stream_playback().get_instance_id()
	var music_bus := AudioServer.get_bus_index("Music")
	var effect_index := AudioServer.get_bus_effect_count(music_bus)
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 8.0
	AudioServer.add_bus_effect(music_bus, capture)
	await wait_seconds(0.8)
	var energy := pcm_energy(capture)
	print("MENU_AUDIO_PCM energy=", energy, " MusicMuted=", AudioServer.is_bus_mute(music_bus), " menuVolume=", menu.player.volume_db)
	check(is_finite(energy) and energy > 0.00001, "The real menu mixer produces finite audible stereo music")
	check(audio.menu_rhythm_frame().active and audio.menu_rhythm_frame().audible_seconds > 0.0 and audio.menu_rhythm_frame().bpm == 128.0, "The cached menu rhythm follows the actual audible OGG position")
	check(Catalog.SECONDARY_SAMPLES.size() == 128 and Catalog.SECONDARY_STRENGTHS.size() == 128 and Catalog.SECONDARY_TRACK == 8, "All real offbeat bass markers are independent of the menu's kick events")
	var secondary_heard: Dictionary = {}
	var distinct_secondary := false
	var secondary_peak := 0.0
	var secondary_deadline := Time.get_ticks_msec() + 1100
	while Time.get_ticks_msec() < secondary_deadline:
		await wait_seconds(0.008)
		var rhythm: Dictionary = audio.menu_rhythm_frame()
		secondary_peak = maxf(secondary_peak, float(rhythm.secondary_pulse))
		if float(rhythm.secondary_pulse) > 0.7:
			secondary_heard[float(rhythm.secondary_timestamp)] = true
			distinct_secondary = distinct_secondary or absf(float(rhythm.secondary_timestamp) - float(rhythm.kick_timestamp)) > 0.2
	check(secondary_heard.size() >= 2 and secondary_peak > 0.8 and distinct_secondary, "Several genuine audible offbeat bass hits publish their own pulses and timestamps")
	var position: float = audio.menu_rhythm_frame().audible_seconds
	game.hud.main_menu_panel.browse_environment(1)
	LocaleText.set_locale("en", false)
	await wait_seconds(0.15)
	check(menu.player.get_stream_playback().get_instance_id() == decoder_id and audio.menu_rhythm_frame().audible_seconds > position, "Preview and language changes preserve one decoder and its musical phrase")
	audio.set_live_music_enabled(false)
	audio.set_music_style("hip_hop")
	await wait_seconds(0.08)
	check(menu.playing and menu.player.get_stream_playback().get_instance_id() == decoder_id and audio.music_players.all(func(deck): return not deck.playing), "Live-synthesis preference and gameplay genre leave the additional menu track unchanged")
	position = audio.menu_rhythm_frame().audible_seconds
	audio.set_music_volume(0.0)
	check(not audio.menu_rhythm_frame().active and audio.menu_rhythm_frame().kick_pulse == 0.0 and AudioServer.is_bus_mute(music_bus), "The actual Music control immediately mutes audible menu motion")
	check(audio.menu_rhythm_frame().secondary_pulse == 0.0, "Music mute also removes the second-tone presentation")
	await wait_seconds(0.15)
	audio.set_music_volume(1.0)
	await wait_seconds(0.08)
	check(menu.player.get_stream_playback().get_instance_id() == decoder_id and audio.menu_rhythm_frame().audible_seconds > position, "Unmuting continues the running menu phrase instead of replaying its opening")
	var before_calibration: float = audio.menu_rhythm_frame().audible_seconds
	audio.set_music_calibration(0.125)
	audio._process(0.0)
	check(absf(before_calibration - float(audio.menu_rhythm_frame().audible_seconds) - 0.125) < 0.03, "Stored device calibration compensates the real menu decoder presentation")
	audio.set_music_calibration(0.0)
	var calibration = preload("res://scripts/music_calibration_panel.gd").new()
	calibration.audio = audio
	root.add_child(calibration)
	await wait_seconds(0.12)
	check(audio.calibration_active and menu.player.volume_db <= -79.0 and not audio.menu_rhythm_frame().active, "Actual calibration suspends the menu mix and its title pulse")
	calibration.close()
	await process_frame
	await wait_seconds(0.08)
	check(not audio.calibration_active and audio.menu_rhythm_frame().active and menu.player.get_stream_playback().get_instance_id() == decoder_id, "Closing calibration restores the same underlying menu transport")
	game.hud._toggle_audio()
	await process_frame
	await process_frame
	var options = game.hud.options_panel
	options.tab_buttons[3].pressed.emit()
	options.music_lab_button.pressed.emit()
	await wait_seconds(0.15)
	var lab = options.music_lab
	check(is_instance_valid(lab) and audio.calibration_active and menu.player.volume_db <= -79.0 and not audio.menu_rhythm_frame().active, "The real music-lab control ducks the menu and disables its cosmetic rhythm")
	check(menu.player.get_stream_playback().get_instance_id() == decoder_id and audio.music_players.all(func(deck): return not deck.playing), "A native lab preview cannot enqueue a second recorded world score under the menu")
	lab.close()
	await wait_seconds(0.1)
	check(not audio.calibration_active and menu.player.volume_db > -1.0 and audio.menu_rhythm_frame().active, "Closing the actual lab restores menu listening level and audible beat")
	game.hud._close_audio()
	await process_frame
	capture.clear_buffer()
	menu.player.seek(59.55)
	await wait_seconds(0.08)
	var loop_decoder_id: int = menu.player.get_stream_playback().get_instance_id()
	var previous: float = audio.menu_rhythm_frame().audible_seconds
	var minimum_step := 0.0
	var loop_seen := false
	var deadline := Time.get_ticks_msec() + 1100
	while Time.get_ticks_msec() < deadline:
		await wait_seconds(0.004)
		var frame: Dictionary = audio.menu_rhythm_frame()
		minimum_step = minf(minimum_step, float(frame.audible_seconds) - previous)
		previous = float(frame.audible_seconds)
		loop_seen = loop_seen or int(frame.decoder_loops) >= 1
	check(loop_seen and previous > 60.0 and minimum_step > -0.03, "The real decoder crosses its sixty-second loop with continuous audible time")
	check(menu.player.get_stream_playback().get_instance_id() == loop_decoder_id and audio.menu_rhythm_frame().active, "An actual loop wrap retains the prepared seek decoder and live kick presentation")
	var loop_energy := pcm_energy(capture)
	check(is_finite(loop_energy) and loop_energy > 0.00001, "The real loop boundary retains finite audible PCM")
	AudioServer.remove_bus_effect(music_bus, effect_index)
	var retired: WeakRef = weakref(menu.player.get_stream_playback())
	game.start_scenario(1, {"environment": "ash_foundry", "layout": "workshop", "site": "center", "difficulty": "standard"})
	await wait_seconds(0.12)
	check(game.started and not menu.playing and menu.player.stream == null and not audio.menu_rhythm_frame().active, "Actual scenario start stops/releases the menu score and its title beat")
	check(audio.live_music.session_active and not audio.live_music.native_active and audio.music_player.playing, "A disabled native preference enters the existing recorded level score cleanly")
	audio.set_live_music_enabled(true)
	await wait_seconds(0.12)
	check(audio.live_music.native_active and audio.music_players.all(func(deck): return not deck.playing) and not menu.playing, "Native level synthesis owns the Music mix after enabling it, with no menu/fallback overlap")
	check(retired.get_ref() == null, "The stopped menu playback handle retires from the real AudioServer")
	var old_id: int = game.get_instance_id()
	check(game.return_to_menu(), "The actual return-to-menu action reloads the pre-match shell")
	deadline = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline and (not is_instance_valid(current_scene) or current_scene.get_instance_id() == old_id):
		await process_frame
	game = current_scene
	await wait_seconds(0.2)
	check(is_instance_valid(game) and not game.started and paused and game.audio.menu_music.playing, "The reloaded menu restores its dedicated rave while gameplay remains paused")
	check(game.audio.menu_rhythm_frame().track_id == "kernimpuls" and game.audio.menu_music._track.kick_samples.size() < Catalog.BARS * 4, "The next real mission return selects the additional menu composition with its actual sparse intro markers")
	check(not game.audio.live_music.session_active and game.audio.music_players.all(func(deck): return not deck.playing), "Return from a real mission restores exactly one menu source")
	check(game.audio.music_volume == 1.0 and game.audio.music_style == "hip_hop" and game.audio.live_music_enabled, "Return-to-menu retains local audio preferences without writing a player profile")
	LocaleText.set_locale("de", false)
	check(await Cleanup.free_scene(game, self), "Final game teardown releases current and retired menu/live/recorded playback handles")
	print("MENU MUSIC AUDIO: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
