extends AudioStreamPlayer2D
## Local, pause-aware presentation on host and guests. Four speed/load layers
## and four priority-limited foley voices never consume the shared weapon pool.
const ENGINE_PATH := "res://assets/audio/convoy_idle_v3.wav"
const RECORDING_PATTERN := "res://assets/audio/convoy_%s_v3.wav"
const Journey := preload("res://scripts/convoy_journey.gd")
const LOOP_KINDS: Array[String] = ["idle", "torque", "road", "clatter"]
const MAX_EFFECT_VOICES := 4
const EFFECTS := {
	"start":{"db":-18.0,"priority":3,"cooldown":1200},
	"stop":{"db":-23.0,"priority":2,"cooldown":850},
	"accelerate":{"db":-25.0,"priority":1,"cooldown":1500},
	"brake":{"db":-23.0,"priority":2,"cooldown":1000},
	"gear":{"db":-28.0,"priority":1,"cooldown":700},
	"door_open":{"db":-20.0,"priority":2,"cooldown":200},
	"door_close":{"db":-19.0,"priority":2,"cooldown":200},
	"refuel":{"db":-21.0,"priority":2,"cooldown":1000},
	"tire_puncture":{"db":-15.0,"priority":5,"cooldown":1300},
	"jack":{"db":-19.0,"priority":3,"cooldown":450},
	"wrench":{"db":-22.0,"priority":2,"cooldown":410},
	"bolt_success":{"db":-18.0,"priority":4,"cooldown":80},
	"tool_miss":{"db":-23.0,"priority":3,"cooldown":220},
	"fit":{"db":-20.0,"priority":3,"cooldown":450},
	"fit_contact":{"db":-21.0,"priority":3,"cooldown":650},
	"lower":{"db":-20.0,"priority":3,"cooldown":650},
	"lower_contact":{"db":-22.0,"priority":3,"cooldown":650},
	"repair_done":{"db":-17.0,"priority":5,"cooldown":1000},
	"caution":{"db":-24.0,"priority":4,"cooldown":1600},
}
const JOURNEY_EFFECTS := {
	"boarding":"door_close", "departure":"caution", "engine_start":"start",
	"breakdown":"tire_puncture", "bolt":"bolt_success", "tool_miss":"tool_miss",
	"repair_complete":"repair_done", "route_complete":"stop", "failed":"stop",
}
const WORK_EFFECTS := {"jack":"jack", "remove":"wrench", "fit":"fit", "tighten":"wrench", "lower":"lower"}
const REAR_WHEEL_EFFECTS := ["tire_puncture", "jack", "wrench", "bolt_success", "tool_miss", "fit", "fit_contact", "lower", "lower_contact", "repair_done"]
const REPAIR_CONTACT_WORK := .92
var vehicle: Node2D
var effects: Dictionary = {}
var layers: Dictionary = {}
var effect_voices: Array[AudioStreamPlayer2D] = []
var effects_played := 0
var _last_running := false
var _last_crew := 0
var _last_gear := 0
var _last_fuel := 0.0
var _last_speed := 0.0
var _observed := false
var _last_event_serial := -1
var _voice_serial := 0
var _effect_cooldown: Dictionary = {}
var _gains: Dictionary = {}
var _speed_rate := 0.0
var _load := 0.0
var _gear_sag := 0.0
var _repair_step := ""
var _repair_work := 0.0
var _repair_cadence := 0.0
var _repair_movement := 0.0
var _repair_started := false
var _repair_contacted := false
var _repair_stroke := -1
var _presentation: Node

func _ready() -> void:
	vehicle = get_parent()
	process_mode = Node.PROCESS_MODE_PAUSABLE
	bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	for kind in LOOP_KINDS:
		var voice: AudioStreamPlayer2D = self if kind == "idle" else AudioStreamPlayer2D.new()
		if voice != self:
			voice.name = "Convoy" + kind.capitalize()
			add_child(voice)
		_setup_voice(voice)
		var recording := _load_recording(recording_path(kind))
		if recording != null:
			recording = recording.duplicate()
			recording.loop_mode = AudioStreamWAV.LOOP_FORWARD
			recording.loop_begin = 0
			recording.loop_end = roundi(recording.get_length() * recording.mix_rate)
			voice.stream = recording
		layers[kind] = voice
		_gains[kind] = 0.0
	for kind: String in EFFECTS:
		var recording := _load_recording(recording_path(kind))
		if recording != null: effects[kind] = recording
	for index in MAX_EFFECT_VOICES:
		var voice := AudioStreamPlayer2D.new()
		voice.name = "ConvoyFoley%d" % index
		_setup_voice(voice)
		add_child(voice)
		effect_voices.append(voice)
	tree_exiting.connect(stop_effects)

func _setup_voice(voice: AudioStreamPlayer2D) -> void:
	voice.process_mode = Node.PROCESS_MODE_PAUSABLE
	voice.bus = bus
	voice.max_distance = 1100.0
	voice.attenuation = 1.4
	voice.panning_strength = .65
	voice.volume_db = -80.0
	voice.max_polyphony = 1

static func recording_path(kind: String) -> String:
	return ENGINE_PATH if kind == "idle" else RECORDING_PATTERN % kind

func _load_recording(path: String) -> AudioStreamWAV:
	if ResourceLoader.exists(path): return load(path) as AudioStreamWAV
	if FileAccess.file_exists(path): return AudioStreamWAV.load_from_file(path)
	return null

func _enabled() -> bool:
	if not is_inside_tree() or get_tree().paused: return false
	var index := AudioServer.get_bus_index(bus)
	return index < 0 or not AudioServer.is_bus_mute(index)

func play_effect(requested_kind: String) -> bool:
	var kind := "door_close" if requested_kind == "door" else requested_kind
	if not _enabled() or not effects.has(kind): return false
	var spec: Dictionary = EFFECTS[kind]
	var now := Time.get_ticks_msec()
	if now - int(_effect_cooldown.get(kind, -100000)) < int(spec.cooldown): return false
	var selected: AudioStreamPlayer2D
	var oldest := 9223372036854775807
	var lowest_priority := 2147483647
	for voice in effect_voices:
		if not voice.playing:
			selected = voice
			break
		var priority := int(voice.get_meta("priority", 0))
		var order := int(voice.get_meta("serial", 0))
		if priority > int(spec.priority): continue
		if priority < lowest_priority or (priority == lowest_priority and order < oldest):
			lowest_priority = priority
			oldest = order
			selected = voice
	if not is_instance_valid(selected): return false
	selected.stop()
	selected.stream = effects[kind]
	selected.pitch_scale = 1.0
	selected.volume_db = float(spec.db)
	# Tools belong beside the rear axle; door foley belongs beside the cab.
	# Existing gains, cooldowns and the four-voice budget apply to the new bank.
	selected.position = _effect_position(kind)
	_voice_serial += 1
	selected.set_meta("serial", _voice_serial)
	selected.set_meta("priority", int(spec.priority))
	selected.set_meta("kind", kind)
	selected.play()
	_effect_cooldown[kind] = now
	effects_played += 1
	return true

func _effect_position(kind: String) -> Vector2:
	if not is_instance_valid(vehicle): return Vector2.ZERO
	var side: float=float(vehicle.facing) if "facing" in vehicle else 1.0
	if kind in REAR_WHEEL_EFFECTS:
		var point: Vector2=vehicle.service_point() if vehicle.has_method("service_point") else vehicle.global_position+Vector2(-65*side,-20)
		return to_local(point)
	var offset:=Vector2(58*side,-32)
	if kind in ["door_open", "door_close"]: offset=Vector2(57*side,-34)
	elif kind=="refuel": offset=Vector2(-41*side,-24)
	elif kind=="brake": offset=Vector2(0,-11)
	return to_local(vehicle.to_global(offset))

func _journey() -> Dictionary:
	if is_instance_valid(vehicle) and "journey_state" in vehicle and vehicle.journey_state is Dictionary:
		return vehicle.journey_state
	return {}

func _observe_journey(journey: Dictionary, audible: bool) -> void:
	if not journey.has("event_serial"): return
	var current := int(journey.event_serial)
	# The initial snapshot and a freshly replaced/retried vehicle are baselines.
	if _last_event_serial < 0 or current < _last_event_serial:
		_last_event_serial = current
		return
	var incoming = journey.get("events", [])
	if incoming is Array and audible:
		for event in incoming:
			if not event is Dictionary: continue
			var serial := int(event.get("serial", 0))
			if serial <= _last_event_serial or serial > current: continue
			var kind := str(event.get("kind", ""))
			if JOURNEY_EFFECTS.has(kind): play_effect(JOURNEY_EFFECTS[kind])
	# Advance even while muted; turning SFX back on must not replay old work.
	_last_event_serial = current

func _stroke_index(journey: Dictionary, step: String) -> int:
	if not journey.has("phase_time") or step not in ["jack", "tighten"]: return -1
	var clock := float(journey.phase_time)
	if not is_instance_valid(_presentation): _presentation = vehicle.get_node_or_null("ConvoyPresentation")
	if is_instance_valid(_presentation) and _presentation.has_method("service_clock"):
		clock = _presentation.service_clock(journey)
	# The jack's lowest screen grip point is at .25 of each 1.8 Hz stroke. The
	# socket starts its loaded pull at the authority's marked timing window.
	return floori(clock * 1.8 + .75) if step == "jack" else floori(clock / Journey.TIMING_PERIOD + 1.0 - Journey.TIMING_START)

func _repair_foley(journey: Dictionary, delta: float) -> void:
	var step := str(journey.get("repair_step", "none"))
	var work := float(journey.get("repair_work", 0.0))
	var stroke := _stroke_index(journey, step)
	_repair_cadence = maxf(0.0, _repair_cadence - delta)
	if step != _repair_step:
		_repair_step = step
		_repair_work = work
		_repair_cadence = .30
		_repair_movement = 0.0
		_repair_started = false
		_repair_contacted = work >= REPAIR_CONTACT_WORK
		_repair_stroke = stroke
		return
	var operator := int(journey.get("repair_operator", 0)) > 0 or bool(journey.get("solo_assist", false))
	var working := str(journey.get("phase", "")) == "repair" and WORK_EFFECTS.has(step) and operator
	var advance := maxf(0, work - _repair_work)
	_repair_movement = minf(1.0, _repair_movement + advance) if working and work >= _repair_work else 0.0
	# Step-enter events describe a requested job; only actual work makes foley.
	if working and advance > 0 and _repair_movement > .005 and not _repair_started:
		_repair_started = play_effect(WORK_EFFECTS[step])
		_repair_cadence = 1.0 / 1.8 if step == "jack" else .58
		_repair_movement = 0.0
	elif working and advance > 0 and _repair_movement > .014 and step in ["jack", "remove", "tighten"] and (stroke > _repair_stroke if stroke >= 0 else _repair_cadence <= 0):
		play_effect(WORK_EFFECTS[step])
		_repair_cadence = 1.0 / 1.8 if step == "jack" else .58
		_repair_movement = 0.0
	# These impacts follow real axle/ground contact, not the request to start
	# a stage. Joining, muting or repeating a snapshot never replays them.
	if working and advance > 0 and not _repair_contacted and work >= REPAIR_CONTACT_WORK and step in ["fit", "lower"]:
		play_effect(step + "_contact")
		_repair_contacted = true
	_repair_stroke = stroke
	_repair_work = work

func _process(delta: float) -> void:
	if not is_instance_valid(vehicle):
		stop_effects()
		return
	var journey := _journey()
	var audible := _enabled()
	_observe_journey(journey, audible)
	var speed := absf(float(vehicle.velocity.x))
	var rate := clampf(speed / maxf(1.0, float(vehicle.top_speed)), 0.0, 1.0)
	var driver_present := is_instance_valid(vehicle.driver_seat) and is_instance_valid(vehicle.driver_seat.occupant)
	var active: bool = not vehicle.destroyed and vehicle.fuel > 0 and (driver_present or speed > 2)
	if journey.has("phase"):
		active = not vehicle.destroyed and vehicle.fuel > 0 and str(journey.phase) in ["starting", "driving"]
	var crew := 0
	for seat in vehicle.seats:
		if is_instance_valid(seat.occupant): crew += 1
	# A hysteresis band avoids shifts caused by replica velocity quantization.
	var gear := _last_gear
	if rate > (.31 if gear == 0 else .67): gear = mini(2, gear + 1)
	elif rate < (.22 if gear == 1 else .55): gear = maxi(0, gear - 1)
	var safe_delta := clampf(delta, .0001, .1)
	var acceleration_rate := clampf((speed - _last_speed) / safe_delta / maxf(1.0, float(vehicle.acceleration)), -1.0, 1.0) if _observed else 0.0
	if _observed and audible:
		if active != _last_running and (not journey.has("phase") or not active): play_effect("start" if active else "stop")
		if crew != _last_crew: play_effect("door_close" if crew > _last_crew else "door_open")
		if gear != _last_gear and active:
			play_effect("gear")
			_gear_sag = .085
		if acceleration_rate > .55 and rate > .08 and _last_speed < vehicle.top_speed * .12 and active: play_effect("accelerate")
		if acceleration_rate < -.65 and _last_speed > vehicle.top_speed * .35 and not vehicle.destroyed and str(journey.get("phase", "")) != "repair": play_effect("brake")
		if vehicle.fuel > _last_fuel + .5: play_effect("refuel")
	_observed = true
	_last_running = active
	_last_crew = crew
	_last_gear = gear
	_last_fuel = vehicle.fuel
	_last_speed = speed
	if not audible:
		stop_effects()
		_repair_step = str(journey.get("repair_step", "none"))
		_repair_work = float(journey.get("repair_work", 0.0))
		_repair_contacted = _repair_work >= REPAIR_CONTACT_WORK
		_repair_stroke = _stroke_index(journey, _repair_step)
		_repair_movement = 0.0
		return
	_repair_foley(journey, safe_delta)
	_speed_rate = lerpf(_speed_rate, rate, 1.0 - exp(-safe_delta * 8.0))
	_load = lerpf(_load, clampf(.18 + rate * .48 + maxf(0, acceleration_rate) * .34, 0, 1), 1.0 - exp(-safe_delta * 7.0))
	_gear_sag = move_toward(_gear_sag, 0.0, safe_delta * .24)
	var rolling := smoothstep(.01, .12, _speed_rate) if not vehicle.destroyed else 0.0
	_update_layer("idle", db_to_linear(-28.0 - _speed_rate * 4.0) if active else 0.0, .88 + _speed_rate * .34 - _gear_sag, safe_delta)
	_update_layer("torque", db_to_linear(-35.0 + _load * 10.0) * smoothstep(.04, .22, _speed_rate) if active else 0.0, .87 + _speed_rate * .37 - _gear_sag, safe_delta)
	_update_layer("road", db_to_linear(-35.0 + _speed_rate * 6.0) * rolling, .84 + _speed_rate * .34, safe_delta)
	_update_layer("clatter", db_to_linear(-39.0 + _speed_rate * 6.0) * rolling, .94 + _speed_rate * .13, safe_delta)

func _update_layer(kind: String, target: float, pitch: float, delta: float) -> void:
	var voice: AudioStreamPlayer2D = layers[kind]
	var gain := lerpf(float(_gains[kind]), target, 1.0 - exp(-delta * (8.0 if target > float(_gains[kind]) else 12.0)))
	_gains[kind] = gain
	voice.pitch_scale = move_toward(voice.pitch_scale, clampf(pitch, .7, 1.5), delta * .6)
	voice.volume_db = linear_to_db(maxf(gain, .00001))
	if gain > .00025 and voice.stream != null:
		if not voice.playing: voice.play()
	elif voice.playing: voice.stop()

func stop_effects() -> void:
	for kind: String in layers:
		var voice: AudioStreamPlayer2D = layers[kind]
		voice.stop()
		voice.volume_db = -80.0
		_gains[kind] = 0.0
	for voice in effect_voices: voice.stop()

func _exit_tree() -> void:
	stop_effects()
	for kind: String in layers:
		var voice: AudioStreamPlayer2D = layers[kind]
		voice.stream = null
	for voice in effect_voices: voice.stream = null
