extends SceneTree
## Rapid dialogue switches retain only weak decoder references for safe teardown.
const Dialogue := preload("res://scripts/story_dialogue.gd")
const Catalog := preload("res://scripts/story_dialogue_catalog.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

class AudioProbe extends Node:
	var ducked := false
	func set_dialogue_active(value: bool) -> void: ducked = value

class HudProbe extends Node:
	var overlay := ""

class GameProbe extends Node2D:
	var audio: AudioProbe
	var hud: HudProbe
	var players: Array = []

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func run() -> void:
	LocaleText.set_locale("de", false)
	var game := GameProbe.new()
	root.add_child(game)
	game.audio = AudioProbe.new()
	game.add_child(game.audio)
	game.hud = HudProbe.new()
	game.add_child(game.hud)
	var dialogue := Dialogue.new()
	dialogue.game = game
	game.add_child(dialogue)
	dialogue.set_process(false)
	var stream := AudioStreamWAV.new()
	stream.mix_rate = 8000
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	var silence := PackedByteArray()
	silence.resize(80000)
	silence.fill(128)
	stream.data = silence
	dialogue._streams[Catalog.recording_path("story_open", "san", "de")] = stream
	for _iteration in 8:
		dialogue.enqueue("story_open")
		dialogue.advance(0.1)
		check(dialogue.voice.has_stream_playback() and game.audio.ducked, "A genuine WAV playback starts and ducks music")
		dialogue.reset()
		check(dialogue.voice.stream == null and not game.audio.ducked, "Reset stops the actual voice and releases its stream and ducking")
	var retired := dialogue.get_retired_audio_playbacks()
	check(not retired.is_empty(), "Rapidly stopped actual decoders remain observable through weak references")
	dialogue.enqueue("story_open")
	dialogue.advance(0.1)
	var active_playback: WeakRef = weakref(dialogue.voice.get_stream_playback())
	game.remove_child(dialogue)
	check(not dialogue.voice.playing and dialogue.voice.stream == null and not game.audio.ducked, "Removing a live dialogue from the tree stops the voice and restores music")
	retired.append(active_playback)
	game.add_child(dialogue)
	dialogue.set_process(false)
	check(await Cleanup.free_scene(game, self), "SceneCleanup waits for all active and retired dialogue playback handles")
	check(retired.all(func(playback: WeakRef): return playback.get_ref() == null), "Teardown releases every actual stopped decoder without strong retention")
	print("STORY DIALOGUE LIFECYCLE: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
