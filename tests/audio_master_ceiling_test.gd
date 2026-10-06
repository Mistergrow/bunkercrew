extends SceneTree
## Real mixed PCM proves unchanged quiet output and a final, idempotent ceiling.
const Audio:=preload("res://scripts/audio.gd")
const Cleanup:=preload("res://tests/scene_cleanup.gd")
const OUTPUT:="res://artifacts/audio-air-review/runtime"
var output := "res://artifacts/solo-story/audio" if "--midpoint-review" in OS.get_cmdline_user_args() else OUTPUT
var checks:=0
var failures:=0
var probe: AudioStreamPlayer
var capture: AudioEffectCapture
var results: Dictionary={}
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	print("MASTER %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)
func signal_stream() -> AudioStreamWAV:
	var stream:=AudioStreamWAV.new()
	stream.mix_rate=roundi(AudioServer.get_mix_rate())
	stream.format=AudioStreamWAV.FORMAT_16_BITS
	var count:=roundi(stream.mix_rate*.35)
	var data:=PackedByteArray()
	data.resize(count*2)
	for index in count:
		var fade:=minf(1.0,minf(index/90.0,(count-1-index)/90.0))
		data.encode_s16(index*2,roundi(sin(index*TAU*640/stream.mix_rate)*.125*fade*32767))
	stream.data=data
	return stream
func recorded(db: float,post_gain: float=1.0) -> PackedVector2Array:
	probe.stop()
	await create_timer(.12).timeout
	probe.volume_db=db
	capture.clear_buffer()
	probe.play()
	await create_timer(.43).timeout
	var frames:=capture.get_buffer(capture.get_frames_available())
	var first:=-1
	for index in frames.size():
		frames[index]*=post_gain
		if first<0 and frames[index].length_squared()>1e-20: first=index
	return frames.slice(first,first+roundi(AudioServer.get_mix_rate()*.25)) if first>=0 else PackedVector2Array()
func stats(frames: PackedVector2Array) -> Dictionary:
	var peak:=0.0
	var power:=0.0
	for frame in frames:
		peak=maxf(peak,maxf(absf(frame.x),absf(frame.y)))
		power+=frame.length_squared()
	return {"frames":frames.size(),"peak":peak,"rms":sqrt(power/maxf(1,frames.size()*2))}
func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(1); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var reference_path := "user://audio-master-reference-%d.tres" % OS.get_process_id()
	check(preload("res://tests/audio_reference_fixture.gd").install(reference_path), "Master proof uses an isolated reference instead of a live editor's changed faders")
	var master:=AudioServer.get_bus_index("Master")
	var shipped_limiter: AudioEffectHardLimiter = AudioServer.get_bus_effect(master,0)
	var shipped_gain := shipped_limiter.pre_gain_db
	check(absf(shipped_gain-6.0199986)<.0001 and AudioServer.get_bus_volume_db(master)==0.0,"The actual shipped layout places the preserved six-decibel boost before its output ceiling")
	# Recreate the previous +6dB post-fader layout for the recovery A/B take.
	AudioServer.remove_bus_effect(master,0)
	AudioServer.set_bus_volume_db(master,shipped_gain)
	capture=AudioEffectCapture.new()
	capture.buffer_length=1.0
	AudioServer.add_bus_effect(master,capture)
	probe=AudioStreamPlayer.new()
	probe.bus="Master"
	probe.stream=signal_stream()
	root.add_child(probe)
	var before:=await recorded(-12.0,db_to_linear(shipped_gain))
	AudioServer.remove_bus_effect(master,0)
	var audio:=Audio.new()
	root.add_child(audio)
	audio.set_process(false)
	audio.set_music_volume(0)
	audio.set_voice_volume(0)
	audio.movement.set_process(false)
	audio.aircraft_audio.set_process(false)
	audio.machinery_audio.set_process(false)
	var limiter: AudioEffectHardLimiter=AudioServer.get_bus_effect(master,0)
	check(absf(limiter.pre_gain_db-shipped_gain)<.0001 and AudioServer.get_bus_volume_db(master)==0,"Existing output gain moves ahead of the new limiter")
	AudioServer.add_bus_effect(master,capture)
	var after:=await recorded(-12.0)
	var difference:=0.0
	for index in mini(before.size(),after.size()): difference+=(before[index]-after[index]).length_squared()
	var relative:=sqrt(difference/maxf(1,before.size()*2))/maxf(.00000001,stats(before).rms)
	results.quiet_before=stats(before)
	results.quiet_after=stats(after)
	results.relative_pcm_error=relative
	check(before.size()==after.size() and relative<.0005,"Actual below-ceiling output retains the same PCM amplitude after moving the boost")
	var pre_gain:=limiter.pre_gain_db
	audio._ensure_buses()
	check(AudioServer.get_bus_effect_count(master)==2 and limiter.pre_gain_db==pre_gain and AudioServer.get_bus_volume_db(master)==0,"A second bus setup keeps one limiter and never doubles output gain")
	var second:=Audio.new()
	root.add_child(second)
	second.set_process(false)
	second.set_music_volume(0)
	second.set_voice_volume(0)
	second.movement.set_process(false)
	second.aircraft_audio.set_process(false)
	second.machinery_audio.set_process(false)
	check(limiter.pre_gain_db==pre_gain and AudioServer.get_bus_effect_count(master)==2,"A second audio scene shares the calibrated ceiling without boosting again")
	# A mono .125 peak at +20dB source gain and +6dB preserved output gain
	# would exceed +7dBFS. It must stay within the FINAL device-output ceiling.
	var overloaded:=await recorded(20.0)
	results.overloaded=stats(overloaded)
	results.input_peak_before_limiting=.125*db_to_linear(20+shipped_gain)
	check(results.input_peak_before_limiting>2.0 and results.overloaded.peak<=db_to_linear(-1)+.0001 and results.overloaded.peak>.8,"An input above zero dBFS is limited to minus one dBFS at actual final output")
	probe.stop()
	probe.queue_free()
	AudioServer.remove_bus_effect(master,1)
	capture=null
	check(await Cleanup.free_scene(second,self) and await Cleanup.free_scene(audio,self),"Both actual audio scenes retire without decoder or private-bus leaks")
	var file:=FileAccess.open(output+"/master-ceiling-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"master_fader_db":AudioServer.get_bus_volume_db(master),"limiter_pre_gain_db":pre_gain,"ceiling_db":limiter.ceiling_db,"measurements":results},"\t"))
	print("MASTER CEILING: %d/%d checks passed"%[checks-failures,checks])
	DirAccess.remove_absolute(reference_path)
	quit(1 if failures else 0)
