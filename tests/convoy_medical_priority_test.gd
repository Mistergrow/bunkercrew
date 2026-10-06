extends SceneTree
## Real SAN medical channel beside an active solo wheel, with finite charges.
const Journey := preload("res://scripts/convoy_journey.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	print("CONVOY MEDICAL %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)

func run() -> void:
	if not "--no-profile-save" in OS.get_cmdline_user_args() or not "--no-upnp" in OS.get_cmdline_user_args(): quit(2);return
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.start_scenario(1,{"environment":"ash_foundry","position":"center","build_type":"bastion"})
	game.rounds.running=false
	game.rounds.set_process(false)
	game.rounds.wave=20
	check(game.expedition.on_victory(),"Actual siege victory provides a safe finite convoy")
	game.campaign.select_destination("harbor")
	game.campaign.begin_journey()
	game.expedition._start_road()
	game.expedition.set_physics_process(false)
	game.set_process(false)
	var truck=game.expedition.vehicle
	var worker=game.players[0]
	var medic=game.medic
	truck.set_physics_process(false)
	worker.set_physics_process(false)
	worker.get_node("WorkerWeapon").set_physics_process(false)
	medic.set_physics_process(false)
	Journey.change_phase(truck.journey_state,"driving")
	truck.begin_breakdown()
	# A legal far-rear tool stance places SAN's right-hand medical stance outside
	# the van while still within the actual wheel's64px assist radius.
	worker.position=truck.service_point()+Vector2(-77,20)
	worker.hp=worker.max_hp-8
	worker.medical.state="wounded"
	worker.medical.bleeding=0
	worker.velocity=Vector2.ZERO
	worker.hurt_stun=0
	worker.invulnerability=0
	medic.position=worker.position+Vector2(36,0)
	medic.medical_supplies=1
	for frame in 3: await physics_frame
	check(truck.can_service(worker),"Wounded actual worker remains in legitimate tire interaction reach")
	truck.service_action(worker,.05,false,true)
	truck._service_frame=-100
	# The human's tool attempt owns this frame. Test medical exclusion on a
	# subsequent frame so the medical guard, rather than the frame gate, decides.
	await physics_frame
	# Prepare a valid in-progress medical stance with the production channel,
	# including snapshots from before SAN's preferred outside stance changed.
	medic.target=worker
	medic.velocity=Vector2.ZERO
	worker.medical.begin_or_continue_aid(medic,.05)
	medic.treating=worker.medical.progress_for(medic)>0
	check(medic.treating and medic.target==worker and worker.medical.progress_for(medic)>0,"Actual SAN starts the real bounded medical channel beside the wheel")
	check((medic.position-Vector2(0,20)).distance_to(truck.service_point())<64,"Medical treatment occurs inside the genuine tool-assist range")
	var work: float=truck.journey_state.repair_work
	truck._advance_solo_assist(.05)
	check(truck.journey_state.repair_work==work,"Medical treatment cannot secretly repair the tire in parallel")
	medic.treating=false
	truck._advance_solo_assist(.05)
	check(truck.journey_state.repair_work==work,"An active medical approach target also reserves SAN's hands")
	worker.medical.interrupt()
	worker.hp=worker.max_hp
	worker.medical.state="healthy"
	medic._physics_process(1.0/60)
	truck._advance_solo_assist(.05)
	check(not is_instance_valid(medic.target) and truck.journey_state.repair_work>work,"Finished medical priority releases the robot back to its real tool job")
	check(medic.medical_supplies==1,"Interrupted treatment and tool work never spend or refill a medical charge")
	# Start at the ordinary driver exit with SAN physically stowed on the van's
	# opposite side. The production AI must find an outside, unobstructed stance.
	worker.position=truck.service_point()+Vector2(-50,20)
	worker.hp=worker.max_hp-8
	worker.medical.state="wounded"
	worker.velocity=Vector2.ZERO
	truck.journey_state.solo_assist=false
	medic.position=truck.position+Vector2(-40,-24)
	var treatments: int=medic.treatments_completed
	var deadline := Time.get_ticks_msec()+9000
	while medic.treatments_completed==treatments and Time.get_ticks_msec()<deadline:
		await physics_frame
		medic._physics_process(1.0/60)
	check(medic.treatments_completed==treatments+1 and worker.hp==worker.max_hp,"Actual SAN leaves stowage and treats the normal driver exit without a chassis-blocked channel")
	check(medic.medical_supplies==0,"Ordinary roadside treatment spends its one finite medical charge")
	medic._physics_process(1.0/60)
	check(not medic.visible,"Completed treatment stows SAN without restocking from the hidden bunker")
	check(await Cleanup.free_scene(game,self),"Actual robot, worker channel and road audio release cleanly")
	print("CONVOY MEDICAL PRIORITY CHECKS: %d passed, %d failed"%[checks-failures,failures])
	quit(1 if failures else 0)
