extends SceneTree
## Saved native editor effects through actual Audio integration and mixer PCM.
## Every layout/effect write belongs to this process's isolated user:// fixture.
const Audio:=preload("res://scripts/audio.gd")
const Mix:=preload("res://scripts/audio_bus_mix.gd")
const Cleanup:=preload("res://tests/scene_cleanup.gd")
const OUTPUT:="res://artifacts/final-hardening-20261004/presentation/"
var path:="user://native-fx-%d.tres"%OS.get_process_id()
var effect_path:="user://native-effect-%d.tres"%OS.get_process_id()
var checks:=0
var failures:=0
var audio: Node
var probe: AudioStreamPlayer
var capture: AudioEffectCapture
var pending: Array[WeakRef]=[]
var measurements: Dictionary={}

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(label)

func template() -> String:
	return '[gd_resource type="AudioBusLayout" load_steps=2 format=3]\n\n[sub_resource type="AudioEffectHardLimiter" id="limit"]\npre_gain_db = 0.0\nceiling_db = -1.0\n\n[resource]\nbus/0/effect/0/effect = SubResource("limit")\nbus/0/effect/0/enabled = true\nbus/1/name = &"Music"\nbus/1/send = &"Master"\nbus/2/name = &"SFX"\nbus/2/send = &"Master"\nbus/3/name = &"Voice"\nbus/3/send = &"Master"\n'

func save_layout(effect: AudioEffect=null,channel: String="Music",enabled: bool=true,external: bool=false) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(template());file.close()
	var layout:=ResourceLoader.load(path,"AudioBusLayout",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as AudioBusLayout
	if effect!=null:
		var authored:=effect
		if external:
			check(ResourceSaver.save(effect,effect_path)==OK,"Native editor effect saves as an independent resource")
			authored=ResourceLoader.load(effect_path,"AudioEffect",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as AudioEffect
		var index: int={"Master":0,"Music":1,"SFX":2,"Voice":3}[channel]
		var slot:=1 if channel=="Master" else 0
		layout.set("bus/%d/effect/%d/effect"%[index,slot],authored)
		layout.set("bus/%d/effect/%d/enabled"%[index,slot],enabled)
	check(ResourceSaver.save(layout,path)==OK,"Native AudioBusLayout saves its authored FX through ResourceSaver")

func reload_source() -> void:
	audio.bus_mix._last_poll_usec=0
	audio._process(0.0)
	check(audio.bus_mix.baseline_db.Music==0.0,"Actual Audio poll retains the fixture's authored neutral fader")

func tone() -> AudioStreamWAV:
	var stream:=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate=44100
	stream.stereo=false
	var bytes:=PackedByteArray()
	bytes.resize(44100*2)
	for index in 44100: bytes.encode_s16(index*2,roundi(sin(index*TAU*1000.0/44100.0)*15000.0))
	stream.data=bytes
	stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
	stream.loop_end=44100
	return stream

func record(channel: String) -> Dictionary:
	probe.stop()
	await create_timer(.10).timeout
	probe.bus=channel
	capture.clear_buffer()
	probe.play()
	await create_timer(.70).timeout
	var samples:=capture.get_buffer(capture.get_frames_available())
	if probe.has_stream_playback(): pending.append(weakref(probe.get_stream_playback()))
	probe.stop()
	var start:=maxi(0,samples.size()-roundi(AudioServer.get_mix_rate()*.20))
	var power:=Vector2.ZERO
	var crossings:=0
	var previous:=0.0
	for index in range(start,samples.size()):
		var frame: Vector2=samples[index]
		power+=Vector2(frame.x*frame.x,frame.y*frame.y)
		if index>start and previous<=0.0 and frame.x>0.0: crossings+=1
		previous=frame.x
	var count:=samples.size()-start
	return {"frames":count,"left_rms":sqrt(power.x/maxi(count,1)),"right_rms":sqrt(power.y/maxi(count,1)),"frequency_hz":crossings*float(AudioServer.get_mix_rate())/maxi(count,1)}

func owned_effect(channel: String) -> AudioEffect:
	var bus:=AudioServer.get_bus_index(channel)
	for index in AudioServer.get_bus_effect_count(bus):
		var effect:=AudioServer.get_bus_effect(bus,index)
		if effect.has_meta(Mix.AUTHORED_EFFECT_META): return effect
	return null

func run() -> void:
	if AudioServer.get_driver_name()!="Dummy" or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args(): quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	save_layout()
	# Initial fixture installation precedes any live/private audio resources.
	AudioServer.set_bus_layout(ResourceLoader.load(path,"AudioBusLayout",ResourceLoader.CACHE_MODE_IGNORE_DEEP))
	audio=Audio.new();audio.bus_layout_path=path
	root.add_child(audio)
	for frame in 2: await process_frame
	audio.set_process(false)
	for player in audio.find_children("*","AudioStreamPlayer",true,false):
		if player.has_stream_playback(): pending.append(weakref(player.get_stream_playback()))
		player.stop()
	audio._stop_music();audio.menu_music.stop();audio.live_music.end_session()
	check(audio.bus_mix.watching and audio.music_volume==.5,"Editor-capable actual Audio scene watches saved layout at the unchanged midpoint")
	var master:=AudioServer.get_bus_index("Master")
	capture=AudioEffectCapture.new();capture.buffer_length=1.5
	AudioServer.add_bus_effect(master,capture)
	var capture_id:=capture.get_instance_id()
	probe=AudioStreamPlayer.new();probe.stream=tone();probe.volume_db=-12
	root.add_child(probe)
	var dry:=await record("Music")
	check(dry.frames>8000 and dry.left_rms>.01 and absf(dry.frequency_hz-1000)<20,"Actual output capture receives the native one-kilohertz reference")
	var amplify:=AudioEffectAmplify.new()
	save_layout(amplify);reload_source()
	var neutral:=await record("Music")
	check(absf(neutral.left_rms/dry.left_rms-1)<.005,"Default Amplify zero decibels remains correctly neutral")
	amplify.volume_db=6
	save_layout(amplify);reload_source()
	var amplified:=await record("Music")
	measurements.amplify={"dry":dry,"neutral":neutral,"plus_six_db":amplified}
	check(absf(amplified.left_rms/dry.left_rms-db_to_linear(6))<.01,"Saved native Amplify parameter doubles audible amplitude through actual Audio")
	var pitch:=AudioEffectPitchShift.new()
	save_layout(pitch);reload_source()
	var pitch_neutral:=await record("Music")
	check(absf(pitch_neutral.frequency_hz-1000)<25,"Default PitchShift factor one keeps audible frequency")
	pitch.pitch_scale=2
	save_layout(pitch);reload_source()
	var pitched:=await record("Music")
	measurements.pitch={"neutral":pitch_neutral,"factor_two":pitched}
	check(absf(pitched.frequency_hz-2000)<50,"Saved native PitchShift factor two changes real audible tone by one octave")
	var panner:=AudioEffectPanner.new()
	save_layout(panner,"SFX");reload_source()
	var center:=await record("SFX")
	check(absf(center.left_rms-center.right_rms)<.001,"Default native Panner center remains balanced")
	panner.pan=-1
	save_layout(panner,"SFX");reload_source()
	var left:=await record("SFX")
	measurements.pan={"center":center,"full_left":left}
	check(left.left_rms>.01 and left.right_rms<left.left_rms*.01,"Saved native Panner full-left reaches the actual left output only")
	var equalizer:=AudioEffectEQ6.new()
	save_layout(equalizer);reload_source()
	var eq_neutral:=await record("Music")
	equalizer.set("band_db/1000_hz",-18.0)
	check(equalizer.get("band_db/1000_hz")==-18.0,"Native EQ6 exposes its real editable one-kilohertz band")
	save_layout(equalizer);reload_source()
	var filtered:=await record("Music")
	measurements.equalizer={"flat":eq_neutral,"one_khz_minus_eighteen_db":filtered}
	check(filtered.left_rms/eq_neutral.left_rms<.35,"Saved native EQ6 band change attenuates real matching-frequency output")
	# External effect resources can change without any layout-byte/mtime change.
	amplify=AudioEffectAmplify.new();amplify.volume_db=3
	save_layout(amplify,"Music",true,true);reload_source()
	check(FileAccess.get_file_as_string(path).contains("ExtResource"),"Native saver actually authored an external effect dependency")
	var layout_hash:=FileAccess.get_sha256(path)
	var accepted_hash: String=audio.bus_mix.source_hash
	var external_before:=await record("Music")
	amplify.volume_db=12
	check(ResourceSaver.save(amplify,effect_path)==OK,"External effect parameter saves without rewriting AudioBusLayout")
	reload_source()
	var external_after:=await record("Music")
	measurements.external_amplify={"plus_three_db":external_before,"plus_twelve_db":external_after}
	check(FileAccess.get_sha256(path)==layout_hash and audio.bus_mix.source_hash!=accepted_hash,"Dependency content changes invalidate accepted mix while layout hash stays identical")
	check(absf(external_after.left_rms/external_before.left_rms-db_to_linear(9))<.02,"Saved external FX parameter changes actual output by nine decibels")
	accepted_hash=audio.bus_mix.source_hash
	var broken:=FileAccess.open(effect_path,FileAccess.WRITE)
	broken.store_string('[gd_resource type="AudioEffectAmplify" format=3]\n\n[resource]\nvolume_db = ');broken.close()
	reload_source()
	var retained:=owned_effect("Music") as AudioEffectAmplify
	check(audio.bus_mix.source_hash==accepted_hash and retained!=null and retained.volume_db==12,"Incomplete external effect save retains the last good FX without native loader errors")
	amplify.volume_db=-6
	check(ResourceSaver.save(amplify,effect_path)==OK,"Complete external editor save recovers after truncated intermediate write")
	reload_source()
	retained=owned_effect("Music") as AudioEffectAmplify
	check(retained!=null and retained.volume_db==-6,"Recovered external source adopts its exact new parameter")
	var captures:=0
	for index in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master,index).get_instance_id()==capture_id: captures+=1
	check(captures==1,"Every native/external edit retains the same active output capture once")
	probe.stop();probe.queue_free()
	for index in range(AudioServer.get_bus_effect_count(master)-1,-1,-1):
		if AudioServer.get_bus_effect(master,index)==capture: AudioServer.remove_bus_effect(master,index)
	capture=null
	check(await Cleanup.free_scene(audio,self),"Actual Audio graph retires cleanly")
	var deadline:=Time.get_ticks_msec()+4000
	while pending.any(func(handle: WeakRef):return handle.get_ref()!=null) and Time.get_ticks_msec()<deadline: await create_timer(.01).timeout
	check(not pending.any(func(handle: WeakRef):return handle.get_ref()!=null),"Reference tones and initial recorded decoders retire before test exit")
	DirAccess.remove_absolute(path);DirAccess.remove_absolute(effect_path)
	var report:=FileAccess.open(OUTPUT+"native-fx-verification.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements,"prepared_state":"Actual Audio owner, isolated ResourceSaver-authored layout/effects, one-kilohertz reference through actual retained output mixer capture. User editor, source bus layout and profiles untouched."},"\t")+"\n")
	print("NATIVE AUDIO FX FOLLOWUP: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
