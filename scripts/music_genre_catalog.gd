class_name MusicGenreCatalog
extends RefCounted
## A score keeps its environment's tonic and motif across styles. Genre changes
## the arrangement, tempo and timbre; the native engine writes the actual notes.

const IDS := ["level_default","minimal_techno","schranz","hip_hop","breakbeat"]
const SELECTIONS := IDS
const GENRES := ["minimal_techno","schranz","hip_hop","breakbeat"]
const NATIVE_IDS := {"minimal_techno":0,"schranz":1,"hip_hop":2,"breakbeat":3}
const DEFAULTS := {
	"sector07":"minimal_techno", "ash_foundry":"minimal_techno",
	"abandoned_harbor":"minimal_techno", "basalt_quarry":"minimal_techno",
	"overgrown_steelworks":"minimal_techno", "frozen_rail_yard":"minimal_techno",
	"iron_canyon":"minimal_techno", "flooded_power_station":"minimal_techno",
	"mountain_pass":"minimal_techno", "storm_dam":"minimal_techno",
	"sulfur_refinery":"minimal_techno", "radar_highlands":"minimal_techno",
	"buried_megafactory":"minimal_techno",
}

static func valid_style(style: Variant) -> bool:
	return style is String and style in IDS

static func valid_selection(selection: Variant) -> bool:
	return valid_style(selection)

static func selection_label(id: String) -> String:
	return str({"level_default":"Schauplatz-Empfehlung","minimal_techno":"Minimal Techno","schranz":"Schranz","hip_hop":"Hip-Hop / Boom-Bap","breakbeat":"Breakbeat"}.get(id,"Schauplatz-Empfehlung"))

static func resolve(environment: String, selection: String = "level_default") -> String:
	return str(DEFAULTS.get(environment,"minimal_techno")) if selection == "level_default" or not valid_style(selection) else selection

static func apply(theme: Dictionary, genre: String) -> Dictionary:
	var result := theme.duplicate(true)
	genre = genre if genre in GENRES else "minimal_techno"
	var authored_bpm := float(theme.get("bpm",118.0))
	result.genre = int(NATIVE_IDS[genre])
	# Stage zero remains a sustained cinematic statement in every genre. Its
	# real, sparse drum hits cannot trigger the stronger combat choreography.
	result.stage_dynamics = [0.28,0.44,0.83,1.0]
	match genre:
		"schranz":
			result.bpm = snappedf(clampf(144.0+(authored_bpm-118.0)*0.6,140.0,150.0),0.1)
			result.punch = clampf(float(result.punch)+0.12,0.0,0.96)
			result.bass_weight = clampf(float(result.bass_weight)+0.05,0.0,0.80)
			result.swing = 0.0
			result.density = clampf(float(result.density)+0.14,0.0,0.90)
			result.pad_level = float(result.pad_level)*0.65
			result.room = float(result.room)*0.70
		"hip_hop":
			result.bpm = snappedf(clampf(90.0+(authored_bpm-118.0)*0.5,84.0,96.0),0.1)
			result.swing = 0.18
			result.dust = clampf(float(result.dust)+0.12,0.0,0.55)
			result.punch = clampf(float(result.punch)*0.88,0.0,1.0)
			result.pad_level = float(result.pad_level)*1.15
			result.density = clampf(float(result.density)*0.82,0.0,1.0)
		"breakbeat":
			result.bpm = snappedf(clampf(130.0+(authored_bpm-118.0)*0.6,124.0,136.0),0.1)
			result.swing = 0.06
			result.punch = clampf(float(result.punch)+0.04,0.0,0.92)
			result.density = clampf(float(result.density)+0.08,0.0,0.85)
			result.phrase_variation = clampf(float(result.phrase_variation)+0.08,0.0,0.65)
			result.pad_level = float(result.pad_level)*0.85
	return result
