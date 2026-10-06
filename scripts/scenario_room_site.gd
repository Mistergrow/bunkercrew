class_name ScenarioRoomSite
extends Node2D
const EquipmentArt := preload("res://scripts/support_equipment_art.gd")
## Excavate, install supports, then fit out the room. Each stage owns its payment.
var game: Node
var bunker: Node
var room_index := 0
var materials: Dictionary = {}
var support_materials: Dictionary = {}
var transfer: Dictionary = {}
var support_work := 0.0
var supported := false
var construction := 0.0
var curing_remaining := 0.0
var built := false
var curing := false

func _ready() -> void:
	add_to_group("interactables")
	add_to_group("scenario_room_sites")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 5

func spec() -> Dictionary:
	return ScenarioRoomCatalog.spec(room_index)

func wave_ready() -> bool:
	var wave := int(game.rounds.wave) if is_instance_valid(game) and is_instance_valid(game.get("rounds")) else 1
	return wave >= int(spec().wave)

func can_interact(_player) -> bool:
	return not built

func interaction_point() -> Vector2:
	return global_position - Vector2(0,26)

func excavated() -> bool:
	if not is_instance_valid(bunker):
		return false
	var fields: Variant = bunker.get("fields")
	if not fields is Array or room_index < 0 or room_index >= fields.size():
		return false
	var field: Variant = fields[room_index]
	return is_instance_valid(field) and field.has_method("is_cleared") and field.is_cleared()

func support_cost() -> Dictionary:
	return ScenarioRoomCatalog.SUPPORT_COST.duplicate()

func room_cost() -> Dictionary:
	# Supports are part of the advertised total, never an additional surcharge.
	var cost: Dictionary = spec().cost.duplicate()
	for kind: String in support_cost():
		cost[kind] = maxi(0,int(cost.get(kind,0))-int(support_cost()[kind]))
		if int(cost[kind]) == 0:
			cost.erase(kind)
	return cost

func support_complete_materials() -> bool:
	return _has_materials(support_materials,support_cost())

func complete_materials() -> bool:
	return _has_materials(materials,room_cost())

func _has_materials(buffer: Dictionary,cost: Dictionary) -> bool:
	for kind: String in cost:
		if int(buffer.get(kind,0)) < int(cost[kind]):
			return false
	return true

func prompt(_player) -> String:
	var data := spec()
	if built:
		return LocaleText.format("%s · AUSGEBAUT", data.title)
	if curing:
		return LocaleText.format("%s · Beton härtet %.1f s · Kern +%d LP", [data.title,curing_remaining,int(data.core_bonus)])
	if not wave_ready():
		return LocaleText.format("%s · Bauplan ab Welle %d\n%s", [data.title,int(data.wave),data.benefit])
	if not excavated():
		return LocaleText.format("%s · AUSHUB\nZuerst Erde und Fels abtragen · dabei Rohstoffe bergen",data.title)
	if not supported:
		if support_complete_materials():
			return LocaleText.format("%s · ABSTÜTZEN\nHalten: Stahlstützen montieren",data.title)
		return LocaleText.format("%s · ABSTÜTZEN\n%s · halten: Stahl für die Stützen einbauen",[data.title,_material_amounts(support_materials,support_cost())])
	if complete_materials():
		return LocaleText.format("%s · RAUMBAU\nHalten: Wände, Boden und Einrichtung montieren",data.title)
	return LocaleText.format("%s · RAUMBAU\n%s · halten: Material einbauen",[data.title,_material_amounts(materials,room_cost())])

func _material_amounts(buffer: Dictionary,cost: Dictionary) -> String:
	var amounts := PackedStringArray()
	for kind: String in cost:
		amounts.append(LocaleText.format("%s %d/%d",[Balance.RESOURCE_NAMES[kind],int(buffer.get(kind,0)),int(cost[kind])]))
	return " + ".join(amounts)

func interaction_progress(player) -> float:
	if built:
		return 1.0
	if curing:
		return 1.0-curing_remaining/ScenarioRoomCatalog.CURE_TIME
	if not excavated() or not wave_ready():
		return 0.0
	if not supported:
		if support_complete_materials():
			return support_work/ScenarioRoomCatalog.SUPPORT_TIME
		return _transfer_progress(player)
	if complete_materials():
		return construction/ScenarioRoomCatalog.BUILD_TIME
	return _transfer_progress(player)

func _transfer_progress(player) -> float:
	return float(transfer.get(player.get_instance_id(),0.0))/Balance.TRANSFER_TIME if is_instance_valid(player) else 0.0

func interact(player,delta: float) -> void:
	if not is_finite(delta) or delta <= 0 or not is_instance_valid(player) or not can_interact(player) or curing or not wave_ready() or not excavated():
		return
	if player.has_method("can_act") and not player.can_act():
		return
	if not supported:
		if support_complete_materials():
			support_work = minf(ScenarioRoomCatalog.SUPPORT_TIME,support_work+delta)
			if support_work >= ScenarioRoomCatalog.SUPPORT_TIME:
				supported = true
				transfer.clear()
				preload("res://scripts/spatial_sound.gd").emit(game,"build",global_position)
		else:
			_transfer_material(player,delta,support_cost(),support_materials)
		_refresh_visuals()
		return
	if complete_materials():
		construction = minf(ScenarioRoomCatalog.BUILD_TIME,construction+delta)
		if construction >= ScenarioRoomCatalog.BUILD_TIME:
			curing = true
			curing_remaining = ScenarioRoomCatalog.CURE_TIME
			preload("res://scripts/spatial_sound.gd").emit(game,"build",global_position)
		_refresh_visuals()
		return
	_transfer_material(player,delta,room_cost(),materials)
	_refresh_visuals()

func _transfer_material(player,delta: float,cost: Dictionary,buffer: Dictionary) -> void:
	var choices: Array = cost.keys()
	if player.has_method("selected_material"):
		var selected: String = player.selected_material()
		if selected in choices:
			choices.erase(selected)
			choices.push_front(selected)
	var needed := ""
	for kind: String in choices:
		if int(buffer.get(kind,0)) < int(cost[kind]) and int(player.inventory.get(kind,0)) > 0:
			needed = kind
			break
	if needed.is_empty():
		return
	var id: int = player.get_instance_id()
	transfer[id] = minf(Balance.TRANSFER_TIME,float(transfer.get(id,0.0))+delta)
	if float(transfer[id]) >= Balance.TRANSFER_TIME:
		transfer[id] = 0.0
		if player.take_item(needed,1):
			buffer[needed] = int(buffer.get(needed,0))+1
			preload("res://scripts/spatial_sound.gd").emit(game,"build",global_position)

func _refresh_visuals() -> void:
	queue_redraw()
	if is_instance_valid(bunker):
		bunker.queue_redraw()

func _process(delta: float) -> void:
	if not curing or built or not is_finite(delta) or delta <= 0:
		return
	if not supported or not excavated():
		return
	curing_remaining = maxf(0.0,curing_remaining-delta)
	if curing_remaining <= 0.0:
		# The controller also rejects duplicate/out-of-order completions. This
		# protects both floor geometry and core bonuses from two-worker races.
		if bunker.complete_room(room_index):
			built = true
			curing = false
			remove_from_group("interactables")
			preload("res://scripts/spatial_sound.gd").emit(game,"produce",global_position)
			game.notify(LocaleText.format("%s · fertig · %s", [spec().title,spec().benefit]))
			game.fx(global_position-Vector2(0,32),Art.AMBER,15)
	_refresh_visuals()

func _draw() -> void:
	if built:
		return
	# A fixed junction box attached to the shaft pier, not a floating menu.
	var tint := Color("aec58c") if supported else Art.AMBER if wave_ready() and excavated() else Color("72786d")
	EquipmentArt.construction_panel(self,tint,supported)
	if curing:
		Art.bar(self,Rect2(-19,-48,38,3),interaction_progress(null),Art.AMBER)
	elif support_work > 0.0 and not supported:
		Art.bar(self,Rect2(-19,-48,38,3),support_work/ScenarioRoomCatalog.SUPPORT_TIME,tint)
	elif construction > 0.0:
		Art.bar(self,Rect2(-19,-48,38,3),construction/ScenarioRoomCatalog.BUILD_TIME,tint)
