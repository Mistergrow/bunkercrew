extends RefCounted
## Audited wire schema. No incoming resource path, Object, Callable or method is used.
const VERSION := 4
const MAX_ENTITIES := 1024
const MAX_BYTES := 2*1024*1024
const FIELDS := {
	"convoy_vehicle":"hp max_hp fuel max_fuel cargo cargo_capacity fuel_multiplier has_mg ammo reserve open_pack vehicle_upgrades aim_angle recoil flash flash_tick cooldown reload_timer hit_flash facing wheel_phase suspension animation_time travel_distance road_bounds driving_enabled destroyed velocity journey_state",
	"convoy_seat":"role enter_frame",
	"convoy_supply":"kind amount transfer deposit_transfer",
	"campaign_salvage":"claim_id drop_id amount elapsed fall_speed collected",
	"player":"gore_mask player_id character_id velocity inventory selected_kind last_transfer_kind pickup_animation drop_animation facing max_hp hp invulnerability hurt_flash hurt_stun down_time since_hit knockback climbing mining _animation_time _interacting _interaction_held _landing_time _jump_windup _airborne _drop_time _drop_held",
	"worker_weapon":"weapon_kind reserve open_pack loaded aiming flash recoil aim_direction aim_point reload_timer cooldown _aim_hold _aim_pitch _reload_kind _shot_index",
	"player_progression":"level xp kills combo combo_time skill_points skills armor_tier",
	"worker_medical":"bleeding fractured bandaged splinted state charges critical_remaining down_elapsed recovery_time recovery_kind aid_kind aid_progress hit_serial _refill_elapsed _channel_elapsed _channel_gap",
	"medical_aid_target":"",
	"station":"kind input_amount input_scrap working_scrap output_amount binder working production_time elapsed transfer",
	"deep_station":"kind input_amount input_scrap working_scrap output_amount binder working production_time elapsed transfer ingredient_amounts",
	"glass_furnace":"kind input_amount input_scrap working_scrap output_amount binder working production_time elapsed transfer ingredient_amounts",
	"supply":"kind amount transfer deposit_transfer",
	"resource_pickup":"kind amount elapsed fall_speed",
	"mine_block":"kind yield_amount grid_cell mining last_work elapsed depleted exposed_sides contact_point selected_last_frame",
	"diggable_terrain":"bounds _cleared_emitted",
	"scenario_room_site":"room_index materials transfer construction curing_remaining built curing support_materials support_work supported",
	"core":"hp max_hp elapsed repair_work hit_flash",
	"wall":"state tier hp max_hp reinforced cure_time work work_action last_work_frame hit_flash pour_animation assembly_animation animation_time",
	"turret":"damage_multiplier ammo reserve aim_angle cooldown recoil flash reload_timer enter_frame flash_tick",
	"flak_turret":"damage_multiplier ammo reserve aim_angle cooldown recoil flash reload_timer enter_frame flash_tick tier autonomous scan_clock hp max_hp",
	"flak_station":"available built tier materials transfer construction",
	"dome_controller":"available frame_built built materials transfer construction repair_work flak_port_active",
	"dome_segment":"panel_index stage hp max_hp flash service_port",
	"field_workshop":"selection orders elapsed",
	"perimeter_site":"role side slot_index tier hp max_hp materials transfer work cure ruined gate_open gate_amount ammo aim_angle cooldown burst_left flash recoil shot_serial hit_flash builder_player_id",
	"field_defense":"kind hp max_hp charges arming cooldown animation age spent",
	"field_medic":"velocity medical_supplies status_label treating treatment_progress climbing facing elapsed refill_progress _rest_delay _last_core_hp _replan_clock _stuck_time _jump_elapsed _emergency_mission _mission_complete _returning _motion_phase _idle_time treatments_completed revives_completed logistics_cargo logistics_phase logistics_progress",
	"enemy":"wave elite kind show_status_labels attack_direction profile visual_scale body_height attack_reach attack_damage move_speed hp max_hp gait moving attack_clock windup hit_flash stagger weapon_recoil muzzle_flash dead tracer_end burst_remaining burst_clock locomotion_speed age attack_count worker_windup worker_attack_clock worker_attack_count velocity",
	"ground_infantry":"gore_mask wave elite kind show_status_labels attack_direction profile visual_scale body_height attack_reach attack_damage move_speed hp max_hp gait moving attack_clock windup hit_flash stagger weapon_recoil muzzle_flash dead tracer_end burst_remaining burst_clock locomotion_speed age attack_count worker_windup worker_attack_clock worker_attack_count velocity squad_slot stance",
	"boss_machine":"wave elite kind show_status_labels attack_direction profile visual_scale body_height attack_reach attack_damage move_speed hp max_hp gait moving attack_clock windup hit_flash stagger weapon_recoil muzzle_flash dead tracer_end burst_remaining burst_clock locomotion_speed age attack_count worker_windup worker_attack_clock worker_attack_count velocity overdrive phase_flash",
	"ground_machine_abilities":"mode clock shield_hp shield_flash shield_open rush_warning rush_time rush_cooldown rush_primed repair_remaining repair_clock repair_flash repair_endpoint repaired_total heat vent_time shock_flash aim_point warning_point aim_locked",
	"air_machine":"kind wave elite profile hp max_hp dead body_height show_status_labels attack_direction scenario_lanes scenario_floor flight_velocity age entered entry_time attack_clock windup burst_remaining burst_clock attack_count locked_aim hit_flash shield_flash weapon_recoil muzzle_flash formation_phase dive_origin velocity",
	"projectile":"direction speed damage life trail_length distance_travelled",
	"worker_projectile":"direction damage speed life flavor remaining_hits age distance_travelled",
	"flak_projectile":"direction speed damage life retired distance_travelled",
	"hostile_air_projectile":"velocity gravity damage flavor lifetime age trail spent",
	"upgrade_system":"points earned owned",
	"scenery_damage":"states",
	"round_controller":"phase wave time_left running player_count spawned wave_total spawn_clock air_wave_enabled",
}
const REFS := {
	"convoy_seat":"occupant",
	"player":"mounted_turret focus preferred_focus _locked_focus",
	"worker_medical":"aid_target _healer",
	"medical_aid_target":"medical",
	"mine_block":"last_worker",
	"turret":"occupant",
	"flak_turret":"occupant builder tracking_target",
	"flak_station":"builder turret",
	"dome_controller":"repair_target",
	"field_defense":"builder turret",
	"perimeter_site":"tracking_target",
	"field_medic":"target",
	"enemy":"target burst_target worker_target",
	"ground_infantry":"target burst_target worker_target",
	"boss_machine":"target burst_target worker_target",
	"air_machine":"target",
	"projectile":"credit_worker source",
	"worker_projectile":"credit_worker",
	"flak_projectile":"credit_worker source",
}
const DYNAMIC := ["convoy_supply","convoy_vehicle","campaign_salvage","ground_infantry","enemy","boss_machine","air_machine","projectile","worker_projectile","flak_projectile","hostile_air_projectile","resource_pickup","field_defense"]
const SCENES := {
	"ground_infantry":"res://scenes/ground_infantry.tscn",
	"enemy":"res://scenes/enemy.tscn", "boss_machine":"res://scenes/boss_enemy.tscn",
	"air_machine":"res://scenes/air_enemy.tscn", "projectile":"res://scenes/projectile.tscn",
	"resource_pickup":"res://scenes/resource_pickup.tscn", "field_defense":"res://scenes/field_defense.tscn",
}
const SCRIPTS := {
	"convoy_supply":"res://scripts/convoy_supply.gd",
	"convoy_vehicle":"res://scripts/convoy_vehicle.gd", "campaign_salvage":"res://scripts/campaign_salvage.gd",
	"worker_projectile":"res://scripts/worker_projectile.gd", "flak_projectile":"res://scripts/flak_projectile.gd",
	"hostile_air_projectile":"res://scripts/hostile_air_projectile.gd",
}
const META := ["network_departed","final_boss","boss_phase","boss_title","scenario_front"]
const GAME_FIELDS := "started player_count view_stage elapsed stats world_left world_right notice notice_time camera_target_zoom camera_target_center"

static var _field_cache: Dictionary = {}
static var _ref_cache: Dictionary = {}
static var _kind_cache: Dictionary = {}
static var _game_fields := GAME_FIELDS.split(" ",false)

static func game_fields() -> PackedStringArray: return _game_fields

static func fields(entity_kind: String) -> PackedStringArray:
	if not _field_cache.has(entity_kind): _field_cache[entity_kind]=str(FIELDS.get(entity_kind,"")).split(" ",false)
	return _field_cache[entity_kind]

static func refs(entity_kind: String) -> PackedStringArray:
	if not _ref_cache.has(entity_kind): _ref_cache[entity_kind]=str(REFS.get(entity_kind,"")).split(" ",false)
	return _ref_cache[entity_kind]

static func kind(node: Node) -> String:
	var script: Script = node.get_script()
	if script==null: return ""
	if _kind_cache.has(script): return _kind_cache[script]
	var original := script
	var result := ""
	while script != null:
		var stem := script.resource_path.get_file().get_basename()
		if FIELDS.has(stem): result=stem; break
		script = script.get_base_script()
	_kind_cache[original]=result
	return result

static func factory(kind_name: String) -> Node:
	if SCENES.has(kind_name): return load(SCENES[kind_name]).instantiate()
	if SCRIPTS.has(kind_name): return load(SCRIPTS[kind_name]).new()
	return null

static func bounded(value,depth := 0) -> bool:
	if depth>12: return false
	if value is int or value is float: return absf(float(value))<=1000000000.0
	if value is Vector2: return value.is_finite() and absf(value.x)<=32768 and absf(value.y)<=32768
	if value is Vector2i: return absi(value.x)<=32768 and absi(value.y)<=32768
	if value is Rect2: return bounded(value.position,depth+1) and bounded(value.size,depth+1) and value.size.x>=0 and value.size.y>=0
	if value is Array:
		for item in value:
			if not bounded(item,depth+1): return false
	if value is Dictionary:
		for key in value:
			if not bounded(key,depth+1) or not bounded(value[key],depth+1): return false
	return true

static func counters(value: Dictionary,keys: Array,maximum: int) -> bool:
	for key in value:
		if not key in keys or not value[key] is int or value[key]<0 or value[key]>maximum: return false
	return true

static func valid_weapon_research(state: Dictionary, owned: Dictionary) -> bool:
	const Research = preload("res://scripts/weapon_research.gd")
	if not state.get("loaded") is Dictionary: return false
	for weapon in state.loaded:
		if not WorkerWeapon.WEAPONS.has(weapon): return false
		var stats := Research.stats_owned(owned,weapon,WorkerWeapon.WEAPONS[weapon])
		if state.loaded[weapon]>int(stats.capacity): return false
	var limit := Research.MAX_RESERVE if owned.has("weapon_pouches") else Research.BASE_RESERVE
	return state.get("reserve",0)<=limit

static func valid_state(entity_kind: String,state: Dictionary) -> bool:
	if not bounded(state): return false
	if entity_kind in ["player","ground_infantry"] and (not state.get("gore_mask") is int or state.gore_mask<0 or state.gore_mask>15): return false
	if state.has("z_index") and (state.z_index < -4096 or state.z_index>4095): return false
	if state.has("max_hp"):
		if state.max_hp<0 or state.max_hp>1000000: return false
		# An unbuilt or destroyed wall is a persistent, repairable build site.
		if state.max_hp==0 and not ((entity_kind=="wall" and state.get("state")==DefenseWall.State.EMPTY or entity_kind=="perimeter_site" and state.get("tier")==0) and state.get("hp")==0): return false
	if state.has("hp") and (state.hp<0 or (state.has("max_hp") and state.hp>state.max_hp)): return false
	for field in ["input_amount","output_amount","amount","yield_amount","ammo","reserve","charges"]:
		if state.has(field) and (state[field]<0 or state[field]>10000): return false
	if state.has("output_amount") and state.output_amount>64: return false
	match entity_kind:
		"field_workshop":
			if not CraftingCatalog.valid_workshop_state(state,Balance.TRANSFER_TIME): return false
		"station", "deep_station", "glass_furnace":
			for field in ["input_scrap", "working_scrap"]:
				if not state.get(field) is int or state[field] < 0: return false
			if not state.get("input_amount") is int or state.input_scrap > state.input_amount: return false
			if not state.get("working") is bool: return false
			if state.working_scrap > int(Balance.RECIPES.furnace.inputs.ore): return false
			if state.get("kind") != "furnace" and (state.input_scrap != 0 or state.working_scrap != 0): return false
			if state.working_scrap > 0 and state.get("working") != true: return false
		"convoy_vehicle":
			if not preload("res://scripts/convoy_journey.gd").valid_state(state.get("journey_state")): return false
			var durable := {"unlocked":true,"hp":state.get("hp"),"fuel":state.get("fuel"),"cargo":state.get("cargo"),"upgrades":state.get("vehicle_upgrades"),"ammo":state.get("ammo"),"reserve":state.get("reserve"),"open_pack":state.get("open_pack",0)}
			if not CampaignState.valid_vehicle(durable): return false
			var specs := CampaignCatalog.vehicle_stats(durable.upgrades)
			if state.get("max_hp")!=specs.max_hp or state.get("max_fuel")!=specs.fuel_capacity or state.get("cargo_capacity")!=specs.cargo_capacity or state.get("has_mg")!=specs.mounted_mg or state.get("fuel_multiplier")!=specs.fuel_multiplier: return false
			if not state.get("road_bounds") is Vector2 or state.road_bounds.x< -32768 or state.road_bounds.y>3700 or state.road_bounds.y<=state.road_bounds.x: return false
			if not state.get("velocity") is Vector2 or state.velocity.length()>1000: return false
			if state.get("facing") not in [-1.0,1.0] or not state.get("destroyed") is bool or not state.get("driving_enabled") is bool: return false
			if state.destroyed!=(state.hp<=0) or not state.get("flash_tick") is int or state.flash_tick<0: return false
			for field in ["cooldown","reload_timer","hit_flash","flash","recoil","travel_distance","animation_time"]:
				if not state.has(field) or float(state[field])<0: return false
		"convoy_seat":
			if state.get("role") not in ["driver","gunner","passenger_left","passenger_right"] or not state.get("enter_frame") is int: return false
		"campaign_salvage":
			if not state.get("claim_id") is String or state.claim_id.length()>180 or not state.get("drop_id") is String or state.drop_id.length()>32: return false
			if not state.get("amount") is int or state.amount<1 or state.amount>3 or not state.get("collected") is bool: return false
			if not state.get("elapsed") is float or state.elapsed<0 or not state.get("fall_speed") is float or state.fall_speed<0 or state.fall_speed>650: return false
		"player":
			if not state.get("player_id") in [1,2,3,4] or not CharacterCatalog.contains(str(state.get("character_id",""))): return false
			if not state.get("inventory") is Dictionary or not counters(state.inventory,Balance.RESOURCE_NAMES.keys(),10000): return false
			for field in ["selected_kind","last_transfer_kind"]:
				if state.has(field) and state[field]!="" and not Balance.RESOURCE_NAMES.has(state[field]): return false
		"field_medic":
			if not state.get("logistics_cargo") is String or (state.logistics_cargo!="" and not Balance.RESOURCE_NAMES.has(state.logistics_cargo)): return false
			if not state.get("logistics_phase") in preload("res://scripts/medic_logistics.gd").VALID_PHASES: return false
			if not state.get("logistics_progress") is float and not state.get("logistics_progress") is int: return false
			if not is_finite(float(state.logistics_progress)) or state.logistics_progress<0.0 or state.logistics_progress>1.25: return false
		"worker_projectile":
			if state.get("flavor") not in ["rifle","shotgun","arcgun"]: return false
			if not state.get("remaining_hits") is int or state.remaining_hits<0 or state.remaining_hits>4: return false
		"hostile_air_projectile":
			if not state.get("flavor") in ["dart","tracer","bomb","rocket","arc","grenade"]: return false
			if not state.get("velocity") is Vector2 or state.velocity.length()>4000.0: return false
			for key in ["gravity","damage","lifetime","age"]:
				if not state.get(key) is float and not state.get(key) is int: return false
				if not is_finite(float(state[key])) or state[key]<0.0: return false
			if state.gravity>1000.0 or state.damage>300.0 or state.lifetime>6.0 or state.age>7.0: return false
			if not state.get("trail") is Array or state.trail.size()>8: return false
			for point in state.trail:
				if not point is Vector2: return false
		"ground_machine_abilities":
			if not state.get("mode") in ["","shield","rush","aim","demolition","repair","bastion","grenade","infantry_rifle","infantry_medic","vehicle_gun","vehicle_mortar"]: return false
			if not state.get("aim_point") is Vector2 or not state.get("warning_point") is Vector2 or not state.get("aim_locked") is bool: return false
			if state.mode=="infantry_medic":
				for field in ["repair_remaining","repair_clock","repair_flash","repaired_total"]:
					if not state.get(field) is float and not state.get(field) is int: return false
					if not is_finite(float(state[field])) or state[field]<0: return false
				if state.repair_remaining>GroundMachineAbilities.MEDIC_RESERVE or state.repaired_total>GroundMachineAbilities.MEDIC_RESERVE: return false
				if state.repair_remaining+state.repaired_total>GroundMachineAbilities.MEDIC_RESERVE+.001: return false
				if state.repair_flash>GroundMachineAbilities.MEDIC_WINDUP or state.repair_clock>GroundMachineAbilities.MEDIC_INTERVAL: return false
				if not state.get("repair_endpoint") is Vector2: return false
		"worker_weapon":
			if not WorkerWeapon.WEAPONS.has(state.get("weapon_kind")) or not state.get("loaded") is Dictionary: return false
			if not counters(state.loaded,WorkerWeapon.WEAPONS.keys(),1000): return false
			for weapon in state.loaded:
				if state.loaded[weapon]>int(preload("res://scripts/weapon_research.gd").MAX_MAGAZINES[weapon]): return false
			if not state.get("reserve") is int or state.reserve<0 or state.reserve>180: return false
			var open_pack=state.get("open_pack",0)
			if not open_pack is int or open_pack<0 or open_pack>19: return false
		"round_controller":
			if not state.get("phase") in ["build","warning","attack","salvage","victory","defeat","convoy","occupation"]: return false
			if not state.get("wave") is int or state.wave<1 or state.wave>20: return false
			if not state.get("player_count") in [1,2,3,4]: return false
		"wall":
			if not state.get("state") in [0,1,2,3,4] or not state.get("tier") in [1,2,3,4]: return false
		"flak_station","flak_turret":
			if not state.get("tier") in [0,1,2,3]: return false
		"dome_segment":
			if not state.get("stage") in [0,1,2,3] or not state.get("panel_index") is int or state.panel_index<0 or state.panel_index>13: return false
		"scenario_room_site":
			if not valid_room_site(state): return false
		"perimeter_site":
			if not preload("res://scripts/perimeter_replication.gd").valid(state): return false
		"field_defense":
			if not state.get("kind") in ["jaw_trap","blast_trap","sentry_kit"]: return false
		"resource_pickup","supply","convoy_supply","mine_block":
			if not Balance.RESOURCE_NAMES.has(state.get("kind")) and not (entity_kind=="resource_pickup" and state.get("kind")=="core"): return false
		"station","deep_station","glass_furnace":
			if not Balance.RECIPES.has(state.get("kind")): return false
		"enemy","boss_machine","air_machine","ground_infantry":
			if entity_kind=="ground_infantry":
				if not EnemyCatalog.is_human(str(state.get("kind",""))) or not state.get("squad_slot") in [0,1,2]: return false
				if not state.get("stance") is float or not is_finite(state.stance) or state.stance<0 or state.stance>1: return false
			elif entity_kind=="enemy" and EnemyCatalog.is_human(str(state.get("kind",""))): return false
			var source: Dictionary = AirEnemyCatalog.PROFILES if entity_kind=="air_machine" else EnemyCatalog.PROFILES
			if not source.has(state.get("kind")) or not state.get("profile") is Dictionary: return false
			if not state.get("wave") is int or state.wave<1 or state.wave>20: return false
			var expected: Dictionary=AirEnemyCatalog.profile(state.kind) if entity_kind=="air_machine" else EnemyCatalog.profile(state.kind)
			if entity_kind=="boss_machine":
				if state.kind!="siege": return false
				expected.label=BossMachine.TITLE
				expected.scrap=8
				expected.cores=10
				# The final boss changes four cadence values when opening its drive.
				var opened: Dictionary=expected.duplicate(true)
				opened.merge({"cooldown":2.7,"burst":2,"burst_gap":0.70,"windup":1.8},true)
				if state.profile!=expected and state.profile!=opened: return false
			elif state.profile!=expected: return false
	return true

static func valid_room_site(state: Dictionary) -> bool:
	if not state.get("room_index") in [0,1,2,3]: return false
	var room_cost: Dictionary = ScenarioRoomCatalog.spec(state.room_index).cost.duplicate()
	room_cost.steel -= 2
	if room_cost.steel == 0: room_cost.erase("steel")
	if not _paid_buffer(state.get("support_materials"), {"steel":2}) or not _paid_buffer(state.get("materials"), room_cost): return false
	for field in ["supported", "built", "curing"]:
		if not state.get(field) is bool: return false
	for field in ["support_work", "construction", "curing_remaining"]:
		if not state.get(field) is float and not state.get(field) is int: return false
		if not is_finite(float(state[field])) or state[field] < 0: return false
	if state.support_work > ScenarioRoomCatalog.SUPPORT_TIME or state.construction > ScenarioRoomCatalog.BUILD_TIME or state.curing_remaining > ScenarioRoomCatalog.CURE_TIME: return false
	var support_paid: bool = int(state.support_materials.get("steel", 0)) == 2
	if state.support_work > 0 and not support_paid: return false
	if state.supported and (not support_paid or state.support_work != ScenarioRoomCatalog.SUPPORT_TIME): return false
	if not state.supported and (not state.materials.is_empty() or state.construction > 0 or state.curing or state.built): return false
	var room_paid := true
	for resource: String in room_cost:
		if int(state.materials.get(resource, 0)) != int(room_cost[resource]): room_paid = false
	if state.construction > 0 and not room_paid: return false
	if (state.curing or state.built) and (not room_paid or state.construction != ScenarioRoomCatalog.BUILD_TIME): return false
	if state.built and (state.curing or state.curing_remaining != 0): return false
	if not state.curing and state.curing_remaining != 0: return false
	if not state.get("transfer") is Dictionary or state.transfer.size() > 4: return false
	for value in state.transfer.values():
		if not value is float and not value is int: return false
		if not is_finite(float(value)) or value < 0 or value > Balance.TRANSFER_TIME: return false
	return true

static func _paid_buffer(value, cost: Dictionary) -> bool:
	if not value is Dictionary: return false
	for key in value:
		if not cost.has(key) or not value[key] is int or value[key] < 0 or value[key] > int(cost[key]): return false
	return true

static func safe(value,depth := 0) -> bool:
	if depth>12: return false
	match typeof(value):
		TYPE_NIL,TYPE_BOOL,TYPE_INT: return true
		TYPE_FLOAT: return is_finite(value)
		TYPE_STRING,TYPE_STRING_NAME: return str(value).length()<=1024
		TYPE_VECTOR2: return value.is_finite()
		TYPE_VECTOR2I: return true
		TYPE_RECT2: return value.position.is_finite() and value.size.is_finite()
		TYPE_COLOR: return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
		TYPE_ARRAY:
			if value.size()>4096: return false
			for item in value:
				if not safe(item,depth+1): return false
			return true
		TYPE_DICTIONARY:
			if value.size()>512: return false
			for key in value:
				if not safe(key,depth+1) or not safe(value[key],depth+1): return false
			return true
	return false
