extends SceneTree
## Real main-scene routing and same-start PCM comparisons at the master output.
## --no-profile-save isolates real profiles; only a temporary fixture file is saved.
const Catalog := preload("res://scripts/audio_catalog.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/audio-balance-adjustment"
const BOOSTED := ["shot", "enemy_shot", "shotgun", "cannon", "arc", "hit", "impact_metal", "impact_stone", "impact_wood", "glass_break", "explosion", "impact_core", "air_dart", "air_tracer", "air_rocket", "air_bomb", "air_arc", "air_crash"]
var output := "res://artifacts/solo-story/audio" if "--midpoint-review" in OS.get_cmdline_user_args() else OUTPUT
var checks := 0
var failures := 0
var game: Node
var audio: Node
var capture: AudioEffectCapture
var probe: AudioStreamPlayer
var measurements: Dictionary = {}
var settings_path := "user://audio-balance-adjustment-%d.cfg" % OS.get_process_id()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("BALANCE %s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
		push_error(label)

func wait_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_usec() + roundi(seconds * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		await create_timer(0.008, true, false, true).timeout

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children(): freeze(child)

func stop_sources() -> void:
	audio.menu_music.stop()
	audio.live_music.end_session()
	for deck: AudioStreamPlayer in audio.music_players: deck.stop()
	for voice: AudioStreamPlayer in audio.voices: voice.stop()
	audio.movement.stop_effects()
	audio.upgrade_audio.stop_effects()
	game.dialogue.reset()

func stats(samples: PackedVector2Array) -> Dictionary:
	var power := 0.0
	var peak := 0.0
	var finite := true
	for value: Vector2 in samples:
		finite = finite and value.is_finite()
		power += value.length_squared()
		peak = maxf(peak, maxf(absf(value.x), absf(value.y)))
	return {"frames": samples.size(), "rms": sqrt(power / maxf(1.0, samples.size() * 2.0)), "peak": peak, "finite": finite}

func aligned(samples: PackedVector2Array, seconds: float) -> PackedVector2Array:
	# Mixer blocks may start on different wall-clock frames. Remove only exact
	# leading silence, then compare the identical decoded section from sample 0.
	var first := -1
	for index in samples.size():
		if samples[index].length_squared() > 1.0e-24:
			first = index
			break
	if first < 0: return PackedVector2Array()
	var count := roundi(AudioServer.get_mix_rate() * seconds)
	return samples.slice(first, mini(samples.size(), first + count))

func record(stream: AudioStream, bus: String, source_db: float, section: float) -> PackedVector2Array:
	probe.stop()
	await wait_seconds(0.20)
	probe.bus = bus
	probe.stream = stream
	probe.volume_db = source_db
	capture.clear_buffer()
	probe.play(0.0)
	await wait_seconds(section + 0.35)
	var samples := capture.get_buffer(capture.get_frames_available())
	probe.stop()
	return aligned(samples, section)

func compare(label: String, before: PackedVector2Array, after: PackedVector2Array, expected: float) -> void:
	var old := stats(before)
	var updated := stats(after)
	var ratio: float = updated.rms / maxf(old.rms, 1.0e-12)
	var error_power := 0.0
	for index in mini(before.size(), after.size()):
		error_power += (after[index] - before[index] * expected).length_squared()
	var relative_error: float = sqrt(error_power / maxf(1.0, before.size() * 2.0)) / maxf(updated.rms, 1.0e-12)
	measurements[label] = {"before": old, "after": updated, "amplitude_ratio": ratio, "expected_ratio": expected, "relative_pcm_error": relative_error, "section": "Identical beginning of the real imported recording, aligned by first nonzero mixed sample."}
	print("PCM ", label, " ratio=", ratio, " error=", relative_error, " peak=", updated.peak)
	check(before.size() == after.size() and before.size() > 2000 and old.rms > 0.00001, label + ": complete matching audible sections reach the actual master mixer")
	check(old.finite and updated.finite and updated.peak < 0.89, label + ": original and adjusted real output remain finite with headroom")
	check(absf(ratio - expected) < 0.003 and relative_error < 0.003, label + ": actual sample amplitude changes by the requested factor")

func _run() -> void:
	if AudioServer.get_driver_name() != "Dummy" or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		push_error("Use --audio-driver Dummy -- --no-profile-save --no-upnp for this isolated mixer proof.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var reference_path := "user://audio-balance-reference-%d.tres" % OS.get_process_id()
	check(preload("res://tests/audio_reference_fixture.gd").install(reference_path), "Gain A/B uses an isolated reference, preserving every live editor bus edit")
	InputSetup.install()
	LocaleText.set_locale("de", false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	check(game.audio.music_volume == 0.5 and game.audio.sfx_volume == 0.5 and game.audio.voice_volume == 0.5 and game.voice.output_volume == 0.5, "Actual fresh menu preserves all four fifty-percent listening preferences")
	audio = game.audio
	game.start_scenario(1, {"environment": "mountain_pass", "position": "left", "build_type": "bastion"})
	game.rounds.running = false
	await process_frame
	freeze(game)
	var ambient_level_before: float = audio.movement.wind_player.volume_db
	stop_sources()
	paused = false
	var music_bus := AudioServer.get_bus_index("Music")
	var voice_bus := AudioServer.get_bus_index("Voice")
	var effects_bus := AudioServer.get_bus_index("SFX")
	check(absf(db_to_linear(AudioServer.get_bus_volume_db(music_bus) - linear_to_db(0.8) + 8.0) - 1.10) < 0.00001, "Default Music preserves the chosen 0.8 reference and existing ten-percent source adjustment")
	check(absf(db_to_linear(AudioServer.get_bus_volume_db(voice_bus) - linear_to_db(0.2)) - 0.90) < 0.00001, "Default Voice preserves the quieter 0.2 reference and existing ten-percent source adjustment")
	check(is_equal_approx(AudioServer.get_bus_volume_db(effects_bus), linear_to_db(0.5)), "Shared effects bus remains unchanged for footsteps, reloads and ambience")
	check(game.dialogue.voice.bus == "Voice" and game.hud.air_raid_panel.voice.bus == "Voice", "Both ordinary dialogue and the air-raid voice use the adjusted Voice bus")
	check(game.voice._player.bus == "Master" and is_equal_approx(game.voice._player.volume_db, linear_to_db(0.5)), "Partner chat retains its independent fifty-percent Master route")
	var requested: Array = Catalog.VARIANT_COUNTS.keys()
	requested.append_array(Catalog.ALIASES.keys())
	for request: String in requested:
		for voice: AudioStreamPlayer in audio.voices: voice.stop()
		audio.cooldowns.clear()
		var kind: String = Catalog.ALIASES.get(request, request)
		var accepted: bool = audio.play_sound(request)
		var selected: AudioStreamPlayer = null
		for voice: AudioStreamPlayer in audio.voices:
			if int(voice.get_meta("serial", 0)) == audio._voice_serial: selected = voice
		var gain := 20.0 * log(1.05) / log(10.0) if kind in BOOSTED else 0.0
		check(accepted and is_instance_valid(selected) and absf(selected.volume_db - float(Catalog.LEVEL_DB[kind]) - gain) < 0.0001, "Normal effect pool applies only the intended source gain: " + request)
	for voice: AudioStreamPlayer in audio.voices: voice.stop()
	audio.movement.stop_effects()
	check(audio.play_footstep("metal", audio.acoustics.listener_position, 1.0, false, true), "Actual player foot contact remains accepted through its own spatial pool")
	check(is_equal_approx(audio.movement.voices[0].volume_db, -13.0), "Player footsteps retain their authored source gain")
	audio.movement.stop_effects()
	check(is_equal_approx(audio.movement.wind_player.volume_db, ambient_level_before) and audio.movement.wind_player.bus == "SFX", "Ambient wind retains its independent source gain and unchanged effects bus")
	audio.settings_path = settings_path
	audio.persistence_enabled = true
	audio.set_music_volume(0.37)
	audio.set_voice_volume(0.72)
	audio.set_sfx_volume(0.61)
	audio.save_settings()
	var saved := ConfigFile.new()
	check(saved.load(settings_path) == OK and is_equal_approx(float(saved.get_value("audio", "music")), 0.37) and is_equal_approx(float(saved.get_value("audio", "voice")), 0.72) and is_equal_approx(float(saved.get_value("audio", "sfx")), 0.61), "Saving stores the chosen slider values without baking mix adjustments into the profile")
	audio.music_volume = 0.0
	audio.voice_volume = 0.0
	audio.sfx_volume = 0.0
	audio._load_settings()
	check(is_equal_approx(audio.music_volume, 0.37) and is_equal_approx(audio.voice_volume, 0.72) and is_equal_approx(audio.sfx_volume, 0.61), "The isolated saved slider preferences survive a normal settings reload")
	audio.set_music_volume(0.5)
	audio.set_voice_volume(0.5)
	audio.set_sfx_volume(0.5)
	if audio.acoustics != null:
		audio.acoustics.release()
		audio.acoustics = null
	await wait_seconds(0.35)
	var master := AudioServer.get_bus_index("Master")
	var capture_index := AudioServer.get_bus_effect_count(master)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 3.0
	AudioServer.add_bus_effect(master, capture)
	probe = AudioStreamPlayer.new()
	probe.name = "ActualBusBalanceProbe"
	probe.process_mode = Node.PROCESS_MODE_ALWAYS
	game.add_child(probe)
	var mountain: AudioStream = load("res://assets/audio/" + str(Catalog.MUSIC_SETS[Catalog.score_for_environment("mountain_pass")].combat))
	AudioServer.set_bus_volume_db(music_bus, linear_to_db(0.8) - 8.0)
	var before := await record(mountain, "Music", 0.0, 0.6)
	audio.set_music_volume(0.5)
	var after := await record(mountain, "Music", 0.0, 0.6)
	compare("Gewitterpass recorded music", before, after, 1.10)
	var speech: AudioStream = load(StoryDialogueCatalog.recording_path("story_open", "san", "de"))
	AudioServer.set_bus_volume_db(voice_bus, linear_to_db(0.2))
	before = await record(speech, "Voice", 0.0, 0.6)
	audio.set_voice_volume(0.5)
	after = await record(speech, "Voice", 0.0, 0.6)
	compare("Recorded in-game speech", before, after, 0.90)
	var shot: AudioStream = audio.variants.shot[0]
	before = await record(shot, "SFX", float(Catalog.LEVEL_DB.shot), 0.08)
	after = await record(shot, "SFX", Catalog.effect_level_db("shot_rifle"), 0.08)
	compare("Rifle shot", before, after, 1.05)
	for title: String in ["Music", "Voice", "SFX"]:
		match title:
			"Music": audio.set_music_volume(0.0)
			"Voice": audio.set_voice_volume(0.0)
			"SFX": audio.set_sfx_volume(0.0)
		var muted := await record(shot, title, 0.0, 0.08)
		check(muted.is_empty() and AudioServer.is_bus_mute(AudioServer.get_bus_index(title)), title + ": actual slider mute produces no mixed PCM after internal gain adjustments")
	probe.stop()
	audio.set_music_volume(1.0)
	audio.set_sfx_volume(0.0)
	audio.set_voice_volume(0.0)
	audio.persistence_enabled = false
	audio.set_process(true)
	audio.begin_live_music("mountain_pass", 0)
	game.rounds.running = false
	game.rounds.set_process(false)
	game.set_process(false)
	for actor: Node in game.players: actor.set_physics_process(false)
	await wait_seconds(0.35)
	capture.clear_buffer()
	await wait_seconds(0.7)
	var native := stats(capture.get_buffer(capture.get_frames_available()))
	measurements["Gewitterpass native at full music slider"] = native
	check(audio.live_music.native_active and audio.live_music.environment_id == "mountain_pass" and not audio.menu_music.playing and audio.music_players.all(func(deck): return not deck.playing), "Actual Gewitterpass scenario plays one native authored music source after the adjustment")
	check(native.finite and native.frames > 22050 and native.rms > 0.001 and native.peak < 0.89, "Native Gewitterpass music at full volume reaches real output with audible finite headroom")
	check(game.voice.output_volume == 0.5 and is_equal_approx(game.voice._player.volume_db, linear_to_db(0.5)), "All music and recorded-voice adjustments preserve partner chat output")
	AudioServer.remove_bus_effect(master, capture_index)
	check(await Cleanup.free_scene(game, self), "The actual scene and instrumented playback handles release cleanly")
	if FileAccess.file_exists(settings_path): DirAccess.remove_absolute(settings_path)
	DirAccess.remove_absolute(reference_path)
	var report := FileAccess.open(output + "/verification.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks": checks, "failures": failures, "measurements": measurements, "prepared_state": "Actual normal main scene; no saved profiles; all sources frozen for identical imported sample A/B routed through existing buses and Master limiter, followed by ordinary Gewitterpass native scenario startup at full Music slider.", "user_profiles_modified": false}, "\t") + "\n")
	report.close()
	print("AUDIO BALANCE ADJUSTMENT: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
