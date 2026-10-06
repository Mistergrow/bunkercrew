extends Node2D
## Local presentation on both peers: footsteps are never sent as network events.
## Four spatial voices keep crowds from taking weapon or warning voices.
const MAX_STEP_VOICES := 4
const VARIANTS := 3
const KINDS := ["dry", "metal", "water", "ice", "heavy"]
const EnemyAudio := preload("res://scripts/enemy_audio_catalog.gd")
var audio_owner: Node
var step_streams: Dictionary = {}
var enemy_streams: Dictionary = {}
var voices: Array[AudioStreamPlayer2D] = []
var wind_player: AudioStreamPlayer
var steps_played := 0
var wind_gain := 0.0
var _serial := 0
var _wind_probe := 0.0
var _wind_target := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	for kind: String in KINDS:
		var choices: Array[AudioStream] = []
		for index in VARIANTS:
			choices.append(load("res://assets/audio/step_%s_%02d.wav" % [kind,index+1]))
		step_streams[kind] = choices
	for family: String in EnemyAudio.FAMILIES:
		for surface: String in EnemyAudio.SURFACES:
			var key := "%s_%s"%[family,surface]
			var choices: Array[AudioStream] = []
			for index in EnemyAudio.VARIANTS:
				choices.append(load("res://assets/audio/enemy_step_%s_%02d.wav"%[key,index+1]))
			enemy_streams[key] = choices
	for index in MAX_STEP_VOICES:
		var voice := AudioStreamPlayer2D.new()
		voice.name = "FootContact%d" % index
		voice.process_mode = Node.PROCESS_MODE_PAUSABLE
		voice.bus = "SFX"
		voice.max_distance = 1150.0
		voice.attenuation = 1.4
		voice.panning_strength = 0.75
		add_child(voice)
		voices.append(voice)
	wind_player = AudioStreamPlayer.new()
	wind_player.name = "OutdoorWind"
	wind_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	wind_player.bus = "SFX"
	wind_player.volume_db = -80.0
	var wind_stream := load("res://assets/audio/ambience_wind.ogg") as AudioStreamOggVorbis
	wind_stream.loop = true
	wind_player.stream = wind_stream
	add_child(wind_player)
	tree_exiting.connect(stop_effects)

func play_footstep(surface_kind: String, point: Vector2, strength: float, heavy: bool, player: bool, enemy_kind: String = "", character_id: String = "") -> bool:
	if get_tree().paused or not is_instance_valid(audio_owner) or audio_owner.sfx_volume<=0.0 or not point.is_finite() or not is_finite(strength):
		return false
	var kind := "heavy" if heavy and surface_kind in ["dry","metal"] else surface_kind
	var enemy_key := EnemyAudio.contact_key(enemy_kind,surface_kind) if not player else ""
	if player and not character_id.is_empty() and surface_kind in EnemyAudio.SURFACES:
		var profile := CharacterCatalog.presentation_id(character_id,"motion")
		var family: String = "boot_heavy" if profile=="branko" else ("boot_light" if profile in ["ivo","levin"] else "boot_standard")
		enemy_key = "%s_%s"%[family,surface_kind]
	if not enemy_key.is_empty(): kind = enemy_key
	var bank: Dictionary = enemy_streams if not enemy_key.is_empty() else step_streams
	if not bank.has(kind): return false
	var game = audio_owner.game
	var listener := Vector2.ZERO
	if is_instance_valid(game) and is_instance_valid(game.get("camera")):
		listener = game.camera.get_screen_center_position()
	elif is_instance_valid(game) and "players" in game and not game.players.is_empty():
		listener = game.players[0].global_position
	if audio_owner.get("acoustics") != null:
		listener = audio_owner.acoustics.refresh_listener_position()
	if point.distance_to(listener)>1150.0:
		return false
	var chosen: AudioStreamPlayer2D
	var oldest := 9223372036854775807
	for voice in voices:
		if not voice.playing:
			chosen = voice
			break
		# Enemy crowds cannot replace a still-audible player's step.
		if not player and bool(voice.get_meta("player",false)): continue
		var order := int(voice.get_meta("serial",0))
		if order<oldest:
			oldest = order
			chosen = voice
	if not is_instance_valid(chosen):
		return false
	chosen.stop()
	var count: int = bank[kind].size()
	chosen.stream = bank[kind][audio_owner._next_variant("step_"+kind,count)]
	chosen.global_position = point
	chosen.volume_db = (-13.0 if player else -20.0)+linear_to_db(clampf(sqrt(maxf(.1,strength)),.65,1.35))
	if not enemy_key.is_empty(): chosen.volume_db += 2.0
	chosen.pitch_scale = .88 if heavy and enemy_key.is_empty() else 1.0
	if player: chosen.pitch_scale *= float({"mara":1.0,"branko":.93,"ivo":1.06,"nora":.97,"levin":1.12,"selma":1.03}.get(CharacterCatalog.presentation_id(character_id,"motion"),1.0))
	_serial += 1
	chosen.set_meta("serial",_serial)
	chosen.set_meta("player",player)
	chosen.set_meta("kind",kind)
	chosen.set_meta("enemy_kind",enemy_kind)
	chosen.set_meta("character_id",character_id)
	chosen.play()
	steps_played += 1
	return true

func _process(delta: float) -> void:
	if not is_instance_valid(audio_owner) or audio_owner.sfx_volume<=0:
		stop_effects()
		wind_gain = 0
		return
	_wind_probe -= delta
	if _wind_probe<=0:
		_wind_probe = .125
		_wind_target = 0.0
		var game = audio_owner.game
		if is_instance_valid(game) and game.get("started")==true and is_instance_valid(game.get("weather")):
			var exposure := 0.0
			var count := 0
			if "players" in game:
				for actor in game.players:
					if not is_instance_valid(actor) or not is_instance_valid(actor.get("wetness")): continue
					exposure += float(actor.wetness.exposure)
					count += 1
			if count>0: exposure /= count
			# Acoustic listeners ignore a remote network partner's room.
			# The fallback above preserves simple editor/test worlds.
			if audio_owner.get("acoustics") != null:
				exposure = float(audio_owner.acoustics.exposure)
			var gust: float = game.weather.wind_strength() if game.weather.has_method("wind_strength") else .5
			if game.weather.has_method("gust_at") and audio_owner.get("acoustics") != null:
				gust = game.weather.gust_at(audio_owner.acoustics.listener_position)
			_wind_target = lerpf(.012,.080,exposure)*lerpf(.08,1.0,clampf(gust,0,1))
	wind_gain = move_toward(wind_gain,_wind_target,delta*.07)
	if wind_gain>.0001:
		wind_player.volume_db = linear_to_db(wind_gain)
		if not wind_player.playing: wind_player.play()
	elif wind_player.playing:
		wind_player.stop()

func stop_effects() -> void:
	for voice in voices:
		voice.stop()
	if is_instance_valid(wind_player): wind_player.stop()

func _exit_tree() -> void:
	stop_effects()
	for voice in voices: voice.stream = null
	if is_instance_valid(wind_player): wind_player.stream = null
