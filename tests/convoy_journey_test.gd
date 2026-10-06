extends SceneTree
## Bounded repair state plus real vehicle/seat authority and ownership guards.
const Journey := preload("res://scripts/convoy_journey.gd")
const Vehicle := preload("res://scripts/convoy_vehicle.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

class Room extends Node:
	var active := false
	var is_host := true
	var local_player_id := 1
	var connected := [1,2]
	func is_player_connected(id: int) -> bool: return id in connected

class Fixture extends Node2D:
	var network: Node
	var upgrades: Node
	var medic: Node2D
	var players: Array = []
	var started := true
	func sound_at(_kind: String,_point: Vector2) -> void: pass

class Crew extends CharacterBody2D:
	var game: Node
	var player_id := 1
	var mounted_turret: Node2D
	var facing := 1.0
	var character_id := "mara"
	var climbing := false
	var mining := false
	var inventory: Dictionary = {}
	var active := true
	var downed := false
	@warning_ignore("unused_private_class_variable")
	var _interacting := false
	func can_act() -> bool: return active and not downed
	func is_downed() -> bool: return downed
	func carried_count() -> int: return 0
	func action(kind: String) -> String: return "p%d_%s" % [player_id,kind]

class Medic extends Node2D:
	var game: Node

func _initialize() -> void: run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	print("JOURNEY %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures += 1
		push_error(label)

func hold_step(data: Dictionary, step: String) -> void:
	var budget := 500
	while data.phase=="repair" and data.repair_step==step and budget>0:
		Journey.advance(data,.05)
		Journey.service(data,.05,false,true,1)
		budget -= 1
	check(budget>0,"Holding E completes " + step + " within a finite budget")
	check(Journey.valid_state(data),"Completed " + step + " preserves the replication contract")

func pure_state() -> void:
	var data := Journey.new_state()
	check(Journey.valid_state(data),"Fresh garage state validates")
	check(Journey.valid_state(Journey.new_state("starting",true)),"Old secured-stop resume validates without another flat tire")
	check(Journey.breakdown_required("harbor") and not Journey.breakdown_required("power_station"),"First harbor journey has a flat; authored quieter routes omit it")
	for mutation in [{"phase_time":NAN},{"repair_work":INF},{"repair_operator":5},{"event_serial":1000000001},{"phase":"teleport"},{"repair_bolts":4},{"solo_assist":true}]:
		var malformed := data.duplicate(true)
		malformed.merge(mutation,true)
		check(not Journey.valid_state(malformed),"Malformed journey value is rejected: " + str(mutation.keys()[0]))
	var unchanged := data.duplicate(true)
	Journey.advance(data,NAN)
	Journey.advance(data,-1)
	check(data==unchanged,"Nonfinite and negative clock advances are ignored")
	Journey.advance(data,10)
	check(is_equal_approx(float(data.phase_time),.1),"Long frames cannot skip a boarding or repair window")
	data.phase_time=Journey.MAX_CLOCK
	Journey.advance(data,.1)
	check(data.phase_time==Journey.MAX_CLOCK,"Runtime clocks remain within the finite wire cap")
	check(not Journey.begin_breakdown(data),"Garage cannot create a roadside breakdown")
	Journey.change_phase(data,"driving")
	check(Journey.begin_breakdown(data) and data.repair_step=="jack","Driving enters one concrete tire repair")
	check(not Journey.begin_breakdown(data),"Repeated contact cannot create duplicate breakdowns")
	unchanged=data.duplicate(true)
	check(not Journey.service(data,.2,false,true,1) and not Journey.service(data,.05,false,true,0) and not Journey.service(data,.05,false,false,1) and data==unchanged,"Invalid delta, operator and idle input cannot advance tools")
	hold_step(data,"jack")
	hold_step(data,"remove")
	hold_step(data,"fit")
	check(data.repair_step=="tighten" and data.repair_bolts==0,"Fitted wheel requires three distinct fasteners")
	data.repair_cursor=.2
	var before := int(data.event_serial)
	check(not Journey.service(data,.05,true,true,1) and data.repair_bolts==0 and data.event_serial==before+1,"Early rhythm tap gives bounded feedback without loosening or inventing a bolt")
	before=int(data.event_serial)
	check(not Journey.service(data,.05,true,true,1) and data.event_serial==before,"Retry cooldown prevents key-spam sound bursts")
	data.repair_retry=0.0
	data.repair_cursor=.7
	check(Journey.service(data,.05,true,false,1) and data.repair_bolts==1 and data.events.back().quality=="good","A tap inside the displayed window fastens one bolt")
	hold_step(data,"tighten")
	check(data.repair_bolts==3 and data.repair_step=="lower","Hold fallback finishes the other two bolts without rhythm precision")
	hold_step(data,"lower")
	check(data.phase=="reboarding" and data.breakdown_done and data.repair_operator==0,"Lowering ends repair and clears its operator")
	Journey.change_phase(data,"driving","engine_start")
	check(not Journey.begin_breakdown(data),"Completed journey never repeats its flat tire")
	for index in 50: Journey.event(data,"bolt")
	check(data.events.size()==Journey.MAX_EVENTS and Journey.valid_state(data),"Long event histories stay bounded and retain the last monotonic serial")
	var bad := data.duplicate(true)
	bad.events[1].serial=bad.events[0].serial
	check(not Journey.valid_state(bad),"Duplicate event serials cannot replay audio after reconnect")
	bad=data.duplicate(true)
	bad.events.back().serial-=1
	check(not Journey.valid_state(bad),"An event history must reach its advertised latest serial")
	data.event_serial=Journey.MAX_SERIAL
	data.events=[{"serial":Journey.MAX_SERIAL,"kind":"bolt","quality":"normal"}]
	Journey.event(data,"failed")
	check(data.event_serial==Journey.MAX_SERIAL and Journey.valid_state(data),"Event counter cannot overflow the network bound")

func run() -> void:
	if not "--no-profile-save" in OS.get_cmdline_user_args() or not "--no-upnp" in OS.get_cmdline_user_args(): quit(2); return
	pure_state()
	var game := Fixture.new()
	root.add_child(game)
	var room := Room.new()
	game.network=room
	game.add_child(room)
	var van := Vehicle.new()
	van.game=game
	game.add_child(van)
	van.set_physics_process(false)
	van.configure_trip(Vector2(1000,430),Vector2(740,3700),{"hp":600,"fuel":12})
	var crew := Crew.new()
	crew.game=game
	game.add_child(crew)
	game.players=[crew]
	crew.position=van.position
	check(van.board(crew),"Actual driver enters the real vehicle")
	van.journey_state=Journey.new_state("driving")
	check(van.begin_breakdown() and not is_instance_valid(crew.mounted_turret),"Actual breakdown stops motion and ejects its repairer")
	check(van.can_service(crew) and absf(crew.position.x-van.position.x)>91,"Driver reaches the rear service point outside the real chassis collider")
	check(van.work_uses_real_time() and van.service_point()==van.position+Vector2(-65,-20),"Tools use the common timing clock and actual authored wheel anchor")
	check(not van.passenger_left_seat.can_interact(crew),"Rear seat cannot steal the tire interaction")
	var fuel := van.fuel
	await physics_frame
	van.service_action(crew,.05,false,true)
	var work := float(van.journey_state.repair_work)
	van.service_action(crew,.05,false,true)
	check(work>0 and van.journey_state.repair_work==work,"One physics frame credits held work exactly once")
	check(van.journey_state.solo_assist,"Real solo input enables the assist request")
	van._service_frame=-100
	van._advance_solo_assist(.05)
	check(van.journey_state.repair_work==work,"Absent SAN cannot produce invisible repair progress")
	var medic := Medic.new()
	medic.game=game
	game.add_child(medic)
	game.medic=medic
	medic.position=van.service_point()+Vector2(0,20)
	# A human and SAN share one tool-credit slot per real physics frame.
	await physics_frame
	van._advance_solo_assist(.05)
	check(van.journey_state.repair_work>work and van.journey_state.repair_operator==0,"Real nearby SAN holds tools while solo worker defends")
	work=float(van.journey_state.repair_work)
	van._advance_solo_assist(.05)
	check(van.journey_state.repair_work==work,"SAN and humans share a single tool advance in each physics frame")
	medic.position.x-=100
	await physics_frame
	van._advance_solo_assist(.05)
	check(van.journey_state.repair_work==work,"Distant SAN cannot finish the tire remotely")
	medic.position=van.service_point()+Vector2(0,20)
	crew.position.x-=500
	await physics_frame
	van._advance_solo_assist(.05)
	check(van.journey_state.repair_work==work,"Leaving the convoy also stops solo tool assistance")
	crew.position=van.service_point()+Vector2(-50,20)
	var second := Crew.new()
	second.game=game
	second.player_id=2
	second.active=false
	game.add_child(second)
	game.players.append(second)
	check(van._solo_worker()==null,"A stunned second crew member still prevents solo classification")
	second.set_meta("network_departed",true)
	check(van._solo_worker()==crew,"Explicit departure allows the remaining real player to recover")
	var foreign := Crew.new()
	foreign.game=Node.new()
	game.add_child(foreign.game)
	game.add_child(foreign)
	foreign.position=crew.position
	check(not van.can_service(foreign) and not van.passenger_right_seat.enter(foreign),"Foreign-world worker cannot operate tools or seats")
	foreign.game=game
	check(not van.can_service(foreign),"An unregistered own-world bystander cannot repair")
	game.players.append(foreign)
	foreign.queue_free()
	check(not van.can_service(foreign),"Queued worker cannot receive repair ownership")
	game.players.erase(foreign)
	room.active=true
	room.is_host=false
	work=float(van.journey_state.repair_work)
	check(not van.service_action(crew,.05,true,true),"Guest cannot commit a repair action locally")
	van._physics_process(.05)
	check(van.journey_state.repair_work==work,"Guest physics cannot advance host repair state")
	room.active=false
	van._physics_process(NAN)
	check(van.journey_state.repair_work==work and van.fuel==fuel,"Nonfinite physics and stationary repair cannot spend travel fuel")
	check(is_instance_valid(van.get_node_or_null("ConvoyPresentation")),"Gameplay installs the independently processed cosmetic helper")
	await Cleanup.free_scene(game,self)
	print("CONVOY JOURNEY CHECKS: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
