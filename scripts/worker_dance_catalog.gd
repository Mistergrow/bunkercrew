extends RefCounted
## Local artistic preferences only. These values never enter gameplay or the
## network simulation. Feedback files are bounded, versioned and validated.
const BUILTIN_IDS := ["mara", "branko", "ivo", "nora", "levin", "selma", "oskar", "rika"]
static var IDS: Array[String] = _character_ids()
const STYLES := ["character_default","head_nod","shoulder_groove","hand_tap","side_sway","quiet_rock","breakdance","moonwalk","shuffle","running_man","robot","arm_wave","body_roll","crew_bounce","crew_two_step","crew_clap","mara_precision_step","mara_cross_turn","mara_box_glide","mara_lockstep","mara_pivot_finish","branko_foundry_stomp","branko_hammer_pop","branko_shoulder_hit","branko_low_bounce","branko_power_freeze","ivo_heel_switch","ivo_backslide","ivo_toe_weave","ivo_tick_tock","ivo_knee_wave","nora_flow_step","nora_ribbon_arms","nora_sway_turn","nora_cross_wave","nora_spiral_roll","levin_toprock","levin_six_step","levin_sweep","levin_cc_kick","levin_air_freeze","selma_skip_step","selma_v_step","selma_double_shuffle","selma_running_switch","selma_kick_turn","oskar_quarry_stride","oskar_brace_step","oskar_heel_press","oskar_pack_pop","oskar_tunnel_turn","rika_signal_step","rika_cable_wave","rika_switch_glide","rika_contact_shuffle","rika_coil_finish"]
const LABELS := ["Charakterstil","Kopfnicken","Schultergroove","Handtakt","Seitliches Wippen","Ruhiges Wiegen","Breakdance","Moonwalk","Shuffle","Running Man","Robot / Popping","Arm-Welle","Body Roll","Crew-Bounce","Crew-Two-Step","Crew-Clap","Präzisionsschritt","Kreuzschritt-Drehung","Quadrat-Gleiten","Takt-Lock","Pivot-Finale","Stechschritt","Hammer-Pop","Schulter-Hit","Tiefer Groove","Power-Freeze","Fersenwechsel","Rückwärtsgleiten","Zehenspuren","Tick-Tock","Kniewelle","Flow-Schritt","Band-Arme","Schwung-Drehung","Kreuzwelle","Spiral-Roll","Toprock","Six-Step","Bodensweep","CC-Kick","Air-Freeze","Skip-Step","V-Step","Doppel-Shuffle","Running-Switch","Kick-Drehung","Gruben-Schritt","Lastschritt","Fersen-Press","Rucksack-Pop","Tunnel-Pivot","Signal-Step","Kabel-Welle","Schalter-Gleiten","Kontakt-Shuffle","Spulen-Finale"]
const FULL_BODY_STYLES := ["breakdance","moonwalk","shuffle","running_man","robot","arm_wave","body_roll","crew_bounce","crew_two_step","crew_clap","mara_precision_step","mara_cross_turn","mara_box_glide","mara_lockstep","mara_pivot_finish","branko_foundry_stomp","branko_hammer_pop","branko_shoulder_hit","branko_low_bounce","branko_power_freeze","ivo_heel_switch","ivo_backslide","ivo_toe_weave","ivo_tick_tock","ivo_knee_wave","nora_flow_step","nora_ribbon_arms","nora_sway_turn","nora_cross_wave","nora_spiral_roll","levin_toprock","levin_six_step","levin_sweep","levin_cc_kick","levin_air_freeze","selma_skip_step","selma_v_step","selma_double_shuffle","selma_running_switch","selma_kick_turn","oskar_quarry_stride","oskar_brace_step","oskar_heel_press","oskar_pack_pop","oskar_tunnel_turn","rika_signal_step","rika_cable_wave","rika_switch_glide","rika_contact_shuffle","rika_coil_finish"]
const SHARED_STYLES := ["crew_bounce","crew_two_step","crew_clap"]
const UNLOCK_LEVELS := [2,4,6,8,10]
const _BUILTIN_UNIQUE_STYLES := {
	"mara":["mara_precision_step","mara_cross_turn","mara_box_glide","mara_lockstep","mara_pivot_finish"],
	"branko":["branko_foundry_stomp","branko_hammer_pop","branko_shoulder_hit","branko_low_bounce","branko_power_freeze"],
	"ivo":["ivo_heel_switch","ivo_backslide","ivo_toe_weave","ivo_tick_tock","ivo_knee_wave"],
	"nora":["nora_flow_step","nora_ribbon_arms","nora_sway_turn","nora_cross_wave","nora_spiral_roll"],
	"levin":["levin_toprock","levin_six_step","levin_sweep","levin_cc_kick","levin_air_freeze"],
	"selma":["selma_skip_step","selma_v_step","selma_double_shuffle","selma_running_switch","selma_kick_turn"],
	"oskar":["oskar_quarry_stride","oskar_brace_step","oskar_heel_press","oskar_pack_pop","oskar_tunnel_turn"],
	"rika":["rika_signal_step","rika_cable_wave","rika_switch_glide","rika_contact_shuffle","rika_coil_finish"],
}
const _BUILTIN_DEFAULT_STYLES := {"mara":"shuffle", "branko":"robot", "ivo":"moonwalk", "nora":"arm_wave", "levin":"breakdance", "selma":"running_man", "oskar":"robot", "rika":"shuffle"}
const _BUILTIN_GENRE_DEFAULTS := {
	"hip_hop": {"mara":"body_roll", "branko":"robot", "ivo":"moonwalk", "nora":"arm_wave", "levin":"breakdance", "selma":"running_man", "oskar":"robot", "rika":"shuffle"},
	"breakbeat": {"mara":"shuffle", "branko":"robot", "ivo":"moonwalk", "nora":"body_roll", "levin":"breakdance", "selma":"running_man", "oskar":"robot", "rika":"shuffle"},
}
static var UNIQUE_STYLES: Dictionary = _profile_map(_BUILTIN_UNIQUE_STYLES)
static var DEFAULT_STYLES: Dictionary = _profile_map(_BUILTIN_DEFAULT_STYLES)
static var GENRE_DEFAULTS: Dictionary = _genre_defaults()
const MOVEMENTS := {
	"head_nod": {"sway": 0.18, "shoulder": 0.22, "bounce": 0.45, "nod": 0.080, "wrist": 0.25, "offset": 0.0},
	"shoulder_groove": {"sway": 0.72, "shoulder": 1.85, "bounce": 0.75, "nod": 0.030, "wrist": 0.90, "offset": 0.12},
	"hand_tap": {"sway": 0.32, "shoulder": 0.60, "bounce": 0.35, "nod": 0.025, "wrist": 2.20, "offset": 0.05},
	"side_sway": {"sway": 1.30, "shoulder": -1.30, "bounce": 0.40, "nod": 0.035, "wrist": 0.65, "offset": 0.18},
	"quiet_rock": {"sway": 0.50, "shoulder": 0.38, "bounce": 0.25, "nod": 0.018, "wrist": 0.35, "offset": 0.22},
}

static func _character_ids() -> Array[String]:
	var result: Array[String] = []
	for entry: Dictionary in CharacterCatalog.CHARACTERS: result.append(str(entry.id))
	return result

static func _profile_map(authored: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: String in IDS:
		var profile := CharacterCatalog.presentation_id(id,"dance")
		var value: Variant = authored.get(profile,authored.mara)
		result[id] = value.duplicate(true) if value is Array else value
	return result

static func _genre_defaults() -> Dictionary:
	var result: Dictionary = {}
	for genre: String in _BUILTIN_GENRE_DEFAULTS: result[genre] = _profile_map(_BUILTIN_GENRE_DEFAULTS[genre])
	return result

static func defaults() -> Dictionary:
	return preload("res://scripts/audio_defaults.gd").dance_profiles()

static func character_style(id: String,genre: String="minimal_techno") -> String:
	var styles: Dictionary = GENRE_DEFAULTS.get(genre,DEFAULT_STYLES)
	return str(styles.get(id,"shuffle"))


static func owner(style: String) -> String:
	for id: String in BUILTIN_IDS:
		if style in _BUILTIN_UNIQUE_STYLES[id]: return id
	return ""

static func required_level(style: String) -> int:
	var character := owner(style)
	if character.is_empty(): return 1
	return int(UNLOCK_LEVELS[UNIQUE_STYLES[character].find(style)])

static func styles_for(id: String,include_auto: bool=true) -> Array[String]:
	var result: Array[String] = []
	if include_auto: result.append("character_default")
	for style: String in SHARED_STYLES: result.append(style)
	for style: String in UNIQUE_STYLES.get(id,UNIQUE_STYLES.mara): result.append(style)
	return result

static func label(style: String) -> String:
	var index := STYLES.find(style)
	return str(LABELS[index]) if index>=0 else str(LABELS[0])

static func available_styles(id: String,level: int) -> Array[String]:
	var result: Array[String] = []
	for style: String in styles_for(id,false):
		if required_level(style)<=level: result.append(style)
	return result

static func allowed(id: String,style: String,level: int,preview: bool=false) -> bool:
	if style=="character_default": return true
	if style not in STYLES: return false
	var character := owner(style)
	if not character.is_empty() and character!=CharacterCatalog.presentation_id(id,"dance"): return false
	if not preview and style not in styles_for(id,false): return false
	return preview or required_level(style)<=level

static func repertoire_style(id: String,genre: String,level: int,phrase: int) -> String:
	var learned: Array[String] = []
	for style: String in UNIQUE_STYLES.get(id,UNIQUE_STYLES.mara):
		if required_level(style)<=level: learned.append(style)
	if not learned.is_empty():
		return learned[posmod(phrase,learned.size())]
	var offset := 1 if genre in ["hip_hop","breakbeat"] else 0
	return str(SHARED_STYLES[posmod(phrase+offset,SHARED_STYLES.size())])

static func resolve_style(id: String,requested: String,genre: String,level: int,phrase: int,preview: bool=false) -> String:
	if requested!="character_default" and allowed(id,requested,level,preview): return requested
	return repertoire_style(id,genre,level,phrase)

static func valid_intensity(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= 1.5

static func valid_profiles(value: Variant) -> bool:
	if not value is Dictionary or value.size() > IDS.size():
		return false
	for id: Variant in value:
		if not id is String or id not in IDS:
			return false
		var profile: Variant = value[id]
		if not profile is Dictionary or profile.size() != 2 or profile.get("style") not in STYLES or not valid_intensity(profile.get("intensity")):
			return false
		var character := owner(str(profile.style))
		if not character.is_empty() and character!=CharacterCatalog.presentation_id(id,"dance"): return false
	return true

static func normalized_profiles(value: Variant) -> Dictionary:
	var result := defaults()
	if not value is Dictionary or value.size()>4096: return result
	# Temporarily absent pack preferences remain on disk, outside the active rig
	# configuration. Their presence must not reset the other characters' choices.
	var active: Dictionary = {}
	for id: Variant in value:
		if id is String and id in IDS: active[id] = value[id]
	if valid_profiles(active):
		for id: String in active: result[id] = active[id].duplicate()
	return result
