extends RefCounted
## Presentation only. UpgradeSystem remains authoritative for price and gates.
const GROUPS := [
	[
		{"title":"Fertigung & Logistik", "ids":["bunker_workshop", "medic_logistics", "logistics_drive", "medic_collection", "precision_lines"]},
		{"title":"Kern & Versorgung", "ids":["core_resilience", "repair_tools", "medical_station", "blast_baffles"]},
		{"title":"Außenverteidigung", "ids":["bunker_armor", "bunker_fortress", "perimeter_automation"]},
	],
	[
		{"title":"Handwaffen", "ids":["weapon_handling", "shotgun", "arcgun"]},
		{"title":"Magazin & Reserve", "ids":["weapon_magazines", "weapon_bolt", "weapon_pouches"]},
		{"title":"Visierung & Durchschlag", "ids":["weapon_sights", "weapon_choke", "weapon_capacitor"]},
	],
	[
		{"title":"Arbeitsausrüstung", "ids":["boots", "harness", "craftsmanship"]},
		{"title":"SAN-1 Software", "ids":["bunker_dance", "bunker_dance_2", "bunker_dance_3", "bunker_dance_4", "bunker_dance_5"], "stages":true},
	],
	[
		{"title":"Fahrzeugwaffen", "ids":["convoy_mg", "convoy_reload", "convoy_stabilizer"]},
		{"title":"Fahrzeugschutz", "ids":["convoy_armor", "convoy_armor_heavy", "convoy_blast_lining"]},
		{"title":"Fracht & Werkzeug", "ids":["convoy_cargo", "convoy_support"]},
		{"title":"Fahrwerk & Reichweite", "ids":["convoy_handling", "convoy_transmission", "convoy_tank", "convoy_economy"]},
	],
]

static func groups(category: int, upgrades) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var included: Dictionary = {}
	for definition: Dictionary in GROUPS[category]:
		var ids: Array[String] = []
		for id: String in definition.ids:
			var entry: Dictionary = upgrades.node_data(id)
			if entry.is_empty() or int(entry.branch) != category: continue
			ids.append(id)
			included[id] = true
		if not ids.is_empty():
			result.append({"title":definition.title, "ids":ids, "stages":bool(definition.get("stages", false))})
	# Future catalog additions stay available before their presentation is curated.
	var extra: Array[String] = []
	for entry: Dictionary in upgrades.nodes_for_category(category):
		if not included.has(str(entry.id)): extra.append(str(entry.id))
	if not extra.is_empty(): result.append({"title":UpgradeSystem.CATEGORIES[category], "ids":extra, "stages":false})
	return result
