extends RefCounted
## Each online participant uses P1's keyboard/mouse or the first controller.
## Local co-op retains keyboard P1 and controller P2. The host reads
## the guest's validated input state directly; it never mutates global Input.

const ACTIONS := ["left","right","up","down","jump","interact","drop","reload","cycle_material","cycle_target","cycle_weapon","craft_next","deploy","fire","aim_up","aim_down"]
const MENU_GUARDED_ACTIONS := ["jump", "interact", "drop", "reload", "cycle_material", "cycle_target", "cycle_weapon", "craft_next", "deploy", "fire"]

static func quarantine_menu_inputs(game) -> void:
	if not is_instance_valid(game): return
	var guarded: Dictionary = game.get_meta("menu_guarded_inputs", {})
	# A release completed inside a paused modal cannot be observed by workers.
	# Retire that old hold before accepting a new press after the modal closes.
	# The current release still stays guarded through its resumed physics tick.
	for key: String in guarded.keys():
		if not InputMap.has_action(key) or (not Input.is_action_pressed(key) and not Input.is_action_just_released(key)):
			guarded.erase(key)
	for prefix: String in ["p1_", "p2_", "p3_", "p4_", "primary_pad_"]:
		for action: String in MENU_GUARDED_ACTIONS:
			var key := prefix + action
			if InputMap.has_action(key) and Input.is_action_pressed(key): guarded[key] = [-1, -1]
	game.set_meta("menu_guarded_inputs", guarded)

static func _key_allowed(game, key: String) -> bool:
	if not is_instance_valid(game) or not game.has_meta("menu_guarded_inputs"): return true
	var guarded: Dictionary = game.get_meta("menu_guarded_inputs")
	if not guarded.has(key): return true
	if Input.is_action_pressed(key):
		guarded[key] = [-1, -1]
		return false
	var released: Array = guarded[key]
	if int(released[0]) < 0:
		guarded[key] = [Engine.get_process_frames(), Engine.get_physics_frames()]
		return false
	# Keep both the release event and the first resumed physics tick neutral.
	if Engine.get_process_frames() <= int(released[0]) or Engine.get_physics_frames() <= int(released[1]): return false
	guarded.erase(key)
	return true

static func session(worker):
	if not is_instance_valid(worker) or not "game" in worker:
		return null
	return for_game(worker.game)

static func for_game(game):
	if not is_instance_valid(game) or not "network" in game:
		return null
	var network = game.network
	return network if is_instance_valid(network) and network.active else null

static func _blocked(game) -> bool:
	if not is_instance_valid(game) or not "hud" in game or not is_instance_valid(game.hud):
		return false
	if game.hud.has_method("blocks_gameplay_input"):
		return game.hud.blocks_gameplay_input()
	return not str(game.hud.overlay).is_empty()

static func sample_local(game) -> Dictionary:
	var frame := {"held":{},"pressed":[],"released":[],"aim":[0.0,0.0],"mouse":true}
	if game is Node2D:
		var aim: Vector2 = game.get_global_mouse_position()
		frame.aim = [aim.x,aim.y]
	if _blocked(game):
		return frame
	frame.mouse = _primary_mouse_aim(game)
	for action: String in ACTIONS:
		for key: String in ["p1_"+action, "primary_pad_"+action]:
			if not InputMap.has_action(key) or not _key_allowed(game, key): continue
			var input_strength := Input.get_action_strength(key)
			if input_strength>0.0: frame.held[action] = maxf(float(frame.held.get(action, 0.0)), input_strength)
			if Input.is_action_just_pressed(key) and not action in frame.pressed: frame.pressed.append(action)
			if Input.is_action_just_released(key) and not action in frame.released: frame.released.append(action)
		if float(frame.held.get(action, 0.0)) > 0.0: frame.released.erase(action)
	return frame

static func _remote(worker) -> Dictionary:
	var network = session(worker)
	if network != null and int(worker.player_id)!=int(network.local_player_id):
		return network.remote_input_for(int(worker.player_id)) if network.is_host and network.has_method("remote_input_for") else (network.remote_input if network.is_host else {})
	return {}

static func _uses_remote(worker) -> bool:
	var network = session(worker)
	return network != null and int(worker.player_id)!=int(network.local_player_id)

static func _key(worker,action: String) -> String:
	return "p1_"+action if session(worker)!=null else worker.action(action)

static func primary_controller_enabled(game) -> bool:
	if for_game(game) != null: return true
	return is_instance_valid(game) and "players" in game and game.players.size() == 1

static func _local_keys(worker, action: String) -> Array[String]:
	var keys: Array[String] = [_key(worker, action)]
	if (session(worker) != null or int(worker.player_id) == 1) and primary_controller_enabled(worker.game):
		keys.append("primary_pad_" + action)
	return keys

static func _primary_mouse_aim(game) -> bool:
	if not is_instance_valid(game): return true
	var mouse := bool(game.get_meta("primary_mouse_aim", true))
	if game is Node2D:
		# World coordinates also change while the camera follows or zooms.
		# Input-device selection follows the screen pointer; aim remains global.
		var current: Vector2 = game.get_viewport().get_mouse_position()
		var previous: Vector2 = game.get_meta("primary_mouse_position", current)
		if current.distance_squared_to(previous) > 1.0: mouse = true
		game.set_meta("primary_mouse_position", current)
	for action: String in ACTIONS:
		if InputMap.has_action("p1_" + action) and Input.get_action_strength("p1_" + action) > 0.0: mouse = true
	for action: String in ACTIONS:
		if InputMap.has_action("primary_pad_" + action) and Input.get_action_strength("primary_pad_" + action) > 0.0: mouse = false
	game.set_meta("primary_mouse_aim", mouse)
	return mouse

static func strength(worker,action: String) -> float:
	if _cinematic_blocks(worker): return 0.0
	if _uses_remote(worker):
		var value = _remote(worker).get("held",{}).get(action,0.0)
		return clampf(float(value),0.0,1.0)
	if _blocked(worker.game):
		return 0.0
	var amount := 0.0
	for key: String in _local_keys(worker, action):
		if InputMap.has_action(key) and _key_allowed(worker.game, key): amount = maxf(amount, Input.get_action_strength(key))
	return amount

static func is_pressed(worker,action: String) -> bool:
	return strength(worker,action)>0.0

static func just_pressed(worker,action: String) -> bool:
	if _cinematic_blocks(worker): return false
	if _uses_remote(worker):
		return action in _remote(worker).get("pressed",[])
	if _blocked(worker.game):
		return false
	for key: String in _local_keys(worker, action):
		if InputMap.has_action(key) and _key_allowed(worker.game, key) and Input.is_action_just_pressed(key): return true
	return false

static func just_released(worker,action: String) -> bool:
	if _cinematic_blocks(worker): return false
	if _uses_remote(worker):
		return action in _remote(worker).get("released",[])
	if _blocked(worker.game):
		return false
	if strength(worker, action) > 0.0: return false
	for key: String in _local_keys(worker, action):
		if InputMap.has_action(key) and _key_allowed(worker.game, key) and Input.is_action_just_released(key): return true
	return false

static func axis(worker,negative: String,positive: String) -> float:
	return strength(worker,positive)-strength(worker,negative)

static func _cinematic_blocks(worker) -> bool:
	if not is_instance_valid(worker) or not "game" in worker or not is_instance_valid(worker.game): return false
	var cinematic=worker.game.get("travel_cinematic")
	return is_instance_valid(cinematic) and cinematic.blocks_gameplay()

static func mouse_aim(worker) -> bool:
	if _cinematic_blocks(worker): return false
	if _uses_remote(worker):
		return bool(_remote(worker).get("mouse",true))
	if session(worker) != null or (int(worker.player_id) == 1 and primary_controller_enabled(worker.game)): return _primary_mouse_aim(worker.game)
	return int(worker.player_id)==1

static func aim_position(worker) -> Vector2:
	if _uses_remote(worker):
		var point = _remote(worker).get("aim",[0.0,0.0])
		if point is Vector2:
			return point
		if point is Array and point.size()==2:
			return Vector2(float(point[0]),float(point[1]))
		return worker.global_position+Vector2(float(worker.facing)*300,-38)
	return worker.get_global_mouse_position()
