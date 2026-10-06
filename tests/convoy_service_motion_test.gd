extends SceneTree
## Tool contacts and repair suspension must remain coherent across progress,
## mirroring, pauses, delayed snapshots and frame cadence.
const VehicleArt := preload("res://scripts/convoy_vehicle_art.gd")
const Presentation := preload("res://scripts/convoy_presentation.gd")
var checks := 0
var failures := 0

class Truck extends Node2D:
	var game: Node
	var facing := 1.0
	var velocity := Vector2.ZERO
	var suspension := 0.0
	var destroyed := false
	var visual := Node2D.new()
	var seats: Array[Node2D] = []
	var journey_state: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	var truck := Truck.new()
	root.add_child(truck)
	truck.add_child(truck.visual)
	var presentation := Presentation.new()
	presentation.name = "ConvoyPresentation"
	truck.add_child(presentation)
	presentation.set_process(false)
	var location := truck.position
	var first_work := {"phase":"repair","repair_step":"jack","repair_work":0.0,"repair_bolts":0,"repair_operator":1,"phase_time":.2}
	for side in [1.0,-1.0]:
		truck.facing = side
		truck.journey_state = first_work.duplicate(true)
		var flat := VehicleArt.repair_visual_state(truck)
		var initial_rear := VehicleArt.body_point(truck,Vector2(-65,-11))
		var initial_front := VehicleArt.body_point(truck,Vector2(56,-11))
		truck.journey_state.repair_work = 1.0
		var lifted := VehicleArt.repair_visual_state(truck)
		var raised_rear := VehicleArt.body_point(truck,Vector2(-65,-11))
		var raised_front := VehicleArt.body_point(truck,Vector2(56,-11))
		check(lifted.hub_position.y<flat.hub_position.y-5 and raised_rear.y<initial_rear.y-5,"Jack raises chassis and rim together for facing%s" % side)
		check(absf(initial_front.y-raised_front.y)<.02,"Service lift pivots around undamaged front contact for facing%s" % side)
		truck.journey_state.repair_step = "remove"
		truck.journey_state.repair_work = 0.0
		var rear_hub: Vector2=VehicleArt.repair_visual_state(truck).hub_position
		var last_distance := 0.0
		var clear_road := true
		var consistent_hub := true
		var monotone := true
		for frame in 121:
			truck.journey_state.repair_work = float(frame)/120.0
			var state := VehicleArt.repair_visual_state(truck)
			var distance: float=absf(state.wheel_position.x-rear_hub.x)
			monotone = monotone and distance>=last_distance
			last_distance = distance
			clear_road = clear_road and state.wheel_position.y+5<=.001
			consistent_hub = consistent_hub and state.hub_position==rear_hub
		check(monotone and consistent_hub and clear_road,"Detached tyre clears road without pulling hub along for facing%s" % side)
		truck.journey_state.repair_step = "fit"
		truck.journey_state.repair_work = 0.0
		var replacement := VehicleArt.repair_visual_state(truck)
		check(is_zero_approx(replacement.wheel_position.y+12),"Round spare starts on road for facing%s" % side)
		truck.journey_state.repair_work = 1.0
		check(VehicleArt.repair_visual_state(truck).wheel_position==rear_hub,"Round spare seats on lifted hub for facing%s" % side)
		truck.journey_state.repair_step = "tighten"
		for bolt in 3:
			truck.journey_state.repair_bolts = bolt
			var state := VehicleArt.repair_visual_state(truck)
			check(VehicleArt.service_tool_point(truck,state)==rear_hub+VehicleArt.SERVICE_STUDS[bolt]*Vector2(side,1),"Wrench contact lands on actual mirrored nut%d for facing%s" % [bolt,side])
		truck.journey_state.repair_step = "lower"
		truck.journey_state.repair_work = 1.0
		var lowered := VehicleArt.repair_visual_state(truck)
		check(lowered.hub_position==Vector2(-65*side,-11) and VehicleArt.body_pose(truck)==Transform2D.IDENTITY,"Lowered repaired shell returns exactly to original pose for facing%s" % side)
		var untouched := truck.journey_state.duplicate(true)
		for unused in 100: VehicleArt.repair_visual_state(truck)
		check(truck.journey_state==untouched and truck.position==location,"Geometry samples never mutate journey/collider position for facing%s" % side)
	truck.facing = 1.0
	truck.journey_state = first_work.duplicate(true)
	var service := VehicleArt.repair_visual_state(truck)
	var grip := VehicleArt.jack_grip(truck,service)
	truck.journey_state.phase_time += 1.0/VehicleArt.JACK_PUMP_RATE
	check(VehicleArt.jack_grip(truck,VehicleArt.repair_visual_state(truck)).distance_to(grip)<.00001,"Pump contacts repeat on shared exact foley cadence")
	truck.journey_state.repair_operator = 0
	check(VehicleArt.jack_grip(truck,VehicleArt.repair_visual_state(truck)).y==-4,"Abandoned jack rests instead of pumping on its own")
	truck.journey_state.repair_operator = 1
	truck.journey_state.repair_step = "lower"
	check(VehicleArt.jack_grip(truck,VehicleArt.repair_visual_state(truck)).y==-4,"Lowering releases pressure with steady handle instead of extending jack again")
	truck.journey_state = first_work.duplicate(true)
	presentation.update_state(0)
	var original := truck.journey_state.duplicate(true)
	presentation.update_state(1.0/120.0)
	var interpolated: float=VehicleArt.repair_visual_state(truck).phase_time
	check(interpolated>float(original.phase_time) and truck.journey_state==original,"Held replica sample smoothly advances visual handle clock without changing authority")
	presentation.update_state(.5)
	check(is_equal_approx(VehicleArt.repair_visual_state(truck).phase_time,float(original.phase_time)+.1),"Stale replica phase extrapolation has a strict two-snapshot bound")
	truck.journey_state.repair_step = "remove"
	truck.journey_state.phase_time = 0.0
	presentation.update_state(0)
	check(VehicleArt.repair_visual_state(truck).phase_time==0.0,"New repair step resets cosmetic clock without previous-stage spillover")
	paused = true
	presentation.update_state(.3)
	check(VehicleArt.repair_visual_state(truck).phase_time==0.0,"Pause freezes cosmetic service clock as well as tools and suspension")
	paused = false
	for index in 7:
		var grounded := true
		for frame in 121:
			var age: float=float(frame)/120.0*1.0
			grounded = grounded and presentation.rubber_offset(index,age,1).y<=-1.0
		check(grounded and presentation.rubber_offset(index,1.5,1).y==-1.0,"Rubber fragment%d has one analytic rebound then settles on road" % index)
	presentation._previous_phase = "driving"
	presentation._previous_speed = 160
	truck.journey_state = first_work.duplicate(true)
	truck.journey_state.phase_time = 0.0
	presentation.update_state(0)
	var origin: Vector2=presentation._burst_origin
	truck.position.x += 50
	presentation.update_state(.1)
	check(presentation._burst_origin==origin and presentation._skid_length<=Presentation.MAX_SKID_LENGTH,"Rupture and skid origins stay world-fixed within a fixed length budget")
	paused = true
	var skid: float=presentation.skid_remaining
	presentation.update_state(.3)
	check(presentation.skid_remaining==skid,"Pause freezes road scrape lifetime with rupture/crew")
	paused = false
	presentation.update_state(3.0)
	check(presentation.skid_remaining==0 and presentation.burst_remaining==0,"All breakdown aftermath expires even after a slow frame")
	presentation._previous_phase = "driving"
	truck.journey_state.phase_time = 20.0
	presentation.update_state(0)
	check(presentation.skid_remaining==0 and presentation.burst_remaining==0,"Delayed old snapshot cannot replay braking decal or air burst")
	truck.free()
	await process_frame
	print("CONVOY SERVICE MOTION: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
