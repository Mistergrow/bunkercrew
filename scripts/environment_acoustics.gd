extends RefCounted
## A bounded local mix: one room return and one filter/panner per reused voice.
## No scene/global bus survives its owning Audio controller.
const PROBE_SECONDS := .125
const UI_KINDS := ["warning", "start"]
var audio_owner: Node
var room_bus := ""
var listener_position := Vector2.ZERO
var exposure := 1.0
var indoor_mix := 0.0
var target_indoor := 0.0
var listener_ids: Array[int] = []
var probe_count := 0
var _listeners: Array[Node2D] = []
var _lanes: Dictionary = {}
var _room_filter: AudioEffectLowPassFilter
var _reverb: AudioEffectReverb
var _probe_clock := 0.0
var _initialized := false
var _was_paused := false
var spatial_listener: AudioListener2D

func setup(owner_node: Node) -> void:
	audio_owner = owner_node
	spatial_listener = AudioListener2D.new()
	spatial_listener.name = "WorldAudioListener"
	audio_owner.add_child(spatial_listener)
	spatial_listener.set_as_top_level(true)
	spatial_listener.make_current()
	_probe_listener()

func release() -> void:
	if is_instance_valid(spatial_listener):
		spatial_listener.clear_current()
		spatial_listener.free()
	spatial_listener = null
	# Remove sends before their destination. Bus indices are resolved by name
	# each time, because a second viewport/controller may own adjacent buses.
	for lane: Dictionary in _lanes.values():
		var index := AudioServer.get_bus_index(lane.bus)
		if index >= 0: AudioServer.remove_bus(index)
	_lanes.clear()
	var room_index := AudioServer.get_bus_index(room_bus)
	if room_index >= 0: AudioServer.remove_bus(room_index)
	room_bus = ""
	_room_filter = null
	_reverb = null
	audio_owner = null

func _make_bus(title: String, destination: String) -> int:
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, title)
	AudioServer.set_bus_send(index, destination)
	return index

func _ensure_room() -> void:
	if not room_bus.is_empty(): return
	room_bus = "WorldAcoustics_%s" % audio_owner.get_instance_id()
	var index := _make_bus(room_bus, "SFX")
	_room_filter = AudioEffectLowPassFilter.new()
	_room_filter.resonance = .5
	_room_filter.db = AudioEffectFilter.FILTER_12DB
	AudioServer.add_bus_effect(index, _room_filter)
	_reverb = AudioEffectReverb.new()
	_reverb.dry = 1.0
	_reverb.predelay_feedback = .08
	_reverb.spread = .72
	AudioServer.add_bus_effect(index, _reverb)
	_apply_room()

func route_steps(movement: Node) -> void:
	_ensure_room()
	for voice: AudioStreamPlayer2D in movement.voices: voice.bus = room_bus

func prepare_voice(voice_index: int, kind: String, point: Vector2) -> void:
	var voice: AudioStreamPlayer = audio_owner.voices[voice_index]
	if kind in UI_KINDS:
		voice.bus = "SFX"
		voice.remove_meta("acoustic_source")
		return
	_ensure_room()
	if not _lanes.has(voice_index):
		var title := room_bus + "_Voice%02d" % voice_index
		var index := _make_bus(title, room_bus)
		var lowpass := AudioEffectLowPassFilter.new()
		lowpass.resonance = .5
		lowpass.db = AudioEffectFilter.FILTER_12DB
		var panner := AudioEffectPanner.new()
		AudioServer.add_bus_effect(index, lowpass)
		AudioServer.add_bus_effect(index, panner)
		_lanes[voice_index] = {"bus":title, "filter":lowpass, "pan":panner,
			"source":point, "kind":kind, "occlusion":0.0, "target_occlusion":0.0,
			"gain":0.0, "target_gain":0.0, "panning":0.0, "target_pan":0.0}
	var lane: Dictionary = _lanes[voice_index]
	lane.source = point
	lane.kind = kind
	_probe_lane(lane)
	lane.occlusion = lane.target_occlusion
	lane.gain = lane.target_gain
	lane.panning = lane.target_pan
	_apply_lane(lane)
	voice.bus = lane.bus
	voice.set_meta("acoustic_source", point)

func update(delta: float) -> void:
	if not is_instance_valid(audio_owner) or delta <= 0 or not is_finite(delta): return
	var paused: bool = audio_owner.get_tree().paused
	if paused != _was_paused and not room_bus.is_empty():
		AudioServer.set_bus_mute(AudioServer.get_bus_index(room_bus), paused)
	_was_paused = paused
	if paused: return
	_probe_clock -= delta
	var due := _probe_clock <= 0
	if due:
		_probe_clock = PROBE_SECONDS
		_probe_listener()
	else:
		refresh_listener_position()
	indoor_mix = lerpf(indoor_mix, target_indoor, 1.0 - exp(-delta * 4.0))
	_apply_room()
	for voice_index: int in _lanes:
		var voice: AudioStreamPlayer = audio_owner.voices[voice_index]
		var lane: Dictionary = _lanes[voice_index]
		if not voice.playing or voice.bus != lane.bus: continue
		if due: _probe_lane(lane)
		var blend := 1.0 - exp(-delta * 7.0)
		lane.occlusion = lerpf(float(lane.occlusion), float(lane.target_occlusion), blend)
		lane.gain = lerpf(float(lane.gain), float(lane.target_gain), blend)
		lane.panning = lerpf(float(lane.panning), float(lane.target_pan), blend)
		_apply_lane(lane)

func _apply_room() -> void:
	if _reverb == null: return
	_room_filter.cutoff_hz = lerpf(18000, 10500, indoor_mix)
	_reverb.wet = lerpf(.012, .31, indoor_mix)
	_reverb.room_size = lerpf(.22, .66, indoor_mix)
	_reverb.damping = lerpf(.78, .54, indoor_mix)
	_reverb.predelay_msec = lerpf(45.0, 64.0, indoor_mix)

func _apply_lane(lane: Dictionary) -> void:
	lane.filter.cutoff_hz = exp(lerpf(log(18000.0), log(1250.0), float(lane.occlusion)))
	lane.pan.pan = lane.panning
	var index := AudioServer.get_bus_index(lane.bus)
	if index >= 0: AudioServer.set_bus_volume_db(index, float(lane.gain) - float(lane.occlusion) * 9.0)

func _probe_listener() -> void:
	if not is_instance_valid(audio_owner): return
	var game = audio_owner.game
	if not is_instance_valid(game): return
	_listeners.clear()
	listener_ids.clear()
	var network = game.get("network")
	var online: bool = is_instance_valid(network) and network.get("active") == true
	if game.get("players") is Array:
		for actor in game.players:
			if not is_instance_valid(actor) or not actor is Node2D or actor.is_queued_for_deletion(): continue
			var actor_id := int(actor.get("player_id")) if actor.get("player_id") != null else _listeners.size() + 1
			if online and actor_id != int(network.local_player_id): continue
			_listeners.append(actor)
			listener_ids.append(actor_id)
			if _listeners.size() >= 2: break
	var outside := 0.0
	listener_position = Vector2.ZERO
	if _listeners.is_empty():
		if is_instance_valid(game.get("camera")): listener_position = game.camera.get_screen_center_position()
		outside = 1.0
	else:
		for actor in _listeners:
			var head := actor.global_position + Vector2(0, -25)
			listener_position += head
			outside += _exposure_at(head, actor)
		listener_position /= _listeners.size()
		outside /= _listeners.size()
	exposure = outside
	_sync_spatial_listener()
	target_indoor = 1.0 - exposure
	if not _initialized:
		indoor_mix = target_indoor
		_initialized = true
	probe_count += 1

func refresh_listener_position() -> Vector2:
	# Head positions are cheap to follow every frame. Room/occlusion probes stay
	# bounded at eight per second; camera look-ahead and zoom never move our ears.
	if _listeners.is_empty() or _listeners.any(func(actor): return not is_instance_valid(actor) or actor.is_queued_for_deletion()):
		_probe_listener()
	elif not _listeners.is_empty():
		listener_position = Vector2.ZERO
		for actor: Node2D in _listeners: listener_position += actor.global_position + Vector2(0,-25)
		listener_position /= _listeners.size()
		_sync_spatial_listener()
	return listener_position

func _sync_spatial_listener() -> void:
	if is_instance_valid(spatial_listener): spatial_listener.global_position = listener_position

func _exposure_at(point: Vector2, actor: Node = null) -> float:
	var game = audio_owner.game
	var bunker = game.get("scenario_bunker")
	# A tree crown or free-standing roof outside the room is not an indoor
	# reverberant space. Real bunker openings still use the actual roof query.
	if is_instance_valid(bunker) and bunker.has_method("excavated_rects"):
		var in_room := false
		for room: Rect2 in bunker.excavated_rects():
			if room.has_point(point): in_room = true
		if not in_room: return 1.0
	var weather = game.get("weather")
	if is_instance_valid(weather) and weather.has_method("exposure_at"):
		return clampf(float(weather.exposure_at(point, actor)), 0, 1)
	if actor != null and is_instance_valid(actor.get("wetness")):
		return clampf(float(actor.wetness.exposure), 0, 1)
	if game is Node2D and game.is_inside_tree():
		var query := PhysicsRayQueryParameters2D.create(point, point - Vector2(0, 500), 3)
		query.hit_from_inside = true
		return 1.0 if game.get_world_2d().direct_space_state.intersect_ray(query).is_empty() else 0.0
	return 1.0

func _probe_lane(lane: Dictionary) -> void:
	# A scenario rebuild replaces workers while retaining Audio. A gameplay
	# sound may arrive before the next timed listener probe.
	refresh_listener_position()
	var source: Vector2 = lane.source
	if not source.is_finite():
		lane.target_occlusion = 0.0
		lane.target_gain = 0.0
		lane.target_pan = 0.0
		return
	var offset := source - listener_position
	var distance := offset.length()
	var reach := 950.0 if lane.kind == "thunder" else 720.0 if lane.kind == "explosion" else 560.0 if lane.kind == "cannon" else 430.0
	lane.target_gain = linear_to_db(maxf(.018, 1.0 / (1.0 + pow(distance / reach, 1.35))))
	lane.target_pan = clampf(offset.x / 720.0, -.85, .85)
	var game = audio_owner.game
	lane.target_occlusion = 0.0
	if not game is Node2D or not game.is_inside_tree(): return
	# Endpoint padding avoids testing the floor under a ground impact as a
	# wall. Only actual solid terrain/walls/dome bodies attenuate transmission.
	var blocked := 0.0
	var count := maxi(1, _listeners.size())
	for index in count:
		var destination := listener_position if _listeners.is_empty() else _listeners[index].global_position + Vector2(0, -25)
		var query := PhysicsRayQueryParameters2D.create(source + Vector2(0, -3), destination, 3)
		query.hit_from_inside = true
		var exclusions: Array[RID] = []
		for actor in _listeners:
			if actor is CollisionObject2D: exclusions.append(actor.get_rid())
		query.exclude = exclusions
		if not game.get_world_2d().direct_space_state.intersect_ray(query).is_empty(): blocked += 1.0
	lane.target_occlusion = blocked / count

func diagnostics() -> Dictionary:
	return {"room_bus":room_bus, "voice_lanes":_lanes.size(), "listener":listener_position,
		"listener_ids":listener_ids.duplicate(), "exposure":exposure, "indoor_mix":indoor_mix,
		"target_indoor":target_indoor, "probes":probe_count,
		"wet":_reverb.wet if _reverb != null else 0.0}
