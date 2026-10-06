class_name AirEnemyCatalog
extends RefCounted
## Finite aircraft, separate firing patterns and bounded campaign scaling.

const CLASS_ORDER: Array[String] = ["scout_drone", "gunship", "bomber", "interceptor", "shield_airship", "sky_fortress", "rocket_drone", "patrol_plane", "tiltrotor", "dive_bomber", "pulse_fighter", "heavy_zeppelin"]
const INTRO_WAVES := {"scout_drone":7,"gunship":9,"bomber":11,"interceptor":13,"shield_airship":16,"sky_fortress":18,"rocket_drone":8,"patrol_plane":10,"tiltrotor":12,"dive_bomber":14,"pulse_fighter":15,"heavy_zeppelin":19}
const ENTRY_GRACE := 8.0
const MAX_ACTIVE := 5
const PROFILES := {
	"scout_drone": {"label":"SPÄHDROHNE","hp":64.0,"speed":80.0,"damage":9.0,"cooldown":4.0,"windup":0.85,"burst":1,"burst_gap":0.2,"projectile_speed":300.0,"gravity":0.0,"lane":109.0,"hitbox":Vector2(48,32),"body_size":Vector2(57,34),"atlas":"scout_drone","propulsion":"rotor","scrap":1,"cores":1,"pattern":"tracking","flavor":"dart"},
	"gunship": {"label":"STURMHELIKOPTER","hp":110.0,"speed":61.0,"damage":7.0,"cooldown":5.0,"windup":1.1,"burst":3,"burst_gap":0.27,"projectile_speed":335.0,"gravity":0.0,"lane":142.0,"hitbox":Vector2(83,42),"body_size":Vector2(83,44),"atlas":"gunship","propulsion":"rotor","scrap":2,"cores":2,"pattern":"burst","flavor":"tracer"},
	"bomber": {"label":"LASTENBOMBER","hp":125.0,"speed":45.0,"damage":25.0,"cooldown":6.2,"windup":1.5,"burst":1,"burst_gap":0.2,"projectile_speed":270.0,"gravity":180.0,"lane":89.0,"hitbox":Vector2(102,43),"body_size":Vector2(97,43),"atlas":"bomber","propulsion":"rotor","scrap":2,"cores":2,"pattern":"bomb","flavor":"bomb"},
	"interceptor": {"label":"STURZJÄGER","hp":88.0,"speed":108.0,"damage":10.0,"cooldown":4.7,"windup":1.0,"burst":2,"burst_gap":0.22,"projectile_speed":360.0,"gravity":0.0,"lane":91.0,"hitbox":Vector2(79,32),"body_size":Vector2(69,32),"atlas":"interceptor","propulsion":"jet","scrap":2,"cores":2,"pattern":"dive","flavor":"tracer"},
	"shield_airship": {"label":"SCHIRMLUFTSCHIFF","hp":210.0,"speed":31.0,"damage":14.0,"cooldown":6.0,"windup":1.3,"burst":2,"burst_gap":0.45,"projectile_speed":270.0,"gravity":0.0,"lane":110.0,"hitbox":Vector2(130,49),"body_size":Vector2(124,48),"atlas":"shield_airship","propulsion":"airship","scrap":3,"cores":3,"pattern":"shield","flavor":"arc"},
	"sky_fortress": {"label":"HIMMELSFESTUNG","hp":265.0,"speed":25.0,"damage":38.0,"cooldown":7.0,"windup":2.2,"burst":1,"burst_gap":0.2,"projectile_speed":235.0,"gravity":0.0,"lane":134.0,"hitbox":Vector2(143,64),"body_size":Vector2(133,65),"atlas":"sky_fortress","propulsion":"vtol","scrap":4,"cores":4,"pattern":"charge","flavor":"rocket"},
	"rocket_drone": {"label":"RAKETENDROHNE","hp":76.0,"speed":85.0,"damage":12.0,"cooldown":6.4,"windup":1.4,"burst":2,"burst_gap":0.48,"projectile_speed":280.0,"gravity":0.0,"lane":122.0,"hitbox":Vector2(63,32),"body_size":Vector2(72,34),"atlas":"rocket_drone","propulsion":"rotor","scrap":2,"cores":2,"pattern":"rocket_pair","flavor":"rocket"},
	"patrol_plane": {"label":"PATROUILLENFLIEGER","hp":92.0,"speed":96.0,"damage":5.0,"cooldown":6.0,"windup":1.2,"burst":4,"burst_gap":0.22,"projectile_speed":340.0,"gravity":0.0,"lane":91.0,"hitbox":Vector2(87,34),"body_size":Vector2(92,35),"atlas":"patrol_plane","propulsion":"propeller","scrap":2,"cores":2,"pattern":"strafe","flavor":"tracer"},
	"tiltrotor": {"label":"KIPPROTOR","hp":150.0,"speed":70.0,"damage":8.0,"cooldown":6.2,"windup":1.25,"burst":3,"burst_gap":0.35,"projectile_speed":320.0,"gravity":0.0,"lane":133.0,"hitbox":Vector2(93,43),"body_size":Vector2(96,45),"atlas":"tiltrotor","propulsion":"tiltrotor","scrap":3,"cores":2,"pattern":"convert","flavor":"tracer"},
	"dive_bomber": {"label":"STURZBOMBER","hp":115.0,"speed":114.0,"damage":17.0,"cooldown":7.3,"windup":1.65,"burst":2,"burst_gap":0.55,"projectile_speed":255.0,"gravity":220.0,"lane":82.0,"hitbox":Vector2(92,36),"body_size":Vector2(98,38),"atlas":"dive_bomber","propulsion":"propeller","scrap":3,"cores":3,"pattern":"dive_bomb","flavor":"bomb"},
	"pulse_fighter": {"label":"IMPULSJÄGER","hp":140.0,"speed":104.0,"damage":18.0,"cooldown":7.0,"windup":1.8,"burst":2,"burst_gap":0.62,"projectile_speed":315.0,"gravity":0.0,"lane":113.0,"hitbox":Vector2(99,36),"body_size":Vector2(104,38),"atlas":"pulse_fighter","propulsion":"jet","scrap":3,"cores":3,"pattern":"pulse","flavor":"arc"},
	"heavy_zeppelin": {"label":"BELAGERUNGSZEPPELIN","hp":320.0,"speed":24.0,"damage":24.0,"cooldown":8.0,"windup":2.4,"burst":2,"burst_gap":0.85,"projectile_speed":245.0,"gravity":0.0,"lane":98.0,"hitbox":Vector2(159,56),"body_size":Vector2(168,58),"atlas":"heavy_zeppelin","propulsion":"airship","scrap":5,"cores":4,"pattern":"heavy_burst","flavor":"rocket"},
}

static func is_air(kind: String) -> bool:
	return PROFILES.has(kind)

static func profile(kind: String) -> Dictionary:
	var result: Dictionary = PROFILES.get(kind, PROFILES.scout_drone).duplicate(true)
	result.body_size = AircraftArtCatalog.hull_size(kind,float(result.body_size.x))
	result.hitbox *= .85
	result["scale"] = .85
	return result

static func available(wave: int) -> Array[String]:
	var result: Array[String] = []
	for kind in CLASS_ORDER:
		if int(INTRO_WAVES[kind]) <= wave: result.append(kind)
	return result

static func introduction(wave: int) -> String:
	for kind in CLASS_ORDER:
		if int(INTRO_WAVES[kind]) == wave: return kind
	return ""
