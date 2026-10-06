extends SceneTree
## Actual station and native music: only its painted drum bobs to heard kicks.
## --capture uses an actual rendered game view and can be recorded with --write-movie.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/menu-rave/mixer"
var checks := 0
var failures := 0
var game: Node
var mixer: ProductionStation
var animation: Node2D
var capture_enabled := false
var captures: Array[String] = []
var maximum_bob := -INF
var minimum_bob := INF
var audible_kicks: Dictionary = {}
var baseline_position := Vector2.ZERO
var baseline_anchor := Vector2.ZERO
var transform_unchanged := true

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func sample() -> void:
	await process_frame
	var offset: float = animation.rhythm_offset.y
	maximum_bob = maxf(maximum_bob, offset)
	minimum_bob = minf(minimum_bob, offset)
	transform_unchanged = transform_unchanged and mixer.position == baseline_position and mixer.interaction_point() == baseline_anchor
	var frame: Dictionary = game.audio.live_music.rhythm_frame()
	if frame.active and float(frame.kick_strength) > 0.3:
		audible_kicks[float(frame.kick_timestamp)] = true

func wait_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + ceili(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await sample()

func capture(label: String) -> void:
	if not capture_enabled: return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT + "/" + label + ".png") == OK, "Actual mixer game capture: " + label)
	captures.append(label + ".png")

func _run() -> void:
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args() or (capture_enabled and DisplayServer.get_name() == "headless"):
		push_error("Use --no-profile-save --no-upnp; --capture requires a graphical display.")
		quit(2)
		return
	InputSetup.install()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1280, 720)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1, {"environment": "ash_foundry", "build_type": "bastion", "position": "left"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.dialogue.reset()
	game.audio.live_music.begin_session("ash_foundry", 81731, {"genre": "minimal_techno", "intensity": 2, "current_intensity": 2})
	mixer = get_nodes_in_group("stations").filter(func(station): return station.game == game and station.kind == "mixer")[0]
	animation = mixer.get_node("MixerAnimation")
	baseline_position = mixer.position
	baseline_anchor = mixer.interaction_point()
	game.player_camera.set_process(false)
	game.camera.position = mixer.position + Vector2(5, -58)
	game.camera.zoom = Vector2.ONE * 4.0
	game.camera.force_update_scroll()
	game.hud.canvas.visible = false
	game.players[0].position = mixer.position + Vector2(76, 0)
	var original_binder := mixer.binder
	mixer.input_amount = mixer.input_cost("sand")
	mixer._process(0.0)
	check(game.started and not paused and game.audio.live_music.native_active, "Ordinary game owns actual native groove audio, with automatic wave spawning held")
	check(mixer.working and mixer.binder == original_binder - 1 and mixer.input_amount == 0, "The actual station starts one paid concrete batch")
	var held := 0
	var raised := 0
	# MovieWriter can render slower than wall time. Observe several actual heard
	# kicks rather than treating a wall timer as proof of an audible bar.
	var sample_deadline := Time.get_ticks_msec() + 10000
	while (audible_kicks.size() < 4 or held == 0 or raised == 0) and Time.get_ticks_msec() < sample_deadline:
		await sample()
		if float(animation.rhythm_offset.y) > 0.7 and held == 0:
			await capture("01-kick-settle")
			held += 1
		if float(animation.rhythm_offset.y) < -0.25 and raised == 0:
			await capture("02-kick-rebound")
			raised += 1
	check(audible_kicks.size() >= 3 and held > 0 and raised > 0, "Several genuinely heard bass drums settle and rebound the painted drum")
	check(maximum_bob > 0.7 and minimum_bob < -0.25 and maximum_bob <= 1.200001 and minimum_bob >= -1.200001, "The real visual bob moves up and down within the gentle 1.2-world-pixel limit")
	check(transform_unchanged and animation.position == Vector2.ZERO and animation.rotation == 0.0, "Station, cradle, tool anchor and parent transform stay fixed throughout rhythmic presentation")
	check(animation.drum.position == animation.DRUM_RECT.get_center() + animation.rhythm_offset, "Only the actual painted drum sprite receives the local beat offset")
	check(mixer.working and mixer.output_amount == 0 and mixer.production_time < mixer.duration() and animation.phase > 0.0, "Original drum rotation and real production time continue without an early free batch")
	game.audio.set_music_volume(0.0)
	await wait_seconds(0.04)
	check(animation.rhythm_offset == Vector2.ZERO and animation.drum.position == animation.DRUM_RECT.get_center(), "The actual Music slider clears beat bob while leaving the machine anchored")
	game.audio.set_music_volume(1.0)
	game.audio.set_rhythm_motion_reduced(true)
	await wait_seconds(0.04)
	check(animation.rhythm_offset == Vector2.ZERO and game.audio.live_music.native_active, "Reduced rhythm motion keeps music and production while clearing decorative drum motion")
	game.audio.set_rhythm_motion_reduced(false)
	game.weather.set_reduced_effects(true)
	await wait_seconds(0.04)
	check(animation.rhythm_offset == Vector2.ZERO, "The existing reduced-effects control suppresses mixer bob")
	game.weather.set_reduced_effects(false)
	await wait_seconds(0.18)
	paused = true
	var production_at_pause := mixer.production_time
	var rotation_at_pause: float = animation.phase
	await wait_seconds(0.12)
	check(animation.rhythm_offset == Vector2.ZERO and animation.phase == rotation_at_pause and mixer.production_time == production_at_pause, "Real pause resets beat presentation and freezes the original rotation and recipe clocks")
	await capture("03-paused-fixed-drum")
	paused = false
	await wait_seconds(0.55)
	check(mixer.production_time > production_at_pause and animation.phase != rotation_at_pause, "Resuming continues the same paid batch and its ordinary drum rotation")
	game.audio.set_live_music_enabled(false)
	await wait_seconds(0.05)
	check(animation.rhythm_offset == Vector2.ZERO and not game.audio.live_music.native_active, "Recorded fallback cannot invent native kick motion")
	check(mixer.position == baseline_position and mixer.interaction_point() == baseline_anchor and mixer.binder == original_binder - 1, "Audio choices and presentation never move gameplay anchors or spend another ingredient")
	check(await Cleanup.free_scene(game, self), "Actual game, native/recorded sound and mixer shader release cleanly")
	var report := {"checks": checks, "failures": failures, "actual_native_music": true, "actual_station": true,
		"prepared_state": "Actual foundry bunker, one paid mixer batch and immediate native groove; automatic wave spawning held, normal station/player physics active; camera close view",
		"minimum_drum_bob": minimum_bob, "maximum_drum_bob": maximum_bob, "heard_kicks": audible_kicks.size(),
		"station_and_tool_anchors_unchanged": transform_unchanged, "captures": captures, "rendered": capture_enabled}
	FileAccess.open(OUTPUT + "/verification.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MIXER RHYTHM GAMEPLAY: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
