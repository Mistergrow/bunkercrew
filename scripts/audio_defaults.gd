extends RefCounted
## Baseline chosen from the player's current rhythm preferences. Saved profiles
## override these values; device-specific calibration stays local.
const MUSIC_VOLUME := 0.5
const SFX_VOLUME := 0.5
const VOICE_VOLUME := 0.5
const PARTNER_VOLUME := 0.5
# The default slider midpoint reproduces the chosen listening mix. These are
# channel gains before the existing authored trims and shared output ceiling.
const MIX_VERSION := 2
const REFERENCE_GAINS := {"Music": 0.8, "SFX": 0.5, "Voice": 0.2}
const LIVE_MUSIC := true
const MUSIC_STYLE := "level_default"
const RHYTHM_MOTION_REDUCED := false
const DANCE_INTENSITY := 1.5
const DANCE_PROFILES := {
	"mara": {"style": "character_default", "intensity": 1.0},
	"branko": {"style": "character_default", "intensity": 1.0},
	"ivo": {"style": "character_default", "intensity": 1.0},
	"nora": {"style": "character_default", "intensity": 1.0},
	"levin": {"style": "character_default", "intensity": 1.0},
	"selma": {"style": "character_default", "intensity": 1.0},
	"oskar": {"style": "character_default", "intensity": 1.0},
	"rika": {"style": "character_default", "intensity": 1.0},
}

static func dance_profiles() -> Dictionary:
	var result: Dictionary = {}
	for entry: Dictionary in CharacterCatalog.CHARACTERS:
		var id := str(entry.id)
		result[id] = DANCE_PROFILES.get(CharacterCatalog.presentation_id(id,"dance"),DANCE_PROFILES.mara).duplicate(true)
	return result

static func channel_gain(channel: String, slider: float) -> float:
	var reference_gain: float = REFERENCE_GAINS.get(channel, 0.5)
	var value := clampf(slider, 0.0, 1.0)
	return value * 2.0 * reference_gain if value <= 0.5 else lerpf(reference_gain, 1.0, (value - 0.5) * 2.0)

static func legacy_slider(channel: String, gain: float) -> float:
	var reference_gain: float = REFERENCE_GAINS.get(channel, 0.5)
	var value := clampf(gain, 0.0, 1.0)
	return 0.5 * value / reference_gain if value <= reference_gain else 0.5 + 0.5 * (value - reference_gain) / (1.0 - reference_gain)
