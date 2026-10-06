extends RefCounted
## Original mono sources; runtime spatial voices provide the audible pan.
const PROPULSION := {
	"rotor":{"stream_path":"res://assets/audio/air_engine_rotor_v1.wav","level_db":-18.0,"max_distance":1550.0},
	"propeller":{"stream_path":"res://assets/audio/air_engine_propeller_v1.wav","level_db":-19.0,"max_distance":1650.0},
	"tiltrotor":{"stream_path":"res://assets/audio/air_engine_tiltrotor_v1.wav","level_db":-17.0,"max_distance":1750.0},
	"jet":{"stream_path":"res://assets/audio/air_engine_jet_v1.wav","level_db":-18.0,"max_distance":1800.0},
	"airship":{"stream_path":"res://assets/audio/air_engine_airship_v1.wav","level_db":-18.0,"max_distance":1800.0},
	"vtol":{"stream_path":"res://assets/audio/air_engine_vtol_v1.wav","level_db":-17.0,"max_distance":1750.0},
}
const PROFILES := {
	"scout_drone":{"family":"rotor","pitch":1.22,"gain_db":-3.0,"fire_key":"air_dart"},
	"gunship":{"family":"rotor","pitch":1.0,"gain_db":0.0,"fire_key":"air_tracer"},
	"bomber":{"family":"rotor","pitch":0.80,"gain_db":1.0,"fire_key":"air_bomb"},
	"interceptor":{"family":"jet","pitch":1.13,"gain_db":0.0,"fire_key":"air_tracer"},
	"shield_airship":{"family":"airship","pitch":1.05,"gain_db":0.0,"fire_key":"air_arc","charge_key":"air_charge"},
	"sky_fortress":{"family":"vtol","pitch":0.87,"gain_db":1.0,"fire_key":"air_rocket","lock_key":"air_lock"},
	"rocket_drone":{"family":"rotor","pitch":1.12,"gain_db":-1.0,"fire_key":"air_rocket","lock_key":"air_lock"},
	"patrol_plane":{"family":"propeller","pitch":1.08,"gain_db":-1.0,"fire_key":"air_tracer"},
	"tiltrotor":{"family":"tiltrotor","pitch":1.0,"gain_db":0.0,"fire_key":"air_tracer"},
	"dive_bomber":{"family":"propeller","pitch":0.91,"gain_db":1.0,"fire_key":"air_bomb"},
	"pulse_fighter":{"family":"jet","pitch":1.25,"gain_db":-1.0,"fire_key":"air_arc","charge_key":"air_charge"},
	"heavy_zeppelin":{"family":"airship","pitch":0.78,"gain_db":2.0,"fire_key":"air_rocket","lock_key":"air_lock"},
}

static func profile_for(kind: String) -> Dictionary:
	if not PROFILES.has(kind): return {}
	var result: Dictionary=PROFILES[kind].duplicate()
	result.merge(PROPULSION[result.family])
	return result
