extends SceneTree
## Synth-send A/B is separate from Godot bus DSP: same score, seed and timeline.
const Themes := preload("res://scripts/music_theme_catalog.gd")
const Genres := preload("res://scripts/music_genre_catalog.gd")
const OUTPUT := "res://artifacts/p1-beta-readiness-20261004/music-dance/synth-fx/"
var checks := 0
var failures := 0
var measurements: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func render(settings: Dictionary,seed_value: int,frames: int) -> Dictionary:
	var stream: AudioStream = ClassDB.instantiate("TesselStream")
	stream.call("set_theme",seed_value,settings)
	var samples: PackedFloat32Array = stream.call("render_offline",frames)
	var events: Array = stream.call("poll_events",1024)
	return {"pcm":samples,"events":events,"metadata":stream.call("metadata")}

func stats(samples: PackedFloat32Array) -> Dictionary:
	var finite := true
	var power := 0.0
	var peak := 0.0
	for sample: float in samples:
		finite = finite and is_finite(sample)
		power += sample*sample
		peak = maxf(peak,absf(sample))
	return {"samples":samples.size(),"finite":finite,"peak":peak,"rms":sqrt(power/maxi(1,samples.size())),"sha256":samples.to_byte_array().hex_encode().sha256_text()}

func save_take(samples: PackedFloat32Array,name: String,rate: int) -> void:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = rate
	var data := PackedByteArray()
	data.resize(samples.size()*2)
	for index in samples.size(): data.encode_s16(index*2,roundi(clampf(samples[index],-1.0,1.0)*32767.0))
	wav.data = data
	check(wav.save_to_wav(OUTPUT+name)==OK,"Native synth A/B take saves for optional listening: "+name)

func run() -> void:
	if AudioServer.get_driver_name()!="Dummy" or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args(): quit(2);return
	check(ClassDB.class_exists("TesselStream"),"Native synthesis backend is installed")
	if not ClassDB.class_exists("TesselStream"): quit(1);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var rate := roundi(AudioServer.get_mix_rate())
	var frames := rate*3
	for environment: String in ["ash_foundry","mountain_pass"]:
		for genre: String in Genres.GENRES:
			for stage in [0,3]:
				var settings := Themes.native_settings(environment,{},genre)
				settings.initial_intensity = stage
				var seed_value := Themes.seed_for(environment,20261004)
				var dry_settings := settings.duplicate(true)
				var wet_settings := settings.duplicate(true)
				dry_settings.effects = 0.0
				wet_settings.effects = 1.0
				var dry := render(dry_settings,seed_value,frames)
				var wet := render(wet_settings,seed_value,frames)
				var repeated := render(wet_settings,seed_value,frames)
				var label := "%s/%s/stage%d"%[environment,genre,stage]
				var dry_stats := stats(dry.pcm)
				var wet_stats := stats(wet.pcm)
				check(dry.pcm.size()==frames*2 and wet.pcm.size()==frames*2,label+": complete three-second native stereo takes")
				check(dry_stats.finite and wet_stats.finite and dry_stats.rms>0.0001 and wet_stats.rms>0.0001 and dry_stats.peak<1 and wet_stats.peak<1,label+": both native takes are finite, non-silent and limited")
				check(wet.pcm==repeated.pcm,label+": effects remain deterministic for the same score and seed")
				check(dry.events==wet.events and wet.events==repeated.events and not dry.events.is_empty(),label+": synth FX preserve the actual musical event/kick timeline")
				check(dry.metadata.bpm==wet.metadata.bpm and dry.metadata.intensity==wet.metadata.intensity and dry.metadata.mixed_samples==wet.metadata.mixed_samples,label+": effects preserve arrangement, tempo and mixed sample count")
				var difference := 0.0
				for index in dry.pcm.size(): difference += pow(float(wet.pcm[index])-float(dry.pcm[index]),2)
				var relative_difference := sqrt(difference/dry.pcm.size())/maxf(dry_stats.rms,0.000001)
				check(relative_difference>0.001,label+": native synth-send changes actual PCM independently of Godot bus FX")
				measurements.append({"environment":environment,"genre":genre,"stage":stage,"seed":seed_value,"dry":dry_stats,"wet":wet_stats,"relative_pcm_difference":relative_difference,"event_count":dry.events.size(),"tempo":wet.metadata.bpm})
				if environment=="ash_foundry" and genre=="minimal_techno" and stage==3:
					save_take(dry.pcm,"synth-dry.wav",rate)
					save_take(wet.pcm,"synth-fx.wav",rate)
	var report := FileAccess.open(OUTPUT+"verification.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements,"prepared_state":"Installed native TesselStream.render_offline, same three-second seed/score/event timeline, effects send0 vs1, two real authored environments×four genres×quiet/combat banks. No AudioServer bus layout, preferences or source music assets changed. Current Music-Labor exposes tempo/style/intensity, no dedicated FX slider; this is native synthesis parameter proof, not UI or human hearing proof."},"\t")+"\n")
	print("MUSIC SYNTHESIS FX: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
