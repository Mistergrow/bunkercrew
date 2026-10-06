extends RefCounted
## Authored travel vignettes reuse genuine recorded crew lines. Duration is
## fixed per scene across identities/locales so a shared starting phase cannot
## finish earlier for a client whose selected voice is longer.
const Dialogue := preload("res://scripts/story_dialogue_catalog.gd")
const MIN_SKIP_DELAY := .45
const VOICE_AT := 1.1
const OUTRO_TIME := .85
const MAX_DURATION := 9.0
const ORDER: Array[String] = ["signal","storm","supply"]
const VIGNETTES := {
	"signal":{"title":"Ein Signal im Rauschen","duration":7.50,"crew_line":"crew_reply","radio_line":"relay_online"},
	"storm":{"title":"Zwischen Blitz und Deckung","duration":7.85,"crew_line":"crew_storm","radio_line":"storm_tree"},
	"supply":{"title":"Eine Pause am Straßenrand","duration":6.25,"crew_line":"crew_clear","radio_line":"wave_clear"},
}
const ROUTES := {
	"harbor":"signal", "steelworks":"signal", "radar_archive":"signal", "power_station":"signal",
	"mountain_pass":"storm", "canyon":"storm", "dam_vault":"storm",
	"quarry":"supply", "rail_yard":"supply", "refinery_archive":"supply", "buried_archive":"supply",
}

static func context(destination: String, character_id: String, crew_ids: Array=[]) -> Dictionary:
	if not ROUTES.has(destination) or not CharacterCatalog.contains(character_id): return {}
	var crew: Array[String] = []
	if crew_ids.is_empty():
		crew.append(character_id)
	else:
		for member in crew_ids:
			if member is String and CharacterCatalog.contains(member): crew.append(member)
			if crew.size()>=PartyConfig.MAX_PLAYERS: break
		# A missing local identity must never borrow a present worker's voice.
		if not character_id in crew: return {}
	var id: String = str(ROUTES[destination])
	var definition: Dictionary = VIGNETTES[id]
	var radio := CharacterCatalog.presentation_id(character_id,"voice") in ["oskar","rika"]
	var speaker := "san" if radio else character_id
	var dialogue := Dialogue.line(str(definition.radio_line if radio else definition.crew_line),speaker)
	if dialogue.is_empty(): return {}
	dialogue.speaker_name = Dialogue.speaker_name(speaker)
	dialogue.portrait_id = speaker
	dialogue.accent = Dialogue.speaker_color(speaker)
	dialogue.minimum_duration = 0.0
	var path: String = str(dialogue.voice_path)
	if ResourceLoader.exists(path):
		var recording := load(path) as AudioStream
		if recording!=null:
			dialogue.minimum_duration = recording.get_length()
		else:
			dialogue.voice_path = ""
	else:
		# Text-only fallback retains the exact selected identity and script.
		dialogue.voice_path = ""
	var location: Dictionary = CampaignCatalog.node(destination)
	return {"id":id,"destination":destination,"environment":str(location.environment),
		"title":LocaleText.text(str(definition.title)),"duration":float(definition.duration),
		"character_id":character_id,"crew_ids":crew,"locale":LocaleText.current_locale(),"dialogue":dialogue}
