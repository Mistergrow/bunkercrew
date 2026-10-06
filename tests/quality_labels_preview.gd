extends SceneTree
## Actual game rendering with prepared production buffers and stationary workers.
const DESTINATION := "res://artifacts/quality-pass/labels"
const CLEANUP := preload("res://tests/scene_cleanup.gd")
var game
var captures: Array[Dictionary] = []
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func frames(count: int = 4) -> void:
	for frame in count:
		await process_frame

func capture(label: String, description: String) -> void:
	game.notice = ""
	game.notice_time = 0.0
	game.hud.canvas.queue_redraw()
	for station in get_nodes_in_group("stations"):
		station.queue_redraw()
	await frames()
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(DESTINATION + "/" + label + ".png") != OK:
		failures += 1
		push_error("Could not save label preview " + label)
	captures.append({"file":label + ".png", "description":description})
	print("LABEL PREVIEW ", label)

func station_of(kind: String):
	for station in get_nodes_in_group("stations"):
		if station.kind == kind and not station.is_queued_for_deletion():
			return station
	return null

func focus(station, player_index: int = 0) -> void:
	var worker = game.players[player_index]
	worker.position = station.position + Vector2(-43, 0)
	worker.velocity = Vector2.ZERO
	worker.facing = 1
	worker.focus = station
	worker.preferred_focus = station

func camera_at(height: float) -> void:
	game.camera_target_center = Vector2(720, height)
	game.camera_target_zoom = 1.0
	game.camera.position = game.camera_target_center
	game.camera.zoom = Vector2.ONE

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Use a graphical display and --no-profile-save")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DESTINATION))
	root.size = Vector2i(1440, 900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.start_scenario(1, {"environment":"sector07", "build_type":"workshop", "position":"left"})
	game.set_process(false)
	game.rounds.running = false
	game.rounds.set_process(false)
	game.medic.set_physics_process(false)
	game.players[0].set_physics_process(false)
	for station in get_nodes_in_group("stations"):
		station.set_process(false)
	camera_at(450)
	var mixer = station_of("mixer")
	focus(mixer)
	await capture("01-mixer-empty", "Startbunker, Welle 1 angehalten, Mara vor dem leeren Betonmischer; keine zugewiesenen Rohstoffe.")
	game.players[0].inventory = {"sand":2}
	await capture("02-mixer-supplied", "Mara trägt zwei Sand. Dieselbe Anlage zeigt die mögliche Einfüllaktion.")
	game.players[0].inventory.clear()
	mixer.working = true
	mixer.production_time = mixer.duration() * 0.4
	await capture("03-mixer-working", "Herstellung vorbereitet bei 40 Prozent; Timer für den Screenshot angehalten.")
	mixer.working = false
	mixer.output_amount = int(mixer.recipe().amount)
	await capture("04-mixer-ready", "Fertiger Beton im Ausgabefach; freie Hände und Abholhinweis.")
	game.players[0].inventory = {"sand":game.players[0].capacity()}
	await capture("05-mixer-full", "Fertiger Beton bleibt liegen, weil Maras tatsächliche Tragekapazität ausgeschöpft ist.")
	game.players[0].inventory.clear()
	game.join_coop()
	game.players[1].set_physics_process(false)
	var furnace = station_of("furnace")
	focus(furnace, 1)
	game.players[1].inventory = {"ore":2}
	await capture("06-local-coop", "Lokaler Koop: Mara am Betonmischer, Branko am Schmelzofen; getrennte Hinweise und Belegungen.")
	game.network.active = true
	game.network.is_host = false
	game.network.local_player_id = 2
	game.network.state = "playing"
	game.network.set_process(false)
	game.network.set_physics_process(false)
	focus(mixer, 1)
	game.players[0].position.x += 100
	game.players[1].inventory = {"sand":2}
	await capture("07-online-guest", "Vorbereitete Gastrolle P2 ohne Socket: dieselben Tastaturbelegungen wie P1, nur eigener Kontexthinweis.")
	game.network.leave()
	game.players[1].focus = null
	game.rounds.wave = 16
	for index in ScenarioRoomCatalog.ROOMS.size():
		var worker = game.players[0]
		if not await preload("res://tests/scenario_excavation_fixture.gd").build_room(game,index,worker):
			failures += 1
			push_error("Prepared room failed its actual construction route")
		await frames(1)
	for station in get_nodes_in_group("stations"):
		station.set_process(false)
	for kind in ["ammo_press", "glass", "alloy"]:
		var station = station_of(kind)
		if station == null:
			failures += 1
			push_error("Missing deep station " + kind)
			continue
		focus(station)
		station.working = true
		station.production_time = station.duration() * 0.35
		camera_at(station.position.y + 50)
		await capture("08-deep-" + kind, "Ausgebaute reale Etage, Welle 16 angehalten; " + station.interaction_title() + " mit vorbereitetem laufendem Auftrag. Kamera auf diese Etage gesetzt.")
	game.upgrades.add_points(12)
	game.hud._toggle_upgrades()
	await frames()
	game.hud.upgrade_panel._select("bunker_workshop")
	await capture("09-technology", "Reales Technikmenü, zwölf zugewiesene Punkte; Fertigungstechnik ausgewählt, noch nicht gekauft.")
	game.hud._close_upgrades()
	await frames()
	camera_at(450)
	game.rounds.wave = 1
	var supply = get_nodes_in_group("supplies").filter(func(stock): return stock.kind == "steel" and not stock.is_queued_for_deletion())[0]
	game.players[1].focus = null
	focus(supply)
	game.players[0].inventory = {"steel":game.players[0].capacity()}
	game.players[0].selected_kind = "steel"
	await capture("10-roof-p1-full", "Dachlager, Mara trägt ihre maximale Menge Stahl. Einlagerung bleibt trotz vollem Inventar möglich; keine Entnahme.")
	game.players[0].focus = null
	game.players[0].position = mixer.position + Vector2(-43,0)
	focus(supply,1)
	game.players[1].inventory = {"steel":3}
	game.players[1].selected_kind = "steel"
	await capture("11-roof-p2", "Lokaler P2 vor der Stahlkiste: Entnahme und Einlagerung mit der zweiten Tastatur-/Controllerbelegung.")
	supply.amount = 0
	supply.queue_redraw()
	await capture("12-roof-empty", "Leer vorbereitete Stahlkiste mit passendem Material bei P2. Das sichtbare Lager kann wieder befüllt werden.")
	await physics_frame
	supply.deposit(game.players[1], Balance.TRANSFER_TIME)
	if supply.amount != 1:
		failures += 1
		push_error("Preview could not return one steel through the real supply deposit API")
	await capture("13-roof-returned", "Ein Stahl wurde über die echte Einlagerungsfunktion aus P2s Inventar zurückgegeben; Lagerbestand steigt auf eins.")
	game.network.active = true
	game.network.is_host = false
	game.network.local_player_id = 2
	game.network.state = "playing"
	await capture("14-roof-online", "Vorbereitete Online-Gastrolle ohne Verbindung: derselbe Vorrat zeigt E/G statt der lokalen P2-Belegung.")
	game.network.leave()
	game.hud.overlay = "help"
	game.hud._apply_overlay_pause()
	await capture("15-help", "Reale Spielhilfe mit Materialeinlagerung und beiden lokalen Steuerungsbelegungen.")
	var metadata := FileAccess.open(DESTINATION + "/capture.json", FileAccess.WRITE)
	metadata.store_string(JSON.stringify({"size":[1440,900], "engine":Engine.get_version_info().string, "captures":captures, "fixture":"Actual main scene, no profile saves, no network sockets or router mappings. Wave progression and worker physics stopped. Production buffers and camera are prepared; room construction uses real paid APIs."}, "\t"))
	metadata.close()
	paused = false
	if not await CLEANUP.free_scene(game, self):
		failures += 1
	print("QUALITY LABEL PREVIEW: %d frames, %d failures" % [captures.size(), failures])
	quit(1 if failures else 0)
