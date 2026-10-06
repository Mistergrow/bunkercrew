extends SceneTree
## Actual intro lines must preserve selected identity, language and recording.
const Catalog := preload("res://scripts/air_raid_intro_catalog.gd")
const Dialogue := preload("res://scripts/story_dialogue_catalog.gd")
const Characters := preload("res://scripts/character_catalog.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		push_error(label)


func run() -> void:
	var previous_locale := LocaleText.current_locale()
	var recordings: Dictionary = {}
	var anchors: Dictionary = {}
	for locale: String in LocaleText.SUPPORTED:
		LocaleText.set_locale(locale, false)
		var directory := Dialogue.VOICE_ROOT + ("en/" if locale == "en" else "")
		var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory + "source.json"))
		var translations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://locales/" + locale + ".json"))
		var lines: Dictionary = {}
		for character: Dictionary in Characters.CHARACTERS:
			var character_id := str(character.id)
			if character_id in ["oskar","rika"]: continue
			var detail := Catalog.line(character_id)
			var label := locale + "/" + character_id
			check(detail.get("speaker_id") == character_id and detail.get("portrait_id") == character_id and detail.get("speaker_name") == character.title, label + " keeps the selected portrait and speaker")
			check(detail.get("accent") == Color(character.accent), label + " uses the selected character's accent")
			check(detail.get("id") == "crew_air" and detail.get("locale") == locale and translations.get(detail.get("source_text")) == detail.get("text"), label + " uses the exact localized air warning")
			check(not str(detail.get("text", "")).is_empty() and not lines.has(detail.get("text")), label + " has an individual character comment")
			lines[detail.get("text")] = true
			var voice_path := str(detail.get("voice_path", ""))
			var expected_path := Dialogue.recording_path("crew_air", character_id, locale)
			check(voice_path == expected_path and ResourceLoader.exists(voice_path), label + " selects its actual language-specific recording")
			if voice_path.is_empty(): continue
			var stream := load(voice_path) as AudioStreamWAV
			check(stream != null and stream.mix_rate == 24000 and not stream.stereo and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, label + " imports as non-looping mono speech")
			if stream == null: continue
			check(stream.get_length() > 2.0 and stream.get_length() < 5.0 and float(detail.minimum_duration) >= stream.get_length(), label + " fits a complete brief introduction")
			var source: Dictionary = metadata.files.get(voice_path.get_file(), {})
			var checksum := FileAccess.get_sha256(voice_path)
			check(source.get("speaker") == character_id and source.get("text") == detail.text and source.get("sha256") == checksum, label + " matches recorded script and asset provenance")
			check(not checksum.is_empty() and not recordings.has(checksum), label + " never reuses another speaker or language recording")
			recordings[checksum] = voice_path
			if locale == "de":
				var anchor_path := "res://" + str(source.get("anchor_file", ""))
				var anchor_sha := str(source.get("anchor_sha256", ""))
				check(not anchor_sha.is_empty() and FileAccess.get_sha256(anchor_path) == anchor_sha and not anchors.has(anchor_sha), label + " retains its own verified synthetic voice identity")
				anchors[anchor_sha] = character_id
		for identity: String in ["oskar","rika"]:
			var radio:=Catalog.line(identity)
			var actual_radio:=Dialogue.line("warning_air","san")
			check(radio.get("speaker_id")=="san" and radio.get("portrait_id")=="san" and radio.get("speaker_name")==Dialogue.speaker_name("san"),locale+"/"+identity+" uses SAN's own explicit radio identity")
			check(radio.get("id")=="warning_air" and radio.get("text")==actual_radio.text and radio.get("voice_path")==actual_radio.voice_path and ResourceLoader.exists(radio.voice_path),locale+"/"+identity+" plays an actual matching existing SAN recording")
			check(radio.get("accent")==Dialogue.speaker_color("san") and radio.get("minimum_duration",0)>=load(radio.voice_path).get_length(),locale+"/"+identity+" preserves radio accent and complete speech duration")
		check(lines.size() == 6, locale + " covers all three initial and three rescued characters")
	for invalid_id: String in ["", "san", "MARA", "../mara", "missing"]:
		check(Catalog.line(invalid_id).is_empty(), "Invalid selection cannot borrow a portrait or voice: " + invalid_id)
	LocaleText.set_locale("de", false)
	var original := Catalog.line("mara")
	original.text = "changed by caller"
	original.speaker_id = "ivo"
	var fresh := Catalog.line("mara")
	check(fresh.speaker_id == "mara" and fresh.text == fresh.source_text, "Callers cannot change the shared character script")
	LocaleText.set_locale("en", false)
	var english := Catalog.line("mara")
	check(english.source_text == fresh.source_text and english.text != fresh.text and english.voice_path != fresh.voice_path and english.portrait_id == fresh.portrait_id, "Language changes replace text and audio while preserving the selected identity")
	check(recordings.size() == 12 and anchors.size() == 6, "All twelve localized recordings and six separate German voice identities are covered")
	LocaleText.set_locale(previous_locale, false)
	print("Air raid intro catalog: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
