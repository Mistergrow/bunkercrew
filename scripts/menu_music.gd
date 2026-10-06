extends Node
## Recorded menu rave with presentation driven by its actual audible decoder.
## Original native kick markers are baked in the catalog alongside the OGG.
const Catalog := preload("res://scripts/menu_music_catalog.gd")
const PULSE_DECAY := 0.11
const PULSE_TAIL := 0.36

var player: AudioStreamPlayer
var track_seconds := Catalog.SECONDS
var playing: bool:
	get: return is_instance_valid(player) and player.playing
var _retired_playbacks: Array[WeakRef] = []
var _decoder_id := 0
var _track: Dictionary = {}
var _audible_transport := -INF
var _frame := {"active": false, "kick_pulse": 0.0, "audible_seconds": -1.0,
	"bpm": Catalog.BPM, "beat": -1, "phase": 0.0, "kick_timestamp": -INF,
	"secondary_pulse": 0.0, "secondary_timestamp": -INF, "secondary_strength": 0.0,
	"kick_strength": 0.0, "title": Catalog.TITLE, "loop_seconds": -1.0, "decoder_loops": 0}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = AudioStreamPlayer.new()
	player.name = "MenuRavePlayer"
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.bus = "Music"
	add_child(player)
	set_process(false) # Audio owns one cached audible presentation tick per frame.

func start() -> void:
	if playing or not is_inside_tree() or is_queued_for_deletion(): return
	_track = Catalog.selected_track()
	track_seconds = float(_track.seconds)
	_frame.title = str(_track.title)
	_frame.bpm = float(_track.bpm)
	_frame.track_id = str(_track.id)
	var stream: AudioStreamOggVorbis = load(str(_track.stream_path))
	if stream == null: return
	# Loop state belongs to this player, independently of any authoring preview.
	stream = stream.duplicate()
	stream.loop = true
	stream.loop_offset = 0.0
	player.stream = stream
	player.volume_db = 0.0
	player.play()
	_decoder_id = 0
	_audible_transport = -INF
	_clear_pulse()

func finish_menu_session() -> void:
	if playing: Catalog.advance_after_match()
	stop()

func stop() -> void:
	if is_instance_valid(player):
		if player.has_stream_playback():
			_retired_playbacks.append(weakref(player.get_stream_playback()))
		player.stop()
		player.stream = null
	_clear_pulse()
	_decoder_id = 0
	_audible_transport = -INF
	_prune_retired()

func _prune_retired() -> void:
	for index in range(_retired_playbacks.size() - 1, -1, -1):
		if _retired_playbacks[index].get_ref() == null:
			_retired_playbacks.remove_at(index)

func get_retired_music_playbacks() -> Array[WeakRef]:
	_prune_retired()
	return _retired_playbacks.duplicate()

func _clear_pulse() -> void:
	_frame.active = false
	_frame.kick_pulse = 0.0
	_frame.kick_strength = 0.0
	_frame.kick_timestamp = -INF
	_frame.secondary_pulse = 0.0
	_frame.secondary_timestamp = -INF
	_frame.secondary_strength = 0.0

func tick(enabled: bool, calibration_seconds: float, level_db: float) -> void:
	if not playing or not player.has_stream_playback():
		_clear_pulse()
		return
	player.volume_db = level_db
	var playback := player.get_stream_playback()
	var decoder_id := playback.get_instance_id()
	if decoder_id != _decoder_id:
		# Explicit play/seek replaces Godot's playback handle. Its new source
		# position starts a fresh presentation clock without carrying old time.
		_decoder_id = decoder_id
		_audible_transport = -INF
	var loops := 0
	var decoded_seconds := 0.0
	var since_mix := 0.0
	for attempt in 3:
		var mix_before := AudioServer.get_time_since_last_mix()
		var loops_before := playback.get_loop_count()
		decoded_seconds = player.get_playback_position()
		loops = playback.get_loop_count()
		since_mix = maxf(AudioServer.get_time_since_last_mix(), 0.0)
		if loops == loops_before and since_mix >= mix_before: break
	var mixed_seconds := float(loops) * track_seconds + decoded_seconds
	var output_seconds := mixed_seconds + since_mix - maxf(AudioServer.get_output_latency(), 0.0)
	# Decoder positions arrive in mixer blocks. Between two reads the audio
	# thread can reset interpolation before publishing the new decoder block.
	# Keep cosmetic time monotonic within this playback; audio itself is never
	# rescheduled. Device calibration applies afterwards, so changing it still
	# moves the displayed beat by exactly the requested compensation.
	_audible_transport = maxf(_audible_transport, output_seconds)
	var heard_seconds := _audible_transport - calibration_seconds
	_frame.audible_seconds = heard_seconds
	_frame.decoder_loops = loops
	_frame.loop_seconds = fposmod(heard_seconds, track_seconds) if heard_seconds >= 0.0 else -1.0
	_frame.active = enabled and mixed_seconds > 0.0 and heard_seconds >= 0.0
	_frame.beat = floori(heard_seconds * float(_track.bpm) / 60.0) if heard_seconds >= 0.0 else -1
	_frame.phase = fposmod(heard_seconds * float(_track.bpm) / 60.0, 1.0)
	var kicks: Array = _track.kick_samples
	var secondary: Array = _track.secondary_samples
	if not _frame.active or kicks.is_empty():
		_clear_pulse()
		return
	# Find the latest authored kick, including the previous loop's last hit.
	var cycle := floori(heard_seconds / track_seconds)
	var local_sample := float(_frame.loop_seconds) * Catalog.SAMPLE_RATE
	var index := _marker_index(kicks, local_sample)
	if index < 0:
		index = kicks.size() - 1
		cycle -= 1
	var timestamp := float(cycle) * track_seconds + float(kicks[index]) / Catalog.SAMPLE_RATE
	var strength := float(_track.kick_strengths[index])
	var age := maxf(heard_seconds - timestamp, 0.0)
	_frame.kick_timestamp = timestamp
	_frame.kick_strength = strength
	_frame.kick_pulse = clampf(strength / 0.78, 0.0, 1.0) * exp(-age / PULSE_DECAY) if age < PULSE_TAIL else 0.0
	_frame.secondary_pulse = 0.0
	_frame.secondary_timestamp = -INF
	_frame.secondary_strength = 0.0
	if not secondary.is_empty():
		cycle = floori(heard_seconds / track_seconds)
		index = _marker_index(secondary, local_sample)
		if index < 0:
			index = secondary.size() - 1
			cycle -= 1
		timestamp = float(cycle) * track_seconds + float(secondary[index]) / Catalog.SAMPLE_RATE
		strength = float(_track.secondary_strengths[index])
		age = maxf(heard_seconds - timestamp, 0.0)
		if timestamp >= 0.0:
			_frame.secondary_timestamp = timestamp
			_frame.secondary_strength = strength
			_frame.secondary_pulse = clampf(strength / Catalog.SECONDARY_REFERENCE_STRENGTH, 0.0, 1.0) * exp(-age / PULSE_DECAY) if age < PULSE_TAIL else 0.0
	_prune_retired()

func _marker_index(samples: Array, local_sample: float) -> int:
	var low := 0
	var high := samples.size()
	while low < high:
		var middle := floori((low + high) * 0.5)
		if float(samples[middle]) <= local_sample:
			low = middle + 1
		else:
			high = middle
	return low - 1

func rhythm_frame() -> Dictionary:
	return _frame

func _exit_tree() -> void:
	stop()
