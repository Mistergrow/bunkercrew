class_name LiveMusic
extends Node
## Optional native synthesizer. Retained as an Audio child across level rebuilds.
## A missing extension requests the existing OGG score and leaves gameplay intact.

signal fallback_requested(environment: String)
signal session_started(environment: String, seed: int, native: bool)
signal beat(bar_index: int, beat_index: int, strength: float)
signal downbeat(bar_index: int, strength: float)
signal accent(track: int, strength: float)
signal bar(index: int)
signal phrase(index: int)

const Themes := preload("res://scripts/music_theme_catalog.gd")
const Genres := preload("res://scripts/music_genre_catalog.gd")
const Clock := preload("res://scripts/music_beat_clock.gd")
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const BASE_LEVEL_DB := -8.0

var clock := Clock.new()
var player: AudioStreamPlayer
var native_stream: AudioStream
var native_active := false
var session_active := false
var music_enabled := true
var live_enabled := true
var reduced_motion := false
var automatic_processing := false
var publish_shader_pulse := true
var dance_intensity := preload("res://scripts/audio_defaults.gd").DANCE_INTENSITY
var dance_profiles: Dictionary = Dance.defaults()
var calibration_seconds := 0.0
var environment_id := "ash_foundry"
var music_style := "level_default"
var genre := "minimal_techno"
var match_seed := 0
var theme_seed := Themes.seed_for("ash_foundry",0)
var intensity := 0
var pending_intensity := 0
var pending_bar := 0
var command_serial := 0
var interlude_kind := ""
var interlude_sample := -1
var _theme: Dictionary = {}
var _state: Dictionary = {}
var _frame := {"active":false,"bpm":100.0,"beat_period_seconds":0.6,"phase":0.0,"beat_pulse":0.0,"accent_pulse":0.0,"reduced_motion":false,"motion_gain":1.0,"bar":-1,"beat":-1,"audible_seconds":-1.0}
var _paused := false
var _remote_serial := -1
var _remote_session := false
var _last_boss := false
var _last_phase := ""
var _shader_pulse_available := false
var _retired_playbacks: Array[WeakRef] = []
var _fallback_samples := 0.0
var _fallback_mix_rate := 48000

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = AudioStreamPlayer.new()
	player.name = "LiveMusicPlayer"
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	player.volume_db = BASE_LEVEL_DB
	add_child(player)
	clock.beat.connect(func(a: int,b: int,s: float) -> void: beat.emit(a,b,s))
	clock.downbeat.connect(func(a: int,s: float) -> void: downbeat.emit(a,s))
	clock.accent.connect(func(t: int,s: float) -> void: accent.emit(t,s))
	clock.bar.connect(func(a: int) -> void: bar.emit(a))
	clock.phrase.connect(func(a: int) -> void: phrase.emit(a))
	_shader_pulse_available = ProjectSettings.has_setting("shader_globals/beat_pulse")
	set_process(automatic_processing)

func _process(delta: float) -> void:
	if automatic_processing:
		tick(delta, music_enabled)

func configure_environment(id: String, session_seed: int = 0) -> void:
	session_seed &= 0x7fffffff
	if session_active and id == environment_id and session_seed == match_seed:
		return
	environment_id = id if Themes.THEMES.has(id) else "ash_foundry"
	match_seed = session_seed
	theme_seed = Themes.seed_for(environment_id, match_seed)
	genre = Genres.resolve(environment_id,music_style)
	_theme = Genres.apply(Themes.theme(environment_id, genre),genre)

func begin_session(id: String, session_seed: int = 0, overrides: Dictionary = {}) -> bool:
	session_seed &= 0x7fffffff
	var requested_style := str(overrides.get("genre",music_style))
	var requested_genre := Genres.resolve(id,requested_style)
	var has_timeline_override := false
	for key in overrides:
		if key != "genre":
			has_timeline_override = true
	if session_active and id == environment_id and session_seed == match_seed and genre == requested_genre and not has_timeline_override:
		return native_active
	end_session()
	configure_environment(id, session_seed)
	genre = Genres.resolve(environment_id,requested_style)
	_theme = Genres.apply(Themes.theme(environment_id, genre),genre)
	if overrides.has("bpm") and (overrides.bpm is float or overrides.bpm is int) and is_finite(float(overrides.bpm)):
		_theme.bpm = clampf(float(overrides.bpm),60.0,160.0)
	session_active = true
	command_serial = 0
	_remote_serial = -1
	_remote_session = false
	_last_phase = ""
	_last_boss = false
	pending_intensity = clampi(int(overrides.get("intensity",0)),0,3)
	intensity = clampi(int(overrides.get("current_intensity",pending_intensity)),0,3)
	pending_bar = maxi(int(overrides.get("target_bar",0)),0)
	interlude_kind = ""
	interlude_sample = -1
	_fallback_mix_rate = maxi(int(AudioServer.get_mix_rate()),1)
	_fallback_samples = maxf(float(overrides.get("start_seconds",0.0)),0.0)*float(_fallback_mix_rate)
	clock.configure(float(_theme.bpm), 4, int(_theme.phrase_bars))
	clock.set_calibration(calibration_seconds)
	clock.set_paused(_paused)
	if live_enabled and "--disable-live-music" not in OS.get_cmdline_user_args() and ClassDB.class_exists("TesselStream"):
		var candidate: Object = ClassDB.instantiate("TesselStream")
		if candidate is AudioStream and _valid_backend(candidate):
			native_stream = candidate as AudioStream
			var settings := Themes.native_settings(environment_id,_theme,genre)
			settings.initial_intensity = intensity
			native_stream.call("set_theme", theme_seed, settings)
			if native_stream.has_method("request_intensity_at_bar"):
				native_stream.call("request_intensity_at_bar",pending_intensity,pending_bar)
			else:
				native_stream.call("set_intensity",pending_intensity)
			player.stream = native_stream
			var start_seconds := maxf(float(overrides.get("start_seconds",0.0)),0.0)
			player.play(start_seconds)
			player.stream_paused = _paused
			native_active = true
		elif candidate != null and not candidate is RefCounted:
			candidate.free()
	if not native_active:
		fallback_requested.emit(environment_id)
	_refresh_frame()
	session_started.emit(environment_id, theme_seed, native_active)
	return native_active

func _valid_backend(candidate: Object) -> bool:
	for method: String in ["set_theme","set_intensity","poll_events","mixed_samples","bpm","beats_per_bar","mix_rate"]:
		if not candidate.has_method(method):
			return false
	return true

func end_session() -> void:
	if is_instance_valid(player):
		if player.has_stream_playback():
			_retired_playbacks.append(weakref(player.get_stream_playback()))
		player.stop()
		player.stream = null
	native_stream = null
	native_active = false
	session_active = false
	_state.clear()
	_fallback_samples = 0.0
	clock.reset()
	_refresh_frame()
	_prune_retired_playbacks()

func _prune_retired_playbacks() -> void:
	for index in range(_retired_playbacks.size()-1,-1,-1):
		if _retired_playbacks[index].get_ref()==null:
			_retired_playbacks.remove_at(index)

func get_retired_music_playbacks() -> Array[WeakRef]:
	_prune_retired_playbacks()
	return _retired_playbacks.duplicate()

func set_music_enabled(value: bool) -> void:
	music_enabled = value
	# The mixer continues while muted so deterministic arrangement does not drift.
	if not value:
		_frame.active = false
		_frame.beat_pulse = 0.0
		_frame.accent_pulse = 0.0
		_frame.kick_timestamp = -INF
		_frame.kick_strength = 0.0
		_write_shader_pulse(0.0)

func set_live_enabled(value: bool) -> void:
	if live_enabled == value:
		return
	live_enabled = value
	if session_active:
		var id := environment_id
		var session_seed := match_seed
		var remote := _remote_session
		var serial := _remote_serial
		var state := get_music_state()
		begin_session(id,session_seed,{"genre":genre,"intensity":pending_intensity,"current_intensity":state.current_intensity,"target_bar":pending_bar,"start_seconds":float(state.mixed_samples)/float(state.mix_rate)})
		_remote_session = remote
		_remote_serial = serial
		command_serial = int(state.command_serial)
		interlude_kind = str(state.interlude)
		interlude_sample = int(state.interlude_sample)
		if native_active and interlude_sample > _timeline_samples() and native_stream.has_method("request_interlude"):
			var sample := int(float(interlude_sample)*float(_timeline_mix_rate())/float(state.mix_rate))
			native_stream.call("request_interlude",interlude_kind,sample)

func set_music_style(value: String) -> void:
	if not Genres.valid_style(value) or music_style == value:
		return
	music_style = value
	# Guests follow the host's score. Their preference applies to their next
	# locally controlled session, without replacing a received musical command.
	if session_active and not _remote_session:
		begin_session(environment_id,match_seed,{"genre":value})
	elif not session_active:
		genre = Genres.resolve(environment_id,music_style)
		_theme = Genres.apply(Themes.theme(environment_id, genre),genre)

func set_paused(value: bool) -> void:
	_paused = value
	clock.set_paused(value)
	if is_instance_valid(player):
		player.stream_paused = value
	if value:
		_refresh_frame()

func set_calibration_seconds(value: float) -> void:
	if not is_finite(value):
		return
	calibration_seconds = clampf(value,-0.5,0.5)
	clock.set_calibration(calibration_seconds)

func set_rhythm_motion_reduced(value: bool) -> void:
	reduced_motion = value
	_refresh_frame()

func set_dance_configuration(value: float, profiles: Dictionary = {}) -> void:
	if is_finite(value):
		dance_intensity = clampf(value,0.0,1.5)
	var normalized: Dictionary = {}
	var styles: Array = Dance.STYLES
	for id in profiles:
		if normalized.size() >= 16:
			break
		if not id is String or id.length() > 48 or not profiles[id] is Dictionary:
			continue
		var entry: Dictionary = profiles[id]
		var gain := float(entry.get("intensity",1.0)) if (entry.get("intensity",1.0) is float or entry.get("intensity",1.0) is int) else 1.0
		if not is_finite(gain):
			gain = 1.0
		var style := str(entry.get("style","character_default"))
		normalized[id] = {"style":style if style in styles else "character_default","intensity":clampf(gain,0.0,1.5)}
	dance_profiles = normalized
	_refresh_frame()

func start_preview(id: String, preview_seed: int, tempo: float = -1.0, stage: int = 0, style: String = "level_default") -> bool:
	end_session()
	var overrides := {"bpm":tempo} if tempo > 0.0 and is_finite(tempo) else {}
	overrides.intensity=clampi(stage,0,3)
	overrides.target_bar=0
	overrides.genre=style
	return begin_session(id,preview_seed,overrides)

func set_preview_intensity(stage: int) -> void:
	# The lab compares the same opening in different arrangements. Restart its
	# isolated preview with the chosen bank already selected, instead of waiting
	# up to sixteen bars for the next in-game phrase boundary.
	if session_active:
		begin_session(environment_id,match_seed,{"bpm":float(_theme.bpm),"intensity":clampi(stage,0,3),"target_bar":0,"genre":genre})
	else:
		pending_intensity=clampi(stage,0,3)

func set_mix_level_db(value: float) -> void:
	if is_instance_valid(player) and is_finite(value):
		player.volume_db = clampf(value, -80.0, 0.0)

func update_game_state(state: Dictionary) -> void:
	_state = state.duplicate()
	if not session_active or _remote_session:
		return
	var desired := Themes.intensity_for(state)
	if desired != pending_intensity:
		_schedule_intensity(desired)
	var has_boss := bool(state.get("boss",false))
	var phase_name := str(state.get("phase","build"))
	if has_boss and not _last_boss:
		request_interlude("boss")
	if phase_name != _last_phase and phase_name in ["victory","defeat"]:
		request_interlude(phase_name)
	_last_boss = has_boss
	_last_phase = phase_name

func _mixed_bar() -> int:
	var samples := _timeline_samples()
	var rate := _timeline_mix_rate()
	return int(floor(float(samples)/float(rate)*float(_theme.bpm)/240.0))

func _timeline_samples() -> int:
	if native_active:
		# Native play(start_seconds) is queued on the mixer. A freshly restored
		# paused player can still report zero until its first callback arrives.
		return maxi(int(native_stream.call("mixed_samples")),int(_fallback_samples))
	return int(_fallback_samples)

func _timeline_mix_rate() -> int:
	return maxi(int(native_stream.call("mix_rate")),1) if native_active else _fallback_mix_rate

func _schedule_intensity(value: int) -> void:
	pending_intensity = clampi(value,0,3)
	var length := int(_theme.get("phrase_bars",8))
	# Complete phrases count as whole indices; choose the following phrase.
	pending_bar = (floori(float(_mixed_bar())/float(length))+1)*length
	command_serial += 1
	if native_active:
		if native_stream.has_method("request_intensity_at_bar"):
			native_stream.call("request_intensity_at_bar",pending_intensity,pending_bar)
		else:
			native_stream.call("set_intensity",pending_intensity)

func request_interlude(kind: String) -> void:
	if not kind in ["boss","victory","defeat","air_raid"] or not session_active:
		return
	interlude_kind = kind
	var rate := _timeline_mix_rate()
	var samples := _timeline_samples()
	interlude_sample = Clock.next_beat_after_sample(float(samples),rate,float(_theme.bpm))
	command_serial += 1
	if native_active and native_stream.has_method("request_interlude"):
		native_stream.call("request_interlude",kind,interlude_sample)

func tick(delta: float, enabled: bool = true) -> void:
	_prune_retired_playbacks()
	music_enabled = enabled
	if session_active and not native_active:
		# Local recording fallback does not stop the shared musical arrangement.
		# Keep only its position: recordings never fabricate native beat events.
		if not _paused and is_finite(delta) and delta > 0.0:
			_fallback_samples += delta*float(_fallback_mix_rate)
		if _mixed_bar() >= pending_bar:
			intensity = pending_intensity
	if not session_active or not native_active or not is_instance_valid(player) or not player.playing:
		clock.active = false
		clock.kick_pulse = 0.0
		clock.accent_pulse = 0.0
		_refresh_frame()
		return
	var events: Array = native_stream.call("poll_events",Clock.MAX_EVENTS_PER_FRAME)
	var mixed := 0
	var since_mix := 0.0
	for attempt in 3:
		var mix_before := AudioServer.get_time_since_last_mix()
		mixed = int(native_stream.call("mixed_samples"))
		since_mix = maxf(AudioServer.get_time_since_last_mix(),0.0)
		if since_mix>=mix_before: break
	clock.advance(mixed,int(native_stream.call("mix_rate")),since_mix,AudioServer.get_output_latency(),events,enabled and not _paused)
	if native_stream.has_method("current_intensity"):
		intensity = clampi(int(native_stream.call("current_intensity")),0,3)
	elif _mixed_bar() >= pending_bar:
		intensity = pending_intensity
	_refresh_frame()

func _refresh_frame() -> void:
	_frame = clock.frame()
	_frame.active = bool(_frame.active) and session_active and native_active and music_enabled and not _paused
	if not _frame.active:
		_frame.beat_pulse = 0.0
		_frame.accent_pulse = 0.0
		_frame.kick_timestamp = -INF
		_frame.kick_strength = 0.0
	_frame.reduced_motion = reduced_motion
	_frame.motion_gain = 0.22 if reduced_motion else 1.0
	_frame.dance_intensity = dance_intensity
	_frame.dance_profiles = dance_profiles
	_frame.intensity = intensity
	_frame.genre = genre
	var phrase_index := floori(float(maxi(clock.bar_index,0))/float(_theme.get("phrase_bars",8)))
	_frame.section = Themes.section_for(_state,phrase_index)
	_write_shader_pulse(float(_frame.beat_pulse)*float(_frame.motion_gain))

func _write_shader_pulse(value: float) -> void:
	if publish_shader_pulse and _shader_pulse_available:
		RenderingServer.global_shader_parameter_set("beat_pulse",value)

func rhythm_frame() -> Dictionary:
	return _frame

func get_music_state() -> Dictionary:
	var current := int(native_stream.call("current_intensity")) if native_active and native_stream.has_method("current_intensity") else intensity
	return {"version":Themes.VERSION,"environment":environment_id,"genre":genre,"match_seed":match_seed,"seed":theme_seed,"active":session_active,"intensity":pending_intensity,"current_intensity":current,"target_bar":pending_bar,"command_serial":command_serial,"interlude":interlude_kind,"interlude_sample":interlude_sample,"mixed_samples":_timeline_samples(),"mix_rate":_timeline_mix_rate()}

func apply_music_state(state: Dictionary) -> void:
	if not valid_music_state(state):
		return
	if not bool(state.get("active",false)):
		if session_active:
			end_session()
		return
	var id := str(state.get("environment","ash_foundry"))
	var remote_seed := int(state.get("match_seed",0))
	var remote_genre := Genres.resolve(id,str(state.get("genre","level_default")))
	var new_session := not session_active or id != environment_id or remote_seed != match_seed or remote_genre != genre
	if new_session or not _remote_session:
		# AudioStreamPlayer starts asynchronously on the mixer. A seek issued
		# immediately after play() can be overwritten by its pending _start(0).
		# Pass the initial timeline through the native playback's start position.
		var remote_rate := maxi(int(state.get("mix_rate",48000)),1)
		begin_session(id,remote_seed,{"start_seconds":float(state.get("mixed_samples",0))/float(remote_rate),"intensity":state.intensity,"current_intensity":state.get("current_intensity",state.intensity),"target_bar":state.target_bar,"genre":remote_genre})
	_remote_session = true
	var serial := int(state.get("command_serial",0))
	if serial <= _remote_serial:
		return
	_remote_serial = serial
	command_serial = serial
	pending_intensity = clampi(int(state.get("intensity",0)),0,3)
	pending_bar = maxi(int(state.get("target_bar",0)),0)
	if native_active:
		if native_stream.has_method("request_intensity_at_bar"):
			native_stream.call("request_intensity_at_bar",pending_intensity,pending_bar)
		else:
			native_stream.call("set_intensity",pending_intensity)
	var next_interlude := str(state.get("interlude",""))
	var next_sample := int(state.get("interlude_sample",-1))
	if next_sample >= 0 and (next_interlude != interlude_kind or next_sample != interlude_sample):
		interlude_kind = next_interlude
		interlude_sample = next_sample
		if native_active and native_stream.has_method("request_interlude") and next_sample>int(state.get("mixed_samples",0)):
			var local_rate := int(native_stream.call("mix_rate"))
			var remote_rate := maxi(int(state.get("mix_rate",local_rate)),1)
			native_stream.call("request_interlude",interlude_kind,int(float(next_sample)*float(local_rate)/float(remote_rate)))

func native_metadata() -> Dictionary:
	if native_active and native_stream.has_method("metadata"):
		return native_stream.call("metadata")
	return {"available":false,"fallback":"ogg","theme_seed":theme_seed}

static func valid_music_state(state: Dictionary) -> bool:
	# Optional network envelope: primitive fields only, with bounded identities,
	# counters and times. Device volume/calibration/dance choices stay local.
	if state.size() > 16 or not state.get("environment") is String or not Themes.THEMES.has(state.environment):
		return false
	var allowed := ["version","environment","genre","match_seed","seed","active","intensity","current_intensity","target_bar","command_serial","interlude","interlude_sample","mixed_samples","mix_rate"]
	for key in state:
		if not key is String or key not in allowed:
			return false
	if not state.get("active") is bool or not state.get("interlude","") is String:
		return false
	if state.has("genre") and (not state.genre is String or not state.genre in Genres.GENRES):
		return false
	if not str(state.get("interlude","")) in ["","boss","victory","defeat","air_raid"]:
		return false
	var ranges := {"version":Vector2i(1,1),"match_seed":Vector2i(0,2147483647),"seed":Vector2i(1,2147483647),"intensity":Vector2i(0,3),"target_bar":Vector2i(0,10000000),"command_serial":Vector2i(0,2147483647),"mix_rate":Vector2i(8000,192000)}
	if state.has("current_intensity"):
		ranges.current_intensity=Vector2i(0,3)
	for key: String in ranges:
		var value: Variant = state.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value)!=floorf(float(value)) or float(value)<ranges[key].x or float(value)>ranges[key].y:
			return false
	for key: String in ["mixed_samples","interlude_sample"]:
		var value: Variant = state.get(key,-1)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value)!=floorf(float(value)) or float(value)<(-1.0 if key=="interlude_sample" else 0.0) or float(value)>34560000000.0:
			return false
	return int(state.seed)==Themes.seed_for(str(state.environment),int(state.match_seed))
