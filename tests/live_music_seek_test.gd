extends SceneTree
## Actual extension rewind/restart and live AudioStreamPlayer mixer transport.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func audible(pcm: PackedFloat32Array) -> bool:
	var energy := 0.0
	for sample: float in pcm:
		if not is_finite(sample): return false
		energy+=sample*sample
	return pcm.size()>=4096 and energy>0.00001

func offline_case(stream: AudioStream,target: int,level: int,label: String) -> void:
	stream.call("seek_samples",target)
	var pcm: PackedFloat32Array=stream.call("render_offline",4096)
	check(int(stream.call("current_intensity"))==level,label+": actual native bank matches the target arrangement")
	check(audible(pcm),label+": actual finite synth PCM resumes after target composition")
	var position := int(stream.call("mixed_samples"))
	check(position>=target and position<=target+4096,label+": integer transport remains within the rendered target interval")
	var events: Array=stream.call("poll_events",256)
	var valid := not events.is_empty()
	for event: Dictionary in events: valid=valid and int(event.sample)>=target and int(event.sample)<position
	check(valid,label+": only new-position native events survive the transport generation")
	if target==0:
		var intro := false
		for event: Dictionary in events:
			if int(event.track)==0 and int(event.sample)==0 and float(event.strength)<0.35: intro=true
		check(intro,label+": sample zero triggers the authored intro kick")

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	check(ClassDB.class_exists("TesselStream"),"Native seek fixture uses the actual installed extension")
	if not ClassDB.class_exists("TesselStream"):
		quit(1)
		return
	var stream: AudioStream=ClassDB.instantiate("TesselStream")
	stream.call("set_theme",97123,{"bpm":120.0,"composition_version":2,"score_form":1})
	var rate := int(stream.call("mix_rate"))
	var beat_samples := roundi(rate*0.5)
	var first: PackedFloat32Array=stream.call("render_offline",4096)
	check(audible(first) and int(stream.call("mixed_samples"))==4096,"Normal first start uses its prepared intro without an extra silent block")
	offline_case(stream,16*4*beat_samples,2,"Forward into drop")
	offline_case(stream,0,0,"Rewind to intro")
	offline_case(stream,9*4*beat_samples,1,"Rewind into an earlier middle phrase")
	offline_case(stream,0,0,"Same-core second restart")
	offline_case(stream,56*4*beat_samples,1,"Far-forward relief phrase")
	var adaptive: AudioStream=ClassDB.instantiate("TesselStream")
	adaptive.call("set_theme",97123,{"bpm":120.0,"composition_version":2,"initial_intensity":3})
	adaptive.call("request_intensity_at_bar",0,8)
	adaptive.call("render_offline",4096)
	check(int(adaptive.call("current_intensity"))==3,"A future quiet command preserves the current joining combat arrangement")
	offline_case(adaptive,8*4*beat_samples,0,"Adaptive command reached")
	offline_case(adaptive,3*4*beat_samples,3,"Adaptive rewind before command")
	# Exercise the same transport through Godot's real mixer callback as well.
	var player := AudioStreamPlayer.new()
	var live: AudioStream=ClassDB.instantiate("TesselStream")
	live.call("set_theme",51739,{"bpm":120.0,"composition_version":2,"score_form":1})
	player.stream=live
	root.add_child(player)
	player.play()
	await settle(live,0,0)
	check(int(live.call("mixed_samples"))>0 and player.has_stream_playback(),"The actual AudioStreamPlayer starts native mixer playback")
	var playback := player.get_stream_playback()
	playback.call("seek_samples",16*4*beat_samples)
	await settle(live,16*4*beat_samples,2)
	check(int(live.call("current_intensity"))==2,"Godot mixer forward seek reaches the actual drop bank")
	# Keep the drop's native events queued to prove a rewind filters them.
	playback.call("seek_samples",0)
	await settle(live,0,0,false)
	var rewound := int(live.call("mixed_samples"))
	var new_events: Array=live.call("poll_events",256)
	var fresh := rewound>0 and rewound<rate*2 and not new_events.is_empty()
	for event: Dictionary in new_events: fresh=fresh and int(event.sample)<rate*2
	check(fresh and int(live.call("current_intensity"))==0,"Real mixer rewind rebuilds intro and excludes stale future drop events")
	check(await Cleanup.free_scene(player,self),"Native mixer seek fixture releases its playback without editor or profile changes")
	print("LIVE MUSIC SEEK: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)

func settle(stream: AudioStream,target: int,level: int,drain: bool=true) -> void:
	var deadline := Time.get_ticks_msec()+1500
	while Time.get_ticks_msec()<deadline:
		if drain: stream.call("poll_events",256)
		elif int(stream.call("mixed_samples"))>=rate_bound(stream): stream.call("poll_events",256)
		else:
			# Zero events still refills seek-generation banks on the main producer.
			stream.call("poll_events",0)
		var position := int(stream.call("mixed_samples"))
		if position>target and position<target+rate_bound(stream) and int(stream.call("current_intensity"))==level: return
		await create_timer(0.005,true,false,true).timeout

func rate_bound(stream: AudioStream) -> int:
	return int(stream.call("mix_rate"))*2
