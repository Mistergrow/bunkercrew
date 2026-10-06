class_name MusicThemeCatalog
extends RefCounted
## One persistent musical identity per environment. Wave state changes arrangement,
## never the tonic, motif, seed or tempo of the piece.

const VERSION := 1
const Genres := preload("res://scripts/music_genre_catalog.gd")
const Rave := preload("res://scripts/rave_music_catalog.gd")
const RaveMeasurements := preload("res://scripts/rave_music_measurements.gd")
## Measured native score trim to -16.5 LUFS; source measurements live beside
## the extension in assets/audio/live/normalization.json.
const NORMALIZATION_DB := {
	"abandoned_harbor|breakbeat":-1.2,
	"abandoned_harbor|hip_hop":-2.1,
	"abandoned_harbor|minimal_techno":-1.8,
	"abandoned_harbor|schranz":-3.3,
	"ash_foundry|breakbeat":-1.1,
	"ash_foundry|hip_hop":-2.0,
	"ash_foundry|minimal_techno":-2.1,
	"ash_foundry|schranz":-3.3,
	"basalt_quarry|breakbeat":-2.1,
	"basalt_quarry|hip_hop":-2.9,
	"basalt_quarry|minimal_techno":-2.4,
	"basalt_quarry|schranz":-4.1,
	"buried_megafactory|breakbeat":-1.4,
	"buried_megafactory|hip_hop":-2.6,
	"buried_megafactory|minimal_techno":-2.2,
	"buried_megafactory|schranz":-3.7,
	"flooded_power_station|breakbeat":-1.7,
	"flooded_power_station|hip_hop":-2.4,
	"flooded_power_station|minimal_techno":-1.7,
	"flooded_power_station|schranz":-3.6,
	"frozen_rail_yard|breakbeat":-0.7,
	"frozen_rail_yard|hip_hop":-1.5,
	"frozen_rail_yard|minimal_techno":-0.7,
	"frozen_rail_yard|schranz":-3.0,
	"iron_canyon|breakbeat":-1.4,
	"iron_canyon|hip_hop":-2.2,
	"iron_canyon|minimal_techno":-2.2,
	"iron_canyon|schranz":-3.3,
	"mountain_pass|breakbeat":-0.8,
	"mountain_pass|hip_hop":-1.5,
	"mountain_pass|minimal_techno":-0.6,
	"mountain_pass|schranz":-3.1,
	"overgrown_steelworks|breakbeat":-1.7,
	"overgrown_steelworks|hip_hop":-2.4,
	"overgrown_steelworks|minimal_techno":-2.4,
	"overgrown_steelworks|schranz":-3.8,
	"radar_highlands|breakbeat":-1.2,
	"radar_highlands|hip_hop":-1.9,
	"radar_highlands|minimal_techno":-1.0,
	"radar_highlands|schranz":-3.4,
	"sector07|breakbeat":-1.0,
	"sector07|hip_hop":-2.0,
	"sector07|minimal_techno":-2.1,
	"sector07|schranz":-3.4,
	"storm_dam|breakbeat":-1.4,
	"storm_dam|hip_hop":-2.6,
	"storm_dam|minimal_techno":-2.4,
	"storm_dam|schranz":-3.4,
	"sulfur_refinery|breakbeat":-1.6,
	"sulfur_refinery|hip_hop":-2.3,
	"sulfur_refinery|minimal_techno":-2.5,
	"sulfur_refinery|schranz":-3.5,
}
const THEMES := {
	"sector07": {"bpm":118.0,"key":2,"scale":"minor","tone":0.42,"punch":0.64,"swing":0.04,"dust":0.20,"personality":"industrial","kick_sound":0,"motif":[0,3,7,5,0,10,7,3],"phrase_bars":8,"bass_weight":0.64,"pad_level":0.06,"brightness":0.46,"room":0.18,"density":0.58,"rest_every":4,"phrase_variation":0.32,"effects":{"reverb":0.18,"delay":0.10},"master_gain":0.64},
	"ash_foundry": {"bpm":118.0,"key":0,"scale":"minor","tone":0.33,"punch":0.79,"swing":0.03,"dust":0.28,"personality":"metallic","kick_sound":1,"motif":[0,0,7,3,5,3,10,7],"phrase_bars":8,"bass_weight":0.67,"pad_level":0.05,"brightness":0.54,"room":0.10,"density":0.66,"rest_every":4,"phrase_variation":0.36,"effects":{"reverb":0.10,"delay":0.07},"master_gain":0.61},
	"abandoned_harbor": {"bpm":116.0,"key":5,"scale":"dorian","tone":0.57,"punch":0.53,"swing":0.12,"dust":0.12,"personality":"tidal","kick_sound":0,"motif":[0,7,9,5,2,5,7,2],"phrase_bars":16,"bass_weight":0.62,"pad_level":0.07,"brightness":0.47,"room":0.36,"density":0.48,"rest_every":4,"phrase_variation":0.43,"effects":{"reverb":0.31,"delay":0.19},"master_gain":0.64},
	"basalt_quarry": {"bpm":114.0,"key":7,"scale":"minor","tone":0.24,"punch":0.86,"swing":0.02,"dust":0.31,"personality":"stone","kick_sound":2,"motif":[0,7,0,3,0,5,3,10],"phrase_bars":8,"bass_weight":0.70,"pad_level":0.05,"brightness":0.30,"room":0.28,"density":0.43,"rest_every":4,"phrase_variation":0.28,"effects":{"reverb":0.24,"delay":0.08},"master_gain":0.59},
	"overgrown_steelworks": {"bpm":118.0,"key":9,"scale":"dorian","tone":0.58,"punch":0.59,"swing":0.10,"dust":0.19,"personality":"organic","kick_sound":0,"motif":[0,2,5,9,7,5,2,7],"phrase_bars":16,"bass_weight":0.62,"pad_level":0.07,"brightness":0.55,"room":0.26,"density":0.52,"rest_every":4,"phrase_variation":0.41,"effects":{"reverb":0.24,"delay":0.14},"master_gain":0.65},
	"frozen_rail_yard": {"bpm":112.0,"key":4,"scale":"minor","tone":0.68,"punch":0.44,"swing":0.0,"dust":0.08,"personality":"frost","kick_sound":0,"motif":[0,7,12,10,7,3,5,0],"phrase_bars":16,"bass_weight":0.58,"pad_level":0.04,"brightness":0.64,"room":0.33,"density":0.34,"rest_every":4,"phrase_variation":0.27,"effects":{"reverb":0.30,"delay":0.21},"master_gain":0.66},
	"iron_canyon": {"bpm":122.0,"key":2,"scale":"phrygian","tone":0.38,"punch":0.80,"swing":0.05,"dust":0.25,"personality":"canyon","kick_sound":1,"motif":[0,1,7,5,3,1,10,7],"phrase_bars":8,"bass_weight":0.68,"pad_level":0.05,"brightness":0.43,"room":0.24,"density":0.67,"rest_every":4,"phrase_variation":0.35,"effects":{"reverb":0.22,"delay":0.11},"master_gain":0.60},
	"flooded_power_station": {"bpm":114.0,"key":10,"scale":"dorian","tone":0.52,"punch":0.54,"swing":0.09,"dust":0.15,"personality":"submerged","kick_sound":0,"motif":[0,5,9,7,2,7,5,0],"phrase_bars":16,"bass_weight":0.64,"pad_level":0.07,"brightness":0.40,"room":0.38,"density":0.45,"rest_every":4,"phrase_variation":0.39,"effects":{"reverb":0.34,"delay":0.22},"master_gain":0.63},
	"mountain_pass": {"bpm":110.0,"key":1,"scale":"minor","tone":0.27,"punch":0.48,"swing":0.02,"dust":0.13,"personality":"mountain","kick_sound":2,"motif":[0,7,3,0,10,7,5,3],"phrase_bars":16,"bass_weight":0.63,"pad_level":0.06,"brightness":0.28,"room":0.35,"density":0.31,"rest_every":4,"phrase_variation":0.25,"effects":{"reverb":0.32,"delay":0.16},"master_gain":0.64},
	"storm_dam": {"bpm":120.0,"key":6,"scale":"minor","tone":0.46,"punch":0.72,"swing":0.06,"dust":0.17,"personality":"storm","kick_sound":1,"motif":[0,5,7,10,7,3,5,0],"phrase_bars":8,"bass_weight":0.68,"pad_level":0.07,"brightness":0.46,"room":0.31,"density":0.60,"rest_every":4,"phrase_variation":0.40,"effects":{"reverb":0.27,"delay":0.16},"master_gain":0.61},
	"sulfur_refinery": {"bpm":124.0,"key":8,"scale":"phrygian","tone":0.62,"punch":0.73,"swing":0.07,"dust":0.23,"personality":"acid","kick_sound":1,"motif":[0,1,5,7,8,7,3,1],"phrase_bars":8,"bass_weight":0.66,"pad_level":0.05,"brightness":0.67,"room":0.17,"density":0.65,"rest_every":4,"phrase_variation":0.44,"effects":{"reverb":0.14,"delay":0.13},"master_gain":0.61},
	"radar_highlands": {"bpm":112.0,"key":11,"scale":"dorian","tone":0.73,"punch":0.48,"swing":0.04,"dust":0.06,"personality":"signal","kick_sound":0,"motif":[0,2,7,9,12,9,5,2],"phrase_bars":16,"bass_weight":0.58,"pad_level":0.04,"brightness":0.69,"room":0.29,"density":0.37,"rest_every":4,"phrase_variation":0.33,"effects":{"reverb":0.25,"delay":0.24},"master_gain":0.66},
	"buried_megafactory": {"bpm":116.0,"key":3,"scale":"minor","tone":0.21,"punch":0.83,"swing":0.02,"dust":0.29,"personality":"subterranean","kick_sound":2,"motif":[0,3,0,7,10,7,5,3],"phrase_bars":8,"bass_weight":0.72,"pad_level":0.09,"brightness":0.26,"room":0.32,"density":0.57,"rest_every":4,"phrase_variation":0.30,"effects":{"reverb":0.29,"delay":0.11},"master_gain":0.58},
}

static func theme(environment_id: String, style: String = "level_default") -> Dictionary:
	var result: Dictionary = Rave.theme_for_environment(environment_id) if Genres.resolve(environment_id, style) == "minimal_techno" else {}
	if result.is_empty(): result = THEMES.get(environment_id, THEMES.ash_foundry).duplicate(true)
	# Native output is already loudness-normalized and peak-limited. Keep its
	# unity setting; the Music bus and dialogue duck own the listening level.
	result.master_gain = 1.0
	return result

static func native_settings(environment_id: String, overrides: Dictionary = {}, style: String = "level_default") -> Dictionary:
	# The authored motif is measured in semitones; Tessel expects scale degrees.
	# Keep the readable theme independent of the synth's integer enums.
	var genre := Genres.resolve(environment_id,style)
	var settings := Genres.apply(theme(environment_id, genre),genre)
	settings.merge(overrides,true)
	settings.genre = int(Genres.NATIVE_IDS[genre])
	settings.normalization_db = float(NORMALIZATION_DB.get(environment_id+"|"+genre,0.0))
	if genre == "minimal_techno" and Rave.ENVIRONMENT_TRACKS.has(environment_id):
		settings.normalization_db = float(RaveMeasurements.TRACKS[Rave.ENVIRONMENT_TRACKS[environment_id]].gain_db)
	var personalities := {"industrial":3,"metallic":3,"tidal":4,"stone":0,"organic":4,"frost":0,"canyon":3,"submerged":1,"mountain":0,"storm":1,"acid":2,"signal":6,"subterranean":3}
	settings.personality = int(personalities.get(str(settings.personality),3))
	var effects: Dictionary = settings.effects
	settings.effects = clampf(float(effects.get("reverb",0.2))*0.8+float(effects.get("delay",0.1))*0.5,0.0,1.0)
	settings.tone = lerpf(float(settings.tone),float(settings.brightness),0.35)
	settings.erase("brightness")
	var scale_name := str(settings.scale)
	settings.scale = {"minor":0,"major":1,"dorian":2,"phrygian":3}.get(scale_name,0)
	var pitches: Array = {"minor":[0,3,5,7,10],"major":[0,2,4,7,9],"dorian":[0,2,3,5,7,9,10],"phrygian":[0,1,3,5,7,8,10]}.get(scale_name,[0,3,5,7,10])
	var degrees: Array[int] = []
	for note: int in settings.motif:
		var octave := int(floor(float(note)/12.0))
		var pitch := posmod(note,12)
		var closest := 0
		var distance := 100
		for index in pitches.size():
			if absi(int(pitches[index])-pitch)<distance:
				distance=absi(int(pitches[index])-pitch)
				closest=index
		degrees.append(octave*pitches.size()+closest)
	settings.motif = degrees
	return settings

static func seed_for(environment_id: String, match_seed: int) -> int:
	# Explicit arithmetic is stable across process launches and Python/C++ ports.
	# Godot's process-global RNG and Dictionary iteration order never enter music.
	var value := 2166136261
	for byte: int in environment_id.to_utf8_buffer():
		value = ((value ^ byte) * 16777619) & 0x7fffffff
	value = ((value ^ (match_seed & 0x7fffffff)) * 16777619) & 0x7fffffff
	return maxi(value, 1)

static func intensity_for(state: Dictionary) -> int:
	if not bool(state.get("running", true)):
		return 0
	var phase := str(state.get("phase", "build"))
	if phase in ["victory", "defeat", "finished", "salvage"]:
		return 0
	if phase == "warning":
		return 2
	if phase != "attack":
		# Request the first groove immediately. LiveMusic applies it at the
		# next 8/16-bar phrase, preserving a complete cinematic opening first.
		return 1 if phase == "build" else 0
	if bool(state.get("boss", false)) or bool(state.get("air_raid", false)) or float(state.get("core_ratio", 1.0)) < 0.30:
		return 3
	if int(state.get("enemy_count", 0)) >= 12 or int(state.get("wave", 1)) >= 10:
		return 3
	return 2 if int(state.get("enemy_count", 0)) >= 4 else 1

static func section_for(state: Dictionary, phrase_index: int) -> String:
	if not bool(state.get("running", true)):
		return "resolution"
	match str(state.get("phase", "build")):
		"salvage": return "release"
		"warning": return "tension"
		"attack": return "attack" if phrase_index % 4 != 3 else "breath"
		"victory", "defeat", "finished": return "resolution"
	return "intro" if phrase_index == 0 else ("breath" if phrase_index % 4 == 3 else "build")
