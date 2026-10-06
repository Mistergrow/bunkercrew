extends Node
## Explicit push-to-talk, bounded 20 ms frames and a short receive jitter buffer.
const Codec := preload("res://scripts/voice_codec.gd")
const Defaults := preload("res://scripts/audio_defaults.gd")
const SETTINGS := "user://voice.cfg"
const MAX_QUEUE := 10
const PREBUFFER := 3
var game
var playback_only := false
var _primary_sender := 0
var _receivers: Dictionary = {}
var _muted_senders: Dictionary = {}
var enabled := false
var output_volume := Defaults.PARTNER_VOLUME
var remote_muted := false
var speaking := false
var remote_speaking := false
var received_frames := 0
var played_frames := 0
var lost_frames := 0
var dropped_frames := 0
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _queue: Dictionary = {}
var _expected := -1
var _highest := -1
var _last_received := -100.0
var _clock := 0.0
var _started_at := 0.0
var _playing := false
var _generation := -1
var _network_instance := 0
var _frame := PackedFloat32Array()
var _resample_time := 0.0
var _filtered := 0.0
var _filtered_second := 0.0
var _previous := 0.0
var _receive_peak := 0.0
var _ptt_armed := false
var _tail_sample := 0.0
var _concealed := true
var _playback_capacity := 0

func speaking_players() -> Array[int]:
	# Presentation uses authenticated seats, never guesses from packet order.
	var result: Array[int] = []
	if not enabled or not _connected(): return result
	if speaking: result.append(int(game.network.local_player_id))
	if not remote_muted and not _muted_senders.has(_primary_sender) and _primary_sender > 0 and _clock - _last_received < 0.25 and _receive_peak > 0.008:
		result.append(_primary_sender)
	for sender: int in _receivers:
		var receiver: Node = _receivers[sender]
		if not remote_muted and not _muted_senders.has(sender) and receiver.remote_speaking and sender not in result: result.append(sender)
	return result

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	var config:=ConfigFile.new()
	if not playback_only and "--no-profile-save" not in OS.get_cmdline_user_args() and config.load(SETTINGS)==OK:
		var saved_enabled=config.get_value("voice","enabled",false)
		enabled=saved_enabled is bool and saved_enabled
		var volume=config.get_value("voice","output",Defaults.PARTNER_VOLUME)
		if (volume is float or volume is int) and is_finite(float(volume)): output_volume=clampf(float(volume),0.0,1.0)
		var saved_muted=config.get_value("voice","muted",false)
		remote_muted=saved_muted is bool and saved_muted
	if not playback_only:
		game.microphone.samples_ready.connect(_samples)
		if game.microphone.has_signal("device_lost"): game.microphone.device_lost.connect(_input_lost)
	_player=AudioStreamPlayer.new()
	_player.name="PartnerVoice"
	_player.volume_db=linear_to_db(output_volume) if output_volume>0 else -80.0
	add_child(_player)
	var generator:=AudioStreamGenerator.new()
	generator.mix_rate=Codec.RATE
	generator.buffer_length=0.12
	_player.stream=generator

func set_enabled(value: bool) -> void:
	enabled=value
	_ptt_armed=false
	if not value: reset()
	for receiver in _receivers.values(): receiver.set_enabled(value)
	_save()

func set_output_volume(value: float) -> void:
	if not is_finite(value): return
	output_volume=clampf(value,0.0,1.0)
	for receiver in _receivers.values(): receiver.set_output_volume(output_volume)
	if is_instance_valid(_player): _player.volume_db=linear_to_db(output_volume) if output_volume>0 else -80.0
	_save()

func set_remote_muted(value: bool) -> void:
	remote_muted=value
	for receiver in _receivers.values(): receiver.set_remote_muted(value)
	if value:
		_clear_playback()
		_expected=-1
		_highest=-1
		_last_received=-100.0
	_save()

func set_sender_muted(sender: int, value: bool) -> void:
	if sender < 1 or sender > 4: return
	if value: _muted_senders[sender] = true
	else: _muted_senders.erase(sender)
	if value and sender == _primary_sender: _clear_playback()
	if value and _receivers.has(sender): _receivers[sender]._clear_playback()

func clear_sender_mutes() -> void:
	_muted_senders.clear()

func retire_sender(sender: int) -> void:
	# A room seat can be assigned to a different person. Retire its queued
	# speech and sequence window without interrupting other speakers or PTT.
	if sender == _primary_sender:
		_clear_playback()
		_expected = -1
		_highest = -1
		_last_received = -100.0
	if _receivers.has(sender):
		var receiver: Node = _receivers[sender]
		receiver.reset()
		receiver.queue_free()
		_receivers.erase(sender)

func _save() -> void:
	if playback_only or "--no-profile-save" in OS.get_cmdline_user_args(): return
	var config:=ConfigFile.new()
	config.set_value("voice","enabled",enabled)
	config.set_value("voice","output",output_volume)
	config.set_value("voice","muted",remote_muted)
	config.save(SETTINGS)

func _connected() -> bool:
	return is_instance_valid(game) and is_instance_valid(game.network) and game.network.active and game.network.peer_connected and (game.network.is_host or game.network._authenticated) and game.network.state in ["lobby","playing"]

func _push_to_talk() -> bool:
	if not _ptt_armed or not enabled or not _connected() or not _window_focused(): return false
	if not is_instance_valid(game.hud) or game.hud.overlay not in ["","network","pause"]: return false
	if game.hud.has_method("has_session_action") and game.hud.has_session_action(): return false
	if game.hud.has_method("has_text_entry") and game.hud.has_text_entry(): return false
	var focus:=get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return false
	return Input.is_physical_key_pressed(KEY_V)

func _window_focused() -> bool:
	return get_tree().root.has_focus()

func _input_lost() -> void:
	_ptt_armed=false
	if speaking: _stop_capture()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: _input_lost()

func _process(delta: float) -> void:
	_clock+=delta
	if playback_only:
		remote_speaking=enabled and not remote_muted and _clock-_last_received<0.25 and _receive_peak>0.008
		_pump()
		return
	if not _connected():
		reset()
		return
	var network_id:int=game.network.get_instance_id()
	if _generation!=game.network._generation or _network_instance!=network_id:
		reset()
		_generation=game.network._generation
		_network_instance=network_id
	var wanted:=_push_to_talk()
	if not Input.is_physical_key_pressed(KEY_V): _ptt_armed=true
	elif not wanted: _ptt_armed=false
	if wanted and not speaking:
		speaking=game.microphone.acquire("voice")
		if not speaking: _ptt_armed=false
	elif not wanted and speaking:
		_stop_capture()
	if speaking and game.microphone.active_owner!="voice": _input_lost()
	remote_speaking=enabled and not remote_muted and _clock-_last_received<0.25 and _receive_peak>0.008
	_pump()
	for receiver in _receivers.values(): remote_speaking=remote_speaking or receiver.remote_speaking

func _samples(capture_owner: String, samples: PackedFloat32Array, rate: int) -> void:
	if capture_owner!="voice" or not speaking or not _push_to_talk() or rate<8000 or rate>192000: return
	# Two simple low-pass stages suppress high-frequency aliasing before downsampling.
	var step:=float(rate)/Codec.RATE
	var alpha:=1.0-exp(-TAU*6000.0/float(rate))
	var sent:=0
	for sample in samples:
		if not is_finite(sample): sample=0.0
		_filtered+=alpha*(sample-_filtered)
		_filtered_second+=alpha*(_filtered-_filtered_second)
		while _resample_time<=1.0:
			_frame.append(lerpf(_previous,_filtered_second,_resample_time))
			_resample_time+=step
			if _frame.size()==Codec.FRAMES:
				if sent<8: game.network.send_voice(Codec.encode(_frame))
				_frame.clear()
				sent+=1
		_resample_time-=1.0
		_previous=_filtered_second

func receive(message: Dictionary) -> bool:
	if not Codec.valid(message) or not _connected() or message.generation!=game.network._generation: return false
	if _muted_senders.has(int(message.get("player_id", 0))): return true
	if not enabled or remote_muted: return true
	if not playback_only and message.has("player_id"):
		var sender: int=message.player_id
		if _primary_sender==0: _primary_sender=sender
		if sender!=_primary_sender:
			if not _receivers.has(sender):
				var receiver=get_script().new()
				receiver.game=game
				receiver.playback_only=true
				receiver.enabled=enabled
				receiver.output_volume=output_volume
				receiver.remote_muted=remote_muted
				add_child(receiver)
				_receivers[sender]=receiver
			var accepted: bool=_receivers[sender].receive(message)
			if accepted: received_frames+=1
			return accepted
	var seq:int=message.seq
	if seq<=_expected-1 or _queue.has(seq):
		dropped_frames+=1
		return false
	if _clock-_last_received>0.3:
		_clear_playback()
		_expected=seq
		_started_at=_clock
	var queued_span := maxi(_highest,seq)-_expected+1 if _expected>=0 else 1
	# Include audio already queued in the native generator, not only packets.
	# A burst or large gap must never accumulate more than 200 ms of old speech.
	if _queue.size()>=MAX_QUEUE or _buffered_samples()+queued_span*Codec.FRAMES>MAX_QUEUE*Codec.FRAMES:
		_clear_playback()
		_expected=seq
		_highest=seq
		_started_at=_clock
		dropped_frames+=1
	if _expected<0:
		_expected=seq
		_started_at=_clock
	_queue[seq]=message.pcm
	_highest=maxi(_highest,seq)
	_last_received=_clock
	received_frames+=1
	return true

func _pump() -> void:
	if not enabled or remote_muted or _queue.is_empty():
		if _playing and _clock-_last_received>0.3: _clear_playback()
		return
	if not _playing:
		if _queue.size()<PREBUFFER and _clock-_started_at<0.08: return
		_player.play()
		_playback=_player.get_stream_playback()
		_playback_capacity=_playback.get_frames_available() if _playback!=null else 0
		_playing=true
	if _playback==null: return
	# Never fill more than 60 ms per render tick, even after a stall.
	for unused in 3:
		if _playback.get_frames_available()<Codec.FRAMES or _expected>_highest: break
		var samples:PackedVector2Array
		if _queue.has(_expected):
			samples=Codec.decode(_queue[_expected])
			_queue.erase(_expected)
			played_frames+=1
			if _concealed:
				for index in 40:
					var blend:=float(index+1)/40.0
					samples[index]=Vector2.ONE*lerpf(_tail_sample,samples[index].x,blend)
			_concealed=false
		else:
			# A future packet does not prove its predecessor is lost. Keep its
			# place while at least one 20 ms frame remains ahead of the listener.
			if _buffered_samples()>=Codec.FRAMES: break
			samples.resize(Codec.FRAMES)
			for index in 80: samples[index]=Vector2.ONE*_tail_sample*(1.0-float(index+1)/80.0)
			_concealed=true
			lost_frames+=1
		_tail_sample=samples[-1].x
		_receive_peak=0.0
		for sample in samples: _receive_peak=maxf(_receive_peak,absf(sample.x))
		_playback.push_buffer(samples)
		_expected+=1

func _buffered_samples() -> int:
	if _playback==null: return 0
	return maxi(0,_playback_capacity-_playback.get_frames_available())

func _stop_capture() -> void:
	if is_instance_valid(game) and is_instance_valid(game.microphone): game.microphone.release("voice")
	speaking=false
	_frame.clear()
	_resample_time=0.0
	_filtered=0.0
	_filtered_second=0.0
	_previous=0.0

func _clear_playback() -> void:
	_queue.clear()
	if is_instance_valid(_player): _player.stop()
	_playback=null
	_playback_capacity=0
	_playing=false
	remote_speaking=false
	_receive_peak=0.0
	_tail_sample=0.0
	_concealed=true

func reset() -> void:
	for receiver in _receivers.values(): receiver.reset()
	_ptt_armed=false
	if speaking: _stop_capture()
	_clear_playback()
	_expected=-1
	_highest=-1
	_last_received=-100.0

func _exit_tree() -> void:
	reset()
