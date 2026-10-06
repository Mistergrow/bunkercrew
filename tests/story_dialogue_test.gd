extends SceneTree
## Queue, authored-event safety and pause behaviour do not depend on sound hardware.

const Dialogue := preload("res://scripts/story_dialogue.gd")
const Catalog := preload("res://scripts/story_dialogue_catalog.gd")

class AudioProbe extends Node:
	var ducked := false
	var changes := 0
	func set_dialogue_active(value: bool):
		ducked = value
		changes += 1

class ActorProbe extends Node2D:
	var player_id := 1
	var character_id := "mara"

class HudProbe extends Node:
	var overlay := ""

class GameProbe extends Node2D:
	var players: Array = []
	var audio: AudioProbe
	var hud: HudProbe

var checks := 0
var failures := 0

func _initialize(): call_deferred("run")

func check(value: bool, label: String):
	checks += 1
	if value: print("PASS ", label)
	else:
		failures += 1
		push_error(label)

func run():
	LocaleText.set_locale("de", false)
	var game := GameProbe.new()
	root.add_child(game)
	game.audio = AudioProbe.new()
	game.add_child(game.audio)
	game.hud = HudProbe.new()
	game.add_child(game.hud)
	var actor := ActorProbe.new()
	actor.position = Vector2(360, 430)
	game.add_child(actor)
	game.players.append(actor)
	var dialogue := Dialogue.new()
	dialogue.game = game
	game.add_child(dialogue)
	dialogue.set_process(false)
	# A real playback handle verifies pause even before generated speech is imported.
	var fixture_stream := AudioStreamWAV.new()
	fixture_stream.mix_rate = 8000
	fixture_stream.format = AudioStreamWAV.FORMAT_8_BITS
	var silence := PackedByteArray()
	silence.resize(80000)
	silence.fill(128)
	fixture_stream.data = silence
	for id: String in Catalog.LINES:
		for speaker: String in Catalog.SPEAKERS:
			var detail := Catalog.line(id, speaker)
			if not detail.is_empty(): dialogue._streams[detail.voice_path] = fixture_stream
	check(Catalog.LINES.size() == 36, "Story, combat, crew and all nine world entries are authored")
	for environment in ScenarioCatalog.environments():
		check(not Catalog.line("world_" + str(environment.id)).is_empty(), "%s has its own introduction" % environment.id)
	check(Catalog.line("not_a_line").is_empty() and Catalog.line("story_open", "mara").is_empty(), "Unknown IDs and unrecorded speaker combinations are rejected")
	check(not dialogue.enqueue("crew_reply", "branko", 1), "Solo never invents an absent Branko")
	check(not dialogue.enqueue("story_open", "san", 99) and not dialogue.enqueue("story_open", "san", 1, -1), "Invalid anchors and event serials are rejected before mutation")
	check(dialogue.enqueue("story_open", "san", 1, 1), "Authored radio opening enters the queue")
	check(not dialogue.enqueue("story_open", "san", 1, 1), "A duplicate host serial cannot repeat a voice")
	check(dialogue.enqueue("crew_wall", "mara", 1, 2), "Selected solo worker can answer the radio")
	dialogue.advance(0.1)
	check(dialogue.active.id == "story_open" and game.audio.ducked and not dialogue._radio_mode(), "Solo opening starts one speech bubble and ducks music")
	var caption: Dictionary = dialogue.caption_layout()
	var caption_before: Rect2 = caption.rect
	actor.position += Vector2(580,200)
	check(dialogue.caption_layout().rect == caption_before,"Moving the worker keeps complete story text at the screen edge, clear of machines")
	actor.position -= Vector2(580,200)
	check(is_equal_approx(caption_before.position.y,74) and caption_before.size.x <= 430,"Live captions occupy the bounded top-right reading area")
	var rows_fit := true
	for row: String in caption.rows:
		rows_fit = rows_fit and UiArt.FONT.get_string_size(row,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x <= caption_before.size.x - 32
	check(rows_fit,"Authored captions wrap by actual glyph widths without shrinking text")
	var before := dialogue.active_age
	var clock_before := dialogue.elapsed
	paused = true
	dialogue.advance(2.0)
	check(dialogue.active_age == before and dialogue.elapsed == clock_before and dialogue.voice.stream_paused and not dialogue.canvas.visible and not game.audio.ducked, "Real pause freezes text, voice and cooldown clock and releases music ducking")
	paused = false
	dialogue.advance(0.1)
	check(dialogue.active_age > before and not dialogue.voice.stream_paused and game.audio.ducked, "Unpausing continues the same line")
	check(dialogue.enqueue("core_low", "san", 1, 3) and dialogue.active.is_empty(), "Critical core warning interrupts a lower-priority introduction")
	dialogue.advance(0.1)
	check(dialogue.active.id == "core_low", "Critical warning is selected ahead of waiting crew chatter")
	check(not dialogue.enqueue("core_low", "san", 1, 4), "Active warning cannot stack or bypass its cooldown")
	dialogue.reset()
	check(dialogue.active.is_empty() and dialogue.pending.is_empty() and dialogue._seen.is_empty() and not game.audio.ducked and dialogue.voice.stream == null, "Rematch reset clears pending text, serials and playback")
	for id: String in ["world_sector07", "world_ash_foundry", "world_abandoned_harbor", "world_basalt_quarry", "world_overgrown_steelworks", "world_frozen_rail_yard", "world_iron_canyon", "world_flooded_power_station"]:
		dialogue.enqueue(id)
	check(dialogue.pending.size() == Dialogue.MAX_QUEUE and not dialogue.enqueue("world_mountain_pass"), "A full bounded queue refuses redundant low-priority ambience")
	check(dialogue.enqueue("relay_failure") and dialogue.pending.size() == Dialogue.MAX_QUEUE, "A real repair objective displaces the oldest low-priority ambience")
	dialogue.reset()
	dialogue.enqueue("warning_ground")
	dialogue.elapsed = 9.0
	dialogue.advance(0.1)
	check(dialogue.active.is_empty(), "A stale queued approach warning expires before it can mislead the player")
	dialogue.reset()
	dialogue.enqueue("story_open", "san", 1, 400)
	check(not dialogue.enqueue("wall_hint", "san", 1, 100), "Ancient serial replay stays rejected after the bounded dedupe window")
	dialogue.reset()
	dialogue.enqueue("crew_reply", "mara", 1, 1)
	actor.character_id = "ivo"
	dialogue.advance(0.1)
	check(dialogue.active.is_empty(), "Changing the actual character before playback removes the old character's reply")
	for character_id: String in ["mara", "branko", "ivo", "nora", "levin", "selma", "oskar", "rika"]:
		actor.character_id = character_id
		dialogue.reset()
		check(dialogue.enqueue("crew_reply", character_id, 1), "%s has an authored recorded reply" % character_id)
		dialogue.advance(0.1)
		check(dialogue.active.speaker_id == character_id and dialogue.active.text == Catalog.line("crew_reply", character_id).text, "%s subtitle and speaker agree" % character_id)
		check(not dialogue.enqueue("crew_contact", "mara" if character_id != "mara" else "selma", 1), "Absent crew cannot borrow %s's playback anchor" % character_id)
	actor.character_id = "ivo"
	var second := ActorProbe.new()
	second.player_id = 2
	second.character_id = "branko"
	game.add_child(second)
	game.players.append(second)
	check(dialogue._radio_mode(), "Two actual workers use the compact radio subtitle")
	dialogue.reset()
	game.hud.overlay = "victory"
	paused = true
	check(dialogue.enqueue("story_victory", "san", 1, 1) and dialogue.enqueue("crew_final", "ivo", 1, 2), "Victory accepts the radio conclusion and chosen survivor's answer")
	dialogue.advance(0.1)
	check(dialogue.active.id == "story_victory" and dialogue.canvas.visible and not dialogue.voice.stream_paused, "Match-end pause permits the voiced ending on the victory card")
	dialogue.advance(dialogue.active_duration + 0.1)
	check(dialogue.active.id == "crew_final" and dialogue.active.speaker_id == "ivo", "The selected survivor answers after the radio ending")
	game.hud.overlay = "campaign_victory"
	dialogue.advance(.1)
	check(dialogue.canvas.visible and not dialogue.voice.stream_paused, "Completing all campaign sites allows the surviving crew's ending voice")
	game.hud.overlay = "audio"
	before = dialogue.active_age
	dialogue.advance(1.0)
	check(dialogue.active_age == before and dialogue.voice.stream_paused, "Opening Audio on the end card pauses even an ending voice")
	paused = false
	dialogue.reset()
	check(not game.audio.ducked, "Reset while paused releases the music bus")
	# Several simulated line switches occurred within one main-loop frame.
	# Let AudioServer retire the stopped handles before SceneCleanup inspects it.
	await create_timer(0.15, true).timeout
	await preload("res://tests/scene_cleanup.gd").free_scene(game, self)
	print("Story dialogue: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
