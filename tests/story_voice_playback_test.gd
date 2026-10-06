extends SceneTree
## Real imported dialogue, real AudioServer mix, real main-scene pause/settings.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
var capture: AudioEffectCapture

func _initialize(): run.call_deferred()

func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS ", label)
	else:
		failures += 1
		push_error(label)

func energy(frames: PackedVector2Array) -> float:
	var total := 0.0
	for value in frames: total += value.length_squared()
	return sqrt(total / maxf(1.0, frames.size() * 2.0))

func sample(seconds: float) -> PackedVector2Array:
	# The AudioServer runs on a separate real-time thread. SceneTree timers
	# alone can advance across a slow headless frame before queued audio mixes.
	# Drain the handover, then measure a complete wall-clock interval.
	await wall_time(.16)
	capture.clear_buffer()
	await wall_time(seconds)
	return capture.get_buffer(capture.get_frames_available())

func wall_time(seconds: float) -> void:
	var deadline := Time.get_ticks_usec() + roundi(seconds * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		await process_frame

func save_recording(path: String, frames: PackedVector2Array) -> bool:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) != OK:
		return false
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.stereo = true
	wave.mix_rate = roundi(AudioServer.get_mix_rate())
	var data := PackedByteArray()
	data.resize(frames.size() * 4)
	for index in frames.size():
		data.encode_s16(index * 4, roundi(clampf(frames[index].x, -1, 1) * 32767))
		data.encode_s16(index * 4 + 2, roundi(clampf(frames[index].y, -1, 1) * 32767))
	wave.data = data
	return wave.save_to_wav(ProjectSettings.globalize_path(path)) == OK

func run():
	LocaleText.set_locale("de", false)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.story_mode = true
	game.start_scenario(1, {"environment":"sector07", "position":"left", "build_type":"bastion"})
	game.set_process(false)
	game.story.set_process(false)
	game.rounds.running = false
	game.rounds.set_process(false)
	for player in game.players: player.set_physics_process(false)
	game.audio.settings_path = "user://story-voice-playback-test.cfg"
	game.audio.set_music_volume(0)
	game.audio.set_sfx_volume(0)
	game.audio.set_voice_volume(.8)
	game.dialogue.set_process(false)
	game.dialogue.reset()
	capture = AudioEffectCapture.new()
	capture.buffer_length = 2.0
	var master := AudioServer.get_bus_index("Master")
	var effect_index := AudioServer.get_bus_effect_count(master)
	AudioServer.add_bus_effect(master, capture)
	check(game.dialogue._streams.size() == 170, "The actual game preloads both complete recorded language banks")
	game.dialogue.enqueue("story_open", "san", 1, 1)
	game.dialogue.advance(.1)
	check(game.dialogue.voice.playing and game.dialogue.voice.bus == "Voice", "Dialogue starts a dedicated recorded Voice player")
	var audible := await sample(.6)
	check(audible.size() > 12000 and energy(audible) > .015, "Speech reaches the real master mix while SFX is muted")
	check(save_recording("res://artifacts/story-dialogue/actual-voice-mix.wav", audible), "A captured sample proves actual German game playback")
	game.hud.overlay = "pause"
	paused = true
	game.dialogue.advance(.1)
	var before: float = game.dialogue.voice.get_playback_position()
	var quiet := await sample(.3)
	print("Pause capture: rms=%.8f, position_delta=%.6f" % [energy(quiet), game.dialogue.voice.get_playback_position() - before])
	check(energy(quiet) < .0001 and absf(game.dialogue.voice.get_playback_position() - before) < .04, "Real pause stops audible speech and preserves its playback position")
	LocaleText.set_locale("en", false)
	var switched_quiet := await sample(.3)
	check(energy(switched_quiet) < .0001 and game.dialogue.voice.stream_paused and str(game.dialogue.voice.stream.resource_path).contains("/en/") and str(game.dialogue.active.text).begins_with("This is San."), "Changing language while paused replaces text and recording without leaking either voice")
	before = game.dialogue.voice.get_playback_position()
	paused = false
	game.hud.overlay = ""
	game.dialogue.advance(.1)
	var resumed := await sample(.5)
	check(energy(resumed) > .008 and game.dialogue.voice.get_playback_position() > before + .3 and game.dialogue.active.locale == "en", "Resuming plays the chosen English recording with its English subtitle")
	check(save_recording("res://artifacts/story-dialogue/actual-voice-mix-en.wav", resumed), "A captured sample proves actual English game playback")
	game.audio.set_voice_volume(0)
	var muted := await sample(.3)
	check(energy(muted) < .0001 and not game.dialogue.active.is_empty() and game.dialogue.canvas.visible, "The voice slider mutes actual output while preserving the subtitle")
	LocaleText.set_locale("de", false)
	var muted_switch := await sample(.25)
	check(energy(muted_switch) < .0001 and game.dialogue.active.locale == "de" and str(game.dialogue.active.text).begins_with("Hier ist San."), "Switching back to German preserves the voice volume setting")
	game.audio.set_voice_volume(.8)
	var original_character: String = game.players[0].character_id
	for locale: String in ["de", "en"]:
		LocaleText.set_locale(locale, false)
		for speaker: String in ["mara", "branko", "ivo", "nora", "levin", "selma", "oskar", "rika"]:
			game.players[0].character_id = speaker
			game.dialogue.reset()
			check(game.dialogue.enqueue("crew_reply", speaker, 1), "%s/%s accepts the selected new crew member" % [locale, speaker])
			game.dialogue.advance(.1)
			var crew_mix := await sample(.5)
			var expected_path := StoryDialogueCatalog.recording_path("crew_reply", speaker, locale)
			check(energy(crew_mix) > .008 and game.dialogue.voice.stream.resource_path == expected_path and game.dialogue.active.speaker_id == speaker, "%s/%s reaches the real mix with its own recording" % [locale, speaker])
	game.players[0].character_id = original_character
	LocaleText.set_locale("de", false)
	game.dialogue.reset()
	check(not game.audio._dialogue_active and not game.dialogue.voice.playing, "Reset stops playback and releases music ducking")
	AudioServer.remove_bus_effect(master, effect_index)
	await create_timer(.15, true).timeout
	await Cleanup.free_scene(game, self)
	print("Story voice playback: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
