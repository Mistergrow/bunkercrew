extends Node
## Exclusive, opt-in microphone input. Probe samples never leave this node.
signal samples_ready(capture_owner: String, mono: PackedFloat32Array, sample_rate: int)
signal changed
signal devices_changed
signal device_lost

const SETTINGS := "user://microphone.cfg"
const MAX_SECONDS := 5.0
const MAX_READ_FRAMES := 38400 # Up to 200 ms at 192 kHz.
const OWNERS := ["check", "voice"]
var selected_device := "Default"
var input_gain := 1.0
var rms := 0.0
var peak := 0.0
var clipping := false
var active_owner := ""
var capturing := false
var recording := false
var playing := false
var recorded_seconds := 0.0
var status := "Mikrofon ist aus."
var sample_rate := 48000
var _samples := PackedFloat32Array()
var _devices := PackedStringArray()
var _poll_clock := 0.0
var _clip_clock := 0.0
var _silence_clock := 0.0
var _record_elapsed := 0.0
var _capture: AudioEffectCapture
var _input: AudioStreamPlayer
var _playback: AudioStreamPlayer
var _bus_name := ""
var _device_confirmed := false
var _input_started_at := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_devices = _input_devices()
	var config := ConfigFile.new()
	if config.load(SETTINGS) == OK:
		var device = config.get_value("microphone","device","Default")
		if device is String and device in _devices: selected_device = device
		var gain = config.get_value("microphone","gain",1.0)
		if (gain is float or gain is int) and is_finite(float(gain)): input_gain = clampf(float(gain),0.25,4.0)

func devices() -> PackedStringArray:
	return _devices.duplicate()

func set_device(value: String) -> bool:
	if value not in _devices: return false
	if value == selected_device: return true
	# Device changes require another deliberate activation.
	_stop_all(true)
	selected_device = value
	_save_settings()
	status = "Gerät gewählt. Mikrofon zum Testen aktivieren."
	changed.emit()
	return true

func set_input_gain(value: float) -> void:
	if not is_finite(value): return
	input_gain = clampf(value,0.25,4.0)
	_save_settings()
	changed.emit()

func _save_settings() -> void:
	if "--no-profile-save" in OS.get_cmdline_user_args(): return
	var config := ConfigFile.new()
	config.set_value("microphone","device",selected_device)
	config.set_value("microphone","gain",input_gain)
	config.save(SETTINGS)

func acquire(capture_owner: String) -> bool:
	if capture_owner not in OWNERS: return false
	if not active_owner.is_empty() and active_owner != capture_owner: return false
	if capturing: return active_owner == capture_owner
	if playing: return false
	if selected_device not in _input_devices():
		status = "Mikrofon nicht verfügbar. Gerät prüfen."
		changed.emit()
		return false
	if not _open_input():
		status = "Kein Mikrofoneingang. Gerät und Systemfreigabe prüfen."
		changed.emit()
		return false
	active_owner = capture_owner
	capturing = true
	_silence_clock = 0.0
	status = "Mikrofon aktiv. Sprich in normaler Lautstärke."
	changed.emit()
	return true

func release(capture_owner: String) -> void:
	if capture_owner not in OWNERS: return
	if active_owner != capture_owner:
		# A finished probe has no live capture_owner, but must still be erased on exit.
		if capture_owner == "check": _erase_recording()
		return
	_stop_all(capture_owner == "check")
	status = "Mikrofon ist aus."
	changed.emit()

func start_recording() -> bool:
	if active_owner != "check" or not capturing or playing: return false
	_erase_recording()
	recording = true
	_record_elapsed = 0.0
	status = "Probeaufnahme läuft · höchstens 5 Sekunden."
	changed.emit()
	return true

func stop_recording() -> void:
	if not recording: return
	recording = false
	status = "Probe bereit. Wiedergabe stoppt den Mikrofoneingang."
	changed.emit()

func play_recording() -> bool:
	if _samples.is_empty() or active_owner not in ["", "check"]: return false
	stop_recording()
	_close_input()
	capturing = false
	active_owner = "check"
	rms = 0.0
	peak = 0.0
	if not is_instance_valid(_playback):
		_playback = AudioStreamPlayer.new()
		_playback.name = "LocalProbePlayback"
		_playback.process_mode = Node.PROCESS_MODE_ALWAYS
		_playback.volume_db = -6.0
		add_child(_playback)
		_playback.finished.connect(stop_playback)
	var pcm := PackedByteArray()
	pcm.resize(_samples.size()*2)
	for index in _samples.size(): pcm.encode_s16(index*2,int(round(clampf(_samples[index],-1.0,1.0)*32767.0)))
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = sample_rate
	wave.stereo = false
	wave.data = pcm
	_playback.stream = wave
	playing = true
	status = "Lokale Wiedergabe · Mikrofoneingang ist aus."
	_playback.play()
	changed.emit()
	return true

func stop_playback() -> void:
	if is_instance_valid(_playback):
		_playback.stop()
		_playback.stream = null
	playing = false
	if not capturing: active_owner = ""
	status = "Probe bereit. Mikrofon ist aus."
	changed.emit()

func _process(delta: float) -> void:
	_poll_clock += delta
	if _poll_clock >= (0.75 if capturing or playing else 2.0):
		_poll_clock = 0.0
		_refresh_devices()
	_clip_clock = maxf(0.0,_clip_clock-delta)
	clipping = _clip_clock > 0.0
	peak = maxf(0.0,peak-delta*0.75)
	if not capturing: return
	if recording:
		_record_elapsed += delta
		if _record_elapsed >= MAX_SECONDS: stop_recording()
	var frames := _read_input()
	if not capturing: return
	if frames.is_empty():
		rms = move_toward(rms,0.0,delta)
		_silence_clock += delta
	else:
		_consume_frames(frames)
		_silence_clock = _silence_clock+delta if rms < 0.00005 else 0.0
	if _silence_clock > 2.0 and not recording:
		status = "Kein Signal. Gerät, Stummschaltung und Systemfreigabe prüfen."
	elif not recording:
		status = "Mikrofon aktiv. Sprich in normaler Lautstärke."

func _consume_frames(frames: PackedVector2Array) -> void:
	if not capturing or frames.is_empty(): return
	var count := mini(frames.size(),MAX_READ_FRAMES)
	var mono := PackedFloat32Array()
	mono.resize(count)
	var sum := 0.0
	var maximum := 0.0
	for index in count:
		var raw := (frames[index].x+frames[index].y)*0.5*input_gain
		if not is_finite(raw): raw = 0.0
		maximum = maxf(maximum,absf(raw))
		mono[index] = clampf(raw,-1.0,1.0)
		sum += mono[index]*mono[index]
	rms = sqrt(sum/float(count))
	peak = maxf(peak,minf(maximum,1.0))
	if maximum >= 0.99:
		_clip_clock = 0.8
		clipping = true
	if recording:
		var remaining := maxi(0,int(MAX_SECONDS*sample_rate)-_samples.size())
		_samples.append_array(mono.slice(0,mini(count,remaining)))
		recorded_seconds = _samples.size()/float(sample_rate)
		if remaining <= count: stop_recording()
	# Local probes never enter the chat transport callback.
	if active_owner == "voice": samples_ready.emit(active_owner,mono,sample_rate)

func _input_devices() -> PackedStringArray:
	return AudioServer.get_input_device_list()

func _refresh_devices() -> void:
	var latest := _input_devices()
	if latest == _devices: return
	_devices = latest
	# Never silently follow hotplug to another physical microphone.
	_stop_all(true)
	status = "Audiogeräte geändert. Mikrofon erneut aktivieren."
	if selected_device not in _devices: selected_device = "Default" if "Default" in _devices else ""
	device_lost.emit()
	devices_changed.emit()
	changed.emit()

func _open_input() -> bool:
	if AudioServer.get_driver_name() == "Dummy" or not ProjectSettings.get_setting("audio/driver/enable_input",false): return false
	sample_rate = int(AudioServer.get_mix_rate())
	if _bus_name.is_empty():
		_bus_name = "MicrophoneInput_%d" % get_instance_id()
		AudioServer.add_bus()
		var index := AudioServer.bus_count-1
		AudioServer.set_bus_name(index,_bus_name)
		AudioServer.set_bus_mute(index,true)
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.2
		AudioServer.add_bus_effect(index,_capture)
		_input = AudioStreamPlayer.new()
		_input.name = "ExclusiveMicrophoneInput"
		_input.stream = _make_input_stream()
		_input.bus = _bus_name
		_input.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_input)
	AudioServer.input_device = selected_device
	_capture.clear_buffer()
	_input.play()
	# PulseAudio 4.7 applies a pending selection only to an active input stream.
	# Reassert it after start and withhold samples until the driver confirms it.
	AudioServer.input_device = selected_device
	_device_confirmed = AudioServer.input_device == selected_device
	_input_started_at = Time.get_ticks_msec()
	return _input.playing

func _make_input_stream() -> AudioStream:
	return AudioStreamMicrophone.new()

func _close_input() -> void:
	if is_instance_valid(_input): _input.stop()
	if _capture != null: _capture.clear_buffer()

func _read_input() -> PackedVector2Array:
	if _capture == null: return PackedVector2Array()
	if not _device_confirmed:
		_capture.clear_buffer()
		if AudioServer.input_device == selected_device:
			_device_confirmed = true
		elif Time.get_ticks_msec()-_input_started_at > 1500:
			_stop_all(true)
			status = "Gewähltes Mikrofon konnte nicht geöffnet werden. Gerät erneut wählen."
			changed.emit()
		return PackedVector2Array()
	var available := _capture.get_frames_available()
	var maximum := mini(MAX_READ_FRAMES,int(sample_rate*0.2))
	if available>maximum:
		# Drop a stale backlog once rather than trimming every following frame.
		_capture.clear_buffer()
		return PackedVector2Array()
	return _capture.get_buffer(available)

func _erase_recording() -> void:
	recording = false
	_samples = PackedFloat32Array()
	recorded_seconds = 0.0

func _stop_all(erase: bool) -> void:
	_close_input()
	capturing = false
	recording = false
	if is_instance_valid(_playback):
		_playback.stop()
		_playback.stream = null
	playing = false
	active_owner = ""
	rms = 0.0
	peak = 0.0
	clipping = false
	_clip_clock = 0.0
	if erase: _erase_recording()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not active_owner.is_empty():
		_stop_all(true)
		status = "Fenster verlassen. Mikrofon erneut aktivieren."
		changed.emit()

func _exit_tree() -> void:
	_stop_all(true)
	if not _bus_name.is_empty():
		var index := AudioServer.get_bus_index(_bus_name)
		if index >= 0: AudioServer.remove_bus(index)
