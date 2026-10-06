extends RefCounted
## Additional authored mechanical performances. All offsets are presentation only.
const STATES: Array[String] = ["deploy", "scan", "stabilize", "impact", "service", "purge", "destroy"]
const LABELS := {"deploy":"ANTRIEB AUSFAHREN", "scan":"ZIEL ERFASSEN", "stabilize":"ABFANGEN", "impact":"TREFFER ABFANGEN", "service":"VERSCHLUSS WARTEN", "purge":"KÜHLUNG ENTLÜFTEN", "destroy":"ZUSAMMENBRUCH"}
const DURATIONS := {"deploy":1.35, "scan":1.65, "stabilize":0.86, "impact":0.68, "service":1.22, "purge":1.8, "destroy":1.45}
# Mass, actuator travel, sensor mast height, and characteristic roll. Variants
# have independent values even when they share a replaceable painted chassis.
const PROFILES := {
	"runner":Vector4(0.76,1.3,6,1.2), "strider":Vector4(1.0,1,10,0.8),
	"breaker":Vector4(1.22,0.88,7,0.65), "assault":Vector4(0.85,1.15,8,1.1),
	"colossus":Vector4(1.35,1.1,14,0.6), "siege":Vector4(1.3,0.85,11,0.45),
	"shield_guard":Vector4(1.15,0.7,9,0.65), "lancer":Vector4(0.82,1.45,7,1.3),
	"sniper":Vector4(1.15,0.65,17,0.55), "demolisher":Vector4(1.32,1.2,8,0.7),
	"repair_crawler":Vector4(0.94,1.1,13,0.8), "bastion":Vector4(1.38,0.9,12,0.55),
	"scout_drone":Vector4(0.75,1.4,6,1.3), "gunship":Vector4(1.05,1,10,0.8),
	"bomber":Vector4(1.2,0.88,9,0.55), "interceptor":Vector4(0.78,1.3,5,1.25),
	"shield_airship":Vector4(1.38,0.8,13,0.4), "sky_fortress":Vector4(1.45,0.85,16,0.4),
	"rocket_drone":Vector4(0.8,1.1,4,1.0), "patrol_plane":Vector4(0.92,0.75,3,0.75),
	"tiltrotor":Vector4(1.15,0.78,5,0.6), "dive_bomber":Vector4(1.0,0.80,3,0.7),
	"pulse_fighter":Vector4(0.98,0.72,4,0.65), "heavy_zeppelin":Vector4(1.65,0.55,5,0.25),
	"boss":Vector4(1.5,1.25,18,0.5),
	"scout_car":Vector4(0.88,0.62,4,0.70), "mortar_carrier":Vector4(1.42,0.34,3,0.30), "battle_tank":Vector4(1.55,0.29,4,0.22),
}

static func duration(state: String, kind: String) -> float:
	var traits: Vector4 = PROFILES.get(kind, PROFILES.strider)
	return float(DURATIONS.get(state,1.0))*sqrt(traits.x)

static func smooth(value: float) -> float:
	var t := clampf(value,0,1)
	return t*t*(3.0-2.0*t)

static func pulse(phase: float, rise: float = 0.25, fall: float = 0.7) -> float:
	return smooth(phase/rise)*(1.0-smooth((phase-fall)/(1.0-fall)))

static func sample(state: String, phase: float, kind: String, airborne: bool = false) -> Dictionary:
	var traits: Vector4 = PROFILES.get(kind, PROFILES.strider)
	var p := clampf(phase,0,1)
	var envelope := pulse(p)
	var pose := {"offset":Vector2.ZERO, "roll":0.0, "knee":0.0, "sensor":0.0, "mast":0.0, "hatch":0.0, "steam":0.0, "slide":0.0, "rotor":0.0, "thrust":0.0, "foot":0.0, "phase":p}
	match state:
		"deploy":
			var lift := pulse(p,0.42,0.66)
			pose.offset = Vector2(0, -5.0*lift*traits.y)
			pose.knee = -3.0*lift
			pose.foot = 4.0*lift if not airborne else 0.0
			pose.mast = lift
			pose.sensor = -0.5*lift
			pose.rotor = -0.18*lift*traits.w
			pose.thrust = 0.7*lift
			pose.hatch = 0.5*envelope
		"scan":
			# A deliberate left/right optical sweep, then an eased return.
			pose.sensor = sin(p*TAU-PI*0.5)*0.85*envelope
			pose.mast = envelope
			pose.roll = sin(p*TAU)*0.035*envelope*traits.w
			pose.offset = Vector2(sin(p*TAU)*1.6*envelope*traits.y,0)
		"stabilize":
			var compress := pulse(p,0.16,0.36)
			var settle := sin(p*TAU*1.5)*sin(p*PI)*exp(-p*3.0)
			pose.offset = Vector2(-3.0*compress,4.5*compress+settle*2)*traits.y
			pose.roll = -0.075*compress*traits.w
			pose.knee = 4.0*compress
			pose.rotor = 0.19*compress*traits.w
			pose.thrust = 0.6*compress
		"impact":
			# Fast yielding, controlled hydraulic recovery; no one-frame jitter.
			var recoil := pulse(p,0.12,0.22)
			var recovery := sin(p*TAU)*sin(p*PI)*0.7
			pose.offset = Vector2(5.5*recoil,2.5*recoil+recovery)*traits.y
			pose.roll = 0.105*recoil*traits.w
			pose.knee = 2.6*recoil
			pose.rotor = -0.24*recoil*traits.w
			pose.thrust = 0.45*recoil
		"service":
			var unlock := pulse(p,0.2,0.52)
			var bolt := pulse(p,0.38,0.56)
			pose.hatch = unlock
			pose.slide = bolt*7.0*traits.y
			pose.offset = Vector2(bolt*1.4,0)
			pose.mast = 0.2*envelope
		"purge":
			pose.hatch = envelope
			pose.steam = smooth((p-0.16)/0.18)*(1.0-smooth((p-0.62)/0.3))
			pose.offset = Vector2(0,-1.7*envelope)
			pose.knee = -envelope
			pose.thrust = -0.2*envelope
		"destroy":
			var drop := smooth(p/0.62)
			pose.offset = Vector2(9.0*drop,27.0*drop)
			pose.roll = 0.32*drop*traits.w
			pose.knee = 20.0*drop
			pose.rotor = 0.35*drop
	return pose
