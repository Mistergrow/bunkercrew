extends SceneTree
## Actual normal scenario starts hear their new default native identities.
const Rave := preload("res://scripts/rave_music_catalog.gd")
const Menu := preload("res://scripts/menu_music_catalog.gd")
const Themes := preload("res://scripts/music_theme_catalog.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUT := "res://artifacts/music-beat-refresh/gameplay-verification.json"
var checks := 0
var failures := 0
var energies: Dictionary = {}
var fallback_energies: Dictionary = {}
var game: Node

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func wait(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + ceili(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline: await process_frame

func energy(capture: AudioEffectCapture) -> float:
	var buffer := capture.get_buffer(capture.get_frames_available())
	if buffer.is_empty(): return 0.0
	var sum := 0.0
	for sample in buffer:
		if not is_finite(sample.x) or not is_finite(sample.y): return NAN
		sum += float(sample.length_squared())
	return sum / float(buffer.size())

func new_game() -> Node:
	var result: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(result)
	current_scene = result
	result.audio.set_music_volume(1.0)
	result.audio.set_music_style("level_default")
	result.audio.set_live_music_enabled(true)
	return result

func decoder_id(player: AudioStreamPlayer) -> int:
	# A coroutine's chained temporary playback reference can remain live across
	# its later await. Read identity in a synchronous scope before teardown.
	return player.get_stream_playback().get_instance_id()

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args(): quit(2); return
	InputSetup.install()
	Menu.reset_rotation()
	game = new_game()
	await wait(0.15)
	check(game.audio.menu_music.playing and game.audio.menu_rhythm_frame().track_id == "nachtschicht", "A fresh actual launch still greets the player with the exact original Nachtschicht")
	var visited: Dictionary = {}
	for environment: String in Rave.ENVIRONMENT_TRACKS:
		var identifier: String = Rave.ENVIRONMENT_TRACKS[environment]
		var expected: Dictionary = Rave.track(identifier)
		check(Themes.theme(environment).bpm == expected.bpm and Themes.theme(environment).key == expected.theme.key, "Default native identity matches its assigned new score: " + environment)
		for genre in ["hip_hop", "schranz", "breakbeat"]:
			check(Themes.theme(environment, genre).key == Themes.THEMES[environment].key and Themes.theme(environment, genre).bpm == Themes.THEMES[environment].bpm, "Explicit " + genre + " preserves its original theme: " + environment)
		if visited.has(identifier): continue
		visited[identifier] = true
		var music_bus := AudioServer.get_bus_index("Music")
		var effect_index := AudioServer.get_bus_effect_count(music_bus)
		var capture := AudioEffectCapture.new()
		capture.buffer_length = 2.0
		AudioServer.add_bus_effect(music_bus, capture)
		game.start_scenario(1, {"environment":environment,"build_type":"bastion","position":"center"})
		game.rounds.running = false
		game.rounds.set_process(false)
		await wait(0.35)
		var actual: Node = game.audio.live_music
		check(game.started and actual.session_active and actual.native_active and actual.genre == "minimal_techno" and actual._theme.bpm == expected.bpm and actual._theme.motif == expected.theme.motif, "Normal default gameplay owns the new native score: " + identifier)
		check(not game.audio.menu_music.playing and game.audio.music_players.all(func(deck): return not deck.playing), "New live score owns exactly one Music source: " + identifier)
		var heard := energy(capture)
		energies[identifier] = heard
		check(is_finite(heard) and heard > 0.000001, "Actual native Music mixer produces finite audible PCM: " + identifier)
		game.audio.set_live_music_enabled(false)
		await wait(0.08)
		capture.clear_buffer()
		await wait(0.2)
		var recorded := energy(capture)
		fallback_energies[identifier] = recorded
		check(not actual.native_active and game.audio.music_set == identifier and game.audio.music_player.playing, "Disabling synthesis hears the matching new recording in the actual world: " + identifier)
		check(game.audio.music_stream.get_sync_stream(0).resource_path.ends_with(str(expected.calm_asset)) and game.audio.music_stream.get_sync_stream(1).resource_path.ends_with(str(expected.asset)), "The fallback pair preserves the same authored composition: " + identifier)
		check(is_finite(recorded) and recorded > 0.000001, "The actual fallback Music mixer produces finite audible PCM: " + identifier)
		AudioServer.remove_bus_effect(music_bus, effect_index)
		check(await Cleanup.free_scene(game, self), "Actual new native world score releases cleanly: " + identifier)
		game = new_game()
		await wait(0.08)
	check(visited.size() == 9, "All nine new gameplay compositions are selected and genuinely heard")
	check(await Cleanup.free_scene(game, self), "Last prepared menu releases cleanly")
	# Ordinary mission returns prove every piece and wrap across reloads.
	Menu.reset_rotation()
	for expected_id in ["kernimpuls", "nachtstrom", "schichtwechsel", "nachtschicht"]:
		game = new_game()
		await wait(0.1)
		game.start_scenario(1, {"environment":"ash_foundry","build_type":"bastion","position":"center"})
		game.rounds.running = false
		var old_id := game.get_instance_id()
		check(game.return_to_menu(), "The ordinary game returns to its menu without a profile write")
		while not is_instance_valid(current_scene) or current_scene.get_instance_id() == old_id: await process_frame
		game = current_scene
		var menu_bus := AudioServer.get_bus_index("Music")
		var menu_effect_index := AudioServer.get_bus_effect_count(menu_bus)
		var menu_capture := AudioEffectCapture.new()
		menu_capture.buffer_length = 2.0
		AudioServer.add_bus_effect(menu_bus, menu_capture)
		await wait(0.15)
		check(game.audio.menu_music.playing and game.audio.menu_rhythm_frame().track_id == expected_id, "An actual mission return chooses the next menu piece: " + expected_id)
		var menu_energy := energy(menu_capture)
		check(is_finite(menu_energy) and menu_energy > 0.000001, "The selected real menu piece produces finite audible PCM: " + expected_id)
		var current_decoder_id := decoder_id(game.audio.menu_music.player)
		game.hud.main_menu_panel.browse_environment(1)
		game.hud._toggle_audio()
		await wait(0.1)
		game.hud._close_audio()
		await wait(0.1)
		check(decoder_id(game.audio.menu_music.player) == current_decoder_id and game.audio.menu_rhythm_frame().track_id == expected_id, "Preview and real Options preserve the selected menu piece and decoder: " + expected_id)
		if expected_id in ["kernimpuls", "nachtstrom", "schichtwechsel"]:
			var duration: float = game.audio.menu_music.track_seconds
			game.audio.menu_music.player.seek(duration - 0.3)
			await wait(0.08)
			var loop_decoder := decoder_id(game.audio.menu_music.player)
			var previous: float = game.audio.menu_rhythm_frame().audible_seconds
			var continuous := true
			var deadline := Time.get_ticks_msec() + 700
			var heard_kicks: Dictionary = {}
			while Time.get_ticks_msec() < deadline:
				await process_frame
				var rhythm: Dictionary = game.audio.menu_rhythm_frame()
				continuous = continuous and float(rhythm.audible_seconds) >= previous
				previous = float(rhythm.audible_seconds)
				if rhythm.kick_pulse > (0.18 if expected_id == "kernimpuls" else 0.65): heard_kicks[float(rhythm.kick_timestamp)] = true
			check(previous > duration and continuous and decoder_id(game.audio.menu_music.player) == loop_decoder and heard_kicks.size() >= 1, "Actual decoder wraps with continuous time and its own genuine kick markers: " + expected_id)
		if expected_id == "kernimpuls":
			var authored: Dictionary = game.audio.menu_music._track
			check(authored.kick_samples.size() < Menu.BARS * 4, "The new intro uses its sparse authored kick pattern rather than fabricated four-on-the-floor markers")
			game.audio.menu_music.player.seek(game.audio.menu_music.track_seconds * 0.5)
			await wait(0.15)
			var sample_deadline := Time.get_ticks_msec() + 1200
			var actual_hits: Dictionary = {}
			var authored_only := true
			while Time.get_ticks_msec() < sample_deadline:
				await process_frame
				var rhythm: Dictionary = game.audio.menu_rhythm_frame()
				if rhythm.active and rhythm.kick_pulse > 0.65:
					var marker := roundi(fposmod(float(rhythm.kick_timestamp),game.audio.menu_music.track_seconds) * Menu.SAMPLE_RATE)
					authored_only = authored_only and marker in authored.kick_samples
					actual_hits[float(rhythm.kick_timestamp)] = true
			check(authored_only and actual_hits.size() >= 2, "The new menu drop publishes several real recorded kick markers on its own decoded transport")
		AudioServer.remove_bus_effect(menu_bus, menu_effect_index)
		check(await Cleanup.free_scene(game,self), "Rotated real menu decoder releases cleanly: " + expected_id)
	Menu.reset_rotation()
	game = new_game()
	await wait(0.1)
	game.start(1)
	game.rounds.running = false
	check(game.started and not is_instance_valid(game.scenario_bunker) and not game.audio.menu_music.playing and Menu.selected_track().id == "kernimpuls", "The actual classic bunker route advances the next menu composition exactly once")
	var classic_scene_id := game.get_instance_id()
	check(game.return_to_menu(), "The actual classic round can return to the ordinary menu")
	while not is_instance_valid(current_scene) or current_scene.get_instance_id() == classic_scene_id: await process_frame
	game = current_scene
	await wait(0.15)
	check(game.audio.menu_music.playing and game.audio.menu_rhythm_frame().track_id == "kernimpuls", "Returning from the actual classic bunker hears Kernimpuls")
	check(await Cleanup.free_scene(game, self), "Classic round and its rotated menu release all audio cleanly")
	DirAccess.make_dir_recursive_absolute("res://artifacts/music-beat-refresh")
	FileAccess.open(OUT, FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"heard_native_worlds":energies,"heard_recorded_worlds":fallback_energies,"menu_rotation":["nachtschicht","kernimpuls","nachtstrom","schichtwechsel","nachtschicht"],"classic_round_next_menu":"kernimpuls","normal_main_scene":true,"no_profile_save":true}, "\t"))
	print("RAVE MUSIC GAMEPLAY: %d/%d passed; nine genuinely heard native scores and actual menu rotation" % [checks - failures, checks])
	quit(1 if failures else 0)
