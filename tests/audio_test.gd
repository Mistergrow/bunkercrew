extends SceneTree

const Catalog := preload("res://scripts/audio_catalog.gd")

class Phase extends Node:
	var phase := "build"

class TestGame extends Node:
	var started := true
	var rounds

var failures := 0
var checks := 0
const TEST_SETTINGS := "user://audio-regression-test.cfg"

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS ", label)
	else:
		failures += 1
		push_error(label)

func run_checks() -> void:
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	var game := TestGame.new()
	root.add_child(game)
	var phases := Phase.new()
	game.add_child(phases)
	game.rounds = phases
	var audio = load("res://scripts/audio.gd").new()
	audio.settings_path = TEST_SETTINGS
	audio.persistence_enabled = true # Explicitly exercise the isolated settings file.
	game.add_child(audio)
	audio.set_process(false)
	# Playback begins after scene setup so discarded scenes cannot enqueue music.
	await process_frame
	check(audio.music_volume == 0.5 and audio.sfx_volume == 0.5 and audio.voice_volume == 0.5, "Music, effects and character voices start at fifty percent")
	check(audio.process_mode == Node.PROCESS_MODE_ALWAYS, "Music and volume saving remain active in menus and pause")
	check(audio.streams.size() == Catalog.VARIANT_COUNTS.size(), "All declared gameplay sound categories load their real assets")
	var variation_count := 0
	var declared_variation_count := 0
	var valid_samples := true
	for kind: String in Catalog.VARIANT_COUNTS:
		declared_variation_count += int(Catalog.VARIANT_COUNTS[kind])
		if not audio.variants.has(kind) or audio.variants[kind].size() != int(Catalog.VARIANT_COUNTS[kind]):
			valid_samples = false
	for kind in audio.variants:
		variation_count += audio.variants[kind].size()
		for sample in audio.variants[kind]:
			if not sample is AudioStreamWAV or sample.get_length() <= 0.1:
				valid_samples = false
	check(variation_count == declared_variation_count and valid_samples, "Every declared WAV effect and variation is available as a real audible-length stream")
	check(audio.music_player.playing and audio.music_stream.stream_count == 2, "One music player starts both arrangements in a synchronized stream")
	var calm: AudioStreamOggVorbis = audio.music_stream.get_sync_stream(0)
	var combat: AudioStreamOggVorbis = audio.music_stream.get_sync_stream(1)
	check(calm.loop and combat.loop and absf(calm.get_length()-48.0) < 0.01 and absf(combat.get_length()-48.0) < 0.01, "Both score arrangements loop at the same forty-eight-second duration")
	audio._process(0.1)
	check(audio.music_blend == 0 and audio.music_stream.get_sync_stream_volume(1) < -70, "Build phase plays the calm arrangement")
	phases.phase = "warning"
	audio._process(1.1)
	check(is_equal_approx(audio.music_blend, 0.42), "Warning gradually introduces the combat rhythm")
	phases.phase = "attack"
	audio._process(0.1)
	check(audio.music_blend > 0.42 and audio.music_blend < 1.0, "Phase changes crossfade instead of immediately switching music")
	audio._process(3.0)
	check(audio.music_blend == 1 and audio.music_stream.get_sync_stream_volume(0) < -70, "Attack reaches the combat arrangement without restarting its clock")
	phases.phase = "salvage"
	audio._process(3.0)
	check(audio.music_blend == 0, "Salvage returns smoothly to the calm arrangement")
	audio.set_dialogue_active(true)
	audio._process(1.0)
	check(audio._dialogue_active and is_equal_approx(audio._score_level, -13.0), "Existing story calls still lower the music by six decibels")
	audio.set_dialogue_active(true, "air_intro")
	audio.set_dialogue_active(false)
	paused = true
	audio._process(1.0)
	check(audio._dialogue_active and is_equal_approx(audio._score_level, -17.0), "Pausing story dialogue preserves intro ducking and the normal pause mix")
	audio.set_dialogue_active(false, "unknown_owner")
	check(audio._dialogue_active and audio._dialogue_sources.size() == 3, "Unknown sources cannot release dialogue ducking or grow its bounded owner set")
	audio.set_dialogue_active(true, "air_intro")
	audio.set_dialogue_active(true, "air_intro")
	audio.set_dialogue_active(false, "air_intro")
	audio._process(2.0)
	check(not audio._dialogue_active and is_equal_approx(audio._score_level, -11.0), "One intro cleanup releases repeated activation calls while retaining pause attenuation")
	paused = false
	audio._process(2.0)
	check(is_equal_approx(audio._score_level, -7.0), "Closing the completed intro restores the unpaused music mix")
	audio.set_dialogue_active(true)
	audio.set_dialogue_active(true, "air_intro")
	audio.set_dialogue_active(false, "air_intro")
	audio._process(1.0)
	check(audio._dialogue_active and is_equal_approx(audio._score_level, -13.0), "Ending an overlapping intro preserves ongoing story speech ducking")
	audio.set_voice_volume(0)
	audio._process(2.0)
	check(audio._dialogue_active and is_equal_approx(audio._score_level, -7.0), "Muted speech leaves the music unducked without forgetting its active source")
	audio.set_voice_volume(1)
	audio._process(1.0)
	check(is_equal_approx(audio._score_level, -13.0), "Unmuting active speech restores dialogue attenuation")
	var voice_bus := AudioServer.get_bus_index("Voice")
	AudioServer.set_bus_mute(voice_bus,true)
	audio._process(2.0)
	check(audio._dialogue_active and is_equal_approx(audio._score_level,-7.0),"Native Voice bus mute restores music without releasing its ongoing dialogue owner")
	AudioServer.set_bus_mute(voice_bus,false)
	audio._process(1.0)
	check(audio._dialogue_active and is_equal_approx(audio._score_level,-13.0),"Native Voice bus unmute restores attenuation for the same active speaker")
	audio.set_dialogue_active(false)
	audio.set_dialogue_active(true, "unknown_owner")
	audio._process(2.0)
	check(not audio._dialogue_active and is_equal_approx(audio._score_level, -7.0), "Releasing the last owner restores the mix and unknown owners cannot reactivate it")
	audio.set_dialogue_active(true,"travel_intro")
	audio.set_dialogue_active(true,"story")
	audio.set_dialogue_active(false,"story")
	audio._process(1.0)
	check(audio._dialogue_active and is_equal_approx(audio._score_level,-13.0),"Travel speech retains its own music attenuation after ordinary dialogue pauses")
	audio.set_dialogue_active(false,"travel_intro")
	audio._process(2.0)
	check(not audio._dialogue_active and is_equal_approx(audio._score_level,-7.0),"Travel cleanup restores music after the final speaker finishes")
	var music_bus := AudioServer.get_bus_index("Music")
	var effects_bus := AudioServer.get_bus_index("SFX")
	audio.set_music_volume(0)
	check(AudioServer.is_bus_mute(music_bus) and not AudioServer.is_bus_mute(effects_bus), "Music can be muted while effects remain audible")
	audio.set_music_volume(0.30)
	audio.set_sfx_volume(0)
	check(not AudioServer.is_bus_mute(music_bus) and AudioServer.is_bus_mute(effects_bus), "Effects can be muted while music continues")
	check(not audio.play_sound("shot") and audio.music_player.playing, "Effect mute suppresses new voices without stopping the score")
	audio.set_sfx_volume(0.55)
	AudioServer.set_bus_mute(effects_bus,true)
	check(audio.play_sound("reload_rifle_open"),"Native SFX mute leaves the bounded real reload cue available")
	audio._process(.01)
	check(is_equal_approx(audio._handling_duck_db,0.0),"An inaudible reload on the native muted SFX bus cannot attenuate music")
	AudioServer.set_bus_mute(effects_bus,false)
	audio._process(.01)
	check(audio._handling_duck_db>0.0,"Native SFX unmute restores handling attenuation while the same reload cue remains active")
	check(audio.play_sound("mine") and not audio.play_sound("mine"), "Repeated mining sounds are throttled instead of stacking every frame")
	var first_mine: AudioStream
	for voice in audio.voices:
		if voice.get_meta("kind", "") == "mine": first_mine = voice.stream
	check(not audio.play_sound("unknown_effect"), "Unknown sound names stay silent rather than playing an unrelated beep")
	check(audio.play_sound("reload") and audio.streams["reload"] != audio.streams["build"], "Reload uses a distinct mechanical recording")
	check(audio.play_sound("alarm") and not audio.play_sound("warning"), "Phase alarm aliases share a cooldown and cannot double-trigger")
	for voice in audio.voices:
		voice.stop()
	audio.cooldowns.erase("mine")
	check(audio.play_sound("mine") and audio.voices[0].stream != first_mine, "Repeated actions rotate distinct authored sample variations")
	for i in 60:
		audio.cooldowns.clear()
		audio.play_sound(["shot", "hit", "explosion", "mine", "pickup", "reload"][i%6])
	check(audio.voices.size() == audio.MAX_VOICES and audio.get_child_count() == audio.MAX_VOICES+9 and audio.movement.get_parent() == audio and audio.movement.voices.size() == 4 and audio.aircraft_audio.voices.size()==4 and audio.machinery_audio.voices.size()==2 and audio.acoustics.spatial_listener.get_parent()==audio and audio.upgrade_audio.voices.size() == 2 and audio.live_music.get_parent() == audio and audio.menu_music.get_parent() == audio and not audio.menu_music.playing, "Heavy sound activity preserves bounded effect, contact, aircraft, research, world and menu controllers without playing a menu track in an isolated world fixture")
	audio._process(0.4)
	var settings := ConfigFile.new()
	check(settings.load(TEST_SETTINGS) == OK and is_equal_approx(settings.get_value("audio", "music"), 0.30) and is_equal_approx(settings.get_value("audio", "sfx"), 0.55), "Volume changes persist in a dedicated settings file after the debounce")
	var bus_count := AudioServer.bus_count
	var limiter_count := AudioServer.get_bus_effect_count(AudioServer.get_bus_index("Master"))
	var restarted = load("res://scripts/audio.gd").new()
	restarted.settings_path = TEST_SETTINGS
	game.add_child(restarted)
	restarted.set_process(false)
	check(is_equal_approx(restarted.music_volume, 0.30) and is_equal_approx(restarted.sfx_volume, 0.55), "A restarted scene restores saved music and effect volumes")
	check(AudioServer.bus_count == bus_count and AudioServer.get_bus_effect_count(AudioServer.get_bus_index("Master")) == limiter_count, "Scene restarts do not duplicate buses or the output limiter")
	var safety_count := 0
	var master_index := AudioServer.get_bus_index("Master")
	for effect_index in AudioServer.get_bus_effect_count(master_index):
		var effect := AudioServer.get_bus_effect(master_index, effect_index)
		if effect is AudioEffectHardLimiter and effect.ceiling_db <= -1.0 and AudioServer.is_bus_effect_enabled(master_index, effect_index):
			safety_count += 1
	check(safety_count == 1 and not AudioServer.is_bus_bypassing_effects(master_index), "Final mix retains one active minus-one-decibel ceiling alongside authored FX")
	audio.set_music_volume(-2)
	audio.set_sfx_volume(7)
	check(audio.music_volume == 0 and audio.sfx_volume == 1, "Volume APIs clamp invalid values safely")
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game, self), "Stopping a scene actually releases every synchronized and effect playback handle")
	DirAccess.remove_absolute(TEST_SETTINGS)
	print("AUDIO CHECKS: %d passed, %d failed" % [checks-failures, failures])
	quit(0 if failures == 0 else 1)
