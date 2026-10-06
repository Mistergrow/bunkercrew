extends RefCounted
## Authored distant flybys. They provide atmosphere, never combat, loot or a
## control lock. Every client selects the same two slots from the route ID.
const ORDER: Array[String] = ["survey_pair", "low_transport", "jet_crossing", "heavy_transit"]
const DEFINITIONS := {
	"survey_pair":{"kind":"patrol_plane","duration":11.0,"count":2,"width":76.0,"altitude":245.0,"arc":18.0,"direction":-1.0,"bank":.055,"spacing":Vector2(68,-26),"cloud_cell":0},
	"low_transport":{"kind":"tiltrotor","duration":12.0,"count":1,"width":103.0,"altitude":205.0,"arc":26.0,"direction":1.0,"bank":.10,"spacing":Vector2.ZERO,"cloud_cell":2},
	"jet_crossing":{"kind":"interceptor","duration":7.5,"count":2,"width":86.0,"altitude":260.0,"arc":-17.0,"direction":-1.0,"bank":.07,"spacing":Vector2(94,-19),"cloud_cell":1},
	"heavy_transit":{"kind":"heavy_zeppelin","duration":14.0,"count":1,"width":128.0,"altitude":238.0,"arc":-5.0,"direction":1.0,"bank":.012,"spacing":Vector2.ZERO,"cloud_cell":3},
}
const ROUTES := {
	"harbor":"survey_pair", "quarry":"low_transport", "steelworks":"heavy_transit",
	"rail_yard":"survey_pair", "canyon":"jet_crossing", "power_station":"heavy_transit",
	"mountain_pass":"jet_crossing", "dam_vault":"low_transport",
	"refinery_archive":"heavy_transit", "radar_archive":"jet_crossing", "buried_archive":"low_transport",
}
const FIRST_AT := 4.0
const SECOND_AT := 33.0
const MAX_AIRCRAFT := 2

static func slots(destination: String, after_stop: bool=false) -> Array[Dictionary]:
	if not ROUTES.has(destination): return []
	var first: int = ORDER.find(str(ROUTES[destination]))
	if after_stop: first = posmod(first+1, ORDER.size())
	return [{"id":ORDER[first],"at":FIRST_AT},{"id":ORDER[posmod(first+1,ORDER.size())],"at":SECOND_AT}]

static func active(destination: String, clock: float, after_stop: bool=false) -> Dictionary:
	if not is_finite(clock) or clock<0: return {}
	for slot: Dictionary in slots(destination,after_stop):
		var spec: Dictionary = DEFINITIONS[slot.id]
		var elapsed := clock-float(slot.at)
		if elapsed>=0 and elapsed<float(spec.duration):
			var result: Dictionary = spec.duplicate(true)
			result.id = slot.id
			result.elapsed = elapsed
			result.progress = elapsed/float(spec.duration)
			return result
	return {}

static func pose(spec: Dictionary, index: int, view: Rect2, road_y: float=430.0) -> Dictionary:
	if spec.is_empty() or index<0 or index>=int(spec.get("count",0)) or not view.is_finite(): return {}
	var duration := float(spec.duration)
	var elapsed := float(spec.elapsed)-float(index)*.32
	var phase := clampf(elapsed/duration,0,1)
	var direction := float(spec.direction)
	var spacing: Vector2 = spec.spacing
	var crossing := phase if direction>0 else 1.0-phase
	var x := lerpf(view.position.x-180,view.end.x+180,crossing)-direction*spacing.x*index
	var arc := sin(phase*PI)
	var y := road_y-float(spec.altitude)+float(spec.arc)*arc+spacing.y*index
	var fade := smoothstep(0.0,.75,elapsed)*(1.0-smoothstep(duration-1.0,duration,elapsed))
	return {"position":Vector2(x,y),"rotation":direction*float(spec.bank)*sin(phase*TAU),
		"facing":-direction,"alpha":fade,"velocity":Vector2(direction*(view.size.x+360)/duration,float(spec.arc)*PI*cos(phase*PI)/duration)}
