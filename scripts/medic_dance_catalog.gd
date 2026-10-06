extends RefCounted
## SAN-1's software levels are researched in the shared tech tree. The repertoire
## is cosmetic and never consumes supplies or changes rescue/logistics timing.
const STYLES := ["san_kick_nod", "san_servo_lock", "san_track_shuffle", "san_arm_wave", "san_bunker_freeze"]
const LABELS := ["Kern-Takt", "Servo-Lock", "Ketten-Shuffle", "Hydraulik-Welle", "Bunker-Freeze"]
const MAX_LEVEL := 5
const PHRASE_BEATS := 16.0

static func available_styles(software_level: int) -> Array[String]:
	var result: Array[String] = []
	for index in clampi(software_level, 0, MAX_LEVEL):
		result.append(str(STYLES[index]))
	return result

static func required_level(style: String) -> int:
	var index := STYLES.find(style)
	return index + 1 if index >= 0 else 0

static func label(style: String) -> String:
	var index := STYLES.find(style)
	return str(LABELS[index]) if index >= 0 else ""

static func style_for(software_level: int, audible_beats: float) -> String:
	var learned := available_styles(software_level)
	if learned.is_empty() or not is_finite(audible_beats):
		return ""
	var phrase := floori(maxf(0.0, audible_beats) / PHRASE_BEATS)
	return learned[posmod(phrase, learned.size())]
