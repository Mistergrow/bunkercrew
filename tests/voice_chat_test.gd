extends SceneTree
const Codec:=preload("res://scripts/voice_codec.gd")
var checks:=0
var failures:=0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func _run() -> void:
	var samples:=PackedFloat32Array()
	for i in Codec.FRAMES: samples.append(sin(i*TAU*440.0/Codec.RATE)*0.4)
	var pcm:=Codec.encode(samples)
	var decoded:=Codec.decode(pcm)
	check(pcm.size()==640 and decoded.size()==320,"Speech uses exact 20ms mono frames below one datagram")
	var worst:=0.0
	for i in Codec.FRAMES: worst=maxf(worst,absf(samples[i]-decoded[i].x))
	check(worst<1.0/32767.0,"PCM preserves the synthetic signal within one quantization step")
	samples[10]=NAN
	check(Codec.encode(samples).is_empty(),"Nonfinite samples cannot enter the network")
	check(Codec.decode(PackedByteArray([1,2])).is_empty(),"Truncated frames cannot enter playback")
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	var voice=game.voice
	voice.set_process(false)
	check(not voice.enabled and not game.microphone.capturing,"Game startup opens no microphone")
	voice.set_enabled(true)
	game.network.active=true
	game.network._authenticated=true
	game.network.peer_connected=true
	game.network.state="lobby"
	var frame:={"kind":"voice","generation":0,"seq":2,"rate":Codec.RATE,"pcm":pcm}
	check(voice.receive(frame),"Authenticated speech enters the bounded jitter buffer")
	frame.seq=4
	check(voice.receive(frame),"Future frame can arrive before its predecessor")
	frame.seq=3
	check(voice.receive(frame) and voice._queue.size()==3,"Out-of-order speech is retained until playout")
	check(not voice.receive(frame),"Duplicate speech is rejected")
	voice._pump()
	check(voice.played_frames==3 and voice.lost_frames==0,"Three reordered frames play in sequence without artificial loss")
	frame.seq=6
	voice.receive(frame)
	check(voice._queue.size()<=voice.MAX_QUEUE,"Jitter storage remains bounded")
	voice.set_remote_muted(true)
	check(voice._queue.is_empty() and not voice._player.playing,"Muting immediately clears queued partner audio")
	frame.seq=7
	check(voice.receive(frame) and voice._queue.is_empty(),"Muted packets never accumulate for later playback")
	voice.set_remote_muted(false)
	voice._clock+=30.0
	frame.seq=1500
	check(voice.receive(frame),"Playback resynchronizes after a long packet-loss gap")
	frame.generation=1
	check(not voice.receive(frame),"Other-match speech is rejected")
	frame.generation=0
	game.network._authenticated=false
	check(not voice.receive(frame),"Unauthenticated speech is rejected")
	voice.reset()
	check(voice._queue.is_empty() and not voice.speaking and not game.microphone.capturing,"Disconnect stops playback and microphone access")
	game.network.leave()
	paused=false
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Voice playback frees its native resources")
	# stop() retires the generator asynchronously; it is no longer attached to
	# a player when the generic scene cleanup collects its active handles.
	var deadline:=Time.get_ticks_msec()+150
	while Time.get_ticks_msec()<deadline: await process_frame
	print("VOICE CHAT: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
