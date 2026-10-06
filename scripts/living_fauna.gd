extends Node2D
## A single, batched atlas layer of local wildlife. Small state machines and
## five proximity samples per second keep life independent of combat physics.
const Catalog := preload("res://scripts/fauna_catalog.gd")
const THREAT_INTERVAL := .2
const MAX_THREAT_SOURCES := 64
var game: Node
var environment_id := "sector07"
var menu_mode := false
var presentation_weather: Node
var entries: Array[Dictionary] = []
var visible_bounds := Rect2(-100,-100,1640,1000)
var elapsed := 0.0
var last_update_usec := 0
var threat_queries := 0
var simulated_entries := 0
var atlas: Texture2D
var _profile: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _ground_ranges: Array[Vector2] = []
var _perches := PackedVector2Array()
var _atlas_frames: Dictionary = {}
var _atlas_anchors: Dictionary = {}
var _atlas_frame_anchors: Dictionary = {}
var _atlas_canvas_sizes: Dictionary = {}
var _reduced := false
var _threat_clock := 0.0
var _redraw_clock := 0.0
var _shot_serials: Dictionary = {}
var _actor_positions := PackedVector2Array()
var _bunker_left := 90.0
var _bunker_right := 730.0
var _perch_clock := 0.0
var _classic_mode := false
var _air_band := Vector2(190,360)
var _flight_range := Vector2(Catalog.WORLD_LEFT+50,Catalog.WORLD_RIGHT-50)

func configure(game_ref: Node,selected_environment: String) -> void:
	game = game_ref
	environment_id = selected_environment if Catalog.PROFILES.has(selected_environment) else "sector07"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS if menu_mode else Node.PROCESS_MODE_PAUSABLE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 3
	_profile = Catalog.profile(environment_id)
	_rng.seed = absi(environment_id.hash())+73061
	if is_instance_valid(game) and "scenario_bunker" in game and is_instance_valid(game.scenario_bunker):
		_bunker_left = game.scenario_bunker.room_left
		_bunker_right = game.scenario_bunker.room_right
	elif is_instance_valid(game):
		_classic_mode = true
		_bunker_left = 0.0
		_bunker_right = 873.0
	_ground_ranges = Catalog.ground_ranges(_bunker_left,_bunker_right,75,1440) if _classic_mode else Catalog.ground_ranges(_bunker_left,_bunker_right)
	_load_atlas()
	_collect_perches()
	refresh_presentation()
	_create_population()
	refresh_presentation()
	queue_redraw()

func set_menu_mode(value: bool) -> void:
	if menu_mode==value and is_node_ready(): return
	menu_mode = value
	process_mode = Node.PROCESS_MODE_ALWAYS if menu_mode else Node.PROCESS_MODE_PAUSABLE
	if not is_node_ready(): return
	_rng.seed = absi(environment_id.hash())+73061
	_collect_perches()
	refresh_presentation()
	_create_population()
	refresh_presentation()

func _load_atlas() -> void:
	if ResourceLoader.exists(Catalog.ATLAS_PATH): atlas = load(Catalog.ATLAS_PATH) as Texture2D
	if atlas==null: return
	var metadata: Variant = {}
	if FileAccess.file_exists(Catalog.SOURCE_PATH): metadata = JSON.parse_string(FileAccess.get_file_as_string(Catalog.SOURCE_PATH))
	var species_metadata: Dictionary = metadata.get("species",{}) if metadata is Dictionary else {}
	var cell_size := atlas.get_size()/Vector2(4,8)
	for row in Catalog.SPECIES_ORDER.size():
		var species: String = Catalog.SPECIES_ORDER[row]
		var data: Dictionary = species_metadata.get(species,{})
		var frames: Array[Rect2] = []
		for frame in 4:
			var rect := Rect2(Vector2(frame,row)*cell_size,cell_size)
			if frame<data.get("frames",[]).size():
				var coords: Array = data.frames[frame]
				if coords.size()==4: rect = Rect2(float(coords[0]),float(coords[1]),float(coords[2]),float(coords[3]))
			frames.append(rect)
		_atlas_frames[species] = frames
		var anchor: Array = data.get("anchor",[])
		_atlas_anchors[species] = Vector2(float(anchor[0]),float(anchor[1])) if anchor.size()==2 else Vector2(Catalog.SPECIES[species].anchor)
		var frame_anchors: Array[Vector2] = []
		for frame in 4:
			var anchors: Array = data.get("frame_anchors",[])
			frame_anchors.append(Vector2(float(anchors[frame][0]),float(anchors[frame][1])) if frame<anchors.size() else Vector2(_atlas_anchors[species]))
		_atlas_frame_anchors[species] = frame_anchors
		var canvas: Array = data.get("canvas_size",[])
		_atlas_canvas_sizes[species] = Vector2(float(canvas[0]),float(canvas[1])) if canvas.size()==2 else cell_size

func _collect_perches() -> void:
	_perches.clear()
	if menu_mode or _classic_mode: return
	var parent := get_parent()
	if not is_instance_valid(parent) or not "props_layer" in parent: return
	var props: Node = parent.props_layer
	if not is_instance_valid(props) or not "entries" in props: return
	for entry: Dictionary in props.entries:
		if entry.get("kind","")!="tree" or bool(entry.get("broken",false)): continue
		var points: PackedVector2Array = entry.get("emit_points",PackedVector2Array())
		if points.is_empty(): continue
		# The authored canopy anchors place a resting bird on actual foliage,
		# rather than a floating perch guessed from the panoramic photograph.
		var candidate: Vector2 = points[points.size()>>1]
		if candidate.y<Catalog.GROUND_Y-45: _perches.append(candidate)

func _create_population() -> void:
	entries.clear()
	var roster: Dictionary = _profile.species
	for species: String in Catalog.SPECIES_ORDER:
		for local_index in int(roster.get(species,0)):
			if entries.size()>=Catalog.MAX_POPULATION: return
			if menu_mode and not Catalog.airborne(species): continue
			if _ground_ranges.is_empty() and not Catalog.airborne(species): continue
			var data: Dictionary = Catalog.SPECIES[species]
			var range_index := entries.size()%maxi(1,_ground_ranges.size())
			var range_bounds := _ground_ranges[range_index] if not _ground_ranges.is_empty() else Vector2(-380,-280)
			var point := Vector2(_rng.randf_range(range_bounds.x+12,range_bounds.y-12),Catalog.GROUND_Y)
			var ground_point := point
			var airborne := Catalog.airborne(species)
			var state := "rest"
			if airborne:
				point = Vector2(_rng.randf_range(_flight_range.x,_flight_range.y),_rng.randf_range(_air_band.x,_air_band.y))
				state = "flight" if data.mode!="insect" else "flutter"
				if data.mode=="bird" and not menu_mode and local_index%3==0:
					if not _perches.is_empty(): point = _perches[(local_index+entries.size())%_perches.size()]
					else: point = ground_point
					state = "perch"
			var phase := _rng.randf_range(0,TAU)
			var entry := {"index":entries.size(),"species":species,"mode":str(data.mode),"position":point,"origin":point,"target":point,"state":state,"state_time":0.0,"remaining":_rng.randf_range(6.0,18.0) if not airborne else _rng.randf_range(1.2,5.4),"phase":phase,"direction":-1.0 if _rng.randf()<.5 else 1.0,"range_index":range_index,"ground_range":range_bounds,"size":Vector2(data.size),"frame":0,"airborne":airborne,"displayed":true,"active":true,"hop_lift":0.0,"hop_phase":0.0,"flee_events":0,"protected_time":0.0,"hidden_delta":0.0}
			entries.append(entry)

func reduced() -> bool:
	var weather: Node = presentation_weather
	if is_instance_valid(game) and "weather" in game and is_instance_valid(game.weather): weather = game.weather
	return is_instance_valid(weather) and "reduced_effects" in weather and bool(weather.reduced_effects)

func refresh_presentation() -> void:
	_reduced = reduced()
	visible_bounds = (get_global_transform_with_canvas().affine_inverse()*get_viewport_rect()).grow(70)
	_air_band = Vector2(_profile.get("air_height",Vector2(190,360)))
	_flight_range = Vector2(Catalog.WORLD_LEFT+50,Catalog.WORLD_RIGHT-50)
	if menu_mode:
		_flight_range = Vector2(visible_bounds.position.x+60,visible_bounds.end.x-60)
		var sky_bottom := visible_bounds.position.y+visible_bounds.size.y*.35
		var parent := get_parent()
		if is_instance_valid(parent) and "panorama_rect" in parent:
			var panorama: Rect2 = parent.panorama_rect
			var cutoff := .35
			if "data" in parent: cutoff = clampf(float(parent.data.get("sky_cutoff",.5))*.7,.12,.40)
			sky_bottom = minf(sky_bottom,panorama.position.y+panorama.size.y*cutoff)
		var sky_top := visible_bounds.position.y+38
		_air_band = Vector2(sky_top,maxf(sky_top+50,sky_bottom))
	for entry: Dictionary in entries:
		entry.active = not _reduced or int(entry.index)%3==0
		entry.displayed = bool(entry.active) and visible_bounds.grow(30).has_point(entry.position)
	queue_redraw()

func _process(delta: float) -> void:
	if not menu_mode and get_tree().paused: return
	if not is_finite(delta) or delta<=0: return
	if entries.is_empty(): return
	var started_usec := Time.get_ticks_usec()
	# A debugger stall advances one bounded presentation step. Wildlife never
	# asks the engine to catch up missed physical ticks.
	var dt := minf(delta,.12)
	elapsed += dt
	_threat_clock += dt
	_redraw_clock += dt
	_perch_clock += dt
	if _perch_clock>=3.0:
		_perch_clock = 0.0
		_collect_perches()
		for entry: Dictionary in entries:
			if entry.state not in ["perch","landing"] or menu_mode: continue
			var contact: Vector2 = entry.target if entry.state=="landing" else entry.position
			if contact.y>=Catalog.GROUND_Y-2: continue
			var still_supported := false
			for perch: Vector2 in _perches:
				if perch.distance_squared_to(contact)<36:
					still_supported = true
					break
			if not still_supported: _flee(entry,contact+Vector2(0,24))
	if _threat_clock>=THREAT_INTERVAL:
		_threat_clock = fmod(_threat_clock,THREAT_INTERVAL)
		refresh_presentation()
		if not menu_mode: _sample_disturbances()
	simulated_entries = 0
	for entry: Dictionary in entries:
		if not bool(entry.active): continue
		var step_delta := dt
		if not visible_bounds.grow(90).has_point(entry.position):
			entry.hidden_delta = float(entry.hidden_delta)+dt
			entry.displayed = false
			if float(entry.hidden_delta)<.2: continue
			step_delta = float(entry.hidden_delta)
		elif float(entry.hidden_delta)>0:
			step_delta += float(entry.hidden_delta)
		entry.hidden_delta = 0.0
		simulated_entries += 1
		_step_entry(entry,step_delta)
		entry.displayed = visible_bounds.grow(30).has_point(entry.position)
	if _redraw_clock>=1.0/(18.0 if _reduced else 45.0):
		_redraw_clock = 0.0
		queue_redraw()
	last_update_usec = Time.get_ticks_usec()-started_usec

func _sample_disturbances() -> void:
	_actor_positions.clear()
	var current_shooters: Dictionary = {}
	var sources: Array[Node] = []
	if is_instance_valid(game) and "players" in game:
		for actor: Node in game.players:
			if sources.size()>=MAX_THREAT_SOURCES: break
			if is_instance_valid(actor): sources.append(actor)
	if is_inside_tree():
		for actor: Node in get_tree().get_nodes_in_group("enemies"):
			if sources.size()>=MAX_THREAT_SOURCES: break
			sources.append(actor)
		for turret: Node in get_tree().get_nodes_in_group("turrets"):
			if sources.size()>=MAX_THREAT_SOURCES: break
			sources.append(turret)
	for actor: Node in sources:
		if not is_instance_valid(actor) or not actor is Node2D: continue
		if "dead" in actor and actor.dead: continue
		var point: Vector2 = actor.global_position
		_actor_positions.append(to_local(point))
		var shooter: Node = actor.get_node_or_null("WorkerWeapon")
		if shooter==null and ("muzzle_flash" in actor or "flash_tick" in actor): shooter = actor
		if shooter==null: continue
		var serial := int(shooter.get("_shot_index")) if "_shot_index" in shooter else int(shooter.get("flash_tick")) if "flash_tick" in shooter else int(shooter.get("attack_count")) if "attack_count" in shooter else 0
		var shooter_id := shooter.get_instance_id()
		current_shooters[shooter_id] = serial
		if _shot_serials.has(shooter_id) and int(_shot_serials[shooter_id])!=serial:
			notify_disturbance(to_local(point),280.0)
	_shot_serials = current_shooters
	for entry: Dictionary in entries:
		if not entry.active or float(entry.protected_time)>0: continue
		var radius := float(Catalog.SPECIES[entry.species].threat_radius)
		for point: Vector2 in _actor_positions:
			threat_queries += 1
			if point.distance_squared_to(entry.position)<radius*radius:
				_flee(entry,point)
				break

func notify_disturbance(point: Vector2,radius := 260.0) -> void:
	if menu_mode or not is_finite(radius) or radius<=0: return
	for entry: Dictionary in entries:
		if entry.active and float(entry.protected_time)<=0 and point.distance_squared_to(entry.position)<radius*radius:
			_flee(entry,point)

func _flee(entry: Dictionary,source: Vector2) -> void:
	if entry.mode=="insect":
		entry.origin = entry.position+Vector2(signf(entry.position.x-source.x)*22,-8)
		entry.protected_time = 1.4
		return
	entry.state = "flee"
	entry.state_time = 0.0
	entry.remaining = _rng.randf_range(.7,1.1)
	entry.protected_time = entry.remaining+5.0
	entry.direction = -1.0 if source.x>=entry.position.x else 1.0
	entry.flee_events = int(entry.flee_events)+1
	if Catalog.airborne(entry.species):
		entry.airborne = true
		entry.target = Vector2(clampf(entry.position.x+float(entry.direction)*260,Catalog.WORLD_LEFT+30,Catalog.WORLD_RIGHT-30),clampf(entry.position.y-115,115,360))
	else:
		var range_bounds: Vector2 = entry.ground_range
		var escape_distance := 55.0 if entry.species=="frog" else 105.0 if entry.species=="rabbit" else 85.0
		entry.target = Vector2(clampf(entry.position.x+float(entry.direction)*escape_distance,range_bounds.x+10,range_bounds.y-10),Catalog.GROUND_Y)
		if absf(entry.target.x-entry.position.x)<3:
			entry.direction *= -1.0
			entry.target.x = clampf(entry.position.x+float(entry.direction)*30,range_bounds.x+10,range_bounds.y-10)

func _step_entry(entry: Dictionary,delta: float) -> void:
	entry.state_time = float(entry.state_time)+delta
	entry.remaining = float(entry.remaining)-delta
	entry.protected_time = maxf(0,float(entry.protected_time)-delta)
	var data: Dictionary = Catalog.SPECIES[entry.species]
	if entry.mode=="insect":
		var phase := elapsed*1.4+float(entry.phase)
		entry.position = Vector2(entry.origin)+Vector2(sin(phase)*18,sin(phase*1.73)*7)
		entry.frame = int(elapsed*float(data.fps)+float(entry.phase))%4
		return
	if entry.mode in ["bird","flyer"]:
		_step_air(entry,data,delta)
	else:
		_step_ground(entry,data,delta)
	var moving: bool = str(entry.state) in ["flight","landing","flee","scurry","hop"]
	if entry.mode=="hopper" and moving:
		var hop_phase: float = entry.hop_phase
		entry.frame = 0 if hop_phase<.11 else 1 if hop_phase<.22 else 2 if hop_phase<.78 else 3
	else:
		entry.frame = int(float(entry.state_time)*float(data.fps)+float(entry.phase))%4 if moving else 3 if entry.mode=="bird" else 0

func _step_air(entry: Dictionary,data: Dictionary,delta: float) -> void:
	if entry.state=="perch":
		entry.airborne = false
		if float(entry.remaining)<=0:
			entry.state = "flight"
			entry.airborne = true
			entry.state_time = 0.0
			entry.remaining = _rng.randf_range(4.5,10.0)
			entry.target = Vector2(clampf(entry.position.x+float(entry.direction)*_rng.randf_range(220,480),_flight_range.x,_flight_range.y),_rng.randf_range(_air_band.x,_air_band.y))
		return
	var flight_speed := float(data.flight_speed) if entry.state=="flee" else float(data.speed)
	var destination: Vector2 = entry.target
	if entry.state=="landing" and destination.distance_squared_to(entry.position)<36:
		entry.position = destination
		entry.state = "perch"
		entry.airborne = false
		entry.remaining = _rng.randf_range(2.4,6.8)
		entry.state_time = 0.0
		return
	if destination.distance_squared_to(entry.position)<36 or float(entry.remaining)<=0:
		if not menu_mode and entry.mode=="bird" and entry.state!="flee" and _rng.randf()<.38:
			if not _perches.is_empty(): destination = _perches[_rng.randi()%_perches.size()]
			else:
				var range_bounds: Vector2 = entry.ground_range
				destination = Vector2(clampf(entry.position.x,range_bounds.x+12,range_bounds.y-12),Catalog.GROUND_Y)
			entry.state = "landing"
		else:
			destination = Vector2(_rng.randf_range(_flight_range.x,_flight_range.y),_rng.randf_range(_air_band.x,_air_band.y))
			entry.state = "flight"
		entry.target = destination
		entry.remaining = _rng.randf_range(5,11)
		entry.state_time = 0.0
	entry.direction = 1.0 if destination.x>=entry.position.x else -1.0
	entry.position = Vector2(entry.position).move_toward(destination,flight_speed*delta)
	if entry.state=="landing" and Vector2(entry.position).distance_squared_to(destination)<9:
		entry.position = destination
		entry.state = "perch"
		entry.airborne = false
		entry.remaining = _rng.randf_range(2.4,6.8)
		entry.state_time = 0.0
	elif entry.state=="flight":
		# Small lift changes keep a gliding flock alive without translating the
		# sprite in large decorative sine waves.
		entry.position.y += sin(elapsed*2.2+float(entry.phase))*.8*delta
	entry.position.x = clampf(entry.position.x,_flight_range.x-30,_flight_range.y+30)
	entry.position.y = clampf(entry.position.y,_air_band.x if menu_mode else 90.0,_air_band.y if menu_mode else Catalog.GROUND_Y)

func _step_ground(entry: Dictionary,data: Dictionary,delta: float) -> void:
	var range_bounds: Vector2 = entry.ground_range
	if entry.state=="rest":
		if float(entry.remaining)<=0:
			entry.state = "hop" if entry.mode=="hopper" else "scurry"
			entry.state_time = 0.0
			entry.remaining = _rng.randf_range(.55,.95)
			entry.direction = -1.0 if _rng.randf()<.5 else 1.0
			entry.target = Vector2(clampf(entry.position.x+float(entry.direction)*_rng.randf_range(7,23),range_bounds.x+10,range_bounds.y-10),Catalog.GROUND_Y)
		return
	var speed := float(data.flight_speed) if entry.state=="flee" else float(data.speed)
	entry.position.y = Catalog.GROUND_Y
	entry.hop_lift = 0.0
	entry.hop_phase = 0.0
	var moving_amount := speed*delta
	if entry.mode=="hopper":
		var cycle := (.40 if entry.species=="frog" else .33) if entry.state=="flee" else (.72 if entry.species=="frog" else .55)
		var hop_phase := fposmod(float(entry.state_time)/cycle,1.0)
		entry.hop_phase = hop_phase
		# Crouch, push-off, extension, and landing use the same clock as lift
		# and forward movement. A resting frog no longer alternates jump poses.
		var lift_phase := clampf((hop_phase-.22)/.56,0,1)
		entry.hop_lift = sin(lift_phase*PI)*(3.0 if entry.species=="frog" else 4.5)
		moving_amount *= 1.75 if hop_phase>=.22 and hop_phase<.78 else 0.0
	entry.position.x = move_toward(entry.position.x,entry.target.x,moving_amount)
	if absf(entry.position.x-entry.target.x)<1.0 or float(entry.remaining)<=0:
		if entry.mode=="hopper" and float(entry.hop_phase)>=.22 and float(entry.hop_phase)<.78: return
		entry.state = "rest"
		entry.state_time = 0.0
		entry.remaining = _rng.randf_range(6.0,18.0)
		entry.hop_lift = 0.0
	entry.position.x = clampf(entry.position.x,range_bounds.x+10,range_bounds.y-10)

func _sprite_rect(entry: Dictionary,frame: int) -> Rect2:
	var source: Rect2 = _atlas_frames[entry.species][frame]
	# All poses share one native-pixel scale. Cropping an extended wing or
	# leg must not inflate the animal's torso on the next animation frame.
	var canvas: Vector2 = _atlas_canvas_sizes[entry.species]
	var source_scale := float(entry.size.x)/maxf(1.0,canvas.x)
	var size: Vector2 = source.size*source_scale
	var anchor: Vector2 = _atlas_frame_anchors[entry.species][frame]
	if entry.mode=="bird" and not entry.airborne: anchor.y = .96
	var point: Vector2 = Vector2(entry.position)-Vector2(0,float(entry.hop_lift))
	var destination := Rect2((point-size*anchor).round(),size)
	if float(entry.direction)<0:
		# A tail gives mice a deliberately off-center body pivot. Mirroring
		# around the rectangle's midpoint would shift their body sideways.
		destination.position.x = roundf(point.x+size.x*anchor.x)
		destination.size.x = -destination.size.x
	return destination

func _draw() -> void:
	if atlas==null: return
	for entry: Dictionary in entries:
		if not entry.displayed or not _atlas_frames.has(entry.species): continue
		var frame := int(entry.frame)%4
		var source: Rect2 = _atlas_frames[entry.species][frame]
		# No shadow/blob shader per body part: one atlas and one canvas material.
		draw_texture_rect_region(atlas,_sprite_rect(entry,frame),source,Color(.91,.93,.94,1.0))

func debug_snapshot() -> Array[Dictionary]:
	return entries.duplicate(true)

func debug_stats() -> Dictionary:
	var active := 0
	var displayed := 0
	var airborne := 0
	var state_counts: Dictionary = {}
	for entry: Dictionary in entries:
		if entry.active: active += 1
		if entry.displayed: displayed += 1
		if entry.airborne: airborne += 1
		state_counts[entry.state] = int(state_counts.get(entry.state,0))+1
	return {"population":entries.size(),"active":active,"visible":displayed,"airborne":airborne,"grounded":entries.size()-airborne,"reduced":_reduced,"state_counts":state_counts,"last_update_usec":last_update_usec,"threat_queries":threat_queries,"collision_queries":0,"atlas_loaded":atlas!=null,"elapsed":elapsed,"simulated_entries":simulated_entries}
