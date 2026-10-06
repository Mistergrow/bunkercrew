class_name AircraftArtCatalog
extends RefCounted
## Regions sample the immutable generated aircraft plate; each crop includes only
## its own alpha island, rather than relying on approximate atlas grid cells.
const TEXTURE_PATH := "res://assets/enemies/aircraft_hulls_v1.png"
const REGIONS := {
	"scout_drone":Rect2(48,137,281,150),
	"gunship":Rect2(368,123,383,167),
	"bomber":Rect2(773,73,409,219),
	"interceptor":Rect2(1211,96,431,194),
	"shield_airship":Rect2(30,385,340,212),
	"sky_fortress":Rect2(387,374,434,214),
	"rocket_drone":Rect2(881,406,270,157),
	"patrol_plane":Rect2(1209,401,424,171),
	"tiltrotor":Rect2(44,656,345,211),
	"dive_bomber":Rect2(407,667,396,191),
	"pulse_fighter":Rect2(823,664,348,223),
	"heavy_zeppelin":Rect2(1193,676,463,213),
}
const SOCKETS := {
	"scout_drone":[Vector2(144,151),Vector2(269,151)],
	"gunship":[Vector2(515,137)],
	"bomber":[Vector2(847,109),Vector2(1130,88)],
	"interceptor":[Vector2(1609,205)],
	"shield_airship":[Vector2(117,557),Vector2(255,557)],
	"sky_fortress":[Vector2(477,389),Vector2(729,389),Vector2(429,479),Vector2(785,479)],
	"rocket_drone":[Vector2(907,421),Vector2(1122,428)],
	"patrol_plane":[Vector2(1232,506)],
	"tiltrotor":[Vector2(66,674),Vector2(345,678)],
	"dive_bomber":[Vector2(429,786)],
	"pulse_fighter":[Vector2(1138,752),Vector2(1142,790)],
	"heavy_zeppelin":[Vector2(1292,847),Vector2(1508,847)],
}

static func hull_size(kind: String, width: float) -> Vector2:
	var region: Rect2 = REGIONS.get(kind,REGIONS.scout_drone)
	return Vector2(width,width*region.size.y/region.size.x)

static func engine_points(kind: String, width: float) -> Array[Vector2]:
	var region: Rect2 = REGIONS.get(kind,REGIONS.scout_drone)
	var points: Array[Vector2] = []
	for source: Vector2 in SOCKETS.get(kind,SOCKETS.scout_drone):
		points.append((source-region.get_center())*width/region.size.x)
	return points
