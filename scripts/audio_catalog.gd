extends RefCounted
## Offline-authored recordings. Playback never scans directories or loads per frame.

const MUSIC_SETS := {
	"base":{"calm":"music_calm.ogg", "combat":"music_combat.ogg"},
	"foundry":{"calm":"music_foundry_calm.ogg", "combat":"music_foundry_combat.ogg"},
	"tidal":{"calm":"music_tidal_calm.ogg", "combat":"music_tidal_combat.ogg"},
	"frost":{"calm":"music_frost_calm.ogg", "combat":"music_frost_combat.ogg"},
	"glutkern":{"calm":"music_rave_glutkern_v2_calm.ogg","combat":"music_rave_glutkern_v2_combat.ogg"},
	"basalttakt":{"calm":"music_rave_basalttakt_v2_calm.ogg","combat":"music_rave_basalttakt_v2_combat.ogg"},
	"wurzelstrom":{"calm":"music_rave_wurzelstrom_v2_calm.ogg","combat":"music_rave_wurzelstrom_v2_combat.ogg"},
	"eisenhall":{"calm":"music_rave_eisenhall_v2_calm.ogg","combat":"music_rave_eisenhall_v2_combat.ogg"},
	"hafennebel":{"calm":"music_rave_hafennebel_v2_calm.ogg","combat":"music_rave_hafennebel_v2_combat.ogg"},
	"tiefenpuls":{"calm":"music_rave_tiefenpuls_v2_calm.ogg","combat":"music_rave_tiefenpuls_v2_combat.ogg"},
	"frostsignal":{"calm":"music_rave_frostsignal_v2_calm.ogg","combat":"music_rave_frostsignal_v2_combat.ogg"},
	"hoehenlicht":{"calm":"music_rave_hoehenlicht_v2_calm.ogg","combat":"music_rave_hoehenlicht_v2_combat.ogg"},
	"unterstrom":{"calm":"music_rave_unterstrom_v2_calm.ogg","combat":"music_rave_unterstrom_v2_combat.ogg"},
}
const ENVIRONMENT_SCORES := {
	"storm_dam":"tiefenpuls", "sulfur_refinery":"glutkern", "radar_highlands":"frostsignal", "buried_megafactory":"unterstrom",
	"sector07":"unterstrom", "ash_foundry":"glutkern", "basalt_quarry":"basalttakt",
	"overgrown_steelworks":"wurzelstrom", "iron_canyon":"eisenhall",
	"abandoned_harbor":"hafennebel", "flooded_power_station":"tiefenpuls",
	"frozen_rail_yard":"frostsignal", "mountain_pass":"hoehenlicht",
}
const VARIANT_COUNTS := {
	"shot":3, "enemy_shot":3, "hit":3, "mine":3, "pickup":3, "build":3,
	"reload":2, "produce":2, "empty":2, "explosion":2, "warning":1, "start":1,
	"thunder":1, "shotgun":3, "cannon":3, "arc":3, "impact_metal":3,
	"impact_stone":3, "impact_wood":3, "glass_break":3, "impact_core":5,
	"ricochet_metal":2, "ricochet_stone":1,
	"reload_rifle_open":3, "reload_rifle_load":3, "reload_rifle_close":3,
	"reload_shotgun_open":3, "reload_shotgun_load":3, "reload_shotgun_close":3,
	"reload_arc_open":3, "reload_arc_load":3, "reload_arc_close":3,
	"reload_cannon_open":3, "reload_cannon_load":3, "reload_cannon_close":3,
	"reload_flak_open":3, "reload_flak_load":3, "reload_flak_close":3,
	"weapon_mount":3, "weapon_switch":3,
	"air_dart":3, "air_tracer":3, "air_rocket":3, "air_bomb":3,
	"air_arc":3, "air_charge":2, "air_lock":2, "air_crash":3,
	"medical_heal":2, "medical_revive":2,
}
const ALIASES := {
	"alarm":"warning", "interact":"pickup", "ready":"produce", "break":"explosion",
	"shot_rifle":"shot", "shot_shotgun":"shotgun", "shot_cannon":"cannon", "shot_arc":"arc",
	"mine_metal":"impact_metal", "mine_stone":"impact_stone",
	"mortar_shot":"cannon", "enemy_shotgun":"shotgun",
}
const COOLDOWN_MS := {
	"shot":75, "enemy_shot":110, "hit":100, "mine":145, "pickup":190,
	"build":180, "reload":350, "produce":400, "empty":350, "explosion":160,
	"warning":3000, "start":1000, "thunder":1500, "shotgun":140, "cannon":150,
	"arc":110, "impact_metal":145, "impact_stone":145, "impact_wood":145, "glass_break":120, "impact_core":145,
	"ricochet_metal":125, "ricochet_stone":145,
	"reload_rifle_open":90, "reload_rifle_load":90, "reload_rifle_close":90,
	"reload_shotgun_open":90, "reload_shotgun_load":90, "reload_shotgun_close":90,
	"reload_arc_open":90, "reload_arc_load":90, "reload_arc_close":90,
	"reload_cannon_open":90, "reload_cannon_load":90, "reload_cannon_close":90,
	"reload_flak_open":90, "reload_flak_load":90, "reload_flak_close":90,
	"weapon_mount":90, "weapon_switch":90,
	"air_dart":110, "air_tracer":95, "air_rocket":180, "air_bomb":220,
	"air_arc":160, "air_charge":650, "air_lock":750, "air_crash":220,
	"medical_heal":350, "medical_revive":500,
}
const LEVEL_DB := {
	"shot":-12.0, "enemy_shot":-15.0, "hit":-18.0, "mine":-17.0, "pickup":-15.0,
	"build":-15.0, "reload":-14.0, "produce":-17.0, "empty":-19.0,
	"explosion":-11.0, "warning":-16.0, "start":-15.0, "thunder":-17.0,
	"shotgun":-12.0, "cannon":-8.0, "arc":-15.0, "impact_metal":-18.0,
	"impact_stone":-17.0, "impact_wood":-17.0, "glass_break":-18.0, "impact_core":-18.0,
	"ricochet_metal":-16.0, "ricochet_stone":-17.0,
	"reload_rifle_open":-2.0, "reload_rifle_load":-2.0, "reload_rifle_close":-2.0,
	"reload_shotgun_open":-2.0, "reload_shotgun_load":-2.0, "reload_shotgun_close":-2.0,
	"reload_arc_open":-2.0, "reload_arc_load":-2.0, "reload_arc_close":-2.0,
	"reload_cannon_open":-2.0, "reload_cannon_load":-2.0, "reload_cannon_close":-2.0,
	"reload_flak_open":-2.0, "reload_flak_load":-2.0, "reload_flak_close":-2.0,
	"weapon_mount":-10.0, "weapon_switch":-10.0,
	"air_dart":-13.0, "air_tracer":-13.0, "air_rocket":-11.0, "air_bomb":-13.0,
	"air_arc":-12.0, "air_charge":-14.0, "air_lock":-14.0, "air_crash":-10.0,
	"medical_heal":-8.0, "medical_revive":-8.0,
}
# Five percent more source amplitude for weapon fire and physical contacts.
# Shared material contacts also retain this level when used by the pickaxe.
const SHOT_HIT_GAIN_DB := 0.4237859813987618
const SHOT_HIT_KINDS := [
	"shot", "enemy_shot", "shotgun", "cannon", "arc", "hit", "explosion",
	"impact_metal", "impact_stone", "impact_wood", "glass_break", "impact_core",
	"ricochet_metal", "ricochet_stone",
	"air_dart", "air_tracer", "air_rocket", "air_bomb", "air_arc", "air_crash",
]
const PRIORITY := {
	"shot":4, "shotgun":4, "cannon":5, "arc":4, "explosion":4,
	"warning":5, "start":5, "reload":3, "thunder":1, "impact_core":4,
	"ricochet_metal":3, "ricochet_stone":2,
	"reload_rifle_open":5, "reload_rifle_load":5, "reload_rifle_close":5,
	"reload_shotgun_open":5, "reload_shotgun_load":5, "reload_shotgun_close":5,
	"reload_arc_open":5, "reload_arc_load":5, "reload_arc_close":5,
	"reload_cannon_open":5, "reload_cannon_load":5, "reload_cannon_close":5,
	"reload_flak_open":5, "reload_flak_load":5, "reload_flak_close":5,
	"weapon_mount":3, "weapon_switch":3,
	"air_dart":3, "air_tracer":3, "air_rocket":4, "air_bomb":4,
	"air_arc":4, "air_charge":5, "air_lock":5, "air_crash":4,
	"medical_heal":4, "medical_revive":5,
}

static func score_for_environment(environment_id: String) -> String:
	return ENVIRONMENT_SCORES.get(environment_id, "base")

static func effect_level_db(requested_kind: String) -> float:
	var kind: String = ALIASES.get(requested_kind, requested_kind)
	return float(LEVEL_DB.get(kind, -16.0)) + (SHOT_HIT_GAIN_DB if kind in SHOT_HIT_KINDS else 0.0)

static func score_gain_db(score_id: String) -> float:
	# New originals are mastered at the same -16.5 LUFS as native music. Older
	# recordings retain their historical source trim.
	return 7.0 if score_id in preload("res://scripts/rave_music_catalog.gd").TRACKS else 0.0
