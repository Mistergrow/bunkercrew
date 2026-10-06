extends SceneTree
## Real room/wall physics and real mixer output, never an auditory assertion.
const ACOUSTICS := preload("res://scripts/environment_acoustics.gd")
const CLEANUP := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/environment-acoustics"
var checks := 0
var failures := 0
var game: Node2D
var audio: Node
var capture: AudioEffectCapture
var capture_bus := -1
var capture_effect := -1
var base_buses := 0
var measurements: Dictionary = {}

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	print("ACOUSTICS %s: %s" % ["PASS" if value else "FAIL", label])
	if not value:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func place(first: Vector2, second: Vector2) -> void:
	game.players[0].global_position = first
	game.players[1].global_position = second
	await physics_frame
	await physics_frame
	game.weather.collision.invalidate()

func reset_mix() -> void:
	for voice in audio.voices: voice.stop()
	audio.acoustics.release()
	audio.acoustics = ACOUSTICS.new()
	audio.acoustics.setup(audio)
	audio.cooldowns.clear()
	audio._variant_bags.clear()
	audio._last_variants.clear()
	check(AudioServer.bus_count == base_buses, "Disposing the acoustic mix releases every private bus")

func silence() -> void:
	for voice in audio.voices: voice.stop()
	await create_timer(.1).timeout
	capture.clear_buffer()

func recorded(name: String, listener: Vector2, source: Vector2, seconds: float = 2.4) -> PackedVector2Array:
	await place(listener, listener)
	reset_mix()
	audio._variant_bags["explosion"] = [0]
	await silence()
	check(audio.play_sound_at("explosion", source), name + ": positioned original explosion starts")
	await create_timer(seconds).timeout
	var samples := capture.get_buffer(capture.get_frames_available())
	check(samples.size() > AudioServer.get_mix_rate() * seconds * .8, name + ": captures actual mixer output")
	measurements[name] = stats(samples)
	save_wav(OUTPUT + "/" + name + ".wav", samples)
	return samples

func stats(samples: PackedVector2Array) -> Dictionary:
	var energy := Vector2.ZERO
	var difference := 0.0
	var peak := 0.0
	var previous := Vector2.ZERO
	var tail := 0.0
	for index in samples.size():
		var value := samples[index]
		energy += Vector2(value.x*value.x, value.y*value.y)
		difference += (value-previous).length_squared()
		peak = maxf(peak, maxf(absf(value.x), absf(value.y)))
		if index > int(AudioServer.get_mix_rate() * 1.3): tail += value.length_squared()
		previous = value
	return {"frames":samples.size(), "rms":sqrt((energy.x+energy.y)/maxf(1.0,samples.size()*2.0)),
		"peak":peak, "left_energy":energy.x, "right_energy":energy.y,
		"high_frequency_ratio":difference/maxf(.0000001, energy.x+energy.y), "tail_energy":tail}

func save_wav(path: String, samples: PackedVector2Array) -> void:
	var bytes := PackedByteArray()
	bytes.resize(samples.size()*4)
	for index in samples.size():
		bytes.encode_s16(index*4, roundi(clampf(samples[index].x,-1,1)*32767))
		bytes.encode_s16(index*4+2, roundi(clampf(samples[index].y,-1,1)*32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = true
	stream.mix_rate = roundi(AudioServer.get_mix_rate())
	stream.data = bytes
	check(stream.save_to_wav(ProjectSettings.globalize_path(path)) == OK, "A reproducible captured WAV is available for " + path.get_file())

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(2, {"environment":"sector07", "position":"left", "build_type":"bastion"})
	game.rounds.running = false
	for frame in 3: await physics_frame
	freeze(game)
	# Free-mode world introductions may already be speaking before the freeze.
	# Stop that unrelated recording before measuring isolated explosion acoustics.
	if is_instance_valid(game.dialogue): game.dialogue.reset()
	audio = game.audio
	audio.set_music_volume(0)
	audio.set_sfx_volume(.65)
	audio.movement.stop_effects()
	audio.acoustics.release()
	audio.acoustics = ACOUSTICS.new()
	audio.acoustics.setup(audio)
	base_buses = AudioServer.bus_count
	capture = AudioEffectCapture.new()
	capture.buffer_length = 5.0
	capture_bus = AudioServer.get_bus_index("Master")
	capture_effect = AudioServer.get_bus_effect_count(capture_bus)
	AudioServer.add_bus_effect(capture_bus, capture)

	await place(Vector2(1020,430), Vector2(1020,430))
	audio.acoustics._probe_listener()
	check(audio.acoustics.exposure == 1.0, "Both actual listeners outside the bunker are exposed")
	await place(Vector2(510,430), Vector2(510,430))
	audio.acoustics._probe_listener()
	check(audio.acoustics.exposure == 0.0, "Actual solid bunker roof shields both listeners")
	audio.acoustics.indoor_mix = 0.0
	audio.acoustics.update(.02)
	check(audio.acoustics.indoor_mix > 0 and audio.acoustics.indoor_mix < .2, "Room tone interpolates across the entrance rather than switching in one frame")
	await place(Vector2(510,430), Vector2(1020,430))
	audio.acoustics._probe_listener()
	check(audio.acoustics.exposure == .5 and audio.acoustics.listener_ids == [1,2], "Local shared-screen cooperative listeners use the mean of their two environments")
	game.network.active = true
	game.network.local_player_id = 2
	audio.acoustics._probe_listener()
	check(audio.acoustics.exposure == 1.0 and audio.acoustics.listener_ids == [2], "A network guest hears its own outdoor position, independent of the remote indoor partner")
	game.network.local_player_id = 1
	audio.acoustics._probe_listener()
	check(audio.acoustics.exposure == 0.0 and audio.acoustics.listener_ids == [1], "A network host hears its own bunker interior")
	game.network.active = false

	await recorded("explosion-outside", Vector2(1020,430), Vector2(995,398))
	await recorded("explosion-inside", Vector2(510,430), Vector2(485,398))
	await recorded("explosion-outside-wall", Vector2(690,430), Vector2(780,398))
	var doorway: Node = null
	for wall in get_nodes_in_group("walls"):
		if absf(wall.global_position.x-722.0) < 1.0: doorway = wall
	check(is_instance_valid(doorway), "The actual front defensive wall is available for an open-door control")
	if is_instance_valid(doorway):
		doorway.collider.disabled = true
		await recorded("explosion-open-door", Vector2(690,430), Vector2(780,398))
		doorway.collider.disabled = false
	var outside: Dictionary = measurements["explosion-outside"]
	var inside: Dictionary = measurements["explosion-inside"]
	var wall: Dictionary = measurements["explosion-outside-wall"]
	check(float(inside.tail_energy) > maxf(.000001, float(outside.tail_energy)*2.0), "The concrete room creates a measured reflection tail beyond the original explosion sample")
	check(float(wall.rms) < float(inside.rms)*.65 and float(wall.high_frequency_ratio) < float(inside.high_frequency_ratio)*.7, "A real intervening bunker wall attenuates and low-pass filters the explosion")
	if measurements.has("explosion-open-door"):
		var open: Dictionary = measurements["explosion-open-door"]
		check(float(wall.rms) < float(open.rms)*.6 and float(wall.high_frequency_ratio) < float(open.high_frequency_ratio)*.7, "Removing the actual wall restores level and high frequencies at exactly the same listener and source positions")
	check(float(outside.peak) < .98 and float(inside.peak) < .98 and float(wall.peak) < .98, "Captured original explosions retain headroom in all three environments")

	await recorded("explosion-left", Vector2(1020,430), Vector2(720,398), 1.4)
	await recorded("explosion-right", Vector2(1020,430), Vector2(1320,398), 1.4)
	check(float(measurements["explosion-left"].left_energy) > float(measurements["explosion-left"].right_energy)*1.5, "Positioned sources to the left produce measurably greater left-channel energy")
	check(float(measurements["explosion-right"].right_energy) > float(measurements["explosion-right"].left_energy)*1.5, "Positioned sources to the right produce measurably greater right-channel energy")
	reset_mix()
	for index in audio.MAX_VOICES:
		audio.cooldowns.clear()
		check(audio.play_sound_at("explosion", Vector2(1100+index,398)), "Bounded voice receives a positioned event")
	check(audio.voices.size() == 12 and audio.acoustics._lanes.size() <= 12 and AudioServer.bus_count <= base_buses+13, "A burst remains bounded to twelve effect players, twelve lanes and one room return")
	audio.cooldowns.clear()
	check(audio.play_sound("warning"), "Priority warning remains available in a full environmental mix")
	var warning: AudioStreamPlayer = null
	for voice in audio.voices:
		if voice.get_meta("kind") == "warning": warning = voice
	check(is_instance_valid(warning) and warning.bus == "SFX", "Warning bypasses room filtering while preserving the SFX volume control")
	check(audio.music_player.bus == "Music" and AudioServer.get_bus_send(AudioServer.get_bus_index("Voice")) == "Master", "Music and dialogue remain separate from world acoustic filtering")
	await silence()
	audio.cooldowns.clear()
	audio.play_sound_at("explosion", Vector2(1020,405))
	await create_timer(.08).timeout
	var current: AudioStreamPlayer = audio.voices[0]
	var before_pause := current.get_playback_position()
	var room_before: float = audio.acoustics.indoor_mix
	paused = true
	audio.acoustics.update(.5)
	await create_timer(.15, true).timeout
	capture.clear_buffer()
	await create_timer(.1, true).timeout
	check(current.has_stream_playback() and absf(current.get_playback_position()-before_pause) < .03 and audio.acoustics.indoor_mix == room_before, "Pause preserves the actual active playback and freezes acoustic transitions")
	check(float(stats(capture.get_buffer(capture.get_frames_available())).rms) < .000001, "Paused world playback and its reverb return are silent")
	check(not audio.play_sound_at("explosion", Vector2(1020,405)), "Paused simulation cannot start a new world sound")
	paused = false
	audio.acoustics.update(.01)
	audio.set_sfx_volume(0)
	await create_timer(.08).timeout
	capture.clear_buffer()
	await create_timer(.1).timeout
	check(float(stats(capture.get_buffer(capture.get_frames_available())).rms) < .000001 and not audio.play_sound_at("explosion", Vector2.ZERO), "F4 SFX mute silences dry sound and room reflections and blocks new events")
	audio.set_voice_volume(.27)
	# --no-profile-save deliberately blocks the real player preference file.
	# Exercise persistence only through this isolated, disposable test path.
	var saved_settings_path: String = audio.settings_path
	audio.settings_path = "user://acoustics-dialogue-audit-%d.cfg" % OS.get_process_id()
	audio.persistence_enabled = true
	audio.save_settings()
	check(audio.voice_volume == .27 and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Voice")), "Dialogue volume remains independent from a muted world")
	var settings := ConfigFile.new()
	check(settings.load(audio.settings_path) == OK and is_equal_approx(float(settings.get_value("audio","voice",-1)), .27), "The dedicated dialogue volume is persisted with existing sound settings")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(audio.settings_path))
	audio.persistence_enabled = false
	audio.settings_path = saved_settings_path
	audio.set_voice_volume(NAN)
	check(audio.voice_volume == .27, "A malformed dialogue volume cannot corrupt the Voice bus")
	audio.set_dialogue_active(true)
	audio._process(.3)
	var ducked: float = audio._score_level
	audio.set_dialogue_active(false)
	audio._process(.1)
	check(ducked <= -12.5 and audio._score_level > ducked and audio._score_level < -7.0, "Spoken dialogue smoothly lowers music and releases it gradually")
	audio.set_dialogue_active(true)
	audio.set_voice_volume(0)
	audio._process(2)
	check(is_equal_approx(audio._score_level, -7) and AudioServer.is_bus_mute(AudioServer.get_bus_index("Voice")), "Muted dialogue leaves the music at its ordinary level")
	check(not audio.play_sound_at("explosion", Vector2(INF,0)), "Non-finite world positions are rejected")
	FileAccess.open(OUTPUT+"/mixer-measurements.json", FileAccess.WRITE).store_string(JSON.stringify({"mix_rate":AudioServer.get_mix_rate(),"recordings":measurements,"fixture":"Actual main scene, prepared positions, fixed original explosion_01 recording; physical roof and wall queries; captured Master output after room DSP, SFX volume and the output limiter"}, "\t"))
	AudioServer.remove_bus_effect(capture_bus, capture_effect)
	check(await CLEANUP.free_scene(game, self), "Native playback handles release on scene teardown")
	check(AudioServer.bus_count == base_buses, "Scene teardown removes every owned acoustic bus")
	print("ENVIRONMENT ACOUSTICS: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
