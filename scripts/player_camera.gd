extends Node
## Local view preferences never travel in authoritative world snapshots.
const PixelGrid := preload("res://scripts/pixel_grid.gd")
const MIN_ZOOM := .45
const MAX_ZOOM := 2.5
const DEFAULT_ZOOM := 1.25
## The follow view keeps at most this much world below the followed feet (the
## designed 720-unit framing). Taller whole-pixel views give the spare height
## to the sky, where aircraft attack, instead of to the static rock band.
const BELOW_FEET := 265.0
const LIFT := 95.0
## The exponential ease never arrives; these minimum approach speeds land the
## view exactly on its whole-pixel scale and centre.
const CENTER_SETTLE_SPEED := 24.0 # world units per second
const ZOOM_SETTLE_RATE := .08 # share of the target zoom per second
var game
var mode := "follow"
var view_zoom := DEFAULT_ZOOM
var settings_path := "user://camera.cfg"
var _save_delay := -1.0
## Presentation-only impulses: a decaying trauma level drives a small noise
## offset, a kick is one directional nudge. Both live in Camera2D.offset, so the
## followed position, zoom and their limits are never touched.
const MAX_SHAKE := 14.0 # screen pixels at full trauma and full setting
const MAX_KICK := 5.0
var shake_scale := 1.0
var trauma := 0.0
var _kick := Vector2.ZERO
var _shake_clock := 0.0
## Continuous framing before it is placed on whole pixels.
var _view_center := Vector2.INF
var _view_zoom := Vector2.ZERO
var _presented_position := Vector2.INF
var _presented_zoom := Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Run after network interpolation and actor motion.
	process_priority = 100
	load_settings()

func settings() -> Dictionary:
	return {"mode":mode,"zoom":view_zoom,"min_zoom":MIN_ZOOM,"max_zoom":MAX_ZOOM,"shake":shake_scale}

func set_shake(value: float) -> void:
	if not is_finite(value): return
	shake_scale=clampf(value,0.0,1.0)
	_save_delay=.4

func impulses_enabled() -> bool:
	if shake_scale<=0.0 or not is_instance_valid(game) or not is_instance_valid(game.camera): return false
	var weather: Variant=game.get("weather")
	return not (is_instance_valid(weather) and weather.get("reduced_effects")==true)

func proximity(at: Vector2,reach: float) -> float:
	# Only this view's own workers listen: online each peer follows itself,
	# couch co-op shares one view and takes its nearest worker.
	if not at.is_finite() or reach<=0.0: return 0.0
	var nearest:=INF
	if mode=="follow" and game.started:
		for worker in follow_players(): nearest=minf(nearest,worker.global_position.distance_to(at))
	if nearest==INF: nearest=game.camera.position.distance_to(at)
	return 1.0-smoothstep(reach*.22,reach,nearest)

func add_trauma(amount: float,at: Vector2,reach: float=900.0) -> void:
	if not impulses_enabled() or not is_finite(amount) or amount<=0.0: return
	trauma=minf(1.0,trauma+amount*proximity(at,reach))

func add_kick(direction: Vector2,amount: float) -> void:
	if not impulses_enabled() or not direction.is_finite() or not is_finite(amount) or amount<=0.0: return
	_kick=(_kick+direction.normalized()*amount).limit_length(MAX_KICK)

func _update_impulses(delta: float) -> void:
	if not is_instance_valid(game.camera): return
	if (trauma<=0.0 and _kick==Vector2.ZERO) or not impulses_enabled():
		trauma=0.0
		_kick=Vector2.ZERO
		if game.camera.offset!=Vector2.ZERO: game.camera.offset=Vector2.ZERO
		return
	_shake_clock+=delta
	trauma=maxf(0.0,trauma-delta*1.25)
	_kick*=exp(-delta*15.0)
	if _kick.length_squared()<.01: _kick=Vector2.ZERO
	var level:=trauma*trauma*MAX_SHAKE*shake_scale
	var wobble:=Vector2(sin(_shake_clock*37.1)+sin(_shake_clock*59.3+1.7)*.6,sin(_shake_clock*43.7+.5)+sin(_shake_clock*71.9+2.1)*.6)/1.6
	# Whole physical pixels: a nearest-filtered pixel world must not shimmer.
	game.camera.offset=PixelGrid.snap_offset(wobble*level+_kick*shake_scale,game.camera.zoom,get_viewport())

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
	set_zoom(wheel_zoom(view_zoom*pow(1.12,direction*clampf(event.factor,.1,4.0)),direction))
	get_viewport().set_input_as_handled()

## The view only shows whole pixels per texel, so a wheel notch that would
## settle on the same step moves the preference on to the next whole step.
func wheel_zoom(next: float,direction: float) -> float:
	if not is_finite(next): return view_zoom
	var factor:=PixelGrid.stretch(get_viewport())
	var unit:=minf(factor.x,factor.y)
	var window:=PixelGrid.window_pixels(get_viewport())
	var current:=_preferred_scale(view_zoom,unit,window)
	if current<1.0-PixelGrid.EPSILON or not PixelGrid.is_whole(current): return next
	if not is_equal_approx(_preferred_scale(next,unit,window),current): return next
	if direction>0.0: return minf(MAX_ZOOM,(current+1.0)/unit)
	if current>1.0+PixelGrid.EPSILON: return (current-1.0)/unit
	return minf(next,.70/unit)

func _preferred_scale(zoom: float,unit: float,window: Vector2) -> float:
	return PixelGrid.settle_scale(zoom*unit,INF,window,zoom<=DEFAULT_ZOOM)

func _process(delta: float) -> void:
	if _save_delay>=0:
		_save_delay-=delta
		if _save_delay<0: save_settings()
	if not is_instance_valid(game) or get_tree().paused: return
	_update_impulses(delta)
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
	# Every framing settles on a whole number of physical pixels per world unit
	# (see pixel_grid.gd); fits that need less than one keep their exact value.
	var viewport:=get_viewport()
	var factor:=PixelGrid.stretch(viewport)
	var unit:=minf(factor.x,factor.y)
	var window:=PixelGrid.window_pixels(viewport)
	var viewport_size:=viewport.get_visible_rect().size
	var center: Vector2=game.camera_target_center
	var magnification: float=game.camera_target_zoom
	if not game.started: return _view(center,PixelGrid.fit_scale(magnification*unit),unit)
	if "expedition" in game and is_instance_valid(game.expedition) and game.expedition.stage in ["travel","stop"] and is_instance_valid(game.expedition.vehicle):
		var truck=game.expedition.vehicle
		var workers_in_view:=follow_players()
		if workers_in_view.any(func(worker):return is_instance_valid(worker.mounted_turret) and worker.mounted_turret.get_parent()==truck):
			var speed_bias:=clampf(float(truck.velocity.x)/float(truck.SPEED),-1,1)
			var look_ahead: float=lerpf(float(truck.facing)*105,speed_bias*210,absf(speed_bias))
			var convoy_center: Vector2=truck.global_position+Vector2(look_ahead,-190)
			var span:=Rect2(truck.global_position-Vector2(145,95),Vector2(290,110))
			for worker in workers_in_view: span=span.expand(worker.global_position)
			var fit:=minf(viewport_size.x/(span.size.x+680),viewport_size.y/(span.size.y+420))
			if span.size.x>500: convoy_center.x=span.get_center().x+look_ahead*.4
			return _view(convoy_center,PixelGrid.settle_scale(clampf(view_zoom,.65,1.65)*unit,maxf(.45,fit)*unit,window,view_zoom<=DEFAULT_ZOOM),unit)
	# The overview must keep the whole bunker framing: never round up. A whole
	# step that shows more keeps the framing's lower edge and adds sky instead
	# of rock below the deepest floor.
	if mode=="overview":
		var designed:=clampf(magnification*view_zoom,.25,MAX_ZOOM)
		var overview:=PixelGrid.fit_scale(designed*unit)
		center.y+=viewport_size.y*.5/designed-viewport_size.y*.5/(overview/unit)
		return _view(center,overview,unit)
	var workers:=follow_players()
	if workers.is_empty(): return _view(center,PixelGrid.settle_scale(view_zoom*unit,INF,window,view_zoom<=DEFAULT_ZOOM),unit)
	var bounds:=Rect2(workers[0].global_position,Vector2.ZERO)
	for worker in workers: bounds=bounds.expand(worker.global_position)
	var limit:=INF
	var hud_bottom:=-1.0
	if workers.size()>1:
		# Local couch co-op shares a view; online peers each follow themselves.
		limit=maxf(MIN_ZOOM,minf(viewport_size.x/(bounds.size.x+500.0),viewport_size.y/(bounds.size.y+390.0)))
		# Workers on different floors must remain above their interaction docks.
		# Keep the normal composition until the lowest worker would be covered.
		if is_instance_valid(game.hud) and game.hud.overlay.is_empty():
			hud_bottom=viewport_size.y-72.0
			var screen: Rect2=game.hud.screen_rect()
			for occupied: Rect2 in game.hud.occupied_gameplay_bounds():
				if occupied.position.y>screen.get_center().y:
					hud_bottom=minf(hud_bottom,game.hud.canvas.position.y+occupied.position.y*game.hud.canvas.scale.y-24.0)
			limit=minf(limit,maxf(MIN_ZOOM,(hud_bottom-80.0)/(bounds.size.y+72.0)))
	# A deliberate zoom past the default may round up past the designed area.
	var scale:=PixelGrid.settle_scale(view_zoom*unit,limit*unit,window,view_zoom<=DEFAULT_ZOOM)
	magnification=scale/unit
	center=bounds.get_center()+Vector2(0,-follow_lift(window.y/scale))
	if workers.size()==1:
		center.x+=float(workers[0].facing)*60.0
	elif hud_bottom>=0.0:
		var lowest_center:=bounds.end.y-(hud_bottom-viewport_size.y*.5)/magnification
		var highest_center:=bounds.position.y-72.0-(80.0-viewport_size.y*.5)/magnification
		if lowest_center<=highest_center: center.y=clampf(center.y,lowest_center,highest_center)
	return _view(center,scale,unit)

## How far the follow view centre sits above the followed feet for a view this
## many world units tall.
static func follow_lift(visible_height: float) -> float:
	if not is_finite(visible_height): return LIFT
	return maxf(LIFT,visible_height*.5-BELOW_FEET)

func _view(center: Vector2,scale: float,unit: float) -> Dictionary:
	return {"center":center,"zoom":scale/maxf(unit,.0001),"scale":scale}

func update_view(delta: float,snap: bool=false) -> void:
	if not is_instance_valid(game.camera): return
	var target:=desired_view()
	var viewport:=get_viewport()
	var target_zoom:=PixelGrid.zoom_for(float(target.scale),viewport)
	var target_center: Vector2=target.center
	# A fixture or scene change placed the camera itself: continue from there.
	if not _view_center.is_finite() or game.camera.position!=_presented_position or game.camera.zoom!=_presented_zoom:
		_view_center=game.camera.position
		_view_zoom=game.camera.zoom
	if snap:
		_view_center=target_center
		_view_zoom=target_zoom
	else:
		var step:=maxf(0,delta)
		var weight:=1.0-exp(-step*7.0)
		_view_center=_view_center.lerp(target_center,weight).move_toward(target_center,CENTER_SETTLE_SPEED*step)
		_view_zoom=_view_zoom.lerp(target_zoom,weight).move_toward(target_zoom,target_zoom.length()*ZOOM_SETTLE_RATE*step)
	# Present on whole physical pixels: texel edges meet pixel edges and the
	# world scrolls in whole-pixel steps.
	game.camera.zoom=_view_zoom
	game.camera.position=PixelGrid.snap_center(_view_center,_view_zoom,viewport)
	_presented_position=game.camera.position
	_presented_zoom=game.camera.zoom
	game.camera.force_update_scroll()

## Physical pixels per world unit the camera currently shows (x and y).
func presented_scale() -> Vector2:
	if not is_instance_valid(game) or not is_instance_valid(game.camera): return Vector2.ZERO
	return PixelGrid.scale_of(game.camera.zoom,get_viewport())

func load_settings() -> void:
	if "--no-profile-save" in OS.get_cmdline_user_args() and settings_path=="user://camera.cfg": return
	var config:=ConfigFile.new()
	if config.load(settings_path)!=OK: return
	var saved_mode: Variant=config.get_value("camera","mode","follow")
	if saved_mode is String and saved_mode in ["follow","overview"]: mode=saved_mode
	var saved_zoom: Variant=config.get_value("camera","zoom",DEFAULT_ZOOM)
	if (saved_zoom is float or saved_zoom is int) and is_finite(float(saved_zoom)):
		view_zoom=clampf(float(saved_zoom),MIN_ZOOM,MAX_ZOOM)
	var saved_shake: Variant=config.get_value("camera","shake",1.0)
	if (saved_shake is float or saved_shake is int) and is_finite(float(saved_shake)):
		shake_scale=clampf(float(saved_shake),0.0,1.0)

func save_settings() -> void:
	if "--no-profile-save" in OS.get_cmdline_user_args() and settings_path=="user://camera.cfg": return
	var config:=ConfigFile.new()
	config.set_value("camera","mode",mode)
	config.set_value("camera","zoom",view_zoom)
	config.set_value("camera","shake",shake_scale)
	config.save(settings_path)

func _exit_tree() -> void:
	if _save_delay>=0: save_settings()
