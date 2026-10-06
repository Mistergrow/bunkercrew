extends SceneTree
## Physical access and finite warehouse transfers across every bunker blueprint.
const Storage = preload("res://scripts/medic_storage.gd")
const Cleanup = preload("res://tests/scene_cleanup.gd")
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("STORAGE FOLLOWUP ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1
		push_error(label)

func stores(kind := "") -> Array:
	return get_nodes_in_group("supplies").filter(func(crate): return crate.game == game and not crate.is_queued_for_deletion() and (kind.is_empty() or crate.kind == kind))

func freeze() -> void:
	game.rounds.running = false
	game.rounds.set_process(false)
	game.expedition.set_physics_process(false)
	game.medic.set_physics_process(false)
	for player in game.players:
		player.set_physics_process(false)
	for station in get_nodes_in_group("stations"):
		if station.game == game:
			station.set_process(false)
	paused = true

func create_world(position_mode: String, build_type: String):
	paused = false
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start_scenario(4, {"environment":"ash_foundry", "position":position_mode, "build_type":build_type})
	freeze()
	for frame in 3:
		await physics_frame
	game.rounds.wave = Balance.TOTAL_WAVES
	check(game.expedition.on_victory(), position_mode + "/" + build_type + ": real victory enters preparation")

func close_world():
	paused = false
	await Cleanup.free_scene(game, self)
	game = null

func place_player(crate: Supply) -> bool:
	var player = game.players[0]
	for offset in [-28.0, 28.0]:
		player.position = crate.position + Vector2(offset, 0)
		if game.medic.navigation.support_at(player.position) and game.medic.navigation.body_clear(player.position) and crate.can_interact(player):
			return true
	return false

func access_matrix():
	var maximum: Dictionary = {}
	for kind: String in Storage.MATERIALS:
		maximum[kind] = CampaignState.MAX_STOCK_PER_KIND
	for position_mode: String in ["left", "center", "right"]:
		for build_type: String in ScenarioRoomCatalog.BUILD_TYPES:
			await create_world(position_mode, build_type)
			var label := position_mode + "/" + build_type
			game.campaign.expedition.garage_stock = maximum.duplicate()
			var started := Time.get_ticks_usec()
			game.expedition._mirror_stock()
			print("STORAGE MATRIX ", label, " crates=", stores().size(), " mirror_usec=", Time.get_ticks_usec() - started)
			check(game.expedition._capture_stock() == maximum, label + ": exact maximum mirror preserves every material")
			var player = game.players[0]
			for kind: String in Storage.MATERIALS:
				var matching: Array = stores(kind)
				check(not matching.is_empty(), label + "/" + kind + ": actual material chest exists")
				if matching.is_empty():
					continue
				var crate: Supply = matching[0]
				check(not game.medic.logistics._route_to(crate).is_empty(), label + "/" + kind + ": real SAN transport can reach chest")
				var accessible := place_player(crate)
				check(accessible, label + "/" + kind + ": player has supported reachable interaction position")
				if not accessible:
					continue
				player.inventory.clear()
				player.selected_kind = kind
				crate.interact(player, Balance.TRANSFER_TIME)
				check(player.inventory.get(kind, 0) == 1 and game.expedition._capture_stock() == maximum, label + "/" + kind + ": ordinary withdrawal transfers exactly one finite unit")
				crate.deposit(player, Balance.TRANSFER_TIME)
				check(player.inventory.is_empty() and game.expedition._capture_stock() == maximum, label + "/" + kind + ": ordinary return preserves all ownership")
			await close_world()

func partial_crate_bound():
	await create_world("left", "bastion")
	game.campaign.expedition.garage_stock = {"sand":CampaignState.MAX_STOCK_PER_KIND}
	game.expedition._mirror_stock()
	check(Storage.stored_amount(game, "sand") == CampaignState.MAX_STOCK_PER_KIND and Storage.reserve_amount(game, "sand") > 0, "Boundary fixture has the exact legal maximum in physical sand chests and finite reserve")
	var matching: Array = stores("sand")
	var crate: Supply = matching[0] if not matching.is_empty() else null
	# At the serialization maximum all safe floor slots may already be used.
	# Shift this actual container's finite quantity into its existing reserve
	# to exercise an empty chest without inventing another placement or unit.
	var emptied := is_instance_valid(crate) and Storage.add_reserve(game, "sand", crate.amount)
	if emptied:
		crate.amount = 0
	check(emptied and Storage.stored_amount(game, "sand") == CampaignState.MAX_STOCK_PER_KIND, "Boundary fixture includes an actual reachable empty physical chest without changing aggregate ownership")
	if is_instance_valid(crate):
		check(place_player(crate), "Empty boundary chest remains physically reachable")
		var player = game.players[0]
		player.inventory = {"sand":1, "glass":1}
		player.selected_kind = "sand"
		check(not Storage.can_deposit(crate), "Partially empty chest respects the aggregate warehouse bound")
		crate.deposit(player, Balance.TRANSFER_TIME)
		check(crate.amount == 0 and player.inventory == {"sand":1, "glass":1} and Storage.stored_amount(game, "sand") == CampaignState.MAX_STOCK_PER_KIND, "Bounded warehouse rejects extra material before taking it from mixed inventory")
		player.inventory.clear()
	await close_world()

func run():
	if not "--no-profile-save" in OS.get_cmdline_user_args() or not "--no-upnp" in OS.get_cmdline_user_args():
		quit(2)
		return
	await access_matrix()
	await partial_crate_bound()
	print("STORAGE FOLLOWUP CHECKS: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
