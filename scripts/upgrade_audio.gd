extends Node
## UI confirmations remain audible while the research screen pauses the world.
const KINDS := ["tech_upgrade_base","tech_upgrade_weapons","tech_upgrade_crew","tech_upgrade_vehicle"]
const VARIANTS := 3
const MAX_VOICES := 2
var audio_owner: Node
var streams: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var last_played := -10000
var serial := 0
var sounds_played := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for kind: String in KINDS:
		var choices: Array[AudioStream] = []
		for index in VARIANTS:
			choices.append(load("res://assets/audio/%s_%02d.wav"%[kind,index+1]))
		streams[kind] = choices
	for index in MAX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name = "ResearchConfirmation%d"%index
		voice.process_mode = Node.PROCESS_MODE_ALWAYS
		voice.bus = "SFX"
		add_child(voice)
		voices.append(voice)

func play_sound(kind: String) -> bool:
	if not streams.has(kind) or not is_instance_valid(audio_owner) or audio_owner.sfx_volume<=0: return false
	var now := Time.get_ticks_msec()
	if now-last_played<80: return false
	var selected: AudioStreamPlayer
	for voice in voices:
		if not voice.playing:
			selected = voice
			break
		if selected==null or int(voice.get_meta("serial",0))<int(selected.get_meta("serial",0)):
			selected = voice
	selected.stop()
	selected.stream = streams[kind][audio_owner._next_variant(kind,VARIANTS)]
	selected.volume_db = -7.0
	selected.pitch_scale = 1.0
	serial += 1
	selected.set_meta("serial",serial)
	selected.set_meta("kind",kind)
	selected.play()
	last_played = now
	sounds_played += 1
	return true

func stop_effects() -> void:
	for voice in voices: voice.stop()

func _exit_tree() -> void:
	stop_effects()
	for voice in voices: voice.stream = null
