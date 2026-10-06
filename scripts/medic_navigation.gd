class_name MedicNavigation
extends RefCounted
## A small support-and-ladder graph for the rescue unit. Terrain is queried from
## the actual arena; the graph never cuts through undug earth or invents shafts.
const SPEED := 188.0
const CLIMB_SPEED := 145.0
const GRAVITY := 1100.0
const JUMP_SPEED := 395.0
const BODY_SIZE := Vector2(18,26)
var actor: CharacterBody2D
var game: Node
var _box := RectangleShape2D.new()
var _points: Array[Vector2] = []
var _edges: Array = []

func _init(body: CharacterBody2D, arena: Node) -> void:
	actor=body
	game=arena
	_box.size=BODY_SIZE

func _space() -> PhysicsDirectSpaceState2D:
	return actor.get_world_2d().direct_space_state

func ladder_for(point: Vector2) -> Rect2:
	for ladder: Rect2 in game.ladders:
		if absf(point.x-ladder.get_center().x)<=19 and point.y>=ladder.position.y+28 and point.y<=ladder.end.y+8:
			return ladder
	return Rect2()

func _planning_exclusions() -> Array[RID]:
	var result: Array[RID]=[actor.get_rid()]
	# Crew-operated gates open as SAN-1 approaches. Only route planning ignores
	# them; movement and treatment rays still use the actual collision geometry.
	for site in actor.get_tree().get_nodes_in_group("perimeter_sites"):
		if site.get("game")==game and site.has_method("navigation_passable") and site.navigation_passable(): result.append(site.get_rid())
	return result

func support_at(point: Vector2) -> bool:
	var exclusions := _planning_exclusions()
	for x in [-7.0,0.0,7.0]:
		var query:=PhysicsRayQueryParameters2D.create(point+Vector2(x,-3),point+Vector2(x,5),1)
		query.exclude=exclusions
		var hit:=_space().intersect_ray(query)
		if hit.is_empty() or hit.normal.y>-.5 or absf(hit.position.y-point.y)>2:
			return false
	return true

func body_clear(point: Vector2) -> bool:
	var query:=PhysicsShapeQueryParameters2D.new()
	query.shape=_box
	query.transform=Transform2D(0,point-Vector2(0,BODY_SIZE.y*.5+.5))
	query.collision_mask=1
	query.exclude=_planning_exclusions()
	return _space().intersect_shape(query,1).is_empty()

func foot_point(position: Vector2) -> Vector2:
	if ladder_for(position).has_area():
		var nearest:=position
		for floor_y: float in game.floor_levels:
			if absf(position.y-floor_y)<10: nearest.y=floor_y
		return nearest.round()
	var query:=PhysicsRayQueryParameters2D.create(position-Vector2(0,3),position+Vector2(0,19),1)
	query.exclude=_planning_exclusions()
	var hit:=_space().intersect_ray(query)
	if hit.is_empty() or hit.normal.y>-.5: return Vector2.INF
	return Vector2(roundf(position.x),roundf(hit.position.y))

func treatment_line(point: Vector2, patient: Node2D) -> bool:
	var query:=PhysicsRayQueryParameters2D.create(point-Vector2(0,18),patient.global_position-Vector2(0,18),1|2)
	query.hit_from_inside=true
	return _space().intersect_ray(query).is_empty()

func _allowed(point: Vector2) -> bool:
	return (support_at(point) and body_clear(point)) or ladder_for(point).has_area()

func route_to(patient: Node2D) -> Array[Dictionary]:
	var target:=foot_point(patient.global_position)
	if target==Vector2.INF: return []
	var candidates: Array[Vector2]=[]
	for offset in [-31.0,31.0,-23.0,23.0,0.0]:
		var point:=target+Vector2(offset,0)
		if support_at(point) and body_clear(point) and treatment_line(point,patient): candidates.append(point)
	candidates.sort_custom(func(a,b):return actor.global_position.distance_squared_to(a)<actor.global_position.distance_squared_to(b))
	var path:=_route_candidates(candidates,false)
	if not path.is_empty(): return path
	# One expanded graph contains every treatment position, including ore ledges.
	return _route_candidates(candidates,true)

func route(goal: Vector2, allow_jumps: bool = false) -> Array[Dictionary]:
	return _route_candidates([goal],allow_jumps)

func _route_candidates(goals: Array[Vector2],allow_jumps: bool) -> Array[Dictionary]:
	var start:=foot_point(actor.global_position)
	if start==Vector2.INF or goals.is_empty(): return []
	var valid_goals: Array[Vector2]=[]
	for goal: Vector2 in goals:
		if not _allowed(goal): continue
		if start.distance_to(goal)<3: return [{"point":goal,"kind":"walk"}]
		if not valid_goals.has(goal): valid_goals.append(goal)
	if valid_goals.is_empty(): return []
	var goal:=valid_goals[0]
	_points=[start]
	_points.append_array(valid_goals)
	var goal_indices: Array[int]=[]
	var xs: Array[float]=[start.x]
	var ys: Array[float]=[start.y]
	for index in valid_goals.size():
		goal_indices.append(index+1)
		if not xs.has(valid_goals[index].x): xs.append(valid_goals[index].x)
		if not ys.has(valid_goals[index].y): ys.append(valid_goals[index].y)
	for level: float in game.floor_levels:
		if not ys.has(level): ys.append(level)
	for ladder: Rect2 in game.ladders:
		var x:=roundf(ladder.get_center().x)
		if not xs.has(x): xs.append(x)
	if allow_jumps:
		for block in actor.get_tree().get_nodes_in_group("mine_blocks"):
			if block.is_queued_for_deletion(): continue
			var y: float=roundf(block.global_position.y-24)
			if y<minf(start.y,goal.y)-120 or y>maxf(start.y,goal.y)+150: continue
			if not ys.has(y): ys.append(y)
			for offset in [-14.0,14.0]:
				var x: float=roundf(block.global_position.x+offset)
				if not xs.has(x): xs.append(x)
		# Floor ends are valid takeoff and landing points next to a mine ledge.
		for body in game.find_children("*","StaticBody2D",true,false):
			if body.collision_layer!=1 or body.is_in_group("mine_blocks"): continue
			for child in body.get_children():
				if child is CollisionShape2D and child.shape is RectangleShape2D:
					for sign_x in [-1.0,1.0]:
						var x: float=roundf(child.global_position.x+sign_x*(child.shape.size.x*.5-10))
						var left: float=float(game.world_left) if "world_left" in game else 70.0
						if x>=left and x<=game.world_right and not xs.has(x): xs.append(x)
	for y: float in ys:
		for x: float in xs:
			var point:=Vector2(x,y)
			if not _points.has(point) and _allowed(point): _points.append(point)
	_edges=[]
	for point in _points: _edges.append([])
	for y: float in ys:
		var row: Array[int]=[]
		for i in _points.size():
			if is_equal_approx(_points[i].y,y): row.append(i)
		row.sort_custom(func(a,b):return _points[a].x<_points[b].x)
		for i in range(row.size()-1):
			var a:=row[i]
			var b:=row[i+1]
			if walk_clear(_points[a],_points[b]):
				_link(a,b,"walk",_points[a].distance_to(_points[b])/SPEED)
				_link(b,a,"walk",_points[a].distance_to(_points[b])/SPEED)
	for ladder: Rect2 in game.ladders:
		var column: Array[int]=[]
		for i in _points.size():
			if absf(_points[i].x-ladder.get_center().x)<.1 and _points[i].y>=ladder.position.y+28 and _points[i].y<=ladder.end.y+8:
				column.append(i)
		column.sort_custom(func(a,b):return _points[a].y<_points[b].y)
		for i in range(column.size()-1):
			var a:=column[i]
			var b:=column[i+1]
			var cost:=absf(_points[a].y-_points[b].y)/CLIMB_SPEED
			_link(a,b,"climb",cost,{"ladder":ladder})
			_link(b,a,"climb",cost,{"ladder":ladder})
	if allow_jumps:
		var supported: Array[bool]=[]
		for point: Vector2 in _points: supported.append(support_at(point))
		for a in _points.size():
			if not supported[a]: continue
			for b in _points.size():
				if a==b: continue
				var difference:=_points[b]-_points[a]
				if absf(difference.x)>128 or absf(difference.x)<12 or difference.y< -60 or difference.y>145 or not supported[b]: continue
				var jump:=jump_between(_points[a],_points[b])
				if not jump.is_empty(): _link(a,b,"jump",float(jump.duration)+.45,jump)
	return _shortest_path(goal_indices)

func walk_clear(from: Vector2,to: Vector2) -> bool:
	var samples:=maxi(1,ceili(absf(to.x-from.x)/14.0))
	for i in samples+1:
		var point:=from.lerp(to,float(i)/samples)
		if not support_at(point) or not body_clear(point): return false
	return true

func jump_between(from: Vector2,to: Vector2) -> Dictionary:
	var difference:=to-from
	var discriminant:=JUMP_SPEED*JUMP_SPEED+2*GRAVITY*difference.y
	if discriminant<=0: return {}
	var duration:=(JUMP_SPEED+sqrt(discriminant))/GRAVITY
	var speed_x:=difference.x/duration
	if absf(speed_x)>SPEED or duration>1.15: return {}
	for i in range(1,13):
		var t:=duration*float(i)/12.0
		var point:=from+Vector2(speed_x*t,-JUMP_SPEED*t+.5*GRAVITY*t*t)
		if not body_clear(point): return {}
	return {"launch":Vector2(speed_x,-JUMP_SPEED),"duration":duration}

func _link(a: int,b: int,kind: String,cost: float,extra: Dictionary = {}) -> void:
	var edge:={"to":b,"point":_points[b],"kind":kind,"cost":cost}
	edge.merge(extra,true)
	_edges[a].append(edge)

func _shortest_path(goals: Array[int]) -> Array[Dictionary]:
	var distances: Array[float]=[]
	var previous: Array=[]
	var visited: Array[bool]=[]
	for i in _points.size():
		distances.append(INF)
		previous.append({})
		visited.append(false)
	distances[0]=0
	var destination := -1
	for _step in _points.size():
		var current:=-1
		var best:=INF
		for i in _points.size():
			if not visited[i] and distances[i]<best:
				best=distances[i]
				current=i
		if current<0: return []
		if current in goals:
			destination=current
			break
		visited[current]=true
		for edge: Dictionary in _edges[current]:
			var next: int=edge.to
			var cost:=best+float(edge.cost)
			if cost<distances[next]:
				distances[next]=cost
				previous[next]={"from":current,"edge":edge}
	if destination<0 or previous[destination].is_empty(): return []
	var result: Array[Dictionary]=[]
	var cursor:=destination
	while cursor!=0:
		var entry: Dictionary=previous[cursor]
		if entry.is_empty(): return []
		result.push_front(entry.edge.duplicate())
		cursor=entry.from
	return result
