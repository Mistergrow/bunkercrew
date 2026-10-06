extends "res://tests/network_gameplay_peer.gd"
const Codec:=preload("res://scripts/voice_codec.gd")
var capture:AudioEffectCapture
var capture_index:=-1

func configure_audio() -> void:
	game.audio.set_music_volume(0.0)
	game.audio.set_sfx_volume(0.0)
	game.voice.set_enabled(true)
	capture=AudioEffectCapture.new()
	capture.buffer_length=2.0
	capture_index=AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0,capture)

func send_tone() -> void:
	for packet_index in 50:
		var samples:=PackedFloat32Array()
		for i in Codec.FRAMES:
			samples.append(0.22*sin(TAU*440.0*float(i+packet_index*Codec.FRAMES)/Codec.RATE))
		check(game.network.send_voice(Codec.encode(samples)),"One bounded speech frame queued on UDP voice channel")
		await delay(0.02)

func heard() -> bool:
	var samples:=capture.get_buffer(capture.get_frames_available())
	var power:=0.0
	for sample in samples: power+=sample.length_squared()
	var rms:=sqrt(power/maxf(1.0,samples.size()*2.0))
	print("VOICE_MIX ",role," frames=",samples.size()," rms=",rms," received=",game.voice.received_frames," played=",game.voice.played_frames," session_seq=",game.network._voice_highest," jitter_seq=",game.voice._highest," expected=",game.voice._expected," drops=",game.voice.dropped_frames," invalid=",game.network._invalid_packets," budget=",game.network._packet_budgets.get("voice",{}))
	return samples.size()>8000 and rms>0.015 and game.voice.received_frames>=35 and game.voice.played_frames>=30

func host_run() -> void:
	configure_audio()
	game.network.host_room(OS.get_environment("LASTSHIFT_VOICE_RELAY"))
	if not await wait_for(func():return game.network.state=="lobby" and not game.network.room_code.is_empty(),"voice room ready"):
		await complete_voice(false)
		return
	publish("room",{"code":game.network.room_code})
	if not await barrier("guest_ready"):
		await complete_voice(false)
		return
	check(game.network.peer_connected,"Voice uses an authenticated game connection")
	await send_tone()
	publish("host_sent")
	if not await barrier("guest_heard"):
		await complete_voice(false)
		return
	capture.clear_buffer()
	publish("host_ready")
	if not await barrier("guest_sent"):
		await complete_voice(false)
		return
	await delay(.18)
	check(heard(),"Real UDP partner speech reaches the host AudioServer mix")
	check(not game.microphone.capturing,"Synthetic integration never opens the physical microphone")
	publish("host_heard")
	if not await barrier("guest_done"):
		await complete_voice(false)
		return
	await complete_voice(failures==0)

func guest_run() -> void:
	configure_audio()
	game.network.join_room(OS.get_environment("LASTSHIFT_VOICE_RELAY"),str(read_stage("room").get("code","")))
	if not await wait_for(func():return game.network.peer_connected and game.network._authenticated,"authenticated voice lobby"):
		await complete_voice(false)
		return
	capture.clear_buffer()
	publish("guest_ready")
	if not await barrier("host_sent"):
		await complete_voice(false)
		return
	await delay(.18)
	check(heard(),"Real UDP host speech reaches the guest AudioServer mix")
	check(not game.microphone.capturing,"Received voice never activates the local microphone")
	publish("guest_heard")
	if not await barrier("host_ready"):
		await complete_voice(false)
		return
	await send_tone()
	publish("guest_sent")
	if not await barrier("host_heard"):
		await complete_voice(false)
		return
	game.voice.set_remote_muted(true)
	check(game.voice._queue.is_empty() and not game.voice._player.playing,"Mute drains partner playback immediately")
	publish("guest_done")
	await complete_voice(failures==0)

func complete_voice(success:bool) -> void:
	game.voice.reset()
	if capture_index>=0: AudioServer.remove_bus_effect(0,capture_index)
	await delay(.2)
	await finish(success,"real UDP speech and actual audio mix in both directions")
