extends SceneTree
## Real solo scene. Initial actor positions and a separate cover control are
## prepared; the rescue itself uses normal physics, gate proximity and aid time.
const Cleanup=preload("res://tests/scene_cleanup.gd")
var game
var patient
var medic
var fence
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	print("PERIMETER RESCUE %s: %s"%["PASS" if value else "FAIL",label])
	if not value:
		failures+=1
		push_error(label)
func frames(count: int=3) -> void:
	for unused in count: await physics_frame
func set_gate(open: bool) -> void:
	fence.gate_open=open
	fence.gate_amount=1.0 if open else 0.0
	fence._gate_hold=0.0
	fence.sync_replica()
func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	game=preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	game.combat_events.persistence_enabled=false
	game.start_scenario(1,{"environment":"sector07","position":"left","build_type":"workshop"})
	game.rounds.set_process(false)
	game.set_process(false)
	game.dialogue.reset()
	game.dialogue.set_process(false)
	patient=game.players[0]
	medic=game.medic
	patient.set_physics_process(false)
	medic.set_physics_process(false)
	for site in game.perimeter.sites:
		site.set_physics_process(false)
		if site.role=="fence": fence=site
	check(is_instance_valid(medic) and is_instance_valid(fence) and game.players.size()==1,"Real solo main scene provides SAN-1 and its outer gate site")
	# Rebuild after destruction before checking the same physical rescue route.
	fence.take_damage(10000)
	patient.global_position=fence.global_position-Vector2(35,0)
	patient.inventory={"steel":2}
	# Pay through the real bounded deposit/assembly API, without assigning tier.
	for index in 45:
		if fence.tier==1: break
		fence.interact(patient,.1)
	check(fence.tier==1 and fence.hp==120 and int(patient.inventory.get("steel",0))==0,"Two carried steel units build one real field gate")
	set_gate(false)
	patient.global_position=fence.global_position+Vector2(24,0)
	medic.global_position=fence.global_position-Vector2(24,0)
	patient.invulnerability=0
	patient.take_damage(12.0)
	patient.knockback=0
	patient.velocity=Vector2.ZERO
	medic.velocity=Vector2.ZERO
	await frames()
	check(fence.collision_layer==3 and fence.is_blocking(),"Closed gate retains actual movement and projectile collision")
	var health_before: float=patient.hp
	var supplies_before: int=medic.medical_supplies
	check(patient.global_position.distance_to(medic.global_position)<=MedicalCatalog.AID_REACH,"Cover control keeps the wounded patient inside normal treatment range")
	check(not medic.navigation.treatment_line(medic.global_position,patient) and not patient.medical.reachable_can_aid(medic),"Both navigation treatment ray and shared medical reach reject the closed gate")
	check(not patient.medical.begin_or_continue_aid(medic,10.0) and patient.hp==health_before and medic.medical_supplies==supplies_before and patient.medical.progress_for(medic)==0,"Blocked treatment cannot heal, advance a channel or spend supplies")
	set_gate(true)
	await frames()
	check(medic.navigation.treatment_line(medic.global_position,patient) and patient.medical.reachable_can_aid(medic),"Opening only the gate permits treatment at the same two positions")
	# Final mission setup. No positions are assigned once physics resumes.
	set_gate(false)
	medic.global_position=fence.global_position-Vector2(100,0)
	patient.global_position=fence.global_position+Vector2(130,0)
	patient.invulnerability=0
	patient.take_damage(1000.0)
	patient.knockback=0
	patient.velocity=Vector2.ZERO
	medic.velocity=Vector2.ZERO
	await frames()
	var patient_start: Vector2=patient.global_position
	var medic_start: Vector2=medic.global_position
	var starting_cargo: Dictionary=patient.inventory.duplicate(true)
	var revives_before: int=medic.revives_completed
	check(patient.is_downed() and not fence.gate_open and fence.is_blocking(),"Rescue starts with KO patient 130px outside and SAN-1 100px inside a closed gate")
	var planned: Array[Dictionary]=medic.navigation.route_to(patient)
	check(not planned.is_empty() and planned.all(func(edge):return edge.kind=="walk"),"Real route planner finds a grounded walking route through the proximity gate")
	check(not medic.navigation.treatment_line(medic.global_position,patient),"Planning permission does not remove physical treatment cover")
	patient.set_physics_process(true)
	fence.set_physics_process(true)
	medic.set_physics_process(true)
	var previous: Vector2=medic.global_position
	var elapsed:=0.0
	var largest_step:=0.0
	var walked:=0.0
	var saw_open_before_crossing:=false
	var crossed_open:=false
	var crossed_closed:=false
	var treated_outside:=false
	var first_treatment:=-1.0
	while elapsed<14.0 and medic.revives_completed==revives_before:
		await physics_frame
		elapsed+=game.get_physics_process_delta_time()
		var point: Vector2=medic.global_position
		var distance:=point.distance_to(previous)
		largest_step=maxf(largest_step,distance)
		walked+=distance
		if fence.gate_open and point.x<fence.global_position.x: saw_open_before_crossing=true
		if previous.x<fence.global_position.x and point.x>=fence.global_position.x:
			crossed_open=fence.gate_open and not fence.is_blocking() and fence.collision_layer==0
			crossed_closed=not crossed_open
		if medic.treating:
			if first_treatment<0: first_treatment=elapsed
			treated_outside=point.x>fence.global_position.x and patient.medical.reachable_can_aid(medic)
		previous=point
	medic.set_physics_process(false)
	check(saw_open_before_crossing and crossed_open and not crossed_closed,"SAN-1 proximity opens the gate before a real collision-safe crossing")
	check(walked>150 and medic.global_position.x>medic_start.x+150 and largest_step<=MedicNavigation.SPEED/float(Engine.physics_ticks_per_second)+.3,"Rescue travel uses bounded physical steps without teleports")
	check(treated_outside and first_treatment>=0 and elapsed-first_treatment>=MedicalCatalog.REVIVE_TIME-.05,"SAN-1 reaches the exterior patient before completing the full five-second treatment")
	check(medic.revives_completed==revives_before+1 and not patient.is_downed() and patient.hp>0,"Actual SAN-1 medical channel revives the KO player")
	check(medic.medical_supplies==supplies_before-1 and patient.inventory==starting_cargo,"Exactly one finite medical charge is spent; player cargo is preserved")
	check(patient.global_position.distance_to(patient_start)<2,"Patient revives at the exterior fall position")
	print("RESCUE TRACE: seconds=%.3f, walk=%.3fpx, max_step=%.3fpx, aid_start=%.3fs, medic=%s, patient=%s"%[elapsed,walked,largest_step,first_treatment,medic.global_position,patient.global_position])
	await Cleanup.free_scene(game,self)
	print("Perimeter rescue: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
