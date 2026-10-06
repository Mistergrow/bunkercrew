extends Node2D
## Two distant authored flyby slots read the already replicated vehicle clock.
## No enemy group, collision, ordnance, additional wire state or gameplay timer.
const Catalog := preload("res://scripts/convoy_air_encounter_catalog.gd")
const AircraftArt := preload("res://scripts/aircraft_art.gd")
const AircraftSound := preload("res://scripts/aircraft_audio_catalog.gd")
const HULLS := preload("res://assets/enemies/aircraft_hulls_v1.png")
const CLOUDS := preload("res://assets/cinematics/air_clouds_top_v1.png")
const CLOUD_SHADER := preload("res://shaders/air_intro_cloud.gdshader")
const EXTRAPOLATION := .12
var game: Node
var controller: Node
var aircraft: Array[Node2D] = []
var voices: Array[AudioStreamPlayer2D] = []
var cloud_nodes: Array[Sprite2D] = []
var active_id := ""
var clock := 0.0
var _streams: Dictionary = {}
var _sample := -1.0
var _since_sample := 0.0
var _vehicle_id := 0
var _redraw_clock := 0.0
var _routed_audio := false
var _slot: Dictionary = {}

class DistantAircraft extends Node2D:
	var game: Node
	var kind := "patrol_plane"
	var profile: Dictionary = {}
	var chassis_atlas: Texture2D
	var age := 0.0
	var formation_phase := 0.0
	var flight_velocity := Vector2.ZERO
	var windup := 0.0
	var burst_remaining := 0
	var elite := false
	var hp := 1.0
	var max_hp := 1.0
	var body: Node2D
	var engines: Node2D

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		engines = Node2D.new()
		engines.name = "DistantPropulsion"
		engines.draw.connect(_draw_propulsion)
		add_child(engines)
		body = Node2D.new()
		body.name = "DistantHull"
		body.draw.connect(_draw_hull)
		add_child(body)

	func visual_age() -> float:
		return age

	func _draw_hull() -> void:
		AircraftArt.body(self,body)

	func _draw_propulsion() -> void:
		AircraftArt.propulsion(self,engines)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = 120
	z_index = -6
	z_as_relative = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for index in Catalog.MAX_AIRCRAFT:
		var plane := DistantAircraft.new()
		plane.name = "DistantAircraft%d"%index
		plane.game = game
		plane.chassis_atlas = HULLS
		plane.profile = AirEnemyCatalog.profile("patrol_plane")
		plane.z_index = 1
		plane.visible = false
		add_child(plane)
		aircraft.append(plane)
		var motor := AudioStreamPlayer2D.new()
		motor.name = "DistantMotor%d"%index
		motor.bus = "SFX"
		motor.attenuation = 1.25
		motor.panning_strength = .85
		motor.volume_db = -80.0
		motor.max_polyphony = 1
		add_child(motor)
		voices.append(motor)
	for index in 2:
		var cloud := Sprite2D.new()
		cloud.name = "BackCloudBank" if index==0 else "FrontCloudBank"
		cloud.texture = CLOUDS
		cloud.z_index = 0 if index==0 else 2
		cloud.visible = false
		var cloud_material := ShaderMaterial.new()
		cloud_material.shader = CLOUD_SHADER
		cloud_material.set_shader_parameter("phase",float(index)*1.731)
		cloud.material = cloud_material
		add_child(cloud)
		cloud_nodes.append(cloud)
	tree_exiting.connect(stop_effects)

func _process(delta: float) -> void:
	update_state(delta)

func _eligible() -> bool:
	if not is_instance_valid(game) or game.get("started")!=true or not is_instance_valid(controller): return false
	var vehicle = controller.get("vehicle")
	return controller.get("road_open")==true and controller.get("stage") in ["travel","stop"] and is_instance_valid(vehicle) and not vehicle.is_queued_for_deletion() and vehicle.get("destroyed")!=true and vehicle.get("game")==game and is_instance_valid(game.get("camera"))

func update_state(delta: float) -> void:
	if not is_finite(delta) or delta<0 or (is_inside_tree() and get_tree().paused): return
	if not _eligible():
		stop_effects()
		return
	var vehicle = controller.get("vehicle")
	var sampled: float = float(vehicle.get("animation_time"))
	if not is_finite(sampled) or sampled<0:
		stop_effects()
		return
	var vehicle_id: int = vehicle.get_instance_id()
	if vehicle_id!=_vehicle_id:
		_vehicle_id = vehicle_id
		_sample = -1.0
		_since_sample = 0.0
	if sampled!=_sample:
		_sample = sampled
		_since_sample = 0.0
	else:
		_since_sample = minf(EXTRAPOLATION,_since_sample+delta)
	clock = sampled+_since_sample
	var state = controller.get("state")
	var destination: String = str(state.pending_node) if state!=null else ""
	_slot = Catalog.active(destination,clock,bool(controller.get("stop_done")))
	if _slot.is_empty():
		stop_effects()
		return
	var changed: bool = active_id!=str(_slot.id)
	active_id = str(_slot.id)
	var camera: Camera2D = game.get("camera")
	var size: Vector2 = get_viewport_rect().size/camera.zoom
	var view := Rect2(camera.get_screen_center_position()-size*.5,size)
	var weather = game.get("weather")
	var reduced: bool = is_instance_valid(weather) and weather.get("reduced_effects")==true
	_redraw_clock += delta
	var repaint: bool = changed or _redraw_clock>=(.05 if reduced else 1.0/30.0) or delta==0
	if repaint: _redraw_clock=0.0
	for index in aircraft.size():
		var plane = aircraft[index]
		var pose := Catalog.pose(_slot,index,view)
		if changed:
			plane.kind = str(_slot.kind)
			plane.profile = AirEnemyCatalog.profile(plane.kind)
			plane.profile.body_size = AircraftArtCatalog.hull_size(plane.kind,float(_slot.width))
			plane.formation_phase = float(index)*1.73
		plane.visible = not pose.is_empty() and float(pose.get("alpha",0))>0.001
		if not plane.visible:
			voices[index].stop()
			continue
		plane.global_position = pose.position
		plane.rotation = float(pose.rotation)*(.35 if reduced else 1.0)
		plane.scale = Vector2(float(pose.facing),1)
		plane.modulate = Color(.71,.78,.81,float(pose.alpha)*(.82 if index==0 else .70))
		plane.age = clock
		plane.flight_velocity = pose.velocity
		if repaint:
			plane.body.queue_redraw()
			plane.engines.queue_redraw()
		_update_motor(index,plane,float(pose.alpha))
	_update_clouds(view,reduced)

func _update_clouds(view: Rect2,reduced: bool) -> void:
	var fade := smoothstep(0.0,.75,float(_slot.elapsed))*(1.0-smoothstep(float(_slot.duration)-1.0,float(_slot.duration),float(_slot.elapsed)))
	var environment: String = str(game.scenario_options.get("environment","ash_foundry"))
	var cold: bool = environment in ["frozen_rail_yard","mountain_pass","radar_highlands"]
	var tint := Color("738295") if cold else Color("777b79")
	for index in cloud_nodes.size():
		var cloud := cloud_nodes[index]
		var width := 295.0 if index==0 else 250.0
		# Use a complete UV domain: the shader itself crops a cloud atlas cell.
		# A Sprite region would apply the atlas crop a second time.
		cloud.scale = Vector2.ONE*(width/float(CLOUDS.get_width()))
		cloud.global_position = Vector2(view.get_center().x+(90 if index==0 else -36),430-float(_slot.altitude)+(26 if index==0 else -10))
		cloud.rotation = -.19 if index==0 else .14
		cloud.visible = fade>.001
		var cell: int = posmod(int(_slot.cloud_cell)+index,4)
		var cloud_material: ShaderMaterial = cloud.material
		cloud_material.set_shader_parameter("source_region",Vector4((cell%2)*.5,floorf(float(cell)/2.0)*.5,.5,.5))
		cloud_material.set_shader_parameter("cloud_clock",clock)
		cloud_material.set_shader_parameter("morph_amount",.12 if reduced else .5)
		cloud_material.set_shader_parameter("cloud_tint",Color(tint.r,tint.g,tint.b,fade*(.23 if index==0 else .46)))

func _update_motor(index: int,plane: Node2D,fade: float) -> void:
	var voice := voices[index]
	var audio = game.get("audio")
	if not is_instance_valid(audio) or float(audio.get("sfx_volume"))<=0:
		voice.stop()
		return
	var profile := AircraftSound.profile_for(str(plane.kind))
	if profile.is_empty(): return
	var family: String = str(profile.family)
	if not _streams.has(family):
		var stream: AudioStreamWAV = load(str(profile.stream_path)) as AudioStreamWAV
		if stream==null: return
		stream = stream.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = roundi(stream.get_length()*stream.mix_rate)
		_streams[family] = stream
	if voice.stream!=_streams[family]:
		voice.stop()
		voice.stream = _streams[family]
	voice.global_position = plane.global_position
	voice.max_distance = float(profile.max_distance)
	voice.pitch_scale = float(profile.pitch)*(1.0+.035*sin(float(_slot.progress)*PI))
	var crowd_db := -10.0*log(float(_slot.count))/log(10.0)
	voice.volume_db = float(profile.level_db)+float(profile.gain_db)-5.0+crowd_db+linear_to_db(maxf(.0001,fade))
	if not _routed_audio and audio.get("acoustics")!=null:
		audio.acoustics.route_steps(self)
		_routed_audio = true
	if not voice.playing: voice.play()

func stop_effects() -> void:
	active_id = ""
	for plane in aircraft: plane.visible=false
	for cloud in cloud_nodes: cloud.visible=false
	for voice in voices: voice.stop()

func diagnostics() -> Dictionary:
	var audible := 0
	var visible_planes := 0
	for voice in voices:
		if voice.playing: audible+=1
	for plane in aircraft:
		if plane.visible: visible_planes+=1
	return {"active":active_id,"clock":clock,"visible_aircraft":visible_planes,"playing_motors":audible,"allocated_aircraft":aircraft.size(),"allocated_motors":voices.size(),"cloud_banks":cloud_nodes.size(),"stream_families":_streams.size(),"extrapolation":_since_sample}

func _exit_tree() -> void:
	stop_effects()
	_streams.clear()
