extends SceneTree
## Actual game mixer/timing capture. Diagnostic, not a subjective listening test.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var output := "res://artifacts/music-beat-refresh/final"
var captures: Dictionary = {}
var report := {"fixture":"Actual game Music and Master AudioEffectCapture at unchanged 50% volume. Dummy mixer; no physical sound-device or subjective listening assessment.","sessions":[]}
var game: Node

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output=argument.trim_prefix("--output=")
	_run.call_deferred()

func _wait(seconds: float) -> void:
	var deadline := Time.get_ticks_usec()+roundi(seconds*1000000.0)
	while Time.get_ticks_usec()<deadline:
		await create_timer(0.003,true,false,true).timeout

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): _freeze(child)

func _save(path: String, samples: PackedVector2Array) -> Dictionary:
	var stream := AudioStreamWAV.new()
	stream.mix_rate=roundi(AudioServer.get_mix_rate())
	stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.stereo=true
	var bytes := PackedByteArray()
	bytes.resize(samples.size()*4)
	var peak := 0.0
	var power := 0.0
	var finite := true
	for index in samples.size():
		var sample: Vector2 = samples[index]
		finite=finite and sample.is_finite()
		peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
		power+=sample.length_squared()
		bytes.encode_s16(index*4,roundi(clampf(sample.x,-1,1)*32767))
		bytes.encode_s16(index*4+2,roundi(clampf(sample.y,-1,1)*32767))
	stream.data=bytes
	var error := stream.save_to_wav(ProjectSettings.globalize_path(path))
	return {"frames":samples.size(),"seconds":samples.size()/float(stream.mix_rate),"peak":peak,"rms":sqrt(power/maxf(samples.size()*2,1)),"finite":finite,"write_error":error}

func _record(id: String, native: bool, seconds: float) -> void:
	await _wait(0.15)
	for capture in captures.values(): capture.clear_buffer()
	var frames: Array[Dictionary] = []
	var previous := -INF
	var minimum_step := 0.0
	var backwards := 0
	var plateau_start := -1
	var longest_plateau_us := 0
	var previous_wall_us := Time.get_ticks_usec()
	var kick_markers: Dictionary = {}
	var deadline := Time.get_ticks_usec()+roundi(seconds*1000000.0)
	while Time.get_ticks_usec()<deadline:
		var wall_us := Time.get_ticks_usec()
		var raw_mixed_before := int(game.audio.live_music.native_stream.call("mixed_samples")) if native else -1
		game.audio._process(0.003)
		var frame: Dictionary = game.audio.live_music.rhythm_frame().duplicate() if native else game.audio.menu_rhythm_frame().duplicate()
		var now := float(frame.audible_seconds)
		if bool(frame.active) and previous!=-INF:
			minimum_step=minf(minimum_step,now-previous)
			if now<previous-1.0/float(AudioServer.get_mix_rate()): backwards+=1
			if absf(now-previous)<=1.0/float(AudioServer.get_mix_rate()):
				if plateau_start<0: plateau_start=previous_wall_us
				longest_plateau_us=maxi(longest_plateau_us,wall_us-plateau_start)
			else: plateau_start=-1
		if bool(frame.active): previous=now
		previous_wall_us=wall_us
		if float(frame.get("kick_strength",0.0))>0.0 and is_finite(float(frame.get("kick_timestamp",-INF))):
			kick_markers[float(frame.kick_timestamp)]=true
		frames.append({"wall_us":Time.get_ticks_usec(),"audible_seconds":now,"phase":float(frame.phase),"active":bool(frame.active),"kick_timestamp":float(frame.get("kick_timestamp",-1.0)) if is_finite(float(frame.get("kick_timestamp",-INF))) else -1.0,"kick_strength":float(frame.get("kick_strength",0.0)),"raw_mixed_before":raw_mixed_before,"raw_mixed_after":int(game.audio.live_music.native_stream.call("mixed_samples")) if native else -1,"native_rate":int(game.audio.live_music.native_stream.call("mix_rate")) if native else -1,"since_mix":AudioServer.get_time_since_last_mix(),"latency":AudioServer.get_output_latency()})
		await create_timer(0.003,true,false,true).timeout
	var elapsed_wall := float(frames[-1].wall_us-frames[0].wall_us)/1000000.0
	var elapsed_audible := float(frames[-1].audible_seconds-frames[0].audible_seconds)
	var result := {"id":id,"native":native,"minimum_step_seconds":minimum_step,"backwards_frames":backwards,"frames_sampled":frames.size(),"distinct_kicks":kick_markers.size(),"streams":{},"longest_plateau_ms":longest_plateau_us/1000.0,"elapsed_wall_seconds":elapsed_wall,"elapsed_audible_seconds":elapsed_audible,"clock_to_wall_ratio":elapsed_audible/maxf(elapsed_wall,0.001)}
	if native:
		result.elapsed_native_seconds=float(frames[-1].raw_mixed_after-frames[0].raw_mixed_after)/float(frames[0].native_rate)
		result.clock_vs_native_elapsed_error_seconds=elapsed_audible-result.elapsed_native_seconds
	for title: String in captures:
		var samples: PackedVector2Array = captures[title].get_buffer(captures[title].get_frames_available())
		result.streams[title]=_save(output+"/"+id+"-"+title.to_lower()+".wav",samples)
		result.streams[title].discarded_frames=captures[title].get_discarded_frames()
	if native: result.metadata=game.audio.live_music.native_metadata()
	report.sessions.append(result)
	var trace := FileAccess.open(output+"/"+id+"-timing.json",FileAccess.WRITE)
	trace.store_string(JSON.stringify(frames)+"\n")
	print("MUSIC_REFRESH_MIXER ",JSON.stringify(result))

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or AudioServer.get_driver_name()!="Dummy":
		push_error("Use Dummy audio and --no-profile-save --no-upnp with isolated XDG directories")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	InputSetup.install()
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	await process_frame
	_freeze(game)
	game.audio.set_music_volume(0.5)
	game.audio.set_sfx_volume(0.0)
	game.audio.set_voice_volume(0.0)
	for title: String in ["Music","Master"]:
		var index := AudioServer.get_bus_index(title)
		var capture := AudioEffectCapture.new()
		capture.buffer_length=12.0
		AudioServer.add_bus_effect(index,capture)
		captures[title]=capture
	await _record("menu",false,6.0)
	var menu_catalog = preload("res://scripts/menu_music_catalog.gd")
	if "kernimpuls" in menu_catalog.TRACK_IDS and "--original-menu-only" not in OS.get_cmdline_user_args():
		menu_catalog.advance_after_match()
		game.audio.menu_music.stop()
		game.audio._sync_menu_music()
		await _record("kernimpuls-intro",false,6.0)
		game.audio.menu_music.player.seek(game.audio.menu_music.track_seconds*0.5)
		await _record("kernimpuls-drop",false,6.0)
	game.start_scenario(1,{"environment":"ash_foundry","layout":"workshop","site":"center","difficulty":"standard"})
	await process_frame
	_freeze(game)
	paused=false
	game.rounds.running=false
	game.rounds.phase="build"
	for environment: String in ["ash_foundry","mountain_pass"]:
		game.audio.live_music.start_preview(environment,81731,-1.0,2,"minimal_techno")
		await _record(environment,true,6.0)
	for title: String in captures:
		var index := AudioServer.get_bus_index(title)
		AudioServer.remove_bus_effect(index,AudioServer.get_bus_effect_count(index)-1)
	var valid := true
	for session in report.sessions:
		for stream in session.streams.values(): valid=valid and stream.finite and stream.write_error==OK and stream.frames>48000 and stream.rms>0.00001 and stream.discarded_frames==0
		if session.native:
			valid=valid and session.backwards_frames==0 and absf(session.clock_vs_native_elapsed_error_seconds)<0.1
	report.valid_pcm=valid
	report.cleanup=await Cleanup.free_scene(game,self)
	var file := FileAccess.open(output+"/mixer-measurements.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")+"\n")
	quit(0 if valid and report.cleanup else 1)
