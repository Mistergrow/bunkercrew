extends RefCounted
## Ambient species belong to the authored climate. Wildlife is presentation
## only: no drops, network IDs, combat targets, or physics bodies.
const ATLAS_PATH := "res://assets/environments/life/fauna_v1.png"
const SOURCE_PATH := "res://assets/environments/life/fauna_v1.source.json"
const SPECIES_ORDER := ["mouse","crow","gull","sparrow","frog","rabbit","moth","bat"]
const WORLD_LEFT := -410.0
const WORLD_RIGHT := 1850.0
const GROUND_Y := 430.0
const MAX_POPULATION := 2
const SPECIES := {
	"mouse":{"mode":"ground","size":Vector2(17,10),"speed":17.0,"flight_speed":82.0,"threat_radius":92.0,"fps":14.0,"anchor":Vector2(.5,1)},
	"crow":{"mode":"bird","size":Vector2(26,22),"speed":45.0,"flight_speed":111.0,"threat_radius":145.0,"fps":8.0,"anchor":Vector2(.5,1)},
	"gull":{"mode":"bird","size":Vector2(31,25),"speed":53.0,"flight_speed":123.0,"threat_radius":140.0,"fps":7.0,"anchor":Vector2(.5,1)},
	"sparrow":{"mode":"bird","size":Vector2(17,14),"speed":56.0,"flight_speed":132.0,"threat_radius":113.0,"fps":12.0,"anchor":Vector2(.5,1)},
	"frog":{"mode":"hopper","size":Vector2(13,9),"speed":13.0,"flight_speed":43.0,"threat_radius":68.0,"fps":9.0,"anchor":Vector2(.5,1)},
	"rabbit":{"mode":"hopper","size":Vector2(23,17),"speed":22.0,"flight_speed":90.0,"threat_radius":119.0,"fps":11.0,"anchor":Vector2(.5,1)},
	"moth":{"mode":"insect","size":Vector2(9,8),"speed":9.0,"flight_speed":21.0,"threat_radius":36.0,"fps":15.0,"anchor":Vector2(.5,.5)},
	"bat":{"mode":"flyer","size":Vector2(23,17),"speed":42.0,"flight_speed":106.0,"threat_radius":107.0,"fps":13.0,"anchor":Vector2(.5,.5)},
}
const PROFILES := {
	"sector07":{"habitat":"industrial","wetland":false,"cold":false,"species":{"mouse":1},"air_height":Vector2(210,370)},
	"ash_foundry":{"habitat":"dry_industrial","wetland":false,"cold":false,"species":{"mouse":1},"air_height":Vector2(195,360)},
	"abandoned_harbor":{"habitat":"coastal","wetland":true,"cold":false,"species":{"mouse":1,"frog":1},"air_height":Vector2(190,365)},
	"basalt_quarry":{"habitat":"rocky","wetland":false,"cold":false,"species":{"mouse":1,"rabbit":1},"air_height":Vector2(205,360)},
	"overgrown_steelworks":{"habitat":"woodland","wetland":true,"cold":false,"species":{"mouse":1,"frog":1},"air_height":Vector2(220,382)},
	"frozen_rail_yard":{"habitat":"frozen","wetland":false,"cold":true,"species":{"rabbit":1},"air_height":Vector2(200,350)},
	"iron_canyon":{"habitat":"arid","wetland":false,"cold":false,"species":{"mouse":1},"air_height":Vector2(180,360)},
	"flooded_power_station":{"habitat":"wetland","wetland":true,"cold":false,"species":{"frog":1,"mouse":1},"air_height":Vector2(220,382)},
	"mountain_pass":{"habitat":"mountain","wetland":false,"cold":false,"species":{"rabbit":1,"mouse":1},"air_height":Vector2(190,360)},
	"storm_dam":{"habitat":"waterside","wetland":true,"cold":false,"species":{"frog":1},"air_height":Vector2(185,365)},
	"sulfur_refinery":{"habitat":"dry_industrial","wetland":false,"cold":false,"species":{"mouse":1},"air_height":Vector2(215,370)},
	"radar_highlands":{"habitat":"cold_highland","wetland":false,"cold":true,"species":{"rabbit":1},"air_height":Vector2(170,345)},
	"buried_megafactory":{"habitat":"industrial_shadow","wetland":false,"cold":false,"species":{"mouse":1},"air_height":Vector2(230,380)},
}

static func profile(environment_id: String) -> Dictionary:
	return Dictionary(PROFILES.get(environment_id,PROFILES.sector07)).duplicate(true)

static func species_data(species: String) -> Dictionary:
	return Dictionary(SPECIES.get(species,SPECIES.mouse)).duplicate()

static func ground_ranges(bunker_left: float,bunker_right: float,world_left := WORLD_LEFT,world_right := WORLD_RIGHT) -> Array[Vector2]:
	var result: Array[Vector2] = []
	# Leave doors, service paths, and the outer terrain edge clear. These are
	# authored floor extents, rather than the painted panoramic landscape.
	if bunker_left-48.0>world_left+30.0:
		result.append(Vector2(world_left+30.0,minf(bunker_left-48.0,world_right-30.0)))
	if world_right-30.0>bunker_right+48.0:
		result.append(Vector2(maxf(bunker_right+48.0,world_left+30.0),world_right-30.0))
	return result

static func population(environment_id: String) -> int:
	var total := 0
	for count: int in profile(environment_id).species.values(): total += count
	return mini(total,MAX_POPULATION)

static func airborne(species: String) -> bool:
	return str(SPECIES.get(species,SPECIES.mouse).mode) in ["bird","flyer","insect"]
