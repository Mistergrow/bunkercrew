extends SceneTree
## Real production/repair/SAN-1 code with isolated stock and a controlled victory gate.
class VictoryGate extends Node:
	var unlocked := false
	var manageable := true
	func can_manage() -> bool: return manageable
	func vehicle_unlocked() -> bool: return unlocked
	func outpost_pending() -> bool: return false
class Session extends Node:
	var active := false
	var is_host := true
class RoundState extends Node:
	var wave := 1
class ResearchLab extends Node2D:
	var upgrades: UpgradeSystem
	var core: BunkerCore
	var campaign: CampaignState
	var expedition := VictoryGate.new()
	var network := Session.new()
	var rounds := RoundState.new()
	func sound(_kind): pass
	func fx(_at, _color, _count): pass
	func notify(_value): pass
	func on_core_destroyed(): pass
class Stock extends Node:
	var inventory: Dictionary = {}
	func take_item(kind: String, count: int) -> bool:
		if int(inventory.get(kind, 0)) < count: return false
		inventory[kind] -= count
		return true
var game: ResearchLab
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func run() -> void:
	game = ResearchLab.new()
	root.add_child(game)
	for node in [game.expedition, game.network, game.rounds]: game.add_child(node)
	game.upgrades = UpgradeSystem.new()
	game.upgrades.game = game
	game.add_child(game.upgrades)
	game.core = BunkerCore.new()
	game.core.game = game
	game.add_child(game.core)
	var research := game.upgrades
	var base_ids: Array = research.nodes_for_category(0).map(func(entry: Dictionary): return str(entry.id))
	var expected_base := ["bunker_workshop","medic_logistics","medic_collection","bunker_armor","bunker_fortress","perimeter_automation","core_resilience","repair_tools","blast_baffles","precision_lines","medical_station","logistics_drive"]
	check(base_ids==expected_base and research.nodes_for_category(3).size()==12,"The twelve base improvements, including SAN-1 collection, and twelve vehicle nodes have explicit categories")
	var crew_ids: Array = research.nodes_for_category(2).map(func(entry: Dictionary): return str(entry.id))
	check(crew_ids==["bunker_dance","bunker_dance_2","bunker_dance_3","bunker_dance_4","bunker_dance_5","boots","harness","craftsmanship"],"All five portable SAN-1 dance stages belong to the crew category with personal equipment")
	var ids: Array = []
	for entry: Dictionary in UpgradeSystem.NODES:
		check(not ids.has(entry.id), "Unique research ID " + str(entry.id))
		ids.append(entry.id)
		check(str(entry.parent).is_empty() or not research.node_data(entry.parent).is_empty(), "Existing prerequisite " + str(entry.id))
	research.points = 100
	check(not research.purchase("not_research") and research.points == 100, "Unknown research cannot spend points")
	check(not research.purchase("core_resilience"), "Core reinforcement requires the real workshop parent")
	check(not research.purchase("convoy_mg"), "Vehicle research stays locked before first twenty-wave victory")
	check(research.purchase("bunker_workshop"), "Workshop unlocks base fabrication")
	var maximum := game.core.max_hp
	game.core.hp -= 70.0
	check(research.purchase("core_resilience") and game.core.max_hp == maximum + 120.0 and game.core.hp == maximum + 50.0, "Core gains exactly120 capacity while retaining70 damage")
	research.apply_world_effects()
	check(game.core.max_hp == maximum + 120.0, "Repeated world refresh cannot duplicate core reinforcement")
	var before_points := research.points
	check(not research.purchase("core_resilience") and research.points == before_points, "Owned research cannot spend again")
	check(not research.purchase("blast_baffles"), "Later base armor respects its wave gate")
	check(research.purchase("repair_tools"), "Core tools unlock at parent")
	var worker := Stock.new()
	game.add_child(worker)
	worker.inventory = {"steel":1}
	game.core.hp = game.core.max_hp - Balance.CORE_REPAIR - 20.0
	var hp_before := game.core.hp
	game.core.interact(worker, Balance.CORE_REPAIR_TIME / 1.35 + .001)
	check(is_equal_approx(game.core.hp, hp_before + Balance.CORE_REPAIR) and worker.inventory.steel == 0, "Actual improved core repair keeps exact material cost and repair amount")
	var wall := DefenseWall.new()
	wall.initial_state = DefenseWall.State.HARD
	wall.game = game
	game.add_child(wall)
	wall.hp -= Balance.WALL_REPAIR + 10.0
	worker.inventory = {"concrete":1}
	hp_before = wall.hp
	wall.interact(worker, Balance.WALL_WORK_TIME / 1.35 + .001)
	check(is_equal_approx(wall.hp, hp_before + Balance.WALL_REPAIR) and worker.inventory.concrete == 0, "Actual wall repair is faster without free concrete")
	game.rounds.wave = 8
	check(research.purchase("blast_baffles"), "Core protection becomes available at wave8")
	hp_before = game.core.hp
	game.core.take_damage(100.0)
	check(is_equal_approx(game.core.hp, hp_before - 85.0), "Core takes85 from actual100 damage after protection")
	var station := ProductionStation.new()
	station.game = game
	check(research.purchase("precision_lines"), "Production upgrade unlocks after workshop")
	check(is_equal_approx(station.duration(), float(station.recipe().time) * .68), "Actual production duration stacks20 and15 percent multiplicatively")
	game.campaign = CampaignState.new("user://unused-research.json", false)
	game.campaign.active = true
	game.campaign.blueprints = ["precision_foundry", "repair_matrix"]
	check(is_equal_approx(station.duration(), float(station.recipe().time) * .68 * .85), "Earned foundry blueprint stacks without replacing site research")
	check(is_equal_approx(research.repair_multiplier(), 1.35) and is_equal_approx(game.core.repair_amount(), Balance.CORE_REPAIR * 1.25), "Base tools improve speed while persistent repair blueprint improves core repair amount")
	station.free()
	var medic := FieldMedic.new()
	medic.game = game
	check(research.purchase("medical_station") and is_equal_approx(medic.refill_duration(), MedicalCatalog.REFILL_TIME * .7), "Actual SAN-1 refill duration follows medical station")
	check(research.purchase("medic_logistics") and research.purchase("logistics_drive"), "Logistics drive requires transport branch")
	var logistics = preload("res://scripts/medic_logistics.gd").new(medic)
	check(is_equal_approx(logistics.handoff_time(), 1.25 * .75) and is_equal_approx(logistics.trip_delay(), 3.0 * .75), "Both robot handoff and between-trip delay use improved timings")
	logistics = null
	medic.free()
	game.expedition.unlocked = true
	game.expedition.manageable = false
	check(not research.purchase("convoy_mg"), "Vehicle upgrades cannot be purchased mid-journey or during defense")
	game.expedition.manageable = true
	check(not research.purchase("convoy_armor_heavy"), "Heavy vehicle armor requires first armor level")
	for id: String in CampaignCatalog.VEHICLE_UPGRADES:
		check(research.purchase(id), "Vehicle upgrade purchases after victory: " + id)
	for id: String in CampaignCatalog.VEHICLE_PREREQUISITES:
		check(not CampaignCatalog.valid_vehicle_research([id]), "Persisted vehicle research requires real parent: " + id)
		check(str(research.node_data(id).parent)==str(CampaignCatalog.VEHICLE_PREREQUISITES[id]), "UI parent matches persistence validator: " + id)
	for id: String in ["convoy_handling","convoy_transmission","convoy_reload","convoy_stabilizer","convoy_support","convoy_blast_lining"]:
		var truck := {"unlocked":true,"hp":600.0,"fuel":12.0,"cargo":{},"upgrades":[id],"ammo":0,"reserve":0}
		check(CampaignState.valid_vehicle(truck)==(id=="convoy_handling"), "Vehicle snapshot rejects missing dependency except valid root: " + id)
	check(CampaignCatalog.valid_vehicle_research(CampaignCatalog.VEHICLE_UPGRADES), "Complete research tree passes persisted dependency validation")
	check(not CampaignCatalog.valid_vehicle_research(["convoy_mg","convoy_mg"]) and not CampaignCatalog.valid_vehicle_research(["fake"]), "Duplicate and unknown research cannot enter save data")
	var vehicle_stats := CampaignCatalog.vehicle_stats(research.persistent_owned())
	check(vehicle_stats.mounted_mg and vehicle_stats.max_hp==1100.0 and vehicle_stats.cargo_capacity==36 and vehicle_stats.fuel_capacity==50.0 and vehicle_stats.fuel_multiplier==.75,"Canonical vehicle stats reflect purchased portable research")
	var portable := research.persistent_owned()
	check(portable.size() == 12 and not portable.has("core_resilience") and portable.has("convoy_mg"), "Portable research excludes every local base improvement")
	research.points = 0
	check(not research.purchase("boots") and research.points == 0, "Insufficient points reject purchases without debt")
	research.points = 10
	game.network.active = true
	game.network.is_host = false
	check(not research.purchase("boots") and research.points == 10, "Off-host direct purchases cannot mutate shared research")
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game, self), "Research fixture releases all runtime nodes")
	print("BASE RESEARCH: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
