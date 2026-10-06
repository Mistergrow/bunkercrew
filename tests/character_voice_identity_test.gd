extends SceneTree
## Every playable character owns real recordings; compact party IDs select that
## character in authored host events without borrowing another crew member.
const Catalog := preload("res://scripts/story_dialogue_catalog.gd")
const Dialogue := preload("res://scripts/story_dialogue.gd")
const Director := preload("res://scripts/story_director.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const CREW_LINES := ["crew_wall", "crew_reply", "crew_storm", "crew_final", "crew_contact", "crew_air", "crew_clear"]

class ActorProbe extends Node2D:
	var player_id := 1
	var character_id := "oskar"
	var downed := false
	func is_downed() -> bool: return downed

class AudioProbe extends Node:
	var ducked := false
	func set_dialogue_active(value: bool) -> void: ducked = value

class HudProbe extends Node:
	var overlay := ""

class NetworkProbe extends Node:
	var active := true
	var is_host := true
	var _generation := 7
	var events: Array[Dictionary] = []
	func queue_event(kind: String, event: Dictionary) -> void:
		events.append({"kind":kind, "event":event.duplicate(true)})

class GameProbe extends Node2D:
	var players: Array = []
	var audio: AudioProbe
	var hud: HudProbe
	var network: NetworkProbe
	var dialogue: StoryDialogue

var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	check(CharacterCatalog.CHARACTERS.size() == 8 and Catalog.SPEAKERS.size() == 9, "Eight playable identities and the separate SAN radio are present")
	for locale: String in LocaleText.SUPPORTED:
		LocaleText.set_locale(locale, false)
		for id: String in CREW_LINES:
			var scripts: Dictionary = {}
			for entry: Dictionary in CharacterCatalog.CHARACTERS:
				var character_id := str(entry.id)
				var line := Catalog.line(id, character_id)
				check(not line.is_empty() and line.speaker_id == character_id, "%s/%s/%s has its authored identity" % [locale, character_id, id])
				if line.is_empty(): continue
				check(not scripts.has(line.text), "%s/%s/%s uses its own character response" % [locale, character_id, id])
				scripts[line.text] = true
				var stream := load(str(line.voice_path)) as AudioStreamWAV
				check(stream != null and stream.get_length() > 0.8 and stream.mix_rate == 24000, "%s/%s/%s loads real finished speech" % [locale, character_id, id])
				check(line.text == line.source_text if locale == "de" else line.text != line.source_text, "%s/%s/%s subtitle matches its recording locale" % [locale, character_id, id])

	var game := GameProbe.new()
	root.add_child(game)
	game.audio = AudioProbe.new()
	game.add_child(game.audio)
	game.hud = HudProbe.new()
	game.add_child(game.hud)
	game.network = NetworkProbe.new()
	game.add_child(game.network)
	for party_id: int in [1, 3]:
		var actor := ActorProbe.new()
		actor.player_id = party_id
		actor.character_id = "oskar" if party_id == 1 else "rika"
		game.add_child(actor)
		game.players.append(actor)
	game.dialogue = Dialogue.new()
	game.dialogue.game = game
	game.add_child(game.dialogue)
	game.dialogue.set_process(false)
	var director := Director.new()
	director.game = game
	game.add_child(director)
	director.set_process(false)
	check(director.reply_player_id() in [1, 3], "Reply selection never invents player two in a compact one/three party")
	var original_crew := game.players.duplicate()
	game.players = [original_crew[1]]
	check(director.reply_player_id() == 3, "A sole surviving player three keeps their actual voice identity")
	game.players = original_crew.duplicate()
	for actor: ActorProbe in game.players: actor.downed = true
	check(director.reply_player_id() == 0, "The SAN radio answers when the entire crew is downed")
	game.players = []
	check(director.reply_player_id() == 0, "An empty party never invents a human speaker")
	game.players = original_crew.duplicate()
	for actor: ActorProbe in game.players: actor.downed = false
	check(game.dialogue._streams.size() == 170, "The real dialogue service preloads all nine speaker banks in both languages")
	for locale: String in LocaleText.SUPPORTED:
		LocaleText.set_locale(locale, false)
		for actor: ActorProbe in game.players:
			for id: String in CREW_LINES:
				game.dialogue.reset()
				director.say(id, actor.player_id)
				game.dialogue.advance(0.1)
				var active: Dictionary = game.dialogue.active
				check(not active.is_empty() and active.id == id and active.speaker_id == actor.character_id and active.anchor_player_id == actor.player_id, "%s/%s/%s keeps the requested non-contiguous party identity" % [locale, actor.character_id, id])
				check(game.dialogue.voice.playing and game.dialogue.voice.bus == "Voice" and game.dialogue.voice.pitch_scale == 1.0 and game.dialogue.voice.stream.resource_path == Catalog.recording_path(id, actor.character_id, locale), "%s/%s/%s plays its own recording without pitch substitution" % [locale, actor.character_id, id])
				var delivered: Dictionary = game.network.events.back()
				check(delivered.kind == "dialogue" and delivered.event.speaker == actor.character_id and delivered.event.player == actor.player_id and delivered.event.serial == director.serial and delivered.event.generation == game.network._generation, "%s/%s/%s broadcasts the same authored character event" % [locale, actor.character_id, id])
	game.dialogue.reset()
	check(not game.dialogue.enqueue("crew_reply", "rika", 1, 500), "Rika never borrows Oskar's player anchor")
	check(not game.dialogue.enqueue("crew_reply", "oskar", 3, 501), "Oskar never borrows Rika's player anchor")
	check(not game.dialogue.enqueue("crew_reply", "unknown_crew", 1, 502), "Unknown speaker IDs remain outside the network whitelist")
	check(game.dialogue.enqueue("crew_reply", "rika", 3, 503) and not game.dialogue.enqueue("crew_reply", "rika", 3, 503), "New speaker events retain the same serial deduplication")
	game.players[1].character_id = "ivo"
	game.dialogue.advance(0.1)
	check(game.dialogue.active.is_empty() and not game.dialogue.voice.playing, "Changing the selected character discards its queued old voice")
	game.dialogue.reset()
	LocaleText.set_locale("de", false)
	await create_timer(0.2, true).timeout
	check(await Cleanup.free_scene(game, self), "All real speech decoders and speaker scene nodes release cleanly")
	print("CHARACTER VOICE IDENTITY: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
