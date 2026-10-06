class_name RaveMusicCatalog
extends RefCounted
## Original companions to Nachtschicht. A track's identity persists across
## calm, build, combat and climax arrangements; gameplay chooses intensity.
const VERSION := 2
const BARS := 32
const SAMPLE_RATE := 48000
const BASE_THEME := {
	"composition_version":2,"melody_level":0.28,"bpm":128.0,"key":9,"scale":"minor","tone":0.27,"brightness":0.27,
	"punch":0.67,"swing":0.015,"dust":0.045,"personality":"submerged",
	"kick_sound":0,"hook_style":0,"phrase_bars":8,"bass_weight":0.59,
	"pad_level":0.045,"room":0.16,"density":0.36,"rest_every":4,
	"phrase_variation":0.21,"effects":{"reverb":0.16,"delay":0.104},
	"master_gain":1.0,"motif":[0,0,5,0,0,7,5,0],
}
const TRACKS := {
	"nachtstrom":{"title":"Nachtstrom","role":"menu","seed":1111708210,"description":"A-Moll als Antwort auf Nachtschicht: warme, trockene Bassdrum, Bass auf den Zwischenschlägen und ein tiefes Gegenmotiv.","theme":{"composition_version":1,"key":9,"tone":0.32,"brightness":0.32,"bass_weight":0.62,"room":0.21,"punch":0.65,"motif":[0,5,0,7,3,0,5,3],"effects":{"reverb":0.21,"delay":0.12}}},
	"schichtwechsel":{"title":"Schichtwechsel","role":"menu","seed":1111708220,"description":"Fis-Phrygisch zum Schichtwechsel: kräftige trockene Bassdrum, kurze Bassantworten auf den Zwischenschlägen und ein dunkles Halbtonmotiv mit sparsamer metallischer Percussion.","theme":{"composition_version":1,"bpm":130.0,"key":6,"scale":"phrygian","tone":0.30,"brightness":0.30,"punch":0.74,"kick_sound":1,"personality":"metallic","bass_weight":0.63,"room":0.10,"swing":0.012,"dust":0.03,"pad_level":0.035,"density":0.34,"phrase_variation":0.23,"motif":[0,7,1,0,5,1,3,0],"effects":{"reverb":0.10,"delay":0.075}}},
	"kernimpuls":{"title":"Kernimpuls","role":"menu","seed":1111708221,"description":"D-Moll: ein getragenes Acht-Takt-Motiv, trockener Groove-Aufbau, kräftiger Minimal-Techno-Drop und eine luftige Rückkehr. Tiefer Subbass antwortet der Bassdrum.","theme":{"bpm":130.0,"key":2,"tone":0.31,"brightness":0.31,"punch":0.78,"kick_sound":0,"personality":"metallic","bass_weight":0.69,"melody_level":0.33,"room":0.16,"swing":0.010,"dust":0.025,"pad_level":0.055,"density":0.39,"phrase_variation":0.24,"motif":[0,7,3,0,5,7,3,0],"score_form":1,"effects":{"reverb":0.16,"delay":0.10}}},
	"glutkern":{"title":"Glutkern","role":"world","seed":1111708211,"description":"C-Moll im Hochofen: kurze metallische Akzente und ein gleichmäßiges, druckvolles Bassmotiv.","theme":{"bpm":130.0,"key":0,"tone":0.29,"brightness":0.29,"punch":0.74,"kick_sound":1,"personality":"metallic","bass_weight":0.63,"room":0.12,"motif":[0,0,7,3,0,5,3,0],"effects":{"reverb":0.12,"delay":0.07}}},
	"basalttakt":{"title":"Basalttakt","role":"world","seed":1111708212,"description":"G-Moll im Steinbruch: runde Bassdrum, dezente steinerne Percussion und absteigende Bassakzente.","theme":{"bpm":132.0,"key":7,"tone":0.22,"brightness":0.22,"punch":0.76,"kick_sound":2,"personality":"stone","bass_weight":0.65,"room":0.23,"motif":[0,7,0,5,3,0,3,0],"effects":{"reverb":0.23,"delay":0.065}}},
	"wurzelstrom":{"title":"Wurzelstrom","role":"world","seed":1111708213,"description":"A-Dorisch im Stahlwerk: sanfte Percussion, Luft zwischen den Klängen und eine kurze aufsteigende Melodie.","theme":{"key":9,"scale":"dorian","tone":0.40,"brightness":0.40,"punch":0.62,"personality":"organic","bass_weight":0.56,"room":0.24,"motif":[0,2,0,5,7,5,2,0],"effects":{"reverb":0.24,"delay":0.13}}},
	"eisenhall":{"title":"Eisenhall","role":"world","seed":1111708214,"description":"D-Phrygisch in der Schlucht: trockene eiserne Bassdrum und eine dunkle Halbtonantwort mit sparsamer Melodie.","theme":{"bpm":131.0,"key":2,"scale":"phrygian","tone":0.31,"brightness":0.31,"punch":0.73,"kick_sound":1,"personality":"canyon","bass_weight":0.63,"room":0.18,"motif":[0,1,0,7,5,1,3,0],"effects":{"reverb":0.18,"delay":0.09}}},
	"hafennebel":{"title":"Hafennebel","role":"world","seed":1111708215,"description":"F-Dorisch im Hafen: runder Bass, neblige Echoakkorde und kühle, sparsame Percussion.","theme":{"key":5,"scale":"dorian","tone":0.36,"brightness":0.36,"punch":0.61,"personality":"tidal","bass_weight":0.57,"room":0.28,"swing":0.02,"motif":[0,5,0,9,7,5,2,0],"effects":{"reverb":0.28,"delay":0.17}}},
	"tiefenpuls":{"title":"Tiefenpuls","role":"world","seed":1111708216,"description":"B-Dorisch im Kraftwerk: tiefer Bass, kurze elektrische Akzente und dezente räumliche Nachklänge.","theme":{"bpm":129.0,"key":10,"scale":"dorian","tone":0.25,"brightness":0.25,"punch":0.68,"bass_weight":0.64,"room":0.29,"motif":[0,5,0,2,7,5,2,0],"effects":{"reverb":0.29,"delay":0.18}}},
	"frostsignal":{"title":"Frostsignal","role":"world","seed":1111708217,"description":"E-Moll am Frostbahnhof: klare, trockene Bassdrum und kalte Antworttöne über einem ruhigen Bass.","theme":{"key":4,"tone":0.46,"brightness":0.46,"punch":0.62,"personality":"frost","bass_weight":0.55,"room":0.22,"swing":0.0,"dust":0.025,"motif":[0,7,3,0,5,3,7,0],"effects":{"reverb":0.22,"delay":0.15}}},
	"hoehenlicht":{"title":"Höhenlicht","role":"world","seed":1111708218,"description":"Cis-Moll am Gewitterpass: eine klare Bassdrum mit viel Raum und ein tiefes Motiv, das ansteigt und sich setzt.","theme":{"key":1,"tone":0.34,"brightness":0.34,"punch":0.63,"personality":"mountain","bass_weight":0.57,"room":0.30,"motif":[0,3,7,0,5,3,0,0],"effects":{"reverb":0.30,"delay":0.14}}},
	"unterstrom":{"title":"Unterstrom","role":"world","seed":1111708219,"description":"Es-Moll unter der Fabrik: kräftiger, kontrollierter Bass, gedämpfte industrielle Akzente und ein absteigendes Motiv.","theme":{"bpm":130.0,"key":3,"tone":0.20,"brightness":0.20,"punch":0.75,"kick_sound":2,"personality":"subterranean","bass_weight":0.65,"room":0.21,"motif":[0,3,0,7,5,3,0,0],"effects":{"reverb":0.21,"delay":0.08}}},
}
const ENVIRONMENT_TRACKS := {
	"sector07":"unterstrom","ash_foundry":"glutkern","basalt_quarry":"basalttakt",
	"overgrown_steelworks":"wurzelstrom","iron_canyon":"eisenhall",
	"abandoned_harbor":"hafennebel","flooded_power_station":"tiefenpuls",
	"frozen_rail_yard":"frostsignal","mountain_pass":"hoehenlicht",
	"storm_dam":"tiefenpuls","sulfur_refinery":"glutkern",
	"radar_highlands":"frostsignal","buried_megafactory":"unterstrom",
}

static func track(id: String) -> Dictionary:
	if not TRACKS.has(id): return {}
	var result: Dictionary = TRACKS[id].duplicate(true)
	result.id = id
	result.theme = BASE_THEME.duplicate(true)
	result.theme.merge(TRACKS[id].theme, true)
	result.bpm = float(result.theme.bpm)
	result.seconds = float(BARS * 4) * 60.0 / result.bpm
	result.frames = roundi(result.seconds * SAMPLE_RATE)
	result.version = int(result.theme.composition_version)
	result.asset = "menu_rave_%s_v%d.ogg" % [id, result.version] if result.role == "menu" else "music_rave_%s_v%d_combat.ogg" % [id, result.version]
	result.calm_asset = "" if result.role == "menu" else "music_rave_%s_v%d_calm.ogg" % [id, result.version]
	return result

static func theme_for_environment(id: String) -> Dictionary:
	var track_id := str(ENVIRONMENT_TRACKS.get(id, ""))
	return track(track_id).get("theme", {}).duplicate(true)

static func native_settings_for_track(id: String) -> Dictionary:
	var result: Dictionary = track(id).get("theme", {}).duplicate(true)
	if result.is_empty(): return result
	var scale_name := str(result.scale)
	result.scale = {"minor":0,"major":1,"dorian":2,"phrygian":3}.get(scale_name, 0)
	result.genre = 0
	var personalities := {"metallic":3,"tidal":4,"stone":0,"organic":4,"frost":0,"canyon":3,"submerged":1,"mountain":0,"subterranean":3}
	result.personality = int(personalities.get(str(result.personality), 1))
	var effects: Dictionary = result.effects
	result.effects = clampf(float(effects.reverb) * 0.8 + float(effects.delay) * 0.5, 0.0, 1.0)
	result.erase("brightness")
	result.initial_intensity = 2
	result.normalization_db = 0.0
	var pitches: Array = {"minor":[0,3,5,7,10],"major":[0,2,4,7,9],"dorian":[0,2,3,5,7,9,10],"phrygian":[0,1,3,5,7,8,10]}.get(scale_name, [0,3,5,7,10])
	var degrees: Array[int] = []
	for note: int in result.motif:
		var octave := floori(float(note) / 12.0)
		var pitch := posmod(note, 12)
		var closest := 0
		var distance := 100
		for index in pitches.size():
			if absi(int(pitches[index]) - pitch) < distance:
				distance = absi(int(pitches[index]) - pitch)
				closest = index
		degrees.append(octave * pitches.size() + closest)
	result.motif = degrees
	return result
