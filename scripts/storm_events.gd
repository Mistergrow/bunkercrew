extends Node2D
## A rare, host-owned strike lands on real exposed wood. Ambient sky flashes
## remain harmless; this event reuses the existing scenery damage/fire system.
const STRIKE_SECONDS := .42
const THUNDER_SECONDS := .34
const COOLDOWN_SECONDS := 75.0
const MAX_SERIAL := 2147483647
const DAMAGE := 54.0
var weather: Node2D
var serial := 0
var target_index := -1
var target := Vector2.ZERO
var origin := Vector2.ZERO
var age := 10.0
var cooldown := 0.0
var replica_only := false
var bolt := PackedVector2Array()
var branches: Array[PackedVector2Array] = []
var flash_columns: Array[Rect2] = []
var thunder_count := 0
var _thunder_pending := false
var _thunder_delay := THUNDER_SECONDS
var _suppressed := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 8
	var paint := CanvasItemMaterial.new()
	paint.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = paint

func _game():
	return weather.get("game") if is_instance_valid(weather) else null

func _props():
	var game = _game()
	var scenery = game.get("scenery") if is_instance_valid(game) else null
	return scenery.get("props_layer") if is_instance_valid(scenery) else null

func is_authority() -> bool:
	if replica_only or not is_inside_tree() or get_tree().paused: return false
	var game = _game()
	var network = game.get("network") if is_instance_valid(game) else null
	return not is_instance_valid(network) or not bool(network.get("active")) or bool(network.get("is_host"))

func reset() -> void:
	serial = 0
	target_index = -1
	target = Vector2.ZERO
	origin = Vector2.ZERO
	age = 10.0
	cooldown = 0.0
	_thunder_pending = false
	_suppressed = false
	bolt.clear()
	branches.clear()
	flash_columns.clear()
	queue_redraw()

func trigger_tree_strike(index: int = -1,visible_only: bool = true) -> bool:
	if not is_authority() or cooldown>0.0 or not is_instance_valid(weather): return false
	if not bool(weather.get("lightning_enabled")): return false
	var props = _props()
	if not is_instance_valid(props) or not is_instance_valid(props.get("reactions")): return false
	var bounds := get_canvas_transform().affine_inverse()*get_viewport_rect()
	var focus_x := bounds.get_center().x
	var game = _game()
	# Story events must not depend on one participant's local camera/zoom.
	if not visible_only and is_instance_valid(game) and is_instance_valid(game.core): focus_x=game.core.global_position.x
	var selected := {}
	var best := INF
	for entry: Dictionary in props.entries:
		if index>=0 and int(entry.index)!=index: continue
		if entry.kind!="tree": continue
		var state: Dictionary = props.reactions.state_for(int(entry.index))
		if state.is_empty() or bool(state.broken) or bool(state.burning): continue
		var root_point: Vector2 = props.to_global(entry.position)
		# The trunk must be outdoors too; a tall crown poking through a shelter
		# never makes the covered tree a valid target.
		if visible_only and not bounds.grow(-12).has_point(root_point-Vector2(0,2)): continue
		if weather.rain_surface(root_point.x)<root_point.y-1.0: continue
		var tip := Vector2.INF
		var points: PackedVector2Array = entry.get("emit_points",PackedVector2Array())
		for sample in points.size():
			var point: Vector2 = props.to_global(props.canopy_point(entry,sample))
			if point.y<tip.y and (not visible_only or bounds.grow(-8).has_point(point)): tip = point
		if not tip.is_finite(): continue
		var start := Vector2(tip.x+24.0,bounds.position.y-24.0 if visible_only else tip.y-500.0).round()
		if not _clear_path(start,tip): continue
		var score := absf(root_point.x-focus_x)+tip.y*.15
		if score<best:
			best = score
			selected = {"index":int(entry.index),"target":tip,"origin":start}
	if selected.is_empty(): return false
	# A strong hit leaves a short, visible burning interval before rain either
	# quenches it or the existing fire controller breaks the weakened trunk.
	if not props.reactions.damage_entry(selected.index,DAMAGE,"arc",selected.target,Vector2.DOWN): return false
	serial = mini(MAX_SERIAL,serial+1)
	target_index = selected.index
	target = selected.target
	origin = selected.origin
	age = 0.0
	cooldown = COOLDOWN_SECONDS
	_suppressed = false
	_thunder_pending = true
	_thunder_delay = weather.thunder_delay(target,THUNDER_SECONDS)
	_rebuild_arc()
	# Avoid simultaneous unrelated thunder/sky flashes hiding the local hit.
	weather.lightning_age = 10.0
	weather.thunder_wait = -1.0
	weather.lightning_wait = maxf(float(weather.lightning_wait),2.0)
	queue_redraw()
	return true

func _clear_path(from: Vector2,to: Vector2) -> bool:
	var ray := PhysicsRayQueryParameters2D.create(from,to,1|2)
	ray.hit_from_inside = true
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()

func _rebuild_arc() -> void:
	bolt.clear()
	branches.clear()
	flash_columns.clear()
	var random := RandomNumberGenerator.new()
	random.seed = 291031+serial*7919+target_index*137
	for step in 13:
		var fraction := float(step)/12.0
		var point := origin.lerp(target,fraction)
		if step>0 and step<12: point.x += random.randf_range(-18,18)*sin(fraction*PI)
		bolt.append(point.round() if step<12 else target)
	# Keep every visible segment outside real roof/wall geometry, including
	# the jagged detours (not just the straight line used to choose the tree).
	for step in range(1,bolt.size()):
		if not _clear_path(bolt[step-1],bolt[step]):
			for safe_step in bolt.size(): bolt[safe_step] = origin.lerp(target,float(safe_step)/12.0)
			break
	for branch in 3:
		var point := bolt[3+branch*2]
		var path := PackedVector2Array([point])
		for step in 3:
			var next := point+Vector2((-1 if branch%2==0 else 1)*random.randf_range(9,19),random.randf_range(10,22))
			if next.y>=target.y or not _clear_path(point,next): break
			path.append(next.round())
			point = next
		if path.size()>1: branches.append(path)
	for x in range(floori(target.x)-112,floori(target.x)+112,8):
		var top := target.y-110.0
		var cover: float = minf(weather.rain_surface(float(x)),minf(weather.rain_surface(float(x+4)),weather.rain_surface(float(x+8))))
		var bottom: float = minf(target.y+116.0,cover)
		if bottom>top: flash_columns.append(Rect2(x,top,8,bottom-top))

func _process(delta: float) -> void:
	if get_tree().paused or not is_finite(delta) or delta<=0.0: return
	cooldown = maxf(0.0,cooldown-delta)
	var was_visible := age<STRIKE_SECONDS and not _suppressed
	age = minf(10.0,age+delta)
	if _thunder_pending and age>=_thunder_delay:
		_thunder_pending = false
		var game = _game()
		if is_instance_valid(game) and is_instance_valid(game.get("audio")):
			# Local playback: the replicated event schedules one thunder on each
			# peer. game.sound would additionally broadcast and double it.
			if game.audio.has_method("play_sound_at"): game.audio.play_sound_at("thunder",target)
			else: game.audio.play_sound("thunder")
		thunder_count += 1
	if was_visible or age<STRIKE_SECONDS: queue_redraw()

func capture_state() -> Dictionary:
	return {"serial":serial,"target_index":target_index,"target":target,"origin":origin,"age":age,"cooldown":cooldown}

static func valid_state(state: Variant) -> bool:
	if not state is Dictionary or state.size()!=6: return false
	if not state.get("serial") is int or state.serial<0 or state.serial>MAX_SERIAL: return false
	if not state.get("target_index") is int or state.target_index< -1 or state.target_index>=96: return false
	for field in ["target","origin"]:
		if not state.get(field) is Vector2 or not state[field].is_finite() or state[field].abs().x>1000000 or state[field].abs().y>1000000: return false
	for field in ["age","cooldown"]:
		if not state.get(field) is float or not is_finite(state[field]): return false
	if state.age<0.0 or state.age>10.0 or state.cooldown<0.0 or state.cooldown>COOLDOWN_SECONDS: return false
	if state.serial==0: return state.target_index== -1
	return state.target_index>=0 and state.origin.y<state.target.y and state.origin.distance_to(state.target)<4000.0

func apply_state(state: Dictionary,first_snapshot: bool = false) -> bool:
	if not valid_state(state): return false
	if not first_snapshot and int(state.serial)<serial: return false
	var changed := int(state.serial)!=serial
	serial = state.serial
	target_index = state.target_index
	target = state.target
	origin = state.origin
	# A repeat snapshot cannot rewind an already presented flash or thunder.
	age = float(state.age) if changed or first_snapshot else maxf(age,float(state.age))
	cooldown = state.cooldown
	replica_only = true
	if first_snapshot:
		_suppressed = true
		_thunder_pending = false
	elif changed:
		_suppressed = age>=STRIKE_SECONDS
		_thunder_delay = weather.thunder_delay(target,THUNDER_SECONDS)
		_thunder_pending = age<_thunder_delay
	if (changed or first_snapshot) and serial>0: _rebuild_arc()
	queue_redraw()
	return true

func visual_strength() -> float:
	if _suppressed or age>=STRIKE_SECONDS or bolt.size()<2: return 0.0
	# One attack and decaying afterglow; no repeated hard flashes.
	return 1.0-smoothstep(.055,STRIKE_SECONDS,age)

func _draw() -> void:
	var strength := visual_strength()
	if strength<=0.0: return
	var reduced := bool(weather.get("reduced_effects")) if is_instance_valid(weather) else false
	if reduced:
		if age<.16: draw_polyline(bolt,Color(.60,.72,.79,.38*strength),1,false)
		return
	for rect in flash_columns:
		var top := rect.position.y
		while top<rect.end.y:
			var bottom := minf(top+24.0,rect.end.y)
			var corners := PackedVector2Array([Vector2(rect.position.x,top),Vector2(rect.end.x,top),Vector2(rect.end.x,bottom),Vector2(rect.position.x,bottom)])
			var colors := PackedColorArray()
			for corner in corners:
				var falloff := maxf(0.0,1.0-corner.distance_to(target)/112.0)
				colors.append(Color(.65,.78,.90,.15*strength*falloff*falloff))
			draw_polygon(corners,colors)
			top = bottom
	draw_polyline(bolt,Color(.38,.61,.79,.15*strength),9,false)
	draw_polyline(bolt,Color(.61,.78,.89,.40*strength),4,false)
	draw_polyline(bolt,Color(.91,.96,1.0,.96*strength),1,false)
	for branch in branches: draw_polyline(branch,Color(.64,.82,.94,.67*strength),1,false)
	for spoke in 7:
		var direction := Vector2.from_angle(float(spoke)*TAU/7.0)
		draw_line(target+direction*3,target+direction*(8.0+age*24.0),Color(.88,.92,.77,.74*strength),1,false)
