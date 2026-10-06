class_name CampaignBonus
extends RefCounted
## Portable crew research and convoy supplies survive bunker transitions.
static func snapshot_player(player: Node) -> Dictionary:
	if not is_instance_valid(player) or not "progression" in player or not is_instance_valid(player.progression): return {}
	var progress: PlayerProgression = player.progression
	var weapon := player.get_node_or_null("WorkerWeapon")
	var result := {"character":str(player.character_id), "level":progress.level, "xp":progress.xp, "skill_points":progress.skill_points, "skills":progress.skills.duplicate(), "armor_tier":progress.armor_tier, "weapon_kind":str(weapon.weapon_kind) if is_instance_valid(weapon) else "rifle"}
	result.ammunition=weapon.capture_ammunition() if is_instance_valid(weapon) else WorkerWeapon.initial_ammunition()
	result.inventory=player.inventory.duplicate() if "inventory" in player else {}
	return result if valid_snapshot(result) else {}

static func valid_snapshot(value: Variant) -> bool:
	if not value is Dictionary or value.size()<7 or value.size()>9: return false
	for key in value:
		if not key in ["character","level","xp","skill_points","skills","armor_tier","weapon_kind","ammunition","inventory"]: return false
	if value.has("ammunition") and not WorkerWeapon.valid_ammunition(value.ammunition): return false
	if value.has("inventory") and not valid_inventory(value.inventory): return false
	for key: String in ["character", "level", "xp", "skill_points", "skills", "armor_tier", "weapon_kind"]:
		if not value.has(key): return false
	if not value.character is String or not CharacterCatalog.contains(value.character): return false
	if not CampaignState._integer(value.level, 1, PlayerProgression.MAX_LEVEL) or not CampaignState._integer(value.skill_points, 0, PlayerProgression.MAX_LEVEL-1) or not CampaignState._integer(value.armor_tier, 0, 2): return false
	if not (value.xp is float or value.xp is int) or not is_finite(float(value.xp)) or float(value.xp) < 0: return false
	var required := PlayerProgression.XP_FIRST_LEVEL + PlayerProgression.XP_LEVEL_STEP * (int(value.level)-1)
	if float(value.xp) >= required or (int(value.level) == PlayerProgression.MAX_LEVEL and float(value.xp) != 0): return false
	if not value.skills is Dictionary or value.skills.size() != 3: return false
	var spent := 0
	for skill: String in PlayerProgression.SKILL_SPECS:
		if not value.skills.has(skill) or not CampaignState._integer(value.skills[skill], 0, PlayerProgression.MAX_SKILL_RANK): return false
		spent += int(value.skills[skill])
	if spent + int(value.skill_points) != int(value.level)-1: return false
	return value.weapon_kind is String and value.weapon_kind in ["rifle", "shotgun", "arcgun", "veteran_rifle", "breacher_shotgun", "storm_arcgun"]

static func valid_inventory(value: Variant) -> bool:
	if not value is Dictionary or value.size()>Balance.RESOURCE_NAMES.size(): return false
	for kind in value:
		if not kind is String or not Balance.RESOURCE_NAMES.has(kind) or not CampaignState._integer(value[kind],0,Balance.PICKUP_STACK_MAX): return false
	return true

static func valid_ammunition_research(snapshot: Dictionary, research: Array, epic_weapons: Array) -> bool:
	if not snapshot.has("ammunition"): return true
	var owned: Dictionary={}
	for id in research: owned[id]=true
	var rounds: Dictionary=snapshot.ammunition
	if int(rounds.reserve)>(WeaponResearch.MAX_RESERVE if owned.has("weapon_pouches") else WeaponResearch.BASE_RESERVE): return false
	for kind in rounds.loaded:
		var spec:=WeaponResearch.stats_owned(owned,kind,WorkerWeapon.WEAPONS[kind])
		if int(rounds.loaded[kind])>int(spec.capacity): return false
		if int(rounds.loaded[kind])<=0: continue
		if kind in ["shotgun","arcgun"] and not owned.has(kind): return false
		if kind in CampaignCatalog.EPIC_WEAPONS and not epic_weapons.has(kind): return false
	return true

static func restore_players(game: Node, state: CampaignState) -> void:
	if not is_instance_valid(game) or state == null or not state.active: return
	if is_instance_valid(game.upgrades):
		# The new site's upgrade system must already be fresh. This function adds
		# only portable crew/convoy research, preserving no bunker infrastructure.
		for id: String in state.shared_personal_upgrades: game.upgrades.owned[id] = true
		game.upgrades.points = int(state.expedition.tech_points)
		game.upgrades.changed.emit()
	for player in game.players:
		restore_player(player, state)

static func restore_player(player: Node, state: CampaignState) -> bool:
	if not is_instance_valid(player) or state == null: return false
	var snapshot: Dictionary = state.snapshots.get(str(player.player_id), {})
	if not valid_snapshot(snapshot) or player.character_id != snapshot.character: return false
	var progress: PlayerProgression = player.progression
	progress.level = int(snapshot.level)
	progress.xp = float(snapshot.xp)
	progress.skill_points = int(snapshot.skill_points)
	progress.skills = snapshot.skills.duplicate()
	progress.armor_tier = int(snapshot.armor_tier)
	progress.kills = 0
	progress.break_combo()
	progress._refresh_hp()
	player.hp = player.max_hp
	var weapon := player.get_node_or_null("WorkerWeapon")
	if is_instance_valid(weapon):
		weapon.restore_ammunition(snapshot.get("ammunition",WorkerWeapon.initial_ammunition()))
		if weapon.available_weapons().has(snapshot.weapon_kind): weapon.weapon_kind = snapshot.weapon_kind
	if "inventory" in player:
		# JSON checkpoints contain integral floats. Restore canonical integer
		# quantities so persisted hands satisfy the strict player wire schema.
		var carried: Dictionary={}
		for kind: String in snapshot.get("inventory",{}):
			carried[kind]=int(snapshot.inventory[kind])
		player.inventory=carried
		player.selected_material()
	progress.changed.emit()
	return true

static func _state(game: Node) -> CampaignState:
	if is_instance_valid(game) and "campaign" in game and game.campaign is CampaignState and game.campaign.active:
		return game.campaign
	return null

static func owns(game: Node, blueprint: String) -> bool:
	var state := _state(game)
	return state != null and state.blueprints.has(blueprint)

static func apply_bunker(game: Node, state: CampaignState) -> void:
	if not is_instance_valid(game) or state == null or not state.active: return
	if state.blueprints.has("reinforced_core") and is_instance_valid(game.core) and not game.core.has_meta("campaign_core_bonus"):
		game.core.set_meta("campaign_core_bonus", true)
		game.core.max_hp += 180.0
		game.core.hp += 180.0

static func production_multiplier(game: Node) -> float:
	return 0.85 if owns(game, "precision_foundry") else 1.0

static func gun_multiplier(game: Node) -> float:
	return 1.15 if owns(game, "siege_optics") else 1.0

static func repair_multiplier(game: Node) -> float:
	return 1.25 if owns(game, "repair_matrix") else 1.0
