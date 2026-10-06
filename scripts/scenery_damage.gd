extends Node
## Host-owned cosmetic damage. No collision body, loot or gameplay target is added.
signal state_changed(index: int, state: Dictionary)
const MAX_ENTRIES := 96
const BURN_SECONDS := 8.0
const MAX_SERIAL := 2147483647
const PropArt := preload("res://scripts/scenario_prop_art.gd")
const FLEXIBLE := ["grass","frost_grass","brush","reeds","windsock","bollard","cable","tape","vines"]
const HEALTH := {"tree":72.0,"brush":18.0,"grass":10.0,"frost_grass":10.0,"reeds":14.0,"vines":24.0,"windsock":28.0,"tape":16.0,"cable":40.0,"fan":90.0,"bollard":100.0,"ore_cart":110.0,"signal":64.0,"pipe":85.0,"generator":110.0,"pump":90.0,"transformer":120.0,"relay_antenna":75.0,"crane_hook":105.0,"cargo_beacon":100.0}
const FLAMMABLE := ["tree","brush","grass","frost_grass","reeds","vines","windsock","tape"]
const HOT := ["arcgun","arc","bomb","rocket","explosion","fire","flame"]
var props: Node2D
var states: Dictionary = {}
var replica_only := false
var _geometry: Dictionary = {}
var _geometry_ticks: Dictionary = {}
var _rain_clock := 0.0
var _rain_exposure: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("scenery_damage")
	if not is_instance_valid(props): return
	for entry: Dictionary in props.entries.slice(0,MAX_ENTRIES):
		var kind := str(entry.kind)
		if not HEALTH.has(kind): continue
		var index := int(entry.index)
		var broken := str(entry.get("initial_state","intact"))=="broken"
		var burning := not broken and kind in FLAMMABLE and str(entry.get("initial_state","intact"))=="burning"
		states[index] = {"hp":0.0 if broken else float(HEALTH[kind]),"burning":burning,"charred":burning,"burn_left":BURN_SECONDS if burning else 0.0,"broken":broken,"serial":0,"hit":props.to_global(entry.position),"direction":Vector2.RIGHT}
		_geometry[index] = _shape(entry)

func is_authority() -> bool:
	if replica_only or not is_inside_tree() or get_tree().paused: return false
	var game = props.get("game") if is_instance_valid(props) else null
	var network = game.get("network") if is_instance_valid(game) else null
	return not is_instance_valid(network) or not bool(network.get("active")) or bool(network.get("is_host"))

func state_for(index: int) -> Dictionary:
	return states.get(index,{})

func target_point(index: int) -> Vector2:
	var entry := _entry(index)
	var shape := _geometry_for(index)
	if entry.is_empty() or shape.is_empty(): return Vector2.INF
	if not shape.segments.is_empty():
		var segment: Dictionary = shape.segments[0]
		return props.to_global(entry.position+Vector2(segment.from).lerp(segment.to,.5))
	if not shape.rects.is_empty(): return props.to_global(entry.position+Rect2(shape.rects[0]).get_center())
	return Vector2.INF

func _geometry_for(index: int) -> Dictionary:
	var entry := _entry(index)
	if entry.is_empty(): return {}
	if str(entry.kind) in FLEXIBLE and _geometry_ticks.get(index,-1)!=Engine.get_physics_frames():
		_geometry_ticks[index] = Engine.get_physics_frames()
		var clock := float(props.get("elapsed")) if "elapsed" in props else 0.0
		var motion := float(props.get("_motion_scale")) if "_motion_scale" in props else 1.0
		var strength := float(props.get("_profile").get("wind",1.0))*float(props.get("_gust_strength")) if "_profile" in props and "_gust_strength" in props else 0.0
		if props.has_method("gust_for"):
			strength=float(props.get("_profile").get("wind",1.0))*float(props.gust_for(entry.position))
		clock *= float(entry.get("wind_rate",1.0))
		strength /= maxf(.01,float(entry.get("stiffness",1.0)))
		_geometry[index] = _shape(entry,clock,motion,strength)
	return _geometry.get(index,{})

func _entry(index: int) -> Dictionary:
	if not is_instance_valid(props) or index<0 or index>=props.entries.size(): return {}
	return props.entries[index]

func damage_entry(index: int,power: float,flavor: String = "rifle",hit: Vector2 = Vector2.ZERO,direction: Vector2 = Vector2.RIGHT) -> bool:
	if not is_authority() or not is_finite(power) or power<=0.0 or not hit.is_finite() or not direction.is_finite(): return false
	var state := state_for(index)
	if state.is_empty() or state.broken: return false
	var entry := _entry(index)
	if entry.is_empty(): return false
	state.hp = maxf(0.0,float(state.hp)-minf(power,1000.0))
	state.hit = hit
	state.direction = direction.normalized() if direction.length_squared()>.001 else Vector2.RIGHT
	if str(entry.kind) in FLAMMABLE and flavor in HOT and not state.burning:
		state.burning = true
		state.charred = true
		state.burn_left = BURN_SECONDS
	if state.hp<=0.0: state.broken = true
	_bump(index,state)
	return true

func _bump(index: int,state: Dictionary) -> void:
	state.serial = mini(MAX_SERIAL,int(state.serial)+1)
	state_changed.emit(index,state)

func _process(delta: float) -> void:
	if not is_authority() or not is_finite(delta) or delta<=0.0: return
	_rain_clock += delta
	var sample_rain := _rain_clock>=.5
	if sample_rain: _rain_clock = 0.0
	var game = props.get("game")
	var weather = game.get("weather") if is_instance_valid(game) else null
	var rain_value = weather.get("rain_strength") if is_instance_valid(weather) else null
	var rain := clampf(float(rain_value),0.0,1.0) if (rain_value is float or rain_value is int) and is_finite(float(rain_value)) else 0.0
	for index: int in states:
		var state: Dictionary = states[index]
		if not state.burning: continue
		var entry := _entry(index)
		if entry.is_empty(): continue
		if sample_rain or not _rain_exposure.has(index):
			_rain_exposure[index] = float(weather.exposure_at(props.to_global(entry.position-Vector2(0,float(entry.size.y)*.45)))) if rain>0.0 and weather.has_method("exposure_at") else 0.0
		var wet := rain*clampf(float(_rain_exposure.get(index,0.0)),0.0,1.0)
		state.burn_left = maxf(0.0,float(state.burn_left)-delta*(1.0+wet*2.5))
		state.hp = maxf(0.0,float(state.hp)-delta*float(HEALTH[entry.kind])/BURN_SECONDS)
		var newly_broken := false
		if state.hp<=0.0 and not state.broken:
			state.broken = true
			newly_broken = true
		if state.burn_left<=0.0:
			state.burning = false
			if wet<=.001:
				state.hp = 0.0
				newly_broken = newly_broken or not bool(state.broken)
				state.broken = true
			# Extinguishing changes presentation, but is not another impact.
			if not newly_broken: state_changed.emit(index,state)
		if newly_broken:
			_bump(index,state)

func trace_damage(from: Vector2,to: Vector2,power: float,flavor: String,visited: Dictionary = {}) -> int:
	if not is_authority() or not from.is_finite() or not to.is_finite(): return 0
	# External callers receive the same cover protection as actual projectiles.
	var query := PhysicsRayQueryParameters2D.create(from,to,1|2)
	query.hit_from_inside = true
	var hit := props.get_world_2d().direct_space_state.intersect_ray(query)
	return _trace_segment(from,hit.position if not hit.is_empty() else to,power,flavor,visited)

func _trace_segment(from: Vector2,to: Vector2,power: float,flavor: String,visited: Dictionary) -> int:
	if not is_authority() or not from.is_finite() or not to.is_finite() or from.distance_squared_to(to)<.001: return 0
	var count := 0
	var local_from := props.to_local(from)
	var local_to := props.to_local(to)
	for index: int in states:
		if visited.has(index) or bool(states[index].broken): continue
		var entry := _entry(index)
		var shape: Dictionary = _geometry.get(index,{})
		if entry.is_empty() or shape.is_empty(): continue
		if _rect_hit(Rect2(shape.bounds).grow(20.0),local_from-entry.position,local_to-entry.position).is_empty(): continue
		shape = _geometry_for(index)
		var contact := _intersect(shape,local_from-entry.position,local_to-entry.position)
		if contact.is_empty(): continue
		if damage_entry(index,power,flavor,props.to_global(entry.position+contact.point),(to-from).normalized()):
			visited[index] = true
			count += 1
	return count

static func for_game(game: Node) -> Node:
	if not is_instance_valid(game): return null
	var scenery = game.get("scenery")
	var layer = scenery.get("props_layer") if is_instance_valid(scenery) else null
	if is_instance_valid(layer):
		var reactions = layer.get("reactions")
		if is_instance_valid(reactions): return reactions
	if game.is_inside_tree():
		for reactions in game.get_tree().get_nodes_in_group("scenery_damage"):
			if is_instance_valid(reactions.props) and reactions.props.get("game")==game: return reactions
	return null

static func projectile_path(game: Node,from: Vector2,to: Vector2,power: float,flavor: String,visited: Dictionary,already_clipped: bool = false) -> int:
	var reactions := for_game(game)
	if not is_instance_valid(reactions): return 0
	# Projectile callers reuse their first-hit ray; no second physics query.
	return reactions._trace_segment(from,to,power,flavor,visited) if already_clipped else reactions.trace_damage(from,to,power,flavor,visited)

static func explosion(game: Node,at: Vector2,radius: float,power: float) -> int:
	var reactions := for_game(game)
	if not is_instance_valid(reactions) or not reactions.is_authority() or not at.is_finite() or not is_finite(radius) or not is_finite(power): return 0
	return reactions._blast(at,clampf(radius,1.0,160.0),power)

func _blast(at: Vector2,radius: float,power: float) -> int:
	var count := 0
	for index: int in states:
		if states[index].broken: continue
		var entry := _entry(index)
		var shape := _geometry_for(index)
		if entry.is_empty() or shape.is_empty(): continue
		var local := props.to_local(at)-Vector2(entry.position)
		var closest := Vector2.INF
		for segment: Dictionary in shape.segments:
			var point := Geometry2D.get_closest_point_to_segment(local,segment.from,segment.to)
			if local.distance_squared_to(point)<local.distance_squared_to(closest): closest = point
		for rect: Rect2 in shape.rects:
			var point := local.clamp(rect.position,rect.end)
			if local.distance_squared_to(point)<local.distance_squared_to(closest): closest = point
		var destination := props.to_global(entry.position+closest)
		var distance := at.distance_to(destination)
		if distance>radius: continue
		var ray := PhysicsRayQueryParameters2D.create(at,destination,1|2)
		ray.hit_from_inside = true
		if not props.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(): continue
		if damage_entry(index,power*lerpf(1.0,.3,distance/radius),"explosion",destination,(destination-at).normalized()): count += 1
	return count

static func valid_states(value: Variant,entries: Array) -> bool:
	if not value is Dictionary or value.size()>MAX_ENTRIES: return false
	var expected := 0
	for entry: Dictionary in entries.slice(0,MAX_ENTRIES):
		if HEALTH.has(str(entry.kind)): expected += 1
	if value.size()!=expected: return false
	for index in value:
		if not index is int or index<0 or index>=mini(entries.size(),MAX_ENTRIES): return false
		var kind := str(entries[index].kind)
		var state = value[index]
		if not HEALTH.has(kind) or not state is Dictionary or state.size()!=8: return false
		for key in ["hp","burn_left"]:
			if not state.get(key) is float or not is_finite(state[key]): return false
		if state.hp<0.0 or state.hp>float(HEALTH[kind]) or state.burn_left<0.0 or state.burn_left>BURN_SECONDS: return false
		if not state.get("burning") is bool or not state.get("charred") is bool or not state.get("broken") is bool or not state.get("serial") is int: return false
		if state.serial<0 or state.serial>MAX_SERIAL or (state.burning and not kind in FLAMMABLE): return false
		if (state.burning and not state.charred) or (state.charred and not kind in FLAMMABLE): return false
		if state.burning!=(state.burn_left>0.0) or state.broken!=(state.hp<=0.0): return false
		if not state.get("hit") is Vector2 or not state.hit.is_finite() or state.hit.abs().x>1000000 or state.hit.abs().y>1000000: return false
		if not state.get("direction") is Vector2 or not state.direction.is_finite() or state.direction.length_squared()>1.001: return false
	return true

static func _intersect(shape: Dictionary,from: Vector2,to: Vector2) -> Dictionary:
	if _rect_hit(shape.bounds,from,to).is_empty(): return {}
	for rect: Rect2 in shape.rects:
		var hit := _rect_hit(rect,from,to)
		if not hit.is_empty(): return hit
	for segment: Dictionary in shape.segments:
		var points := Geometry2D.get_closest_points_between_segments(from,to,segment.from,segment.to)
		if points[0].distance_squared_to(points[1])<=float(segment.radius)*float(segment.radius): return {"point":points[0]}
	return {}

static func _rect_hit(rect: Rect2,from: Vector2,to: Vector2) -> Dictionary:
	var first := 0.0
	var last := 1.0
	var step := to-from
	for axis in 2:
		if absf(step[axis])<.00001:
			if from[axis]<rect.position[axis] or from[axis]>rect.end[axis]: return {}
		else:
			var a := (rect.position[axis]-from[axis])/step[axis]
			var b := (rect.end[axis]-from[axis])/step[axis]
			first = maxf(first,minf(a,b))
			last = minf(last,maxf(a,b))
			if first>last: return {}
	return {"point":from+step*first}

static func _shape(entry: Dictionary,time: float = 0.0,motion: float = 1.0,strength: float = 0.0) -> Dictionary:
	var segments: Array[Dictionary] = []
	var rects: Array[Rect2] = []
	var phase := float(entry.get("phase",0.0))
	var gust := PropArt.wind(time,phase,motion*strength)
	var flexible_motion := motion*clampf(strength,.03,1.0)
	match str(entry.kind):
		"tree":
			if entry.get("damage_segments") is Array:
				segments.assign(entry.damage_segments)
			else:
				segments.append({"from":Vector2(0,-2),"to":Vector2(0,-float(entry.size.y)*.62),"radius":maxf(3.0,float(entry.size.y)/35.0)})
		"grass","frost_grass","brush","reeds":
			_growth_segments(segments,entry,time,flexible_motion,gust)
		"fan": rects.append(Rect2(-30,-74,60,74))
		"ore_cart": rects.append(Rect2(-33,-42,66,32))
		"pipe":
			rects.assign([Rect2(-29,-56,12,56),Rect2(-28,-61,59,12),Rect2(23,-53,14,12)])
		"signal": rects.assign([Rect2(-4,-112,8,112),Rect2(-13,-111,30,56),Rect2(-10,-28,20,20)])
		"generator": rects.assign([Rect2(-43,-56,88,50),Rect2(23,-76,12,21)])
		"pump": rects.assign([Rect2(-20,-46,48,40),Rect2(-42,-23,27,11),Rect2(33,-44,9,38)])
		"transformer": rects.assign([Rect2(-29,-63,66,57),Rect2(-24,-84,48,22)])
		"relay_antenna": rects.assign([Rect2(-4,-85,8,79),Rect2(-28,-92,58,38),Rect2(-14,-30,28,24)])
		"crane_hook": rects.assign([Rect2(-24,-101,8,95),Rect2(-26,-104,70,7),Rect2(-32,-41,24,29)])
		"cargo_beacon": rects.assign([Rect2(-25,-50,56,44),Rect2(-9,-74,18,24)])
		"windsock":
			rects.assign([Rect2(-2.5,-99,5,99),Rect2(-14,-6,28,6),Rect2(-5,-104,12,10),Rect2(5,-103,29,5)])
			var joints:=preload("res://scripts/industrial_prop_art.gd").windsock_points(time,phase,gust,motion,strength)
			for joint in 8:
				segments.append({"from":joints[joint],"to":joints[joint+1],"radius":lerpf(10,2,float(joint)/8.0)})
		"bollard":
			for x in [-34.0,34.0]: rects.append(Rect2(x-9,-29,18,29))
			_arc(segments,Vector2(-34,-24),68.0,15.0+gust*3,2.0)
		"cable":
			for x in [-35.0,35.0]: rects.append(Rect2(x-2.5,-96,5,96))
			for wire in 2:
				var previous := Vector2(-42.5+wire*15,-95)
				for part in range(1,13):
					var t := part/12.0
					var point := Vector2(-42.5+wire*15+t*70,-95+sin(t*PI)*(18+gust*3)+sin(time*1.8+phase+t*4)*sin(t*PI)*absf(gust)*1.7)
					segments.append({"from":previous,"to":point,"radius":1.5 if wire==0 else 1.0})
					previous = point
		"tape":
			for x in [-39.0,39.0]: rects.append(Rect2(x-2,-49,4,49))
			for band in 2:
				var previous := Vector2(-39,-41.5+band*16)
				for part in range(1,14):
					var t := part/13.0
					var point := Vector2(-39+t*78,-41.5+band*16+sin(t*PI)*(6+gust*3)+sin(time*3+phase-t*9)*sin(t*PI)*2*flexible_motion)
					segments.append({"from":previous,"to":point,"radius":2.5})
					previous = point
		"vines":
			for x in [-34.0,34.0]: rects.append(Rect2(x-2.5,-87,5,87))
			rects.append(Rect2(-39,-88,78,8))
			for strand in 6:
				var x := -31.0+strand*12
				var previous := Vector2(x,-82)
				for joint in range(1,7):
					var t := joint/6.0
					var point := Vector2(x+sin(t*3+time*1.25+phase+strand)*t*4*flexible_motion+gust*t*7,-82+t*(26+strand%3*16))
					segments.append({"from":previous,"to":point,"radius":1.5})
					previous = point
	var bounds := Rect2()
	var initialized := false
	for rect: Rect2 in rects:
		bounds = bounds.merge(rect) if initialized else rect
		initialized = true
	for segment: Dictionary in segments:
		var rect := Rect2(segment.from,Vector2.ZERO).expand(segment.to).grow(float(segment.radius))
		bounds = bounds.merge(rect) if initialized else rect
		initialized = true
	return {"segments":segments,"rects":rects,"bounds":bounds.grow(.1)}

static func _growth_segments(segments: Array[Dictionary],entry: Dictionary,time: float,motion: float,gust: float) -> void:
	var reeds := str(entry.kind)=="reeds"
	var brush := str(entry.kind)=="brush"
	# Match the deterministic stalks drawn by PropArt, including their open gaps.
	for blade in (9 if reeds else 13):
		var growth_seed := int(float(entry.get("phase",0.0))*901.0)+blade*7339
		var spread := PropArt._growth_hash(growth_seed+119)
		var length := PropArt._growth_hash(growth_seed+8317)
		var lean := PropArt._growth_hash(growth_seed+2731)
		var x := -16.0+float(blade%3)*17.0+(spread-.5)*7.0
		var root := Vector2(x,-float(blade%2))
		var height := (24+length*25) if reeds else (12+length*22) if brush else (9+length*27)
		var splay := (lean-.5)*(10.0 if reeds else 26.0)
		var tip_x := clampf(x+splay+gust*(7 if reeds else 5)+sin(time*2+float(growth_seed))*(.8+length)*motion,-28,28)
		var mid := Vector2(lerpf(x,tip_x,.35),-height*.51)
		var tip := Vector2(tip_x,-height)
		segments.append({"from":root.round(),"to":mid.round(),"radius":1.3})
		segments.append({"from":mid.round(),"to":tip.round(),"radius":.8})
		if reeds:
			segments.append({"from":tip.round(),"to":(tip+Vector2((lean-.5)*2,-4-length*4)).round(),"radius":1.5})
		elif brush:
			for fork in 2:
				var at := mid.lerp(tip,.15+fork*.42)
				var side := -1.0 if (blade+fork)%2 else 1.0
				var twig := Vector2(clampf(at.x+side*(4+spread*5)+gust*.8,-29,29),at.y-4-length*5)
				segments.append({"from":at.round(),"to":twig.round(),"radius":.8})

static func _arc(segments: Array[Dictionary],start: Vector2,width: float,drop: float,radius: float) -> void:
	var previous := start
	for index in range(1,9):
		var t := index/8.0
		var point := start+Vector2(width*t,sin(t*PI)*drop)
		segments.append({"from":previous,"to":point,"radius":radius})
		previous = point
