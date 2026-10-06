extends SceneTree
## Real spatial players and captured mixer samples, with prepared world exposure.
const AUDIO := preload("res://scripts/audio.gd")
const CLEANUP := preload("res://tests/scene_cleanup.gd")
const SETTINGS := "user://movement-audio-test.cfg"

class Phase extends Node:
	var phase := "build"

class Exposure extends Node:
	var exposure := 1.0

class Weather extends Node:
	var gust := 1.0
	func wind_strength() -> float:
		return gust

class Actor extends Node2D:
	var wetness: Node

class World extends Node2D:
	var started := true
	var camera: Camera2D
	var players: Array[Node2D] = []
	var weather: Node
	var rounds: Node

var checks := 0
var failures := 0
var game: World
var audio: Node
var movement: Node2D
var capture: AudioEffectCapture
var capture_index := -1
var sfx_bus := -1

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func latest_voice() -> AudioStreamPlayer2D:
	var latest: AudioStreamPlayer2D
	var serial := -1
	for voice: AudioStreamPlayer2D in movement.voices:
		if int(voice.get_meta("serial", 0)) > serial:
			latest = voice
			serial = int(voice.get_meta("serial", 0))
	return latest

func stop_steps() -> void:
	for voice: AudioStreamPlayer2D in movement.voices:
		voice.stop()

func active_steps() -> int:
	var count := 0
	for voice: AudioStreamPlayer2D in movement.voices:
		if voice.playing:
			count += 1
	return count

func step(kind: String, heavy := false, player := true, offset := Vector2.ZERO, weight := 1.0) -> bool:
	return audio.play_footstep(kind, game.camera.get_screen_center_position() + offset, weight, heavy, player)

func set_exposure(first: float, second: float) -> void:
	game.players[0].wetness.exposure = first
	game.players[1].wetness.exposure = second

func settle_wind() -> void:
	audio.acoustics.update(2.0)
	movement._wind_probe = 0.0
	movement._process(2.0)

func captured_step(offset: Vector2) -> Vector2:
	stop_steps()
	await create_timer(0.08).timeout
	capture.clear_buffer()
	step("metal", false, true, offset)
	await create_timer(0.15).timeout
	var frames := capture.get_buffer(capture.get_frames_available())
	var energy := Vector2.ZERO
	for sample: Vector2 in frames:
		energy += Vector2(sample.x * sample.x, sample.y * sample.y)
	return energy / maxf(1.0, frames.size())

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Use --no-profile-save, --audio-driver Dummy and an isolated XDG_DATA_HOME")
		quit(1)
		return
	root.size = Vector2i(1440, 900)
	root.audio_listener_enable_2d = true
	DirAccess.remove_absolute(SETTINGS)
	game = World.new()
	root.add_child(game)
	current_scene = game
	game.camera = Camera2D.new()
	game.camera.position = Vector2(720, 450)
	game.add_child(game.camera)
	game.camera.make_current()
	game.weather = Weather.new()
	game.add_child(game.weather)
	game.rounds = Phase.new()
	game.add_child(game.rounds)
	for index in 2:
		var actor := Actor.new()
		actor.position = Vector2(660 + index * 120, 450)
		actor.wetness = Exposure.new()
		actor.add_child(actor.wetness)
		game.add_child(actor)
		game.players.append(actor)
	audio = AUDIO.new()
	audio.settings_path = SETTINGS
	game.add_child(audio)
	audio.set_process(false)
	audio.set_music_volume(0.0)
	audio.set_sfx_volume(0.65)
	movement = audio.movement
	movement.set_process(false)
	await physics_frame
	await physics_frame
	game.camera.force_update_scroll()
	check(movement.process_mode == Node.PROCESS_MODE_PAUSABLE, "Movement controller pauses even though the music parent always processes")
	check(movement.voices.size() == 4 and movement.get_child_count() == 5, "Four spatial contact players and one wind player are allocated once")
	check(audio.voices.size() == 12 and audio.music_players.size() == 2, "Movement has a separate pool from weapon voices and score players")
	var streams_valid: bool = movement.step_streams.size() == 5
	for kind: String in movement.KINDS:
		streams_valid = streams_valid and movement.step_streams[kind].size() == 3
		for stream: AudioStream in movement.step_streams[kind]:
			streams_valid = streams_valid and stream is AudioStreamWAV and stream.mix_rate == 32000 and stream.get_length() >= 0.25
	check(streams_valid, "All fifteen real 32 kHz contact recordings are cached")
	var wind: AudioStreamOggVorbis = movement.wind_player.stream
	check(wind != null and wind.loop and absf(wind.get_length() - 16.0) < 0.00004, "Real stereo wind recording loops at exactly sixteen seconds")
	for kind: String in ["dry", "metal", "water", "ice"]:
		stop_steps()
		check(step(kind), "%s contact is accepted through the real Audio facade" % kind)
		var voice := latest_voice()
		check(voice.get_meta("kind") == kind and voice.stream in movement.step_streams[kind] and voice.global_position == game.camera.get_screen_center_position(), "%s selects its own recording at the world contact point" % kind)
		check(voice.bus == audio.acoustics.room_bus and AudioServer.get_bus_send(AudioServer.get_bus_index(voice.bus)) == "SFX" and voice.max_distance == 1150.0 and voice.attenuation > 0 and voice.panning_strength > 0, "%s voice uses spatial attenuation and panning through room acoustics into the effects bus" % kind)
	for kind: String in ["dry", "metal", "water", "ice"]:
		stop_steps()
		check(step(kind, true, false), "Heavy %s contact starts" % kind)
		var expected := "heavy" if kind in ["dry", "metal"] else kind
		check(latest_voice().get_meta("kind") == expected and latest_voice().stream in movement.step_streams[expected] and latest_voice().pitch_scale < 1.0, "Heavy %s preserves wet/frozen material while dry solid floors use machine weight" % kind)
	for kind: String in movement.KINDS:
		var previous: AudioStream = null
		var used: Dictionary = {}
		var no_repeat := true
		for index in 12:
			stop_steps()
			no_repeat = step(kind) and no_repeat
			var stream: AudioStream = latest_voice().stream
			no_repeat = no_repeat and stream != previous
			used[stream.get_instance_id()] = true
			previous = stream
		check(no_repeat and used.size() == 3, "%s uses all three variants without repeats across shuffled cycles" % kind)
	stop_steps()
	for index in 4:
		step("dry", false, true, Vector2(index * 10, 0))
	check(active_steps() == 4, "Four same-frame player contacts occupy four real spatial voices")
	var protected_streams: Array[AudioStream] = []
	for voice: AudioStreamPlayer2D in movement.voices:
		protected_streams.append(voice.stream)
	var rejected := true
	for index in 24:
		rejected = not step("heavy", true, false) and rejected
	var preserved := true
	for index in 4:
		preserved = preserved and movement.voices[index].stream == protected_streams[index] and movement.voices[index].get_meta("player")
	check(rejected and preserved, "An enemy crowd cannot replace four ongoing player contacts")
	stop_steps()
	for index in 4:
		step("heavy", true, false, Vector2(index * 10, 0))
	check(active_steps() == 4 and step("water", false, true), "A player can take a voice from a full enemy contact pool")
	var player_voice := latest_voice()
	var player_stream: AudioStream = player_voice.stream
	for index in 40:
		step("heavy", true, false)
	check(player_voice.stream == player_stream and player_voice.get_meta("player") and movement.voices.size() == 4, "Further crowds preserve the player's voice and never grow the pool")
	audio.cooldowns.clear()
	check(audio.play_sound("warning"), "A real warning can play beside foot contacts")
	var warning_stream: AudioStream = audio.voices[0].stream
	for index in 30:
		step("dry")
	check(audio.voices[0].playing and audio.voices[0].stream == warning_stream, "Footstep traffic never steals the separate warning voice")
	for voice: AudioStreamPlayer in audio.voices:
		voice.stop()
	stop_steps()
	var accepted_before: int = movement.steps_played
	check(not step("dry", false, true, Vector2(1151, 0)) and movement.steps_played == accepted_before, "Contacts beyond the listener range are rejected before taking a voice")
	check(not step("unknown") and not audio.play_footstep("dry", Vector2(NAN, 0)) and not step("dry", false, true, Vector2.ZERO, NAN), "Unknown material and non-finite contact inputs are rejected")
	sfx_bus = AudioServer.get_bus_index("SFX")
	capture = AudioEffectCapture.new()
	capture.buffer_length = 0.5
	capture_index = AudioServer.get_bus_effect_count(sfx_bus)
	AudioServer.add_bus_effect(sfx_bus, capture)
	var left := await captured_step(Vector2(-360, 0))
	var right := await captured_step(Vector2(360, 0))
	check(left.length_squared() > 0.000000000001 and right.length_squared() > 0.000000000001, "Dummy driver still produces captured real stereo contact samples")
	check(left.x > left.y * 1.25 and right.y > right.x * 1.25, "Captured contacts pan left and right with their actual world positions")
	print("MOVEMENT PAN ENERGY: left=", left, " right=", right)
	AudioServer.remove_bus_effect(sfx_bus, capture_index)
	capture = null
	stop_steps()
	set_exposure(0, 0)
	game.weather.gust = 1.0
	settle_wind()
	var interior: float = movement.wind_gain
	check(movement.wind_player.playing and interior > 0, "Sheltered actors retain a restrained continuous wind bed")
	set_exposure(1, 1)
	settle_wind()
	var exterior: float = movement.wind_gain
	check(exterior > interior * 4 and is_equal_approx(movement.wind_player.volume_db, linear_to_db(exterior)), "Open exposure raises wind gain substantially above the interior")
	set_exposure(0, 1)
	settle_wind()
	var mixed: float = movement.wind_gain
	check(mixed > interior and mixed < exterior, "Two players average indoor and outdoor exposure")
	set_exposure(1, 1)
	game.weather.gust = 0.0
	settle_wind()
	check(movement.wind_gain < exterior*.15 and movement.wind_gain > 0, "Calm outdoor air falls below fifteen percent of a gust without abrupt silence")
	game.weather.gust = 1.0
	movement._wind_probe = 0
	var quiet_gain: float = movement.wind_gain
	movement._process(0.01)
	check(movement.wind_gain > quiet_gain and movement.wind_gain < exterior, "Wind level approaches new conditions over time")
	settle_wind()
	check(step("metal"), "Contact is active before effects mute")
	audio.set_sfx_volume(0.0)
	check(active_steps() == 0 and not movement.wind_player.playing and AudioServer.is_bus_mute(sfx_bus), "F4 effects volume zero stops all footsteps and the wind immediately")
	check(not step("dry"), "Effects mute prevents new contacts")
	movement._process(0.2)
	check(not movement.wind_player.playing and movement.wind_gain == 0, "Muted wind processing cannot restart its playback")
	audio.set_sfx_volume(0.65)
	settle_wind()
	await create_timer(0.08).timeout
	check(movement.wind_player.playing and step("heavy"), "Unmuting allows the same cached wind and contact players to resume")
	movement.set_process(true)
	await physics_frame
	await process_frame
	paused = true
	await create_timer(0.06, true, false, true).timeout
	var paused_position: float = movement.wind_player.get_playback_position()
	var paused_gain: float = movement.wind_gain
	var paused_probe: float = movement._wind_probe
	var paused_contacts: Dictionary = {}
	for voice: AudioStreamPlayer2D in movement.voices:
		# Godot reports playing=false for a paused spatial voice; its native
		# playback handle remains active and must keep the same sample position.
		if voice.has_stream_playback():
			paused_contacts[voice.get_instance_id()] = voice.get_playback_position()
	await create_timer(0.12, true, false, true).timeout
	check(movement.wind_player.stream_paused and absf(movement.wind_player.get_playback_position() - paused_position) < 0.005, "Tree pause freezes actual wind playback position")
	check(movement.wind_gain == paused_gain and movement._wind_probe == paused_probe and not step("dry"), "Paused movement does not advance gain/probe time or accept contacts")
	var contact_paused := not paused_contacts.is_empty()
	for voice: AudioStreamPlayer2D in movement.voices:
		if paused_contacts.has(voice.get_instance_id()):
			contact_paused = contact_paused and voice.stream_paused and absf(voice.get_playback_position() - paused_contacts[voice.get_instance_id()]) < 0.005
	check(contact_paused, "Active spatial contact playback positions freeze with the world")
	paused = false
	await create_timer(0.10).timeout
	check(not movement.wind_player.stream_paused and movement.wind_player.get_playback_position() > paused_position, "Resuming the world advances the same wind playback again")
	movement.set_process(false)
	game.started = false
	settle_wind()
	check(movement.wind_gain == 0 and not movement.wind_player.playing, "Returning to a non-started world fades the wind out")
	check(await CLEANUP.free_scene(game, self), "Scene cleanup releases both spatial and non-spatial playback handles")
	DirAccess.remove_absolute(SETTINGS)
	print("MOVEMENT AUDIO: %d/%d checks passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
