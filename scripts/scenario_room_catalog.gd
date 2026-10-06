class_name ScenarioRoomCatalog
extends RefCounted
## All room costs, unlocks and benefits share one source with the build panels.
const ROOM_WIDTH := 640.0
const FLOOR_STEP := 205.0
const SUPPORT_TIME := 2.0
const SUPPORT_COST := {"steel":2}
const BUILD_TIME := 2.8
const CURE_TIME := 6.0
const BUILD_TYPES := {
	"bastion": {"title":"BETONBASTION", "description":"Massive Betonrippen · Kern +120 LP", "core_bonus":120.0, "extra_steel":0, "extra_concrete":0, "ore_bonus":0},
	"workshop": {"title":"STAHLWERK", "description":"Genietete Stahlträger · +6 Stahl / +2 Beton", "core_bonus":0.0, "extra_steel":6, "extra_concrete":2, "ore_bonus":0},
	"stronghold": {"title":"FELSENFESTE", "description":"In den Fels gesetztes Tragwerk · Adern +2 Ertrag", "core_bonus":0.0, "extra_steel":0, "extra_concrete":0, "ore_bonus":2},
}
const ROOMS := [
	{"id":"foundry", "title":"VERSORGUNGSGALERIE", "wave":1, "cost":{"concrete":4,"steel":3}, "core_bonus":40.0, "benefit":"Munition pressen · Erzlager · tragende Rückwand", "station":"ammo_press", "seams":["ore","sand","ore"]},
	{"id":"glassworks", "title":"GLASWERK", "wave":5, "cost":{"concrete":6,"steel":4}, "core_bonus":60.0, "benefit":"Sand + Kalkstein → Glas · neue Rohstoffadern", "station":"glass_furnace", "seams":["sand","limestone","ore"]},
	{"id":"alloy", "title":"TIEFENSCHMELZE", "wave":10, "cost":{"concrete":8,"steel":6}, "core_bonus":80.0, "benefit":"Wolframerz + Stahl → Panzerstahl · Tiefenerze", "station":"alloy_furnace", "seams":["tungsten","ore","tungsten"]},
	{"id":"arsenal", "title":"FESTUNGSARSENAL", "wave":15, "cost":{"concrete":10,"steel":6,"alloy":2}, "core_bonus":100.0, "benefit":"Zweite Munitionspresse · Dachgeschütz +25 % Schaden", "station":"ammo_press", "seams":["tungsten","limestone","ore"]},
]

static func spec(index: int) -> Dictionary:
	return ROOMS[clampi(index,0,ROOMS.size()-1)]

static func floor_y(index: int) -> float:
	return 430.0 + FLOOR_STEP * float(index+1)

static func style(key: String) -> Dictionary:
	return BUILD_TYPES.get(key,BUILD_TYPES.bastion)
