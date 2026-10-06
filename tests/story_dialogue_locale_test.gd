extends SceneTree
## Local text/audio changes preserve host-authored dialogue identity and game state.
const Dialogue := preload("res://scripts/story_dialogue.gd")
const Catalog := preload("res://scripts/story_dialogue_catalog.gd")

class ActorProbe extends Node2D:
	var player_id := 1
	var character_id := "mara"

class AudioProbe extends Node:
	var ducked := false
	func set_dialogue_active(value: bool): ducked = value

class HudProbe extends Node:
	var overlay := ""

class GameProbe extends Node2D:
	var players: Array = []
	var audio: AudioProbe
	var hud: HudProbe
	var wave := 11
	var steel := 7

var checks := 0
var failures := 0

func _initialize(): run.call_deferred()

func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS ", label)
	else:
		failures += 1
		push_error(label)

func run():
	LocaleText.set_locale("de", false)
	var original := Catalog.line("story_open")
	check(original.text == original.source_text and original.locale == "de" and not str(original.voice_path).contains("/en/"), "German text and original recorded script remain identical")
	LocaleText.set_locale("en", false)
	var translated := Catalog.line("story_open")
	check(str(translated.text).begins_with("This is San.") and translated.source_text == original.text and translated.locale == "en", "English subtitles preserve the stable German source text")
	check(str(translated.voice_path).contains("/en/") and translated.voice_path != original.voice_path, "English selects a separate English recording")
	check(Catalog.speaker_name("san") == "SAN · RADIO" and Catalog.speaker_name("mara") == "MARA", "Speaker labels use the shared locale table")
	var localized := 0
	for id: String in Catalog.LINES:
		for speaker: String in Catalog.SPEAKERS:
			var detail := Catalog.line(id, speaker)
			if detail.is_empty(): continue
			localized += 1
			check(detail.text != detail.source_text and str(detail.voice_path).contains("/en/"), "%s/%s has English text and its own English recording path" % [id, speaker])
	check(localized == 85, "All eighty-five utterances are translated")
	check(Catalog.recording_path("story_open", "san", "../de").is_empty(), "Unknown locale strings cannot become resource paths")
	LocaleText.set_locale("de", false)
	var game := GameProbe.new()
	root.add_child(game)
	game.audio = AudioProbe.new()
	game.add_child(game.audio)
	game.hud = HudProbe.new()
	game.add_child(game.hud)
	var actor := ActorProbe.new()
	game.add_child(actor)
	game.players.append(actor)
	var dialogue := Dialogue.new()
	dialogue.game = game
	game.add_child(dialogue)
	dialogue.set_process(false)
	# Actual playback handles distinguish the language banks before generated EN
	# recordings have been imported; real recordings have separate mixer tests.
	for locale: String in LocaleText.SUPPORTED:
		var stream := AudioStreamWAV.new()
		stream.mix_rate = 8000
		stream.format = AudioStreamWAV.FORMAT_8_BITS
		stream.set_meta("locale", locale)
		var silence := PackedByteArray()
		silence.resize(120000)
		silence.fill(128)
		stream.data = silence
		for id: String in Catalog.LINES:
			for speaker: String in Catalog.SPEAKERS:
				var path := Catalog.recording_path(id, speaker, locale)
				if not path.is_empty(): dialogue._streams[path] = stream
	dialogue.enqueue("story_open", "san", 1, 21)
	dialogue.enqueue("crew_reply", "mara", 1, 22)
	dialogue.advance(.1)
	dialogue.advance(.5)
	var seen := dialogue._seen.duplicate()
	var cooldowns := dialogue._cooldowns.duplicate()
	var clock := dialogue.elapsed
	var game_id := game.get_instance_id()
	LocaleText.set_locale("en", false)
	check(dialogue.active.id == "story_open" and dialogue.active.serial == 21 and dialogue.active.locale == "en" and dialogue.active_age == 0, "A live switch restarts the same host event in English")
	check(dialogue.voice.stream.get_meta("locale") == "en" and dialogue.voice.playing and dialogue.active.text == translated.text, "The English recording and English subtitle switch together")
	check(dialogue.pending.size() == 1 and dialogue.pending[0].id == "crew_reply" and dialogue.pending[0].serial == 22 and dialogue.pending[0].locale == "en", "Queued identity, order and speaker survive with translated text")
	check(dialogue._seen == seen and dialogue._cooldowns == cooldowns and dialogue.elapsed == clock and dialogue.spoken_count == 1, "A language preference does not reset serials, cooldowns or the dialogue clock")
	check(game.get_instance_id() == game_id and game.wave == 11 and game.steel == 7 and game.players[0] == actor, "Language changes preserve the running world, wave, stock and selected worker")
	check(not dialogue.enqueue("story_open", "san", 1, 21), "An already delivered network event remains deduplicated after switching")
	game.hud.overlay = "audio"
	paused = true
	dialogue.advance(.1)
	LocaleText.set_locale("de", false)
	check(dialogue.active.locale == "de" and dialogue.voice.stream.get_meta("locale") == "de" and dialogue.voice.stream_paused and not dialogue.canvas.visible and not game.audio.ducked, "Switching inside paused Audio settings keeps the replacement voice silent")
	paused = false
	game.hud.overlay = ""
	dialogue.advance(.1)
	check(not dialogue.voice.stream_paused and dialogue.canvas.visible and dialogue.active_age > 0, "Closing settings resumes the chosen-language line")
	game.hud.overlay = "audio"
	LocaleText.set_locale("en", false)
	dialogue.advance(.1)
	check(not paused and dialogue.voice.playing and dialogue.active.locale == "en" and not dialogue.canvas.visible, "Local online settings keep the match and chosen voice running without obscuring the settings controls")
	game.hud.overlay = ""
	LocaleText.set_locale("de", false)
	dialogue.advance(.1)
	check(dialogue.canvas.visible and dialogue.active.locale == "de", "Closing a non-pausing menu restores the current-language caption")
	dialogue._streams.erase(Catalog.recording_path("story_open", "san", "en"))
	LocaleText.set_locale("en", false)
	check(dialogue.active.locale == "en" and str(dialogue.active.text).begins_with("This is San.") and dialogue.voice.stream == null and not dialogue.voice.playing and not game.audio.ducked, "A missing English recording leaves English subtitles without German audio or unnecessary music ducking")
	dialogue.reset()
	game.hud.overlay = "victory"
	paused = true
	dialogue.enqueue("story_victory", "san", 1, 41)
	dialogue.advance(.1)
	LocaleText.set_locale("de", false)
	check(dialogue.active.id == "story_victory" and dialogue.active.locale == "de" and not dialogue.voice.stream_paused and dialogue.canvas.visible, "The paused end card can switch and continue its ending voice")
	dialogue.reset()
	paused = false
	await create_timer(.15, true).timeout
	await preload("res://tests/scene_cleanup.gd").free_scene(game, self)
	LocaleText.set_locale("de", false)
	print("Story dialogue locale: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
