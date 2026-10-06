extends Node2D
## Cosmetic mechanical feedback. Seats and displacement are authoritative;
## this child keeps rendering on replicas without changing vehicle gameplay.
const DOOR_HOLD := .24
const DOOR_SPEED := 4.5
const BURST_DURATION := .95
const LOAD_PITCH := .008
const LOAD_HEAVE := .5
const SPRING_RATE := 9.0
const CASING_DURATION := .72
const MAX_CASINGS := 5
const SKID_DURATION := 2.2
const MAX_SKID_LENGTH := 28.0
const RUBBER_GRAVITY := 85.0
const CASING_PIXELS := [
	[Vector2(-1,0),Vector2(0,0),Vector2(1,0)],
	[Vector2(-1,-1),Vector2(0,0),Vector2(1,1)],
	[Vector2(0,-1),Vector2(0,0),Vector2(0,1)],
	[Vector2(-1,1),Vector2(0,0),Vector2(1,-1)],
]
const VehicleArt := preload("res://scripts/convoy_vehicle_art.gd")
const Journey := preload("res://scripts/convoy_journey.gd")
const REPAIR_PARTS := preload("res://assets/expedition/repair_props_v2.png")
const REPAIR_REGIONS := {"jack":Rect2(104,80,469,514),"wheel":Rect2(708,73,530,527),"toolbox":Rect2(63,805,603,286),"beacon":Rect2(863,674,269,445)}
const PixelArt := preload("res://scripts/pixel_effect_art.gd")
var vehicle: Node2D
var door_open := 0.0
var brake_glow := 0.0
var headlight_gain := 0.0
var stopped := true
var _door_hold := 0.0
var _crew: Array[int] = []
var _previous_speed := 0.0
var _redraw_clock := 0.0
var _service_details: Node2D
var body_pitch := 0.0
var body_heave := 0.0
var burst_remaining := 0.0
var skid_remaining := 0.0
var _burst_origin := Vector2.ZERO
var _burst_facing := 1.0
var _skid_length := 0.0
var _pitch_velocity := 0.0
var _heave_velocity := 0.0
var _load := 0.0
var _motion_speed := 0.0
var _previous_phase := ""
var _previous_flash := -1
var _casings: Array[Vector4] = []
var _service_phase := ""
var _service_step := ""
var _service_sample_time := 0.0
var _service_elapsed := 0.0

func _ready() -> void:
	vehicle=get_parent() as Node2D
	process_mode=Node.PROCESS_MODE_PAUSABLE
	z_index=-1
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	# Light beams stay behind the truck. Small service markings/handle belong
	# in front of its side panel, which used to hide the complete timing rail.
	_service_details=Node2D.new()
	_service_details.name="ServiceDetails"
	_service_details.z_index=2
	_service_details.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	_service_details.draw.connect(_draw_service_details)
	add_child(_service_details)
	update_state(0.0)

func reduced() -> bool:
	var owner_game=vehicle.get("game") if is_instance_valid(vehicle) else null
	var weather=owner_game.get("weather") if is_instance_valid(owner_game) else null
	return is_instance_valid(weather) and weather.get("reduced_effects")==true

func update_state(delta: float) -> void:
	if not is_instance_valid(vehicle) or not is_finite(delta) or delta<0: return
	if is_inside_tree() and get_tree().paused: return
	var current: Array[int]=[]
	for seat in vehicle.seats:
		var worker=seat.occupant
		current.append(int(worker.player_id) if is_instance_valid(worker) else 0)
	if not _crew.is_empty() and current!=_crew and absf(vehicle.velocity.x)<14:
		_door_hold=DOOR_HOLD
	_crew=current
	var journey: Dictionary=VehicleArt.journey_state(vehicle)
	var phase: String=str(journey.get("phase",""))
	_update_service_clock(delta,phase,journey)
	_update_motion(delta,phase,journey)
	_update_casings(delta)
	if phase in ["boarding","reboarding"]:
		_door_hold=maxf(_door_hold,DOOR_HOLD+delta)
	var speed: float=absf(vehicle.velocity.x)
	stopped=speed<3.0
	var braking: bool=speed+1.0<_previous_speed or (stopped and current.any(func(id:int):return id>0))
	brake_glow=move_toward(brake_glow,1.0 if braking and not vehicle.destroyed else 0.0,delta*7.0)
	_previous_speed=speed
	_door_hold=maxf(0.0,_door_hold-delta)
	door_open=move_toward(door_open,1.0 if _door_hold>0 else 0.0,delta*DOOR_SPEED)
	headlight_gain=move_toward(headlight_gain,0.0 if vehicle.destroyed else 1.0,delta*3.0)
	if burst_remaining>0:
		# The sub-second rupture needs the display cadence rather than the 20 Hz
		# service-prop cadence. Both layers still keep a fixed small draw count.
		queue_redraw()
		if is_instance_valid(_service_details): _service_details.queue_redraw()
	_redraw_clock+=delta
	if _redraw_clock>=.05:
		_redraw_clock=fmod(_redraw_clock,.05)
		queue_redraw()
		if is_instance_valid(_service_details): _service_details.queue_redraw()
		if is_instance_valid(vehicle.visual): vehicle.visual.queue_redraw()
		vehicle.queue_redraw()

func _update_service_clock(delta: float, phase: String, state: Dictionary) -> void:
	var step: String=str(state.get("repair_step","none"))
	var sample: float=float(state.get("phase_time",0.0))
	if phase!=_service_phase or step!=_service_step or not is_equal_approx(sample,_service_sample_time):
		_service_elapsed=0.0
		_service_phase=phase
		_service_step=step
		_service_sample_time=sample
	elif phase=="repair" and not vehicle.destroyed:
		# Display-rate interpolation of a 20 Hz replicated phase. A stale peer
		# can extrapolate at most two snapshots; never invent elapsed work.
		_service_elapsed=minf(.1,_service_elapsed+delta)

func service_clock(state: Dictionary) -> float:
	var sample: float=float(state.get("phase_time",0.0))
	if str(state.get("phase",""))==_service_phase and str(state.get("repair_step","none"))==_service_step and is_equal_approx(sample,_service_sample_time):
		return sample+_service_elapsed
	return sample

func _update_motion(delta: float, phase: String, journey: Dictionary) -> void:
	# The first observed repair is a late join/load, not a freshly popped tyre.
	# Reading the phase transition works on the host and snapshot replicas and
	# never adds another journey event or alters movement/service authority.
	var fresh: bool=phase=="repair" and _previous_phase=="driving" and journey.get("repair_step","")=="jack" and not vehicle.destroyed
	if fresh:
		var age:=maxf(0.0,float(journey.get("phase_time",0)))
		burst_remaining=maxf(0.0,BURST_DURATION-age)
		skid_remaining=maxf(0.0,SKID_DURATION-age)
		_burst_origin=vehicle.to_global(Vector2(VehicleArt.WHEELS[0]*vehicle.facing,0))
		_burst_facing=vehicle.facing
		_skid_length=minf(MAX_SKID_LENGTH,maxf(_previous_speed,absf(_motion_speed))*.16)
		_heave_velocity=4.0*burst_remaining/BURST_DURATION
		_pitch_velocity=-.045*burst_remaining/BURST_DURATION
	_previous_phase=phase
	if vehicle.destroyed or phase!="repair": burst_remaining=0.0
	if vehicle.destroyed: skid_remaining=0.0
	elif not fresh: skid_remaining=maxf(0.0,skid_remaining-delta)
	if delta<=0 or not is_finite(float(vehicle.velocity.x)): return
	var speed: float=vehicle.velocity.x
	var acceleration: float=clampf((speed-_motion_speed)/delta*vehicle.facing,-240,240)
	_motion_speed=speed
	_load=lerpf(_load,acceleration/240.0,1.0-exp(-delta*8.0))
	var moving: bool=absf(speed)>3 and not vehicle.destroyed
	var pitch_target: float=-_load*LOAD_PITCH if moving else 0.0
	var heave_target: float=absf(_load)*LOAD_HEAVE if moving else 0.0
	var pitch:=_spring(body_pitch,_pitch_velocity,pitch_target,delta)
	var heave:=_spring(body_heave,_heave_velocity,heave_target,delta)
	body_pitch=clampf(pitch.x,-.014,.014)
	_pitch_velocity=pitch.y
	body_heave=clampf(heave.x,-.8,.8)
	_heave_velocity=heave.y
	if not fresh: burst_remaining=maxf(0,burst_remaining-delta)

func _update_casings(delta: float) -> void:
	var raw_tick: Variant=vehicle.get("flash_tick")
	var tick: int=int(raw_tick) if raw_tick!=null else 0
	var raw_flash: Variant=vehicle.get("flash")
	var fired: bool=raw_flash!=null and float(raw_flash)>0
	# Reuse a tiny bounded list. Positions are world-fixed so a moving truck
	# drives away from its own spent brass rather than towing particles along.
	for index in range(_casings.size()-1,-1,-1):
		_casings[index].w+=delta
		if _casings[index].w>=CASING_DURATION: _casings.remove_at(index)
	if reduced() or vehicle.destroyed:
		_casings.clear()
	elif fired and _previous_flash>=0 and tick>_previous_flash and vehicle.get("has_mg")==true and vehicle.has_method("gun_origin"):
		var origin: Vector2=vehicle.gun_origin()+Vector2(8,5).rotated(float(vehicle.get("aim_angle")))
		if _casings.size()>=MAX_CASINGS: _casings.pop_front()
		_casings.append(Vector4(origin.x,origin.y,vehicle.facing,0))
	_previous_flash=tick

func _spring(value: float, speed: float, target: float, delta: float) -> Vector2:
	# Analytic critically damped spring: no frame-rate-dependent integration or
	# permanent idle jitter, including a slow frame after a snapshot arrives.
	var displacement:=value-target
	var impulse:=speed+SPRING_RATE*displacement
	var decay:=exp(-SPRING_RATE*delta)
	return Vector2(target+(displacement+impulse*delta)*decay,(speed-SPRING_RATE*impulse*delta)*decay)

func tyre_collapse() -> float:
	return clampf((BURST_DURATION-burst_remaining)/.22,0,1) if burst_remaining>0 else 1.0

func boarding_feedback() -> void:
	# Optional authoritative/replica hook; the seat-change observer is a fallback.
	_door_hold=DOOR_HOLD
	door_open=maxf(door_open,.25)
	queue_redraw()

func _process(delta: float) -> void:
	update_state(delta)

func _draw() -> void:
	if is_instance_valid(_service_details): _service_details.queue_redraw()
	if not is_instance_valid(vehicle) or vehicle.destroyed: return
	var side: float=vehicle.facing
	var front:=VehicleArt.body_point(vehicle,Vector2(91,-24))
	if headlight_gain>0:
		# Source geometry stays attached to the moving cab. Two broad triangles,
		# rather than many lights or a fullscreen post effect, keep the cost fixed.
		if not reduced():
			var beam:=PackedVector2Array([front,front+Vector2(180*side,24),front+Vector2(180*side,-16)])
			draw_polygon(beam,PackedColorArray([Color(.93,.76,.42,.15*headlight_gain),Color(.93,.76,.42,0),Color(.93,.76,.42,0)]))
			var pool:=PackedVector2Array([Vector2(98*side,-1),Vector2(238*side,-1),Vector2(195*side,5),Vector2(122*side,5)])
			draw_colored_polygon(pool,Color(.81,.70,.43,.055*headlight_gain))
		draw_rect(Rect2(front+Vector2(-2,-2),Vector2(4,4)),Color(.98,.86,.59,headlight_gain))
	if brake_glow>0:
		draw_rect(Rect2(VehicleArt.body_point(vehicle,Vector2(-96,-24))-Vector2(1,0),Vector2(3,6)),Color(.84,.21,.12,.4+.6*brake_glow))
	var journey: Dictionary=VehicleArt.journey_state(vehicle)
	if skid_remaining>0.0: _draw_skid()
	if journey.get("phase","")=="repair": _draw_repair(journey)

func _draw_skid() -> void:
	# One finite, world-fixed braking mark: a stopped/returning truck cannot
	# tow the scrape along with it, nor accumulate permanent decal nodes.
	if _skid_length<3.0: return
	var point:=to_local(_burst_origin).round()
	var age: float=SKID_DURATION-skid_remaining
	var fade: float=minf(1.0,skid_remaining/.45)
	var length: float=_skid_length*clampf(age/.12,0,1)
	for index in 7:
		var fraction: float=float(index)/7.0
		var at:=point+Vector2(-_burst_facing*length*fraction,index%2)
		draw_rect(Rect2(at.round(),Vector2(maxf(1.0,roundf(length/7.0)),1)),Color(.08,.12,.105,fade*.6))
		if index%2==0:
			draw_rect(Rect2((at+Vector2(0,-1)).round(),Vector2(2,1)),Color(.31,.32,.25,fade*.4))

func _draw_repair(state: Dictionary) -> void:
	var side: float=vehicle.facing
	var x: float=VehicleArt.WHEELS[0]*side
	var service := VehicleArt.repair_visual_state(vehicle)
	if not service.active: return
	var foot:=Vector2(x+17*side,0)
	var top:=VehicleArt.body_point(vehicle,Vector2(VehicleArt.WHEELS[0]+17,-9)).round()
	var ink:=Color("182323")
	var brass:=Color("baa06c")
	# Fixed hydraulic housing, planted base and extending piston. Stretching a
	# complete bottle-jack image also stretched its foot and suggested no lift.
	var jack: Rect2=REPAIR_REGIONS.jack
	var base:=Rect2(jack.position+Vector2(0,433),Vector2(365,81))
	var housing:=Rect2(jack.position+Vector2(76,146),Vector2(157,284))
	draw_texture_rect_region(REPAIR_PARTS,Rect2(foot+Vector2(-8,-3),Vector2(16,3)),base)
	draw_rect(Rect2(Vector2(foot.x-1,top.y+1),Vector2(2,maxf(1,-6-top.y))),Color("adb2a0"))
	draw_texture_rect_region(REPAIR_PARTS,Rect2(foot+Vector2(-3,-8),Vector2(6,6)),housing)
	draw_rect(Rect2(top+Vector2(-4,-1),Vector2(8,2)),ink)
	draw_line(top+Vector2(-3,-1),top+Vector2(3,-1),brass,1,false)
	draw_rect(Rect2(foot+Vector2(3*side,-5),Vector2(2,2)),Color("ad8754"))
	# The undamaged middle wheel has a physical-looking parking chock. Its
	# painted edge is restrained like the surrounding bunker equipment.
	var chock := Vector2((VehicleArt.WHEELS[1]-14)*side,0)
	draw_set_transform(chock,0,Vector2(side,1))
	draw_colored_polygon(PackedVector2Array([Vector2(-7,0),Vector2(0,-6),Vector2(2,0)]),ink)
	draw_colored_polygon(PackedVector2Array([Vector2(-5,-1),Vector2(0,-5),Vector2(1,-1)]),Color("7d805f"))
	draw_line(Vector2(-4,-1),Vector2(-1,-4),brass,1,false)
	draw_set_transform(Vector2.ZERO)
	var kit:=Vector2(x-49*side,-13)
	draw_texture_rect_region(REPAIR_PARTS,Rect2(kit,Vector2(28,13.28)),REPAIR_REGIONS.toolbox)
	var pulse: float=.75+.25*sin(float(state.get("phase_time",0))*TAU*.85)
	draw_texture_rect_region(REPAIR_PARTS,Rect2(x-66*side,-24,13,21.5),REPAIR_REGIONS.beacon,Color(pulse,pulse,pulse))

func _draw_service_details() -> void:
	if not is_instance_valid(vehicle) or vehicle.destroyed: return
	if burst_remaining>0: _draw_tyre_burst()
	var service := VehicleArt.repair_visual_state(vehicle)
	if not service.active: return
	var side: float=vehicle.facing
	var x: float=VehicleArt.WHEELS[0]*side
	var ink:=Color("182323")
	var olive:=Color("7f8c68")
	var brass:=Color("baa06c")
	if service.step in ["jack","lower"]:
		var pivot:=Vector2(x+21*side,-5)
		var grip:=VehicleArt.jack_grip(vehicle,service)
		_service_details.draw_line(pivot,grip,ink,3,false)
		_service_details.draw_line(pivot,grip,Color("929c87"),1,false)
		_service_details.draw_rect(Rect2(grip-Vector2(2,1),Vector2(4,3)),Color("6e4f35"))
	var center:=Vector2(x,-39)
	# Three actual nuts are shown on the rim by VehicleArt. Only the necessary
	# timing cue sits above the work point; the HUD already shows held work.
	if service.step=="tighten":
		for index in 3:
			_service_details.draw_rect(Rect2(center+Vector2(-6+index*5,-8),Vector2(3,3)),brass if index<int(service.bolts) else ink)
		_service_details.draw_line(center+Vector2(-12,-16),center+Vector2(12,-16),ink,3,false)
		_service_details.draw_line(center+Vector2(-12+24*Journey.TIMING_START,-16),center+Vector2(-12+24*Journey.TIMING_END,-16),olive,3,false)
		_service_details.draw_rect(Rect2(center+Vector2(-12+24*float(service.cursor),-19),Vector2(2,6)),brass)

func _draw_tyre_burst() -> void:
	var side: float=_burst_facing
	var origin:=_service_details.to_local(_burst_origin)
	var age: float=BURST_DURATION-burst_remaining
	var fade: float=clampf(1-age/BURST_DURATION,0,1)
	# A small fixed set of rubber flecks and escaping-air streaks stays at the
	# actual failed axle. Reduced effects retains only three rubber fragments.
	var fewer:=reduced()
	var count: int=3 if fewer else 7
	for index in count:
		var point: Vector2=origin+rubber_offset(index,age,side)
		var size:=Vector2(2+index%2,1+index%2)
		_service_details.draw_rect(Rect2(point.round(),size),Color(.13,.17,.16,fade))
		if index%2==0:
			_service_details.draw_rect(Rect2(point.round()+Vector2.ONE,Vector2.ONE),Color(.32,.35,.27,fade*.7))
		if age<.3 and not fewer:
			var impulse: float=clampf((age-.025)/.2,0,1)
			var end:=origin+Vector2(-side*(6+index*3)*impulse,-8-(index%3)*4*impulse)
			_service_details.draw_line((end-Vector2(-side*4,1)).round(),end.round(),Color(.64,.68,.62,fade*.6),1,false)
	if not fewer:
		for index in 4:
			var delay: float=index*.055
			var dust_age: float=maxf(0,age-delay)
			var point:=origin+Vector2(-side*(7+index*9)*dust_age,-2-dust_age*(3+index%2*3))
			if age>delay:
				PixelArt.puff(_service_details,point,2+dust_age*6,Color(.49,.49,.38,fade*.3),index,false)
		if age<.12:
			var at:=origin+Vector2(-8*side,-6)
			_service_details.draw_polyline(PackedVector2Array([(at+Vector2(-3,0)).round(),(at+Vector2(0,-2)).round(),(at+Vector2(3,1)).round()]),Color(.73,.69,.52,fade*.7),1,false)

func rubber_offset(index: int, age: float, side: float) -> Vector2:
	# One analytic rebound, then grounded rubber. A frame skipped across the
	# contact still samples the same trajectory; no per-particle physics/areas.
	var speed: float=12.0+float(index%3)*9.0
	var contact: float=(speed+sqrt(speed*speed+16.0*RUBBER_GRAVITY))/RUBBER_GRAVITY
	var y: float=-8.0-speed*age+.5*RUBBER_GRAVITY*age*age
	if age>=contact:
		var after: float=age-contact
		var rebound: float=(RUBBER_GRAVITY*contact-speed)*.27
		y=minf(0.0,-rebound*after+.5*RUBBER_GRAVITY*after*after)
	return Vector2(-side*(12.0+float(index)*7.0)*age,y-1.0)

func draw_weapon_debris(node: Node2D) -> void:
	# The existing articulated gun layer is ahead of mounted crew; drawing
	# brass on the low service layer hid every casing behind the gunner's coat.
	for casing: Vector4 in _casings:
		var age: float=casing.w
		var start:=Vector2(casing.x,casing.y)
		var point:=node.to_local(start+Vector2(-casing.z*19*age,-10*age+70*age*age))
		# The trajectory stays analytic and world-fixed. Discrete authored brass
		# clusters tumble without turning a thin native pixel into a soft sliver.
		var pose: Array=CASING_PIXELS[posmod(roundi(age*9/(PI*.25)),CASING_PIXELS.size())]
		for offset: Vector2 in pose:
			node.draw_rect(Rect2(point.round()+offset*Vector2(casing.z,1),Vector2.ONE),Color("e4c888") if offset==Vector2.ZERO else Color("bc9959"))
