class_name PerimeterCatalog
extends RefCounted
## Small finite outposts. Prices are real cargo, deposited one item at a time.
const VALID_ROLES := ["fence","ground"]
# The outer mesh is existing site infrastructure, like the bunker entrance.
# It grants neither construction XP nor refundable cargo. Reconstruction is paid.
const STARTER_FENCE_TIER := 1
const SITES := [
	{"id":"ground_rear","role":"ground","distance":260.0},
	{"id":"ground_front","role":"ground","distance":350.0},
	{"id":"fence","role":"fence","distance":445.0},
]
const MUZZLE := Vector2(45.0,-39.0*45.0/282.0)
const BURST_SIZE := 3
const BURST_INTERVAL := .14
const FENCE_PORT_TOP := -44.0
const FENCE_PORT_BOTTOM := -32.0
const FENCE := {
	1:{"label":"Feldzaun","cost":{"steel":2},"wave":1,"tech":"","hp":120.0,"time":1.8,"cure":0.0,"repair":"steel","repair_hp":60.0},
	2:{"label":"Betonzaun","cost":{"concrete":3,"steel":1},"wave":6,"tech":"bunker_armor","hp":320.0,"time":2.4,"cure":8.0,"repair":"concrete","repair_hp":100.0},
	3:{"label":"Stahlzaun","cost":{"alloy":2,"steel":2},"wave":11,"tech":"bunker_armor","hp":620.0,"time":3.0,"cure":0.0,"repair":"steel","repair_hp":125.0},
}
const GUNS := {
	"ground":{"label":"Bodenwache","cost":{"steel":2,"concrete":1},"wave":11,"tech":"perimeter_automation","hp":160.0,"time":3.0,"cure":0.0,"repair":"steel","repair_hp":80.0,"damage":10.0,"interval":1.7,"range":580.0,"capacity":40,"pivot":Vector2(0,-32)},
}
const TECH_NAMES := {"bunker_armor":"VERBUNDWÄNDE","perimeter_automation":"AUSSENWACHE"}
const AMMO_PER_CRATE := 20
const TRANSFER_TIME := .3
const SERVICE_TIME := .85
const MAX_ACTIVE_SHOTS := 12

static func spec(role: String,tier: int) -> Dictionary:
	return FENCE[clampi(tier,1,3)] if role=="fence" else GUNS.get(role,GUNS.ground)

static func max_tier(role: String) -> int:
	return 3 if role=="fence" else 1
