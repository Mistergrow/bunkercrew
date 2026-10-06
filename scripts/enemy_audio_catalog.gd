extends RefCounted
## Chassis/boot identity is independent from the contacted ground material.
const VARIANTS := 5
const SURFACES := ["dry","metal","ice","water"]
const FAMILIES := ["mech_light","mech_quad","mech_assault","mech_heavy","mech_colossus","boot_light","boot_standard","boot_heavy"]
const CLASS_FAMILIES := {
	"runner":"mech_light", "lancer":"mech_light",
	"strider":"mech_quad", "shield_guard":"mech_quad", "repair_crawler":"mech_quad",
	"assault":"mech_assault", "sniper":"mech_assault",
	"breaker":"mech_heavy", "demolisher":"mech_heavy", "siege":"mech_heavy",
	"colossus":"mech_colossus", "bastion":"mech_colossus",
	"scout":"boot_light", "marksman":"boot_light",
	"rifle_guard":"boot_standard", "grenadier":"boot_standard", "combat_medic":"boot_standard",
	"heavy_gunner":"boot_heavy",
}

static func contact_key(enemy_kind: String,surface: String) -> String:
	if not CLASS_FAMILIES.has(enemy_kind) or surface not in SURFACES: return ""
	return "%s_%s"%[CLASS_FAMILIES[enemy_kind],surface]
