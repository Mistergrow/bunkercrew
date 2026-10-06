extends RefCounted
## Host-authoritative full world snapshots. Client instances are presentation only.
const Schema := preload("res://scripts/network_replication_schema.gd")
const ID_META := "network_entity_id"
const NEXT_ID_META := "network_entity_next_id"
const Story := preload("res://scripts/story_director.gd")
const Storm := preload("res://scripts/storm_events.gd")
const Expedition := preload("res://scripts/expedition_controller.gd")
var game: Node
var client := false
var entities: Dictionary = {}
var next_id := 1
var last_error := ""
var _targets: Dictionary = {}
var _signal_changes: Array[Node] = []
var _registry_dirty := true
var _applied := false
var _property_types: Dictionary = {}
var _spatial_types: Dictionary = {}
var _allowed_fields: Dictionary = {}
var _required_fields: Dictionary = {}
var _construction_signature: Array = []
var _construction_plan: Dictionary = {}
const COMMON_PROPERTY_TYPES := {"position":TYPE_VECTOR2,"velocity":TYPE_VECTOR2,"rotation":TYPE_FLOAT,"visible":TYPE_BOOL,"z_index":TYPE_INT}
const SPATIAL_FIELDS := ["position","rotation","visible","z_index"]
const SMOOTH_TYPES := ["convoy_vehicle","player","ground_infantry","enemy","boss_machine","air_machine","field_medic","projectile","worker_projectile","flak_projectile","hostile_air_projectile"]

func bind(owner_game: Node) -> void:
	game = owner_game
	_registry_dirty=true
	entities.clear()
	_targets.clear()
	_construction_signature.clear()
	_construction_plan.clear()
	next_id = maxi(1,int(game.get_meta(NEXT_ID_META,1)))
	_applied = false
	_reserve_dynamic_ids(game)
	_scan(game)

func _reserve_dynamic_ids(parent: Node) -> void:
	# A reconnect binds the surviving world. Reserve all old IDs before assigning
	# any new ones, including a newly inserted node earlier in the scene tree.
	for node in parent.get_children():
		_reserve_id(str(node.get_meta(ID_META,"")))
		_reserve_dynamic_ids(node)

func _reserve_id(id: String) -> void:
	if not id.begins_with("dynamic:"): return
	var number:=id.get_slice("/",0).trim_prefix("dynamic:")
	if number.is_valid_int() and number.to_int()>0 and number.to_int()<=1000000000:
		next_id=maxi(next_id,number.to_int()+1)
		game.set_meta(NEXT_ID_META,next_id)

func _registry_changed(_node: Node) -> void:
	_registry_dirty=true

func _scan(parent: Node) -> void:
	if parent==game:
		if not _registry_dirty: return
		_registry_dirty=false
	if not parent.child_entered_tree.is_connected(_registry_changed): parent.child_entered_tree.connect(_registry_changed)
	if not parent.child_exiting_tree.is_connected(_registry_changed): parent.child_exiting_tree.connect(_registry_changed)
	for node in parent.get_children():
		if node.is_queued_for_deletion(): continue
		var kind := Schema.kind(node)
		if not kind.is_empty():
			var id := _id(node,kind)
			entities[id] = node
		_scan(node)

func _id(node: Node,kind := "") -> String:
	if node.has_meta(ID_META) and not str(node.get_meta(ID_META)).begins_with("local:"):
		var saved: String=str(node.get_meta(ID_META))
		_reserve_id(saved)
		return saved
	if kind.is_empty(): kind = Schema.kind(node)
	if kind.is_empty(): return ""
	var id := ""
	if kind=="player":
		id = "player:%d"%int(node.player_id)
	elif kind=="scenario_room_site":
		# The work panel moves down with its newly opened shaft; its identity does not.
		id = "fixed:scenario_room_site:%d"%int(node.room_index)
	elif kind=="mine_block" and is_instance_valid(node.terrain_owner):
		# Missing cells must not renumber surviving siblings before the first scan.
		id = _id(node.terrain_owner,"diggable_terrain")+"/mine_block:%d:%d"%[node.grid_cell.x,node.grid_cell.y]
	elif kind in Schema.DYNAMIC:
		id = "dynamic:%d"%next_id
		next_id += 1
		game.set_meta(NEXT_ID_META,next_id)
	else:
		var parent := node.get_parent()
		var parent_kind := Schema.kind(parent) if parent != null else ""
		if not parent_kind.is_empty():
			var ordinal := 0
			for sibling in parent.get_children():
				if sibling==node: break
				if Schema.kind(sibling)==kind: ordinal+=1
			id = _id(parent,parent_kind)+"/"+kind+":"+str(ordinal)
		elif kind=="diggable_terrain":
			id = "fixed:diggable_terrain:%d:%d"%[roundi(node.bounds.position.x),roundi(node.bounds.position.y)]
		elif node is Node2D:
			id = "fixed:%s:%d:%d"%[kind,roundi(node.global_position.x),roundi(node.global_position.y)]
		else:
			id = "system:"+kind
	node.set_meta(ID_META,id)
	return id

func capture() -> Dictionary:
	if not is_instance_valid(game): return {}
	_scan(game)
	var records: Array = []
	for id: String in entities.keys():
		var node = entities[id]
		if not _alive(node):
			entities.erase(id)
			continue
		var kind := Schema.kind(node)
		var state := _capture_fields(node,Schema.fields(kind))
		if node is Node2D:
			state.position = node.position
			state.rotation = node.rotation
			state.visible = node.visible
			state.z_index = node.z_index
		var references := {}
		for field in Schema.refs(kind):
			var target = node.get(field)
			references[field] = _id(target) if _alive(target) else ""
		var metadata := {}
		for key in Schema.META:
			if node.has_meta(key) and Schema.safe(node.get_meta(key)): metadata[key] = node.get_meta(key)
		var parent_id := str(node.get_parent().get_meta(ID_META,""))
		var record := {"id":id,"type":kind,"parent":parent_id,"state":state,"refs":references,"meta":metadata}
		if kind=="field_medic": record.status_message=LocaleText.message_payload(node.status_label)
		records.append(record)
	var bunker = game.scenario_bunker
	var boss_id := ""
	if is_instance_valid(game.combat_events) and game.combat_events._boss != null:
		var boss = game.combat_events._boss.get_ref()
		if is_instance_valid(boss) and not boss.is_queued_for_deletion(): boss_id = _id(boss)
	var result := {"version":Schema.VERSION,"boss":boss_id,"options":game.scenario_options.duplicate(),"game":_capture_fields(game,Schema.game_fields()),"structure":{"rooms":bunker.open_depths,"excavation_depths":bunker.excavation_depths,"wave":game.rounds.wave,"view_stage":game.view_stage,"flak_tier":game.flak_station.tier,"dome_available":game.dome.available},"entities":records}
	if is_instance_valid(game.get("story")): result.story=game.story.capture_state()
	if is_instance_valid(game.weather.get("storm_events")): result.storm=game.weather.storm_events.capture_state()
	if is_instance_valid(game.get("expedition")): result.expedition=game.expedition.capture_state()
	result.notice_message=LocaleText.message_payload(game.notice)
	return result

func _alive(node) -> bool:
	if not is_instance_valid(node) or not node is Node: return false
	var current: Node=node
	while current!=game:
		if current==null or current.is_queued_for_deletion(): return false
		current=current.get_parent()
	return true

func _capture_fields(node: Node,fields: PackedStringArray) -> Dictionary:
	var state := {}
	for field in fields:
		if not field in node: continue
		var value = node.get(field)
		if field=="transfer" and value is Dictionary:
			var transfer := {}
			for key in value:
				var wire_key = key
				for player in game.players:
					if key is int and key==player.get_instance_id(): wire_key="@player:%d"%player.player_id
				transfer[wire_key]=value[key]
			value=transfer
		if Schema.safe(value): state[field]=value.duplicate(true) if value is Dictionary or value is Array else value
	return state

func _fail(reason: String) -> bool:
	last_error=reason
	return false

func _validate(snapshot: Dictionary, wire_validated: bool=false) -> bool:
	if not snapshot.get("version") is int or snapshot.version!=Schema.VERSION: return _fail("Unsupported world version")
	for field in snapshot:
		if not field in ["version","boss","options","game","structure","entities","story","storm","notice_message","expedition"]: return _fail("Unexpected snapshot field")
	if snapshot.has("expedition"):
		if not Expedition.valid_state(snapshot.expedition): return _fail("Invalid expedition state")
		if not is_instance_valid(game.get("expedition")): return _fail("Missing expedition controller")
		if not snapshot.expedition.is_empty():
			if snapshot.expedition.checkpoint.player_count!=game.player_count: return _fail("Expedition player count mismatch")
			if game.expedition.road_open and not snapshot.expedition.road: return _fail("Road bounds regressed")
	if not snapshot.has("notice_message") or not LocaleText.valid_message_payload(snapshot.notice_message): return _fail("Invalid localized notice")
	if is_instance_valid(game.get("story")) and not snapshot.has("story"): return _fail("Missing story state")
	if is_instance_valid(game.weather.get("storm_events")) and not snapshot.has("storm"): return _fail("Missing storm state")
	if snapshot.has("story"):
		if not snapshot.story is Dictionary or not Story.valid_state(snapshot.story): return _fail("Invalid story state")
		if not is_instance_valid(game.get("story")) or snapshot.story.enabled!=game.story.enabled: return _fail("Story mode mismatch")
		if _applied and snapshot.story.serial<game.story.serial: return _fail("Stale story state")
	if snapshot.has("storm"):
		if not snapshot.storm is Dictionary or not Storm.valid_state(snapshot.storm): return _fail("Invalid storm state")
		if _applied and is_instance_valid(game.weather.get("storm_events")) and snapshot.storm.serial<game.weather.storm_events.serial: return _fail("Stale storm state")
		if snapshot.storm.serial>0:
			var props=game.scenery.get("props_layer")
			var index: int=snapshot.storm.target_index
			if not is_instance_valid(props) or index<0 or index>=props.entries.size() or props.entries[index].kind!="tree": return _fail("Missing storm tree")
			if not Rect2(props.entries[index].bounds).grow(32).has_point(props.to_local(snapshot.storm.target)): return _fail("Storm target outside tree")
	if not snapshot.get("entities") is Array or snapshot.entities.size()>Schema.MAX_ENTITIES: return _fail("Invalid entity count")
	if not snapshot.get("structure") is Dictionary or not snapshot.get("game") is Dictionary: return _fail("Missing world structure")
	if (not wire_validated and (not Schema.safe(snapshot.game) or not Schema.safe(snapshot.structure))) or not Schema.bounded(snapshot.game): return _fail("Invalid world values")
	for field in Schema.game_fields():
		if not snapshot.game.has(field): return _fail("Missing game property")
	for field in snapshot.game:
		if not field in Schema.game_fields(): return _fail("Unlisted game property")
		if not field in game or (typeof(snapshot.game[field])!=typeof(game.get(field)) and not (game.get(field) is float and snapshot.game[field] is int)): return _fail("Wrong game property type")
	if not wire_validated and var_to_bytes(snapshot).size()>Schema.MAX_BYTES: return _fail("World exceeds size limit")
	if not snapshot.get("options") is Dictionary or snapshot.options!=game.scenario_options: return _fail("World selection mismatch")
	var structure: Dictionary=snapshot.structure
	if not structure.get("rooms") is int or structure.rooms<0 or structure.rooms>4: return _fail("Invalid room count")
	if not structure.get("excavation_depths") is int or structure.excavation_depths<maxi(1,structure.rooms) or structure.excavation_depths>mini(4,structure.rooms+1): return _fail("Invalid excavation depth")
	if not structure.get("flak_tier") is int or structure.flak_tier<0 or structure.flak_tier>3: return _fail("Invalid flak tier")
	if not structure.get("wave") is int or structure.wave<1 or structure.wave>20: return _fail("Invalid wave")
	if not structure.get("view_stage") is int or structure.view_stage<1 or structure.view_stage>4: return _fail("Invalid view stage")
	if not structure.get("dome_available") is bool: return _fail("Invalid dome availability")
	if structure.size()!=6 or structure.rooms<game.scenario_bunker.open_depths or structure.excavation_depths<game.scenario_bunker.excavation_depths or structure.flak_tier<game.flak_station.tier or (game.dome.available and not structure.dome_available): return _fail("Structure regressed")
	for index in range(structure.excavation_depths):
		if structure.wave<int(ScenarioRoomCatalog.spec(index).wave): return _fail("Room precedes construction wave")
	if not snapshot.game.player_count in [1,2,3,4] or snapshot.game.player_count!=game.player_count: return _fail("Player count changed")
	var road_snapshot: bool = snapshot.has("expedition") and not snapshot.expedition.is_empty() and snapshot.expedition.road
	var expected_right: float = Expedition.ROAD_BOUND if road_snapshot else game.world_right
	if snapshot.game.view_stage!=structure.view_stage or snapshot.game.world_left!=game.world_left or snapshot.game.world_right!=expected_right: return _fail("Invalid world bounds or stage")
	if snapshot.game.camera_target_zoom<0.1 or snapshot.game.camera_target_zoom>8.0: return _fail("Invalid camera zoom")
	if not snapshot.game.stats is Dictionary or not Schema.counters(snapshot.game.stats,["mined","produced","built","kills"],100000000): return _fail("Invalid match counters")
	var convoy_count := 0
	var ids := {}
	for record in snapshot.entities:
		if not record is Dictionary or not record.get("id") is String or not record.get("type") is String: return _fail("Invalid entity record")
		if record.id.length()>256 or record.id.is_empty() or ids.has(record.id): return _fail("Invalid or duplicate entity ID")
		ids[record.id]=record
		if not Schema.FIELDS.has(record.type): return _fail("Unknown entity type")
		if record.type=="convoy_vehicle":
			convoy_count+=1
			if convoy_count>1: return _fail("Multiple crew convoys")
		if is_instance_valid(entities.get(record.id)) and Schema.kind(entities[record.id])!=record.type: return _fail("Entity type changed")
		if not record.get("state") is Dictionary or not record.get("refs") is Dictionary or not record.get("meta") is Dictionary: return _fail("Malformed entity state")
		if record.type=="field_medic" and not LocaleText.valid_message_payload(record.get("status_message")): return _fail("Invalid localized medic status")
		if not record.get("parent") is String or record.parent.length()>256: return _fail("Invalid parent ID")
		if not wire_validated and (not Schema.safe(record.state) or not Schema.safe(record.meta)): return _fail("Unsafe entity state")
		if record.type=="scenery_damage":
			var reactions = entities.get(record.id)
			if record.id!="system:scenery_damage" or not is_instance_valid(reactions) or not is_instance_valid(reactions.props): return _fail("Unknown scenery controller")
			if record.state.size()!=1 or not preload("res://scripts/scenery_damage.gd").valid_states(record.state.get("states"),reactions.props.entries): return _fail("Invalid scenery damage states")
		_property_types_for(record.type)
		var allowed: Dictionary = _allowed_fields[record.type]
		if _spatial_types[record.type]:
			for field in SPATIAL_FIELDS:
				if not record.state.has(field): return _fail("Missing entity transform")
		for field in record.state:
			if not field in allowed: return _fail("Unlisted property: "+str(field))
			var expected: int = allowed[field]
			var value = record.state[field]
			if expected<0 or (expected!=TYPE_NIL and typeof(value)!=expected and not (expected==TYPE_FLOAT and value is int)): return _fail("Wrong property type: "+str(field))
		for field in _required_fields[record.type]:
			if not record.state.has(field): return _fail("Missing entity property")
		if not Schema.valid_state(record.type,record.state): return _fail("Invalid entity values: "+record.id+" ("+record.type+")")
		if record.refs.size()!=Schema.refs(record.type).size(): return _fail("Missing object references")
		for field in record.refs:
			if not field in Schema.refs(record.type) or not record.refs[field] is String or record.refs[field].length()>256: return _fail("Invalid object reference")
		for key in record.meta:
			if not key in Schema.META: return _fail("Unlisted metadata")
			if key in ["final_boss","scenario_front"] and not record.meta[key] is bool: return _fail("Wrong metadata type")
			if key=="boss_phase" and (not record.meta[key] is int or not record.meta[key] in [1,2]): return _fail("Wrong boss phase")
			if key=="boss_title" and not record.meta[key] is String: return _fail("Wrong boss title")
	if is_instance_valid(entities.get("system:scenery_damage")) and not ids.has("system:scenery_damage"): return _fail("Missing scenery damage controller")
	if not snapshot.get("boss","") is String or (snapshot.get("boss","")!="" and not ids.has(snapshot.boss)): return _fail("Invalid boss reference")
	for record in snapshot.entities:
		if record.parent!="" and not ids.has(record.parent): return _fail("Missing entity parent")
		for ref_id in record.refs.values():
			if ref_id!="" and not ids.has(ref_id): return _fail("Missing referenced entity")
	return _validate_graph(snapshot,ids)

func _fixed_id(kind: String,point: Vector2) -> String:
	return "fixed:%s:%d:%d"%[kind,roundi(point.x),roundi(point.y)]

func _fixed_construction_plan(structure: Dictionary) -> Dictionary:
	var bunker=game.scenario_bunker
	var dome_id: String=str(game.dome.get_meta(ID_META,""))
	var panel_count: int=game.dome.ROOF_PANELS+game.dome.front_x_positions().size()
	var signature: Array=[structure.rooms,structure.excavation_depths,structure.flak_tier,game.flak_station.tier,structure.dome_available,game.dome.available,bunker.room_left,game.flak_station.gun_position,dome_id,panel_count]
	if signature==_construction_signature: return _construction_plan.duplicate()
	var planned := {}
	for index in range(structure.rooms):
		var floor_y: float=ScenarioRoomCatalog.floor_y(index)
		var kind: String="glass_furnace" if index==1 else "deep_station"
		var station_position:=Vector2(bunker.room_left+268,floor_y)
		planned[_fixed_id(kind,station_position)]={"type":kind,"parent":"","required":true,"position":station_position,"kind":"glass" if index==1 else "alloy" if index==2 else "ammo_press"}
	for index in range(mini(4,structure.rooms+1)):
		var floor_index: int=index if index<structure.excavation_depths else index-1
		var site_position:=Vector2(bunker.room_left+107,ScenarioRoomCatalog.floor_y(floor_index))
		planned["fixed:scenario_room_site:%d"%index]={"type":"scenario_room_site","parent":"","required":true,"position":site_position,"room_index":index}
	for index in range(structure.excavation_depths):
		var bounds:=Rect2(bunker.room_left+128,ScenarioRoomCatalog.floor_y(index)-144,480,144)
		var terrain_id:=_fixed_id("diggable_terrain",bounds.position)
		planned[terrain_id]={"type":"diggable_terrain","parent":"","required":true,"bounds":bounds}
		for row in 3:
			for col in 10:
				var cell:=Vector2i(col,row)
				var cell_id:=terrain_id+"/mine_block:%d:%d"%[col,row]
				planned[cell_id]={"type":"mine_block","parent":terrain_id,"required":false,"grid_cell":cell,"position":bounds.position+Vector2(cell)*48.0+Vector2(24,24)}
	if structure.flak_tier>0 and game.flak_station.tier==0:
		planned[_fixed_id("flak_turret",game.flak_station.gun_position)]={"type":"flak_turret","parent":"","required":true,"position":game.flak_station.gun_position}
	if structure.dome_available and not game.dome.available:
		for panel in panel_count:
			planned[dome_id+"/dome_segment:"+str(panel)]={"type":"dome_segment","parent":dome_id,"required":true}
	_construction_signature=signature
	_construction_plan=planned
	# Dynamic children are added by the current packet below. A shallow copy
	# protects this immutable constructor template without rebuilding earth IDs.
	return planned.duplicate()

func _validate_graph(snapshot: Dictionary,records: Dictionary) -> bool:
	# Predict only constructors actually invoked by _structure. No scene or
	# process state changes until all IDs, ownership and required objects agree.
	var structure: Dictionary=snapshot.structure
	var planned:=_fixed_construction_plan(structure)
	var bunker=game.scenario_bunker
	# Count current earth once, rather than scanning all records for each shaft.
	# This remains snapshot-local: mining and new excavation must never reuse an
	# earlier packet's count when validating construction against the live graph.
	var mine_counts: Dictionary = {}
	for id: String in records:
		var record: Dictionary = records[id]
		if record.type=="mine_block":
			mine_counts[record.parent]=int(mine_counts.get(record.parent,0))+1
	for index in range(structure.excavation_depths):
		var bounds:=Rect2(bunker.room_left+128,ScenarioRoomCatalog.floor_y(index)-144,480,144)
		var terrain_id:=_fixed_id("diggable_terrain",bounds.position)
		var remaining: int = int(mine_counts.get(terrain_id,0))
		var site: Dictionary=records.get("fixed:scenario_room_site:%d"%index,{})
		if not site.is_empty() and remaining>0:
			var state: Dictionary=site.state
			if not state.support_materials.is_empty() or state.support_work>0 or state.supported or state.built: return _fail("Construction precedes excavation")
	if structure.dome_available and not game.dome.available:
		var rounds_id: String=str(game.rounds.get_meta(ID_META,""))
		var phase: String=str(records.get(rounds_id,{}).get("state",{}).get("phase",""))
		if structure.wave<Balance.DOME_WAVE and not (structure.wave==Balance.DOME_WAVE-1 and phase=="salvage"): return _fail("Dome precedes unlock wave")
	for record in records.values():
		if record.type in Schema.DYNAMIC:
			if record.parent!="" or not record.id.begins_with("dynamic:") or not record.id.trim_prefix("dynamic:").is_valid_int(): return _fail("Invalid dynamic ownership")
			var numeric_id: String=record.id.trim_prefix("dynamic:")
			if numeric_id.to_int()<1 or numeric_id.to_int()>1000000000 or str(numeric_id.to_int())!=numeric_id: return _fail("Invalid dynamic ID")
			if record.type in ["enemy","boss_machine","ground_infantry"] and record.state.profile.has("ability"):
				planned[record.id+"/ground_machine_abilities:0"]={"type":"ground_machine_abilities","parent":record.id,"required":true}
			if record.type=="convoy_vehicle":
				for index in 4:
					planned[record.id+"/convoy_seat:"+str(index)]={"type":"convoy_seat","parent":record.id,"required":true,"role":["driver","gunner","passenger_left","passenger_right"][index]}
			if record.type=="field_defense" and record.state.kind=="sentry_kit":
				planned[record.id+"/turret:0"]={"type":"turret","parent":record.id,"required":true}
	for id: String in planned:
		if planned[id].required and not records.has(id): return _fail("Missing constructed entity")
	for id: String in entities:
		var node=entities[id]
		if not _alive(node) or records.has(id) or Schema.kind(node) in Schema.DYNAMIC or Schema.kind(node)=="mine_block": continue
		var parent_id: String=str(node.get_parent().get_meta(ID_META,""))
		if parent_id!="" and not records.has(parent_id): continue
		return _fail("Missing permanent entity")
	for record in records.values():
		var node=entities.get(record.id)
		if _alive(node):
			if record.parent!=str(node.get_parent().get_meta(ID_META,"")): return _fail("Entity parent changed")
			if record.type=="player" and (record.state.player_id!=node.player_id or record.state.character_id!=node.character_id): return _fail("Player identity changed")
			if record.state.has("kind") and "kind" in node and record.state.kind!=node.kind: return _fail("Entity kind changed")
			if record.type=="perimeter_site":
				for field in ["role","side","slot_index"]:
					if record.state[field]!=node.get(field): return _fail("Perimeter identity changed")
			if record.type=="diggable_terrain" and record.state.bounds!=node.bounds: return _fail("Terrain bounds changed")
			# The hand weapon is a child whose local pose follows facing/crouch.
			if node is Node2D and not record.type in SMOOTH_TYPES and not record.type in Schema.DYNAMIC and record.type not in ["worker_weapon","convoy_seat","scenario_room_site"] and record.state.get("position")!=node.position: return _fail("Fixed entity moved: "+record.type)
		elif not record.type in Schema.DYNAMIC:
			if not planned.has(record.id) or planned[record.id].type!=record.type or planned[record.id].parent!=record.parent: return _fail("Unknown fixed entity")
			if record.type=="mine_block" and _alive(entities.get(record.parent)): return _fail("Excavated earth cannot return")
		if planned.has(record.id):
			for field in ["position","kind","room_index","role","bounds","grid_cell"]:
				if planned[record.id].has(field) and record.state.get(field)!=planned[record.id][field]: return _fail("Constructed entity changed")
		if record.type=="convoy_vehicle":
			if record.state.road_bounds.x<snapshot.game.world_left or record.state.road_bounds.y>snapshot.game.world_right: return _fail("Convoy lane outside declared world")
		if record.type=="convoy_seat":
			if not records.get(record.parent,{}).get("type")=="convoy_vehicle": return _fail("Seat has no vehicle owner")
			var ordinal := ["driver","gunner","passenger_left","passenger_right"].find(record.state.role)
			if record.id!=record.parent+"/convoy_seat:"+str(ordinal): return _fail("Seat role does not match stable ID")
			var occupant: String=record.refs.occupant
			if not occupant.is_empty():
				if records[occupant].type!="player" or records[occupant].refs.mounted_turret!=record.id: return _fail("Seat occupant disagrees with player mount")
		if record.type=="player" and not str(record.refs.mounted_turret).is_empty():
			var mount: Dictionary=records[record.refs.mounted_turret]
			if mount.type=="convoy_seat" and mount.refs.occupant!=record.id: return _fail("Player claims another convoy seat")
		if record.type=="worker_weapon":
			var research: Dictionary=records.get("system:upgrade_system",{}).get("state",{}).get("owned",{})
			if not Schema.valid_weapon_research(record.state,research): return _fail("Weapon ammunition exceeds researched capacity")
		if record.type=="worker_weapon" and record.state.weapon_kind in CampaignCatalog.EPIC_WEAPONS:
			var campaign: Dictionary=snapshot.get("expedition",{}).get("checkpoint",{})
			if not campaign.get("expedition",{}).get("epic_weapons",[]).has(record.state.weapon_kind): return _fail("Unearned equipped epic weapon")
		if record.type=="ground_machine_abilities":
			var owner_record: Dictionary=records.get(record.parent,{})
			if not owner_record.get("type") in ["enemy","boss_machine","ground_infantry"] or record.state.mode!=owner_record.get("state",{}).get("profile",{}).get("ability",""):
				return _fail("Ability does not match machine chassis")
		if record.type=="round_controller" and record.state.wave!=structure.wave: return _fail("Conflicting wave fields")
		if record.type=="round_controller" and record.state.player_count!=snapshot.game.player_count: return _fail("Conflicting player counts")
		if record.type=="scenario_room_site":
			if record.state.built!=(record.state.room_index<structure.rooms): return _fail("Conflicting room construction")
			if record.state.room_index>=structure.excavation_depths and (not record.state.support_materials.is_empty() or record.state.support_work>0 or record.state.supported): return _fail("Construction has no opened excavation")
		if record.type in ["flak_station","flak_turret"] and record.state.tier!=structure.flak_tier: return _fail("Conflicting flak construction")
		if record.type=="flak_station" and record.state.built!=(structure.flak_tier>0): return _fail("Conflicting flak availability")
		if record.type=="dome_controller" and record.state.available!=structure.dome_available: return _fail("Conflicting dome construction")
		for field in record.refs:
			var target_id: String=record.refs[field]
			if target_id.is_empty(): continue
			var target_kind: String=records[target_id].type
			if not _reference_kind(record.type,field,target_kind): return _fail("Wrong referenced entity type")
	var boss_id: String=snapshot.get("boss","")
	if boss_id!="" and not records[boss_id].type in ["enemy","boss_machine","air_machine","ground_infantry"]: return _fail("Boss is not an enemy")
	return true

func _reference_kind(kind: String,field: String,target: String) -> bool:
	match field:
		"mounted_turret": return target in ["turret","flak_turret","convoy_seat"]
		"turret": return target in ["turret","flak_turret"]
		"occupant","builder","last_worker","credit_worker","worker_target": return target=="player"
		"medical": return target=="worker_medical"
		"aid_target": return target=="player"
		"_healer": return target in ["player","field_medic"]
		"tracking_target": return target in ["enemy","boss_machine","ground_infantry","air_machine"] if kind=="perimeter_site" else target=="air_machine"
		"repair_target": return target=="dome_segment"
		"source": return target in ["turret","flak_turret","player","perimeter_site","convoy_vehicle"]
		"target":
			if kind=="field_medic": return target in ["player","core"]
	return target in ["convoy_vehicle","convoy_seat","perimeter_site","player","medical_aid_target","wall","core","dome_segment","field_defense","ground_infantry","enemy","boss_machine","air_machine","station","deep_station","glass_furnace","supply","convoy_supply","resource_pickup","mine_block","scenario_room_site","flak_station","dome_controller","field_workshop","turret","flak_turret"]

func _property_types_for(kind: String) -> void:
	if _property_types.has(kind): return
	var script: Script=load("res://scripts/"+kind+".gd")
	var types := {}
	for property in script.get_script_property_list(): types[property.name]=int(property.type)
	_property_types[kind]=types
	_spatial_types[kind]=ClassDB.is_parent_class(script.get_instance_base_type(),"Node2D")
	var allowed: Dictionary = {}
	var required := PackedStringArray()
	for field: String in Schema.fields(kind):
		# Resolve script/common types once per chassis rather than for every
		# field in every snapshot. A declared Variant retains its TYPE_NIL rule.
		allowed[field]=int(COMMON_PROPERTY_TYPES.get(field,types.get(field,-1)))
		if types.has(field): required.append(field)
	if _spatial_types[kind]:
		for field: String in SPATIAL_FIELDS: allowed[field]=COMMON_PROPERTY_TYPES[field]
	_allowed_fields[kind]=allowed
	_required_fields[kind]=required

func apply(snapshot: Dictionary, wire_validated: bool=false) -> bool:
	if not is_instance_valid(game): return _fail("No bound game")
	if not _validate(snapshot,wire_validated): return false
	_signal_changes.clear()
	if snapshot.has("expedition"): game.expedition.apply_state(snapshot.expedition)
	if not client: freeze_client()
	var phase: String=game.rounds.phase
	for record in snapshot.entities:
		if record.type=="round_controller": phase=record.state.phase
	if not _structure(snapshot.structure,phase): return false
	_scan(game)
	var seen := {}
	# Parents are created before children. All construction is through local,
	# fixed factories; a packet can never load an arbitrary scene or script.
	var pending: Array=snapshot.entities.duplicate()
	var static_changes: Dictionary = {}
	for pass_index in 8:
		if pending.is_empty(): break
		var unresolved: Array=[]
		for record in pending:
			var id: String=record.id
			var node = entities.get(id)
			if not is_instance_valid(node):
				var parent: Node=game if record.parent=="" else entities.get(record.parent)
				if not is_instance_valid(parent): unresolved.append(record); continue
				node=_spawn(record,parent)
				if node==null: return _fail("Entity cannot be reconstructed: "+id)
				entities[id]=node
				_scan(node)
			seen[id]=true
			static_changes[id]=_apply_fields(node,record.state)
			if record.type=="field_medic": node.status_label=LocaleText.message_text(record.status_message)
			for key in record.meta: node.set_meta(key,record.meta[key])
		pending=unresolved
	if not pending.is_empty(): return _fail("Unresolved entity parents")
	# Resolve mounts, medical partners and damage ownership after every ID exists.
	for record in snapshot.entities:
		var node: Node=entities[record.id]
		for field in record.refs:
			node.set(field,entities.get(record.refs[field]) if record.refs[field]!="" else null)
		if not _applied or bool(static_changes.get(record.id,true)) or not record.type in ["mine_block","supply","resource_pickup"]:
			_refresh_visual(node,record.type)
	_sync_mounted_players()
	if is_instance_valid(game.get("combat_gore")):
		for player in game.players: game.combat_gore.sync_actor(player)
	var terrain_changed := false
	for id in entities.keys():
		var node = entities[id]
		if not seen.has(id):
			if is_instance_valid(node) and not node.is_queued_for_deletion():
				terrain_changed = terrain_changed or Schema.kind(node)=="mine_block"
				if Schema.kind(node) in ["enemy","boss_machine","air_machine","ground_infantry"] and node.has_method("spawn_motion_wreck"):
					node.spawn_motion_wreck()
				node.get_parent().remove_child(node)
				node.queue_free()
			entities.erase(id)
			_targets.erase(id)
	# Removed earth changes exposed faces even though replica simulation is frozen.
	if terrain_changed or not _applied:
		for field in game.scenario_bunker.fields:
			for block in field.blocks:
				if _alive(block): block.refresh_neighbors.call_deferred()
	game.scenario_bunker.queue_redraw()
	_apply_fields(game,snapshot.game)
	game.notice=LocaleText.message_text(snapshot.notice_message)
	if snapshot.has("story"): game.story.apply_state(snapshot.story,not _applied)
	if snapshot.has("storm") and is_instance_valid(game.weather.get("storm_events")): game.weather.storm_events.apply_state(snapshot.storm,not _applied)
	var boss_node=entities.get(snapshot.get("boss",""))
	game.combat_events._boss=weakref(boss_node) if is_instance_valid(boss_node) else null
	game.update_scenario_camera()
	if game.rounds.phase in ["victory","defeat"]:
		game.hud.overlay="campaign_victory" if game.rounds.phase=="victory" and game.campaign.active and CampaignCatalog.all_complete(game.campaign.completed) else game.rounds.phase
	for node in entities.values():
		if is_instance_valid(node) and (node.is_processing() or node.is_physics_processing()): _freeze(node)
	for node in _signal_changes:
		if is_instance_valid(node) and node.has_signal("changed"): node.emit_signal("changed")
	_signal_changes.clear()
	_applied=true
	last_error=""
	return true

func _structure(state: Dictionary,phase: String) -> bool:
	var bunker=game.scenario_bunker
	if state.rooms<bunker.open_depths: return _fail("Room structure cannot shrink inside a match")
	game.rounds.wave=state.wave
	game.rounds.phase=phase
	game.view_stage=state.view_stage
	bunker.on_view_stage(state.view_stage)
	while bunker.open_depths<int(state.rooms):
		var index: int=bunker.open_depths
		if not bunker.prepare_excavation(index): return _fail("Excavation reconstruction failed")
		var site=bunker.modules[index]
		# Geometry replay must never mine, pay workers or emit resource/XP events.
		var field=bunker.fields[index]
		for block in field.blocks.duplicate():
			if is_instance_valid(block):
				block.get_parent().remove_child(block)
				block.queue_free()
		field._cleared_emitted=true
		site.support_materials=site.support_cost()
		site.support_work=ScenarioRoomCatalog.SUPPORT_TIME
		site.supported=true
		site.materials=site.room_cost()
		site.construction=ScenarioRoomCatalog.BUILD_TIME
		site.curing=true
		site.curing_remaining=0.0
		if not bunker.complete_room(index): return _fail("Paid room reconstruction failed")
		site.built=true
		site.curing=false
		site.remove_from_group("interactables")
	while bunker.excavation_depths<int(state.excavation_depths):
		if not bunker.prepare_excavation(bunker.excavation_depths): return _fail("Next excavation reconstruction failed")
	# Reuse the real structural constructors, then overwrite their transient
	# starting HP/ammo with the authoritative entity state below.
	if int(state.flak_tier)>game.flak_station.tier:
		var old_notice: String=game.notice
		var old_notice_time: float=game.notice_time
		var audio=game.audio
		game.audio=null
		while game.flak_station.tier<int(state.flak_tier):
			game.flak_station._complete()
		game.audio=audio
		game.notice=old_notice
		game.notice_time=old_notice_time
	if bool(state.get("dome_available",false)) and not game.dome.available:
		game.dome.unlock()
	game.update_scenario_camera()
	return true

func _spawn(record: Dictionary,parent: Node) -> Node:
	if not record.type in Schema.DYNAMIC: return null
	var node: Node=Schema.factory(record.type)
	if node==null: return null
	node.set_meta(ID_META,record.id)
	if "game" in node: node.set("game",game)
	if record.type=="convoy_vehicle":
		node.expedition=game.expedition
		game.expedition.vehicle=node
	for field in ["kind","wave","elite","squad_slot","attack_direction","scenario_lanes","scenario_floor","position"]:
		if record.state.has(field) and field in node: node.set(field,record.state[field])
	parent.add_child(node)
	_freeze(node)
	return node

func _apply_fields(node: Node,state: Dictionary) -> bool:
	var changed := false
	for field in state:
		if not field in node: continue
		var value = state[field]
		if field=="transfer" and value is Dictionary:
			var mapped := {}
			for key in value:
				var local_key = key
				if key is String and key.begins_with("@player:"):
					var player=entities.get(key.substr(1))
					if is_instance_valid(player): local_key=player.get_instance_id()
				mapped[local_key]=value[key]
			value=mapped
		if node.get(field)==value:
			if field=="position": _targets.erase(str(node.get_meta(ID_META,"")))
			continue
		changed=true
		# Interpolate only presentation transforms, never physics or damage.
		if field=="position" and _applied and Schema.kind(node) in SMOOTH_TYPES and node.position.distance_to(value)<120.0:
			_targets[str(node.get_meta(ID_META))]={"from":node.position,"to":value,"age":0.0}
		else:
			if field=="position": _targets.erase(str(node.get_meta(ID_META,"")))
			node.set(field,value.duplicate(true) if value is Array or value is Dictionary else value)
	if changed and node.has_signal("changed") and not _signal_changes.has(node): _signal_changes.append(node)
	return changed

func _refresh_visual(node: Node,kind: String) -> void:
	if node is CanvasItem: node.queue_redraw()
	match kind:
		"scenery_damage":
			if is_instance_valid(node.props) and is_instance_valid(node.props.get("debris")) and node.props.debris.has_method("sync_replica"):
				node.props.debris.sync_replica(not _applied)
		"enemy","boss_machine","air_machine","ground_infantry":
			node._pose_parts()
			var retained_weapon: bool=node.has_method("request_weapon_redraw")
			for child in node.get_children():
				if retained_weapon and child==node.weapon_part: continue
				if child is CanvasItem: child.queue_redraw()
			if retained_weapon: node.request_weapon_redraw()
		"turret","flak_turret":
			node.pose_barrel()
			if is_instance_valid(node.barrel): node.barrel.queue_redraw()
		"perimeter_site","convoy_vehicle": node.sync_replica()
		"convoy_seat": node.sync_operator()
		"wall":
			if is_instance_valid(node.collider): node.collider.set_deferred("disabled",not node.is_blocking())
		"dome_segment":
			node.update_service_port(node.service_port)
			node._update_collision()
		"scenario_room_site":
			if node.built: node.remove_from_group("interactables")
		"worker_weapon": node.queue_redraw()

func freeze_client() -> void:
	client=true
	if not is_instance_valid(game): return
	game.set_process(false)
	game.set_physics_process(false)
	_scan(game)
	for node in entities.values():
		if is_instance_valid(node): _freeze(node)
	if is_instance_valid(game.get("environment_growth")):
		game.environment_growth.set_process(false)

func _freeze(node: Node) -> void:
	if Schema.kind(node)=="scenery_damage": node.replica_only=true
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)

func interpolate(delta: float) -> void:
	if not client or not is_instance_valid(game): return
	for id in _targets.keys():
		var node=entities.get(id)
		if not is_instance_valid(node):
			_targets.erase(id)
			continue
		var target: Dictionary=_targets[id]
		target.age=minf(.05,float(target.age)+maxf(0,delta))
		node.position=Vector2(target.from).lerp(target.to,float(target.age)/.05)
		if target.age>=.05: _targets.erase(id)
	for node in game.get_tree().get_nodes_in_group("convoy_vehicles"):
		if node.game==game: node.sync_replica()
	_sync_mounted_players()
	# Camera preferences and follow targets belong to this participant.

func _sync_mounted_players() -> void:
	# A seat is a rigid attachment. Interpolating a side change separately from
	# the already updated barrel makes the operator's hands leave the controls.
	for worker in game.players:
		if not is_instance_valid(worker) or not is_instance_valid(worker.mounted_turret): continue
		var mount: Node2D = worker.mounted_turret
		if not mount.has_method("operator_position"): continue
		_targets.erase(str(worker.get_meta(ID_META,"")))
		worker.global_position = mount.operator_position()
