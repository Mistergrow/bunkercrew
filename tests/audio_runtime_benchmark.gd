extends SceneTree
## Measures only the main-thread audio controller, not native decoder/mixer time.
const AUDIO := preload("res://scripts/audio.gd")
const OUTPUT := "res://artifacts/audio-refresh/runtime-metrics.json"

class Phase extends Node:
	var phase := "build"

class TestGame extends Node:
	var started := true
	var rounds: Node

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Use --no-profile-save and an isolated XDG_DATA_HOME")
		quit(1)
		return
	var game := TestGame.new()
	root.add_child(game)
	game.rounds = Phase.new()
	game.add_child(game.rounds)
	var audio := AUDIO.new()
	audio.settings_path = "user://audio-runtime-benchmark.cfg"
	var started_us := Time.get_ticks_usec()
	game.add_child(audio)
	var initialization_ms := (Time.get_ticks_usec() - started_us) / 1000.0
	audio.set_process(false)
	await create_timer(0.1).timeout
	for index in 1000:
		audio._process(1.0 / 60.0)
	var batches: Array[float] = []
	for batch in 9:
		started_us = Time.get_ticks_usec()
		for index in 5000:
			audio._process(1.0 / 60.0)
		batches.append((Time.get_ticks_usec() - started_us) / 5000.0)
	batches.sort()
	var transitions: Array[float] = []
	var worlds := ["ash_foundry", "abandoned_harbor", "frozen_rail_yard", "sector07"]
	for index in 16:
		started_us = Time.get_ticks_usec()
		audio.set_environment(worlds[index % worlds.size()])
		transitions.append((Time.get_ticks_usec() - started_us) / 1000.0)
		audio._process(2.4)
		await create_timer(0.03).timeout
	transitions.sort()
	var result := {
		"fixture":"Headless main-thread controller; 9 x 5000 stable-phase callbacks after 1000 warmup calls; 16 cached world transitions. Native audio decoder/mixer CPU is not measured.",
		"initialization_ms":initialization_ms,
		"steady_callback_median_us":batches[4], "steady_callback_batches_us":batches,
		"cached_transition_median_ms":(transitions[7] + transitions[8]) * 0.5,
		"cached_transition_max_ms":transitions.back(),
		"cached_music_sets":audio._score_streams.size(),
		"effect_samples":50, "effect_voices":audio.voices.size(), "score_players":audio.music_players.size(),
	}
	var output := FileAccess.open(OUTPUT, FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t") + "\n")
	output.close()
	print("AUDIO RUNTIME METRICS: ", JSON.stringify(result))
	var released: bool = await preload("res://tests/scene_cleanup.gd").free_scene(game, self)
	quit(0 if released else 1)
