extends SceneTree
## Prepared first-aircraft encounters, real solo game and renderer. No profile writes.
const OUT := "res://artifacts/air-raid-intro/preview/"
const Cleanup := preload("res://tests/scene_cleanup.gd")
const IntroLines := preload("res://scripts/air_raid_intro_catalog.gd")
const CREW := ["mara", "branko", "ivo", "nora", "levin", "selma"]
var game
var view: SubViewport
var checks := 0
var failures := 0
var captures: Array[Dictionary] = []
var requested_crew := PackedStringArray()
var record_video := false

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func frames(count: int = 4) -> void:
	for unused in count: await process_frame

func effective_z(item: CanvasItem) -> int:
	var result := item.z_index
	var parent := item.get_parent()
	if item.z_as_relative and parent is CanvasItem:
		result += effective_z(parent)
	return result

func prepare(character_id: String) -> void:
	if is_instance_valid(game):
		paused = false
		check(await Cleanup.free_scene(game, self), "Previous preview releases audio and input services")
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.selected_characters.assign([character_id])
	game.start_scenario(1, {"environment":"storm_dam", "position":"left", "build_type":"bastion"})
	game.rounds.set_process(false)
	game.air_raid_intro.set_process(false)
	# Construct the real AA emplacement, then reach the first scheduled air slot.
	game.rounds.wave = 6
	game.flak_station.unlock()
	var worker: Node = game.players[0]
	worker.inventory = {"steel":3, "concrete":2, "ammo":1}
	for kind: String in ["steel", "concrete", "ammo"]:
		worker.selected_kind = kind
		for transfer in 8:
			if int(worker.inventory.get(kind, 0)) <= 0: break
			game.flak_station.interact(worker, Balance.TRANSFER_TIME)
	game.flak_station.interact(worker, 3.0)
	check(game.air_defense_ready(), "Prepared scene commissions real AA")
	game.rounds.wave = 7
	game.rounds.phase = "build"
	game.rounds.begin_warning()
	game.rounds._begin_attack()
	var roster := EnemyCatalog.wave_roster(7, game.rounds.wave_total, true)
	var air_index := -1
	for index in roster.size():
		if AirEnemyCatalog.is_air(roster[index]):
			air_index = index
			break
	check(air_index >= 0, "Wave seven contains a scheduled aircraft")
	game.rounds.spawned = air_index
	game.rounds.spawn_clock = 0.0
	game.rounds._process(.01)
	await frames()
	check(game.air_raid_intro.active and paused and game.hud.overlay == "air_raid_intro", "Real first-air trigger presents the overlay")
	check(game.air_raid_intro.context.character_id == character_id and game.players[0].character_id == character_id, "Presentation preserves chosen worker " + character_id)

func capture(character_id: String, locale: String, resolution: String, label: String, clock: float, reduced: bool = false) -> void:
	LocaleText.set_locale(locale, false)
	view.size = Vector2i(2560, 1440) if resolution == "qhd" else Vector2i(960, 600)
	view.size_2d_override = Vector2i(1600, 900) if resolution == "qhd" else Vector2i(1440, 900)
	game.hud._layout_viewport()
	game.weather.set_reduced_effects(reduced)
	# Language switching deliberately extends a live introduction. These prepared
	# timeline frames review its authored eight-second duration instead.
	game.air_raid_intro.duration = 8.0
	game.air_raid_intro.elapsed = clock
	await frames()
	await RenderingServer.frame_post_draw
	check(game.air_raid_intro.active and paused, "Capture keeps simulation paused: " + label)
	check(not game.dialogue.canvas.visible, "Standard speech UI stays hidden behind presentation: " + label)
	var panel = game.hud.air_raid_panel
	check(panel.visible and panel.size.x > 0 and panel.size.y > 0, "Full-screen presentation is visible: " + label)
	var scene_front := -4096
	for item: CanvasItem in panel.cloud_nodes + panel.aircraft_nodes:
		scene_front = maxi(scene_front, effective_z(item))
	var ui_clear := true
	for item: CanvasItem in [panel.decoration, panel.portrait_canvas, panel.caption_label, panel.speaker_label, panel.skip_button]:
		ui_clear = ui_clear and effective_z(item) > scene_front
	check(ui_clear, "Clouds and aircraft cannot occlude captions, portrait or skip control: " + label)
	if label in ["comment", "reduced"]:
		var visible_area := Rect2(Vector2.ZERO, panel.size)
		check(visible_area.encloses(panel.caption_bounds) and panel.caption_bounds.has_area(), "Localized caption fits actual presentation: " + label)
		check(visible_area.encloses(panel.portrait_bounds) and panel.portrait_bounds.has_area(), "Selected portrait fits actual presentation: " + label)
		check(visible_area.encloses(panel.skip_button.get_rect()) and not panel.skip_button.get_rect().intersects(panel.caption_bounds), "Skip control leaves the dialogue unobstructed: " + label)
		check(panel.caption_label.get_line_count() * panel.caption_label.get_line_height() <= panel.caption_label.size.y, "Wrapped localized caption fits its height: " + label)
	var line: Dictionary = IntroLines.line(character_id)
	check(line.portrait_id == character_id and not str(line.text).is_empty(), "Localized selected-crew comment exists: " + label)
	check(panel.dialogue.portrait_id == character_id and panel.caption_label.text == str(line.text) and panel.speaker_label.text == str(line.speaker_name), "Visible portrait and caption use actual localized worker: " + label)
	if clock >= 1.15 and not str(line.voice_path).is_empty():
		check(panel.voice.stream != null and panel.voice.stream.resource_path == str(line.voice_path), "Matching character recording is selected: " + label)
	var filename := "%s-%s-%s-%s.png" % [resolution, locale, character_id, label]
	var picture := view.get_texture().get_image()
	check(picture.get_size() == view.size and picture.save_png(OUT + filename) == OK, "Native capture saved: " + filename)
	captures.append({"file":filename, "character":character_id, "locale":locale, "resolution":[view.size.x, view.size.y], "phase":label, "presentation_clock":clock, "reduced_effects":reduced, "subtitle":str(line.text)})

func capture_video() -> void:
	LocaleText.set_locale("de", false)
	view.size = Vector2i(1280, 720)
	view.size_2d_override = Vector2i(1600, 900)
	game.hud._layout_viewport()
	game.weather.set_reduced_effects(false)
	game.air_raid_intro.duration = 8.0
	var directory := OUT + "video-frames/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var saved := true
	for frame in 161:
		game.air_raid_intro.elapsed = float(frame) / 20.0
		await frames(2)
		await RenderingServer.frame_post_draw
		var picture := view.get_texture().get_image()
		saved = saved and picture.get_size() == view.size and picture.save_png(directory + "%04d.png" % frame) == OK
	check(saved and paused and game.air_raid_intro.active, "Eight-second 720p timeline renders from the real paused introduction at 20 fps")

func write_report() -> void:
	var report := FileAccess.open(OUT + "gallery.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"prepared_state":"Actual solo game with a paid and completed Flak I; wave seven's first scheduled aircraft triggers the introduction. Presentation clock is frozen only for captures. All six identities are unlocked in disposable memory; player profiles remain untouched.", "checks":checks, "failures":failures, "video":"Silent 1280x720 preview, 20 fps, controlled presentation clock from 0 through 8 seconds; no user window recording." if record_video else "", "captures":captures}, "  "))
	report.close()
	var html := "<!doctype html><html lang='en'><meta charset='utf-8'><meta name='viewport' content='width=device-width'><title>Bunkercrew · first air raid</title><style>body{margin:24px;background:#111a1c;color:#e0decb;font:16px system-ui}h1{font-size:24px}p{max-width:80ch}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(430px,1fr));gap:20px}figure{margin:0}img{width:100%;display:block}figcaption{padding:8px 0;font-size:14px}a{color:inherit}</style><h1>Bunkercrew · first air raid</h1><p>Prepared solo encounters: six selected identities, German and English, native QHD and 960×600. Additional timeline and reduced-effects states. Captures freeze presentation time; they do not represent a live playthrough.</p><main>"
	if record_video:
		html += "<figure><video controls preload='metadata' style='width:100%' src='air-raid-intro-de-mara.mp4'></video><figcaption>Mara · DE · 1280×720 · silent 20 fps preview; controlled presentation clock</figcaption></figure>"
	for entry: Dictionary in captures:
		html += "<figure><a href='%s'><img loading='lazy' src='%s' alt='%s'></a><figcaption>%s · %s · %d×%d · %s · %.2fs%s</figcaption></figure>" % [entry.file, entry.file, entry.character, entry.character.capitalize(), entry.locale.to_upper(), entry.resolution[0], entry.resolution[1], entry.phase, entry.presentation_clock, " · reduced effects" if entry.reduced_effects else ""]
	html += "</main></html>"
	var index_file := FileAccess.open(OUT + "index.html", FileAccess.WRITE)
	index_file.store_string(html)
	index_file.close()

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("Air raid preview requires a renderer and --no-profile-save")
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="): requested_crew = argument.trim_prefix("--only=").split(",", false)
		if argument == "--video": record_video = true
	AudioServer.set_bus_mute(0, true)
	CrewRoster.persistence_enabled = false
	CrewRoster.unlocked = {"nora":true, "levin":true, "selma":true}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	view = SubViewport.new()
	view.size = Vector2i(2560, 1440)
	view.size_2d_override = Vector2i(1600, 900)
	view.size_2d_override_stretch = true
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	for character_id: String in CREW:
		if not requested_crew.is_empty() and character_id not in requested_crew: continue
		await prepare(character_id)
		for locale: String in ["de", "en"]:
			for resolution: String in ["qhd", "small"]:
				await capture(character_id, locale, resolution, "comment", 3.4)
		if character_id == "mara":
			for phase: Dictionary in [{"name":"entry", "time":0.35}, {"name":"reveal", "time":1.65}, {"name":"pass", "time":6.35}, {"name":"exit", "time":7.75}]:
				await capture(character_id, "de", "qhd", phase.name, phase.time)
			await capture(character_id, "de", "qhd", "reduced", 3.4, true)
			await capture(character_id, "en", "small", "reduced", 3.4, true)
			if record_video: await capture_video()
	# Send a real pointer press through the rendered viewport's GUI hit test.
	# This intentionally does not emit Button.pressed or call the skip method.
	if is_instance_valid(game):
		game.air_raid_intro.elapsed = 3.4
		await frames()
		var target: Vector2 = game.hud.air_raid_panel.skip_button.get_global_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = target
		view.push_input(motion, true)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = target
		click.pressed = true
		view.push_input(click, true)
		click = click.duplicate()
		click.pressed = false
		view.push_input(click, true)
		await frames()
		check(not game.air_raid_intro.active and not paused and game.hud.overlay.is_empty(), "Rendered skip button receives pointer hit and releases only the introduction")
	paused = false
	if is_instance_valid(game): check(await Cleanup.free_scene(game, self), "Final preview releases cleanly")
	view.queue_free()
	await process_frame
	write_report()
	print("AIR RAID PREVIEW: %d/%d checks passed; %d native captures" % [checks - failures, checks, captures.size()])
	quit(1 if failures else 0)
