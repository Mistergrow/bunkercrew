extends SceneTree
## All thirteen preview locations, two languages and two native resolutions.
## Actual paused menu, fixed presentation clock, fresh roster, no saved profile.
const OUT := "res://artifacts/menu-world-gallery/"
const L := preload("res://scripts/locale_text.gd")
const Roster := preload("res://scripts/crew_roster.gd")
var view: SubViewport
var game
var checks := 0
var failures := 0
var captures: Array = []
var requested_worlds: PackedStringArray = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int = 3) -> void:
	for unused in count: await process_frame

func validate(panel, environment: Dictionary) -> void:
	check(panel.preview_clip.get_rect() == game.hud.screen_rect(), "Preview covers full output: " + environment.id)
	var title: String = L.text(str(environment.title)).capitalize()
	var title_size := 24
	while title_size > 14 and UiArt.MENU_FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > 308: title_size -= 1
	check(UiArt.MENU_FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x <= 308, "Translated location fits beside arrows: " + environment.id)
	var labels_fit := true
	var controls: Array = []
	controls.append_array(panel.mode_buttons)
	controls.append_array(panel.utility_buttons)
	controls.append_array([panel.story_button, panel.friends_button, panel.quit_button, panel.preview_previous, panel.preview_next])
	for button: Button in controls:
		var font := button.get_theme_font("font")
		labels_fit = labels_fit and font.get_string_size(L.text(button.text), HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x <= button.size.x - 24
	check(labels_fit, "All translated native controls fit: " + environment.id)

func write_index() -> void:
	var html := "<!doctype html><html lang='en'><meta charset='utf-8'><meta name='viewport' content='width=device-width'><title>Bunkercrew menu world review</title><style>body{margin:24px;background:#111a1c;color:#e0decb;font:16px system-ui}h1{font-size:24px}p{max-width:80ch;color:#b8b9ad}nav{position:sticky;top:0;padding:12px;background:#111a1c}button{margin-right:8px;padding:8px;background:#344039;color:#e0decb;border:1px solid #63726c;cursor:pointer}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(430px,1fr));gap:20px}figure{margin:0}img{display:block;width:100%}figcaption{padding:8px 0;font-size:14px}a{color:inherit}figure[hidden]{display:none}</style><h1>Bunkercrew · menu world review</h1><p>Actual paused main-menu captures: thirteen preview locations, German and English, native 2560×1440 and 960×600. Prepared empty roster and controlled weather clock; no saved campaign or player progress was changed. Open an image to inspect its full resolution.</p><nav><button onclick=\"show('qhd','de')\">QHD · DE</button><button onclick=\"show('qhd','en')\">QHD · EN</button><button onclick=\"show('small','de')\">960×600 · DE</button><button onclick=\"show('small','en')\">960×600 · EN</button></nav><main>"
	for entry: Dictionary in captures:
		var resolution: String = "qhd" if int(entry.resolution[0]) == 2560 else "small"
		html += "<figure data-size='%s' data-lang='%s'><a href='%s'><img loading='lazy' src='%s' alt='%s'></a><figcaption>%s · %s · %d×%d</figcaption></figure>" % [resolution, entry.locale, entry.file, entry.file, entry.environment, entry.environment, entry.locale.to_upper(), entry.resolution[0], entry.resolution[1]]
	html += "</main><script>function show(size,lang){document.querySelectorAll('figure').forEach(item=>item.hidden=item.dataset.size!==size||item.dataset.lang!==lang)}show('qhd','de')</script></html>"
	var file := FileAccess.open(OUT + "index.html", FileAccess.WRITE)
	file.store_string(html)
	file.close()

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="): requested_worlds = argument.trim_prefix("--only=").split(",", false)
	AudioServer.set_bus_mute(0, true)
	Roster.persistence_enabled = false
	Roster.unlocked.clear()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	view = SubViewport.new()
	view.world_2d = World2D.new()
	view.size_2d_override_stretch = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames(8)
	var panel = game.hud.main_menu_panel
	panel.set_process(false)
	var game_clock: float = game.elapsed
	for resolution in ["qhd", "small"]:
		view.size = Vector2i(2560,1440) if resolution == "qhd" else Vector2i(960,600)
		view.size_2d_override = Vector2i(1600,900) if resolution == "qhd" else Vector2i(1440,900)
		game.hud._layout_viewport()
		for locale in ["de", "en"]:
			L.set_locale(locale, false)
			for index in panel.environments.size():
				var environment: Dictionary = panel.environments[index]
				if not requested_worlds.is_empty() and environment.id not in requested_worlds: continue
				panel.environment_index = index
				panel._show_environment()
				panel.preview.set_process(false)
				panel.preview.elapsed = 12.0 - panel.preview.atmosphere.phase
				panel.preview._redraw_clock = 1.0
				panel.preview._process(0.0)
				panel.decoration.queue_redraw()
				panel.mode_buttons[0].grab_focus()
				await frames()
				validate(panel, environment)
				var name: String = "%s-%s-%s" % [resolution, locale, environment.id]
				if DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
					var picture := view.get_texture().get_image()
					check(picture.get_size() == view.size and picture.save_png(OUT + name + ".png") == OK, "Native capture saved: " + name)
				captures.append({"file":name + ".png", "environment":environment.id, "locale":locale, "resolution":[view.size.x, view.size.y], "presentation_clock":panel.preview.elapsed})
	check(paused and game.elapsed == game_clock and not game.started and not game.network.active, "Gallery preserves paused gameplay and inactive network")
	check(captures.size() == (52 if requested_worlds.is_empty() else requested_worlds.size() * 4), "Every requested location has both languages and resolutions")
	var run_captures := captures.size()
	# Focused follow-up captures replace their entries in the full review gallery.
	if not requested_worlds.is_empty() and FileAccess.file_exists(OUT + "gallery.json"):
		var previous = JSON.parse_string(FileAccess.get_file_as_string(OUT + "gallery.json"))
		if previous is Dictionary:
			for entry: Dictionary in previous.get("captures", []):
				if str(entry.environment) not in requested_worlds: captures.append(entry)
	var report := FileAccess.open(OUT + "gallery.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"prepared_state":"Actual paused main menu; disposable empty roster, first action focused, controlled 12-second weather cycle; no campaign or player profile writes.", "checks":checks, "failures":failures, "rendered":DisplayServer.get_name() != "headless", "last_run_worlds":Array(requested_worlds), "captures":captures}, "  "))
	report.close()
	if DisplayServer.get_name() != "headless": write_index()
	paused = false
	await preload("res://tests/scene_cleanup.gd").free_scene(game, self)
	view.queue_free()
	await process_frame
	print("MENU WORLD GALLERY: %d/%d passed; %d prepared states, %d total gallery entries" % [checks - failures, checks, run_captures, captures.size()])
	quit(1 if failures else 0)
