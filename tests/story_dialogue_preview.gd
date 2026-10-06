extends SceneTree
## Actual main-scene UI at native QHD; positions are prepared for repeatable review.

const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
var game
var rendered: SubViewport
var locale := "de"

func _initialize(): run.call_deferred()

func check(value: bool, label: String):
	checks += 1
	if value: print("PASS ", label)
	else:
		failures += 1
		push_error(label)

func capture(label: String):
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	var size := rendered.get_visible_rect().size
	check(Rect2(Vector2.ZERO, size).encloses(game.dialogue.panel_bounds) and game.dialogue.panel_bounds.size.y >= 60, label + " stays inside the actual viewport")
	var picture := rendered.get_texture().get_image()
	check(picture.get_size() == Vector2i(2560, 1440), label + " is rendered at native 2560×1440")
	for button: Button in game.hud.buttons:
		check(not game.dialogue.panel_bounds.intersects(button.get_global_rect()), label + " leaves " + button.text + " unobstructed")
	var prefix := "en-" if locale == "en" else ""
	check(picture.save_png("res://artifacts/story-dialogue/" + prefix + label + ".png") == OK, label + " screenshot saved")

func prepare(count: int):
	if is_instance_valid(game): await Cleanup.free_scene(game, self)
	game = load("res://scenes/main.tscn").instantiate()
	rendered.add_child(game)
	game.selected_characters.assign(["mara", "branko"])
	game.story_mode = true
	game.start_scenario(count, {"environment":"overgrown_steelworks", "position":"left", "build_type":"bastion"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.story.set_process(false)
	game.set_process(false)
	game.audio.set_music_volume(0.0)
	game.audio.set_sfx_volume(0.0)
	game.weather.lightning_enabled = false
	game.dialogue.set_process(false)
	game.dialogue.reset()
	for index in game.players.size():
		var worker = game.players[index]
		worker.set_physics_process(false)
		worker.position = Vector2(365 + 130 * index, 430)
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	for frame in 5: await process_frame

func run():
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--locale="): locale = argument.trim_prefix("--locale=")
	if not LocaleText.set_locale(locale, false):
		quit(1)
		return
	if DisplayServer.get_name() == "headless":
		push_error("This preview requires a renderer")
		quit(1)
		return
	# A native render target avoids desktop decorations changing the requested
	# window client size. This is the same canvas stretch as the QHD game window.
	rendered = SubViewport.new()
	rendered.size = Vector2i(2560, 1440)
	rendered.size_2d_override = Vector2i(1600, 900)
	rendered.size_2d_override_stretch = true
	rendered.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(rendered)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/story-dialogue"))
	await prepare(1)
	game.dialogue.enqueue("story_open", "san", 1, 1)
	game.dialogue.advance(.1)
	game.dialogue.advance(.2)
	check(not game.dialogue._radio_mode(), "Solo uses an anchored speech bubble")
	await capture("solo-san-qhd")
	game.dialogue.reset()
	game.dialogue.enqueue("crew_wall", "mara", 1, 2)
	game.dialogue.advance(.1)
	game.dialogue.advance(.2)
	await capture("solo-mara-qhd")
	var age: float = game.dialogue.active_age
	paused = true
	game.hud.overlay = "pause"
	game.dialogue.advance(2.0)
	check(game.dialogue.active_age == age and not game.dialogue.canvas.visible, "Actual main pause hides and freezes solo speech")
	paused = false
	game.hud.overlay = ""
	await prepare(2)
	game.dialogue.enqueue("crew_reply", "branko", 2, 1)
	game.dialogue.advance(.1)
	game.dialogue.advance(.2)
	check(game.dialogue._radio_mode() and game.dialogue.active.speaker_id == "branko", "Co-op uses the actual second worker's radio subtitle")
	await capture("coop-branko-qhd")
	game.dialogue.reset()
	game.hud.overlay = "victory"
	paused = true
	game.dialogue.enqueue("story_victory", "san", 1, 2)
	game.dialogue.advance(.1)
	game.dialogue.advance(.2)
	await capture("ending-san-qhd")
	game.dialogue.reset()
	paused = false
	await create_timer(.2, true).timeout
	await Cleanup.free_scene(game, self)
	print("Story dialogue preview: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
