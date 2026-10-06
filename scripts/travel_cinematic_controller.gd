extends Node
## Shared presentation derives from the existing authoritative ignition phase.
## No separate pause, network timer, campaign flag or new enemy is introduced.
const Catalog := preload("res://scripts/travel_cinematic_catalog.gd")
const Journey := preload("res://scripts/convoy_journey.gd")
var game: Node
var active: bool:
	get: return not context().is_empty() and elapsed()<float(context().duration)
var _context: Dictionary = {}
var _context_key := ""
var _observed_vehicle := 0
var _was_blocking := false

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS

func source_vehicle() -> Node2D:
	if not is_instance_valid(game) or game.get("started")!=true: return null
	var expedition=game.get("expedition")
	if not is_instance_valid(expedition) or expedition.get("road_open")!=true or expedition.get("stage")!="travel" or expedition.get("stop_done")==true: return null
	var truck=expedition.get("vehicle")
	if not is_instance_valid(truck) or not truck is Node2D or truck.is_queued_for_deletion() or truck.get("destroyed")==true or truck.get("game")!=game: return null
	if truck.journey_state.phase!="starting" or absf(truck.position.x-float(expedition.ROAD_START))>1.0: return null
	return truck

func context() -> Dictionary:
	var truck:=source_vehicle()
	if truck==null: return {}
	var driver=truck.driver_seat.occupant
	if not is_instance_valid(driver): return {}
	var crew: Array=[]
	for worker in game.players:
		if is_instance_valid(worker) and not worker.is_queued_for_deletion(): crew.append(str(worker.character_id))
	var destination: String=str(game.expedition.state.pending_node)
	var key: String="%s|%s|%s|%s" % [destination,str(driver.character_id),str(crew),LocaleText.current_locale()]
	if key!=_context_key:
		_context_key=key
		_context=Catalog.context(destination,str(driver.character_id),crew)
	return _context

func elapsed() -> float:
	var truck:=source_vehicle()
	return float(truck.journey_state.phase_time) if truck!=null else 0.0

func startup_duration() -> float:
	var scene:=context()
	return Journey.START_TIME+(float(scene.duration) if not scene.is_empty() else 0.0)

func blocks_gameplay() -> bool:
	# Include the existing final ignition interval after skip/visual completion.
	# Hot input paths check only cheap shared phase/route data, never voice loads.
	return source_vehicle()!=null and Catalog.ROUTES.has(str(game.expedition.state.pending_node))

func is_presented() -> bool:
	if not active or not is_inside_tree() or get_tree().paused: return false
	var room=game.get("network")
	if is_instance_valid(room) and room.active and (room._loading or room.state!="playing"): return false
	var hud=game.get("hud")
	return is_instance_valid(hud) and str(hud.overlay).is_empty()

func can_skip() -> bool:
	var room=game.get("network")
	return is_presented() and elapsed()>=Catalog.MIN_SKIP_DELAY and (not is_instance_valid(room) or not room.active or (room.is_host and room.state=="playing"))

func skip(player_id: int=1) -> bool:
	if player_id!=1 or not can_skip() or not game.expedition.authoritative(): return false
	_release_actions()
	# The normal host physics path still performs ignition and enables driving.
	source_vehicle().journey_state.phase_time=float(context().duration)
	return true

func request_skip() -> void:
	if can_skip(): game.expedition.request("cinematic_skip")

func _release_actions() -> void:
	for action: StringName in InputMap.get_actions():
		if str(action).begins_with("p1_") or str(action).begins_with("p2_") or str(action).begins_with("p3_") or str(action).begins_with("p4_"): Input.action_release(action)

func _process(_delta: float) -> void:
	var truck:=source_vehicle()
	var blocking:=blocks_gameplay()
	if blocking and truck.get_instance_id()!=_observed_vehicle:
		_observed_vehicle=truck.get_instance_id()
		_release_actions()
		var hud=game.get("hud")
		if is_instance_valid(hud) and is_instance_valid(hud.chat_panel): hud.chat_panel.close()
	if blocking or _was_blocking!=blocking: _release_actions()
	_was_blocking=blocking

func _input(event: InputEvent) -> void:
	if not is_presented(): return
	if event is InputEventKey and event.physical_keycode in [KEY_F3,KEY_F11]:
		if event.pressed and not event.echo and event.physical_keycode==KEY_F3:
			game.weather.set_reduced_effects(not game.weather.reduced_effects)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		_release_actions()
		return
	get_viewport().set_input_as_handled()
	if not event.is_echo() and (event.is_action_pressed("start") or event.is_action_pressed("ui_accept") or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")): request_skip()
	_release_actions()
