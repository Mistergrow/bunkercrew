class_name CampaignCatalog
extends RefCounted
## Secured bunkers unlock routes. Optional roadside stops are finite encounters.
const ENTRY := "last_shift"
const PERSONAL_UPGRADES := ["boots", "harness", "craftsmanship", "weapon_handling", "shotgun", "arcgun", "weapon_magazines", "weapon_bolt", "weapon_sights", "weapon_choke", "weapon_capacitor", "weapon_pouches"]
const BLUEPRINTS := {
	"reinforced_core":{"title":"VERBUNDKERN", "detail":"Jeder neue Bunkerkern erhält 180 zusätzliche LP."},
	"precision_foundry":{"title":"PRÄZISIONSFORMEN", "detail":"Alle Produktionsrezepte brauchen 15 % weniger Zeit."},
	"siege_optics":{"title":"BELAGERUNGSOPTIK", "detail":"Dachgeschütze und Flak verursachen 15 % mehr Schaden."},
	"repair_matrix":{"title":"REPARATURMATRIX", "detail":"Eine Kernreparatur stellt 25 % mehr LP mit demselben Material her."},
}
const NODES := [
	{"id":"last_shift", "title":"BUNKERCREW", "environment":"ash_foundry", "parent":"", "cost":0, "blueprint":"", "map":[0.12,0.70], "detail":"Der erste Halt. Sichere den Ausgangspunkt der Reise."},
	{"id":"harbor", "title":"VERLASSENER HAFEN", "environment":"abandoned_harbor", "parent":"last_shift", "cost":0, "blueprint":"", "map":[0.25,0.78], "detail":"Zwischen Kränen und rostenden Docks führt die Küstenroute weiter."},
	{"id":"quarry", "title":"BASALTBRUCH", "environment":"basalt_quarry", "parent":"harbor", "cost":0, "blueprint":"", "map":[0.37,0.59], "detail":"Ein aufgelassener Steinbruch schützt den Weg ins Landesinnere."},
	{"id":"steelworks", "title":"VERWACHSENES STAHLWERK", "environment":"overgrown_steelworks", "parent":"quarry", "cost":0, "blueprint":"", "map":[0.46,0.38], "detail":"Überwucherte Fertigungshallen liegen an der alten Versorgungsstrecke."},
	{"id":"rail_yard", "title":"GEFRORENER RANGIERHOF", "environment":"frozen_rail_yard", "parent":"steelworks", "cost":0, "blueprint":"", "map":[0.60,0.24], "detail":"Die Bahntrasse über die Frostgrenze ist der nächste sichere Korridor."},
	{"id":"canyon", "title":"EISENSCHLUCHT", "environment":"iron_canyon", "parent":"rail_yard", "cost":0, "blueprint":"", "map":[0.71,0.43], "detail":"Rostrote Felsen und alte Förderbrücken führen zum Kraftwerk."},
	{"id":"power_station", "title":"GEFLUTETES KRAFTWERK", "environment":"flooded_power_station", "parent":"canyon", "cost":0, "blueprint":"", "map":[0.78,0.63], "detail":"Das letzte Netz wartet hinter den versunkenen Turbinenhallen."},
	{"id":"mountain_pass", "title":"GEBIRGSPASS", "environment":"mountain_pass", "parent":"power_station", "cost":0, "blueprint":"", "map":[0.91,0.31], "detail":"Der letzte Hauptweg führt über den Pass. Sichere die Evakuierungsroute."},
	{"id":"dam_vault", "title":"STURMSTAUDAMM", "environment":"storm_dam", "parent":"harbor", "cost":3, "blueprint":"reinforced_core", "map":[0.19,0.48], "detail":"Entschlüssle die Wartungsroute. Im Damm liegt der Bauplan für den Verbundkern."},
	{"id":"refinery_archive", "title":"SCHWEFELRAFFINERIE", "environment":"sulfur_refinery", "parent":"quarry", "cost":5, "blueprint":"precision_foundry", "map":[0.38,0.83], "detail":"Räume die Raffinerie und sichere das Formenarchiv für den weiteren Wiederaufbau."},
	{"id":"radar_archive", "title":"RADARHÖHEN", "environment":"radar_highlands", "parent":"rail_yard", "cost":7, "blueprint":"siege_optics", "map":[0.53,0.08], "detail":"Die Höhenstation bewahrt Zieloptiken für Geschütze und Flak."},
	{"id":"buried_archive", "title":"VERSCHÜTTETE GROSSFABRIK", "environment":"buried_megafactory", "parent":"canyon", "cost":4, "blueprint":"repair_matrix", "map":[0.87,0.81], "detail":"Eine gesperrte Tiefenroute führt zu einer industriellen Reparaturmatrix."},
]

const OUTPOST_OBJECTIVES := {
	"dam_vault":{"id":"dam_control", "title":"SCHLEUSENSTEUERUNG SICHERN", "detail":"Schalte die verbliebene Besatzung aus und aktiviere die Schleusensteuerung. Der Verbundkern-Bauplan wird für alle folgenden Bunker geborgen.", "hold_time":5.0, "guards":8},
	"refinery_archive":{"id":"foundry_archive", "title":"FORMENARCHIV SICHERN", "detail":"Räume die Raffinerie und sichere das Formenarchiv. Präzisionsformen beschleunigen die Produktion in allen weiteren Bunkern.", "hold_time":5.0, "guards":10},
	"radar_archive":{"id":"radar_array", "title":"RADARSTATION SICHERN", "detail":"Besiege die Wachmannschaft und sichere die Zieloptiken der Radarstation. Die Besatzung kann anschließend zur Hauptroute zurückkehren.", "hold_time":5.0, "guards":12},
	"buried_archive":{"id":"repair_archive", "title":"REPARATURARCHIV SICHERN", "detail":"Räume das Werksgelände und aktiviere das Reparaturarchiv. Die geborgene Matrix verbessert zukünftige Kernreparaturen.", "hold_time":5.0, "guards":12},
}

static func node(id: String) -> Dictionary:
	for entry: Dictionary in NODES:
		if entry.id == id:
			var result: Dictionary = LocaleText.data(entry)
			result.site_kind = site_kind(id)
			result.required = true
			result.objective = objective(id)
			return result
	return {}

static func contains(id: String) -> bool:
	return not node(id).is_empty()

static func main_complete(completed: Array) -> bool:
	for entry: Dictionary in NODES:
		if int(entry.cost) == 0 and not completed.has(entry.id):
			return false
	return true

# Convoy research travels with the crew. Infrastructure belongs to its bunker.
const VEHICLE_UPGRADES := ["convoy_mg", "convoy_armor", "convoy_armor_heavy", "convoy_cargo", "convoy_tank", "convoy_economy", "convoy_handling", "convoy_transmission", "convoy_reload", "convoy_stabilizer", "convoy_support", "convoy_blast_lining"]
const VEHICLE_PREREQUISITES := {"convoy_armor_heavy":"convoy_armor", "convoy_economy":"convoy_tank", "convoy_transmission":"convoy_handling", "convoy_reload":"convoy_mg", "convoy_stabilizer":"convoy_reload", "convoy_support":"convoy_cargo", "convoy_blast_lining":"convoy_armor_heavy"}
const MEDIC_UPGRADES := ["bunker_dance", "bunker_dance_2", "bunker_dance_3", "bunker_dance_4", "bunker_dance_5"]
const PERSISTENT_UPGRADES := PERSONAL_UPGRADES + VEHICLE_UPGRADES + MEDIC_UPGRADES

static func valid_medic_research(upgrades: Array) -> bool:
	for index in range(1, MEDIC_UPGRADES.size()):
		if upgrades.has(MEDIC_UPGRADES[index]) and not upgrades.has(MEDIC_UPGRADES[index-1]): return false
	return true
static var CARGO_KINDS: Array[String]:
	get: return ItemCatalog.cargo_kinds()
const EPIC_WEAPONS := ["veteran_rifle", "breacher_shotgun", "storm_arcgun"]
const STAGES := ["defense", "preparation", "map", "travel", "stop", "occupation", "failed"]
const STOP_TYPES := {
	"fuel":{"title":"ALTE TANKSTELLE", "detail":"Sichere die Zapfsäulen. Ein begrenzter Treibstoffvorrat wartet im Depot.", "fuel":10, "cargo":{}, "guards":3, "extra_fuel":2, "weapon":""},
	"salvage":{"title":"VERSORGUNGSKONVOI", "detail":"Ein liegen gebliebener Konvoi enthält Stahl und Munition. Freier Laderaum ist erforderlich.", "fuel":0, "cargo":{"steel":4,"ammo":3}, "guards":4, "extra_fuel":2, "weapon":""},
	"weapon":{"title":"VERSIEGELTES WAFFENDEPOT", "detail":"Eine bewachte Waffenkiste enthält eine seltene Waffe für die Besatzung.", "fuel":0, "cargo":{}, "guards":5, "extra_fuel":3, "weapon":"veteran_rifle"},
}

static func valid_vehicle_research(upgrades: Array) -> bool:
	var seen: Array = []
	for id in upgrades:
		if not id is String or not VEHICLE_UPGRADES.has(id) or seen.has(id): return false
		if VEHICLE_PREREQUISITES.has(id) and not upgrades.has(VEHICLE_PREREQUISITES[id]): return false
		seen.append(id)
	return true

static func vehicle_stats(upgrades: Array) -> Dictionary:
	return {
		"max_hp":600 + (200 if upgrades.has("convoy_armor") else 0) + (300 if upgrades.has("convoy_armor_heavy") else 0),
		"cargo_capacity":18 + (18 if upgrades.has("convoy_cargo") else 0),
		"fuel_capacity":30 + (20 if upgrades.has("convoy_tank") else 0),
		"fuel_multiplier":0.75 if upgrades.has("convoy_economy") else 1.0,
		"mounted_mg":upgrades.has("convoy_mg"),
		"speed":140.0 if upgrades.has("convoy_transmission") else 125.0,
		"acceleration":250.0 if upgrades.has("convoy_handling") else 190.0,
		"braking":460.0 if upgrades.has("convoy_handling") else 350.0,
		"reload_time":1.05 if upgrades.has("convoy_reload") else 1.4,
		"mg_damage":21.0 if upgrades.has("convoy_stabilizer") else 18.0,
		"repair_multiplier":1.3 if upgrades.has("convoy_support") else 1.0,
		"damage_multiplier":0.85 if upgrades.has("convoy_blast_lining") else 1.0,
	}

static func journey(destination: String) -> Dictionary:
	var entry := node(destination)
	if entry.is_empty() or destination == ENTRY: return {}
	var ordinal := 0
	for candidate: Dictionary in NODES:
		if candidate.id == destination: break
		ordinal += 1
	return {"destination":destination, "distance":2400, "fuel":8, "guards":4 + mini(ordinal,6), "ambushes":2 + mini(floori(float(ordinal)/4.0),2), "stops":[destination+":fuel",destination+":salvage",destination+":weapon"]}

static func stop(id: String) -> Dictionary:
	var pieces := id.split(":")
	if pieces.size()!=2 or pieces[0]==ENTRY or not contains(pieces[0]) or not STOP_TYPES.has(pieces[1]): return {}
	var result: Dictionary = STOP_TYPES[pieces[1]].duplicate(true)
	result.id = id
	result.kind = pieces[1]
	result.destination = pieces[0]
	if pieces[1] == "weapon":
		var index := 0
		for entry: Dictionary in NODES:
			if entry.id == pieces[0]: break
			index += 1
		result.weapon = EPIC_WEAPONS[index%EPIC_WEAPONS.size()]
	return LocaleText.data(result)

static func route_fuel(destination: String, stop_id: String, upgrades: Array) -> int:
	var route := journey(destination)
	if route.is_empty(): return 0
	var extra := 0
	if not stop_id.is_empty():
		var halt := stop(stop_id)
		if halt.is_empty() or halt.destination != destination: return -1
		extra = int(halt.extra_fuel)
	return ceili(float(int(route.fuel)+extra)*float(vehicle_stats(upgrades).fuel_multiplier))

static func cargo_count(cargo: Dictionary) -> int:
	var count := 0
	for amount in cargo.values(): count += int(amount)
	return count

static func site_kind(id: String) -> String:
	return "outpost" if OUTPOST_OBJECTIVES.has(id) else "bunker"

static func objective(id: String) -> Dictionary:
	return LocaleText.data(OUTPOST_OBJECTIVES.get(id, {}))

static func all_complete(completed: Array) -> bool:
	for entry: Dictionary in NODES:
		if not completed.has(entry.id): return false
	return true

static func completion_summary(completed: Array) -> Dictionary:
	var result := {"secured":0, "total":NODES.size(), "bunkers":0, "bunkers_total":0, "outposts":0, "outposts_total":0, "remaining":[], "all_complete":false}
	for entry: Dictionary in NODES:
		var counter := "outposts" if site_kind(str(entry.id)) == "outpost" else "bunkers"
		result[counter + "_total"] += 1
		if completed.has(entry.id):
			result.secured += 1
			result[counter] += 1
		else:
			result.remaining.append(str(entry.id))
	result.all_complete = result.secured == result.total
	return result
