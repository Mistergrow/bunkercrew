class_name ConvoyJourney
extends RefCounted
## Pure, bounded journey state. The host owns all advances and tool actions;
## the single dictionary also drives reconnect-safe local art, UI and sound.
const VERSION := 1
const PHASE_IDS := ["garage","boarding","departure","starting","driving","repair","reboarding","complete","failed"]
const STEPS := ["none","jack","remove","fit","tighten","lower","done"]
const EVENT_KINDS := ["boarding","departure","engine_start","breakdown","jack","remove","fit","bolt","tool_miss","lower","repair_complete","route_complete","failed"]
const QUALITIES := ["normal","good","assisted"]
const MAX_EVENTS := 16
const MAX_SERIAL := 1000000000
const MAX_CLOCK := 2160.0
const DEPARTURE_TIME := 1.2
const START_TIME := 0.8
const REBOARD_TIME := 0.65
const BREAKDOWN_PROGRESS := 0.35
const TIMING_PERIOD := 1.35
const TIMING_START := 0.60
const TIMING_END := 0.85
const BOLT_HOLD_TIME := 2.6
const HOLD_TIMES := {"jack":2.0,"remove":1.8,"fit":2.0,"lower":1.5}
const BREAKDOWN_ROUTES := ["harbor","quarry","rail_yard","canyon","mountain_pass","dam_vault","radar_archive","buried_archive"]
const STATE_KEYS := ["version","phase","phase_time","breakdown_done","repair_step","repair_work","repair_bolts","repair_cursor","repair_operator","repair_retry","event_serial","events","solo_assist"]

static func new_state(phase: String="garage", after_stop: bool=false) -> Dictionary:
	return {"version":VERSION,"phase":phase if phase in PHASE_IDS else "garage","phase_time":0.0,"breakdown_done":after_stop,"repair_step":"done" if after_stop else "none","repair_work":0.0,"repair_bolts":0,"repair_cursor":0.0,"repair_operator":0,"repair_retry":0.0,"event_serial":0,"events":[],"solo_assist":false}

static func breakdown_required(destination: String) -> bool:
	return destination in BREAKDOWN_ROUTES

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func valid_state(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=STATE_KEYS.size(): return false
	for key: String in STATE_KEYS:
		if not data.has(key): return false
	if not data.version is int or data.version!=VERSION or not data.phase is String or not data.phase in PHASE_IDS: return false
	if not data.breakdown_done is bool or not data.solo_assist is bool or not data.repair_step is String or not data.repair_step in STEPS: return false
	if not _number(data.phase_time,0,MAX_CLOCK) or not _number(data.repair_work,0,1) or not _number(data.repair_cursor,0,1) or not _number(data.repair_retry,0,.5): return false
	if not data.repair_bolts is int or data.repair_bolts<0 or data.repair_bolts>3: return false
	if not data.repair_operator is int or data.repair_operator<0 or data.repair_operator>PartyConfig.MAX_PLAYERS: return false
	if not data.event_serial is int or data.event_serial<0 or data.event_serial>MAX_SERIAL: return false
	if not data.events is Array or data.events.size()>MAX_EVENTS: return false
	var previous := maxi(0,int(data.event_serial)-MAX_EVENTS)
	for trip_event in data.events:
		if not trip_event is Dictionary or trip_event.size()!=3 or not trip_event.get("serial") is int: return false
		if trip_event.serial<=previous or trip_event.serial>data.event_serial or not trip_event.get("kind") is String or not trip_event.kind in EVENT_KINDS or not trip_event.get("quality") is String or not trip_event.quality in QUALITIES: return false
		previous=int(trip_event.serial)
	if data.events.is_empty()!=bool(data.event_serial==0): return false
	if not data.events.is_empty() and data.events.back().serial!=data.event_serial: return false
	if data.breakdown_done and data.repair_step!="done": return false
	if data.phase=="repair" and (data.breakdown_done or not data.repair_step in ["jack","remove","fit","tighten","lower"]): return false
	if data.repair_step in ["jack","remove","fit"] and data.repair_bolts!=0: return false
	if data.repair_step=="lower" and data.repair_bolts!=3: return false
	if data.repair_step=="tighten" and data.repair_bolts>=3: return false
	if data.repair_operator!=0 and data.phase!="repair": return false
	if data.solo_assist and data.phase!="repair": return false
	return true

static func event(data: Dictionary, kind: String, quality: String="normal") -> void:
	if not kind in EVENT_KINDS or not quality in QUALITIES or int(data.event_serial)>=MAX_SERIAL: return
	data.event_serial=int(data.event_serial)+1
	data.events.append({"serial":data.event_serial,"kind":kind,"quality":quality})
	while data.events.size()>MAX_EVENTS: data.events.pop_front()

static func change_phase(data: Dictionary, phase: String, kind: String="") -> void:
	if not phase in PHASE_IDS: return
	data.phase=phase
	data.phase_time=0.0
	data.repair_operator=0
	if phase!="repair": data.solo_assist=false
	if not kind.is_empty(): event(data,kind)

static func advance(data: Dictionary, delta: float) -> void:
	if not is_finite(delta) or delta<=0: return
	var step := minf(delta,.1)
	data.phase_time=minf(MAX_CLOCK,float(data.phase_time)+step)
	data.repair_retry=maxf(0,float(data.repair_retry)-step)
	if data.phase=="repair": data.repair_cursor=fmod(float(data.phase_time)/TIMING_PERIOD,1.0)

static func begin_breakdown(data: Dictionary) -> bool:
	if data.phase!="driving" or data.breakdown_done: return false
	change_phase(data,"repair","breakdown")
	data.repair_step="jack"
	data.repair_work=0.0
	data.repair_bolts=0
	data.repair_cursor=0.0
	data.repair_retry=0.0
	event(data,"jack")
	return true

static func _next_step(data: Dictionary, step: String) -> void:
	data.repair_step=step
	data.repair_work=0.0
	data.repair_cursor=0.0
	data.phase_time=0.0
	event(data,step)

static func service(data: Dictionary, delta: float, tapped: bool, held: bool, operator: int) -> bool:
	if data.phase!="repair" or not is_finite(delta) or delta<=0 or delta>.1 or operator<1 or operator>PartyConfig.MAX_PLAYERS or (not tapped and not held): return false
	data.repair_operator=operator
	if data.repair_step=="tighten":
		if float(data.repair_retry)>0: return false
		var good: bool=tapped and float(data.repair_cursor)>=TIMING_START and float(data.repair_cursor)<=TIMING_END
		if tapped and not good:
			data.repair_retry=.30
			event(data,"tool_miss")
			return false
		if held: data.repair_work=minf(1,float(data.repair_work)+delta/BOLT_HOLD_TIME)
		if not good and float(data.repair_work)<1: return false
		data.repair_bolts=int(data.repair_bolts)+1
		data.repair_work=0.0
		data.repair_retry=.22
		event(data,"bolt","good" if good else "assisted")
		if int(data.repair_bolts)>=3: _next_step(data,"lower")
		return true
	if not held or not HOLD_TIMES.has(data.repair_step): return false
	data.repair_work=minf(1,float(data.repair_work)+delta/float(HOLD_TIMES[data.repair_step]))
	if float(data.repair_work)<1: return false
	match data.repair_step:
		"jack": _next_step(data,"remove")
		"remove": _next_step(data,"fit")
		"fit": _next_step(data,"tighten")
		"lower":
			data.repair_step="done"
			data.breakdown_done=true
			change_phase(data,"reboarding","repair_complete")
	return true
