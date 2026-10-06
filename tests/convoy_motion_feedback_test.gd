extends SceneTree
## Cosmetic feedback follows true movement/shot/repair observations without
## taking over anchors, mechanics or replicated state.
const Presentation := preload("res://scripts/convoy_presentation.gd")
const VehicleArt := preload("res://scripts/convoy_vehicle_art.gd")
var checks:=0
var failures:=0

class Weather extends Node:
	var reduced_effects:=false

class World extends Node2D:
	var weather:=Weather.new()

class Seat extends Node2D:
	var occupant: Node2D

class Truck extends Node2D:
	var game: Node
	var velocity:=Vector2.ZERO
	var facing:=1.0
	var suspension:=0.0
	var destroyed:=false
	var seats: Array[Node2D]=[]
	var visual:=Node2D.new()
	var wheel_phase:=0.0
	var flash_tick:=0
	var flash:=.075
	var has_mg:=true
	var aim_angle:=-.1
	var journey_state: Dictionary={"phase":"driving"}
	func gun_origin() -> Vector2: return global_position+Vector2(-7*facing,-77+suspension)
	func service_point() -> Vector2: return global_position+Vector2(-65*facing,-20)

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	var world:=World.new()
	root.add_child(world)
	world.add_child(world.weather)
	var truck:=Truck.new()
	truck.game=world
	truck.position=Vector2(1910,430)
	world.add_child(truck)
	truck.add_child(truck.visual)
	var presentation:=Presentation.new()
	presentation.name="ConvoyPresentation"
	truck.add_child(presentation)
	presentation.set_process(false)
	var pose_30:=Vector2.ZERO
	var pose_120:=Vector2.ZERO
	for rate in [30,120]:
		presentation.body_pitch=0
		presentation.body_heave=0
		presentation._pitch_velocity=0
		presentation._heave_velocity=0
		presentation._load=0
		presentation._motion_speed=0
		truck.velocity=Vector2.ZERO
		for frame in rate:
			truck.velocity.x=160.0*float(frame+1)/rate
			presentation.update_state(1.0/rate)
		var pose:=Vector2(presentation.body_pitch,presentation.body_heave)
		check(pose.x<-.003 and pose.y>.15,"Actual acceleration transfers a bounded load at %d Hz"%rate)
		if rate==30: pose_30=pose
		else: pose_120=pose
	check(absf(pose_30.x-pose_120.x)<.0005 and absf(pose_30.y-pose_120.y)<.035,"Load response remains consistent over 30/120 Hz")
	for frame in 30:
		truck.velocity.x=160.0-float(frame+1)*4.0
		presentation.update_state(1.0/60)
	check(presentation.body_pitch>.002 and presentation.brake_glow>0,"Real deceleration transfers weight toward cab and lights braking")
	truck.velocity=Vector2.ZERO
	for unused in 240: presentation.update_state(1.0/60)
	check(absf(presentation.body_pitch)<.00001 and absf(presentation.body_heave)<.00001,"Stationary chassis fully settles without synthetic idle wobble")
	var anchor:=truck.service_point()
	var gun:=truck.gun_origin()
	var position_before:=truck.position
	var journey_before:=truck.journey_state.duplicate(true)
	presentation.body_pitch=.008
	presentation.body_heave=.4
	var right:=VehicleArt.body_point(truck,Vector2(91,-24))
	truck.facing=-1
	var left:=VehicleArt.body_point(truck,Vector2(91,-24))
	check(is_equal_approx(right.x,-left.x) and is_equal_approx(right.y,left.y),"Cab lamp/door hull pose mirrors with road direction")
	truck.facing=1
	check(truck.position==position_before and truck.service_point()==anchor and truck.gun_origin()==gun and truck.journey_state==journey_before,"Shell feedback cannot move physical chassis, repair/shot anchors or journey state")
	presentation.update_state(.05)
	truck.journey_state={"phase":"repair","repair_step":"jack","phase_time":0.0}
	presentation.update_state(0)
	check(presentation.burst_remaining==Presentation.BURST_DURATION and presentation.tyre_collapse()==0,"Fresh road breakdown starts bounded rear-axle rupture with intact first-frame rubber")
	presentation.update_state(.1)
	check(presentation.tyre_collapse()>0 and presentation.tyre_collapse()<1,"Rear rubber collapses continuously during first tenth-second")
	presentation.update_state(.25)
	check(presentation.tyre_collapse()==1 and presentation.burst_remaining>0,"Tire is visibly collapsed before finite air/rubber aftermath ends")
	var phase_work:=truck.journey_state.duplicate(true)
	truck.journey_state.repair_step="remove"
	truck.journey_state.phase_time=0.0
	var remaining:=presentation.burst_remaining
	presentation.update_state(.05)
	check(is_equal_approx(presentation.burst_remaining,remaining-.05),"Repair stage clock reset cannot replay a fresh rupture")
	check(phase_work.phase==truck.journey_state.phase and truck.position==position_before,"Rupture feedback never advances repair authority")
	presentation.update_state(2.0)
	check(presentation.burst_remaining==0 and presentation.tyre_collapse()==1,"Rupture has finite lifetime even over slow frames")
	presentation._previous_phase="driving"
	truck.journey_state={"phase":"repair","repair_step":"jack","phase_time":.7}
	presentation.update_state(0)
	check(is_equal_approx(presentation.burst_remaining,.25) and presentation.tyre_collapse()==1,"Delayed fresh snapshot starts only the remaining actual rupture time")
	presentation._previous_phase="driving"
	truck.journey_state.phase_time=2.0
	presentation.update_state(0)
	check(presentation.burst_remaining==0,"Old repair snapshot does not replay a tire burst")
	var late_truck:=Truck.new()
	late_truck.game=world
	late_truck.journey_state={"phase":"repair","repair_step":"jack","phase_time":0.0}
	world.add_child(late_truck)
	late_truck.add_child(late_truck.visual)
	var late:=Presentation.new()
	late.name="ConvoyPresentation"
	late_truck.add_child(late)
	late.set_process(false)
	check(late.burst_remaining==0 and late.tyre_collapse()==1,"Late joining an already repairing truck initializes settled geometry")
	truck.journey_state={"phase":"driving"}
	presentation.update_state(.01)
	truck.flash_tick+=1
	presentation.update_state(.01)
	check(presentation._casings.size()==1,"Actual observed MG shot emits one casing")
	var world_origin:=presentation._casings[0]
	truck.position.x+=40
	presentation.update_state(.05)
	check(presentation._casings[0].x==world_origin.x and presentation._casings[0].y==world_origin.y,"Moving truck leaves its brass behind in world space")
	for unused in 20:
		truck.flash_tick+=1
		presentation.update_state(.01)
	check(presentation._casings.size()==Presentation.MAX_CASINGS,"Burst firing uses a strict five-casing memory/render bound")
	var casings_before:=presentation._casings.size()
	truck.flash_tick=0
	presentation.update_state(.01)
	check(presentation._casings.size()==casings_before,"A reset/replaced replica shot counter emits no fake shot")
	paused=true
	var pose_before:=Vector2(presentation.body_pitch,presentation.body_heave)
	var time_before: float=presentation._casings[0].w
	presentation.update_state(.2)
	check(Vector2(presentation.body_pitch,presentation.body_heave)==pose_before and presentation._casings[0].w==time_before,"Pause freezes new motion and real-shot cosmetics")
	paused=false
	for delta in [NAN,INF,-INF,-1.0]: presentation.update_state(delta)
	check(Vector2(presentation.body_pitch,presentation.body_heave)==pose_before and presentation._casings[0].w==time_before,"Invalid frame durations cannot poison suspension or casing ages")
	world.weather.reduced_effects=true
	truck.flash_tick+=1
	presentation.update_state(.01)
	check(presentation._casings.is_empty(),"Reduced-effects setting removes spent brass without muting actual shots")
	world.weather.reduced_effects=false
	truck.flash_tick+=1
	presentation.update_state(.01)
	presentation.update_state(2.0)
	check(presentation._casings.is_empty(),"Spent brass expires independently of further gunfire")
	truck.flash=0
	truck.flash_tick=500
	presentation.update_state(.01)
	check(presentation._casings.is_empty(),"Old restored shot counter with no live flash cannot replay a casing")
	truck.destroyed=true
	truck.journey_state={"phase":"repair","repair_step":"jack","phase_time":0.0}
	presentation.update_state(.1)
	check(presentation.burst_remaining==0 and presentation._casings.is_empty(),"Destroyed vehicle cannot replay repair or weapon cosmetics")
	check(presentation.get_child_count()==1 and presentation.get_node("ServiceDetails")!=null,"Feedback reuses the single existing foreground layer")
	world.free()
	await process_frame
	print("CONVOY MOTION FEEDBACK: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
