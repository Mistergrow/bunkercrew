class_name BetaLiveMusicExportCheck
extends SceneTree
## Run from an empty directory with --main-pack on the actual exported platform.
## Native PCM/profile checks and real Godot mixer playback share the same pack.
const Runtime := preload("res://scripts/live_music.gd")
const Themes := preload("res://scripts/music_theme_catalog.gd")
const Genres := preload("res://scripts/music_genre_catalog.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
var beats := 0
var accents := 0
var finite_events := true

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Export diagnostics require --no-profile-save")
		quit(1)
		return
	check(ClassDB.class_exists("TesselStream"),"Native TesselStream class loads from the exported library")
	if not ClassDB.class_exists("TesselStream"):
		print("BETA LIVE MUSIC FAILED: %d checks" % checks)
		quit(1)
		return
	check(Themes.THEMES.size() == 13,"All thirteen authored music themes survive export")
	var signatures: Dictionary = {}
	for id: String in Themes.THEMES:
		var stream: AudioStream = ClassDB.instantiate("TesselStream")
		var settings := Themes.native_settings(id)
		var theme_seed := Themes.seed_for(id,17029)
		stream.call("set_theme",theme_seed,settings)
		check(is_equal_approx(float(stream.call("bpm")),float(settings.bpm)),id+" retains its resolved genre tempo")
		check(int(stream.call("beats_per_bar")) == 4,id+" retains the four-beat meter")
		var metadata: Dictionary = stream.call("metadata")
		check(int(metadata.get("seed",0)) == theme_seed,id+" receives its deterministic theme seed")
		var rate := int(stream.call("mix_rate"))
		check(rate >= 22050 and rate <= 192000,id+" native sample rate is valid")
		var sample_count := int(rate / 10.0)
		var samples: PackedFloat32Array = stream.call("render_offline",sample_count)
		var finite := true
		var peak := 0.0
		for sample: float in samples:
			finite = finite and is_finite(sample)
			peak = maxf(peak,absf(sample))
		check(samples.size() == sample_count*2 and finite and peak > 0.0001 and peak < 1.0,id+" produces finite, audible, limited native stereo PCM")
		var fingerprint := samples.to_byte_array().hex_encode().sha256_text()
		check(not signatures.has(fingerprint),id+" has a distinct exported opening")
		signatures[fingerprint] = true
	for id: String in Themes.THEMES:
		for genre: String in Genres.GENRES:
			var stream: AudioStream = ClassDB.instantiate("TesselStream")
			var settings := Themes.native_settings(id,{},genre)
			var theme_seed := Themes.seed_for(id,17029)
			stream.call("set_theme",theme_seed,settings)
			var metadata: Dictionary = stream.call("metadata")
			check(int(metadata.get("genre",-1))==int(Genres.NATIVE_IDS[genre]) and is_equal_approx(float(stream.call("bpm")),float(settings.bpm)),id+" / "+genre+" preserves its native genre and resolved tempo")
			var rate := int(stream.call("mix_rate"))
			var sample_count := int(rate / 20.0)
			var samples: PackedFloat32Array = stream.call("render_offline",sample_count)
			var finite := true
			var peak := 0.0
			for sample: float in samples:
				finite = finite and is_finite(sample)
				peak = maxf(peak,absf(sample))
			check(samples.size()==sample_count*2 and finite and peak>0.0001 and peak<1.0,id+" / "+genre+" produces finite audible exported stereo PCM")
	var runtime := Runtime.new()
	runtime.publish_shader_pulse = false
	root.add_child(runtime)
	runtime.set_mix_level_db(-30.0)
	runtime.beat.connect(func(_bar: int,_beat: int,strength: float):
		beats += 1
		finite_events = finite_events and is_finite(strength))
	runtime.accent.connect(func(_track: int,strength: float):
		accents += 1
		finite_events = finite_events and is_finite(strength))
	check(runtime.start_preview("ash_foundry",17029,-1.0,2,"minimal_techno"),"The exported AudioStreamPlayer opens actual stage-two native mixer playback")
	check(runtime.native_active and runtime.player.playing,"Native playback is active instead of OGG fallback")
	if runtime.native_active:
		var deadline := Time.get_ticks_msec() + 2200
		while Time.get_ticks_msec() < deadline:
			runtime.tick(1.0/120.0,true)
			await create_timer(1.0/120.0).timeout
		check(int(runtime.native_stream.call("mixed_samples")) > 48000,"Mixer callback advances the native sample counter")
		check(runtime.rhythm_frame().active and is_finite(runtime.clock.audible_seconds) and runtime.clock.audible_seconds > 0.5,"Exported visual clock follows actual audible output")
		check(beats >= 2 and accents >= 1 and finite_events,"Native mixer events dispatch finite audible beat/accent notifications")
		check(runtime.clock.pending_count() < 128,"Exported native event polling remains bounded")
	check(await Cleanup.free_scene(runtime,self),"Exported native playback and its retired handles release cleanly")
	print("BETA LIVE MUSIC %s: %d/%d checks passed" % ["PASSED" if failures == 0 else "FAILED",checks-failures,checks])
	quit(1 if failures else 0)
