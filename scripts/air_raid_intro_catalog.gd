class_name AirRaidIntroCatalog
extends RefCounted
## A solo introduction uses the selected worker's existing, verified air warning.
## Trigger timing and once-per-run state belong to the introduction controller.

const Dialogue := preload("res://scripts/story_dialogue_catalog.gd")
const LINE_ID := "crew_air"


static func line(character_id: String) -> Dictionary:
	# CharacterCatalog.data() defaults to Mara; do not borrow her identity when
	# a selected character is missing or invalid.
	if not CharacterCatalog.contains(character_id): return {}
	# Oskar/Rika have no human recording. SAN speaks its own verified radio
	# warning, with its own identity, rather than impersonating a rescued worker.
	var radio := CharacterCatalog.presentation_id(character_id,"voice") in ["oskar", "rika"]
	var speaker := "san" if radio else character_id
	var result := Dialogue.line("warning_air" if radio else LINE_ID, speaker)
	if result.is_empty(): return {}
	result.speaker_name = Dialogue.speaker_name(speaker)
	result.portrait_id = speaker
	result.accent = Dialogue.speaker_color(speaker)
	# Keep the exact spoken script in the subtitle, including after a locale
	# change. A missing recording leaves readable text, never another voice.
	if not ResourceLoader.exists(str(result.voice_path)): result.voice_path = ""
	result.minimum_duration = clampf(str(result.text).length() / 16.0 + .8, 3.2, 6.5)
	if radio and not str(result.voice_path).is_empty():
		var recording:=load(str(result.voice_path)) as AudioStream
		if recording!=null: result.minimum_duration=maxf(float(result.minimum_duration),recording.get_length()+.15)
	return result
