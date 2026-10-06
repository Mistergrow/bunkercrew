class_name ShiftWeather
extends Node2D
## Bounded rain in three world-depth bands. Every moving streak is swept against
## the actual world; secondary droplets disappear at their next contact.

const SKY_TOP := 95.0
const ROOF_EDGE := 873.0
const ROOF_Y := 245.0
const GROUND_Y := 430.0
var game
var elapsed := 0.0
var reduced_effects := false
var rain_strength := 1.0
var rain_base_strength := 1.0
var lightning_enabled := true
var environment_weather := "storm"
var rain: Array[Dictionary] = []
var dust: Array[Vector3] = []
var bolt := PackedVector2Array()
var lightning_branches: Array[PackedVector2Array] = []
var thunder_origin := Vector2.ZERO
var lightning_age := 10.0
var lightning_wait := 18.0
var thunder_wait := -1.0
var rng := RandomNumberGenerator.new()
var sky_layer: Node2D
var wind_layer: Node2D
var rain_layers: Array[Node2D] = []
var surface_effects: Node2D
var prop_surfaces: Node2D
var world_wind: Node2D
var storm_events: Node2D
var environment_id := "sector07"
var collision := RainCollision.new()
var contact_count := 0
var _last_parallax := Vector2.ZERO
var _last_view_stage := 0
var _bounds_frame := -1
var _wide_bounds := Rect2(-550,-300,2800,730)
var _shelter_frame := -1
var _shelter_by_x: Dictionary = {}
var _cover_query := PhysicsRayQueryParameters2D.create(Vector2.ZERO,Vector2.ZERO,1)

func _ready() -> void:
	rng.seed = 194603
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if is_instance_valid(game) and "scenario_options" in game and not game.scenario_options.is_empty():
		configure_environment(ScenarioCatalog.environment(str(game.scenario_options.environment)))
	collision.weather = self
	sky_layer = _layer("DistantLightning", 0, _draw_sky)
	wind_layer = _layer("RoofFlagAndWind", 1, _draw_wind)
	for band in 3:
		rain_layers.append(_layer(["FineDistantRain","WorldRain","ForegroundRain"][band], [0,13,25][band], _draw_rain_band.bind(band)))
	# Compile these helpers with the game; a broken rain helper must never look
	# like a successful launch of a silently disabled particle system.
	prop_surfaces = preload("res://scripts/weather_prop_surfaces.gd").new()
	prop_surfaces.set("game",game)
	prop_surfaces.set("weather",self)
	add_child(prop_surfaces)
	surface_effects = preload("res://scripts/surface_weather.gd").new()
	surface_effects.set("weather",self)
	add_child(surface_effects)
	world_wind = preload("res://scripts/world_wind.gd").new()
	world_wind.name = "WindborneMaterial"
	world_wind.weather = self
	world_wind.configure_environment({"id":environment_id})
	add_child(world_wind)
	storm_events = preload("res://scripts/storm_events.gd").new()
	storm_events.name = "StormEvents"
	storm_events.weather = self
	add_child(storm_events)
	for band in 3:
		var spec: Dictionary = RainCatalog.BANDS[band]
		for index in int(spec.count):
			var drop := {"point":Vector2.ZERO,"tail":Vector2.ZERO,"band":band,"density_slot":(float(index)+0.5)/float(spec.count),"depth":float(spec.depth),"speed":float(spec.speed)*rng.randf_range(0.88,1.14),"length":float(spec.length)*rng.randf_range(0.80,1.20),"alpha":float(spec.alpha)*rng.randf_range(0.78,1.13)}
			_respawn(drop,true)
			rain.append(drop)
	lightning_wait = rng.randf_range(15,30)

func configure_environment(environment: Dictionary) -> void:
	if is_instance_valid(storm_events): storm_events.reset()
	environment_id = str(environment.get("id","sector07"))
	environment_weather = str(environment.get("weather", "storm"))
	var default_rain := 1.0 if environment_weather in ["rain", "storm"] else 0.0
	rain_base_strength = clampf(float(environment.get("rain_strength", default_rain)), 0.0, 1.0)
	rain_strength = rain_intensity_at(elapsed)
	lightning_enabled = bool(environment.get("lightning", environment_weather == "storm"))
	if is_instance_valid(world_wind):
		world_wind.configure_environment(environment)
	if not lightning_enabled:
		lightning_age = 10.0
		thunder_wait = -1.0
		bolt.clear()
		lightning_branches.clear()
	for layer in rain_layers + [sky_layer]:
		if is_instance_valid(layer):
			layer.queue_redraw()

func _layer(title: String, depth: int, paint: Callable) -> Node2D:
	var layer := Node2D.new()
	layer.name = title
	layer.z_index = depth
	layer.draw.connect(paint)
	add_child(layer)
	return layer

func trace_rain(from: Vector2, to: Vector2, include_actors: bool = true, exclude_actor: Node = null) -> Dictionary:
	return collision.trace(from,to,include_actors,exclude_actor)

func exposure_at(point: Vector2, exclude_actor: Node = null) -> float:
	return collision.exposure_at(point,exclude_actor)

func surface_at(x: float) -> Dictionary:
	return collision.surface_at(x)

func refresh_collision_cache() -> void:
	collision.invalidate()
	_shelter_frame = -1
	_shelter_by_x.clear()

func rain_surface(x: float) -> float:
	# Architectural shelter remains separate from a character/weapon silhouette.
	# A gun intercepts a streak but does not turn its whole vertical column into
	# a permanently dry indoor region.
	var cover := _bunker_surface(x)
	if is_instance_valid(game) and "dome" in game and is_instance_valid(game.dome):
		cover = minf(cover,collision.dome_cover_height(x))
	return cover

func _bunker_surface(x: float) -> float:
	if is_instance_valid(game) and "scenario_bunker" in game and is_instance_valid(game.scenario_bunker):
		var bunker: ScenarioBunker=game.scenario_bunker
		# A service hatch is a real moving cover. Its open shaft cannot inherit
		# the former solid roof silhouette, including at the second flak ladder.
		# Exact x keys preserve narrow steel rims; repeated draw/simulation calls
		# share a result only within this frame or until geometry invalidates it.
		var frame := Engine.get_process_frames()
		if frame != _shelter_frame:
			_shelter_frame = frame
			_shelter_by_x.clear()
		if _shelter_by_x.has(x):
			return float(_shelter_by_x[x])
		_cover_query.from = Vector2(x,-1400)
		_cover_query.to = Vector2(x,1800)
		var hit := get_world_2d().direct_space_state.intersect_ray(_cover_query)
		# Physics may return 429.99997 for a pixel-aligned y430 slab. Keep the
		# architectural boundary stable without coarsening its horizontal holes.
		var cover := snappedf(float(hit.position.y),0.001) if not hit.is_empty() else bunker.ground_y
		_shelter_by_x[x] = cover
		return cover
	if is_instance_valid(game) and "flak_station" in game and is_instance_valid(game.flak_station) and game.flak_station.built and x>=474 and x<=586:
		return 35.0
	if x < 750:
		return ROOF_Y
	if x < 775:
		return 260.0+(x-747.0)*19.0/28.0
	if x < ROOF_EDGE:
		return 279.0+(x-775.0)*45.0/98.0
	return GROUND_Y

func is_outdoors(point: Vector2) -> bool:
	return point.x>=_sky_left() and point.x<_sky_right() and point.y>=_sky_top() and point.y<=rain_surface(point.x)

func _wide_view() -> bool:
	if is_instance_valid(game) and "scenario_bunker" in game and is_instance_valid(game.scenario_bunker): return true
	return is_instance_valid(game) and (("view_stage" in game and game.view_stage>=2) or ("dome" in game and is_instance_valid(game.dome) and game.dome.available))

func _sky_top() -> float:
	return _camera_sky_bounds().position.y if _wide_view() else SKY_TOP

func _sky_left() -> float:
	return _camera_sky_bounds().position.x if _wide_view() else 70.0

func _sky_right() -> float:
	return _camera_sky_bounds().end.x if _wide_view() else 1440.0

func _camera_sky_bounds() -> Rect2:
	# Deeper excavation widens and pans the actual camera. Include its whole sky
	# with a margin, so a late zoom never reveals a motionless strip at an edge.
	var frame:=Engine.get_process_frames()
	if frame==_bounds_frame:
		return _wide_bounds
	_bounds_frame=frame
	var left:=-550.0
	var right:=2250.0
	var top:=-300.0
	if is_instance_valid(game) and "camera" in game and is_instance_valid(game.camera):
		var camera:Camera2D=game.camera
		var center:=camera.get_screen_center_position()
		var half:=get_viewport_rect().size*0.5/camera.zoom
		left=minf(left,center.x-half.x-40.0)
		right=maxf(right,center.x+half.x+40.0)
		top=minf(top,center.y-half.y-30.0)
	_wide_bounds=Rect2(left,top,right-left,GROUND_Y-top)
	return _wide_bounds

func gust_at(point: Vector2, at: float = -1.0) -> float:
	# Compact smooth pulses leave genuine quiet gaps. Their phase travels across
	# the scene; it never depends on camera, player position or random draw order.
	var clock := elapsed if at < 0.0 else at
	var seed_value := posmod(environment_id.hash(), 19)
	var period := 68.0 + float(seed_value % 5)
	var phase := fposmod(clock + float(seed_value % 4) * .45 - (point.x-900.0)/145.0,period)
	var first := _gust_pulse(phase,4.0,9.0,period)
	var second := _gust_pulse(phase,34.0,7.0,period)*.78
	return maxf(first,second)

func _gust_pulse(phase: float, center: float, width: float, period: float) -> float:
	var distance := absf(fposmod(phase-center+period*.5,period)-period*.5)
	return 1.0-smoothstep(width*.12,width,distance)

func wind_at(point: Vector2, at: float = -1.0) -> Vector2:
	var gain := float(preload("res://scripts/world_wind.gd").PROFILES.get(environment_id,preload("res://scripts/world_wind.gd").PROFILES.sector07).gain)
	return Vector2(2.0 + gust_at(point,at)*122.0*gain,0.0)

func wind_speed() -> float:
	return wind_at(Vector2(900,250)).x

func wind_strength() -> float:
	return clampf((wind_speed()-2.0)/122.0,0.0,1.0)

func rain_intensity_at(at: float) -> float:
	if rain_base_strength<=0.0: return 0.0
	var phase := fposmod(at+float(posmod(environment_id.hash(),11)),92.0)
	# Sustained shower, retreat to drizzle, then a second softer shower. The
	# intensity has continuous value and slope at every boundary and loop seam.
	var first := 1.0-smoothstep(10.0,32.0,phase)
	var second := smoothstep(44.0,58.0,phase)*(1.0-smoothstep(65.0,79.0,phase))*.75
	var returning := smoothstep(81.0,92.0,phase)
	return rain_base_strength*(.12+.88*maxf(first,maxf(second,returning)))

func rain_visibility(drop: Dictionary) -> float:
	# Density bands enter over several seconds rather than popping all at once.
	return smoothstep(0.0,.05,rain_strength-float(drop.density_slot))

func flag_flutter() -> float:
	return 0.0 if reduced_effects else gust_at(flag_offset()+Vector2(130,185))*1.4

func thunder_delay(point: Vector2, minimum: float = .34) -> float:
	var listener := Vector2(720,300)
	if is_instance_valid(game) and "audio" in game and is_instance_valid(game.audio):
		var acoustics = game.audio.get("acoustics")
		if is_instance_valid(acoustics): listener = acoustics.listener_position
	# Pixel distance is a perceptual game scale, not a claim of physical metres.
	return clampf(minimum+maxf(0.0,point.distance_to(listener)-480.0)/1050.0,minimum,2.4)

func _play_thunder(point: Vector2) -> void:
	if not is_instance_valid(game): return
	if "audio" in game and is_instance_valid(game.audio):
		# Each peer schedules its own atmospheric presentation. Broadcasting a
		# second game.sound event would duplicate the same thunder on clients.
		game.audio.play_sound_at("thunder",point)
	elif game.has_method("sound"):
		game.sound("thunder")

func _parallax() -> Vector2:
	if is_instance_valid(game) and "scenery" in game and is_instance_valid(game.scenery):
		return game.scenery.offset
	return Vector2.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("weather_toggle"):
		set_reduced_effects(not reduced_effects)
		get_viewport().set_input_as_handled()
		if is_instance_valid(game):
			game.notify(LocaleText.text("Wettereffekte reduziert · F3: wieder einschalten") if reduced_effects else LocaleText.text("Landschaft, Wind und Wetter aktiv · F3: reduzieren"))

func set_reduced_effects(value: bool) -> void:
	reduced_effects = value
	if is_instance_valid(world_wind):
		world_wind.set_reduced(value)
	if value:
		lightning_age = 10.0
		thunder_wait = -1.0
	_last_parallax = _parallax()
	for layer in [sky_layer,wind_layer]+rain_layers:
		if is_instance_valid(layer):
			layer.queue_redraw()

func _respawn(drop: Dictionary, distribute: bool = false) -> void:
	var x := rng.randf_range(_sky_left()+6,_sky_right()-3)
	var ceiling := rain_surface(x)
	var top := _sky_top()
	if distribute:
		var initial_hit := trace_rain(Vector2(x,top),Vector2(x,ceiling))
		if not initial_hit.is_empty():
			ceiling=minf(ceiling,float(initial_hit.position.y))
	var y := rng.randf_range(top,maxf(top+1,ceiling-12)) if distribute else top
	drop.point = Vector2(x,y)
	drop.tail = drop.point

func _process(delta: float) -> void:
	if reduced_effects or get_tree().paused or not is_finite(delta) or delta<=0.0:
		return
	elapsed += delta
	rain_strength = rain_intensity_at(elapsed)
	var parallax := _parallax()
	var parallax_delta := parallax-_last_parallax
	_last_parallax = parallax
	var stage := 2 if _wide_view() else 1
	if stage!=_last_view_stage:
		_last_view_stage=stage
		for drop in rain:
			_respawn(drop,true)
		collision.invalidate()
	for index in rain.size():
		var drop: Dictionary = rain[index]
		if float(drop.density_slot)>=clampf(rain_strength,0,1):
			continue
		var point: Vector2=drop.point
		if not is_outdoors(point):
			_respawn(drop)
			continue
		var spec: Dictionary=RainCatalog.BANDS[int(drop.band)]
		var velocity := Vector2(wind_at(point).x*(0.7+float(drop.band)*0.25),float(drop.speed))
		var next := point+velocity*delta+parallax_delta*float(spec.parallax)
		var hit := trace_rain(point,next)
		if not hit.is_empty():
			_rain_contact(hit,velocity,float(drop.depth))
			_respawn(drop)
		elif next.x>=_sky_right()-1 or next.x<_sky_left() or next.y>rain_surface(next.x)+5:
			_respawn(drop)
		else:
			drop.point=next
			drop.tail=point
	lightning_age+=delta
	if lightning_enabled:
		lightning_wait-=delta
	if lightning_enabled and lightning_wait<=0.0:
		_start_lightning()
	if thunder_wait>=0:
		thunder_wait-=delta
		if thunder_wait<0:
			_play_thunder(thunder_origin)
	sky_layer.queue_redraw()
	wind_layer.queue_redraw()
	for layer in rain_layers:
		layer.queue_redraw()

func _rain_contact(hit: Dictionary, velocity: Vector2, depth: float) -> void:
	contact_count+=1
	if is_instance_valid(surface_effects):
		surface_effects.on_rain_hit(hit,velocity,depth)
	var wetness=hit.get("wetness")
	var collider=hit.get("collider")
	if not is_instance_valid(wetness) and is_instance_valid(collider) and collider is Node:
		wetness=collider.get_node_or_null("Wetness")
	if is_instance_valid(wetness) and wetness.has_method("receive_rain"):
		wetness.receive_rain(RainCatalog.WET_CONTACT*rain_strength,hit.position,hit.normal)

func _start_lightning() -> void:
	if not lightning_enabled or reduced_effects: return
	lightning_wait = rng.randf_range(15,30)
	bolt.clear()
	lightning_branches.clear()
	var view := get_canvas_transform().affine_inverse()*get_viewport_rect()
	var left := maxf(_sky_left()+50.0,view.position.x+50.0) if _wide_view() else 930.0
	var right := minf(_sky_right()-50.0,view.end.x-50.0) if _wide_view() else 1320.0
	if right<=left: return
	var top := maxf(_sky_top(),view.position.y)+8.0 if _wide_view() else _sky_top()+8.0
	var x := rng.randf_range(left,right)
	var length := minf(290.0,rain_surface(x)-top-24.0)
	if length<70.0: return
	for index in 11:
		var fraction := float(index)/10.0
		var point := Vector2(x+sin(fraction*PI)*rng.randf_range(-24,24),top+length*fraction).round()
		if not is_outdoors(point): break
		bolt.append(point)
	if bolt.size()<4:
		bolt.clear()
		return
	for branch_index in 3:
		var origin_index := mini(2+branch_index*2,bolt.size()-2)
		var point := bolt[origin_index]
		var path := PackedVector2Array([point])
		for step in 3:
			var next := (point+Vector2((-1.0 if branch_index%2==0 else 1.0)*rng.randf_range(12,25),rng.randf_range(12,27))).round()
			if not is_outdoors(next): break
			path.append(next)
			point = next
		if path.size()>1: lightning_branches.append(path)
	lightning_age = 0.0
	thunder_origin = bolt[-1]
	thunder_wait = thunder_delay(thunder_origin,.7)

func lightning_strength() -> float:
	if reduced_effects or not lightning_enabled or lightning_age>=0.28:
		return 0.0
	return 1.0 if lightning_age<0.10 else (0.28-lightning_age)/0.18*0.24

func _draw_sky() -> void:
	var bright := lightning_strength()
	if bright <= 0.0 or bolt.size() < 4:
		return
	# Local outdoor illumination avoids flashing the HUD, bunker or underground.
	var tint := Color(0.66, 0.76, 0.89, 0.065 * bright)
	# Sample the real roof, including intact glass, so lightning never paints a
	# flat rectangle across the newly covered bunker or an underground room.
	for x in range(int(maxf(_sky_left(),thunder_origin.x-380)),int(minf(_sky_right(),thunder_origin.x+380)),10):
		var cover := minf(rain_surface(x),minf(rain_surface(x+5),rain_surface(x+10)))
		var left_y := maxf(_sky_top()+1,cover)
		var right_y := left_y
		var column_tint := tint
		column_tint.a *= 1.0-smoothstep(160.0,380.0,absf(float(x)-thunder_origin.x))
		sky_layer.draw_colored_polygon(PackedVector2Array([Vector2(x,_sky_top()),Vector2(x+10,_sky_top()),Vector2(x+10,right_y),Vector2(x,left_y)]),column_tint)
	sky_layer.draw_polyline(bolt, Color(0.58, 0.73, 0.89, 0.22 * bright), 5)
	sky_layer.draw_polyline(bolt, Color(0.84, 0.89, 0.95, 0.67 * bright), 1.4)
	for branch in lightning_branches:
		sky_layer.draw_polyline(branch, Color(0.73, 0.82, 0.90, 0.36 * bright), 1)

func _draw_wind() -> void:
	if not roof_flag_visible(): return
	var clock := 0.0 if reduced_effects else elapsed
	wind_layer.draw_set_transform(flag_offset())
	wind_layer.draw_line(Vector2(110, 244), Vector2(110, 174), Color("152027"), 5)
	wind_layer.draw_line(Vector2(109, 242), Vector2(109, 175), Color("737971"), 2)
	wind_layer.draw_rect(Rect2(105, 240, 10, 5), Color("455052"))
	# Five cloth panels articulate independently; the torn tip follows the gust.
	for panel in 5:
		var corners := flag_panel(panel)
		wind_layer.draw_colored_polygon(corners, Color("793f35").lightened(sin(clock*4.3-panel*.85)*.08*flag_flutter()/1.4))
		wind_layer.draw_line(corners[0],corners[1],Color("a16d51"),1)
		if panel in [1,2]:
			wind_layer.draw_line(corners[0]+Vector2(0,6),corners[1]+Vector2(0,6),Color("b49d76"),2)
	wind_layer.draw_set_transform(Vector2.ZERO)

func roof_flag_visible() -> bool:
	var trip=game.get("expedition") if is_instance_valid(game) else null
	return not (is_instance_valid(trip) and trip.road_open and trip.stage in ["travel","stop","failed"])

func flag_panel(panel: int) -> PackedVector2Array:
	# Drawing and rain interception share the same hanging/wind-stretched cloth.
	var clock := 0.0 if reduced_effects else elapsed
	var gust := flag_flutter()/1.4
	var width := lerpf(2.0,7.0,gust)
	var x := 112.0+panel*width
	var left := (1.0-gust)*panel*3.2+sin(clock*4.3-panel*.85)*panel*.7*flag_flutter()
	var right := (1.0-gust)*(panel+1)*3.2+sin(clock*4.3-(panel+1)*.85)*(panel+1)*.7*flag_flutter()
	return PackedVector2Array([Vector2(x,180+left),Vector2(x+width,180+right),Vector2(x+width,197+right-(5 if panel==4 else 0)),Vector2(x,197+left)])

func flag_offset() -> Vector2:
	if is_instance_valid(game) and "scenario_bunker" in game and is_instance_valid(game.scenario_bunker):
		return Vector2(game.scenario_bunker.room_left-80.0,0)
	return Vector2.ZERO

func _draw_rain_band(band: int) -> void:
	if reduced_effects or rain_strength<=0:
		return
	var layer:Node2D=rain_layers[band]
	var spec:Dictionary=RainCatalog.BANDS[band]
	for index in rain.size():
		var drop:Dictionary=rain[index]
		if int(drop.band)!=band or float(drop.density_slot)>=clampf(rain_strength,0,1):
			continue
		var segment := rain_segment(drop)
		if segment.is_empty():
			continue
		var start:Vector2=segment[0]
		var point:Vector2=segment[1]
		# The bright head trails upward along its already swept motion, so a drawn
		# streak cannot extend beyond a roof just before its next simulation step.
		var tint:=Color(0.57,0.66,0.68,float(drop.alpha)*rain_visibility(drop)*(1.0+lightning_strength()*0.5))
		layer.draw_line(start.round(),point.round(),tint,float(spec.width),false)
		if band==2:
			layer.draw_rect(Rect2(point.round(),Vector2(1,2)),Color(0.76,0.80,0.74,0.38*rain_visibility(drop)))

func rain_segment(drop: Dictionary) -> PackedVector2Array:
	var point:Vector2=drop.point
	if not is_outdoors(point):
		return PackedVector2Array()
	var direction:=Vector2(wind_at(point).x*(0.7+int(drop.band)*0.25),float(drop.speed)).normalized()
	var length:=minf(float(drop.length),maxf(0,point.y-_sky_top()))
	var start:=point-direction*length
	if start.x<_sky_left():
		start=point-direction*minf(length,(point.x-_sky_left())/maxf(0.001,direction.x))
	if not is_outdoors(start):
		start=point
	return PackedVector2Array([start,point])
