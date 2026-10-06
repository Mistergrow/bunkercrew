extends SceneTree
## Real interaction states, measured text bounds and control ownership.
const CLEANUP := preload("res://tests/scene_cleanup.gd")
var game
var checks := 0
var failures := 0

class LongPrompt extends Node2D:
	var body := ""
	func interaction_title() -> String:
		return "Prüfanschluss"
	func prompt(_worker) -> String:
		return interaction_title() + "\n" + body

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func measured_width(value: String, font_size: int = 12) -> float:
	return UiArt.FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

func check_detail(worker, label: String) -> Dictionary:
	var detail: Dictionary = game.hud.context_details(worker)
	check(not detail.title.is_empty() and not detail.lines.is_empty(), label + " has an interaction heading and details")
	check(not detail.title in detail.lines, label + " does not repeat its heading in the body")
	for line: String in detail.lines:
		check(measured_width(line) <= 366.01, label + " body fits the actual 366-pixel text column")
	check(measured_width("P%d · %s" % [worker.player_id, detail.title], 13) <= 366.01, label + " heading fits the column")
	for action_line: String in detail.action_lines:
		check(measured_width(action_line, 10) <= 366.01, label + " action footer fits the column")
	return detail

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.start_scenario(2, {"environment":"sector07", "build_type":"workshop", "position":"left"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.medic.set_physics_process(false)
	for worker in game.players:
		worker.set_physics_process(false)
	var player = game.players[0]
	var stations: Array = get_nodes_in_group("stations").filter(func(station): return not station.is_queued_for_deletion())
	for scene_name in ["glass_furnace", "alloy_furnace", "ammo_press"]:
		stations.append(game._entity(scene_name, Vector2(1000, 430)))
	for station in stations:
		station.set_process(false)
		player.position = station.position + Vector2(-40, 0)
		player.focus = station
		player.inventory.clear()
		var empty := check_detail(player, station.kind + " empty")
		check(not empty.show_key, "Empty-handed workers see no inactive station action key")
		var initial_body := "\n".join(empty.lines)
		for resource in station.recipe().inputs:
			player.inventory[resource] = int(station.recipe().inputs[resource])
		var supplied := check_detail(player, station.kind + " supplied")
		check(supplied.show_key, "Usable materials reveal the active deposit key")
		check(empty.action != supplied.action, "Usable cargo changes " + station.kind + " to a deposit action")
		for resource in station.recipe().inputs:
			player.selected_kind = resource
			for unit in int(station.recipe().inputs[resource]):
				station.interact(player, Balance.TRANSFER_TIME)
		station._process(0.0)
		check(station.working and player.inventory.is_empty(), "Actual deposits start " + station.kind + " and consume its ingredients")
		station._process(station.duration() * 0.4)
		var working := check_detail(player, station.kind + " working")
		check(not working.show_key, "Automatic production hides the inactive interaction key")
		check("\n".join(working.lines) != initial_body and working.action != supplied.action, "Production replaces the recipe input state with timing/action feedback")
		station._process(station.duration())
		check(not station.working and station.output_amount > 0, station.kind + " produces real collectable output")
		var finished := check_detail(player, station.kind + " finished")
		check(finished.show_key, "Collectable output reveals the interaction key")
		check(finished.action != working.action, "Finished output changes the action from waiting to collection")
		player.inventory = {"sand":player.capacity()}
		var full := check_detail(player, station.kind + " full inventory")
		check(not full.show_key, "A full inventory hides the blocked collection key")
		check(full.action != finished.action, "Full cargo visibly blocks collection")
		var output_before: int = station.output_amount
		station.interact(player, Balance.TRANSFER_TIME)
		check(station.output_amount == output_before and player.carried_count() == player.capacity(), "A full-inventory message matches the actual blocked transfer")
		player.inventory.clear()
		station.interact(player, Balance.TRANSFER_TIME)
		check(station.output_amount == output_before - 1 and int(player.inventory.get(station.output_kind(), 0)) == 1, "Freeing capacity restores the real collection route")
	# Long leading tokens must split without introducing an empty first row.
	var long_prompt := LongPrompt.new()
	game.add_child(long_prompt)
	player.focus = long_prompt
	for text_sample in [
		"Übertragungsanschluss".repeat(6),
		"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".repeat(3) + " abgeschlossen",
		"Kurzer Satz\n" + "LangeVerbindung".repeat(9),
	]:
		long_prompt.body = text_sample
		var detail := check_detail(player, "long prompt")
		check(not detail.lines[0].is_empty(), "An oversized first token never creates a blank first row")
		check(not "" in detail.lines, "Wrapped nonempty paragraphs remain nonempty")
		check("".join(detail.lines).replace(" ", "") == text_sample.replace(" ", "").replace("\n", ""), "Wrapping preserves every nonspace character")
	long_prompt.body=""
	var empty_compact: Dictionary=game.hud.compact_context_details(player,302,14)
	check(empty_compact.lines.is_empty() and empty_compact.lines.get_typed_builtin()==TYPE_STRING,"Empty context retains a typed string array instead of casting an untyped literal")
	var roof_gun=get_nodes_in_group("turrets").filter(func(node): return node is RoofTurret and node.game==game)[0]
	for operator in game.players:
		operator.focus=roof_gun
		roof_gun.enter(operator)
		check(operator.mounted_turret==roof_gun,"Empty-context regression uses a genuinely mounted worker")
		var mounted: Dictionary=game.hud.compact_context_details(operator,302,14)
		check(mounted.lines.is_empty() and mounted.lines.get_typed_builtin()==TYPE_STRING,"Mounted gun returns typed empty body lines")
		check(not mounted.action_lines.is_empty(),"Mounted gun keeps the owning player's controls visible")
		roof_gun.exit()
	var mixer = stations.filter(func(station): return station.kind == "mixer")[0]
	var guest = game.players[1]
	guest.position = mixer.position + Vector2(-40, 0)
	guest.focus = mixer
	# Explicit adjacent target: room furniture spacing no longer guarantees overlap.
	var second_target = game._entity("station", mixer.position+Vector2(-24,0))
	second_target.set_process(false)
	var local_details := check_detail(guest, "local P2")
	check(local_details.key == "Enter / X" and local_details.cycle_hint.contains("RB"), "Offline P2 retains its keyboard/controller interaction mapping")
	game.network.active = true
	game.network.is_host = false
	game.network.local_player_id = 2
	game.network.state = "playing"
	game.network.set_process(false)
	game.network.set_physics_process(false)
	var online_details := check_detail(guest, "online P2")
	check(online_details.key == "E" and online_details.cycle_hint.begins_with("F ·") and not online_details.cycle_hint.contains("RB"), "Online P2 receives the local keyboard E/F hints")
	check(online_details.multiple, "The prepared guest really has multiple nearby interaction targets")
	game.network.leave()
	var supply = get_nodes_in_group("supplies").filter(func(stock): return stock.kind == "steel" and not stock.is_queued_for_deletion())[0]
	for worker in game.players:
		worker.focus = supply
		worker.position = supply.position + Vector2(-40, 0)
		worker.selected_kind = supply.kind
		for stocked in [true, false]:
			supply.amount = 12 if stocked else 0
			for carried in [0, 2, worker.capacity()]:
				worker.inventory = {supply.kind:carried} if carried > 0 else {}
				var stock_detail := check_detail(worker, "supply capacity/stock state")
				check(not stock_detail.show_key, "Supply controls remain in the footer instead of covering neighboring world labels with one misleading key")
				check(not stock_detail.action_lines.is_empty(), "Every supply state has a measured action/reason footer")
				if carried > 0:
					var deposit_key := "G" if worker.player_id == 1 else "Num*/L3"
					check(stock_detail.action.replace(" ", "").contains(deposit_key), "Selected cargo shows the owning player's deposit key")
	game.network.active = true
	game.network.is_host = false
	game.network.local_player_id = 2
	game.network.state = "playing"
	guest.inventory = {supply.kind:2}
	guest.selected_kind = supply.kind
	var guest_stock := check_detail(guest, "online guest supply")
	check(not guest_stock.show_key, "Online supply retains focus markers without a duplicate single-key badge")
	check(guest_stock.action.contains("G") and not guest_stock.action.contains("L3"), "Online guest supply deposit uses the local keyboard mapping")
	game.network.leave()
	# Use the real menu callback to verify the text refactor still buys research.
	game.upgrades.points = 12
	game.hud._toggle_upgrades()
	await process_frame
	await process_frame
	var panel = game.hud.upgrade_panel
	panel._select("bunker_workshop")
	var entry: Dictionary = game.upgrades.node_data("bunker_workshop")
	check(panel.node_title_lines(entry).size() <= 2, "Selected technology title fits its actual diagram card")
	check(UiArt.wrap_text(panel._research_title(str(entry.title)), 333, 22).size() <= 2, "Selected technology title fits its detail column")
	for line: String in panel._detail_lines(entry.detail):
		check(measured_width(line, panel.BODY_SIZE) <= panel.DETAIL_RECT.size.x, "Technology description fits before the right panel edge")
	var points_before: int = game.upgrades.points
	check(not panel.purchase_button.disabled, "An affordable technology enables the actual purchase button")
	panel.purchase_button.pressed.emit()
	check(game.upgrades.has_upgrade(entry.id) and game.upgrades.points == points_before - int(entry.cost), "Actual button callback purchases the selected technology once")
	check(panel.purchase_button.disabled, "Purchased technology disables repeat buying")
	paused = false
	check(await CLEANUP.free_scene(game, self), "Context and menu fixture releases its real scene")
	print("CONTEXT LABELS: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
