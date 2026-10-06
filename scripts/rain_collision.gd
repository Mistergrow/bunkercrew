class_name RainCollision
extends RefCounted
## Swept rain contacts share actual terrain with projectiles. Painted objects and
## articulated actor tops add narrow visual surfaces without gameplay blockers.
var weather: Node2D
var physics_queries := 0
var profiling := false
var profile_us := [0,0,0,0,0]
var _cache_frame := -1
var _actor_frame := -1
var _actor_records: Array[Dictionary] = []
var _actor_segments: Array[Dictionary] = []
var _static_segments: Array[Dictionary] = []
var _actor_rids: Array[RID] = []
var _prop_rids: Array[RID] = []
const CELL_SIZE := 64.0
const ACTOR_CELL_SIZE := 16.0
const CELL_CONTACT_MARGIN := .1
var _actor_cells: Dictionary = {}
var _static_cells: Dictionary = {}
var _static_cell_bounds: Array[Rect2i] = []
var _fallback_segments: Array[Dictionary] = []
var _scenario_bunker: Node2D
var _legacy_foundation_end := 0.0
var _dome_frame := -1
var _dome_edges: Array[Vector4] = []
var _dome_columns: Dictionary = {}
var _terrain_query := PhysicsRayQueryParameters2D.create(Vector2.ZERO,Vector2.ZERO,3)
var _actor_query := PhysicsRayQueryParameters2D.create(Vector2.ZERO,Vector2.ZERO,3)
var _excluded_query := PhysicsRayQueryParameters2D.create(Vector2.ZERO,Vector2.ZERO,3)

func invalidate() -> void:
	_cache_frame = -1
	_actor_frame = -1
	_dome_frame = -1

func refresh(include_actors: bool = true) -> void:
	if not is_instance_valid(weather) or not weather.is_inside_tree(): return
	var frame := Engine.get_process_frames()
	if _cache_frame != frame:
		_cache_frame = frame
		_rebuild_fallback_segments()
		_static_segments.clear()
		_prop_rids.clear()
		var props = weather.get("prop_surfaces")
		if is_instance_valid(props):
			_static_segments.assign(props.rain_segments())
		var rebuild := _static_segments.size()!=_static_cell_bounds.size()
		_static_cell_bounds.resize(_static_segments.size())
		var seen_props: Dictionary={}
		for index in _static_segments.size():
			var segment: Dictionary=_static_segments[index]
			var bounds := _segment_cell_bounds(segment,CELL_SIZE)
			if _static_cell_bounds[index]!=bounds:
				_static_cell_bounds[index]=bounds
				rebuild=true
			var prop = segment.get("collider")
			if is_instance_valid(prop) and prop is Node and not seen_props.has(prop):
				seen_props[prop]=true
				var hull = prop.get("hull")
				if hull is CollisionObject2D and not _prop_rids.has(hull.get_rid()): _prop_rids.append(hull.get_rid())
		# Endpoints/materials are always fresh. Reuse only their integer cell
		# membership until a moving edge crosses a boundary, or the list changes.
		if rebuild:
			_static_cells.clear()
			for index in _static_cell_bounds.size():
				_index_cell_bounds(_static_cells,_static_cell_bounds[index],index)
		_terrain_query.hit_from_inside = true
		_terrain_query.exclude = _prop_rids
	if not include_actors or _actor_frame == frame: return
	_actor_frame=frame
	_actor_segments.clear()
	_actor_records.clear()
	_actor_rids.clear()
	_actor_cells.clear()
	for wetness in weather.get_tree().get_nodes_in_group("weather_actors"):
		if not is_instance_valid(wetness) or wetness.is_queued_for_deletion() or not wetness.has_method("rain_segments"): continue
		var actor = wetness.get("actor")
		if not _valid_actor(wetness,actor): continue
		# Player/enemy capsules live on layers 4/8 and cannot describe painted
		# rain tops. Query only terrain/defence; exclude the few weather actors
		# (such as the convoy) that also occupy those solid layers.
		if actor is CollisionObject2D and actor.collision_layer&3!=0: _actor_rids.append(actor.get_rid())
		# Conservatively covers authored bodies, articulated tools and convoy cabs.
		# Exact alpha contours are sampled only for bodies reached by a rain ray.
		var bounds := actor_bounds(actor)
		var index:=_actor_records.size()
		_actor_records.append({"actor":actor,"wetness":wetness,"segments":[],"cells":{},"bounds":bounds,"sampled":false})
		_index_segment(_actor_cells,{"from":bounds.position,"to":bounds.end},index)
	var exclusions: Array[RID] = []
	exclusions.assign(_prop_rids)
	exclusions.append_array(_actor_rids)
	_actor_query.hit_from_inside = true
	_actor_query.exclude = exclusions

func _valid_actor(wetness,actor) -> bool:
	if not is_instance_valid(weather) or not weather.is_inside_tree(): return false
	if not is_instance_valid(wetness) or wetness.is_queued_for_deletion() or not is_instance_valid(actor) or not actor is Node2D: return false
	if actor.is_queued_for_deletion() or not actor.is_inside_tree() or not actor.is_visible_in_tree() or actor.get_world_2d()!=weather.get_world_2d(): return false
	var game=weather.get("game")
	return not is_instance_valid(game) or actor.get("game")==game

func actor_bounds(actor: Node2D) -> Rect2:
	# Use the articulated nodes' current transforms; sampling alpha contours is
	# still deferred until a ray actually reaches this much tighter envelope.
	if actor.is_in_group("air_enemies"):
		return ActorWeatherGeometry.machine_bounds(actor)
	if actor.is_in_group("enemies"):
		if actor.has_method("weather_segments"):
			return actor.global_transform*Rect2(-64,-100,128,116)
		return ActorWeatherGeometry.machine_bounds(actor)
	if actor.is_in_group("players"):
		return actor.global_transform*Rect2(-86,-110,172,144)
	if actor.is_in_group("medics"):
		return actor.global_transform*Rect2(-26,-50,52,55)
	return actor.global_transform*Rect2(-144,-224,288,320)

func _candidate_actor_indices(from: Vector2,to: Vector2) -> Array[int]:
	return _candidate_indices(_actor_cells,from,to)

func _actor_contours(record: Dictionary) -> Array:
	if not record.sampled:
		record.sampled=true
		if _valid_actor(record.wetness,record.actor):
			var lower := Vector2(INF,INF)
			var upper := Vector2(-INF,-INF)
			for segment: Dictionary in record.wetness.rain_segments():
				var a: Vector2=segment.from
				var b: Vector2=segment.to
				lower=lower.min(a).min(b)
				upper=upper.max(a).max(b)
				segment["collider"]=record.actor
				segment["wetness"]=record.wetness
				record.segments.append(segment)
				_index_segment(record.cells,segment,record.segments.size()-1,ACTOR_CELL_SIZE)
				_actor_segments.append(segment)
			if not record.segments.is_empty(): record.bounds=Rect2(lower,upper-lower)
	return record.segments

func _index_segment(cells: Dictionary, segment: Dictionary, index: int, cell_size: float = CELL_SIZE) -> void:
	var a:Vector2=segment.get("from",segment.get("a",Vector2.ZERO))
	var b:Vector2=segment.get("to",segment.get("b",Vector2.ZERO))
	for x in range(floori(minf(a.x,b.x)/cell_size),floori(maxf(a.x,b.x)/cell_size)+1):
		for y in range(floori(minf(a.y,b.y)/cell_size),floori(maxf(a.y,b.y)/cell_size)+1):
			var key:=Vector2i(x,y)
			if not cells.has(key):
				var indices: Array[int]=[]
				cells[key]=indices
			cells[key].append(index)

func _segment_cell_bounds(segment: Dictionary, cell_size: float) -> Rect2i:
	var a:Vector2=segment.get("from",segment.get("a",Vector2.ZERO))
	var b:Vector2=segment.get("to",segment.get("b",Vector2.ZERO))
	var first := Vector2i(floori(minf(a.x,b.x)/cell_size),floori(minf(a.y,b.y)/cell_size))
	var last := Vector2i(floori(maxf(a.x,b.x)/cell_size),floori(maxf(a.y,b.y)/cell_size))
	return Rect2i(first,last-first+Vector2i.ONE)

func _index_cell_bounds(cells: Dictionary, bounds: Rect2i, index: int) -> void:
	for x in range(bounds.position.x,bounds.end.x):
		for y in range(bounds.position.y,bounds.end.y):
			var key:=Vector2i(x,y)
			if not cells.has(key):
				var indices: Array[int]=[]
				cells[key]=indices
			cells[key].append(index)

func _candidate_indices(cells: Dictionary, from: Vector2, to: Vector2, cell_size: float = CELL_SIZE) -> Array[int]:
	# Supercover traversal visits the cells actually crossed by the segment,
	# including both neighbours at corners. Wind-slanted 1800px exposure rays
	# previously searched their whole bounding rectangle, mostly empty cells.
	var cell := Vector2i(floori(from.x/cell_size),floori(from.y/cell_size))
	var target := Vector2i(floori(to.x/cell_size),floori(to.y/cell_size))
	# Short rain sweeps commonly stay within one cell. All callers only read
	# candidate lists, so reuse its typed index instead of copying every ID.
	var from_edge := from-Vector2(cell)*cell_size
	var to_edge := to-Vector2(target)*cell_size
	var near_from := from_edge.x<CELL_CONTACT_MARGIN or from_edge.y<CELL_CONTACT_MARGIN or from_edge.x>cell_size-CELL_CONTACT_MARGIN or from_edge.y>cell_size-CELL_CONTACT_MARGIN
	var near_to := to_edge.x<CELL_CONTACT_MARGIN or to_edge.y<CELL_CONTACT_MARGIN or to_edge.x>cell_size-CELL_CONTACT_MARGIN or to_edge.y>cell_size-CELL_CONTACT_MARGIN
	if cell==target and not near_from and not near_to and cells.has(cell): return cells[cell]
	var result:Array[int]=[]
	if cell==target and not near_from and not near_to:
		return result
	var seen:Dictionary={}
	var direction := to-from
	var step := Vector2i(int(signf(direction.x)),int(signf(direction.y)))
	var stride := Vector2(cell_size/absf(direction.x) if step.x!=0 else INF,cell_size/absf(direction.y) if step.y!=0 else INF)
	var next := Vector2(((cell.x+(1 if step.x>0 else 0))*cell_size-from.x)/direction.x if step.x!=0 else INF,((cell.y+(1 if step.y>0 else 0))*cell_size-from.y)/direction.y if step.y!=0 else INF)
	_append_cell_indices(cells,cell,seen,result)
	# Geometry2D accepts near-touching native endpoints. Include only their
	# adjacent edge/corner cells, using the same margin as _intersect_segment.
	if near_from: _append_endpoint_indices(cells,cell,from_edge,cell_size,seen,result)
	while cell!=target:
		# The packed float boundary times may round a near-corner endpoint to
		# the same value on both axes. Never step past an axis's final cell: that
		# would make the old unbounded traversal unable to reach its target.
		if cell.x==target.x:
			cell.y+=step.y
			next.y+=stride.y
		elif cell.y==target.y:
			cell.x+=step.x
			next.x+=stride.x
		elif next.x<next.y:
			cell.x+=step.x
			next.x+=stride.x
		elif next.y<next.x:
			cell.y+=step.y
			next.y+=stride.y
		else:
			_append_cell_indices(cells,cell+Vector2i(step.x,0),seen,result)
			_append_cell_indices(cells,cell+Vector2i(0,step.y),seen,result)
			cell+=step
			next+=stride
		_append_cell_indices(cells,cell,seen,result)
	if near_to: _append_endpoint_indices(cells,target,to_edge,cell_size,seen,result)
	return result

func _append_endpoint_indices(cells: Dictionary, cell: Vector2i, edge: Vector2, cell_size: float, seen: Dictionary, result: Array[int]) -> void:
	var x_side := -1 if edge.x<CELL_CONTACT_MARGIN else (1 if edge.x>cell_size-CELL_CONTACT_MARGIN else 0)
	var y_side := -1 if edge.y<CELL_CONTACT_MARGIN else (1 if edge.y>cell_size-CELL_CONTACT_MARGIN else 0)
	if x_side!=0: _append_cell_indices(cells,cell+Vector2i(x_side,0),seen,result)
	if y_side!=0: _append_cell_indices(cells,cell+Vector2i(0,y_side),seen,result)
	if x_side!=0 and y_side!=0: _append_cell_indices(cells,cell+Vector2i(x_side,y_side),seen,result)

func _append_cell_indices(cells: Dictionary, cell: Vector2i, seen: Dictionary, result: Array[int]) -> void:
	for index: int in cells.get(cell,[]):
		if seen.has(index): continue
		seen[index]=true
		result.append(index)

func dome_cover_height(x: float) -> float:
	_refresh_dome_edges()
	var cover:=INF
	for index:int in _dome_columns.get(floori(x/CELL_SIZE),[]):
		var edge:Vector4=_dome_edges[index]
		if x<minf(edge.x,edge.z) or x>maxf(edge.x,edge.z):
			continue
		if is_equal_approx(edge.x,edge.z):
			cover=minf(cover,minf(edge.y,edge.w))
		else:
			cover=minf(cover,lerpf(edge.y,edge.w,(x-edge.x)/(edge.z-edge.x)))
	return cover

func _refresh_dome_edges() -> void:
	var frame:=Engine.get_process_frames()
	if _dome_frame==frame:
		return
	_dome_frame=frame
	_dome_edges.clear()
	_dome_columns.clear()
	var game=weather.get("game") if is_instance_valid(weather) else null
	var dome=game.get("dome") if is_instance_valid(game) else null
	if not is_instance_valid(dome):
		return
	# Exact transformed polygon edges, never a rounded height map. Pane damage,
	# repair and service-port polygon replacement are picked up every new frame.
	for segment in dome.segments:
		if not segment.is_visible_in_tree() or not segment.is_blocking():
			continue
		for polygon:PackedVector2Array in segment.polygons:
			for index in polygon.size():
				var a:Vector2=segment.to_global(polygon[index])
				var b:Vector2=segment.to_global(polygon[(index+1)%polygon.size()])
				var id:=_dome_edges.size()
				_dome_edges.append(Vector4(a.x,a.y,b.x,b.y))
				for column in range(floori(minf(a.x,b.x)/CELL_SIZE),floori(maxf(a.x,b.x)/CELL_SIZE)+1):
					if not _dome_columns.has(column):
						_dome_columns[column]=[]
					_dome_columns[column].append(id)

func trace(from: Vector2, to: Vector2, include_actors: bool = true, exclude_actor: Node = null) -> Dictionary:
	var stamp := Time.get_ticks_usec() if profiling else 0
	refresh(include_actors)
	if profiling:
		profile_us[0]+=Time.get_ticks_usec()-stamp
		stamp=Time.get_ticks_usec()
	var best := _fallback_trace(from, to)
	var distance := from.distance_squared_to(best.position) if not best.is_empty() else INF
	if profiling:
		profile_us[1]+=Time.get_ticks_usec()-stamp
		stamp=Time.get_ticks_usec()
	if is_instance_valid(weather) and weather.is_inside_tree():
		# Query resources and their exclusion arrays belong to this World2D.
		# Ordinary streaks only replace endpoints, rather than allocating three
		# new arrays/resources for every swept contact and exposure probe.
		var query := _actor_query if include_actors else _terrain_query
		if exclude_actor is CollisionObject2D and exclude_actor.collision_layer&3!=0 and not query.exclude.has(exclude_actor.get_rid()):
			var exclude: Array[RID] = []
			exclude.assign(query.exclude)
			exclude.append(exclude_actor.get_rid())
			_excluded_query.hit_from_inside = true
			_excluded_query.exclude = exclude
			query = _excluded_query
		query.from = from
		query.to = to
		physics_queries += 1
		var physical := weather.get_world_2d().direct_space_state.intersect_ray(query)
		if not physical.is_empty() and from.distance_squared_to(physical.position) <= distance + 0.02:
			best = physical
			best["material"] = material_for(physical.collider, physical.position)
			distance = from.distance_squared_to(physical.position)
	if profiling:
		profile_us[2]+=Time.get_ticks_usec()-stamp
		stamp=Time.get_ticks_usec()
	for index:int in _candidate_indices(_static_cells,from,to):
		var segment:Dictionary=_static_segments[index]
		var hit := _intersect_segment(from, to, segment)
		if not hit.is_empty() and from.distance_squared_to(hit.position) < distance:
			best = hit
			distance = from.distance_squared_to(hit.position)
	if profiling:
		profile_us[3]+=Time.get_ticks_usec()-stamp
		stamp=Time.get_ticks_usec()
	if include_actors:
		var sweep_bounds := Rect2(from,to-from).abs().grow(.1)
		for index:int in _candidate_actor_indices(from,to):
			var record: Dictionary=_actor_records[index]
			if not _valid_actor(record.wetness,record.actor): continue
			if record.actor==exclude_actor: continue
			# A coarse occupied cell is wider than the actual art envelope. Reject
			# misses before sampling a silhouette for the first ray of this frame.
			if not Rect2(record.bounds).grow(.1).intersects(sweep_bounds): continue
			var contours := _actor_contours(record)
			for contour_index in _candidate_indices(record.cells,from,to,ACTOR_CELL_SIZE):
				var segment: Dictionary = contours[contour_index]
				var hit := _intersect_segment(from, to, segment)
				if not hit.is_empty() and from.distance_squared_to(hit.position) < distance:
					best = hit
					distance = from.distance_squared_to(hit.position)
	if profiling:profile_us[4]+=Time.get_ticks_usec()-stamp
	if not best.is_empty():
		if Vector2(best.normal).length_squared() < 0.1:
			best.normal = -(to-from).normalized()
		best["distance"] = sqrt(distance)
	return best

func surface_at(x: float) -> Dictionary:
	return trace(Vector2(x, -1400.0), Vector2(x, 1800.0), false)

func exposure_at(point: Vector2, exclude_actor: Node = null) -> float:
	# Start from sky on the actual incoming wind direction. A vertical-only roof
	# test would keep a character beside an overhang incorrectly dry.
	var local_wind: float = weather.wind_at(point).x if weather.has_method("wind_at") else weather.wind_speed()
	var direction: Vector2 = Vector2(local_wind, 315.0).normalized()
	var hit := trace(point-direction*RainCatalog.SKY_RAY_LENGTH, point-Vector2(0,0.8), false, exclude_actor)
	return 1.0 if hit.is_empty() else 0.0

func _intersect_segment(from: Vector2, to: Vector2, segment: Dictionary) -> Dictionary:
	var collider=segment.get("collider")
	if typeof(collider)==TYPE_OBJECT and not is_instance_valid(collider): return {}
	if collider is Node2D:
		if collider.is_queued_for_deletion() or not collider.is_inside_tree() or not collider.is_visible_in_tree(): return {}
	var a: Vector2 = segment.get("from",segment.get("a",Vector2.ZERO))
	var b: Vector2 = segment.get("to",segment.get("b",Vector2.ZERO))
	if maxf(from.x,to.x) < minf(a.x,b.x)-0.1 or minf(from.x,to.x)>maxf(a.x,b.x)+0.1 or maxf(from.y,to.y)<minf(a.y,b.y)-0.1 or minf(from.y,to.y)>maxf(a.y,b.y)+0.1:
		return {}
	var point = Geometry2D.segment_intersects_segment(from,to,a,b)
	if point == null:
		return {}
	var normal: Vector2 = segment.get("normal", (b-a).normalized().orthogonal())
	if normal.dot(to-from)>0:
		normal = -normal
	return {"position":Vector2(point),"normal":normal,"material":str(segment.get("material","concrete")),"collider":segment.get("collider"),"wetness":segment.get("wetness"),"weather_prop":bool(segment.get("weather_prop",false)),"moving":bool(segment.get("moving",false))}

func _rebuild_fallback_segments() -> void:
	# These are the visible, permanent world surfaces. Terrain physics agrees
	# inside the playable bounds; the hillside and distant road continue beyond
	# the collision arena and still need a rain silhouette at wide camera stages.
	var spans := [
		[Vector2(-1100,245),Vector2(75,245),"soil"],
		[Vector2(75,245),Vector2(750,245),"concrete"],
		[Vector2(750,262.035714),Vector2(775,279),"concrete"],
		[Vector2(775,279),Vector2(873,324),"concrete"],
		[Vector2(873,430),Vector2(2880,430),"soil"],
	]
	var game = weather.get("game")
	_scenario_bunker = game.get("scenario_bunker") if is_instance_valid(game) else null
	_legacy_foundation_end = 0.0
	if is_instance_valid(game):
		if is_instance_valid(_scenario_bunker):
			var bunker: ScenarioBunker=_scenario_bunker
			# In the playable arena the split slabs and sliding hatch bodies are
			# authoritative. Only the distant earth beyond their physical bounds
			# needs a painted continuation; an interior fallback would seal holes.
			spans=[
				[Vector2(-1850,bunker.ground_y),Vector2(ScenarioBunker.WORLD_LEFT-160,bunker.ground_y),"soil"],
				[Vector2(ScenarioBunker.WORLD_RIGHT+160,bunker.ground_y),Vector2(3450,bunker.ground_y),"soil"],
			]
		var flak = game.get("flak_station")
		if not is_instance_valid(_scenario_bunker) and is_instance_valid(flak) and bool(flak.get("built")):
			var platform: Rect2=flak.platform
			spans.append([platform.position,Vector2(platform.end.x,platform.position.y),"metal"])
		var growth=game.get("environment_growth")
		if not is_instance_valid(_scenario_bunker) and is_instance_valid(growth) and growth.glassworks_open:
			_legacy_foundation_end=1210.0 if growth.exterior_open else 1065.0
		var trip=game.get("expedition")
		if is_instance_valid(trip) and trip.road_open and trip.stage in ["travel","stop","failed"]:
			_scenario_bunker=null
			_legacy_foundation_end=0.0
			spans=[[Vector2(-1850,430),Vector2(float(game.world_right)+1850,430),"concrete"]]
	_fallback_segments.clear()
	for span in spans:
		_fallback_segments.append({"from":span[0],"to":span[1],"material":span[2]})

func _fallback_trace(from: Vector2, to: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var distance := INF
	for span in _fallback_segments:
		var hit := _intersect_segment(from,to,span)
		if not hit.is_empty() and from.distance_squared_to(hit.position)<distance:
			if hit.material=="soil":
				hit.material=material_for(null,hit.position)
			best=hit
			distance=from.distance_squared_to(hit.position)
	return best

func _foundation_end() -> float:
	refresh(false)
	return _legacy_foundation_end

func material_for(collider: Object, point: Vector2) -> String:
	if is_instance_valid(collider):
		if collider.has_meta("weather_material"):
			var surface_material := str(collider.get_meta("weather_material"))
			return "concrete" if surface_material=="soil" and _courtyard_pavement_at(point) else surface_material
		if collider is Node:
			if collider.is_in_group("convoy_vehicles"):
				return "metal"
			if collider.is_in_group("dome_segments"):
				return "glass"
			if collider.is_in_group("anti_air"):
				return "metal"
			if collider.is_in_group("players") or collider.is_in_group("enemies"):
				return "actor"
			if collider.is_in_group("walls"):
				return "concrete"
	refresh(false)
	var game=weather.get("game") if is_instance_valid(weather) else null
	var trip=game.get("expedition") if is_instance_valid(game) else null
	if is_instance_valid(trip) and trip.road_open and trip.stage in ["travel","stop","failed"] and absf(point.y-430)<3:
		return "concrete"
	if is_instance_valid(_scenario_bunker):
		var bunker: ScenarioBunker=_scenario_bunker
		if absf(point.y-bunker.ground_y)<3.0:
			return "concrete" if (point.x>=bunker.room_left and point.x<=bunker.room_right) or _courtyard_pavement_at(point) else "soil"
	if absf(point.y-35.0)<2.0:
		return "metal"
	if point.x>=870.0 and point.x<=_foundation_end() and point.y>=422.0 and point.y<=433.0:
		return "concrete"
	if (point.x>=873.0 and absf(point.y-430.0)<3.0) or (point.x<75 and absf(point.y-245.0)<3.0):
		return "concrete" if _courtyard_pavement_at(point) else "soil"
	return "concrete"

func _courtyard_pavement_at(point: Vector2) -> bool:
	# Paving changes the surface finish of the existing earth slab, rather than
	# its body/layer or the floor of another room below that same x position.
	var game = weather.get("game") if is_instance_valid(weather) else null
	var perimeter = game.get("perimeter") if is_instance_valid(game) else null
	var courtyard = perimeter.get_node_or_null("ServiceCourtyard") if is_instance_valid(perimeter) else null
	if not is_instance_valid(courtyard) or courtyard.is_queued_for_deletion() or not courtyard.is_visible_in_tree(): return false
	var local: Vector2 = courtyard.to_local(point)
	for section: Dictionary in courtyard.sections:
		if local.x>=float(section.start) and local.x<float(section.end) and absf(local.y-float(section.ground))<.05:
			return true
	return false
