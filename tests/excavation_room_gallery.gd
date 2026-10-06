extends SceneTree
## Rendered, prepared construction states reached through real digging and
## deposit APIs. Travel is arranged; yields are banked in real supply crates.
const OUT := "res://artifacts/excavation-room-gallery/"
const Cleanup := preload("res://tests/scene_cleanup.gd")
var view: SubViewport
var game
var checks := 0
var failures := 0
var captures: Array[Dictionary] = []
var banked: Dictionary = {}
var only_style := ""

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func frames(count: int = 3) -> void:
	for unused in count: await process_frame

func prepare(style: String) -> void:
	if is_instance_valid(game):
		check(await Cleanup.free_scene(game, self), "Previous construction scene released")
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames()
	game.start_scenario(1, {"environment":"ash_foundry", "build_type":style, "position":"left"})
	game.set_process(false)
	game.rounds.set_process(false)
	game.story.set_process(false)
	game.player_camera.set_process(false)
	game.hud.canvas.hide()
	game.dialogue.canvas.hide()
	game.dialogue.set_process(false)
	game.players[0].set_physics_process(false)
	game.notice = ""
	game.notice_time = 0.0
	game.scenario_bunker.modules[0].set_process(false)
	banked.clear()
	await physics_frame
	await physics_frame
	place_worker(0, game.scenario_bunker.room_left + 107)
	set_camera(0)
	check(game.scenario_bunker.fields[0].remaining_count() == 30, style + ": entire future room contains thirty real earth cells")

func place_worker(index: int, x: float) -> void:
	var worker: Worker = game.players[0]
	worker.global_position = Vector2(x, ScenarioRoomCatalog.floor_y(index))
	worker.velocity = Vector2.ZERO
	worker.mining = false
	worker._interacting = false
	worker.focus = null
	worker.queue_redraw()

func set_camera(index: int) -> void:
	game.camera.position = Vector2(game.scenario_bunker.room_left + 320, ScenarioRoomCatalog.floor_y(index) - 162)
	game.camera.zoom = Vector2.ONE * 1.85
	game.camera.force_update_scroll()

func bank_inventory() -> void:
	var worker: Worker = game.players[0]
	var original := worker.global_position
	for kind: String in worker.inventory.keys():
		var amount := int(worker.inventory.get(kind, 0))
		if amount <= 0: continue
		var target: Supply
		for supply: Supply in get_nodes_in_group("supplies"):
			if supply.kind == kind and not supply.is_queued_for_deletion(): target = supply; break
		if not is_instance_valid(target):
			target = game._entity("supply", Vector2(game.scenario_bunker.room_left + 255, 245), {"kind":kind, "amount":0})
		worker.global_position = target.global_position
		worker.selected_kind = kind
		var before := target.amount
		for unit in amount: target.deposit(worker, Balance.TRANSFER_TIME + 0.01)
		check(target.amount - before == amount and int(worker.inventory.get(kind, 0)) == 0, "Excavated " + kind + " reaches a real stockpile")
		banked[kind] = int(banked.get(kind, 0)) + target.amount - before
	worker.global_position = original
	worker.selected_kind = ""

func excavate(index: int, first_column: int, end_column: int) -> void:
	var field: DiggableTerrain = game.scenario_bunker.fields[index]
	var worker: Worker = game.players[0]
	for column in range(first_column, end_column):
		for row in [2, 1, 0]:
			var block: MineBlock = field.cell_at(Vector2i(column, row))
			if not is_instance_valid(block): continue
			place_worker(index, block.global_position.x - 48)
			await physics_frame
			check(block.can_interact(worker), "Reachable real digging face at %d/%d/%d" % [index, column, row])
			var before := field.remaining_count()
			worker.focus = block
			worker.mining = true
			block.interact(worker, block.mining_duration() + 0.01)
			check(field.remaining_count() == before - 1, "Held work removes exactly one solid cell")
			worker.mining = false
			worker.focus = null
			await physics_frame
			await frames(2)
			bank_inventory()
			for pickup: ResourcePickup in get_nodes_in_group("pickups"):
				if pickup.is_queued_for_deletion() or pickup.kind == "core": continue
				if worker.global_position.distance_to(pickup.global_position) > 100: continue
				pickup.interact(worker, 0.01)
				bank_inventory()
	place_worker(index, field.bounds.position.x + end_column * 48 - 45)

func deliver(site: ScenarioRoomSite, cost: Dictionary) -> void:
	var worker: Worker = game.players[0]
	worker.global_position = site.global_position + Vector2(34, 0)
	worker.inventory.clear()
	for kind: String in cost:
		worker.selected_kind = kind
		for unit in int(cost[kind]):
			check(worker.add_item(kind, 1) == 1, "Prepared construction delivery fits backpack")
			site.interact(worker, Balance.TRANSFER_TIME + 0.01)
	check(worker.carried_count() == 0, "Construction materials are consumed by the staged API")

func capture(style: String, index: int, stage: String, locale := "de") -> void:
	LocaleText.set_locale(locale, false)
	game.scenario_bunker.queue_redraw()
	game.notice = ""
	game.notice_time = 0.0
	set_camera(index)
	await frames(5)
	await RenderingServer.frame_post_draw
	var file := "%s-floor%d-%s-%s.png" % [style, index + 1, stage, locale]
	var picture := view.get_texture().get_image()
	check(picture.get_size() == Vector2i(2560, 1440) and picture.save_png(OUT + file) == OK, "Native rendered capture: " + file)
	var site: ScenarioRoomSite = game.scenario_bunker.modules[index]
	captures.append({"file":file, "style":style, "floor":index + 1, "stage":stage, "locale":locale, "remaining_cells":game.scenario_bunker.fields[index].remaining_count(), "supported":site.supported, "construction":site.construction, "curing":site.curing, "built":site.built, "prompt":site.prompt(game.players[0]), "banked_materials":banked.duplicate()})

func stages(style: String, index: int, short := false) -> void:
	var bunker: ScenarioBunker = game.scenario_bunker
	var site: ScenarioRoomSite = bunker.modules[index]
	site.set_process(false)
	place_worker(index, bunker.room_left + 107)
	await capture(style, index, "01-earth")
	await excavate(index, 0, 5)
	if not short: await capture(style, index, "02-half-dug")
	await excavate(index, 5, 10)
	check(site.excavated() and not site.supported and not site.built, "Cleared room waits for its supports")
	place_worker(index, bunker.room_left + 150)
	if not short: await capture(style, index, "03-cleared")
	deliver(site, site.support_cost())
	site.interact(game.players[0], ScenarioRoomCatalog.SUPPORT_TIME)
	check(site.supported and not site.built, "Two paid steel supports precede any finished room")
	await capture(style, index, "04-supported")
	deliver(site, site.room_cost())
	site.interact(game.players[0], ScenarioRoomCatalog.BUILD_TIME * 0.55)
	if not short: await capture(style, index, "05-fitout")
	site.interact(game.players[0], ScenarioRoomCatalog.BUILD_TIME)
	check(site.curing and not site.built, "Full construction still waits for concrete curing")
	if not short: await capture(style, index, "06-curing")
	site._process(ScenarioRoomCatalog.CURE_TIME + 0.01)
	await physics_frame
	check(site.built and bunker.fields[index].is_cleared(), "Finished floor preserves exhausted geology")
	place_worker(index, bunker.room_left + 160)
	await capture(style, index, "07-finished")
	await capture(style, index, "07-finished", "en")

func write_report() -> void:
	var report := FileAccess.open(OUT + "gallery.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"prepared_state":"Actual solo game and GPU renderer. Real mining, stockpile deposits, construction payments and curing APIs; fixture delivery times and worker travel are arranged. Fixed camera includes the upper room for material comparison. HUD is hidden only for inspection. Native 2560x1440 captures, no player profile writes.", "checks":checks, "failures":failures, "captures":captures}, "  "))
	report.close()
	var html := "<!doctype html><html lang='de'><meta charset='utf-8'><meta name='viewport' content='width=device-width'><title>Bunkercrew · Aushub und Raumausbau</title><style>body{margin:24px;background:#141d1b;color:#e2ddc8;font:16px system-ui}p{max-width:90ch}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(480px,1fr));gap:20px}figure{margin:0}img{width:100%;display:block}figcaption{padding:8px 0}a{color:inherit}</style><h1>Bunkercrew · Aushub und Raumausbau</h1><p>Vorbereitete echte Spielszenen: Erde abbauen und in Kisten einlagern, Stahlstützen montieren, Raum ausbauen, Beton härten lassen. Drei Baustile und eine zweite Tiefe. Arbeiterwege und Materiallieferungen sind für die Inspektion angeordnet; das HUD ist ausgeblendet. Alle Bilder 2560×1440.</p><main>"
	for entry: Dictionary in captures:
		html += "<figure><a href='%s'><img loading='lazy' src='%s' alt='%s'></a><figcaption>%s · Ebene %d · %s · %s · %d Erdzellen</figcaption></figure>" % [entry.file, entry.file, entry.stage, entry.style, entry.floor, entry.stage, entry.locale.to_upper(), entry.remaining_cells]
	html += "</main></html>"
	var index_file := FileAccess.open(OUT + "index.html", FileAccess.WRITE)
	index_file.store_string(html)
	index_file.close()

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Excavation gallery requires a renderer and --no-profile-save")
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="): only_style = argument.trim_prefix("--only=")
	AudioServer.set_bus_mute(0, true)
	CrewRoster.persistence_enabled = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	view = SubViewport.new()
	view.size = Vector2i(2560, 1440)
	view.size_2d_override = Vector2i(1600, 900)
	view.size_2d_override_stretch = true
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	for style: String in ["bastion", "workshop", "stronghold"]:
		if not only_style.is_empty() and style != only_style: continue
		await prepare(style)
		await stages(style, 0)
		if style == "bastion":
			game.rounds.wave = 5
			check(game.scenario_bunker.prepare_excavation(1), "Wave-five blueprint opens the second actual digging floor")
			await physics_frame
			await physics_frame
			await stages(style, 1, true)
	write_report()
	check(await Cleanup.free_scene(game, self), "Final construction scene releases audio and world")
	view.queue_free()
	await frames()
	print("EXCAVATION ROOM GALLERY: %d/%d passed; %d actual QHD frames" % [checks - failures, checks, captures.size()])
	quit(1 if failures else 0)
