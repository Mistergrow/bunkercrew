extends Node
## Bounded local roadside sound, shared by gameplay and the development player.
## Seeking consumes prior cues; no cue is retriggered by a slider or late replica.
const BANK := "res://assets/audio/travel_cinematics/"
const MAX_CUE_VOICES := 3
const DIALOGUE_DUCK_DB := -7.0
const CLOCK_JUMP_LIMIT := .35
const SCENES := {
	"signal":{"duration":7.5,"bed":"signal_receiver_v1","db":-10.0,"cues":[
		{"at":3.4,"path":BANK+"signal_relay_lock_v1.wav","db":-14.0,"kind":"relay_lock"}]},
	"storm":{"duration":7.85,"bed":"storm_roof_rain_v1","db":-10.0,"cues":[
		{"at":1.10,"path":BANK+"storm_branch_snap_v1.wav","db":-18.0,"kind":"branch_snap"},
		{"at":1.15,"path":"res://assets/audio/thunder_01.wav","db":-22.0,"kind":"thunder"}]},
	"supply":{"duration":6.25,"bed":"supply_generator_v1","db":-10.0,"cues":[
		{"at":1.6875,"path":BANK+"supply_shutter_v1.wav","db":-17.0,"kind":"shutter"}]},
}
var ambient_voice: AudioStreamPlayer
var cue_voices: Array[AudioStreamPlayer] = []
var cues_played := 0
var _streams: Dictionary = {}
var _scene_id := ""
var _elapsed := 0.0
var _consumed: Dictionary = {}
var _muted := false
var _dialogue_active := false
var _speed := 1.0
var _gain := 1.0
var _retired: Array[WeakRef] = []
var _ending := false
var _fade_remaining := 0.0
var _fade_duration := .08
var _fade_start_gain := 1.0

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	set_process(false)
	ambient_voice=_player("RoadsideAmbience")
	for index in MAX_CUE_VOICES: cue_voices.append(_player("RoadsideCue%d"%index))
	for definition: Dictionary in SCENES.values():
		var bed_path: String=BANK+str(definition.bed)+".wav"
		_streams[bed_path]=load(bed_path) as AudioStream
		for cue: Dictionary in definition.cues:
			var path: String=str(cue.path)
			if not _streams.has(path): _streams[path]=load(path) as AudioStream
	tree_exiting.connect(stop)

func _player(label: String) -> AudioStreamPlayer:
	var voice:=AudioStreamPlayer.new()
	voice.name=label
	voice.bus=&"SFX"
	voice.max_polyphony=1
	voice.process_mode=Node.PROCESS_MODE_ALWAYS
	add_child(voice)
	return voice

func begin_sequence(id: String, elapsed: float=0.0, muted: bool=false) -> void:
	stop()
	_muted=muted
	if not SCENES.has(id): return
	_scene_id=id
	_elapsed=_safe_time(elapsed)
	_consume_until(_elapsed)
	ambient_voice.stream=_streams.get(BANK+str(SCENES[id].bed)+".wav")
	_apply_gain()

func update_sequence(id: String, elapsed: float, playing: bool, replay_cues: bool=false) -> void:
	if not SCENES.has(id): stop(); return
	if _ending: return
	if id!=_scene_id: begin_sequence(id,elapsed,_muted)
	var next_time:=_safe_time(elapsed)
	var jumped:=next_time<_elapsed-.01 or next_time-_elapsed>CLOCK_JUMP_LIMIT*_speed
	if jumped:
		seek(next_time)
	elif not playing:
		_consume_until(next_time)
	else:
		for index in SCENES[id].cues.size():
			var cue: Dictionary=SCENES[id].cues[index]
			if not _consumed.has(index) and next_time>=float(cue.at):
				_consumed[index]=true
				if not _muted: _play_cue(cue)
	# Explicit preview replay is a restart operation, never implicit seeking.
	if replay_cues and next_time<=.001: _consumed.clear()
	_elapsed=next_time
	var audible:=playing and not _muted and next_time<float(SCENES[id].duration)
	for voice: AudioStreamPlayer in cue_voices: voice.stream_paused=not audible
	ambient_voice.stream_paused=not audible
	if audible and not ambient_voice.playing and ambient_voice.stream!=null:
		ambient_voice.play(next_time)
	_apply_gain()
	_prune_retired()

func seek(elapsed: float) -> void:
	_stop_voice(ambient_voice)
	for voice: AudioStreamPlayer in cue_voices: _stop_voice(voice)
	_elapsed=_safe_time(elapsed)
	_consumed.clear()
	_consume_until(_elapsed)

func set_muted(enabled: bool) -> void:
	if _muted==enabled: return
	_muted=enabled
	if enabled:
		_stop_voice(ambient_voice)
		for voice: AudioStreamPlayer in cue_voices: _stop_voice(voice)

func set_dialogue_active(enabled: bool) -> void:
	if _ending: return
	_dialogue_active=enabled
	_apply_gain()

func set_speed(value: float) -> void:
	_speed=clampf(value,.25,2.0) if is_finite(value) else 1.0
	if is_instance_valid(ambient_voice): ambient_voice.pitch_scale=_speed
	for voice: AudioStreamPlayer in cue_voices: voice.pitch_scale=_speed

func set_gain(value: float) -> void:
	_gain=clampf(value,0,1) if is_finite(value) else 1.0
	_apply_gain()

func stop() -> void:
	if _ending: _gain=_fade_start_gain
	_ending=false
	set_process(false)
	_stop_voice(ambient_voice)
	if is_instance_valid(ambient_voice): ambient_voice.stream=null
	for voice: AudioStreamPlayer in cue_voices:
		_stop_voice(voice)
		voice.stream=null
	_scene_id=""
	_elapsed=0.0
	_consumed.clear()
	_dialogue_active=false

func release() -> void:
	stop()

func stop_with_fade(seconds: float=.08) -> void:
	if _ending: return
	if not is_instance_valid(ambient_voice) or (not ambient_voice.playing and not cue_voices.any(func(voice):return voice.playing)):
		stop()
		return
	_fade_duration=clampf(seconds,.025,.20) if is_finite(seconds) else .08
	_fade_remaining=_fade_duration
	_fade_start_gain=_gain
	_ending=true
	set_process(true)

func _process(delta: float) -> void:
	if not _ending: return
	_fade_remaining=maxf(0,_fade_remaining-delta)
	_gain=_fade_start_gain*(_fade_remaining/_fade_duration)
	_apply_gain()
	if _fade_remaining<=0: stop()

func get_retired_audio_playbacks() -> Array[WeakRef]:
	_prune_retired()
	return _retired.duplicate()

func _safe_time(value: float) -> float:
	if not is_finite(value): return 0.0
	return clampf(value,0,float(SCENES[_scene_id].duration)) if SCENES.has(_scene_id) else 0.0

func _consume_until(elapsed: float) -> void:
	if not SCENES.has(_scene_id): return
	for index in SCENES[_scene_id].cues.size():
		if float(SCENES[_scene_id].cues[index].at)<=elapsed: _consumed[index]=true

func _play_cue(cue: Dictionary) -> void:
	for voice: AudioStreamPlayer in cue_voices:
		if voice.playing: continue
		voice.stream=_streams.get(str(cue.path))
		if voice.stream==null: return
		voice.set_meta("base_db",float(cue.db))
		voice.set_meta("kind",str(cue.kind))
		voice.pitch_scale=_speed
		_apply_gain()
		voice.play()
		cues_played+=1
		return

func _apply_gain() -> void:
	var offset:=DIALOGUE_DUCK_DB if _dialogue_active else 0.0
	var fade:=linear_to_db(maxf(_gain,.00001))
	if is_instance_valid(ambient_voice) and SCENES.has(_scene_id): ambient_voice.volume_db=float(SCENES[_scene_id].db)+offset+fade
	for voice: AudioStreamPlayer in cue_voices: voice.volume_db=float(voice.get_meta("base_db",-80.0))+offset+fade

func _stop_voice(voice: AudioStreamPlayer) -> void:
	if not is_instance_valid(voice): return
	if voice.has_stream_playback(): _retired.append(weakref(voice.get_stream_playback()))
	voice.stop()
	voice.stream_paused=false

func _prune_retired() -> void:
	for index in range(_retired.size()-1,-1,-1):
		if _retired[index].get_ref()==null: _retired.remove_at(index)
