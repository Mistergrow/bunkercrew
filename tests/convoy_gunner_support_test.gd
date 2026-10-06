extends SceneTree
## Actual occupied seat: painted platform support must not alter physics,
## ammunition or fixed control contacts under service tilt/recoil/reload.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const VehicleArt := preload("res://scripts/convoy_vehicle_art.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Journey := preload("res://scripts/convoy_journey.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	AudioServer.set_bus_mute(0,true)
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.start_scenario(2,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	freeze(game)
	var truck=load("res://scenes/convoy_vehicle.tscn").instantiate()
	truck.game=game
	game.add_child(truck)
	truck.configure_trip(Vector2(1910,430),Vector2(740,3700),{"hp":600,"fuel":12,"ammo":40,"reserve":40})
	truck.has_mg=true
	freeze(truck)
	var worker: Node2D=game.players[1]
	worker.position=truck.position
	check(truck.board(worker,"gunner"),"Actual finite gunner occupies real convoy seat")
	var seat: Node2D=truck.gunner_seat
	var collider=worker.get_node("CollisionShape2D")
	var collider_size: Vector2=collider.shape.size
	var max_support_error := 0.0
	var max_control_error := 0.0
	var max_reach := 0.0
	for identity in ["mara","branko","ivo"]:
		game.started=false
		check(worker.configure_character(identity),"Prepared real gunner identity%s"%identity)
		game.started=true
		for side in [1.0,-1.0]:
			truck.facing=side
			for step in ["jack","remove","fit","tighten","lower"]:
				for work in [0.0,.5,1.0]:
					truck.journey_state=Journey.new_state("repair")
					truck.journey_state.repair_step=step
					truck.journey_state.repair_work=work
					var authority: Dictionary=truck.journey_state.duplicate(true)
					for angle in [-.8,0.0,.7,PI-.6]:
						truck.aim_angle=angle
						for kick in [0.0,7.0]:
							truck.recoil=kick
							for reload_phase in [-1.0,.3,.6,.9]:
								truck.reload_timer=truck.reload_duration*(1-reload_phase) if reload_phase>=0 else 0.0
								truck.sync_replica()
								var controls: Dictionary=seat.operator_pose_anchors()
								var position: Vector2=worker.global_position
								var gun_origin: Vector2=truck.gun_origin()
								var pose: Dictionary=seat.operator_pose_skeleton(worker)
								var body:=PoseArt.torso_transform(pose)
								var mirror:=Vector2(worker.facing,1)
								for foot in 2:
									var local: Vector2=Vector2(pose.feet[foot])+Vector2(0,3)
									var actual: Vector2=truck.to_local(worker.to_global(local*mirror))
									var unsprung: Vector2=VehicleArt.body_pose(truck).affine_inverse()*actual
									max_support_error=maxf(max_support_error,absf(unsprung.y+42))
								for hand in 2:
									max_reach=maxf(max_reach,(body*Vector2(-6 if hand==0 else 3,0)).distance_to(pose.hands[hand]))
									if hand==0 or reload_phase<0:
										max_control_error=maxf(max_control_error,worker.to_global(Vector2(pose.hands[hand])*mirror).distance_to(controls.hands[hand]))
								check(worker.global_position==position and truck.gun_origin()==gun_origin and truck.journey_state==authority and truck.ammo==40 and truck.reserve==40 and collider.shape.size==collider_size,"Cosmetic support sample preserves actual seat/shot/hitbox/resources")
	check(max_support_error<.0001,"Both real boot soles lie exactly on sloped painted platform for all prepared states")
	check(max_control_error<.0001,"Supported gunner keeps fixed true gun/reload support controls")
	check(max_reach<22.9,"Supported pelvis/shoulders keep complete arms within native lengths")
	check(await Cleanup.free_scene(game,self),"Actual support fixture releases convoy/player/audio resources")
	print("CONVOY GUNNER SUPPORT: %d/%d passed; floor%s, controls%s, arm%s"%[checks-failures,checks,max_support_error,max_control_error,max_reach])
	quit(1 if failures else 0)
