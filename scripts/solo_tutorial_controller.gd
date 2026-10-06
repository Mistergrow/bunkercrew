extends Node
const Catalog := preload("res://scripts/solo_tutorial_catalog.gd")
const Records := preload("res://scripts/solo_tutorial_state.gd")
const Labels := preload("res://scripts/input_labels.gd")
const NetInput := preload("res://scripts/network_input.gd")
const L := preload("res://scripts/locale_text.gd")
const POLL_INTERVAL := 0.2
const MAX_TRACKED := 256
const GROUPS := ["supplies","pickups","stations","walls","turrets","diggable_terrain","scenario_room_sites","field_workshops"]
var game: Node
var records := Records.new()
var enabled := true
var active := false
var _clock := 0.0
var _worker_id := 0
var _core_id := 0
var _last_position := Vector2.ZERO
var _walked := 0.0
var _inventory: Dictionary = {}
var _objects: Dictionary = {}
var _nodes: Dictionary = {}
var _mined := 0
var _phase := ""
var _wave := 0
var _repair_vehicle := 0
var _choice: Dictionary = {}
var _events: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	records.load_records()
	enabled = records.enabled

func _process(delta: float) -> void:
	_clock += delta
	if _clock<POLL_INTERVAL: return
	_clock = 0.0
	observe()

static func _value(subject: Variant,key: String,fallback: Variant = null) -> Variant:
	return subject.get(key) if subject is Object and is_instance_valid(subject) and key in subject else fallback

func _owned(node: Variant) -> bool:
	return node is Node2D and is_instance_valid(node) and not node.is_queued_for_deletion() and node.is_inside_tree() and _value(node,"game") == game and game is Node2D and node.get_world_2d() == game.get_world_2d()

func _worker() -> Node2D:
	var party: Variant = _value(game,"players",[])
	if not party is Array or party.size()!=1 or not _owned(party[0]) or int(_value(party[0],"player_id",0))!=1: return null
	return party[0]

func is_available() -> bool:
	if not is_instance_valid(game) or not game.is_inside_tree() or not bool(_value(game,"started",false)) or int(_value(game,"player_count",0))!=1: return false
	if bool(_value(_value(game,"network"),"active",false)): return false
	return _worker()!=null

func _can_observe() -> bool:
	if not enabled or not is_available() or get_tree().paused or bool(_value(game,"_restart_pending",false)): return false
	var hud: Variant = _value(game,"hud")
	if not str(_value(hud,"overlay","")).is_empty(): return false
	if hud is Object and is_instance_valid(hud) and hud.has_method("blocks_gameplay_input") and hud.blocks_gameplay_input(): return false
	return true

func _read_nodes() -> void:
	_nodes.clear()
	for group: String in GROUPS:
		var matches: Array[Node2D] = []
		for node: Node in get_tree().get_nodes_in_group(group):
			if _owned(node): matches.append(node)
			if matches.size()>=MAX_TRACKED: break
		_nodes[group] = matches

func _object_samples() -> Dictionary:
	var result: Dictionary = {}
	for group: String in ["supplies","pickups","stations"]:
		for node: Node2D in _nodes.get(group,[]):
			if not _owned(node): continue
			var kind := str(_value(node,"kind",""))
			var amount := int(_value(node,"amount",0))
			if group=="stations":
				if not node.has_method("output_kind"): continue
				kind = str(node.output_kind())
				amount = int(_value(node,"output_amount",0))
			result[node.get_instance_id()] = {"kind":kind,"amount":amount,"group":group}
			if result.size()>=MAX_TRACKED: return result
	return result

func _bind_events() -> void:
	var next: Variant = _value(game,"combat_events")
	if next==_events: return
	if is_instance_valid(_events) and _events.has_signal("event") and _events.is_connected("event",_on_event): _events.disconnect("event",_on_event)
	_events = next if next is Node and is_instance_valid(next) else null
	if is_instance_valid(_events) and _events.has_signal("event"): _events.connect("event",_on_event)

func _baseline(worker: Node2D) -> void:
	_worker_id = worker.get_instance_id()
	var core: Variant = _value(game,"core")
	_core_id = core.get_instance_id() if is_instance_valid(core) else 0
	_last_position = worker.global_position
	_walked = 0.0
	_inventory = _value(worker,"inventory",{}).duplicate()
	_objects = _object_samples()
	_mined = int(_value(_events,"counters",{}).get("mined",0))
	_phase = str(_value(_value(game,"rounds"),"phase",""))
	_wave = int(_value(_value(game,"rounds"),"wave",0))
	_repair_vehicle = 0

func observe() -> void:
	# A five-Hz observer reads only this game's physical world. It never controls
	# timers, actors, resources, research, mission rewards, or network events.
	if not enabled or records.completed():
		active = false
		_choice.clear()
		return
	if not is_available():
		active = false
		_worker_id = 0
		_choice.clear()
		return
	if not _can_observe():
		active = false
		return
	var worker := _worker()
	_read_nodes()
	_bind_events()
	var core: Variant = _value(game,"core")
	var core_id: int = core.get_instance_id() if is_instance_valid(core) else 0
	if worker.get_instance_id()!=_worker_id or core_id!=_core_id:
		_baseline(worker)
	else:
		_learn_world_changes(worker)
	_learn_existing_context(worker)
	_choice = _select(worker)
	active = enabled and not records.completed() and not _choice.is_empty()

func _learn_world_changes(worker: Node2D) -> void:
	var movement := worker.global_position-_last_position
	_last_position = worker.global_position
	if not is_instance_valid(_value(worker,"mounted_turret")) and movement.is_finite() and movement.length()<128.0:
		var horizontal := NetInput.axis(worker,"left","right")
		var vertical := NetInput.axis(worker,"up","down")
		if absf(horizontal)>.1 and movement.x*horizontal>1.0:
			_walked += absf(movement.x)
		elif bool(_value(worker,"climbing",false)) and absf(vertical)>.1 and movement.y*vertical>1.0:
			_walked += absf(movement.y)
		if _walked>=36.0: records.mark("move")
	var inventory: Dictionary = _value(worker,"inventory",{})
	var samples := _object_samples()
	for id: int in _objects:
		var previous: Dictionary = _objects[id]
		var current: Dictionary = samples.get(id,{"amount":0})
		var kind := str(previous.kind)
		if int(previous.amount)>int(current.amount) and int(inventory.get(kind,0))>int(_inventory.get(kind,0)):
			if previous.group in ["supplies","pickups"]: records.mark("gather")
			elif previous.group=="stations": records.mark("production")
	var mined := int(_value(_events,"counters",{}).get("mined",0))
	if mined>_mined: records.mark("gather")
	_mined = mined
	_inventory = inventory.duplicate()
	_objects = samples
	var rounds: Variant = _value(game,"rounds")
	var phase := str(_value(rounds,"phase",""))
	var wave := int(_value(rounds,"wave",0))
	if _phase=="attack" and ((phase=="salvage" and wave==_wave) or (phase=="build" and wave>_wave)):
		records.mark("defend")
	_phase = phase
	_wave = wave
	var vehicle: Variant = _vehicle()
	if _owned(vehicle):
		var journey: Dictionary = _value(vehicle,"journey_state",{})
		if str(journey.get("phase",""))=="repair": _repair_vehicle = vehicle.get_instance_id()
		if vehicle.get_instance_id()==_repair_vehicle and bool(journey.get("breakdown_done",false)) and str(journey.get("repair_step",""))=="done": records.mark("repair")

func _learn_existing_context(worker: Node2D) -> void:
	var story: Variant = _value(game,"story")
	var wall: Variant = _value(story,"wall")
	if bool(_value(story,"enabled",false)):
		if int(_value(story,"stage",0))>0 or (_owned(wall) and int(_value(wall,"state",0))==DefenseWall.State.HARD): records.mark("wall")
	else:
		for front: Node2D in _nodes.get("walls",[]):
			if _owned(front) and front is DefenseWall and front.state==DefenseWall.State.HARD:
				records.mark("wall")
				break
	var mounted: Variant = _value(worker,"mounted_turret")
	if _owned(mounted) and mounted is RoofTurret: records.mark("turret")
	if int(_value(_value(game,"rounds"),"wave",1))>1: records.mark("defend")
	var workshop: Variant = _value(game,"workshop")
	if _owned(workshop) and workshop.has_method("accessible") and workshop.accessible(): records.mark("excavate")
	var medic: Variant = _value(game,"medic")
	if _owned(medic):
		if int(_value(medic,"treatments_completed",0))>0 or (_walked>=36.0 and worker.global_position.distance_to(medic.global_position)<72.0): records.mark("san")
	var vehicle: Variant = _vehicle()
	if _owned(vehicle):
		var journey: Dictionary = _value(vehicle,"journey_state",{})
		if str(journey.get("phase",""))=="driving" and vehicle.has_method("seat_for") and is_instance_valid(vehicle.seat_for(worker)):
			records.mark("departure")
		if str(journey.get("phase",""))=="repair": _repair_vehicle = vehicle.get_instance_id()

func _on_event(kind: String,data: Dictionary) -> void:
	if not _can_observe() or int(data.get("player_id",0))!=1: return
	if kind in ["hit","kill"] and float(data.get("damage",0.0))>0.0:
		records.mark("defend")
	elif kind=="support" and str(data.get("action",""))=="production" and float(data.get("earned",0.0))>0.0:
		var worker := _worker()
		for station: Node2D in _nodes.get("stations",[]):
			if _owned(station) and station is ProductionStation and station.output_amount>0 and station.batch_donors.has(worker.get_instance_id()):
				# The real batch event captures this exact paid output buffer. This
				# survives finishing and collecting between two observer polls;
				# taking the same material from a crate cannot debit this station.
				_objects[station.get_instance_id()] = {"kind":station.output_kind(),"amount":station.output_amount,"group":"stations"}
	elif kind=="craft":
		var workshop: Variant = _value(game,"workshop")
		if not _owned(workshop) or not workshop.has_method("accessible") or not workshop.accessible(): return
		for recipe: Dictionary in CraftingCatalog.recipes():
			if str(recipe.get("kind",""))==str(data.get("recipe","")):
				records.mark("workshop")
				break

func _vehicle() -> Variant:
	return _value(_value(game,"expedition"),"vehicle")

func _nearest(group: String,worker: Node2D,predicate: Callable = Callable()) -> Node2D:
	var nearest: Node2D
	var distance := INF
	for node: Node2D in _nodes.get(group,[]):
		if not _owned(node) or (predicate.is_valid() and not predicate.call(node)): continue
		var score := worker.global_position.distance_squared_to(node.global_position)
		if score<distance:
			nearest = node
			distance = score
	return nearest

func _production_possible(station: Node2D,worker: Node2D) -> bool:
	if not station is ProductionStation: return false
	if station.output_amount>0 or station.working: return true
	if station.binder<int(station.recipe().get("binder",0)): return false
	if station.input_amount>=station.input_cost(station.input_kind()): return true
	for kind: String in station.input_kinds():
		if int(_value(worker,"inventory",{}).get(kind,0))>0: return true
		for group: String in ["supplies","pickups"]:
			for source: Node2D in _nodes.get(group,[]):
				if _owned(source) and str(_value(source,"kind",""))==kind and int(_value(source,"amount",0))>0: return true
		for field: Node2D in _nodes.get("diggable_terrain",[]):
			if not _owned(field) or not field is DiggableTerrain: continue
			for block: MineBlock in field.blocks:
				if _owned(block) and not block.depleted and block.kind==kind: return true
	return false

func _select(worker: Node2D) -> Dictionary:
	var stage := str(_value(_value(game,"expedition"),"stage","defense"))
	var vehicle: Variant = _vehicle()
	if worker.has_method("can_act") and not worker.can_act(): return {"id":"downed","target":_value(game,"medic")}
	if _owned(vehicle) and str(_value(vehicle,"journey_state",{}).get("phase",""))=="repair":
		var journey: Dictionary = vehicle.journey_state
		var san_working: bool = int(journey.get("repair_operator",0))==0 and bool(journey.get("solo_assist",false)) and vehicle.has_method("_solo_service_medic") and is_instance_valid(vehicle._solo_service_medic())
		return {"id":"repair","target":vehicle,"entry":"repair_cover" if san_working else "repair"}
	var phase := str(_value(_value(game,"rounds"),"phase",""))
	if phase in ["defeat","victory"] and stage=="defense": return {}
	if stage in ["preparation","map"] or (stage=="travel" and not records.learned.has("departure")):
		return {"id":"departure","target":vehicle} if records.pending("departure") else {}
	if stage!="defense": return {}
	var story: Variant = _value(game,"story")
	if phase in ["warning","attack"]: return {"id":"danger","target":_value(game,"turret")}
	if bool(_value(story,"enabled",false)) and int(_value(story,"stage",0)) in [2,4,6]: return {"id":"signal","target":_value(story,"relay")}
	if worker.has_method("carried_count") and worker.has_method("capacity") and worker.carried_count()>=worker.capacity(): return {"id":"full","target":null}
	if records.pending("move"): return {"id":"move","target":null}
	var wall: Variant = _value(story,"wall")
	if records.pending("gather"):
		var needed := "concrete" if _owned(wall) and int(_value(wall,"state",0))<DefenseWall.State.FRESH else ""
		var supply := _nearest("supplies",worker,func(node: Node2D): return int(_value(node,"amount",0))>0 and (needed.is_empty() or str(_value(node,"kind",""))==needed))
		if supply==null: supply = _nearest("supplies",worker,func(node: Node2D): return int(_value(node,"amount",0))>0)
		if supply!=null and _value(worker,"inventory",{}).is_empty(): return {"id":"gather","target":supply}
	if records.pending("wall") and _owned(wall) and int(_value(wall,"state",0))!=DefenseWall.State.HARD: return {"id":"wall","target":wall}
	if records.pending("turret"):
		var gun := _nearest("turrets",worker,func(node: Node2D): return node is RoofTurret)
		if gun!=null: return {"id":"turret","target":gun}
	if records.pending("defend") and bool(_value(_value(game,"rounds"),"running",false)): return {"id":"defend","target":_value(game,"turret")}
	if records.pending("production"):
		var station := _nearest("stations",worker,func(node: Node2D): return _production_possible(node,worker))
		if station!=null: return {"id":"production","target":station}
	var workshop: Variant = _value(game,"workshop")
	if records.pending("excavate") and _owned(workshop) and not workshop.accessible():
		var field := _nearest("diggable_terrain",worker,func(node: Node2D): return node is DiggableTerrain and not node.is_cleared())
		if field!=null: return {"id":"excavate","target":field}
	if records.pending("workshop") and _owned(workshop) and workshop.accessible(): return {"id":"workshop","target":workshop}
	if records.pending("san") and _owned(_value(game,"medic")): return {"id":"san","target":game.get("medic")}
	return {}

func current_step() -> Dictionary:
	if not active or not _can_observe() or _choice.is_empty(): return {}
	var id := str(_choice.id)
	var entry_id := str(_choice.get("entry",id))
	var entry := Catalog.entry(entry_id)
	if entry.is_empty(): return {}
	var worker := _worker()
	var interact := Labels.action(worker,"interact")
	var fire := Labels.action(worker,"fire")
	var reload_label := Labels.action(worker,"reload")
	var args: Array = []
	match id:
		"move":
			var movement := L.text("Linker Stick") if NetInput.primary_controller_enabled(game) and not NetInput.mouse_aim(worker) else Labels.action(worker,"left")+" / "+Labels.action(worker,"right")
			args = [movement,Labels.action(worker,"jump"),_menu_label(worker,"help")]
		"gather": args = [interact,Labels.action(worker,"cycle_target")]
		"wall":
			var story: Variant = _value(game,"story")
			args = [story.objective() if is_instance_valid(story) and story.has_method("objective") else "",interact]
		"turret": args = [interact,fire,reload_label]
		"defend": args = [Labels.menu(game,"skip_build"),fire,reload_label]
		"production": args = [interact,interact]
		"excavate": args = [interact,Labels.action(worker,"drop")]
		"workshop","departure": args = [interact]
		"san": args = [_menu_label(worker,"upgrades")]
		"repair": args = [interact] if entry_id=="repair_cover" else [interact,interact]
		"full": args = [Labels.action(worker,"cycle_material"),Labels.action(worker,"drop")]
		"danger": args = [fire,reload_label,interact]
		"signal": args = [_value(game,"story").objective()]
	var index := Catalog.IDS.find(id)
	var result := {"id":id,"title":L.text(str(entry.title)),"body":L.format(str(entry.body),args) if not args.is_empty() else L.text(str(entry.body)),"target":_choice.get("target"),"learned":id in records.learned,"index":index if index>=0 else mini(Catalog.IDS.size()-1,records.learned.size()),"count":Catalog.IDS.size(),"progress":float(records.learned.size()+records.skipped.size())/Catalog.IDS.size()}
	return result

func _menu_label(worker: Node2D,action: String) -> String:
	if NetInput.primary_controller_enabled(game) and not NetInput.mouse_aim(worker):
		if action=="help": return L.text("Pause → Handbuch")
		if action=="upgrades": return L.text("Pause → Technik")
	return Labels.menu(game,action)

func get_view() -> Dictionary:
	var result := current_step()
	result.merge({"enabled":enabled,"active":not result.is_empty(),"completed":records.completed(),"learned_count":records.learned.size(),"count":Catalog.IDS.size()},true)
	return result

func target_position() -> Vector2:
	var target: Variant = current_step().get("target")
	if _owned(target):
		if target is DiggableTerrain:
			var worker := _worker()
			var best := Vector2(INF,INF)
			var distance := INF
			for block: MineBlock in target.blocks:
				if not _owned(block) or block.depleted: continue
				var point := block.surface_near(worker.global_position-Vector2(0,20))
				var score := point.distance_squared_to(worker.global_position)
				if score<distance:
					best = point
					distance = score
			return best
		return target.interaction_point() if target.has_method("interaction_point") else target.global_position
	return Vector2(INF,INF)

func set_enabled(value: bool) -> void:
	enabled = value
	records.enabled = value
	records.save()
	# Pauses and co-op are suspension, not learned actions. Resume from a clean
	# observation baseline rather than crediting unrelated paused-world changes.
	_worker_id = 0
	observe()

func restart() -> void:
	records.reset()
	enabled = true
	_worker_id = 0
	observe()

func stop() -> void:
	set_enabled(false)

func dismiss_current() -> void:
	var step := current_step()
	if not step.is_empty() and Catalog.contains(str(step.id)):
		records.mark(str(step.id),true)
		observe()

func session_records() -> Dictionary:
	return records.capture()

func restore_session_records(data: Variant) -> bool:
	if not records.restore(data): return false
	enabled = records.enabled
	active = false
	_worker_id = 0
	_choice.clear()
	return true

func _exit_tree() -> void:
	if is_instance_valid(_events) and _events.has_signal("event") and _events.is_connected("event",_on_event): _events.disconnect("event",_on_event)
