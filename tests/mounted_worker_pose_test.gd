extends SceneTree
const Pose := preload("res://scripts/mounted_worker_pose.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func settle(gun: Node2D,worker: Node2D,angle: float,recoil: float=0.0,progress: float=-1.0) -> Dictionary:
	gun.aim_angle=angle
	gun.recoil=recoil
	gun.reload_timer=gun.reload_duration()*(1.0-progress) if progress>=0 else 0.0
	gun.pose_barrel()
	worker.facing=gun.facing_direction()
	worker.global_position=gun.operator_position()
	var visual=worker.get_node("PixelVisual")
	visual._process(0.0)
	return visual.pose_skeleton
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.start_scenario(2,{"environment":"sector07","position":"center","build_type":"bastion"})
	game.combat_events.persistence_enabled=false
	game.rounds.running=false
	game.rounds.set_process(false)
	game.audio.set_music_volume(0)
	game.audio.set_sfx_volume(0)
	game.audio.set_voice_volume(0)
	game.flak_station.unlock()
	game.flak_station._complete()
	var guns: Array=[game.turret,game.flak_station.turret]
	for worker in game.players:
		worker.set_physics_process(false)
		worker.get_node("PixelVisual").set_physics_process(false)
	for index in 2:
		var gun=guns[index]
		var worker=game.players[index]
		gun.set_physics_process(false)
		gun.enter(worker)
		for identity in ["mara","branko","ivo"]:
			game.started=false
			check(worker.configure_character(identity),"Prepared identity changes through the normal pre-match configuration API")
			game.started=true
			var baseline: Dictionary=settle(gun,worker,0)
			var feet: Array=baseline.feet.duplicate()
			for angle in range(-245,66,10):
				for kick in [0.0,7.0]:
					var pose: Dictionary=settle(gun,worker,deg_to_rad(angle),kick)
					var controls: Dictionary=gun.operator_pose_anchors()
					var tx:=PoseArt.torso_transform(pose)
					check(pose.feet==feet,"Both boots stay planted across aim and recoil")
					for hand in 2:
						var actual: Vector2=worker.to_global(Vector2(pose.hands[hand])*Vector2(worker.facing,1))
						check(actual.distance_to(controls.hands[hand])<0.01,"Articulated glove reaches the actual visible gun control")
						var shoulder: Vector2=tx*Vector2(-6 if hand==0 else 3,0)
						check(shoulder.distance_to(pose.hands[hand])<22.9,"Arm renderer never clamps a hand off its grip")
					check(Vector2(pose.shoulder).is_finite() and absf(pose.shoulder.x)<18 and pose.shoulder.y<-30,"Upper body stays finite and within natural bracing range")
			for side in [-1,1]:
				var angle: float=-PI-(-.5) if side<0 else -.5
				var calm: Dictionary=settle(gun,worker,angle)
				var kick: Dictionary=settle(gun,worker,angle,7)
				check(calm.shoulder.distance_to(kick.shoulder)>1.0 and calm.feet==kick.feet,"Real recoil shifts shoulders while feet remain fixed")
				var up: Dictionary=settle(gun,worker,-PI-( -.95) if side<0 else -.95)
				var down: Dictionary=settle(gun,worker,-PI-.55 if side<0 else .55)
				check(PoseArt.torso_transform(up).get_rotation()+up.head_tilt<-.2 and PoseArt.torso_transform(down).get_rotation()+down.head_tilt>.1,"Actual head rotation follows elevation despite the torso bracing lean")
				check(absf(up.head_tilt-down.head_tilt)>.3 and up.hands!=down.hands,"Head and arms visibly follow both upward and downward aim")
				var old_hand: Vector2=calm.hands[1]
				var excursion:=0.0
				for frame in 20:
					var pose: Dictionary=settle(gun,worker,angle,0,frame/20.0)
					excursion=maxf(excursion,old_hand.distance_to(pose.hands[1]))
					check(pose.feet==feet,"Reload retains grounded feet")
					var tx:=PoseArt.torso_transform(pose)
					check((tx*Vector2(3,0)).distance_to(pose.hands[1])<22.9,"Reload hand remains physically connected to arm")
				check(excursion>12,"Reload visibly reaches the ammunition pouch and breech")
			check(worker.get_node("PixelVisual").special_pose=="mounted","Real worker visual selects the articulated mounted rig")
	var first=game.players[0].get_node("PixelVisual")
	var second=game.players[1].get_node("PixelVisual")
	check(first.special_pose=="mounted" and second.special_pose=="mounted","Both cooperative players animate separate occupied weapons")
	settle(guns[0],game.players[0],-.6,0,.45)
	var before: Dictionary=first.pose_skeleton.duplicate(true)
	paused=true
	for unused in 5: await process_frame
	check(first.pose_skeleton==before,"Game pause freezes mounted pose")
	paused=false
	guns[0].exit()
	first._process(0)
	check(first.special_pose!="mounted" and first.pose_name!="turret","Dismount restores normal worker animation")
	await Cleanup.free_scene(game,self)
	print("Mounted worker poses: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
