extends Node
## Local view preferences never travel in authoritative world snapshots.
const MIN_ZOOM := .45
const MAX_ZOOM := 2.5
const DEFAULT_ZOOM := 1.25
var game
var mode := "follow"
var view_zoom := DEFAULT_ZOOM
var settings_path := "user://camera.cfg"
var _save_delay := -1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Run after network interpolation and actor motion.
	process_priority = 100
	load_settings()

func settings() -> Dictionary:
	return {"mode":mode,"zoom":view_zoom,"min_zoom":MIN_ZOOM,"max_zoom":MAX_ZOOM}

func set_mode(value: String) -> void:
	if value not in ["follow","overview"] or value==mode: return
	mode=value
	view_zoom=DEFAULT_ZOOM if mode=="follow" else 1.0
	_save_delay=.4

func set_zoom(value: float) -> void:
	if not is_finite(value): return
	view_zoom=clampf(value,MIN_ZOOM,MAX_ZOOM)
	_save_delay=.4

func reset_view() -> void:
	mode="follow"
	view_zoom=DEFAULT_ZOOM
	_save_delay=.4

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(game) or not game.started or get_tree().paused: return
	if is_instance_valid(game.hud) and not game.hud.overlay.is_empty(): return
	if is_instance_valid(game.hud) and game.hud.has_method("has_session_action") and game.hud.has_session_action(): return
	if is_instance_valid(game.hud) and game.hud.has_method("has_text_entry") and game.hud.has_text_entry(): return
	if not event is InputEventMouseButton or not event.pressed: return
	if event.button_index not in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]: return
	var direction := 1.0 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1.0
	set_zoom(view_zoom*pow(1.12,direction*clampf(event.factor,.1,4.0)))
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _save_delay>=0:
		_save_delay-=delta
		if _save_delay<0: save_settings()
	if not is_instance_valid(game) or get_tree().paused: return
	# Explicitly frozen offline gallery fixtures retain their authored camera.
	var guest: bool=is_instance_valid(game.network) and game.network.active and not game.network.is_host
	if not game.is_processing() and not guest: return
	update_view(delta)

func follow_players() -> Array:
	var result: Array=[]
	var online: bool=is_instance_valid(game.network) and game.network.active
	for worker in game.players:
		if not is_instance_valid(worker) or worker.is_queued_for_deletion(): continue
		if online and worker.player_id!=game.network.local_player_id: continue
		result.append(worker)
	return result

func desired_view() -> Dictionary:
	var center: Vector2=game.camera_target_center
	var magnification: float=game.camera_target_zoom
	if not game.started: return {"center":center,"zoom":magnification}
	if "expedition" in game and is_instance_valid(game.expedition) and game.expedition.stage in ["travel","stop"] and is_instance_valid(game.expedition.vehicle):
		var truck=game.expedition.vehicle
		var workers_in_view:=follow_players()
		if workers_in_view.any(func(worker):return is_instance_valid(worker.mounted_turret) and worker.mounted_turret.get_parent()==truck):
			var speed_bias:=clampf(float(truck.velocity.x)/float(truck.SPEED),-1,1)
			var look_ahead: float=lerpf(float(truck.facing)*105,speed_bias*210,absf(speed_bias))
			var convoy_center: Vector2=truck.global_position+Vector2(look_ahead,-190)
			var span:=Rect2(truck.global_position-Vector2(145,95),Vector2(290,110))
			for worker in workers_in_view: span=span.expand(worker.global_position)
			var viewport_size:=get_viewport().get_visible_rect().size
			var convoy_zoom:=clampf(view_zoom,.65,1.65)
			convoy_zoom=minf(convoy_zoom,minf(viewport_size.x/(span.size.x+680),viewport_size.y/(span.size.y+420)))
			if span.size.x>500: convoy_center.x=span.get_center().x+look_ahead*.4
			return {"center":convoy_center,"zoom":maxf(.45,convoy_zoom)}
	if mode=="overview": return {"center":center,"zoom":clampf(magnification*view_zoom,.25,MAX_ZOOM)}
	var workers:=follow_players()
	if workers.is_empty(): return {"center":center,"zoom":view_zoom}
	var bounds:=Rect2(workers[0].global_position,Vector2.ZERO)
	for worker in workers: bounds=bounds.expand(worker.global_position)
	center=bounds.get_center()+Vector2(0,-95)
	magnification=view_zoom
	if workers.size()==1:
		center.x+=float(workers[0].facing)*60.0
	else:
		# Local couch co-op shares a view; online peers each follow themselves.
		var viewport_size:=get_viewport().get_visible_rect().size
		magnification=minf(magnification,minf(viewport_size.x/(bounds.size.x+500.0),viewport_size.y/(bounds.size.y+390.0)))
		magnification=maxf(MIN_ZOOM,magnification)
		# Workers on different floors must remain above their interaction docks.
		# Keep the normal composition until the lowest worker would be covered.
		if is_instance_valid(game.hud) and game.hud.overlay.is_empty():
			var bottom:=viewport_size.y-72.0
			var screen: Rect2=game.hud.screen_rect()
			for occupied: Rect2 in game.hud.occupied_gameplay_bounds():
				if occupied.position.y>screen.get_center().y:
					bottom=minf(bottom,game.hud.canvas.position.y+occupied.position.y*game.hud.canvas.scale.y-24.0)
			magnification=minf(magnification,maxf(MIN_ZOOM,(bottom-80.0)/(bounds.size.y+72.0)))
			var lowest_center:=bounds.end.y-(bottom-viewport_size.y*.5)/magnification
			var highest_center:=bounds.position.y-72.0-(80.0-viewport_size.y*.5)/magnification
			if lowest_center<=highest_center: center.y=clampf(center.y,lowest_center,highest_center)
	return {"center":center,"zoom":magnification}

func update_view(delta: float,snap: bool=false) -> void:
	if not is_instance_valid(game.camera): return
	var target:=desired_view()
	var weight:=1.0 if snap else 1.0-exp(-maxf(0,delta)*7.0)
	game.camera.position=game.camera.position.lerp(target.center,weight)
	game.camera.zoom=game.camera.zoom.lerp(Vector2.ONE*float(target.zoom),weight)
	game.camera.force_update_scroll()

func load_settings() -> void:
	if "--no-profile-save" in OS.get_cmdline_user_args() and settings_path=="user://camera.cfg": return
	var config:=ConfigFile.new()
	if config.load(settings_path)!=OK: return
	var saved_mode: Variant=config.get_value("camera","mode","follow")
	if saved_mode is String and saved_mode in ["follow","overview"]: mode=saved_mode
	var saved_zoom: Variant=config.get_value("camera","zoom",DEFAULT_ZOOM)
	if (saved_zoom is float or saved_zoom is int) and is_finite(float(saved_zoom)):
		view_zoom=clampf(float(saved_zoom),MIN_ZOOM,MAX_ZOOM)

func save_settings() -> void:
	if "--no-profile-save" in OS.get_cmdline_user_args() and settings_path=="user://camera.cfg": return
	var config:=ConfigFile.new()
	config.set_value("camera","mode",mode)
	config.set_value("camera","zoom",view_zoom)
	config.save(settings_path)

func _exit_tree() -> void:
	if _save_delay>=0: save_settings()
