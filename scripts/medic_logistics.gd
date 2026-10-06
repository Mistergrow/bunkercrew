extends RefCounted
## One physical unit stays on SAN-1 until a local debit/credit transaction commits.
## This helper runs only on the authority; replicas receive cargo and presentation.
const HANDOFF_TIME := 1.25
const TRIP_DELAY := 3.0
const SEARCH_INTERVAL := 2.0
const TRAVEL_SPEED := 104.0
const Storage = preload("res://scripts/medic_storage.gd")
const VALID_PHASES := ["idle","collect","deliver","return","holding","medical"]
var medic: CharacterBody2D
var source: Node2D
var station: Node2D
var _destination: Node2D
var _search_clock := 0.0
var _route_clock := 0.0
var _blocked_time := 0.0
var _station_cursor := 0
var _resource := ""
var _job := "supply"
var _depot: Node2D
var _collection_cursor := 0
var _prefer_collection := false

func _init(robot: CharacterBody2D) -> void:
	medic = robot

func _robot_live() -> bool:
	if not is_instance_valid(medic) or not medic.is_inside_tree() or medic.is_queued_for_deletion(): return false
	var owner_game: Variant = medic.get("game")
	return owner_game is Node and is_instance_valid(owner_game) and owner_game.is_inside_tree() and not owner_game.is_queued_for_deletion()

func authoritative() -> bool:
	if not _robot_live(): return false
	var session = medic.game.get("network") if is_instance_valid(medic.game) else null
	return not is_instance_valid(session) or not session.active or session.is_host

func enabled() -> bool:
	var research = medic.game.get("upgrades") if is_instance_valid(medic.game) else null
	return is_instance_valid(research) and research.has_upgrade("medic_logistics")

func collection_enabled() -> bool:
	var research = medic.game.get("upgrades") if is_instance_valid(medic.game) else null
	return is_instance_valid(research) and research.has_upgrade("medic_collection")

func _live(node) -> bool:
	return _robot_live() and is_instance_valid(node) and node is Node2D and node.is_inside_tree() and not node.is_queued_for_deletion() and node.get("game")==medic.game and node.get_world_2d()==medic.get_world_2d()

func needs_input(candidate, resource: String) -> bool:
	if not _live(candidate) or not candidate is ProductionStation or candidate.working or candidate.output_amount > 0:
		return false
	if candidate.binder < int(candidate.recipe().get("binder",0)) or not candidate.input_kinds().has(resource):
		return false
	if candidate is RecipeStation:
		return candidate.input_cost(resource) > candidate.amount_for(resource)
	# Simple furnace alternatives share the primary ore buffer, as manual delivery does.
	return candidate.input_amount < candidate.input_cost(candidate.input_kind())

func suspend() -> void:
	if medic.logistics_phase in ["idle","medical"]:
		return
	medic.logistics_phase = "medical"
	medic.logistics_progress = 0.0
	medic.route.clear()
	_destination = null
	_route_clock = 0.0
	_blocked_time = 0.0

func _clear_trip() -> void:
	source = null
	station = null
	_destination = null
	_resource = ""
	_job = "supply"
	_depot = null
	medic.route.clear()
	medic.logistics_phase = "idle"
	medic.logistics_progress = 0.0
	_search_clock = trip_delay()
	_route_clock = 0.0
	_blocked_time = 0.0

func tick(delta: float) -> bool:
	if not authoritative() or not is_finite(delta) or delta <= 0.0:
		return false
	_search_clock = maxf(0.0,_search_clock-delta)
	_route_clock = maxf(0.0,_route_clock-delta)
	if medic.logistics_cargo.is_empty():
		if not enabled() and not collection_enabled():
			if medic.logistics_phase != "idle": _clear_trip()
			return false
		if not _pending_job_valid():
			if medic.logistics_phase not in ["idle","medical"]: _clear_trip()
			if _search_clock > 0.0: return false
			_search_clock = SEARCH_INTERVAL
			if not _find_job():
				medic.logistics_phase = "idle"
				return false
		medic.logistics_phase = "collect"
		var message := "SAN-1 · %s einsammeln" if _job == "store" else "SAN-1 · %s holen"
		medic.status_label = LocaleText.format(message,Balance.RESOURCE_NAMES.get(_resource,_resource))
		return _visit(source,delta)
	if _job == "store":
		return _store_cargo(delta)
	if enabled() and needs_input(station,medic.logistics_cargo):
		medic.logistics_phase = "deliver"
		medic.status_label = LocaleText.format("SAN-1 · %s liefern",Balance.RESOURCE_NAMES.get(medic.logistics_cargo,medic.logistics_cargo))
		return _visit(station,delta)
	# Completed/removed stations never swallow a unit. Return to real storage.
	if not _depot_valid(source,medic.logistics_cargo):
		source = null
		if _search_clock <= 0.0:
			_search_clock = SEARCH_INTERVAL
			source = _find_depot(medic.logistics_cargo)
	if not _live(source):
		return _hold_cargo(delta,"SAN-1 · Ladung gesichert · Kiste fehlt")
	medic.logistics_phase = "return"
	medic.status_label = LocaleText.format("SAN-1 · %s zurückbringen",Balance.RESOURCE_NAMES.get(medic.logistics_cargo,medic.logistics_cargo))
	return _visit(source,delta)

func _pending_job_valid() -> bool:
	if _job == "store":
		return collection_enabled() and _collection_kind(source) == _resource and not _resource.is_empty() and _depot_valid(_depot,_resource)
	return enabled() and _live(source) and source is Supply and source.amount > 0 and source.kind == _resource and needs_input(station,_resource)

func _store_cargo(delta: float) -> bool:
	# Once collected, a unit can always be secured even if the research is revoked.
	if not _depot_valid(_depot,medic.logistics_cargo):
		_depot = null
		if _search_clock <= 0.0:
			_search_clock = SEARCH_INTERVAL
			_depot = _find_depot(medic.logistics_cargo)
	if not _live(_depot):
		return _hold_cargo(delta,"SAN-1 · Ladung gesichert · Lager fehlt oder voll")
	medic.logistics_phase = "deliver"
	medic.status_label = LocaleText.format("SAN-1 · %s einlagern",Balance.RESOURCE_NAMES.get(medic.logistics_cargo,medic.logistics_cargo))
	return _visit(_depot,delta)

func _hold_cargo(delta: float, message: String) -> bool:
	medic.logistics_phase = "holding"
	medic.logistics_progress = 0.0
	medic.status_label = LocaleText.text(message)
	medic._stand(delta)
	return true

func _depot_valid(candidate, resource: String) -> bool:
	return _live(candidate) and candidate is Supply and candidate.kind == resource and Storage.can_deposit(candidate)

func _collection_kind(candidate) -> String:
	if not _live(candidate): return ""
	if candidate is ResourcePickup:
		return candidate.kind if candidate.amount > 0 and Balance.RESOURCE_NAMES.has(candidate.kind) else ""
	if candidate is ProductionStation:
		return candidate.output_kind() if not candidate.working and candidate.output_amount > 0 else ""
	return ""

func _find_depot(resource: String) -> Node2D:
	var crates := medic.get_tree().get_nodes_in_group("supplies")
	crates.sort_custom(func(a,b): return medic.global_position.distance_squared_to(a.global_position)<medic.global_position.distance_squared_to(b.global_position))
	for crate in crates:
		if _depot_valid(crate,resource) and (_in_reach(crate) or not _route_to(crate).is_empty()):
			return crate
	return null

func _assign_job(origin: Node2D, resource: String, job: String, path: Array[Dictionary]) -> void:
	source = origin
	_resource = resource
	_job = job
	_destination = origin
	medic.route = path
	medic._returning = false
	_route_clock = 1.2
	_blocked_time = 0.0
	if medic.has_method("notice_task"):
		var task := "supply" if job == "supply" else ("collect_output" if origin is ProductionStation else "collect_loose")
		medic.notice_task(task,station if job == "supply" else _depot)

func _find_job() -> bool:
	if not authoritative(): return false
	# Finished products block their machines, so clear them before restocking.
	if collection_enabled() and _find_collection_job(true):
		_prefer_collection = false
		return true
	# Alternate the two independent tasks so sustained collection cannot starve
	# crafting and a permanently hungry machine cannot monopolize the assistant.
	if _prefer_collection and collection_enabled() and _find_collection_job():
		_prefer_collection = false
		return true
	if enabled() and _find_supply_job():
		_prefer_collection = true
		return true
	if collection_enabled() and _find_collection_job():
		_prefer_collection = false
		return true
	return false

func _find_supply_job() -> bool:
	var stations := medic.get_tree().get_nodes_in_group("stations")
	var crates := medic.get_tree().get_nodes_in_group("supplies")
	if stations.is_empty(): return false
	# Rotate after every assignment so a repeatedly emptied mixer cannot starve an oven.
	for offset in stations.size():
		var index := (_station_cursor+offset)%stations.size()
		var candidate = stations[index]
		if not _live(candidate) or not candidate is ProductionStation: continue
		var reach_checked := false
		var reachable := false
		for resource: String in candidate.input_kinds():
			if not needs_input(candidate,resource): continue
			for crate in crates:
				if not _live(crate) or not crate is Supply or crate.kind != resource or crate.amount <= 0: continue
				# Synchronous search: each matching crate has the same delivery
				# route. Replan next search, never once per crate in this search.
				if not reach_checked:
					reachable = _in_reach(candidate) or not _route_to(candidate).is_empty()
					reach_checked = true
				if not reachable: break
				var path: Array[Dictionary] = _route_to(crate)
				if path.is_empty() and not _in_reach(crate): continue
				station = candidate
				_depot = null
				_assign_job(crate,resource,"supply",path)
				_station_cursor = (index+1)%stations.size()
				return true
	return false

func _find_collection_job(only_outputs: bool = false) -> bool:
	var candidates := medic.get_tree().get_nodes_in_group("stations")
	if not only_outputs:
		candidates.append_array(medic.get_tree().get_nodes_in_group("pickups"))
	if candidates.is_empty(): return false
	var depots: Dictionary = {}
	# Move through all candidates, including large piles and successive batches.
	for offset in candidates.size():
		var index := (_collection_cursor+offset)%candidates.size()
		var candidate = candidates[index]
		var resource := _collection_kind(candidate)
		if resource.is_empty(): continue
		if not depots.has(resource): depots[resource] = _find_depot(resource)
		var depot: Node2D = depots[resource]
		if not is_instance_valid(depot): continue
		var path: Array[Dictionary] = _route_to(candidate)
		if path.is_empty() and not _in_reach(candidate): continue
		_depot = depot
		station = null
		_assign_job(candidate,resource,"store",path)
		_collection_cursor = (index+1)%candidates.size()
		return true
	return false

func _route_to(node: Node2D) -> Array[Dictionary]:
	# Storage is served over built floors and ladders. Medical-only ledge jumps
	# perform a broad terrain scan and would hitch whenever a workshop is blocked.
	var floor_point: Vector2 = medic.navigation.foot_point(node.global_position)
	if floor_point==Vector2.INF: return []
	var candidates: Array[Vector2] = []
	for offset in [-31.0,31.0,0.0]:
		var point := floor_point+Vector2(offset,0)
		if medic.navigation.support_at(point) and medic.navigation.body_clear(point) and medic.navigation.treatment_line(point,node):
			candidates.append(point)
	candidates.sort_custom(func(a,b): return medic.global_position.distance_squared_to(a)<medic.global_position.distance_squared_to(b))
	for point: Vector2 in candidates:
		var path: Array[Dictionary] = medic.navigation.route(point,false)
		if not path.is_empty(): return path
	return []

func _in_reach(node: Node2D) -> bool:
	return _live(node) and absf(medic.global_position.y-node.global_position.y)<8.0 and medic.global_position.distance_to(node.global_position)<=39.0 and medic.navigation.support_at(medic.global_position) and medic.navigation.treatment_line(medic.global_position,node)

func _visit(node: Node2D, delta: float) -> bool:
	medic._returning = false
	medic.refill_progress = 0.0
	if _destination != node:
		_destination = node
		medic.route.clear()
		_route_clock = 0.0
		_blocked_time = 0.0
		medic.logistics_progress = 0.0
	if _in_reach(node):
		medic.route.clear()
		medic._stand(delta)
		if medic.velocity.length() > 4.0: return true
		medic.logistics_progress = minf(handoff_time(),medic.logistics_progress+delta)
		if medic.logistics_progress >= handoff_time(): _handoff(node)
		return true
	medic.logistics_progress = 0.0
	if _route_clock <= 0.0 and (medic.route.is_empty() or medic._stuck_time>.65 or _blocked_time>.65):
		medic.route = _route_to(node)
		medic._stuck_time = 0.0
		_route_clock = 1.2
	var before: Vector2 = medic.global_position
	if medic.route.is_empty():
		medic._stand(delta)
	else:
		medic._follow_route(delta,TRAVEL_SPEED)
	# A newly placed obstacle can leave a syntactically valid ladder route.
	# Measure actual travel, including the early safety return in ladder motion.
	_blocked_time = _blocked_time+delta if medic.global_position.distance_to(before)<.01 else 0.0
	if _blocked_time>.65:
		medic.status_label = LocaleText.text("SAN-1 · Transportweg blockiert")
	if _blocked_time>=6.0:
		if medic.logistics_cargo.is_empty(): _clear_trip()
		elif _job == "store":
			_depot = null
		elif node == station:
			station = null
		elif node == source:
			source = null
	return true

func _handoff(node: Node2D) -> void:
	# Recheck the live inventory at commit time; players may take it during the hold.
	if not authoritative() or not _in_reach(node): return
	if medic.logistics_phase == "collect":
		if not _pending_job_valid() or node != source or not medic.logistics_cargo.is_empty(): return
		if _job == "store":
			# A storage destination is reserved before debit; no crate is invented.
			if not _in_reach(_depot) and _route_to(_depot).is_empty(): return
			if source is ResourcePickup:
				source.amount -= 1
				if source.amount <= 0: source.queue_free()
			else:
				source.output_amount -= 1
		else:
			source.amount -= 1
			Storage.refill(source)
		medic.logistics_cargo = _resource
		medic.logistics_phase = "deliver"
		var message := "SAN-1 · %s einlagern" if _job == "store" else "SAN-1 · %s liefern"
		medic.status_label = LocaleText.format(message,Balance.RESOURCE_NAMES.get(_resource,_resource))
	elif medic.logistics_phase == "deliver":
		if _job == "store":
			if node != _depot or not _depot_valid(_depot,medic.logistics_cargo) or medic.logistics_cargo.is_empty(): return
			if not Storage.store_unit(_depot): return
		else:
			if not enabled() or node != station or not needs_input(station,medic.logistics_cargo): return
			if station is RecipeStation:
				station.set_amount(medic.logistics_cargo,station.amount_for(medic.logistics_cargo)+1)
			else:
				station.input_amount += 1
				if station.kind == "furnace" and medic.logistics_cargo == "scrap":
					station.input_scrap += 1
		medic.logistics_cargo = ""
		_clear_trip()
	elif medic.logistics_phase == "return":
		if node != source or not _depot_valid(source,medic.logistics_cargo) or medic.logistics_cargo.is_empty(): return
		if not Storage.store_unit(source): return
		medic.logistics_cargo = ""
		_clear_trip()
	else:
		return
	medic.logistics_progress = 0.0
	_destination = null
	node.queue_redraw()
	preload("res://scripts/spatial_sound.gd").emit(medic.game,"pickup",medic.global_position)

func handoff_time() -> float:
	var research = medic.game.get("upgrades") if is_instance_valid(medic.game) else null
	return HANDOFF_TIME * (research.logistics_time_multiplier() if is_instance_valid(research) and research.has_method("logistics_time_multiplier") else 1.0)

func trip_delay() -> float:
	var research = medic.game.get("upgrades") if is_instance_valid(medic.game) else null
	return TRIP_DELAY * (research.logistics_time_multiplier() if is_instance_valid(research) and research.has_method("logistics_time_multiplier") else 1.0)
