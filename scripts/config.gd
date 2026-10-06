class_name Balance
extends RefCounted

const CARRY_CAPACITY = 6
const PLAYER_SPEED = 190.0
const CLIMB_SPEED = 155.0
const WORKER_HP = 100.0
const WORKER_IFRAMES = 0.65
const WORKER_KO_TIME = 6.0
const WORKER_RESPAWN_SHIELD = 2.0
const WORKER_REGEN_DELAY = 4.0
const WORKER_REGEN_RATE = 8.0
const WORKER_REGEN_RADIUS = 105.0
const MINE_TIME = 1.25
const SOIL_DIG_TIME = 0.5
const TRANSFER_TIME = 0.30
const PICKUP_SUPPORT_INTERVAL := 0.25
const PICKUP_COMPACT_INTERVAL := 3.0
const PICKUP_COMPACT_RADIUS := 48.0
const PICKUP_STACK_MAX := 10000 # Existing network quantity limit; keep overflow.
# A roadside repair has finite pressure and two finite solo escort loadouts.
const CONVOY_DEFENSE_INTERVAL := 8.0
const CONVOY_DEFENSE_BATCHES := 2
const CONVOY_DEFENSE_MAX_ENEMIES := 12
const CONVOY_REPAIR_FOCUS_PRIORITY := 90.0
const CONVOY_ESCORT_HP := 120.0
const CONVOY_ESCORT_DAMAGE := 16.0
const CONVOY_ESCORT_SHOT_INTERVAL := 0.55
const CONVOY_ESCORT_RANGE := 400.0
const CONVOY_ESCORT_SPEED := 96.0
const CONVOY_ESCORT_MAGAZINE := 24
const CONVOY_ESCORT_RESERVE := 48
const CONVOY_ESCORT_RELOAD_TIME := 1.9
# Ingredients, outputs and seconds per batch have one source of truth.
# Furnace scrap substitutes for ore unit-for-unit; it is not a second requirement.
static var RECIPES: Dictionary:
	get: return CraftingCatalog.stations()
const ROOM_LINING_SPECS = {
	1: {"label":"RÜCKWAND", "cost":{"concrete":2,"steel":1}, "build_time":1.4, "cure_time":8.0, "hp_bonus":30.0},
	2: {"label":"TRAGWERK", "cost":{"concrete":3,"steel":2}, "build_time":2.0, "cure_time":12.0, "hp_bonus":45.0},
}
# Compatibility aliases for existing callers and balance checks.
const CURE_TIME = 18.0
const WALL_HP = 250.0
const REINFORCED_HP = 450.0
const FRESH_HP = 95.0
const CORE_HP = 450.0
# Economy and construction tuning.
const MINE_YIELD = 3
const BINDER_STOCK = 80
const FORM_HP = 60.0
const REBAR_FORM_HP = 100.0
const FORM_TIME = 1.0
const WALL_WORK_TIME = 0.7
const WALL_STEEL_COST = 2
const WALL_CONCRETE_COST = 2
const WALL_REPAIR = 85.0
const CORE_REPAIR = 65.0
const CORE_REPAIR_TIME = 1.0
const FRESH_REBAR_MULTIPLIER = 1.5
const TOTAL_WAVES = 20
const EXPANSION_INTERVAL = 5
const DOME_WAVE = 16
const BUILD_TIMES = [120.0, 55.0, 50.0, 50.0, 70.0, 165.0, 55.0, 50.0, 50.0, 70.0, 180.0, 55.0, 50.0, 50.0, 70.0, 210.0, 65.0, 60.0, 60.0, 90.0]
const WARNING_TIME = 8.0
const SALVAGE_TIME = 14.0
const WAVE_COUNTS = [4,5,6,6,7,6,7,7,8,8,7,8,8,9,9,8,9,10,11,12]
const SPAWN_INTERVAL = 5.5
const ENEMY_HP = 90.0
const SHOT_DAMAGE = 32.0
const SHOT_INTERVAL = 0.23
const MAGAZINE = 60
static var RESOURCE_NAMES: Dictionary:
	get: return ItemCatalog.names()
static var RESOURCE_COLORS: Dictionary:
	get: return ItemCatalog.colors()

static func capacity_for(player: Node) -> int:
	return player.capacity() if player.has_method("capacity") else CARRY_CAPACITY

static func resource_quantity(resource: String, amount: int) -> String:
	if resource == "ammo":
		return LocaleText.format("%d %s", [amount, LocaleText.text("Munitionskiste") if amount == 1 else LocaleText.text("Munitionskisten")])
	return LocaleText.format("%d %s", [amount, RESOURCE_NAMES.get(resource, resource)])

# Keep solo unchanged. Extra crew adds mostly separate enemies rather than HP.
static func active_players(game: Node) -> int:
	if not is_instance_valid(game): return 1
	var network = game.get("network")
	if is_instance_valid(network) and network.active and network.has_method("connected_player_count"):
		return clampi(network.connected_player_count(),1,4)
	if "players" in game and not game.players.is_empty(): return clampi(game.players.size(),1,4)
	return clampi(int(game.get("player_count")),1,4) if "player_count" in game else 1

static func wave_multiplier(players: int) -> float:
	return 1.0 + 0.45*(clampi(players,1,4)-1)

static func spawn_interval(players: int) -> float:
	return SPAWN_INTERVAL / (1.0 + 0.1458333333*(clampi(players,1,4)-1))

static func enemy_hp_multiplier(players: int) -> float:
	return 1.0 + 0.08*(clampi(players,1,4)-1)

static func enemy_damage_multiplier(players: int) -> float:
	return 1.0 + 0.04*(clampi(players,1,4)-1)
