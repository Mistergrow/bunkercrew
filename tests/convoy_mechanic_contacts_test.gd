extends SceneTree
## Check the actual working rig against the truck's visible tool anchors. This
## guards detached gloves, overlong limbs and cosmetic inventory/state writes.
const Mechanic := preload("res://scripts/convoy_mechanic_pose.gd")
const VehicleArt := preload("res://scripts/convoy_vehicle_art.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Journey := preload("res://scripts/convoy_journey.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
var max_arm := 0.0
var max_leg := 0.0
var max_contact_error := 0.0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args(): quit(2); return
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.start_scenario(1,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	await physics_frame
	freeze(game)
	var truck = load("res://scenes/convoy_vehicle.tscn").instantiate()
	truck.game=game
	game.add_child(truck)
	truck.configure_trip(Vector2(1910,430),Vector2(740,3700),{"hp":600,"fuel":12,"ammo":40,"reserve":0,"cargo":{"steel":4}})
	freeze(truck)
	var worker: Node2D=game.players[0]
	worker.focus=truck
	worker._interacting=true
	var inventory: Dictionary=worker.inventory.duplicate(true)
	for character: Dictionary in CharacterCatalog.CHARACTERS:
		worker.character_id=character.id
		for side in [-1.0,1.0]:
			truck.facing=side
			worker.facing=side
			for distance in [35.0,50.0,70.0]:
				worker.global_position=truck.service_point()+Vector2(-distance*side,20)
				var planted: Array=[]
				for step: String in ["jack","remove","fit","tighten","lower"]:
					for work in [0.0,.25,.5,.75,1.0]:
						truck.journey_state=Journey.new_state("repair")
						truck.journey_state.repair_step=step
						truck.journey_state.repair_operator=worker.player_id
						truck.journey_state.repair_work=work
						truck.journey_state.repair_bolts=2 if step=="tighten" else 3 if step=="lower" else 0
						truck.journey_state.phase_time=.5
						truck.journey_state.repair_cursor=.7
						var authority: Dictionary=truck.journey_state.duplicate(true)
						var original_worker: Vector2=worker.global_position
						var original_truck: Vector2=truck.global_position
						var pose := Mechanic.sample(worker)
						var body := PoseArt.torso_transform(pose)
						var reach_ok := true
						for hand in 2:
							var reach: float=(body*PoseArt.shoulder_local(pose,hand)).distance_to(pose.hands[hand])
							max_arm=maxf(max_arm,reach)
							max_leg=maxf(max_leg,(pose.hip+Vector2(-2 if hand==0 else 2,0)).distance_to(pose.feet[hand]))
							reach_ok=reach_ok and reach<=22.9
						check(reach_ok,"Both real gloves stay reachable: %s/%s/%s/%s"%[character.id,step,distance,work])
						if planted.is_empty(): planted=pose.feet.duplicate()
						check(pose.feet==planted and pose.feet.all(func(point):return is_equal_approx(point.y,-3.0)),"Boots remain on the real road through all wheel stages")
						var service := VehicleArt.repair_visual_state(truck)
						var expected: Vector2=worker.to_local(truck.to_global(VehicleArt.service_tool_point(truck,service)))*Vector2(side,1)
						var painted: Vector2=pose.hands[0] if step in ["jack","lower"] else pose.hands[1]+Transform2D(float(pose.work_tool_angle),Vector2.ZERO)*Mechanic.SOCKET_TIP if step=="tighten" else pose.hands[0]-Vector2(-9,-5)
						var error: float=painted.distance_to(expected)
						max_contact_error=maxf(max_contact_error,error)
						check(error<.001,"Painted handle, wheel rim or socket touches its actual moving component")
						check(truck.journey_state==authority and worker.inventory==inventory and worker.global_position==original_worker and truck.global_position==original_truck,"Sampling cannot move roots, spend cargo or advance authoritative tools")
					for tick in 11:
						truck.journey_state.phase_time=float(tick)*Mechanic.PICKUP_TIME/10.0
						var transitional := Mechanic.sample(worker)
						check(transitional.hip.is_finite() and transitional.shoulder.is_finite() and transitional.hands.all(func(point):return point.is_finite()),"Pickup anticipation remains finite")
						var body := PoseArt.torso_transform(transitional)
						var supported := true
						for index in 2:
							var arm: float=(body*PoseArt.shoulder_local(transitional,index)).distance_to(transitional.hands[index])
							var leg: float=(transitional.hip+Vector2(-2 if index==0 else 2,0)).distance_to(transitional.feet[index])
							max_arm=maxf(max_arm,arm)
							max_leg=maxf(max_leg,leg)
							supported=supported and arm<=22.9 and leg<=23.5+.001
						check(supported,"First pickup and all stage changes preserve the actual arm/leg lengths")
	check(max_leg<=23.5+.001,"Every painted shin stays within the two-segment leg rig")
	truck.journey_state.repair_operator=2
	check(Mechanic.sample(worker).is_empty(),"A different tool owner cannot animate this worker's gloves")
	truck.journey_state.repair_operator=worker.player_id
	worker._interacting=false
	check(Mechanic.sample(worker).is_empty(),"Releasing real interaction clears the service rig immediately")
	worker._interacting=true
	for phase: String in ["driving","reboarding","complete"]:
		truck.journey_state.phase=phase
		check(Mechanic.sample(worker).is_empty(),"Finished or inactive wheel tasks leave no phantom pose")
	check(await Cleanup.free_scene(game,self),"Real truck/worker scenes release their scene and audio handles")
	print("CONVOY MECHANIC CONTACTS: %d/%d passed; arm %.4f, leg %.4f, contact error %.5f"%[checks-failures,checks,max_arm,max_leg,max_contact_error])
	quit(1 if failures else 0)
