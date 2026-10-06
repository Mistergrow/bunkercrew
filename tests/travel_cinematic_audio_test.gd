extends SceneTree
## Imported roadside recordings through the actual isolated Godot mixer.
const Sound := preload("res://scripts/travel_cinematic_sound.gd")
const Reference := preload("res://tests/audio_reference_fixture.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/vegetation-cinematics-20261004/audio"
var checks := 0
var failures := 0
var sound: Node
var scene: Node
var capture: AudioEffectCapture
var capture_index := -1
var master := -1
var sections: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	print("TRAVEL CINEMATIC AUDIO %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)

func wait_seconds(seconds: float) -> void:
	var deadline:=Time.get_ticks_usec()+roundi(seconds*1000000)
	while Time.get_ticks_usec()<deadline:
		await create_timer(.008,true,false,true).timeout

func stats(data: PackedVector2Array) -> Dictionary:
	var power:=0.0
	var left:=0.0
	var right:=0.0
	var peak:=0.0
	var finite:=true
	for value in data:
		left+=value.x*value.x
		right+=value.y*value.y
		power+=value.length_squared()
		peak=maxf(peak,maxf(absf(value.x),absf(value.y)))
		finite=finite and value.is_finite()
	return {"frames":data.size(),"rms":sqrt(power/maxf(1,data.size()*2)),
		"left_rms":sqrt(left/maxf(1,data.size())),"right_rms":sqrt(right/maxf(1,data.size())),
		"peak":peak,"finite":finite}

func segment(label: String,seconds: float=.22,settle: float=.10) -> Dictionary:
	await wait_seconds(settle)
	capture.clear_buffer()
	await wait_seconds(seconds)
	var result:=stats(capture.get_buffer(capture.get_frames_available()))
	sections[label]=result
	print("PCM ",label," ",result)
	return result

func _run() -> void:
	var args:=OS.get_cmdline_user_args()
	if (AudioServer.get_driver_name()!="Dummy" and "--native-audio" not in args) or "--no-profile-save" not in args:
		push_error("Run isolated with --audio-driver Dummy -- --no-profile-save --no-upnp")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var layout_path:=OUTPUT+"/reference-layout.tres"
	check(Reference.install(layout_path),"temporary reference layout leaves saved editor bus settings unchanged")
	master=AudioServer.get_bus_index("Master")
	capture_index=AudioServer.get_bus_effect_count(master)
	capture=AudioEffectCapture.new()
	capture.buffer_length=10.0
	AudioServer.add_bus_effect(master,capture)
	scene=Node.new()
	root.add_child(scene)
	current_scene=scene
	sound=Sound.new()
	scene.add_child(sound)
	check(sound.cue_voices.size()==3 and sound.get_child_count()==4,"one ambient and three fixed cue players bound playback allocation")
	check(sound._streams.size()==7,"all six original recordings and existing thunder preload once")
	check(sound.cue_voices.all(func(player):return player.bus=="SFX" and player.max_polyphony==1)
		and sound.ambient_voice.bus=="SFX","all actual playback follows the existing SFX bus")
	for id: String in Sound.SCENES:
		sound.begin_sequence(id,0)
		var stream: AudioStreamWAV=sound.ambient_voice.stream
		check(stream!=null and stream.stereo and stream.mix_rate==48000 and stream.loop_mode==AudioStreamWAV.LOOP_DISABLED,
			id+": genuine imported stereo scene length plays once")
		check(is_equal_approx(stream.get_length(),float(Sound.SCENES[id].duration)),id+": ambience ends at authored scene boundary")
	sound.begin_sequence("signal",0)
	sound.update_sequence("signal",0,true)
	check(sound.ambient_voice.playing and sound.cues_played==0,"fresh start begins ambience without prematurely triggering a relay contact")
	var normal:=await segment("signal ambience")
	check(normal.finite and normal.frames>6000 and normal.rms>.0005 and normal.peak<.15,"real imported ambience reaches master with finite clipping headroom")
	sound.set_dialogue_active(true)
	check(is_equal_approx(sound.ambient_voice.volume_db,-17.0),"speaking ducks the scene locally by seven dB")
	var ducked:=await segment("dialogue duck")
	check(ducked.rms>0 and ducked.rms<normal.rms*.75,"actual PCM becomes quieter while matching existing dialogue")
	sound.update_sequence("signal",.10,false)
	check(sound.ambient_voice.stream_paused,"external pause suspends actual scene stream")
	var silence:=await segment("paused",.14)
	check(silence.rms<.000001,"paused scene contributes no audible mixer samples")
	sound.update_sequence("signal",.10,true)
	check(sound.ambient_voice.playing and not sound.ambient_voice.stream_paused,"resume restores the same ambient stream")
	sound.set_muted(true)
	sound.update_sequence("signal",.20,true)
	silence=await segment("muted",.14)
	check(silence.rms<.000001 and not sound.ambient_voice.playing,"muted development transport stays silent")
	sound.set_muted(false)
	sound.update_sequence("signal",.20,true)
	check(sound.ambient_voice.playing,"unmuting resumes from current scene offset")
	sound.begin_sequence("signal",3.39)
	var played: int=sound.cues_played
	sound.update_sequence("signal",3.40,true)
	check(sound.cues_played==played+1 and sound.cue_voices[0].get_meta("kind")=="relay_lock",
		"crossing actual relay lock boundary plays its matching physical contact once")
	sound.ambient_voice.stop()
	var contact:=await segment("right relay contact",.14,.016)
	check(contact.finite and contact.rms>.0003 and contact.peak<.15,"physical cue is present in actual bounded mixer output")
	check(contact.right_rms>contact.left_rms*1.4,"actual right-hand relay is louder on the right headphone channel")
	for time in [3.42,3.44,3.46]: sound.update_sequence("signal",time,true)
	check(sound.cues_played==played+1,"repeated clock updates never retrigger the same contact")
	sound.seek(3.45)
	check(sound.cue_voices.all(func(player):return not player.playing) and not sound.ambient_voice.playing,
		"dragging preview time stops active one-shots immediately")
	sound.update_sequence("signal",3.45,false)
	check(not sound.ambient_voice.playing and sound.cues_played==played+1,"seeking while paused stays silent without new one-shots")
	sound.update_sequence("signal",3.45,true)
	await wait_seconds(.10)
	check(sound.ambient_voice.playing and sound.ambient_voice.get_playback_position()>=3.45,
		"resuming preview starts the genuine ambience at the selected offset")
	check(sound.cues_played==played+1,"resume never replays a past contact")
	sound.seek(0)
	sound.update_sequence("signal",0,true)
	sound.update_sequence("signal",3.50,true)
	check(sound.cues_played==played+1 and sound.cue_voices.all(func(player):return not player.playing),
		"late replica or large clock jump consumes missed cues without a burst")
	sound.begin_sequence("signal",.80)
	sound.update_sequence("signal",3.80,false)
	sound.update_sequence("signal",3.80,true)
	check(sound.cues_played==played+1,"hidden presentation consumes past cues before becoming visible again")
	sound.begin_sequence("storm",1.09)
	played=sound.cues_played
	sound.update_sequence("storm",1.10,true)
	sound.update_sequence("storm",1.15,true)
	check(sound.cues_played==played+2 and sound.cue_voices[0].get_meta("kind")=="branch_snap"
		and sound.cue_voices[1].get_meta("kind")=="thunder","struck-tree fracture and reused thunder use independent fixed voices")
	sound.begin_sequence("supply",1.68)
	played=sound.cues_played
	sound.update_sequence("supply",1.70,true)
	check(sound.cues_played==played+1 and sound.cue_voices[0].get_meta("kind")=="shutter",
		"pictured shutter movement gets rolling metal rather than a car door")
	sound.set_speed(4)
	check(sound.ambient_voice.pitch_scale==2 and sound.cue_voices.all(func(player):return player.pitch_scale==2),
		"development speed is clamped and applied to actual players")
	sound.set_speed(NAN)
	check(sound.ambient_voice.pitch_scale==1,"nonfinite speed safely returns to real-time playback")
	sound.set_gain(.5)
	sound.set_dialogue_active(true)
	check(absf(sound.cue_voices[0].volume_db-(-17.0-7.0+linear_to_db(.5)))<.001,
		"preview envelope and dialogue duck also affect active mechanical cues")
	sound.update_sequence("invalid",0,true)
	check(sound._scene_id.is_empty() and not sound.ambient_voice.playing
		and sound.cue_voices.all(func(player):return not player.playing),"unknown scene cannot leave previous sound playing")
	for unused in 20:
		sound.begin_sequence("signal",0)
		sound.update_sequence("signal",0,true)
		sound.seek(4.0)
	await wait_seconds(.35)
	check(sound.get_child_count()==4 and sound.get_retired_audio_playbacks().is_empty(),
		"repeated preview seeks release mixer handles without adding players")
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")),-6.0206)
		and is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Voice")),-14.89455),
		"scene never rewrites the existing fifty-percent SFX or voice bus reference")
	sound.set_gain(1.0)
	sound.begin_sequence("signal",.3)
	sound.update_sequence("signal",.3,true)
	await wait_seconds(.12)
	sound.stop_with_fade()
	check(sound._ending and sound.ambient_voice.playing,"skip begins bounded fade on existing scene voices")
	sound.set_dialogue_active(false)
	await wait_seconds(.035)
	check(sound._ending and sound.ambient_voice.volume_db<-10.0,"owned close fade lowers real player gain before stop")
	await wait_seconds(.13)
	check(not sound._ending and not sound.ambient_voice.playing and not sound.is_processing(),
		"skip tail ends within its eighty-millisecond fade and leaves no processing callback")
	sound.begin_sequence("supply",0)
	sound.update_sequence("supply",0,true)
	check(sound.ambient_voice.playing and is_equal_approx(sound.ambient_voice.volume_db,-10),
		"immediate replay after fade restores the original scene gain")
	var sfx:=AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_mute(sfx,true)
	silence=await segment("muted SFX bus",.14)
	check(silence.rms<.000001,"muting the actual SFX bus silences cinematic players")
	AudioServer.set_bus_mute(sfx,false)
	var restored:=await segment("unmuted SFX bus",.14)
	check(restored.rms>.0005,"restoring the SFX bus restores genuine cinematic PCM")
	sound.release()
	silence=await segment("released",.14)
	check(silence.rms<.000001,"closing preview releases all audible scene playback")
	AudioServer.remove_bus_effect(master,capture_index)
	capture=null
	check(await Cleanup.free_scene(scene,self),"actual playback handles and scene nodes drain during teardown")
	var file:=FileAccess.open(OUTPUT+("/runtime-native-verification.json" if "--native-audio" in args else "/runtime-verification.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"sections":sections,
		"audio_driver":AudioServer.get_driver_name(),
		"scope":"Actual AudioServer playback, fixed voice pool, scene-cue/seek/mute/pause/duck and stereo routing."},"\t"))
	file.close()
	print("TRAVEL CINEMATIC AUDIO: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
