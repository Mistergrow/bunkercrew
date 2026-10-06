extends SceneTree
## Decode each shipping strike through the actual native audio mixer.
const Catalog := preload("res://scripts/audio_catalog.gd")
var checks := 0
var failures := 0
var measurements: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _run() -> void:
	var bus := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus,"CoreImpactProbe")
	AudioServer.set_bus_send(bus,"Master")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(bus,capture)
	var voice := AudioStreamPlayer.new()
	voice.bus = "CoreImpactProbe"
	root.add_child(voice)
	check(Catalog.VARIANT_COUNTS.get("impact_core",0)==5,"dedicated core bank declares five variations")
	check(is_equal_approx(Catalog.effect_level_db("impact_core"),-18.0+Catalog.SHOT_HIT_GAIN_DB),"core contacts retain the established five percent hit boost")
	for variant in 5:
		var path := "res://assets/audio/impact_core_%02d.wav"%[variant+1]
		voice.stream = load(path)
		capture.clear_buffer()
		voice.play()
		await create_timer(0.34).timeout
		var samples := capture.get_buffer(capture.get_frames_available())
		var energy := 0.0
		var peak := 0.0
		var finite := true
		for sample: Vector2 in samples:
			finite = finite and sample.is_finite()
			energy += sample.length_squared()*0.5
			peak = maxf(peak,maxf(absf(sample.x),absf(sample.y)))
		var rms := sqrt(energy/maxf(1.0,samples.size()))
		check(voice.stream is AudioStreamWAV and samples.size()>2000 and finite and rms>0.015,"variant %d produces actual finite, audible native PCM"%[variant+1])
		check(peak>0.60 and peak<0.70,"variant %d retains mixer headroom before the game's additional attenuation"%[variant+1])
		measurements.append({"variant":variant+1,"native_frames":samples.size(),"peak":peak,"rms":rms,"finite":finite})
	voice.stop()
	voice.queue_free()
	await process_frame
	AudioServer.remove_bus(bus)
	var report := {"checks":checks,"failures":failures,"measurements":measurements,"prepared_state":"Five shipping core strikes, native AudioStreamWAV playback, isolated unity-gain bus, no generated test waveform"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/core-impact"))
	var file := FileAccess.open("res://artifacts/core-impact/native-mixer-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")+"\n")
	print("CORE IMPACT AUDIO: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
