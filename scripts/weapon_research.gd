class_name WeaponResearch
extends RefCounted
## Derived values only: buying research never fills a magazine or a reserve.
const IDS := ["weapon_magazines","weapon_bolt","weapon_sights","weapon_choke","weapon_capacitor","weapon_pouches"]
const MAX_MAGAZINES := {"rifle":36,"shotgun":8,"arcgun":16,"veteran_rifle":24,"breacher_shotgun":6,"storm_arcgun":12}
const BASE_RESERVE := 120
const MAX_RESERVE := 180

static func stats(game: Node, kind: String, base: Dictionary) -> Dictionary:
	var upgrades = game.get("upgrades") if is_instance_valid(game) else null
	return stats_owned(upgrades.owned if is_instance_valid(upgrades) and "owned" in upgrades else {},kind,base)

static func stats_owned(owned: Dictionary, kind: String, base: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	var family := str(base.get("family",kind))
	if owned.has("weapon_magazines"): result.capacity=int(MAX_MAGAZINES.get(kind,int(base.get("capacity",0))))
	result.reload=float(base.get("reload",1.0))*(.85 if owned.has("weapon_bolt") else 1.0)
	result.spread=float(base.get("spread",0.0))
	if family=="rifle" and owned.has("weapon_sights"): result.spread*=.55
	if family=="shotgun" and owned.has("weapon_choke"): result.spread*=.72
	result.pierce=3 if kind=="storm_arcgun" else (2 if family=="arcgun" else 1)
	if family=="arcgun" and owned.has("weapon_capacitor"): result.pierce+=1
	result.reserve_capacity=MAX_RESERVE if owned.has("weapon_pouches") else BASE_RESERVE
	return result
