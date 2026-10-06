extends Node
## Cached sample bank, bounded effect voices and synchronized world scores.

const Catalog := preload("res://scripts/audio_catalog.gd")
const Defaults := preload("res://scripts/audio_defaults.gd")
const MAX_VOICES := 12
const MAX_COOLDOWN_KEYS := 128
const MUSIC_CROSSFADE_SECONDS := 2.4
# Relative to the established mix: music +10%, recorded character voices -10%.
# Keep these gains separate from the player's saved volume sliders.
const MUSIC_MIX_TRIM_DB := -7.172146296835499
const VOICE_MIX_TRIM_DB := -0.9151498112135024
const VARIANT_COUNTS := Catalog.VARIANT_COUNTS
const COOLDOWN_MS := Catalog.COOLDOWN_MS
const LEVEL_DB := Catalog.LEVEL_DB
const PRIORITY := Catalog.PRIORITY

var game
var music_volume := Defaults.MUSIC_VOLUME
var sfx_volume := Defaults.SFX_VOLUME
var voice_volume := Defaults.VOICE_VOLUME
var live_music_enabled := Defaults.LIVE_MUSIC
var music_style := Defaults.MUSIC_STYLE
var rhythm_motion_reduced := Defaults.RHYTHM_MOTION_REDUCED
var music_calibration_seconds := 0.0
var dance_intensity := Defaults.DANCE_INTENSITY
var dance_profiles: Dictionary = Defaults.dance_profiles()
var live_music: Node
var menu_music: Node
var calibration_active := false
var settings_path := "user://audio.cfg"
var bus_layout_path := ""
var bus_mix := preload("res://scripts/audio_bus_mix.gd").new()
var persistence_enabled := "--no-profile-save" not in OS.get_cmdline_user_args()
var streams: Dictionary = {}
var variants: Dictionary = {}
var cooldowns: Dictionary = {}
var music_player: AudioStreamPlayer
var music_stream: AudioStreamSynchronized
var music_blend := 0.0
var music_set := "base"
var music_players: Array[AudioStreamPlayer] = []
var voices: Array[AudioStreamPlayer] = []
var movement: Node2D
var aircraft_audio: Node2D
var machinery_audio: Node2D
var upgrade_audio: Node
var acoustics: RefCounted
var _dialogue_active := false
var _dialogue_sources := {"story": false, "air_intro": false, "travel_intro": false}
var _variant_bags: Dictionary = {}
var _last_variants: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _score_streams: Dictionary = {}
var _active_deck := 0
var _requested_music_set := "base"
var _crossfade := 1.0
var _score_level := -7.0
var _last_blend := -1.0
var _voice_serial := 0
var _settings_dirty := false
var _save_delay := 0.0
var _handling_duck_left := 0.0
var _handling_duck_db := 0.0
var _handling_duck_target := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not is_instance_valid(game):
		game = get_parent()
	_ensure_buses()
	bus_mix.setup(bus_layout_path if not bus_layout_path.is_empty() else str(ProjectSettings.get_setting("audio/buses/default_bus_layout", "res://default_bus_layout.tres")))
	_load_settings()
	_apply_bus_volume("Music", music_volume)
	_apply_bus_volume("SFX", sfx_volume)
	_apply_bus_volume("Voice", voice_volume)
	_rng.randomize()
	for kind: String in VARIANT_COUNTS:
		var choices: Array[AudioStream] = []
		for index in int(VARIANT_COUNTS[kind]):
			var stream: AudioStream = load("res://assets/audio/%s_%02d.wav" % [kind, index+1])
			choices.append(stream)
		variants[kind] = choices
		streams[kind] = choices[0]
	for index in MAX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name = "EffectVoice%d" % index
		voice.bus = "SFX"
		voice.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(voice)
		voices.append(voice)
	_start_music()
	movement = preload("res://scripts/movement_audio.gd").new()
	movement.name = "MovementAudio"
	movement.audio_owner = self
	add_child(movement)
	upgrade_audio = preload("res://scripts/upgrade_audio.gd").new()
	upgrade_audio.name = "UpgradeAudio"
	upgrade_audio.audio_owner = self
	add_child(upgrade_audio)
	acoustics = preload("res://scripts/environment_acoustics.gd").new()
	acoustics.setup(self)
	aircraft_audio = preload("res://scripts/aircraft_audio.gd").new()
	aircraft_audio.name = "AircraftAudio"
	aircraft_audio.audio_owner = self
	add_child(aircraft_audio)
	machinery_audio = preload("res://scripts/machinery_audio.gd").new()
	machinery_audio.name = "MachineryAudio"
	machinery_audio.audio_owner = self
	add_child(machinery_audio)
	live_music = preload("res://scripts/live_music.gd").new()
	live_music.name = "LiveMusicSession"
	add_child(live_music)
	live_music.live_enabled = live_music_enabled
	live_music.set_music_style(music_style)
	live_music.set_calibration_seconds(music_calibration_seconds)
	live_music.set_rhythm_motion_reduced(rhythm_motion_reduced)
	live_music.set_dance_configuration(dance_intensity,dance_profiles)
	live_music.fallback_requested.connect(func(_id: String): _restore_recorded_music())
	menu_music = preload("res://scripts/menu_music.gd").new()
	menu_music.name = "MenuMusicSession"
	add_child(menu_music)

func _ensure_buses() -> void:
	for title: String in ["Music", "SFX", "Voice"]:
		if AudioServer.get_bus_index(title) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count-1
			AudioServer.set_bus_name(index, title)
			AudioServer.set_bus_send(index, "Master")
	# The shipped layout already places its output gain before the ceiling.
	# Recover old/custom layouts too: a post-effect Master fader would boost an
	# already limited peak above zero. Never add the preserved gain twice.
	var master := AudioServer.get_bus_index("Master")
	var limiter: AudioEffectHardLimiter
	for index in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, index) is AudioEffectHardLimiter:
			limiter = AudioServer.get_bus_effect(master,index)
			break
	if limiter == null:
		limiter = AudioEffectHardLimiter.new()
		limiter.resource_name = "LastShiftOutputCeiling"
		AudioServer.add_bus_effect(master, limiter)
	var output_gain := AudioServer.get_bus_volume_db(master)
	if not is_zero_approx(output_gain):
		limiter.pre_gain_db += output_gain
		AudioServer.set_bus_volume_db(master,0.0)
	limiter.ceiling_db = minf(limiter.ceiling_db,-1.0)

func _start_music() -> void:
	# Ogg data and synchronized arrangements are prepared once, before playback.
	for score_id: String in Catalog.MUSIC_SETS:
		var score := AudioStreamSynchronized.new()
		score.stream_count = 2
		for index in 2:
			var arrangement := "calm" if index == 0 else "combat"
			var stem: AudioStreamOggVorbis = load("res://assets/audio/" + Catalog.MUSIC_SETS[score_id][arrangement])
			stem.loop = true
			score.set_sync_stream(index, stem)
		score.set_sync_stream_volume(0, 0.0)
		score.set_sync_stream_volume(1, -80.0)
		_score_streams[score_id] = score
	for index in 2:
		var player := AudioStreamPlayer.new()
		player.name = "SynchronizedScore%d" % index
		player.bus = "Music"
		player.volume_db = -80.0
		add_child(player)
		# Release native playback while this child is still in the tree.
		player.tree_exiting.connect(_stop_deck.bind(index))
		music_players.append(player)
	music_set = _requested_music_set
	music_player = music_players[0]
	music_stream = _score_streams[music_set]
	music_player.stream = music_stream
	music_player.set_meta("score_id", music_set)
	music_player.volume_db = _score_level + Catalog.score_gain_db(music_set)
	_begin_music.call_deferred()

func _begin_music() -> void:
	# A preview/test scene may be disposed during the same frame as _ready.
	# Avoid enqueueing a synchronized playback for a scene already leaving.
	if not is_inside_tree() or is_queued_for_deletion() or get_parent().is_queued_for_deletion():
		return
	if _menu_context():
		_sync_menu_music()
		return
	if _live_score_active():
		return
	if is_instance_valid(music_player) and not _deck_active(music_player):
		music_player.play()

func _deck_active(player: AudioStreamPlayer) -> bool:
	# Godot's playing flag is false during stream_paused, but the decoder and
	# position are still owned by this deck. Repeated restores must not restart it.
	return player.playing or (player.stream_paused and player.has_stream_playback())

func set_environment(environment_id: String) -> void:
	_requested_music_set = Catalog.score_for_environment(environment_id)
	# Coalesce fast menu selections. Never cut a half-audible deck to load a third.
	if _crossfade >= 1.0 and _requested_music_set != music_set and not _live_score_active() and not _menu_context():
		_transition_music()
	if is_instance_valid(live_music) and not live_music.session_active:
		live_music.configure_environment(environment_id)

func _transition_music() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or music_players.size() != 2 or not _score_streams.has(_requested_music_set):
		return
	var source_length := maxf(music_stream.get_length(), 0.001)
	var source_phase := fposmod(music_player.get_playback_position(), source_length) / source_length
	_active_deck = 1 - _active_deck
	music_set = _requested_music_set
	music_player = music_players[_active_deck]
	music_stream = _score_streams[music_set]
	music_player.stream = music_stream
	music_player.set_meta("score_id", music_set)
	music_player.volume_db = -80.0
	_set_arrangement_mix(music_stream)
	# New pieces have individual tempos but the same 32-bar cycle. Enter at the
	# corresponding musical position rather than copying arbitrary seconds.
	music_player.play(source_phase * music_stream.get_length())
	_crossfade = 0.0

func _set_arrangement_mix(score: AudioStreamSynchronized) -> void:
	# Calm material is also present in combat; linear weights preserve its level.
	score.set_sync_stream_volume(0, linear_to_db(maxf(1.0 - music_blend, 0.0001)))
	score.set_sync_stream_volume(1, linear_to_db(maxf(music_blend, 0.0001)))

func _recorded_score_level(score_id: String) -> float:
	return -80.0 if calibration_active else _score_level + Catalog.score_gain_db(score_id)

func _process(delta: float) -> void:
	# Editor faders are automatically saved in the authored layout. Adopt their
	# baseline without replacing live voice capture/spatial buses or preferences.
	if bus_mix.poll():
		_apply_bus_volume("Music", music_volume)
		_apply_bus_volume("SFX", sfx_volume)
		_apply_bus_volume("Voice", voice_volume)
	_sync_menu_music()
	if acoustics != null: acoustics.update(delta)
	var phase := "build"
	var playing_round := false
	if is_instance_valid(game) and "rounds" in game:
		playing_round = game.started
		if is_instance_valid(game.rounds):
			phase = game.rounds.phase
	var target := 1.0 if phase == "attack" else (0.42 if phase == "warning" else 0.0)
	music_blend = move_toward(music_blend, target, delta * 0.40)
	if not is_equal_approx(_last_blend, music_blend):
		for player in music_players:
			if player.stream is AudioStreamSynchronized:
				_set_arrangement_mix(player.stream)
		_last_blend = music_blend
	var level := -7.0
	# The menu pauses gameplay too; only an actual round needs pause ducking.
	if playing_round and get_tree().paused:
		level -= 4.0
	var chat_active: bool = is_instance_valid(game) and "voice" in game and is_instance_valid(game.voice) and (game.voice.speaking or game.voice.remote_speaking)
	var duck_music: bool = (_dialogue_active and voice_volume > 0.0 and _channel_unmuted("Voice")) or chat_active
	if duck_music: level -= 6.0
	if not get_tree().paused:
		_handling_duck_left = maxf(0.0,_handling_duck_left-delta)
		var duck_target := _handling_duck_target if _handling_duck_left > 0.0 and sfx_volume > 0.0 and _channel_unmuted("SFX") else 0.0
		_handling_duck_db = move_toward(_handling_duck_db,duck_target,delta*(100.0 if duck_target>_handling_duck_db else 12.0))
	level -= _handling_duck_db
	_score_level = move_toward(_score_level, level, delta * (24.0 if duck_music or _handling_duck_db>0.01 else 5.0))
	_tick_live_music(delta)
	if _menu_score_active():
		menu_music.tick(music_volume > 0.0 and not calibration_active, music_calibration_seconds, -80.0 if calibration_active else _score_level + 7.0)
	elif _live_score_active():
		# The native source is loudness-normalized; apply the existing pause,
		# dialogue and handling reductions without a second source trim.
		live_music.set_mix_level_db(-80.0 if calibration_active else _score_level+7.0)
	elif _crossfade < 1.0:
		_crossfade = minf(1.0, _crossfade + delta / MUSIC_CROSSFADE_SECONDS)
		# Different compositions use an equal-power fade to avoid a midpoint dip.
		music_players[_active_deck].volume_db = _recorded_score_level(str(music_players[_active_deck].get_meta("score_id", "base"))) + linear_to_db(maxf(sin(_crossfade * PI * 0.5), 0.0001))
		music_players[1 - _active_deck].volume_db = _recorded_score_level(str(music_players[1 - _active_deck].get_meta("score_id", "base"))) + linear_to_db(maxf(cos(_crossfade * PI * 0.5), 0.0001))
		if _crossfade >= 1.0:
			_stop_deck(1 - _active_deck)
			if _requested_music_set != music_set:
				_transition_music()
	elif is_instance_valid(music_player):
		var recorded_level := _recorded_score_level(music_set)
		if not is_equal_approx(music_player.volume_db,recorded_level): music_player.volume_db=recorded_level
	if _settings_dirty:
		_save_delay -= delta
		if _save_delay <= 0:
			save_settings()

func _channel_unmuted(channel: String) -> bool:
	# Authored/native bus mutes must suppress attenuation for silent cues too.
	var bus_index := AudioServer.get_bus_index(channel)
	return bus_index>=0 and not AudioServer.is_bus_mute(bus_index)

func play_sound(requested_kind: String) -> bool:
	return _play_sound(requested_kind, Vector2(INF, INF))

func play_sound_at(requested_kind: String, point: Vector2) -> bool:
	if not point.is_finite(): return false
	return _play_sound(requested_kind, point)

func _play_sound(requested_kind: String, point: Vector2) -> bool:
	if requested_kind in preload("res://scripts/upgrade_audio.gd").KINDS:
		return upgrade_audio.play_sound(requested_kind) if is_instance_valid(upgrade_audio) else false
	var kind: String = Catalog.ALIASES.get(requested_kind, requested_kind)
	if not variants.has(kind) or sfx_volume <= 0.0 or get_tree().paused:
		return false
	var now := Time.get_ticks_msec()
	var cooldown_key := kind
	# Independent world sources can speak in the same frame. A global cooldown
	# made the first gun/impact silence every other source, including the other ear.
	# Repeated contacts in one small area remain throttled and memory stays capped.
	if point.is_finite() and kind not in ["warning","start","thunder"]:
		var cell := 8.0 if kind.begins_with("reload_") or kind in ["weapon_mount","weapon_switch"] else 32.0
		cooldown_key += "@%d,%d" % [floori(point.x/cell),floori(point.y/cell)]
	if now - int(cooldowns.get(cooldown_key, -10000)) < int(COOLDOWN_MS.get(kind, 150)):
		return false
	var chosen: AudioStreamPlayer
	var lowest_priority := 100
	var oldest_serial := 9223372036854775807
	var furthest_distance := -1.0
	var listener: Vector2 = acoustics.refresh_listener_position() if acoustics != null else Vector2.ZERO
	var incoming_distance := point.distance_to(listener) if point.is_finite() and kind not in ["warning","start"] else 0.0
	for voice in voices:
		if not voice.playing:
			chosen = voice
			break
		var importance := int(PRIORITY.get(voice.get_meta("kind", ""), 2))
		var serial := int(voice.get_meta("serial", 0))
		var source: Vector2 = voice.get_meta("acoustic_source",Vector2(INF,INF))
		var distance := source.distance_to(listener) if source.is_finite() else 0.0
		if importance < lowest_priority or (importance == lowest_priority and (distance > furthest_distance or (is_equal_approx(distance,furthest_distance) and serial < oldest_serial))):
			lowest_priority = importance
			oldest_serial = serial
			furthest_distance = distance
			chosen = voice
	if not is_instance_valid(chosen):
		return false
	if chosen.playing and lowest_priority > int(PRIORITY.get(kind, 2)):
		return false
	if chosen.playing and lowest_priority == int(PRIORITY.get(kind,2)) and incoming_distance > furthest_distance+320.0:
		# A distant crowd must not cut off the nearby shot/contact currently heard.
		return false
	if not cooldowns.has(cooldown_key) and cooldowns.size() >= MAX_COOLDOWN_KEYS:
		var oldest_key: String = cooldowns.keys()[0]
		for key: String in cooldowns:
			if int(cooldowns[key]) < int(cooldowns[oldest_key]): oldest_key = key
		cooldowns.erase(oldest_key)
	cooldowns[cooldown_key] = now
	var choices: Array = variants[kind]
	var index := _next_variant(kind, choices.size())
	chosen.stop()
	chosen.stream = choices[index]
	chosen.volume_db = Catalog.effect_level_db(kind)
	chosen.pitch_scale = 1.0
	chosen.set_meta("kind", kind)
	_voice_serial += 1
	chosen.set_meta("serial", _voice_serial)
	if acoustics != null: acoustics.prepare_voice(voices.find(chosen), kind, point)
	chosen.play()
	if kind.begins_with("reload_"):
		var proximity := 1.0
		if point.is_finite() and acoustics != null:
			proximity = clampf(1.0-point.distance_to(acoustics.listener_position)/700.0,0.0,1.0)
		if proximity > 0.0:
			_handling_duck_left = 0.34
			_handling_duck_target = 3.5*proximity
	return true

func play_footstep(kind: String, point: Vector2, strength: float = 1.0, heavy: bool = false, player: bool = true, enemy_kind: String = "", character_id: String = "") -> bool:
	if not is_instance_valid(movement): return false
	var accepted: bool = movement.play_footstep(kind,point,strength,heavy,player,enemy_kind,character_id)
	if accepted and acoustics != null: acoustics.route_steps(movement)
	return accepted

func set_voice_volume(value: float) -> void:
	if not is_finite(value): return
	voice_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume("Voice", voice_volume)
	_settings_dirty = true
	_save_delay = .35

func set_dialogue_active(value: bool, source: String = "story") -> void:
	# Pausing world dialogue must not release the separately playing air intro.
	# Known owners set their own state; repeated calls never accumulate a count.
	if not _dialogue_sources.has(source): return
	_dialogue_sources[source] = value
	_dialogue_active = _dialogue_sources.story or _dialogue_sources.air_intro or _dialogue_sources.travel_intro

func _next_variant(kind: String, count: int) -> int:
	var bag: Array = _variant_bags.get(kind, [])
	if bag.is_empty():
		for index in count:
			bag.append(index)
		for index in range(count - 1, 0, -1):
			var other := _rng.randi_range(0, index)
			var held: int = bag[index]
			bag[index] = bag[other]
			bag[other] = held
		if count > 1 and int(bag.back()) == int(_last_variants.get(kind, -1)):
			var held: int = bag[0]
			bag[0] = bag[count - 1]
			bag[count - 1] = held
	var selected := int(bag.pop_back())
	_variant_bags[kind] = bag
	_last_variants[kind] = selected
	return selected

func set_music_volume(value: float) -> void:
	if not is_finite(value):
		return
	music_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume("Music", music_volume)
	if is_instance_valid(live_music): live_music.set_music_enabled(music_volume>0.0)
	if is_instance_valid(menu_music) and menu_music.playing:
		menu_music.tick(music_volume > 0.0 and not calibration_active, music_calibration_seconds, -80.0 if calibration_active else _score_level + 7.0)
	_settings_dirty = true
	_save_delay = 0.35

func set_sfx_volume(value: float) -> void:
	if not is_finite(value):
		return
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume("SFX", sfx_volume)
	if sfx_volume <= 0.0:
		_handling_duck_left = 0.0
		_handling_duck_target = 0.0
		for voice in voices:
			voice.stop()
		if is_instance_valid(movement): movement.stop_effects()
		if is_instance_valid(aircraft_audio): aircraft_audio.stop_effects()
		if is_instance_valid(machinery_audio): machinery_audio.stop_effects()
		if is_instance_valid(upgrade_audio): upgrade_audio.stop_effects()
	_settings_dirty = true
	_save_delay = 0.35

func _apply_bus_volume(title: String, value: float) -> void:
	# The authored fader is the baseline. Fifty percent is neutral; preferences
	# scale that baseline instead of erasing the sound designer's bus settings.
	bus_mix.apply(title, value)

func _load_settings() -> void:
	# Diagnostics must not inherit a real player's muted music or reduced-motion
	# preference. Tests which exercise persistence use an explicit isolated path.
	if not persistence_enabled and settings_path == "user://audio.cfg":
		return
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		var version: Variant = config.get_value("audio", "mix_version", 1)
		var normalized: bool = (version is int or version is float) and float(version) == Defaults.MIX_VERSION
		music_volume = _load_volume(config, "music", "Music", Defaults.MUSIC_VOLUME, normalized)
		sfx_volume = _load_volume(config, "sfx", "SFX", Defaults.SFX_VOLUME, normalized)
		voice_volume = _load_volume(config, "voice", "Voice", Defaults.VOICE_VOLUME, normalized)
		var live: Variant=config.get_value("rhythm","live_music",Defaults.LIVE_MUSIC)
		live_music_enabled=live if live is bool else Defaults.LIVE_MUSIC
		var style: Variant=config.get_value("rhythm","music_style",Defaults.MUSIC_STYLE)
		music_style=style if preload("res://scripts/music_genre_catalog.gd").valid_selection(style) else Defaults.MUSIC_STYLE
		var reduced: Variant=config.get_value("rhythm","reduced_motion",Defaults.RHYTHM_MOTION_REDUCED)
		rhythm_motion_reduced=reduced if reduced is bool else Defaults.RHYTHM_MOTION_REDUCED
		var offset: Variant=config.get_value("rhythm","calibration_seconds",0.0)
		music_calibration_seconds=clampf(float(offset),-.5,.5) if (offset is float or offset is int) and is_finite(float(offset)) else 0.0
		var gain: Variant=config.get_value("rhythm","dance_intensity",Defaults.DANCE_INTENSITY)
		dance_intensity=clampf(float(gain),0.0,1.5) if (gain is float or gain is int) and is_finite(float(gain)) else Defaults.DANCE_INTENSITY
		dance_profiles=preload("res://scripts/worker_dance_catalog.gd").normalized_profiles(config.get_value("rhythm","dance_profiles",{}))
		# Save the new units once; unchanged legacy gains retain their exact mix.
		# Isolated diagnostics never write the real profile.
		if not normalized and persistence_enabled:
			_settings_dirty = true
			_save_delay = .35

func _load_volume(config: ConfigFile, key: String, channel: String, fallback: float, normalized: bool) -> float:
	if not config.has_section_key("audio", key): return fallback
	var value: Variant = config.get_value("audio", key)
	if not (value is float or value is int) or not is_finite(float(value)):
		return fallback
	var saved := _saved_volume(value, fallback)
	return saved if normalized else Defaults.legacy_slider(channel, saved)

func _saved_volume(value: Variant, fallback: float) -> float:
	# ConfigFile accepts arbitrary Variants, including arrays and non-finite
	# numbers. A malformed channel must not stop initialization of the score.
	if not (value is float or value is int) or not is_finite(float(value)):
		return fallback
	return clampf(float(value), 0.0, 1.0)

func save_settings() -> void:
	if not persistence_enabled:
		_settings_dirty = false
		return
	var config := ConfigFile.new()
	config.load(settings_path)
	var saved_profiles: Dictionary = dance_profiles.duplicate(true)
	var previous: Variant = config.get_value("rhythm","dance_profiles",{})
	if previous is Dictionary and previous.size()<=4096:
		for id: Variant in previous:
			if preload("res://scripts/content_registry.gd").valid_id(id) and not CharacterCatalog.contains(id):
				saved_profiles[id] = previous[id]
	config.set_value("audio", "mix_version", Defaults.MIX_VERSION)
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "sfx", sfx_volume)
	config.set_value("audio", "voice", voice_volume)
	config.set_value("rhythm","live_music",live_music_enabled)
	config.set_value("rhythm","music_style",music_style)
	config.set_value("rhythm","reduced_motion",rhythm_motion_reduced)
	config.set_value("rhythm","calibration_seconds",music_calibration_seconds)
	config.set_value("rhythm","dance_intensity",dance_intensity)
	config.set_value("rhythm","dance_profiles",saved_profiles)
	config.save(settings_path)
	_settings_dirty = false

func _stop_music() -> void:
	for index in music_players.size():
		_stop_deck(index)
	music_stream = null

func _stop_deck(index: int) -> void:
	if index < music_players.size() and is_instance_valid(music_players[index]):
		music_players[index].stop()
		music_players[index].stream = null

func _exit_tree() -> void:
	set_dialogue_active(false, "story")
	set_dialogue_active(false, "air_intro")
	set_dialogue_active(false, "travel_intro")
	if _settings_dirty:
		save_settings()
	_stop_music()
	if is_instance_valid(menu_music): menu_music.stop()
	if is_instance_valid(live_music): live_music.end_session()
	if is_instance_valid(upgrade_audio): upgrade_audio.stop_effects()
	if is_instance_valid(aircraft_audio): aircraft_audio.stop_effects()
	if is_instance_valid(machinery_audio): machinery_audio.stop_effects()
	for voice in voices:
		voice.stop()
		voice.stream = null
	if acoustics != null:
		acoustics.release()
		acoustics = null

func drain_for_exit() -> bool:
	# AudioServer retires stopped decoders on later mixer updates. A confirmed
	# window handoff must release them before its process unloads the extension.
	set_process(false)
	var pending: Array[WeakRef] = []
	var players := find_children("*", "AudioStreamPlayer", true, false)
	players.append_array(find_children("*", "AudioStreamPlayer2D", true, false))
	for player in players:
		if player.has_stream_playback(): pending.append(weakref(player.get_stream_playback()))
		player.stop()
		player.stream = null
	_stop_music()
	for owner_node in [menu_music, live_music]:
		if not is_instance_valid(owner_node): continue
		if owner_node == menu_music: owner_node.stop()
		else: owner_node.end_session()
		pending.append_array(owner_node.get_retired_music_playbacks())
	if is_instance_valid(movement): movement.stop_effects()
	if is_instance_valid(aircraft_audio): aircraft_audio.stop_effects()
	if is_instance_valid(machinery_audio): machinery_audio.stop_effects()
	if is_instance_valid(upgrade_audio): upgrade_audio.stop_effects()
	if _settings_dirty: save_settings()
	var deadline := Time.get_ticks_msec() + 5000
	while pending.any(func(playback: WeakRef): return playback.get_ref() != null):
		if Time.get_ticks_msec() >= deadline: return false
		await get_tree().process_frame
	return true

func _live_score_active() -> bool:
	return is_instance_valid(live_music) and live_music.native_active

func _menu_context() -> bool:
	# Isolated Audio fixtures retain their existing world-score behavior. Only
	# the actual game's pre-match shell owns this dedicated menu composition.
	return is_instance_valid(game) and game.has_method("start_scenario") and "hud" in game and "started" in game and not game.started

func _menu_score_active() -> bool:
	return is_instance_valid(menu_music) and menu_music.playing and _menu_context()

func _sync_menu_music() -> void:
	if not is_instance_valid(menu_music): return
	if _menu_context():
		if not menu_music.playing:
			_stop_music()
			_crossfade = 1.0
			menu_music.start()
	elif menu_music.playing:
		menu_music.stop()

func menu_rhythm_frame() -> Dictionary:
	if not _menu_context() or not is_instance_valid(menu_music) or music_volume <= 0.0 or calibration_active:
		return {"active": false, "kick_pulse": 0.0, "audible_seconds": -1.0, "bpm": 128.0, "beat": -1, "phase": 0.0, "kick_timestamp": -INF, "kick_strength": 0.0, "secondary_pulse": 0.0, "secondary_timestamp": -INF, "secondary_strength": 0.0}
	return menu_music.rhythm_frame()

func begin_live_music(environment_id: String, score_seed: int = 0) -> void:
	if not is_instance_valid(live_music): return
	# Stop the menu decoder before either the native or recorded game score
	# can enqueue its first mixer block.
	if is_instance_valid(menu_music): menu_music.finish_menu_session()
	live_music.live_enabled=live_music_enabled
	var genre: String=preload("res://scripts/music_genre_catalog.gd").resolve(environment_id,music_style)
	live_music.begin_session(environment_id,score_seed,{"genre":genre})
	if _live_score_active():
		_stop_music()
		_crossfade=1.0

func _restore_recorded_music() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or music_players.size()!=2: return
	if _menu_context(): return
	var requested_stream: AudioStream=_score_streams[_requested_music_set]
	# A missing/disabled backend can be reported during an ongoing world fade.
	# Let the recorded decks finish that fade and retire the outgoing decoder.
	if music_set==_requested_music_set and _deck_active(music_players[_active_deck]) and music_players[_active_deck].stream==requested_stream:
		return
	_stop_deck(1-_active_deck)
	music_set=_requested_music_set
	music_player=music_players[_active_deck]
	music_stream=_score_streams[music_set]
	music_player.stream=music_stream
	music_player.set_meta("score_id", music_set)
	_set_arrangement_mix(music_stream)
	music_player.volume_db=_recorded_score_level(music_set)
	if not _deck_active(music_player):
		var start_seconds := 0.0
		if is_instance_valid(live_music) and live_music.session_active:
			var state: Dictionary = live_music.get_music_state()
			start_seconds = float(state.mixed_samples)/float(state.mix_rate)
		music_player.play(fposmod(start_seconds,maxf(music_stream.get_length(),0.001)))
		music_player.stream_paused = live_music.clock.paused if is_instance_valid(live_music) and live_music.session_active else false
	_crossfade=1.0

func _tick_live_music(delta: float) -> void:
	if not is_instance_valid(live_music): return
	var valid_game: bool = is_instance_valid(game) and "started" in game and game.started
	var pause_score := false
	if valid_game and live_music.session_active:
		var boss := false
		if is_instance_valid(game.combat_events) and game.combat_events._boss!=null:
			boss=is_instance_valid(game.combat_events._boss.get_ref())
		live_music.update_game_state({"phase":game.rounds.phase,"wave":game.rounds.wave,"enemy_count":get_tree().get_nodes_in_group("enemies").size(),"core_ratio":game.core.hp/maxf(game.core.max_hp,1.0) if is_instance_valid(game.core) else 1.0,"boss":boss,"air_raid":is_instance_valid(game.air_raid_intro) and game.air_raid_intro.active,"running":game.rounds.running})
		var ending: bool = game.rounds.phase in ["victory","defeat"]
		pause_score = get_tree().paused and not ending
	live_music.set_paused(pause_score)
	for deck in music_players:
		# Menu and resolution music continue; a paused mission freezes both
		# recorded and native output together with its shared musical timeline.
		deck.stream_paused = pause_score
	live_music.tick(delta,music_volume>0.0 and not calibration_active)

func _dirty_rhythm_settings() -> void:
	_settings_dirty=true
	_save_delay=.35

func set_live_music_enabled(value: bool) -> void:
	live_music_enabled=value
	if is_instance_valid(live_music):
		live_music.set_live_enabled(value)
		if _live_score_active(): _stop_music();_crossfade=1.0
		else: _restore_recorded_music()
	_dirty_rhythm_settings()

func set_rhythm_motion_reduced(value: bool) -> void:
	rhythm_motion_reduced=value
	if is_instance_valid(live_music): live_music.set_rhythm_motion_reduced(value)
	_dirty_rhythm_settings()

func set_music_style(value: String) -> void:
	if not preload("res://scripts/music_genre_catalog.gd").valid_selection(value): return
	music_style=value
	# A shared piece keeps its tempo and genre until the next level starts.
	if is_instance_valid(live_music) and not (is_instance_valid(game) and "started" in game and game.started):
		live_music.set_music_style(value)
	_dirty_rhythm_settings()

func set_music_calibration(value: float) -> void:
	if not is_finite(value): return
	music_calibration_seconds=clampf(value,-.5,.5)
	if is_instance_valid(live_music): live_music.set_calibration_seconds(music_calibration_seconds)
	_dirty_rhythm_settings()

func set_dance_configuration(value: float,profiles: Dictionary) -> void:
	var catalog:=preload("res://scripts/worker_dance_catalog.gd")
	if not catalog.valid_intensity(value) or not catalog.valid_profiles(profiles): return
	dance_intensity=value
	dance_profiles=catalog.normalized_profiles(profiles)
	if is_instance_valid(live_music): live_music.set_dance_configuration(value,dance_profiles)
	_dirty_rhythm_settings()
