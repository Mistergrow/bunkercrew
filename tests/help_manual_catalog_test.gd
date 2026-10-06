extends SceneTree
## Semantic guidance checks plus read-only queries against an actual main scene.
const Catalog := preload("res://scripts/help_manual_catalog.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const MAIN := preload("res://scenes/main.tscn")
var checks := 0
var failures := 0

class GameProbe extends Node:
	var started := true
	var players: Array = []
	var network: Node
	var core: Node
	var rounds: Node
	var scenario_bunker: Node
	var expedition: Node
	var story: Node
	var flak_station: Node
	var scenario_options: Dictionary = {}

class SessionProbe extends Node:
	var active := false
	var local_player_id := 1

class WorkerProbe extends Node:
	var player_id := 1
	var medical: Node
	var focus: Node
	var mounted_turret: Node
	var inventory: Dictionary = {}
	func capacity() -> int: return Balance.CARRY_CAPACITY
	func carried_count() -> int:
		var amount := 0
		for value in inventory.values(): amount += int(value)
		return amount

class MedicalProbe extends Node:
	var state := "healthy"
	func incapacitated() -> bool: return state in ["downed", "critical"]

class WeaponProbe extends Node:
	var reserve := 90
	var open_pack := 0
	var ammo := 30
	func current_ammo() -> int: return ammo

class StoryProbe extends Node:
	var blocked := false
	func blocks_build() -> bool: return blocked
	func objective() -> String: return LocaleText.text("Baue die Mauer vor dem Bunker.")

class ExpeditionProbe extends Node:
	var stage := "defense"
	var vehicle: Node

class VehicleProbe extends Node:
	var journey_state: Dictionary = {"phase":"garage"}

class RoundProbe extends Node:
	var wave := 1
	var phase := "build"

class MountProbe extends Node:
	var personal := false
	func allows_personal_weapon() -> bool: return personal

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, detail: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(detail)

func _has_page(id: String) -> bool:
	for page: Dictionary in Catalog.PAGES:
		if page.id == id: return true
	return false

func _advice(game: Node, id: String, reason: String) -> void:
	var advice := Catalog.current_advice(game)
	check(advice.id == id, "%s (%s, expected %s)" % [reason, advice.id, id])
	check(_has_page(str(advice.page)) and not str(advice.title).is_empty() and not str(advice.body).is_empty(), reason + " links a complete existing manual page")

func _run() -> void:
	LocaleText.set_locale("de", false)
	var ids: Array[String] = []
	for page: Dictionary in Catalog.PAGES:
		check(not ids.has(str(page.id)) and not str(page.title).is_empty() and not str(page.detail).is_empty(), "Six unique, described manual pages")
		ids.append(str(page.id))
	check(ids == ["first_shift","controls","workshop","construction","crew","travel"], "Stable page contract for native panel")
	check(Catalog.sections("unknown").is_empty(), "Unknown page has a safe empty result")
	_advice(null, "first_shift", "Missing world gives menu-safe guidance")
	var fixture := GameProbe.new()
	root.add_child(fixture)
	var session := SessionProbe.new()
	fixture.network = session
	fixture.add_child(session)
	var rounds := RoundProbe.new()
	fixture.rounds = rounds
	fixture.add_child(rounds)
	var core := BunkerCore.new()
	fixture.core = core
	fixture.add_child(core)
	var story := StoryProbe.new()
	fixture.story = story
	fixture.add_child(story)
	var expedition := ExpeditionProbe.new()
	fixture.expedition = expedition
	fixture.add_child(expedition)
	var vehicle := VehicleProbe.new()
	expedition.vehicle = vehicle
	fixture.add_child(vehicle)
	var workers: Array[WorkerProbe] = []
	var medics: Array[MedicalProbe] = []
	var weapons: Array[WeaponProbe] = []
	for slot in 2:
		var worker := WorkerProbe.new()
		worker.player_id = slot + 1
		fixture.add_child(worker)
		var medical := MedicalProbe.new()
		worker.medical = medical
		worker.add_child(medical)
		var weapon := WeaponProbe.new()
		weapon.name = "WorkerWeapon"
		worker.add_child(weapon)
		workers.append(worker)
		medics.append(medical)
		weapons.append(weapon)
	fixture.players.assign(workers)
	_advice(fixture, "build_pause", "Healthy early crew receives preparation guidance")
	medics[0].state = "downed"
	_advice(fixture, "self_downed", "Offline player one is selected")
	session.active = true
	session.local_player_id = 2
	_advice(fixture, "crew_downed", "Online advice uses local player two, not the host")
	medics[1].state = "critical"
	_advice(fixture, "self_downed", "Own critical state outranks another downed worker")
	medics[0].state = "healthy"
	medics[1].state = "healthy"
	workers[0].inventory = {"sand":Balance.CARRY_CAPACITY}
	_advice(fixture, "build_pause", "Host inventory never becomes guest inventory advice")
	workers[1].inventory = {"ore":Balance.CARRY_CAPACITY}
	_advice(fixture, "inventory_full", "Own actual capacity drives inventory guidance")
	workers[1].inventory.clear()
	weapons[1].ammo = 0
	_advice(fixture, "reload", "Actual reserve distinguishes reload from exhausted ammo")
	weapons[1].reserve = 0
	_advice(fixture, "ammo_supply", "Exhausted selected weapon suggests physical supply")
	workers[1].inventory = {"ammo":1}
	_advice(fixture, "reload", "Carried paid ammo is recognized before sending worker to supply")
	workers[1].inventory.clear()
	weapons[1].open_pack = 1
	_advice(fixture, "reload", "Owned partly consumed ammo pack is recognized")
	weapons[1].open_pack = 0
	var mount := MountProbe.new()
	fixture.add_child(mount)
	workers[1].mounted_turret = mount
	_advice(fixture, "build_pause", "Mounted shared gun is not confused with holstered empty handweapon")
	mount.personal = true
	_advice(fixture, "ammo_supply", "Convoy passenger retains personal weapon guidance")
	workers[1].mounted_turret = null
	weapons[1].ammo = 30
	story.blocked = true
	_advice(fixture, "story_objective", "Only actual blocking story gate supplies objective advice")
	check(Catalog.current_advice(fixture).body == story.objective(), "Actual world story objective is reused")
	core.hp = core.max_hp * .2
	_advice(fixture, "critical_core", "Positive critical core outranks routine story work")
	vehicle.journey_state.phase = "repair"
	_advice(fixture, "tire_repair", "Real repair phase suppresses hidden bunker advice")
	medics[1].state = "downed"
	_advice(fixture, "self_downed", "Actual incapacity outranks tool work")
	medics[1].state = "healthy"
	vehicle.journey_state.phase = "garage"
	story.blocked = false
	expedition.stage = "preparation"
	_advice(fixture, "prepare_convoy", "Preparation omits hidden critical bunker")
	expedition.stage = "travel"
	_advice(fixture, "road_defense", "Road stage gives defense guidance")
	expedition.stage = "defense"
	core.hp = core.max_hp
	var station := ProductionStation.new()
	station.output_amount = 2
	fixture.add_child(station)
	workers[1].focus = station
	_advice(fixture, "collect_output", "Real finished station output needs unloading")
	workers[1].focus = null
	var flak := FlakStation.new()
	fixture.flak_station = flak
	fixture.add_child(flak)
	flak.available = true
	rounds.wave = 5
	_advice(fixture, "build_pause", "Flak advice never arrives before actual catalog wave")
	rounds.wave = int(FlakStation.SPECS[1].wave)
	_advice(fixture, "build_flak", "Catalog unlock and real unbuilt flak select construction guidance")
	flak.built = true
	var turret := FlakTurret.new()
	fixture.add_child(turret)
	flak.turret = turret
	turret.ammo = 0
	turret.reserve = 0
	_advice(fixture, "flak_ammo", "Built live flak with zero ammo is not mistaken for loaded air defense")
	turret.reserve = 1
	_advice(fixture, "build_pause", "Existing reserve is acknowledged without inventing ammo")
	var bunker := ScenarioBunker.new()
	fixture.scenario_bunker = bunker
	var site := ScenarioRoomSite.new()
	site.game = fixture
	site.bunker = bunker
	bunker.modules.append(site)
	fixture.add_child(site)
	_advice(fixture, "next_room", "Actual unlocked room site links excavate/support/build sequence")
	check(Catalog.current_advice(fixture).body.contains(LocaleText.text(str(site.spec().title))), "Next room advice uses actual room catalog identity")
	rounds.phase = "attack"
	_advice(fixture, "defend", "Active attack outranks unfinished room construction")
	flak.built = false
	workers[1].focus = station
	_advice(fixture, "defend", "Active attack outranks routine flak building and collecting machine output")
	workers[1].focus = null
	flak.built = true
	var online_rows := Catalog.controls(fixture)
	check(online_rows.size() == 20, "Complete controls cover fieldwork, storage, travel, social and pause")
	for row: Dictionary in online_rows:
		check(row.primary == row.secondary, "Online participant uses own P1 input bindings")
	session.active = false
	check(Catalog.controls(fixture)[0].primary != Catalog.controls(fixture)[0].secondary, "Local partner retains separate bindings")
	var prior_recipes: Dictionary = Balance.RECIPES.duplicate(true)
	var prior_rooms: Array = ScenarioRoomCatalog.ROOMS.duplicate(true)
	var prior_research: Array = UpgradeSystem.NODES.duplicate(true)
	var prior_vehicle: Dictionary = vehicle.journey_state.duplicate(true)
	for page: Dictionary in Catalog.PAGES:
		var content := Catalog.sections(str(page.id), fixture)
		check(content.size() >= 3, "Each page explains complete existing workflows: " + str(page.id))
		for section: Dictionary in content:
			check(not str(section.title).is_empty() and not str(section.body).is_empty(), "Manual section has readable title and body")
	check(Balance.RECIPES == prior_recipes and ScenarioRoomCatalog.ROOMS == prior_rooms and UpgradeSystem.NODES == prior_research and vehicle.journey_state == prior_vehicle, "All queries preserve gameplay catalogs and live travel state")
	var workshop_text := JSON.stringify(Catalog.sections("workshop"))
	for recipe: Dictionary in Balance.RECIPES.values():
		check(workshop_text.contains(str(recipe.label)), "Production recipes follow canonical station labels")
	var scenario_text := JSON.stringify(Catalog.sections("construction", fixture))
	for room: Dictionary in ScenarioRoomCatalog.ROOMS:
		check(scenario_text.contains(str(room.title)), "Current room costs and unlocks are documented")
	fixture.scenario_bunker = null
	var classic_text := JSON.stringify(Catalog.sections("construction", fixture))
	check(classic_text.contains("Klassischer Bunker") and not classic_text.contains("Gesamtmaterial"), "Classic world gets its own build sequence, never scenario room totals")
	expedition.stage = "travel"
	check(not JSON.stringify(Catalog.sections("construction", fixture)).contains("Klassischer Bunker"), "Road world with no scenario bunker is never labeled Classic")
	expedition.stage = "stop"
	check(not JSON.stringify(Catalog.sections("first_shift", fixture)).contains("6 · Klassischer Bunker"), "Roadside stop retains scenario guidance")
	expedition.stage = "defense"
	fixture.scenario_options = {"environment":"ash_foundry"}
	check(not JSON.stringify(Catalog.sections("construction", fixture)).contains("Klassischer Bunker"), "Scenario option remains authoritative during missing-node transitions")
	fixture.scenario_options.clear()
	bunker.free()
	rounds.phase = "build"
	workers[0].inventory.clear()
	station.queue_free()
	workers[0].focus = station
	_advice(fixture, "build_pause", "Queued focus cannot enter stale output guidance")
	await process_frame
	_advice(fixture, "build_pause", "Freed focus safely ignored on actual focus lookup path")
	workers[0].free()
	_advice(fixture, "build_pause", "Freed worker is skipped before medical/inventory/weapon reads")
	flak.free()
	_advice(fixture, "build_pause", "Freed flak and turret references are safely skipped")
	fixture.started = false
	_advice(fixture, "first_shift", "Returned menu does not use stale active-world props")
	var scene = MAIN.instantiate()
	root.add_child(scene)
	await process_frame
	scene.start_scenario(1, {"environment":"ash_foundry", "build_type":"bastion", "position":"left", "mode":"free"})
	await process_frame
	var inventories: Array = []
	for player in scene.players: inventories.append(player.inventory.duplicate(true))
	var hp_before: float = scene.core.hp
	var time_before: float = scene.rounds.time_left
	var wave_before: int = scene.rounds.wave
	var points_before: int = scene.upgrades.points
	for page: Dictionary in Catalog.PAGES:
		check(not Catalog.sections(str(page.id), scene).is_empty(), "Actual main world supports manual page " + str(page.id))
		check(not Catalog.current_advice(scene).is_empty(), "Actual main world provides read-only contextual guidance")
	check(scene.core.hp == hp_before and scene.rounds.time_left == time_before and scene.rounds.wave == wave_before and scene.upgrades.points == points_before, "Manual does not pause/advance waves, heal core or spend shared research")
	check(scene.players[0].inventory == inventories[0], "Manual cannot manufacture, transfer or erase physical cargo")
	check(await Cleanup.free_scene(scene, self), "Actual scene and audio handles cleaned")
	fixture.queue_free()
	await process_frame
	print("Help manual catalog: %d/%d checks passed" % [checks-failures, checks])
	quit(1 if failures > 0 else 0)
