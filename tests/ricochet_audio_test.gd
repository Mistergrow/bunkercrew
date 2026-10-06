extends SceneTree
## Shipping ricochets decoded by the native mixer and admitted by real world audio.
const Audio := preload("res://scripts/audio.gd")
const Catalog := preload("res://scripts/audio_catalog.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/ricochet-audio-20261005/runtime-validation/native"
const SHIPPING := {
	"ricochet_metal": ["ricochet_metal_01.wav", "ricochet_metal_02.wav"],
	"ricochet_stone": ["ricochet_stone_01.wav"],
}

class Actor extends Node2D:
	var player_id := 1
class Phase extends Node:
	var phase := "build"
class World extends Node2D:
	var started := true
	var players: Array[Node2D] = []
	var camera: Camera2D
	var rounds: Node
	var audio: Node
	var retired_playbacks: Array[WeakRef] = []
	func get_retired_audio_playbacks() -> Array[WeakRef]:
		return retired_playbacks

var checks := 0
var failures := 0
var game: World
var audio: Node
var capture: AudioEffectCapture
var master_capture: AudioEffectCapture
var hearing := PackedVector2Array()
var measurements: Dictionary = {}
var events: Array[Dictionary] = []
var reference_path := "user://ricochet-audio-reference-%d.tres" % OS.get_process_id()

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("RICOCHET AUDIO %s: %s" % ["PASS" if value else "FAIL", label])
	if not value:
		failures += 1
		push_error(label)

func _wait(seconds: float) -> void:
	# Headless timers can run faster than the audio thread. Measure real time.
	var deadline := Time.get_ticks_usec() + roundi(seconds * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		await create_timer(0.008, true, false, true).timeout

func _stats(samples: PackedVector2Array) -> Dictionary:
	var energy := Vector2.ZERO
	var peak := 0.0
	var finite := true
	for sample: Vector2 in samples:
		finite = finite and sample.is_finite()
		energy += Vector2(sample.x * sample.x, sample.y * sample.y)
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	energy /= maxf(1.0, samples.size())
	return {"frames": samples.size(), "left": energy.x, "right": energy.y,
		"rms": sqrt((energy.x + energy.y) * 0.5), "peak": peak, "finite": finite}

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children():
		_freeze(child)

func _stop_voices() -> void:
	for voice: AudioStreamPlayer in audio.voices:
		# A stop hides the decoder from its player before the mixer retires it.
		if voice.has_stream_playback():
			game.retired_playbacks.append(weakref(voice.get_stream_playback()))
		voice.stop()

func _last_voice() -> AudioStreamPlayer:
	for voice: AudioStreamPlayer in audio.voices:
		if int(voice.get_meta("serial", -1)) == audio._voice_serial:
			return voice
	return null

func _record_world(kind: String, offset: Vector2) -> Dictionary:
	_stop_voices()
	await _wait(0.3)
	var source: Vector2 = audio.acoustics.refresh_listener_position() + offset
	audio.cooldowns.clear()
	capture.clear_buffer()
	master_capture.clear_buffer()
	var accepted: bool = audio.play_sound_at(kind, source)
	var voice := _last_voice()
	check(accepted and is_instance_valid(voice), kind + ": real world contact starts a shipping sample")
	if is_instance_valid(voice):
		var lane: Dictionary = audio.acoustics._lanes[audio.voices.find(voice)]
		var lane_bus := AudioServer.get_bus_index(voice.bus)
		var room_bus := AudioServer.get_bus_index(audio.acoustics.room_bus)
		check(voice.get_meta("acoustic_source") == source and voice.bus == lane.bus
			and AudioServer.get_bus_send(lane_bus) == audio.acoustics.room_bus
			and AudioServer.get_bus_send(room_bus) == "SFX", kind + ": unchanged world point routes through WorldAcoustics into SFX")
		check(is_equal_approx(voice.volume_db, Catalog.effect_level_db(kind))
			and signf(float(lane.target_pan)) == signf(offset.x), kind + ": authored gain and pan match the actual contact")
	await _wait(0.85)
	var result := _stats(capture.get_buffer(capture.get_frames_available()))
	var audible_mix := master_capture.get_buffer(master_capture.get_frames_available())
	var segment_start := float(hearing.size()) / AudioServer.get_mix_rate()
	hearing.append_array(audible_mix)
	var gap := PackedVector2Array()
	gap.resize(roundi(AudioServer.get_mix_rate() * 0.15))
	hearing.append_array(gap)
	check(result.finite and result.frames > 2000 and result.rms > 0.000001,
		kind + ": the real spatially filtered ricochet reaches the native SFX mixer")
	events.append({"kind": kind, "source": [source.x, source.y],
		"listener": [audio.acoustics.listener_position.x, audio.acoustics.listener_position.y],
		"measurement": result, "master_output": _stats(audible_mix), "preview_start_seconds": segment_start})
	return result

func _save_hearing() -> void:
	var bytes := PackedByteArray()
	bytes.resize(hearing.size() * 4)
	for index in hearing.size():
		bytes.encode_s16(index * 4, roundi(clampf(hearing[index].x, -1.0, 1.0) * 32767.0))
		bytes.encode_s16(index * 4 + 2, roundi(clampf(hearing[index].y, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.mix_rate = roundi(AudioServer.get_mix_rate())
	wav.stereo = true
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.data = bytes
	check(wav.save_to_wav(ProjectSettings.globalize_path(OUTPUT + "/ricochet-stereo-mix.wav")) == OK,
		"Actual fifty-percent SFX and unchanged Master output is saved without loudness normalization")

func _run() -> void:
	if AudioServer.get_driver_name() != "Dummy" or "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Run the isolated native proof with --audio-driver Dummy -- --no-profile-save.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	check(preload("res://tests/audio_reference_fixture.gd").install(reference_path),
		"Private reference buses isolate native playback from a live editor's FX and preferences")
	check(int(Catalog.VARIANT_COUNTS.get("ricochet_metal", 0)) == 2
		and int(Catalog.VARIANT_COUNTS.get("ricochet_stone", 0)) == 1,
		"The shipping ricochet bank has two metal variations and one stone variation")
	var probe_bus := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(probe_bus, "RicochetUnityProbe")
	AudioServer.set_bus_send(probe_bus, "Master")
	capture = AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(probe_bus, capture)
	var probe := AudioStreamPlayer.new()
	probe.bus = "RicochetUnityProbe"
	root.add_child(probe)
	for kind: String in SHIPPING:
		for filename: String in SHIPPING[kind]:
			probe.stream = load("res://assets/audio/" + filename)
			check(probe.stream is AudioStreamWAV and probe.stream.get_length() > 0.1,
				filename + ": a shipping WAV decodes rather than a generated test waveform")
			capture.clear_buffer()
			probe.play()
			await _wait(probe.stream.get_length() + 0.15)
			var result := _stats(capture.get_buffer(capture.get_frames_available()))
			measurements[filename] = result
			check(result.finite and result.frames > 2000 and result.rms > 0.005,
				filename + ": native PCM is finite and audibly non-silent")
			check(result.peak > 0.1 and result.peak < 0.85,
				filename + ": native unity-gain decoding retains headroom")
			probe.stop()
	probe.queue_free()
	await process_frame
	AudioServer.remove_bus(probe_bus)
	capture = null
	game = World.new()
	root.add_child(game)
	current_scene = game
	game.rounds = Phase.new()
	game.add_child(game.rounds)
	game.camera = Camera2D.new()
	game.camera.position = Vector2(1500, 250)
	game.camera.zoom = Vector2.ONE * 2.0
	game.add_child(game.camera)
	game.camera.make_current()
	var actor := Actor.new()
	actor.position = Vector2(800, 450)
	game.add_child(actor)
	game.players.append(actor)
	audio = Audio.new()
	game.audio = audio
	game.add_child(audio)
	await process_frame
	_freeze(game)
	audio.set_music_volume(0.0)
	audio.set_voice_volume(0.0)
	audio.menu_music.stop()
	audio.live_music.end_session()
	for deck: AudioStreamPlayer in audio.music_players:
		deck.stop()
	audio.movement.stop_effects()
	audio.aircraft_audio.stop_effects()
	audio.upgrade_audio.stop_effects()
	var base_bus_count := AudioServer.bus_count
	for kind: String in SHIPPING:
		var choices: Array = audio.variants.get(kind, [])
		var loaded: bool = choices.size() == SHIPPING[kind].size()
		for sample: AudioStream in choices:
			loaded = loaded and sample is AudioStreamWAV
		check(loaded, kind + ": actual BunkerAudio caches every authored shipping sample")
	var sfx_bus := AudioServer.get_bus_index("SFX")
	var capture_slot := AudioServer.get_bus_effect_count(sfx_bus)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(sfx_bus, capture)
	var master_bus := AudioServer.get_bus_index("Master")
	var master_slot := AudioServer.get_bus_effect_count(master_bus)
	master_capture = AudioEffectCapture.new()
	master_capture.buffer_length = 2.0
	AudioServer.add_bus_effect(master_bus, master_capture)
	for kind: String in SHIPPING:
		var left := await _record_world(kind, Vector2(-360, 0))
		var right := await _record_world(kind, Vector2(360, 0))
		check(left.left > left.right * 2.0 and right.right > right.left * 2.0,
			kind + ": the captured ricochet reaches its matching ear despite camera offset and zoom")
	_stop_voices()
	audio.cooldowns.clear()
	var point: Vector2 = audio.acoustics.listener_position
	check(audio.play_sound_at("impact_metal", point) and audio.play_sound_at("ricochet_metal", point),
		"A metal strike and its ricochet have independent cooldowns at the same contact")
	check(not audio.play_sound_at("ricochet_metal", point),
		"A duplicated ricochet at the same contact is throttled")
	check(audio.play_sound_at("ricochet_metal", point + Vector2(64, 0)),
		"A different physical contact can ricochet in the same frame")
	_stop_voices()
	audio.cooldowns.clear()
	check(audio.play_sound_at("impact_stone", point) and audio.play_sound_at("ricochet_stone", point),
		"A stone strike and its ricochet also retain independent cooldowns")
	var last_sample: AudioStream = null
	var distinct_samples: Array[AudioStream] = []
	var no_adjacent_repeat := true
	for _index in 10:
		_stop_voices()
		audio.cooldowns.clear()
		audio.play_sound_at("ricochet_metal", point)
		var voice := _last_voice()
		no_adjacent_repeat = no_adjacent_repeat and voice.stream != last_sample
		last_sample = voice.stream
		if not distinct_samples.has(last_sample):
			distinct_samples.append(last_sample)
	check(no_adjacent_repeat and distinct_samples.size() == 2,
		"Actual admitted metal ricochets alternate distinct recordings across shuffled bag refills")
	_stop_voices()
	audio.cooldowns.clear()
	for index in 250:
		_stop_voices()
		audio.play_sound_at("ricochet_metal", point + Vector2(index * 40.0, 0))
	check(audio.voices.size() == audio.MAX_VOICES and audio.cooldowns.size() == audio.MAX_COOLDOWN_KEYS
		and audio.acoustics._lanes.size() <= audio.MAX_VOICES,
		"Many ricochet contact points keep the fixed voice pool and cooldown cache bounded")
	_stop_voices()
	audio.cooldowns.clear()
	paused = true
	audio.acoustics.update(0.01)
	check(not audio.play_sound_at("ricochet_metal", point)
		and not audio.play_sound_at("ricochet_stone", point), "A paused game admits neither ricochet bank")
	paused = false
	audio.acoustics.update(0.01)
	audio.set_sfx_volume(0.0)
	check(not audio.play_sound_at("ricochet_metal", point)
		and not audio.play_sound_at("ricochet_stone", point), "The effects slider mute admits neither ricochet bank")
	audio.set_sfx_volume(0.5)
	AudioServer.set_bus_mute(sfx_bus, true)
	await _wait(0.2)
	master_capture.clear_buffer()
	check(audio.play_sound_at("ricochet_metal", point),
		"Native SFX bus mute preserves the established bounded voice-admission contract")
	await _wait(0.15)
	check(_stats(master_capture.get_buffer(master_capture.get_frames_available())).rms < 0.0000001,
		"A native muted SFX bus sends no ricochet output to the Master mix")
	_stop_voices()
	AudioServer.set_bus_mute(sfx_bus, false)
	check(not audio.play_sound_at("ricochet_metal", Vector2(NAN, 0)),
		"A malformed ricochet contact cannot occupy a native voice")
	_save_hearing()
	AudioServer.remove_bus_effect(sfx_bus, capture_slot)
	AudioServer.remove_bus_effect(master_bus, master_slot)
	capture = null
	master_capture = null
	check(await Cleanup.free_scene(game, self), "All actual ricochet playback handles retire during scene cleanup")
	check(AudioServer.bus_count == base_bus_count, "No ricochet lane or room bus survives its audio owner")
	DirAccess.remove_absolute(reference_path)
	var report := {"checks": checks, "failures": failures, "measurements": measurements, "events": events,
		"prepared_state": "Three shipping ricochet WAVs on a native unity bus; actual BunkerAudio with one prepared worker, off-center zoomed camera, outdoor WorldAcoustics, private reference FX, music and speech muted. Stereo preview is the unnormalized real Master output with SFX at its fifty-percent default. Tests decoding and routing, not human listening preference."}
	var file := FileAccess.open(OUTPUT + "/ricochet-native-verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("RICOCHET AUDIO: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
