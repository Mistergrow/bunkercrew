extends SceneTree
## Rendering controls must follow actual seats and replicated service state.
const Presentation := preload("res://scripts/convoy_presentation.gd")
const VehicleArt := preload("res://scripts/convoy_vehicle_art.gd")
var checks:=0
var failures:=0

class TestWorker extends Node2D:
	var player_id:=1

class Seat extends Node2D:
	var occupant: Node2D

class Vehicle extends Node2D:
	var game: Node
	var velocity:=Vector2.ZERO
	var facing:=1.0
	var suspension:=0.0
	var destroyed:=false
	var seats: Array[Node2D]=[]
	var visual:=Node2D.new()
	var journey_state: Dictionary={"phase":"garage"}

class World extends Node2D:
	var weather:=Node.new()

func _initialize() -> void: run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2);return
	var world:=World.new()
	root.add_child(world)
	world.add_child(world.weather)
	var vehicle:=Vehicle.new()
	vehicle.game=world
	world.add_child(vehicle)
	vehicle.add_child(vehicle.visual)
	for unused in 4:
		var seat:=Seat.new()
		vehicle.add_child(seat)
		vehicle.seats.append(seat)
	var art:=Presentation.new()
	art.name="ConvoyPresentation"
	vehicle.add_child(art)
	art.set_process(false)
	check(art.process_mode==Node.PROCESS_MODE_PAUSABLE,"Cosmetic child inherits the real game pause")
	check(art.stopped and art.door_open==0,"Unoccupied garage starts with closed doors and stopped wheels")
	var worker:=TestWorker.new()
	world.add_child(worker)
	vehicle.seats[0].occupant=worker
	art.update_state(.1)
	check(art.door_open>0 and art.brake_glow>0,"Boarding actual crew opens the door and sets the parking light")
	for unused in 12: art.update_state(.05)
	check(is_zero_approx(art.door_open),"Door closes after a finite boarding transition")
	vehicle.journey_state.phase="boarding"
	art.update_state(.5)
	check(art.door_open==1,"Replicated boarding phase holds the door even over a slow frame")
	vehicle.journey_state.phase="driving"
	vehicle.velocity.x=100
	art.update_state(.2)
	check(not art.stopped and art.headlight_gain==1,"Road motion follows actual velocity with headlights active")
	check(art.brake_glow==0,"Parking lights release during acceleration")
	vehicle.velocity.x=50
	art.update_state(.1)
	check(art.brake_glow>0,"Real braking lights the rear lamps")
	var before: float=art.brake_glow
	for delta in [NAN,INF,-INF,-1.0]: art.update_state(delta)
	check(art.brake_glow==before,"Invalid cosmetic delta cannot poison animation")
	paused=true
	art.update_state(.2)
	check(art.brake_glow==before,"Explicit replica update also respects pause")
	paused=false
	for step in ["jack","remove","fit","tighten","lower","done"]:
		vehicle.journey_state={"phase":"repair","repair_step":step,"repair_work":.5,"repair_bolts":2,"repair_cursor":.6,"repair_operator":1,"phase_time":2.0}
		check(VehicleArt.journey_state(vehicle).repair_step==step,"Service art reads the authoritative "+step+" step")
	vehicle.destroyed=true
	art.update_state(.4)
	check(art.headlight_gain==0 and art.brake_glow==0,"Destroyed chassis shuts down mechanical lighting")
	vehicle.journey_state={}
	check(VehicleArt.journey_state(vehicle).is_empty(),"Missing journey presentation safely uses garage fallback")
	check(VehicleArt.REGION.position.x>=0 and VehicleArt.REGION.position.y>=0 and VehicleArt.REGION.end.x<=VehicleArt.HULL.get_width() and VehicleArt.REGION.end.y<=VehicleArt.HULL.get_height(),"Authored V2 hull uses an in-bounds immutable source crop")
	world.free()
	await process_frame
	print("CONVOY PRESENTATION: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
