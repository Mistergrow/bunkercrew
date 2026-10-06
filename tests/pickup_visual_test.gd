extends SceneTree
## Real death, settled loot, collection and host snapshots must retain their
## gameplay meaning when pickup presentation changes.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const World := preload("res://scripts/network_world.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func frames(count := 3) -> void:
	for frame in count:
		await process_frame
		await physics_frame

func scene():
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.start_scenario(1,{"environment":"frozen_rail_yard","build_type":"bastion","position":"left"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.set_process(false)
	game.medic.set_physics_process(false)
	game.players[0].set_physics_process(false)
	game.players[0].position = Vector2(950,430)
	return game

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	AudioServer.set_bus_mute(0,true)
	var host = scene()
	# Keep the reward/replication fixture on open ground. The courtyard fence
	# now occupies the old x=1200 death/drop/worker positions; embedded drops
	# and its real access barrier are covered by pickup_support_test separately.
	var enemy = host._entity("enemy",Vector2(1350,430),{"kind":"strider","wave":3})
	enemy.set_physics_process(false)
	var expected_scrap: int = enemy.profile.scrap
	var expected_points: int = enemy.profile.cores
	enemy.take_damage(enemy.max_hp+1)
	await frames(24)
	var piles := get_nodes_in_group("pickups")
	check(piles.size() == 2, "A real defeated machine leaves exactly its two loot types")
	if piles.size() != 2:
		await Cleanup.free_scene(host,self)
		quit(1)
		return
	var scraps := piles.filter(func(pile): return pile.kind == "scrap")
	var cores := piles.filter(func(pile): return pile.kind == "core")
	check(scraps.size() == 1 and cores.size() == 1, "Industrial artwork preserves scrap and technology identities")
	if scraps.size() != 1 or cores.size() != 1:
		await Cleanup.free_scene(host,self)
		quit(1)
		return
	var scrap: ResourcePickup = scraps[0]
	var core: ResourcePickup = cores[0]
	check(scrap.amount == expected_scrap and core.amount == expected_points, "Catalog reward quantities survive the visual replacement")
	for pile in piles:
		check(absf(pile.position.y-429.5)<1.0 and pile.fall_speed == 0.0, "Actual loose loot settles on the platform surface")
		pile.set_physics_process(false)
	var data_drops := get_nodes_in_group("campaign_salvage")
	check(data_drops.size() == 1, "A real wave-three enemy issues one campaign data reward")
	if data_drops.size() != 1:
		await Cleanup.free_scene(host,self)
		quit(1)
		return
	var data: CampaignSalvage = data_drops[0]
	data.set_physics_process(false)
	check(data.amount == 1 and data.claim_id == host.campaign.mission_id and absf(data.position.y-429.5)<1.0, "Grounded campaign data preserves the reserved mission claim")
	var authority := World.new()
	authority.bind(host)
	var before: Dictionary = authority.capture()
	check(before.entities.filter(func(record): return record.type == "resource_pickup").size() == 2, "Host snapshot includes both real drops")
	check(before.entities.filter(func(record): return record.type == "campaign_salvage").size() == 1, "Campaign reward uses its existing independent network identity")
	var worker = host.players[0]
	worker.position = scrap.position+Vector2(-30,0)
	check(scrap.can_interact(worker), "Grounded scrap is manually collectible")
	check(not core.can_interact(worker), "Recovered technology uses automatic collection, not carried inventory")
	scrap.interact(worker,0.016)
	check(int(worker.inventory.get("scrap",0)) == expected_scrap and scrap.amount == 0, "Collecting scrap conserves material and consumes the pile")
	var points_before: int = host.upgrades.points
	worker.position = core.position+Vector2(-25,0)
	core._collect_upgrade_points()
	check(host.upgrades.points == points_before+expected_points and core.amount == 0, "Recovered technology credits the shared upgrade pool exactly once")
	core._collect_upgrade_points()
	check(host.upgrades.points == points_before+expected_points and not worker.inventory.has("core"), "Repeated contact cannot duplicate points or create cargo crystals")
	check(data.collect(false) and host.campaign.mission_salvage == 1, "Recovered data credits its reserved campaign reward")
	check(not data.collect(false) and host.campaign.mission_salvage == 1, "Repeated data collection cannot duplicate route rewards")
	await frames()
	var after: Dictionary = authority.capture()
	check(after.entities.filter(func(record): return record.type == "resource_pickup").is_empty(), "Collected drops are absent from the next authoritative snapshot")
	check(await Cleanup.free_scene(host,self), "Host fixture releases without touching player saves")
	var guest = scene()
	var replica := World.new()
	replica.bind(guest)
	check(replica.apply(before), "Guest accepts the ordinary existing pickup schema: "+replica.last_error)
	var guest_piles := get_nodes_in_group("pickups")
	check(guest_piles.size() == 2, "Guest reconstructs both grounded loot types")
	var guest_data := get_nodes_in_group("campaign_salvage")
	check(guest_data.size() == 1 and not guest_data[0].is_physics_processing(), "Guest also reconstructs one frozen campaign data object")
	for pile in guest_piles:
		check(not pile.is_physics_processing() and pile.amount > 0, "Guest presentation cannot collect or simulate host loot independently")
		if pile.kind == "core": guest.players[0].position = pile.position
	var guest_points: int = guest.upgrades.points
	await frames(8)
	check(guest.upgrades.points == guest_points and get_nodes_in_group("pickups").size() == 2, "Overlapping a replica module cannot award duplicate technology")
	check(replica.apply(after), "Collection snapshot is accepted by the guest: "+replica.last_error)
	await frames()
	check(get_nodes_in_group("pickups").is_empty(), "Guest removes both consumed loot objects")
	check(get_nodes_in_group("campaign_salvage").is_empty(), "Guest also removes the collected campaign data object")
	check(guest.upgrades.points == points_before+expected_points and int(guest.players[0].inventory.get("scrap",0)) == expected_scrap, "Shared points and physical cargo agree after host collection")
	check(await Cleanup.free_scene(guest,self), "Guest fixture releases cleanly")
	print("PICKUP VISUAL GAMEPLAY: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
