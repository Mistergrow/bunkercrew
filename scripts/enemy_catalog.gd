class_name EnemyCatalog
extends RefCounted
## Class behavior, bounded campaign scaling and reproducible wave composition.
## Body art is independent from the animated legs, weapon and gameplay hitbox.

const HUMAN_CLASSES: Array[String] = ["grenadier", "rifle_guard", "scout", "heavy_gunner", "marksman", "combat_medic"]
const VEHICLE_CLASSES: Array[String] = ["scout_car", "mortar_carrier", "battle_tank"]
const GROUND_CLASSES: Array[String] = ["runner", "strider", "breaker", "assault", "colossus", "siege", "shield_guard", "lancer", "sniper", "demolisher", "repair_crawler", "bastion", "scout_car", "mortar_carrier", "battle_tank", "grenadier", "rifle_guard", "scout", "heavy_gunner", "marksman", "combat_medic"]
const CLASS_ORDER: Array[String] = ["runner", "strider", "breaker", "assault", "colossus", "siege", "shield_guard", "lancer", "sniper", "demolisher", "repair_crawler", "bastion", "scout_car", "mortar_carrier", "battle_tank", "grenadier", "rifle_guard", "scout", "heavy_gunner", "marksman", "combat_medic", "scout_drone", "gunship", "bomber", "interceptor", "shield_airship", "sky_fortress", "rocket_drone", "patrol_plane", "tiltrotor", "dive_bomber", "pulse_fighter", "heavy_zeppelin"]
const INTRO_WAVES := {"runner":1, "strider":1, "breaker":4, "assault":7, "colossus":10, "siege":16, "shield_guard":6, "lancer":8, "sniper":10, "demolisher":12, "repair_crawler":14, "bastion":17, "scout_car":3, "mortar_carrier":11, "battle_tank":9, "grenadier":6, "rifle_guard":6, "scout":8, "heavy_gunner":10, "marksman":12, "combat_medic":14, "scout_drone":7, "gunship":9, "bomber":11, "interceptor":13, "shield_airship":16, "sky_fortress":18, "rocket_drone":8, "patrol_plane":10, "tiltrotor":12, "dive_bomber":14, "pulse_fighter":15, "heavy_zeppelin":19}
const MAX_HP_SCALE := 1.40
const MAX_SPEED_SCALE := 1.12
const MAX_DAMAGE_SCALE := 1.20
const ELITE_HP_SCALE := 1.35
const ELITE_DAMAGE_SCALE := 1.30
const ELITE_SIZE_SCALE := 1.10
const PROFILES := {
	"runner": {"label":"LÄUFER", "hp":58.0, "speed":44.0, "damage":7.0, "reach":49.0, "cooldown":0.90, "windup":0.20, "burst":1, "burst_gap":0.17, "scale":0.72, "body_y":31.0, "hitbox":Vector2(47,39), "center_y":25.0, "gait":14.0, "scrap":1, "cores":1, "legs":2, "body_size":Vector2(65,39)},
	"strider": {"label":"STREIFER", "hp":90.0, "speed":28.0, "damage":12.0, "reach":63.0, "cooldown":1.35, "windup":0.32, "burst":1, "burst_gap":0.17, "scale":1.0, "body_y":43.0, "hitbox":Vector2(66,50), "center_y":30.0, "gait":10.0, "scrap":1, "cores":1, "legs":4, "body_size":Vector2(73,45)},
	"breaker": {"label":"BRECHER", "hp":200.0, "speed":20.0, "damage":22.0, "reach":93.0, "cooldown":1.70, "windup":0.58, "burst":1, "burst_gap":0.17, "scale":1.28, "body_y":63.0, "hitbox":Vector2(96,91), "center_y":49.0, "gait":7.2, "scrap":2, "cores":2, "legs":6, "body_size":Vector2(83,55)},
	"assault": {"label":"STURMLÄUFER", "hp":74.0, "speed":36.0, "damage":6.0, "reach":87.0, "cooldown":1.35, "windup":0.24, "burst":3, "burst_gap":0.17, "scale":0.96, "body_y":53.0, "hitbox":Vector2(65,69), "center_y":38.0, "gait":12.0, "scrap":2, "cores":2, "legs":2, "body_size":Vector2(73,48)},
	"colossus": {"label":"KOLOSS", "hp":360.0, "speed":15.0, "damage":36.0, "reach":126.0, "cooldown":2.25, "windup":0.85, "burst":1, "burst_gap":0.17, "scale":1.55, "body_y":98.0, "hitbox":Vector2(115,132), "center_y":72.0, "gait":5.7, "scrap":3, "cores":3, "legs":2, "body_size":Vector2(83,64)},
	"siege": {"label":"BELAGERER", "hp":285.0, "speed":12.0, "damage":58.0, "reach":155.0, "cooldown":3.0, "windup":1.55, "burst":1, "burst_gap":0.17, "scale":1.48, "body_y":79.0, "hitbox":Vector2(116,113), "center_y":59.0, "gait":4.9, "scrap":3, "cores":4, "legs":6, "body_size":Vector2(91,65)},
	"shield_guard": {"label":"SCHILDWACHE", "chassis":"strider", "ability":"shield", "hp":125.0, "speed":23.0, "damage":10.0, "reach":76.0, "cooldown":1.8, "windup":0.42, "burst":1, "burst_gap":0.17, "scale":1.08, "body_y":46.0, "hitbox":Vector2(76,57), "center_y":32.0, "gait":8.5, "scrap":2, "cores":2, "legs":4, "body_size":Vector2(80,51)},
	"lancer": {"label":"LANZENTRÄGER", "chassis":"runner", "ability":"rush", "hp":95.0, "speed":37.0, "damage":17.0, "reach":67.0, "cooldown":1.7, "windup":0.26, "burst":1, "burst_gap":0.17, "scale":0.96, "body_y":39.0, "hitbox":Vector2(63,49), "center_y":29.0, "gait":12.8, "scrap":2, "cores":2, "legs":2, "body_size":Vector2(75,44)},
	"sniper": {"label":"ZIELSUCHER", "chassis":"assault", "ability":"aim", "hp":105.0, "speed":19.0, "damage":27.0, "reach":245.0, "cooldown":3.5, "windup":1.35, "worker_range":295.0, "worker_windup":1.35, "worker_interval":3.5, "worker_damage":28.0, "burst":1, "burst_gap":0.17, "scale":0.98, "body_y":55.0, "hitbox":Vector2(69,73), "center_y":39.0, "gait":7.2, "scrap":2, "cores":3, "legs":2, "body_size":Vector2(74,49)},
	"demolisher": {"label":"SPRENGBRECHER", "chassis":"breaker", "ability":"demolition", "hp":255.0, "speed":15.0, "damage":52.0, "reach":82.0, "cooldown":3.5, "windup":1.7, "burst":1, "burst_gap":0.17, "scale":1.33, "body_y":65.0, "hitbox":Vector2(104,94), "center_y":51.0, "gait":5.7, "scrap":3, "cores":3, "legs":6, "body_size":Vector2(86,59)},
	"repair_crawler": {"label":"INSTANDSETZER", "chassis":"strider", "ability":"repair", "hp":100.0, "speed":21.0, "damage":5.0, "reach":100.0, "cooldown":2.2, "windup":0.5, "burst":1, "burst_gap":0.17, "scale":0.96, "body_y":43.0, "hitbox":Vector2(70,58), "center_y":31.0, "gait":8.0, "scrap":2, "cores":3, "legs":4, "body_size":Vector2(76,50)},
	"bastion": {"label":"BASTION", "chassis":"colossus", "ability":"bastion", "hp":260.0, "speed":12.0, "damage":7.5, "reach":144.0, "cooldown":3.4, "windup":0.7, "burst":6, "burst_gap":0.16, "scale":1.42, "body_y":91.0, "hitbox":Vector2(119,121), "center_y":66.0, "gait":4.9, "scrap":3, "cores":4, "legs":4, "body_size":Vector2(88,65)},
	"scout_car": {"label":"SPÄHWAGEN", "chassis":"scout_car", "ability":"vehicle_gun", "hp":105.0, "speed":39.0, "damage":5.0, "reach":220.0, "cooldown":3.6, "windup":0.8, "worker_range":240.0, "worker_windup":0.8, "worker_interval":3.6, "worker_damage":5.0, "worker_burst":3, "projectile_speed":640.0, "projectile_lifetime":0.65, "burst":3, "burst_gap":0.2, "scale":1.0, "body_y":25.0, "hitbox":Vector2(105,48), "center_y":25.0, "gait":9.0, "scrap":2, "cores":1, "legs":0, "body_size":Vector2(112,44)},
	"mortar_carrier": {"label":"MÖRSERTRÄGER", "chassis":"mortar_carrier", "ability":"vehicle_mortar", "hp":225.0, "speed":13.0, "damage":28.0, "reach":390.0, "cooldown":6.2, "windup":1.8, "worker_range":390.0, "worker_windup":1.8, "worker_interval":6.2, "worker_damage":24.0, "burst":1, "burst_gap":0.25, "scale":1.0, "body_y":22.0, "hitbox":Vector2(118,42), "center_y":23.0, "gait":4.0, "scrap":3, "cores":3, "legs":0, "body_size":Vector2(126,40)},
	"battle_tank": {"label":"KAMPFPANZER", "chassis":"battle_tank", "ability":"vehicle_gun", "hp":280.0, "speed":16.0, "damage":32.0, "reach":330.0, "cooldown":4.8, "windup":1.3, "worker_range":350.0, "worker_windup":1.3, "worker_interval":4.8, "worker_damage":26.0, "projectile_speed":640.0, "projectile_lifetime":0.8, "burst":1, "burst_gap":0.25, "scale":1.0, "body_y":24.0, "hitbox":Vector2(126,58), "center_y":30.0, "gait":4.0, "scrap":3, "cores":3, "legs":0, "body_size":Vector2(126,55)},
	"grenadier": {"label":"GRANATWERFER", "chassis":"assault", "human":true, "ability":"grenade", "hp":76.0, "speed":27.0, "damage":20.0, "reach":330.0, "cooldown":5.8, "windup":1.5, "worker_range":330.0, "worker_windup":1.5, "worker_interval":6.0, "worker_damage":18.0, "burst":1, "burst_gap":0.22, "scale":1.0, "body_y":45.0, "hitbox":Vector2(28,63), "center_y":32.0, "gait":7.0, "scrap":1, "cores":2, "legs":2, "body_size":Vector2(31,54)},
	"rifle_guard": {"label":"SICHERUNGSSCHÜTZE", "chassis":"runner", "human":true, "ability":"infantry_rifle", "hp":52.0, "speed":40.0, "damage":5.0, "reach":230.0, "cooldown":3.8, "windup":0.75, "worker_range":240.0, "worker_windup":0.75, "worker_interval":3.8, "worker_damage":7.0, "burst":2, "burst_gap":0.24, "scale":1.0, "body_y":43.0, "hitbox":Vector2(26,61), "center_y":31.0, "gait":8.5, "scrap":1, "cores":1, "legs":2, "body_size":Vector2(29,53)},
	"scout": {"label":"SPÄHER", "chassis":"runner", "human":true, "ability":"infantry_rifle", "hp":44.0, "speed":48.0, "damage":4.0, "reach":205.0, "cooldown":2.8, "windup":0.48, "worker_range":225.0, "worker_windup":0.48, "worker_interval":2.8, "worker_damage":5.5, "burst":2, "burst_gap":0.21, "scale":1.0, "body_y":43.0, "hitbox":Vector2(25,60), "center_y":30.0, "gait":10.0, "scrap":1, "cores":1, "legs":2, "body_size":Vector2(28,52)},
	"heavy_gunner": {"label":"MG-SCHÜTZE", "chassis":"assault", "human":true, "ability":"infantry_rifle", "hp":104.0, "speed":20.0, "damage":4.5, "reach":280.0, "cooldown":4.8, "windup":1.1, "worker_range":295.0, "worker_windup":1.1, "worker_interval":4.8, "worker_damage":4.5, "worker_burst":4, "burst":4, "burst_gap":0.18, "scale":1.0, "body_y":44.0, "hitbox":Vector2(31,64), "center_y":32.0, "gait":6.0, "scrap":2, "cores":2, "legs":2, "body_size":Vector2(34,55)},
	"marksman": {"label":"PRÄZISIONSSCHÜTZE", "chassis":"assault", "human":true, "ability":"infantry_rifle", "hp":56.0, "speed":24.0, "damage":22.0, "reach":375.0, "cooldown":5.2, "windup":1.65, "worker_range":420.0, "worker_windup":1.65, "worker_interval":5.2, "worker_damage":23.0, "projectile_speed":760.0, "projectile_lifetime":0.75, "burst":1, "burst_gap":0.24, "scale":1.0, "body_y":43.0, "hitbox":Vector2(26,61), "center_y":31.0, "gait":7.0, "scrap":1, "cores":2, "legs":2, "body_size":Vector2(29,53)},
	"combat_medic": {"label":"FELDSANITÄTER", "chassis":"runner", "human":true, "ability":"infantry_medic", "hp":68.0, "speed":30.0, "damage":4.0, "reach":285.0, "cooldown":4.6, "windup":0.9, "worker_range":225.0, "worker_windup":0.9, "worker_interval":4.6, "worker_damage":5.0, "burst":1, "burst_gap":0.24, "scale":1.0, "body_y":43.0, "hitbox":Vector2(28,61), "center_y":31.0, "gait":7.5, "scrap":1, "cores":2, "legs":2, "body_size":Vector2(31,53)},
}

static func is_human(kind: String) -> bool:
	return kind in HUMAN_CLASSES

static func is_vehicle(kind: String) -> bool:
	return kind in VEHICLE_CLASSES

static func human_fireteam(wave: int) -> Array[String]:
	if wave<6: return []
	if wave<8: return ["grenadier","rifle_guard","rifle_guard"]
	var patterns := {
		8:["scout","grenadier","rifle_guard"],
		9:["scout","rifle_guard","rifle_guard"],
		10:["heavy_gunner","grenadier","rifle_guard"],
		11:["heavy_gunner","scout","rifle_guard"],
		12:["marksman","scout","rifle_guard"],
		13:["grenadier","heavy_gunner","marksman"],
		14:["combat_medic","heavy_gunner","rifle_guard"],
		15:["marksman","combat_medic","scout"],
		16:["heavy_gunner","combat_medic","grenadier"],
		17:["marksman","heavy_gunner","combat_medic"],
		18:["scout","grenadier","marksman"],
		19:["scout","heavy_gunner","combat_medic"],
		20:["grenadier","marksman","combat_medic"],
	}
	var result: Array[String]=[]
	result.assign(patterns[clampi(wave,8,20)])
	return result

static func profile(kind: String) -> Dictionary:
	if AirEnemyCatalog.PROFILES.has(kind):
		return AirEnemyCatalog.profile(kind)
	var result: Dictionary = PROFILES.get(kind, PROFILES["strider"]).duplicate(true)
	var size := .82 if is_human(kind) else (.88 if is_vehicle(kind) else .75)
	result.scale *= size
	result.body_y *= size
	result.hitbox *= size
	result.center_y *= size
	return result

static func wave_progress(wave: int) -> float:
	return clampf(float(wave - 1) / 19.0, 0.0, 1.0)

static func hp_scale(wave: int) -> float:
	return lerpf(1.0, MAX_HP_SCALE, wave_progress(wave))

static func speed_scale(wave: int) -> float:
	return lerpf(1.0, MAX_SPEED_SCALE, wave_progress(wave))

static func damage_scale(wave: int) -> float:
	return lerpf(1.0, MAX_DAMAGE_SCALE, wave_progress(wave))

static func is_elite(wave: int, index: int, count: int) -> bool:
	return wave in [5, 10, 15, 20] and count > 0 and index == count - 1

static func air_limit(wave: int) -> int:
	return 0 if wave < 7 else (1 if wave <= 8 else (2 if wave <= 12 else (3 if wave <= 16 else (4 if wave <= 18 else AirEnemyCatalog.MAX_ACTIVE))))

static func wave_roster(wave: int, count: int, allow_air: bool = true) -> Array[String]:
	var roster: Array[String] = []
	var pattern: Array[String] = ["runner", "strider"]
	if wave >= 17:
		pattern = ["mortar_carrier","shield_guard","lancer","strider","bastion","assault","repair_crawler","scout_car","demolisher","colossus","siege","breaker"]
	elif wave >= 16:
		pattern = ["scout_car","shield_guard","assault","lancer","repair_crawler","breaker","sniper","mortar_carrier","colossus","siege"]
	elif wave >= 14:
		pattern = ["scout_car","assault","shield_guard","lancer","sniper","repair_crawler","breaker","mortar_carrier","strider","colossus"]
	elif wave >= 12:
		pattern = ["mortar_carrier","assault","lancer","shield_guard","demolisher","strider","sniper","scout_car","breaker"]
	elif wave >= 10:
		pattern = ["scout_car","shield_guard","lancer","assault","sniper","strider","colossus","breaker"]
	elif wave >= 8:
		pattern = ["scout_car","lancer","strider","shield_guard","assault","breaker"]
	elif wave >= 7:
		pattern = ["scout_car","assault","shield_guard","strider","breaker"]
	elif wave >= 6:
		pattern = ["scout_car","shield_guard","strider","breaker"]
	elif wave >= 4:
		pattern = ["scout_car","strider","runner","breaker","strider"]
	elif wave >= 3:
		pattern = ["scout_car","strider","runner"]
	if wave >= 9: pattern.insert(mini(6,pattern.size()),"battle_tank")
	for index in maxi(count,0):
		roster.append(pattern[index%pattern.size()])
	if roster.is_empty():
		return _add_fireteam(roster,wave)
	# Give every newly introduced chassis a protected slot.
	if wave in [4,5]: roster[-1] = "breaker"
	elif wave == 7: roster[-1] = "assault"
	elif wave in [10,15]: roster[-1] = "colossus"
	elif wave in [16,20]: roster[-1] = "siege"
	var protected: Array[int] = []
	var introduction_slot := 0
	for kind: String in GROUND_CLASSES:
		if is_human(kind) or INTRO_WAVES[kind] != wave: continue
		if roster[-1] == kind:
			protected.append(roster.size()-1)
		elif introduction_slot < roster.size()-1:
			roster[introduction_slot] = kind
			protected.append(introduction_slot)
			introduction_slot += 1
	if is_elite(wave,roster.size()-1,roster.size()) and roster.size()-1 not in protected:
		protected.append(roster.size()-1)
	# Keep a genuine armored ground threat in late mixed attacks. A newly
	# introduced chassis at slot zero retains priority over the returning tank.
	if wave>=15 and 0 not in protected:
		roster[0] = "battle_tank"
		protected.append(0)
	# A late bombardment carrier complements the returning tank. The final
	# campaign boss retains its endpoint; its carrier uses an interior slot.
	if wave>=17 and roster.size()>1:
		var mortar_slot := roster.size()-2 if wave==20 else roster.size()-1
		if mortar_slot not in protected:
			roster[mortar_slot] = "mortar_carrier"
			protected.append(mortar_slot)
	if not allow_air:
		return _add_fireteam(roster,wave,protected)
	var airborne := AirEnemyCatalog.available(wave)
	var new_air := AirEnemyCatalog.introduction(wave)
	# Reserve the complete three-person ground squad before allocating air slots.
	# Very small synthetic rosters never duplicate a replacement or grow in size.
	var available_slots: Array[int] = []
	for at in range(1,roster.size()-1):
		if at not in protected: available_slots.append(at)
	var squad_reserve := 3 if wave >= 6 and available_slots.size() >= 3 else 0
	var air_count := mini(air_limit(wave),maxi(0,available_slots.size()-squad_reserve))
	if airborne.is_empty(): air_count = 0
	var used: Array[int] = []
	for slot in air_count:
		var desired := clampi(int(float(slot+1)*(count-1)/(air_count+1)),1,count-2)
		var at := -1
		var nearest := count+1
		for candidate in available_slots:
			if candidate in used: continue
			var distance := absi(candidate-desired)
			if distance < nearest:
				at = candidate
				nearest = distance
		if at < 0: continue
		used.append(at)
		roster[at] = new_air if slot==0 and not new_air.is_empty() else airborne[(wave*3+slot*5)%airborne.size()]
	return _add_fireteam(roster,wave,protected)

static func _add_fireteam(roster: Array[String],wave: int,protected: Array[int] = []) -> Array[String]:
	if wave<6: return roster
	var slots: Array[int]=[]
	for index in range(1,roster.size()-1):
		if index not in protected and not AirEnemyCatalog.is_air(roster[index]): slots.append(index)
	if slots.size()<3: return roster
	# The original introduction, aircraft and final elite/boss slots stay intact.
	var team := human_fireteam(wave)
	for index in team.size(): roster[slots[index]]=team[index]
	return roster
