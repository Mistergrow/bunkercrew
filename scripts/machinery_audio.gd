extends Node2D
## Only real running batches emit a quiet local bed. Two reusable voices bound
## decoder cost even when additional campaign workshops have been constructed.
const Catalog := preload("res://scripts/machinery_audio_catalog.gd")
const MAX_VOICES := 2
var audio_owner: Node
var voices: Array[AudioStreamPlayer2D] = []
var streams: Dictionary = {}
var _sources: Array[Node2D] = []
var _gains: Array[float] = []
var _probe_clock := 0.0

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_PAUSABLE
	for kind: String in Catalog.LOOPS:
		var path: String=Catalog.LOOPS[kind].stream_path
		var stream: AudioStreamWAV
		if ResourceLoader.exists(path): stream=load(path) as AudioStreamWAV
		elif FileAccess.file_exists(path): stream=AudioStreamWAV.load_from_file(path)
		if stream==null: continue
		stream=stream.duplicate()
		stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
		stream.loop_end=roundi(stream.get_length()*stream.mix_rate)
		streams[kind]=stream
	for index in MAX_VOICES:
		var voice:=AudioStreamPlayer2D.new()
		voice.name="WorkshopMotor%d"%index
		voice.process_mode=Node.PROCESS_MODE_PAUSABLE
		voice.bus="SFX"
		voice.attenuation=1.5
		voice.panning_strength=.85
		voice.volume_db=-80.0
		add_child(voice)
		voices.append(voice)
		_sources.append(null)
		_gains.append(0.0)
	tree_exiting.connect(stop_effects)

func _working(station) -> bool:
	return is_instance_valid(station) and station is Node2D and not station.is_queued_for_deletion() and station.get("game")==audio_owner.game and station.get("working")==true and station.global_position.is_finite()

func _process(delta: float) -> void:
	if get_tree().paused or not is_finite(delta) or delta<=0: return
	if not is_instance_valid(audio_owner) or audio_owner.sfx_volume<=0 or not is_instance_valid(audio_owner.game) or audio_owner.game.get("started")!=true:
		stop_effects()
		return
	var listener: Vector2=audio_owner.acoustics.refresh_listener_position() if audio_owner.acoustics!=null else Vector2.ZERO
	_probe_clock-=delta
	if _probe_clock<=0:
		_probe_clock=.125
		var nearby: Array[Node2D]=[]
		for station in get_tree().get_nodes_in_group("stations"):
			if not _working(station): continue
			var kind: String=str(station.get("kind"))
			if streams.has(kind) and station.global_position.distance_to(listener)<float(Catalog.LOOPS[kind].max_distance): nearby.append(station)
		nearby.sort_custom(func(first,second):return first.global_position.distance_squared_to(listener)<second.global_position.distance_squared_to(listener))
		if nearby.size()>MAX_VOICES: nearby.resize(MAX_VOICES)
		for index in MAX_VOICES:
			if not is_instance_valid(_sources[index]) or _sources[index] not in nearby: _clear(index)
		for station in nearby:
			if station in _sources: continue
			for index in MAX_VOICES:
				if is_instance_valid(_sources[index]): continue
				_sources[index]=station
				voices[index].stream=streams[str(station.kind)]
				voices[index].max_distance=float(Catalog.LOOPS[str(station.kind)].max_distance)
				break
		if audio_owner.acoustics!=null and not nearby.is_empty(): audio_owner.acoustics.route_steps(self)
	for index in MAX_VOICES:
		if not _working(_sources[index]):
			_clear(index)
			continue
		var station: Node2D=_sources[index]
		var voice:=voices[index]
		var spec: Dictionary=Catalog.LOOPS[str(station.kind)]
		_gains[index]=lerpf(_gains[index],db_to_linear(float(spec.level_db)),1.0-exp(-delta*6.0))
		voice.volume_db=linear_to_db(maxf(.0001,_gains[index]))
		voice.global_position=station.interaction_point()
		if not voice.playing: voice.play()

func _clear(index: int) -> void:
	voices[index].stop()
	voices[index].stream=null
	_sources[index]=null
	_gains[index]=0.0
func stop_effects() -> void:
	for index in voices.size(): _clear(index)
	_probe_clock=0.0
func _exit_tree() -> void:
	stop_effects()
	streams.clear()
