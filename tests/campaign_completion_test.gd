extends "res://tests/epic_weapons_test.gd"
## Prepared objective completions exercise all12 routes; no full-campaign claim.
func run() -> void:
	InputSetup.install()
	game = WeaponLab.new()
	root.add_child(game)
	game.upgrades = UpgradeSystem.new()
	game.upgrades.game = game
	game.add_child(game.upgrades)
	game.campaign = CampaignState.new("user://unused-completion-test.json", false)
	worker = Fighter.new()
	worker.game = game
	game.add_child(worker)
	worker.progression = PlayerProgression.new()
	worker.add_child(worker.progression)
	weapon = WorkerWeapon.new()
	weapon.name = "WorkerWeapon"
	worker.add_child(weapon)
	weapon.set_physics_process(false)
	check(game.campaign.begin_new({"environment":"ash_foundry", "position":"left", "build_type":"bastion"}, ["mara"], 1), "New campaign starts at required first bunker")
	var main_ids: Array = []
	for entry: Dictionary in CampaignCatalog.NODES:
		if CampaignCatalog.site_kind(entry.id) == "bunker": main_ids.append(entry.id)
	check(main_ids.size() == 8 and not CampaignCatalog.all_complete(main_ids), "Eight defended bunkers alone do not finish the campaign")
	var summary := CampaignCatalog.completion_summary(main_ids)
	check(summary.secured == 8 and summary.total == 12 and summary.outposts == 0 and summary.outposts_total == 4 and summary.remaining.size() == 4, "Completion summary explicitly counts all four strategic outposts")
	var sequence := ["last_shift", "harbor", "dam_vault", "quarry", "refinery_archive", "steelworks", "rail_yard", "radar_archive", "canyon", "buried_archive", "power_station", "mountain_pass"]
	for index in sequence.size():
		var id: String = sequence[index]
		if index > 0:
			if int(CampaignCatalog.node(id).cost) > 0: check(game.campaign.unlock_route(id), "Required strategic route unlocks with legitimately banked salvage")
			check(game.campaign.select_destination(id), "Route remains reachable from previous bunker or side site: " + id)
			check(not game.campaign.begin_journey(id).is_empty(), "Selected site starts an actual campaign journey")
			check(game.campaign.arrive_at_destination() and game.campaign.secure_destination(), "Cleared approach permits site entry")
		var mission := game.campaign.mission_start()
		check(not mission.is_empty() and mission.site_kind == CampaignCatalog.site_kind(id), "Mission carries its actual bunker/outpost objective kind")
		check(game.campaign.reserve_drop("prepared_core_reward", 3) and game.campaign.collect_salvage("prepared_core_reward", 3), "Finite recovered core reward funds later mandatory branches")
		var result: Dictionary
		if mission.site_kind == "outpost":
			check(mission.objective.hold_time == 5.0 and mission.objective.guards >= 8, "Strategic site declares five-second facility objective and finite guard count")
			check(game.campaign.complete_mission(mission.id, 20, [worker], game.upgrades).is_empty(), "Outpost cannot substitute twenty-wave victory for facility capture")
			check(game.campaign.complete_outpost(mission.id, 1, true, [worker], game.upgrades).is_empty(), "Remaining guard blocks strategic site completion")
			check(game.campaign.complete_outpost(mission.id, 0, false, [worker], game.upgrades).is_empty(), "Unsecured facility blocks strategic site completion")
			result = game.campaign.complete_outpost(mission.id, 0, true, [worker], game.upgrades)
			check(game.campaign.blueprints.has(CampaignCatalog.node(id).blueprint), "Securing strategic facility actually grants its permanent blueprint")
			check(game.campaign.complete_outpost(mission.id, 0, true, [worker], game.upgrades).is_empty(), "Strategic objective cannot award a second reward")
		else:
			check(game.campaign.complete_outpost(mission.id, 0, true, [worker], game.upgrades).is_empty(), "Ordinary bunker cannot bypass wave20 through the short-outpost API")
			check(game.campaign.complete_mission(mission.id, 19, [worker], game.upgrades).is_empty(), "Defended bunker still requires wave20")
			result = game.campaign.complete_mission(mission.id, 20, [worker], game.upgrades)
		check(not result.is_empty() and result.all_complete == (index == 11), "Final victory fires only after the twelfth distinct secured site")
		check(CampaignState.valid_checkpoint(game.campaign.checkpoint()), "Each site transition remains a valid durable checkpoint")
	summary = CampaignCatalog.completion_summary(game.campaign.completed)
	check(summary.all_complete and summary.bunkers == 8 and summary.outposts == 4 and summary.remaining.is_empty(), "Final summary reports all required bunkers and strategic sites")
	check(game.campaign.expedition.claimed_stops.is_empty() and game.campaign.expedition.epic_weapons.is_empty(), "Roadside loot stops and epic weapons remain optional for final victory")
	await preload("res://tests/scene_cleanup.gd").free_scene(game, self)
	print("CAMPAIGN COMPLETION: %d/%d passed" % [checks-failures, checks])
	quit(1 if failures else 0)
