extends RefCounted
## Presentation-only pacing and gestures; movement, tool timing and stats stay
## in their gameplay systems. Shared by worker visuals and menu portraits.

const Additional := preload("res://scripts/worker_gesture_library.gd")

const PROFILES := {
	"mara":{"walk_rate":1.0,"idle_rate":0.9,"wait_min":3.0,"wait_max":6.0,"gestures":["radio_check","strap_check"]},
	"branko":{"walk_rate":0.82,"idle_rate":0.72,"wait_min":4.0,"wait_max":7.0,"gestures":["shoulder_roll","beard_check"]},
	"ivo":{"walk_rate":1.18,"idle_rate":1.15,"wait_min":2.5,"wait_max":5.0,"gestures":["goggles_check","tool_check"]},
	"nora":{"walk_rate":0.96,"idle_rate":0.85,"wait_min":3.0,"wait_max":6.0,"gestures":[]},
	"levin":{"walk_rate":1.16,"idle_rate":1.02,"wait_min":2.5,"wait_max":5.0,"gestures":[]},
	"selma":{"walk_rate":1.02,"idle_rate":0.88,"wait_min":3.0,"wait_max":6.0,"gestures":[]},
	"oskar":{"walk_rate":0.90,"idle_rate":0.76,"wait_min":3.5,"wait_max":6.5,"gestures":[]},
	"rika":{"walk_rate":1.07,"idle_rate":0.98,"wait_min":2.5,"wait_max":5.5,"gestures":[]},
}
const DURATIONS := {"radio_check":3.4,"strap_check":3.1,"shoulder_roll":4.0,"beard_check":3.6,"goggles_check":2.9,"tool_check":3.3}
static var _motion_frames: Dictionary = {}

static func frames(character_id: String) -> Dictionary:
	character_id = CharacterCatalog.presentation_id(character_id,"motion")
	if _motion_frames.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/workers/character_motion_frames.json"))
		_motion_frames = data if data is Dictionary else {}
	return _motion_frames.get(character_id,_motion_frames.get("mara",{}))

static func frame(character_id: String,pose: String,index: int) -> Dictionary:
	var poses: Dictionary = frames(character_id)
	if not poses.has(pose):
		return {}
	var sequence: Array = poses[pose]
	return sequence[clampi(index,0,sequence.size()-1)]

static func gestures(character_id: String) -> Array[String]:
	character_id = CharacterCatalog.presentation_id(character_id,"motion")
	var result: Array[String] = []
	result.assign(PROFILES.get(character_id,PROFILES.mara).gestures)
	result.append_array(Additional.names(character_id,"idle"))
	return result

static func duration(kind: String) -> float:
	return float(DURATIONS.get(kind,Additional.CATALOG.get(kind,{}).get("duration",1.0)))

static func has_animation(kind: String) -> bool:
	return DURATIONS.has(kind) or Additional.CATALOG.has(kind)

static func reaction(character_id: String,trigger: String) -> String:
	var kinds := Additional.names(character_id,trigger)
	return kinds[0] if not kinds.is_empty() else ""

static func playback_rate(character_id: String,pose: String) -> float:
	character_id = CharacterCatalog.presentation_id(character_id,"motion")
	var profile: Dictionary = PROFILES.get(character_id,PROFILES.mara)
	if pose.ends_with("walk"):
		return float(profile.walk_rate)
	if pose.ends_with("idle") or pose=="crouch":
		return float(profile.idle_rate)
	# Mining frame 3, world-distance climbing and weapon recoil are contracts.
	return 1.0

static func wait_range(character_id: String) -> Vector2:
	character_id = CharacterCatalog.presentation_id(character_id,"motion")
	if not PROFILES.has(character_id):
		return Vector2(6,12)
	var profile: Dictionary = PROFILES[character_id]
	return Vector2(profile.wait_min,profile.wait_max)

static func stance(pose: Dictionary,character_id: String) -> Dictionary:
	character_id = CharacterCatalog.presentation_id(character_id,"motion")
	var result := pose.duplicate(true)
	match character_id:
		"mara":
			result.hip = Vector2(-1,-25)
			result.shoulder = Vector2(0,-42)
			result.feet = [Vector2(-7,-3),Vector2(7,-3)]
			result.hands = [Vector2(-9,-27),Vector2(9,-31)]
		"branko":
			result.hip = Vector2(0,-24)
			result.shoulder = Vector2(-1,-41)
			result.feet = [Vector2(-10,-3),Vector2(10,-3)]
			result.hands = [Vector2(-12,-26),Vector2(11,-27)]
			result.head_shift = Vector2(0,1)
		"ivo":
			result.hip = Vector2(0,-26)
			result.shoulder = Vector2(3,-43)
			result.feet = [Vector2(-5,-3),Vector2(6,-3)]
			result.hands = [Vector2(-6,-31),Vector2(12,-34)]
			result.head_shift = Vector2(0,-1)
		"nora":
			result.hip = Vector2(-1,-24)
			result.shoulder = Vector2(-3,-41)
			result.feet = [Vector2(-9,-3),Vector2(9,-3)]
			result.hands = [Vector2(-10,-25),Vector2(9,-29)]
		"levin":
			result.hip = Vector2(1,-26)
			result.shoulder = Vector2(6,-43)
			result.feet = [Vector2(-8,-3),Vector2(5,-3)]
			result.hands = [Vector2(-7,-29),Vector2(11,-38)]
		"selma":
			result.hip = Vector2(0,-25)
			result.shoulder = Vector2(-1,-42)
			result.feet = [Vector2(-6,-3),Vector2(8,-3)]
			result.hands = [Vector2(-13,-29),Vector2(6,-31)]
		"oskar":
			result.hip = Vector2(-1,-24)
			result.shoulder = Vector2(-3,-41)
			result.feet = [Vector2(-10,-3),Vector2(9,-3)]
			result.hands = [Vector2(-12,-26),Vector2(10,-27)]
			result.head_shift = Vector2(0,1)
		"rika":
			result.hip = Vector2(1,-26)
			result.shoulder = Vector2(3,-43)
			result.feet = [Vector2(-6,-3),Vector2(7,-3)]
			result.hands = [Vector2(-8,-31),Vector2(12,-35)]
			result.head_shift = Vector2(0,-.5)
	return result
