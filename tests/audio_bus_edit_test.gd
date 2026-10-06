extends SceneTree
## Real bus file reloads and imported PCM; no live layout reset or profile writes.
const Mix:=preload("res://scripts/audio_bus_mix.gd")
const Audio:=preload("res://scripts/audio.gd")
const Cleanup:=preload("res://tests/scene_cleanup.gd")
const OUTPUT:="res://artifacts/solo-story/audio/editor-buses/"
var fixture:="user://audio-editor-buses-%d.tres"%OS.get_process_id()
var checks:=0
var failures:=0
var probe: AudioStreamPlayer
var capture: AudioEffectCapture
var measurements: Dictionary={}
var retired: Array[WeakRef]=[]

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func layout_text(music: float=-24.0,sfx: float=-18.0,voice: float=-22.0,post: float=0.0,pre: float=0.0,flags: Dictionary={}) -> String:
	var text:='[gd_resource type="AudioBusLayout" load_steps=2 format=3]\n\n[sub_resource type="AudioEffectHardLimiter" id="limiter"]\nresource_name = "TestOutputCeiling"\npre_gain_db = %.9f\nceiling_db = -1.0\n\n[resource]\nbus/0/volume_db = %.9f\nbus/0/effect/0/effect = SubResource("limiter")\nbus/0/effect/0/enabled = true\n'%[pre,post]
	for index in 4:
		var title: String=["Master","Music","SFX","Voice"][index]
		var state: Dictionary=flags.get(title,{})
		if index>0:
			text+='bus/%d/name = &"%s"\nbus/%d/volume_db = %.9f\nbus/%d/send = &"Master"\n'%[index,title,index,[music,sfx,voice][index-1],index]
		for key: String in ["mute","solo","bypass_fx"]:
			text+='bus/%d/%s = %s\n'%[index,key,"true" if bool(state.get(key,false)) else "false"]
	return text

func write_source(text: String) -> void:
	var file:=FileAccess.open(fixture,FileAccess.WRITE)
	check(file!=null,"Dedicated AudioBusLayout fixture opens without changing real source")
	if file!=null: file.store_string(text);file.close()

func fx_source(channel: String,type: String,properties: String,enabled:=true) -> String:
	var index: int={"Master":0,"Music":1,"SFX":2,"Voice":3}[channel]
	var slot:=1 if channel=="Master" else 0
	var text:=layout_text(-18,-18,-22)
	text=text.replace("[resource]",'[sub_resource type="%s" id="live_fx"]\nresource_name = "Live authored FX"\n%s\n[resource]'%[type,properties])
	return text+'bus/%d/effect/%d/effect = SubResource("live_fx")\nbus/%d/effect/%d/enabled = %s\n'%[index,slot,index,slot,"true" if enabled else "false"]

func adopt(mix: RefCounted,text: String) -> void:
	write_source(text)
	mix._last_poll_usec=0
	check(mix.poll() or mix.source_hash==FileAccess.get_sha256(fixture),"Saved authored FX edit is adopted or already current without resetting live layout")
	for title: String in Mix.CHANNELS: mix.apply(title,.5)

func ratio_check(before: PackedVector2Array,after: PackedVector2Array,expected: float,label: String) -> void:
	var old:=stats(before)
	var current:=stats(after)
	var ratio: float=current.rms/maxf(old.rms,1e-12)
	measurements[label]={"before":old,"after":current,"ratio":ratio,"expected":expected}
	check(before.size()==after.size() and before.size()>2000 and old.rms>.000001,label+": both real imported sound takes reach the retained capture")
	check(absf(ratio-expected)<.003,label+": authored FX changes actual output by expected factor")

func stats(samples: PackedVector2Array) -> Dictionary:
	var power:=0.0
	var peak:=0.0
	for sample in samples:
		power+=sample.length_squared()
		peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
	return {"frames":samples.size(),"rms":sqrt(power/maxf(1.0,samples.size()*2.0)),"peak":peak}

func record(stream: AudioStream,bus: String) -> PackedVector2Array:
	probe.stop()
	await create_timer(.15).timeout
	probe.stream=stream
	probe.bus=bus
	probe.volume_db=-18.0
	capture.clear_buffer()
	probe.play(0)
	await create_timer(.55).timeout
	var samples:=capture.get_buffer(capture.get_frames_available())
	probe.stop()
	for index in samples.size():
		if samples[index].length_squared()>1e-24:
			return samples.slice(index,mini(samples.size(),index+roundi(AudioServer.get_mix_rate()*.12)))
	return PackedVector2Array()

func stop_sources(audio: Node) -> void:
	audio.set_process(false)
	for player in audio.find_children("*","AudioStreamPlayer",true,false):
		if player.has_stream_playback(): retired.append(weakref(player.get_stream_playback()))
	for player in audio.find_children("*","AudioStreamPlayer2D",true,false):
		if player.has_stream_playback(): retired.append(weakref(player.get_stream_playback()))
	audio.menu_music.stop()
	audio.live_music.end_session()
	for player in audio.find_children("*","AudioStreamPlayer",true,false): player.stop()
	for player in audio.find_children("*","AudioStreamPlayer2D",true,false):
		player.stop()
	for child in audio.get_children(): child.set_process(false)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args() or AudioServer.get_driver_name()!="Dummy": quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	write_source(layout_text())
	# A user's open editor may add/change its own FX while this runs. Install
	# only our fixture before any private buses, capture or playback exists.
	AudioServer.set_bus_layout(ResourceLoader.load(fixture,"AudioBusLayout",ResourceLoader.CACHE_MODE_IGNORE_DEEP))
	# Buses/private effects are only added individually, never reset as a layout.
	for title: String in ["Music","SFX","Voice","AudioEditorPrivate"]:
		if AudioServer.get_bus_index(title)<0:
			AudioServer.add_bus()
			var index:=AudioServer.bus_count-1
			AudioServer.set_bus_name(index,title)
			AudioServer.set_bus_send(index,"Master")
	var private_index:=AudioServer.get_bus_index("AudioEditorPrivate")
	AudioServer.set_bus_volume_db(private_index,-11.25)
	var private_fx:=AudioEffectEQ6.new()
	AudioServer.add_bus_effect(private_index,private_fx)
	var music_index:=AudioServer.get_bus_index("Music")
	var sfx_index:=AudioServer.get_bus_index("SFX")
	var voice_index:=AudioServer.get_bus_index("Voice")
	var core_fx:=AudioEffectEQ6.new()
	AudioServer.add_bus_effect(sfx_index,core_fx)
	var master:=AudioServer.get_bus_index("Master")
	capture=AudioEffectCapture.new()
	capture.buffer_length=1.0
	AudioServer.add_bus_effect(master,capture)
	var mix:=Mix.new()
	check(mix.setup(fixture),"Native authored fixture is validated and loaded fresh")
	check(mix.watching==(OS.has_feature("editor") and OS.is_debug_build()),"Watcher is enabled only in editor-capable debug builds")
	for title: String in Mix.CHANNELS:
		check(mix.apply(title,.5) and absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(title))-float(mix.baseline_db[title]))<.00001,"Midpoint preserves authored editor fader: "+title)
	check(AudioServer.get_bus_index("AudioEditorPrivate")==private_index and AudioServer.get_bus_effect(private_index,0)==private_fx and AudioServer.get_bus_volume_db(private_index)==-11.25,"Setup preserves private bus identity, effect and gain")
	check(AudioServer.get_bus_effect(sfx_index,0)==core_fx,"Setup preserves private effects attached to core bus")
	check(not mix.apply("Unknown",.5) and not mix.apply("Music",NAN),"Unknown/nonfinite requests cannot alter mixer")
	var expected: float=float(mix.baseline_db.Music)+linear_to_db(preload("res://scripts/audio_defaults.gd").channel_gain("Music",.75)/.8)
	check(mix.apply("Music",.75) and absf(AudioServer.get_bus_volume_db(music_index)-expected)<.00001,"Slider is a relative multiplier around authored baseline")
	mix.apply("Music",.5)
	probe=AudioStreamPlayer.new()
	root.add_child(probe)
	var imported: AudioStream=load("res://assets/audio/shot_01.wav")
	var before:=await record(imported,"Music")
	var timestamp:=FileAccess.get_modified_time(fixture)
	var original_hash: String=mix.source_hash
	write_source(layout_text(-18))
	var touch:=OS.execute("python3",["-c","import os,sys; n=int(sys.argv[2]); os.utime(sys.argv[1],(n,n))",ProjectSettings.globalize_path(fixture),str(timestamp)])
	check(touch==0 and FileAccess.get_modified_time(fixture)==timestamp,"Actual content edit retains identical second-resolution modification time")
	mix._last_poll_usec=0
	check(mix.poll() and mix.source_hash!=original_hash,"Content hash detects saved same-second editor change")
	mix.apply("Music",.5)
	var after:=await record(imported,"Music")
	var old_stats:=stats(before)
	var new_stats:=stats(after)
	var ratio: float=new_stats.rms/maxf(old_stats.rms,1e-12)
	measurements.editor_fader={"before":old_stats,"after":new_stats,"amplitude_ratio":ratio,"expected_ratio":db_to_linear(6)}
	check(before.size()==after.size() and before.size()>2000 and old_stats.rms>.000001,"Actual imported sound reaches retained Master capture in both takes")
	check(absf(ratio-db_to_linear(6))<.002,"Saved six-decibel editor adjustment changes real output amplitude by expected factor")
	check(not mix.poll(),"Wall-clock poll guard prevents repeated resource reads within half a second")
	var accepted_hash: String=mix.source_hash
	var accepted_db: float=mix.baseline_db.Music
	for broken: String in [layout_text(-3).left(95),layout_text().replace('SubResource("limiter")','SubResource("missing")'),layout_text().replace("volume_db = -24.000000000","volume_db = junk"),layout_text().replace("volume_db = -24.000000000","volume_db = nan"),layout_text().replace("bus/1/name", "bus/999999999/name")]:
		write_source(broken)
		mix._last_poll_usec=0
		check(not mix.poll() and mix.source_hash==accepted_hash and mix.baseline_db.Music==accepted_db,"Malformed/incomplete save retains last good mix without loader errors")
	write_source("x".repeat(Mix.MAX_LAYOUT_BYTES+1))
	mix._last_poll_usec=0
	check(not mix.poll() and mix.source_hash==accepted_hash,"Oversized source is rejected before parsing/loading")
	write_source('[gd_resource type="AudioBusLayout" format=3]\n\n[resource]\nbus/0/volume_db = 0.0\n')
	mix._last_poll_usec=0
	check(not mix.poll() and mix.source_hash==accepted_hash and mix.baseline_db.Music==accepted_db,"Syntactically valid but truncated old three-channel layout cannot reset known mix to fallback")
	write_source(layout_text(-18,-17,-21,4,3,{"Music":{"mute":true},"Voice":{"solo":true},"SFX":{"bypass_fx":true},"Master":{"mute":true}}))
	mix._last_poll_usec=0
	check(mix.poll(),"Complete editor save recovers after invalid intermediate file")
	for title: String in Mix.CHANNELS: mix.apply(title,.8)
	check(AudioServer.is_bus_mute(music_index) and AudioServer.is_bus_solo(voice_index) and AudioServer.is_bus_bypassing_effects(sfx_index),"Authored mute/solo/bypass survive player-slider application")
	check(AudioServer.is_bus_mute(master),"Authored Master mute remains effective")
	var limiter: AudioEffectHardLimiter=null
	var capture_index:=-1
	var count:=0
	for index in AudioServer.get_bus_effect_count(master):
		var effect:=AudioServer.get_bus_effect(master,index)
		if effect is AudioEffectHardLimiter: limiter=effect;count+=1
		if effect==capture: capture_index=index
	check(count==1 and limiter!=null and absf(limiter.pre_gain_db-7)<.00001 and AudioServer.get_bus_volume_db(master)==0 and limiter.ceiling_db<=-1,"Authored pre/post Master gains combine once before one active ceiling")
	check(capture_index>=0 and AudioServer.get_bus_effect(master,capture_index)==capture and AudioServer.get_bus_effect(sfx_index,0)==core_fx,"Reload retains actual active capture and private core FX instances")
	# The source baseline is fresh, even if current live buses include a slider.
	write_source(layout_text(-18,-18,-22))
	mix._last_poll_usec=0
	check(mix.poll(),"Neutral complete source reload clears authored mute/solo flags")
	mix.apply("Music",.75)
	var other:=Mix.new()
	check(other.setup(fixture) and other.baseline_db.Music==-18,"A second helper takes baseline from file rather than multiplied live mixer")
	other.apply("Music",.75)
	check(absf(AudioServer.get_bus_volume_db(music_index)-(-18+linear_to_db(preload("res://scripts/audio_defaults.gd").channel_gain("Music",.75)/.8)))<.00001,"Second scene cannot stack current user-slider gain")
	# Actual Audio integration polls in its ALWAYS process during a real pause.
	var audio:=Audio.new()
	audio.bus_layout_path=fixture
	root.add_child(audio)
	for frame in 2: await process_frame
	stop_sources(audio)
	check("bus_mix" in audio and audio.bus_mix.baseline_db.Music==-18,"Actual Audio setup reads custom authored layout path")
	var second:=Audio.new()
	second.bus_layout_path=fixture
	root.add_child(second)
	for frame in 2: await process_frame
	stop_sources(second)
	check(AudioServer.get_bus_volume_db(music_index)==-18,"A second real Audio scene preserves authored midpoint without gain stacking")
	second.set_process(false)
	audio.set_process(true)
	paused=true
	write_source(layout_text(-12,-16,-20))
	audio.bus_mix._last_poll_usec=0
	await process_frame
	await process_frame
	check(AudioServer.get_bus_volume_db(music_index)==-12 and audio.music_volume==.5 and audio.process_mode==Node.PROCESS_MODE_ALWAYS,"Actual paused Audio process applies saved editor fader without changing player slider")
	paused=false
	audio.set_process(false)
	stop_sources(audio)
	check(AudioServer.get_bus_index("AudioEditorPrivate")==private_index and AudioServer.get_bus_effect(private_index,0)==private_fx,"Two actual Audio setups and paused reload keep private bus indices intact")
	# Add/update/disable/remove actual authored DSP in every core bus. The capture
	# and unowned EQ remain the identical live resources through all operations.
	for channel: String in ["Music","SFX","Voice","Master"]:
		adopt(mix,layout_text(-18,-18,-22))
		var dry:=await record(imported,channel)
		adopt(mix,fx_source(channel,"AudioEffectAmplify","volume_db = 6.0"))
		var boosted:=await record(imported,channel)
		ratio_check(dry,boosted,db_to_linear(6),channel+" FX added")
		adopt(mix,fx_source(channel,"AudioEffectAmplify","volume_db = 12.0"))
		var updated:=await record(imported,channel)
		ratio_check(boosted,updated,db_to_linear(6),channel+" FX parameter updated")
		adopt(mix,fx_source(channel,"AudioEffectAmplify","volume_db = 12.0",false))
		var disabled:=await record(imported,channel)
		ratio_check(dry,disabled,1.0,channel+" FX disabled")
		adopt(mix,layout_text(-18,-18,-22))
		var no_fx:=await record(imported,channel)
		ratio_check(dry,no_fx,1.0,channel+" FX removed")
		check(AudioServer.get_bus_effect(sfx_index,0)==core_fx and AudioServer.get_bus_effect(private_index,0)==private_fx,"Live FX edits retain independent private effect objects")
	var texture_cases:=[
		{"channel":"Music","type":"AudioEffectReverb","props":"wet = 1.0\ndry = 0.0\nroom_size = 0.8","name":"Music hall"},
		{"channel":"SFX","type":"AudioEffectLowPassFilter","props":"cutoff_hz = 100.0\nresonance = 0.5","name":"SFX lowpass"},
		{"channel":"Voice","type":"AudioEffectCompressor","props":"threshold = -50.0\nratio = 12.0\nattack_us = 20.0\nrelease_ms = 200.0","name":"Voice compressor"},
	]
	for texture: Dictionary in texture_cases:
		adopt(mix,layout_text(-18,-18,-22))
		var dry:=await record(imported,texture.channel)
		adopt(mix,fx_source(texture.channel,texture.type,texture.props))
		var processed:=await record(imported,texture.channel)
		var old:=stats(dry)
		var current:=stats(processed)
		measurements[texture.name]={"dry":old,"processed":current}
		check(dry.size()==processed.size() and current.rms>.0000001 and absf(current.rms/maxf(old.rms,1e-12)-1)>.03,texture.name+": native DSP audibly changes actual imported PCM")
	# A Master bypass request silences authored DSP while safety/capture remain.
	adopt(mix,fx_source("Master","AudioEffectAmplify","volume_db = 12.0").replace("bus/0/bypass_fx = false","bus/0/bypass_fx = true"))
	var own_active:=0
	var safety_active:=0
	for index in AudioServer.get_bus_effect_count(master):
		var effect:=AudioServer.get_bus_effect(master,index)
		if effect.has_meta(Mix.AUTHORED_EFFECT_META) and AudioServer.is_bus_effect_enabled(master,index): own_active+=1
		if effect is AudioEffectHardLimiter and AudioServer.is_bus_effect_enabled(master,index): safety_active+=1
	check(own_active==0 and safety_active==1 and not AudioServer.is_bus_bypassing_effects(master),"Master bypass disables authored FX while retaining one active final safety ceiling")
	var reloaded_scene:=Audio.new()
	reloaded_scene.bus_layout_path=fixture
	root.add_child(reloaded_scene)
	for frame in 2: await process_frame
	stop_sources(reloaded_scene)
	var source_count:=0
	for index in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master,index).has_meta(Mix.AUTHORED_EFFECT_META): source_count+=1
	check(source_count==1,"A new actual scene replaces its authored effect instead of stacking duplicates")
	check(await Cleanup.free_scene(reloaded_scene,self),"Third real source-FX scene retires cleanly")
	# An exported/remapped AudioBusLayout is binary, without editable text.
	var binary_path:=fixture.trim_suffix(".tres")+".res"
	var binary_source:=ResourceLoader.load(fixture,"AudioBusLayout",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as AudioBusLayout
	check(binary_source!=null and ResourceSaver.save(binary_source,binary_path)==OK,"Real AudioBusLayout saves into native binary resource fixture")
	var binary:=Mix.new()
	check(binary.setup(binary_path) and binary.baseline_db.Music==-18 and not binary.watching,"Binary startup preserves authored bus baseline and disables text watcher")
	var binary_scene:=Audio.new()
	binary_scene.bus_layout_path=binary_path
	root.add_child(binary_scene)
	for frame in 2: await process_frame
	stop_sources(binary_scene)
	check(binary_scene.bus_mix.baseline_db.Music==-18 and AudioServer.get_bus_volume_db(music_index)==-18,"Actual Audio setup honors native binary layout independently of current live gains")
	check(await Cleanup.free_scene(binary_scene,self),"Binary-source real Audio scene retires cleanly")
	DirAccess.remove_absolute(binary_path)
	mix.watching=false
	write_source(layout_text(-3))
	mix._last_poll_usec=0
	check(not mix.poll(),"Export-disabled watcher never reloads saved file")
	var missing:=Mix.new()
	check(not missing.setup("user://nonexistent-bus-layout.tres") and missing.baseline_db==Mix.FALLBACK_DB,"Missing source retains canonical fallback independent of live bus gains")
	write_source('[gd_resource type="AudioBusLayout" format=3]\n\n[resource]\nbus/0/volume_db = 4.0\n')
	var legacy:=Mix.new()
	check(legacy.setup(fixture) and legacy.baseline_db==Mix.FALLBACK_DB,"Legacy Master-only layout supplies all three known channel baselines")
	legacy.apply("Music",.5)
	check(absf(AudioServer.get_bus_volume_db(music_index)-float(Mix.FALLBACK_DB.Music))<.00001,"Fallback includes authored trim once, without multiplying it again")
	check(audio.bus_layout_path==fixture and second.bus_layout_path==fixture,"Actual scene owners keep the dedicated fixture binding, independent of live editor changes")
	probe.stop()
	probe.queue_free()
	for index in range(AudioServer.get_bus_effect_count(master)-1,-1,-1):
		if AudioServer.get_bus_effect(master,index)==capture: AudioServer.remove_bus_effect(master,index)
	capture=null
	check(await Cleanup.free_scene(second,self) and await Cleanup.free_scene(audio,self),"Both real scenes, decoders and private routing retire cleanly")
	var deadline:=Time.get_ticks_msec()+4000
	while retired.any(func(handle: WeakRef): return handle.get_ref()!=null) and Time.get_ticks_msec()<deadline: await create_timer(.01).timeout
	check(not retired.any(func(handle: WeakRef): return handle.get_ref()!=null),"Stopped synchronized playback retires before test process exits")
	AudioServer.remove_bus(AudioServer.get_bus_index("AudioEditorPrivate"))
	DirAccess.remove_absolute(fixture)
	var file:=FileAccess.open(OUTPUT+"verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements,"prepared_state":"Own AudioBusLayout fixture installed before private routing or playback, actual imported shot WAV through retained Master capture, four real Audio scenes and actual SceneTree pause. No live layout reset; real bus/profile/project files are never written."},"\t")+"\n")
	print("AUDIO EDITOR BUSES: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
