extends Node2D
## A local, bounded engine bed for authoritative and replicated aircraft alike.
## Only four cached mono loops decode; source coordinates supply stereo placement.
const Catalog := preload("res://scripts/aircraft_audio_catalog.gd")
const MAX_MOTOR_VOICES := 4
const PROBE_SECONDS := .125
var audio_owner: Node
var voices: Array[AudioStreamPlayer2D] = []
var streams: Dictionary = {}
var _lanes: Array[Dictionary] = []
var _probe_clock := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	for family: String in Catalog.PROPULSION:
		var path: String = Catalog.PROPULSION[family].stream_path
		var stream: AudioStreamWAV
		if ResourceLoader.exists(path): stream = load(path) as AudioStreamWAV
		elif FileAccess.file_exists(path): stream = AudioStreamWAV.load_from_file(path)
		if stream == null: continue
		stream = stream.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = roundi(stream.get_length()*stream.mix_rate)
		streams[family] = stream
	for index in MAX_MOTOR_VOICES:
		var voice := AudioStreamPlayer2D.new()
		voice.name = "AircraftMotor%d"%index
		voice.process_mode = Node.PROCESS_MODE_PAUSABLE
		voice.bus = "SFX"
		voice.attenuation = 1.25
		voice.panning_strength = .85
		voice.volume_db = -80.0
		voice.max_polyphony = 1
		add_child(voice)
		voices.append(voice)
		_lanes.append({"source":null,"profile":{},"gain":0.0,"kind":""})
	tree_exiting.connect(stop_effects)

func _process(delta: float) -> void:
	if get_tree().paused or not is_finite(delta) or delta <= 0: return
	if not is_instance_valid(audio_owner) or audio_owner.sfx_volume<=0 or not is_instance_valid(audio_owner.game) or audio_owner.game.get("started")!=true:
		stop_effects()
		return
	if audio_owner.acoustics != null: audio_owner.acoustics.refresh_listener_position()
	_probe_clock -= delta
	if _probe_clock<=0:
		_probe_clock=PROBE_SECONDS
		_choose_sources()
	var active := 0
	for lane in _lanes:
		if _valid_aircraft(lane.source): active+=1
	# Four engines remain a readable bed rather than quadrupling the source power.
	var crowd_db := -10.0*log(maxi(1,active))/log(10.0)
	for index in MAX_MOTOR_VOICES:
		var lane: Dictionary = _lanes[index]
		var voice := voices[index]
		if not _valid_aircraft(lane.source):
			_clear_lane(index)
			continue
		var actor: Node2D = lane.source
		var profile: Dictionary = lane.profile
		var velocity: Vector2 = actor.get("flight_velocity") if actor.get("flight_velocity") is Vector2 else Vector2.ZERO
		var movement := clampf(velocity.length()/180.0,0,1)
		var target_db: float = float(profile.level_db)+float(profile.gain_db)+movement*3.0+crowd_db
		lane.gain = lerpf(float(lane.gain),db_to_linear(target_db),1.0-exp(-delta*6.0))
		voice.global_position=actor.global_position
		voice.volume_db=linear_to_db(maxf(.0001,float(lane.gain)))
		voice.pitch_scale=lerpf(voice.pitch_scale,float(profile.pitch)*lerpf(.96,1.08,movement),1.0-exp(-delta*4.0))
		if not voice.playing: voice.play()

func _valid_aircraft(actor) -> bool:
	return is_instance_valid(actor) and actor is Node2D and not actor.is_queued_for_deletion() and actor.get("game")==audio_owner.game and actor.get("dead")!=true and actor.global_position.is_finite()

func _choose_sources() -> void:
	var listener: Vector2 = audio_owner.acoustics.listener_position if audio_owner.acoustics!=null else Vector2.ZERO
	var candidates: Array[Node2D] = []
	for actor in get_tree().get_nodes_in_group("air_enemies"):
		if not _valid_aircraft(actor): continue
		var kind: String = str(actor.get("kind"))
		if not Catalog.PROFILES.has(kind): continue
		var family: String = Catalog.PROFILES[kind].family
		if not streams.has(family) or actor.global_position.distance_to(listener)>float(Catalog.PROPULSION[family].max_distance): continue
		candidates.append(actor)
	candidates.sort_custom(func(first,second):return _selection_distance(first,listener)<_selection_distance(second,listener))
	if candidates.size()>MAX_MOTOR_VOICES: candidates.resize(MAX_MOTOR_VOICES)
	for index in MAX_MOTOR_VOICES:
		var source = _lanes[index].source
		if not is_instance_valid(source) or source not in candidates or str(source.get("kind"))!=str(_lanes[index].kind): _clear_lane(index)
	for actor in candidates:
		if _lanes.any(func(lane):return lane.source==actor): continue
		for index in MAX_MOTOR_VOICES:
			if is_instance_valid(_lanes[index].source): continue
			var profile := Catalog.profile_for(str(actor.get("kind")))
			_lanes[index].source=actor
			_lanes[index].profile=profile
			_lanes[index].kind=str(actor.get("kind"))
			voices[index].stream=streams[profile.family]
			voices[index].max_distance=float(profile.max_distance)
			voices[index].pitch_scale=float(profile.pitch)
			break
	if audio_owner.acoustics!=null and not candidates.is_empty(): audio_owner.acoustics.route_steps(self)

func _selection_distance(actor: Node2D,listener: Vector2) -> float:
	var distance:=actor.global_position.distance_squared_to(listener)
	# Keep an already audible hover stable at the fourth/fifth selection boundary.
	return distance*.85 if _lanes.any(func(lane):return lane.source==actor) else distance

func _clear_lane(index: int) -> void:
	voices[index].stop()
	voices[index].stream=null
	_lanes[index].source=null
	_lanes[index].profile={}
	_lanes[index].gain=0.0
	_lanes[index].kind=""

func stop_effects() -> void:
	for index in voices.size(): _clear_lane(index)
	_probe_clock=0.0

func diagnostics() -> Dictionary:
	var sources: Array[int] = []
	for lane in _lanes:
		if is_instance_valid(lane.source): sources.append(lane.source.get_instance_id())
	return {"voices":voices.size(),"sources":sources,"stream_families":streams.size()}

func _exit_tree() -> void:
	stop_effects()
	streams.clear()
