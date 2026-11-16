extends SceneTree
## Wave banner, result report, panel retirement, world words under menus and
## the reading-surface fixes. A real solo match; no saved profile.
const L := preload("res://scripts/locale_text.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var game
var view: SubViewport
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("UI EVENT %s: %s" % ["PASS" if value else "FAIL", label])

func frames(count: int = 3) -> void:
	for unused in count: await process_frame

func run() -> void:
	root.size = Vector2i(320, 180)
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	view = SubViewport.new()
	view.size = Vector2i(1600, 900)
	view.size_2d_override = Vector2i(1600, 900)
	view.size_2d_override_stretch = true
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.start_scenario(1, {"environment":"sector07", "build_type":"bastion", "position":"left"})
	game.rounds.set_process(false)
	game.set_process(false)
	game.notice_time = 0
	await frames()
	var hud = game.hud
	# Wave banner: state, not events, on first sight; one banner per real turn.
	check(hud._banner.is_empty(), "The first observed phase announces nothing")
	game.rounds.phase = "warning"
	await frames(2)
	check(str(hud._banner.get("word", "")) == "KONTAKT" and int(hud._banner.get("wave", 0)) == game.rounds.wave, "Contact is announced with the replicated wave number")
	var contact_started: float = hud._banner.started
	game.rounds.phase = "attack"
	await frames(2)
	check(str(hud._banner.get("word", "")) == "ANGRIFF", "The attack replaces the contact banner")
	check(float(hud._banner.started) <= contact_started + 1.0, "A held banner swaps its words instead of re-opening")
	game.rounds.phase = "salvage"
	await frames(2)
	check(str(hud._banner.get("word", "")) == "ABGEWEHRT" and bool(hud._banner.hazard) == false, "A repelled wave is announced calmly")
	hud._banner.started = UiMotion.now() - 10.0
	await frames(2)
	check(hud._banner.is_empty(), "The banner leaves after its hold, also with motion off")
	hud.overlay = "upgrades"
	await frames(2)
	game.rounds.phase = "build"
	await frames(2)
	check(hud._banner.is_empty(), "A turn from salvage to build is not an attack ending")
	game.rounds.phase = "warning"
	await frames(2)
	check(not hud._banner.is_empty(), "A turn under an open panel is tracked")
	hud._banner.started = UiMotion.now() - 10.0
	hud.overlay = ""
	await frames(3)
	check(hud._banner.is_empty(), "A turn that happened under a panel is not announced late")
	for locale in ["de", "en"]:
		L.set_locale(locale, false)
		var title: String = L.format("WELLE %02d", 12)
		check(UiArt.TITLE_FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, hud.SIGNAL_CRISP).x < 600.0 - 2.0 * 26.0 - 24.0, "Banner title fits between the hazard caps in " + locale)
		for word in ["KONTAKT", "ANGRIFF", "ABGEWEHRT"]:
			check(UiArt.MENU_FONT.get_string_size(L.text(word), HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x < 600.0 - 2.0 * 26.0 - 24.0, "Banner word fits in %s: %s" % [locale, word])
	L.set_locale("de", false)
	# World words never show through a menu, warnings included.
	var core = game.core
	check(not UiArt.menu_covers_world(game), "Play leaves the world uncovered")
	hud.overlay = "personal"
	await frames(4)
	check(UiArt.menu_covers_world(game) and not UiArt.world_label_visible(core), "An open panel covers world labels")
	var rect: Rect2 = UiArt.world_label(core, Vector2.ZERO, "Bunkerkern", "1/2 LP", UiArt.RED)
	check(not rect.has_area(), "Red warnings also stay under an open panel")
	hud._refresh_world_labels(1.0)
	var callsign: Node = game.medic.get_node_or_null("Callsign")
	check(callsign is CanvasItem and not callsign.visible, "SAN-1's callsign hides under menus")
	check(callsign is CanvasItem and callsign.z_index + game.medic.z_index > game.players[0].z_index, "SAN-1's callsign draws above the crew")
	# Closing with motion off frees at once and leaves no retiring copy.
	hud.overlay = ""
	await frames(4)
	check(not is_instance_valid(hud.personal_panel), "The personnel panel closes")
	var retiring: Array = hud.canvas.get_children().filter(func(node: Node): return str(node.name).begins_with("Retiring"))
	check(retiring.is_empty(), "Settled runs keep the immediate close")
	hud._refresh_world_labels(1.0)
	check(callsign.visible, "The callsign returns in play")
	# With motion on, a dismissed panel fades out and frees itself.
	UiMotion.force(true)
	hud.overlay = "upgrades"
	await frames(4)
	var panel: Control = hud.upgrade_panel
	hud.overlay = ""
	await frames(2)
	check(is_instance_valid(panel) and panel.process_mode == Node.PROCESS_MODE_DISABLED and panel.mouse_filter == Control.MOUSE_FILTER_IGNORE and str(panel.name).begins_with("Retiring"), "A dismissed panel retires without input")
	check(hud.upgrade_panel == null, "The HUD forgets the retiring panel at once")
	var deadline := Time.get_ticks_msec() + 3000
	while is_instance_valid(panel) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not is_instance_valid(panel), "The retiring panel frees itself after its fade")
	UiMotion.force(null)
	# Result report reads replicated values only and lays out inside its plate.
	game.elapsed = 754.0
	game.stats.kills = 37
	game.rounds.running = true
	game.rounds.victory()
	await frames(6)
	check(hud.overlay == "victory" and hud.buttons.size() >= 2, "Victory opens the report with its actions")
	for button: Button in hud.buttons:
		check(hud.RESULT_PLATE.encloses(Rect2(button.position, button.size)), "Report action stays on the plate: " + button.text)
	check(UiArt.ICON_NAMES.has(hud.RESULT_ICONS[0]) and UiArt.ICON_NAMES.has(hud.RESULT_ICONS[3]), "Report tiles use atlas icons")
	# Reading surfaces.
	var boost := UiArt.compact_boost(hud.canvas)
	check(boost >= 1.0 and boost <= 1.25, "Small-window helper boost stays bounded")
	check(is_equal_approx(UiArt.compact_boost(null), 1.0), "No node, no boost")
	var on: Texture2D = UiArt.switch_icon(true)
	check(on.get_width() == 60 and on.get_height() == 30, "Option switches are 60x30 design pixels (12x6 cells of 5)")
	await Cleanup.free_scene(game, self)
	print("UI EVENT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
