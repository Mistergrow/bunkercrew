extends SceneTree
## Fresh listening baseline, legacy gain conservation and actual mixed PCM.
const Defaults := preload("res://scripts/audio_defaults.gd")
const Catalog := preload("res://scripts/audio_catalog.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/solo-story/audio"
const LEGACY_GAINS := {"Music":0.8, "SFX":0.5, "Voice":0.2}
var checks := 0
var failures := 0
var game: Node
var probe: AudioStreamPlayer
var capture: AudioEffectCapture
var measurements: Dictionary = {}
var fixture := "user://audio-midpoint-%d.cfg" % OS.get_process_id()

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children(): freeze(child)

func stats(samples: PackedVector2Array) -> Dictionary:
	var power := 0.0
	var peak := 0.0
	for sample: Vector2 in samples:
		power += sample.length_squared()
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	return {"frames":samples.size(), "rms":sqrt(power / maxf(1.0, samples.size() * 2.0)), "peak":peak}

func record(stream: AudioStream, bus: String) -> PackedVector2Array:
	probe.stop()
	await create_timer(.15).timeout
	probe.stream = stream
	probe.bus = bus
	probe.volume_db = -12.0
	capture.clear_buffer()
	probe.play(0.0)
	await create_timer(.55).timeout
	var samples := capture.get_buffer(capture.get_frames_available())
	var pending: WeakRef = weakref(probe.get_stream_playback())
	probe.stop()
	var deadline := Time.get_ticks_msec() + 1500
	while pending.get_ref() != null and Time.get_ticks_msec() < deadline:
		await process_frame
	check(pending.get_ref() == null, "Instrumented probe retires its playback before the next take")
	for index in samples.size():
		if samples[index].length_squared() > 1.0e-24:
			return samples.slice(index, mini(samples.size(), index + roundi(AudioServer.get_mix_rate() * .12)))
	return PackedVector2Array()

func _run() -> void:
	if AudioServer.get_driver_name() != "Dummy" or "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	check(ProjectSettings.get_setting("audio/buses/default_bus_layout") == "res://default_bus_layout.tres", "Project explicitly binds its shipped AudioBusLayout")
	check(preload("res://tests/audio_reference_fixture.gd").install(fixture + ".tres"), "Listening proof installs its reference before audio owners, isolated from live editor faders")
	var master := AudioServer.get_bus_index("Master")
	check(AudioServer.get_bus_effect_count(master) == 1 and AudioServer.get_bus_effect(master, 0) is AudioEffectHardLimiter, "The actual startup layout has one final output limiter")
	var limiter: AudioEffectHardLimiter = AudioServer.get_bus_effect(master, 0)
	print("STARTUP MIX: pre_gain=",limiter.pre_gain_db," ceiling=",limiter.ceiling_db," master=",AudioServer.get_bus_volume_db(master)," music=",AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")))
	check(is_equal_approx(limiter.pre_gain_db, 6.0199986) and limiter.ceiling_db == -1.0 and AudioServer.get_bus_volume_db(master) == 0.0, "Startup output gain precedes the minus-one-decibel ceiling")
	for bus: String in LEGACY_GAINS:
		var index := AudioServer.get_bus_index(bus)
		var trim := -7.172146296835499 if bus == "Music" else -.9151498112135024 if bus == "Voice" else 0.0
		check(index >= 0 and AudioServer.get_bus_send(index) == "Master", "Editor-visible channel routes to Master: " + bus)
		check(absf(AudioServer.get_bus_volume_db(index) - linear_to_db(LEGACY_GAINS[bus]) - trim) < .00002, "Shipped channel already carries the selected reference mix: " + bus)
	InputSetup.install()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	check(game.audio.music_volume == .5 and game.audio.sfx_volume == .5 and game.audio.voice_volume == .5 and game.voice.output_volume == .5, "Actual fresh main menu starts every listening slider at fifty percent")
	game.hud._toggle_audio()
	await process_frame
	check(game.hud.sliders.size() == 3 and game.hud.sliders.all(func(slider): return slider.value == .5), "Actual options display the fresh midpoint")
	game.hud._close_audio()
	freeze(game)
	# Finish queued playback setup before isolating the imported A/B samples.
	await process_frame
	await process_frame
	game.audio.menu_music.stop()
	game.audio.live_music.end_session()
	for player in game.find_children("*", "AudioStreamPlayer", true, false): player.stop()
	for player in game.find_children("*", "AudioStreamPlayer2D", true, false): player.stop()
	for bus: String in LEGACY_GAINS:
		var trim: float = game.audio.MUSIC_MIX_TRIM_DB if bus == "Music" else game.audio.VOICE_MIX_TRIM_DB if bus == "Voice" else 0.0
		var index := AudioServer.get_bus_index(bus)
		check(absf(AudioServer.get_bus_volume_db(index) - linear_to_db(LEGACY_GAINS[bus]) - trim) < .00002, "Runtime leaves the selected startup gain intact: " + bus)
		for step in 101:
			var previous_gain := step / 100.0
			game.audio._apply_bus_volume(bus, Defaults.legacy_slider(bus, previous_gain))
			check((AudioServer.is_bus_mute(index) if step == 0 else absf(AudioServer.get_bus_volume_db(index) - linear_to_db(previous_gain) - trim) < .00003), "Legacy listening gain survives conversion %s %d" % [bus,step])
		game.audio._apply_bus_volume(bus, .5)
	check(AudioServer.get_bus_effect_count(master) == 1 and is_equal_approx(limiter.pre_gain_db, 6.0199986), "Real main scene does not duplicate the limiter or output gain")
	var old := ConfigFile.new()
	old.set_value("audio", "music", .8)
	old.set_value("audio", "sfx", .5)
	old.set_value("audio", "voice", .2)
	old.set_value("rhythm", "music_style", "hip_hop")
	old.set_value("rhythm", "calibration_seconds", .125)
	old.set_value("rhythm", "dance_intensity", 1.1)
	check(old.save(fixture) == OK, "Legacy fixture saves outside every player profile")
	game.audio.settings_path = fixture
	game.audio.persistence_enabled = true
	game.audio._load_settings()
	check(game.audio.music_volume == .5 and game.audio.sfx_volume == .5 and game.audio.voice_volume == .5, "Chosen legacy mix becomes three genuine fifty-percent slider values")
	check(game.audio.music_style == "hip_hop" and game.audio.music_calibration_seconds == .125 and game.audio.dance_intensity == 1.1, "Migration preserves separate rhythm and device settings")
	game.audio.save_settings()
	var saved := ConfigFile.new()
	check(saved.load(fixture) == OK and saved.get_value("audio", "mix_version") == 2, "Saved normalized units are versioned")
	game.audio._load_settings()
	check(game.audio.music_volume == .5 and game.audio.voice_volume == .5, "Loading normalized preferences again cannot multiply channel gain")
	probe = AudioStreamPlayer.new()
	root.add_child(probe)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(master, capture)
	var sources := {"Music":load("res://assets/audio/" + Catalog.MUSIC_SETS.base.calm), "SFX":game.audio.variants.shot[0], "Voice":load(StoryDialogueCatalog.recording_path("story_open", "san", "de"))}
	for bus: String in sources:
		var index := AudioServer.get_bus_index(bus)
		var trim: float = game.audio.MUSIC_MIX_TRIM_DB if bus == "Music" else game.audio.VOICE_MIX_TRIM_DB if bus == "Voice" else 0.0
		AudioServer.set_bus_volume_db(index, linear_to_db(LEGACY_GAINS[bus]) + trim)
		var before := await record(sources[bus], bus)
		game.audio._apply_bus_volume(bus, .5)
		var after := await record(sources[bus], bus)
		var before_stats := stats(before)
		var after_stats := stats(after)
		var ratio: float = after_stats.rms / maxf(1.0e-12, before_stats.rms)
		measurements[bus] = {"before":before_stats, "default_50_percent":after_stats, "rms_ratio":ratio}
		check(before.size() == after.size() and before.size() > 2000 and before_stats.rms > .00001, "Actual imported samples reach the output mixer: " + bus)
		check(absf(ratio - 1.0) < .001 and after_stats.peak < .89, "Actual midpoint PCM retains the chosen listening level: " + bus)
	AudioServer.remove_bus_effect(master, 1)
	probe.stop()
	probe.queue_free()
	check(await Cleanup.free_scene(game, self), "Actual options and playback retire cleanly")
	DirAccess.remove_absolute(fixture)
	DirAccess.remove_absolute(fixture + ".tres")
	var report := FileAccess.open(OUTPUT + "/defaults-verification.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks, "failures":failures, "default_sliders":[.5,.5,.5,.5], "reference_gains":LEGACY_GAINS, "measurements":measurements, "prepared_state":"Actual fresh main menu/options; real imported PCM through startup buses and final Master limiter. Legacy fixture only, no real profiles written."}, "\t") + "\n")
	print("AUDIO BUS DEFAULTS: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
