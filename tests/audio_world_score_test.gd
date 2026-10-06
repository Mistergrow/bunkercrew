extends SceneTree
## Real cached streams, playback transitions and adversarial voice contention.
const AUDIO := preload("res://scripts/audio.gd")
const CLEANUP := preload("res://tests/scene_cleanup.gd")
const SETTINGS := "user://audio-world-score-test.cfg"

class Phase extends Node:
	var phase := "build"

class TestGame extends Node:
	var started := true
	var rounds: Node

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func wait_for_music_progress(player: AudioStreamPlayer, position: float) -> void:
	# Dummy output publishes 4096-frame blocks. A fixed 120 ms wait can miss
	# the next callback under load even while playback remains healthy.
	var deadline := Time.get_ticks_msec()+1000
	while player.get_playback_position()<=position and Time.get_ticks_msec()<deadline:
		await create_timer(.008,true,false,true).timeout

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Use --no-profile-save and an isolated XDG_DATA_HOME")
		quit(1)
		return
	DirAccess.remove_absolute(SETTINGS)
	var game := TestGame.new()
	root.add_child(game)
	game.rounds = Phase.new()
	game.add_child(game.rounds)
	var audio := AUDIO.new()
	audio.settings_path = SETTINGS
	game.add_child(audio)
	audio.set_process(false)
	await create_timer(0.12).timeout
	check(audio.music_players.size() == 2 and audio.voices.size() == 12, "Score changes reuse two players and a fixed twelve-voice effect pool")
	var score_ids: Dictionary = {}
	check(audio._score_streams.size() == 13, "Four legacy and nine original rave score pairs are cached before gameplay")
	for score_id: String in audio._score_streams:
		var score: AudioStreamSynchronized = audio._score_streams[score_id]
		score_ids[score_id] = score.get_instance_id()
		var calm: AudioStreamOggVorbis = score.get_sync_stream(0)
		var combat: AudioStreamOggVorbis = score.get_sync_stream(1)
		var expected_seconds := 48.0 if score_id in ["base", "foundry", "tidal", "frost"] else float(preload("res://scripts/rave_music_catalog.gd").track(score_id).seconds)
		check(calm != combat and calm.loop and combat.loop and absf(calm.get_length() - combat.get_length()) < 0.00004 and absf(calm.get_length() - expected_seconds) < 0.00004, "%s arrangements have a shared sample-length loop and one synchronized playback clock" % score_id)
	var expected_sets := {"sector07":"unterstrom", "ash_foundry":"glutkern", "basalt_quarry":"basalttakt", "overgrown_steelworks":"wurzelstrom", "iron_canyon":"eisenhall", "abandoned_harbor":"hafennebel", "flooded_power_station":"tiefenpuls", "frozen_rail_yard":"frostsignal", "mountain_pass":"hoehenlicht"}
	for environment_id: String in expected_sets:
		check(AUDIO.Catalog.score_for_environment(environment_id) == expected_sets[environment_id], "%s selects its authored score" % environment_id)
	check(AUDIO.Catalog.score_for_environment("unknown") == "base", "Unknown environments keep the original score")
	var original_player := audio.music_player
	audio.set_environment("flooded_power_station")
	check(audio.music_set == "tiefenpuls" and audio.music_player != original_player and original_player.playing and audio.music_player.playing, "World selection overlaps the old and new scores without stopping the original")
	check(absf(original_player.get_playback_position() / original_player.stream.get_length() - audio.music_player.get_playback_position() / audio.music_player.stream.get_length()) < 0.003, "Incoming score starts at the corresponding musical cycle position")
	audio._process(0.6)
	check(original_player.volume_db > audio.music_player.volume_db - 7.0 and audio.music_player.volume_db > -40, "The incoming score fades in over several frames with its measured source normalization")
	audio._process(0.6)
	check(absf(original_player.volume_db - audio.music_player.volume_db + 7.0) < 0.01 and absf(pow(db_to_linear(original_player.volume_db - audio._score_level), 2) + pow(db_to_linear(audio.music_player.volume_db - audio._score_level - 7.0), 2) - 1.0) < 0.001, "Midpoint world crossfade has equal power after accounting for recorded source loudness")
	audio._process(1.2)
	check(not original_player.playing and original_player.stream == null and audio.music_player.playing, "Completed world fade stops and releases the outgoing decoder")
	var tidal_player := audio.music_player
	var tidal_stream := audio.music_stream
	var tidal_position := tidal_player.get_playback_position()
	audio.set_environment("storm_dam")
	check(audio.music_player == tidal_player and audio.music_stream == tidal_stream and tidal_player.get_playback_position() >= tidal_position, "Changing between worlds with the same score preserves playback")
	game.rounds.phase = "attack"
	audio._process(0.5)
	check(audio.music_blend > 0 and audio.music_blend < 1 and audio.music_player == tidal_player, "Combat adds its synchronized arrangement without replacing the player")
	audio._process(3.0)
	check(audio.music_blend == 1 and audio.music_stream.get_sync_stream_volume(0) < -70, "Combat reaches its full arrangement with the shared phrase clock")
	audio.set_environment("ash_foundry")
	audio._process(0.4)
	audio.set_environment("frozen_rail_yard")
	audio.set_environment("sector07")
	check(audio.music_set == "glutkern" and audio.music_player.playing and tidal_player.playing, "Rapid selection keeps the ongoing crossfade intact")
	audio._process(2.0)
	check(audio.music_set == "unterstrom", "After the current fade only the latest queued score is selected")
	audio._process(2.4)
	var playing_scores := 0
	for player in audio.music_players:
		if player.playing: playing_scores += 1
	check(playing_scores == 1 and audio.get_child_count() == audio.MAX_VOICES + 6 and audio.movement.get_parent() == audio and audio.movement.voices.size() == 4 and audio.upgrade_audio.voices.size() == 2 and audio.live_music.get_parent() == audio and audio.menu_music.get_parent() == audio and not audio.menu_music.playing, "Repeated world changes preserve one active world score and bounded movement/research/live/menu controllers without creating players")
	for score_id: String in audio._score_streams:
		check(audio._score_streams[score_id].get_instance_id() == score_ids[score_id], "%s transition reuses the cached resource" % score_id)
	# The main menu pauses world simulation, but must keep its authored music level.
	game.started = false
	paused = true
	var menu_position := audio.music_player.get_playback_position()
	audio._process(1.0)
	await create_timer(0.12, true, false, true).timeout
	await wait_for_music_progress(audio.music_player,menu_position)
	check(audio.music_player.playing and audio.music_player.get_playback_position() > menu_position and is_equal_approx(audio.music_player.volume_db, 0.0), "A paused fixture keeps the normalized recorded score level and its continuous music clock")
	game.started = true
	var pause_position := audio.music_player.get_playback_position()
	audio._process(1.0)
	await create_timer(0.12, true, false, true).timeout
	await wait_for_music_progress(audio.music_player,pause_position)
	check(audio.music_player.playing and audio.music_player.get_playback_position() > pause_position and audio.music_player.volume_db <= -4, "Pause ducks the normalized recorded score while preserving its continuous music clock")
	paused = false
	# Fill the real voice pool before testing priority arbitration.
	for index in audio.MAX_VOICES:
		audio.cooldowns.clear()
		audio.play_sound("impact_stone")
	audio.cooldowns.clear()
	check(audio.play_sound("warning"), "Warning takes a voice even when mining fills the pool")
	var warning_voice: AudioStreamPlayer
	for voice in audio.voices:
		if voice.get_meta("kind", "") == "warning": warning_voice = voice
	var warning_stream := warning_voice.stream
	for index in 60:
		audio.cooldowns.clear()
		audio.play_sound("impact_metal")
	check(warning_voice.playing and warning_voice.stream == warning_stream and warning_voice.get_meta("kind") == "warning", "Repeated low-priority actions never steal an active warning")
	for index in audio.MAX_VOICES:
		audio.cooldowns.clear()
		audio.play_sound("warning")
	audio.cooldowns.clear()
	check(not audio.play_sound("mine") and not audio.cooldowns.has("mine"), "A rejected low-priority sound does not consume a voice or its cooldown")
	for kind: String in ["shotgun", "cannon", "arc", "impact_metal", "impact_stone", "impact_wood", "glass_break"]:
		var previous: AudioStream = null
		var played: Dictionary = {}
		var non_repeating := true
		for index in 12:
			for voice in audio.voices: voice.stop()
			audio.cooldowns.clear()
			non_repeating = audio.play_sound(kind) and non_repeating
			var current: AudioStream = audio.voices[0].stream
			non_repeating = non_repeating and current != previous
			played[current.get_instance_id()] = true
			previous = current
		check(non_repeating and played.size() == 3, "%s uses all three real samples without immediate repeats across bag boundaries" % kind)
	for voice in audio.voices: voice.stop()
	audio.cooldowns.clear()
	check(audio.play_sound("mine_metal") and not audio.play_sound("impact_metal"), "Material aliases share their canonical cooldown")
	check(audio.streams.glass_break != audio.streams.hit, "Glass destruction has its own recording instead of a generic hit")
	audio.calibration_active=true
	audio._stop_music()
	audio._restore_recorded_music()
	check(audio.music_player.playing and audio.music_player.volume_db<=-80.0,"Restoring a recorded fallback during calibration keeps the new decoder silent")
	audio.calibration_active=false
	audio._process(0.0)
	check(audio.music_player.volume_db>-40.0,"Releasing calibration restores the existing recorded fallback without restarting it")
	audio.set_environment("frozen_rail_yard")
	audio._process(0.5)
	audio.calibration_active=true
	audio._process(0.0)
	check(audio.music_players[0].volume_db<=-80.0 and audio.music_players[1].volume_db<=-80.0,"Calibration suspends both recorded decks during an in-progress world crossfade")
	audio.calibration_active=false
	audio._process(0.0)
	check(audio.music_players[0].volume_db>-40.0 and audio.music_players[1].volume_db>-40.0,"Closing calibration restores both crossfade levels at their current musical positions")
	audio.set_music_volume(0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")) and audio.music_players[0].playing and audio.music_players[1].playing, "Music mute silences both overlapping decks without resetting their positions")
	audio.set_sfx_volume(0)
	var silent_voices := true
	for voice in audio.voices: silent_voices = silent_voices and not voice.playing
	check(silent_voices and not audio.play_sound("cannon"), "Effects mute immediately stops every voice and prevents new attacks")
	check(await CLEANUP.free_scene(game, self), "Scene teardown during a crossfade releases both synchronized playback handles")
	DirAccess.remove_absolute(SETTINGS)
	print("AUDIO WORLD SCORE: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
