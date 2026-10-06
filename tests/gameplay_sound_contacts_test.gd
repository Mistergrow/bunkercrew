extends SceneTree
## Actual running actor physics and sole contacts in the bunker. The recording
## captures the real SFX mixer; contacts are never invoked by this fixture.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var game
var checks := 0
var failures := 0
var capture: AudioEffectCapture
var capture_index := -1
var seen_contacts: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func wait_seconds(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		for voice: AudioStreamPlayer2D in game.audio.movement.voices:
			if voice.has_meta("serial"):
				seen_contacts[int(voice.get_meta("serial"))] = {
					"kind":str(voice.get_meta("kind")),
					"character":str(voice.get_meta("character_id")),
					"enemy":str(voice.get_meta("enemy_kind")),
				}
		await process_frame

func mixer_energy() -> float:
	var samples := capture.get_buffer(capture.get_frames_available())
	var result := 0.0
	for sample: Vector2 in samples:
		result += sample.length_squared()
	return result / maxf(1.0, samples.size())

func latest_upgrade() -> AudioStreamPlayer:
	var result: AudioStreamPlayer = null
	for voice: AudioStreamPlayer in game.audio.upgrade_audio.voices:
		if result == null or int(voice.get_meta("serial",0)) > int(result.get_meta("serial",0)):
			result = voice
	return result

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(2)
		return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.selected_characters.assign(["mara","branko","ivo","nora"])
	game.start_scenario(2, {"environment":"ash_foundry","build_type":"workshop","position":"center"})
	game.rounds.running = false
	game.audio.set_music_volume(0.0)
	game.audio.set_sfx_volume(1.0)
	await wait_seconds(0.8)
	game.audio.movement.wind_player.stream_paused = true
	var bus := AudioServer.get_bus_index("SFX")
	capture = AudioEffectCapture.new()
	capture.buffer_length = 8.0
	capture_index = AudioServer.get_bus_effect_count(bus)
	AudioServer.add_bus_effect(bus, capture)
	var original_steps: int = game.audio.movement.steps_played
	seen_contacts.clear()
	Input.action_press("p1_right")
	await wait_seconds(0.9)
	Input.action_release("p1_right")
	check(game.audio.movement.steps_played > original_steps, "Normal movement on actual bunker floors emits footsteps")
	check(seen_contacts.values().any(func(row): return row.character == "mara" and row.kind == "boot_standard_dry"), "Mara's real soles select her dry bunker-floor recording")
	check(mixer_energy() > 0.000001, "Bunker footsteps reach the actual SFX mixer as non-silent PCM")
	var stopped_steps: int = game.audio.movement.steps_played
	await wait_seconds(0.55)
	check(game.audio.movement.steps_played == stopped_steps, "Idle crew produce no phantom walking sounds")
	seen_contacts.clear()
	var branko_steps: int = game.audio.movement.steps_played
	var branko_start: Vector2 = game.players[1].global_position
	Input.action_press("p2_right")
	await wait_seconds(0.75)
	Input.action_release("p2_right")
	check(game.players[1].global_position.distance_to(branko_start) > 10.0 and game.audio.movement.steps_played > branko_steps, "Branko's actual movement emits new contacts")
	check(seen_contacts.values().any(func(row): return row.character == "branko" and row.kind == "boot_heavy_dry"), "Branko's normal movement uses his distinct heavier bunker boots")
	seen_contacts.clear()
	var enemy: Node = game._entity("enemy",Vector2(1150,430),{"kind":"runner","wave":1})
	await wait_seconds(1.5)
	check(seen_contacts.values().filter(func(row): return row.enemy == "runner").size() >= 2, "A live moving enemy emits repeated authored contacts through normal physics")
	enemy.queue_free()
	await wait_seconds(0.2)
	game.audio.set_sfx_volume(0.0)
	var muted_steps: int = game.audio.movement.steps_played
	Input.action_press("p1_left")
	await wait_seconds(0.45)
	Input.action_release("p1_left")
	check(game.audio.movement.steps_played == muted_steps, "Actual movement remains silent when SFX are muted")
	game.audio.set_sfx_volume(1.0)
	game.upgrades.add_points(100)
	paused = true
	for index in 3:
		var id: String = ["bunker_workshop","weapon_handling","boots"][index]
		capture.clear_buffer()
		var previous: int = game.audio.upgrade_audio.sounds_played
		check(game.upgrades.purchase(id), "Actual paused research accepts branch " + str(index))
		check(game.audio.upgrade_audio.sounds_played == previous + 1 and latest_upgrade().get_meta("kind") == preload("res://scripts/upgrade_audio.gd").KINDS[index], "Research selects its own branch cue while world audio is paused")
		await wait_seconds(0.3)
		check(mixer_energy() > 0.00001, "Paused research cue reaches the actual SFX mixer")
	var confirmed: int = game.audio.upgrade_audio.sounds_played
	check(not game.upgrades.purchase("boots") and game.audio.upgrade_audio.sounds_played == confirmed, "Rejected research emits no false success sound")
	AudioServer.remove_bus_effect(bus, capture_index)
	paused = false
	check(await Cleanup.free_scene(game,self), "World, footsteps and upgrade playback handles release cleanly")
	print("GAMEPLAY SOUND CONTACTS: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
