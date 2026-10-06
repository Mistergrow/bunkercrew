extends SceneTree
## Animation scheduling and anatomy use real Worker/WorkerMedical state. This
## tests decisions and invariants; the gallery separately checks rendered poses.
class WeaponProbe extends Node2D:
	var aiming := true
	var flash := 0.0
	var recoil := 0.0
	var aim_direction := Vector2.RIGHT

var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks += 1
	if value: print("PASS ",label)
	else:
		failures += 1
		push_error(label)
func make_worker(parent,point: Vector2,id: int):
	var worker := Worker.new()
	worker.game = parent
	worker.player_id = id
	worker.position = point
	parent.add_child(worker)
	worker.set_physics_process(false)
	var visual := WorkerVisual.new()
	visual.name = "PixelVisual"
	worker.add_child(visual)
	visual.set_process(false)
	visual.set_physics_process(false)
	return worker
func run():
	InputSetup.install()
	var clock := WorkerIdleClock.new()
	clock.configure(771)
	var observed: Array[String] = []
	var last := ""
	var repeated := false
	var wait_ok := true
	var gap := 0.0
	for tick in 4000:
		clock.tick(0.1,true)
		if clock.gesture.is_empty():
			gap += 0.1
		elif last.is_empty():
			if not observed.is_empty():
				wait_ok = wait_ok and gap>=5.8
				repeated = repeated or observed[-1]==clock.gesture
			observed.append(clock.gesture)
			gap = 0
		last = clock.gesture
	check(observed.size()>20 and WorkerIdleClock.GESTURES.all(func(kind):return observed.has(kind)),"Long idle sessions naturally visit all four authored gestures")
	check(not repeated and wait_ok,"Gestures never repeat immediately and wait at least six seconds between actions")
	clock.begin("helmet")
	clock.tick(0.1,false)
	check(clock.gesture.is_empty() and clock.wait_remaining>=6,"An action cancels the current gesture immediately and restarts a natural wait")
	var other := WorkerIdleClock.new()
	other.configure(992)
	check(not is_equal_approx(other.wait_remaining,clock.wait_remaining),"Independent worker clocks do not synchronize every gesture")
	var base := WorkerPoseArt.neutral()
	for kind in WorkerIdleClock.GESTURES:
		var start := WorkerPoseArt.sample(kind,0)
		var end := WorkerPoseArt.sample(kind,1)
		check(start.hip==base.hip and end.hip==base.hip and start.feet==base.feet and end.feet==base.feet,"%s returns both boots to their original planted contacts" % kind)
	var boot := WorkerPoseArt.sample("boot",0.45)
	check(boot.feet[0]==base.feet[0] and boot.feet[1].y<-5,"Boot shake balances on one planted foot while lifting the other")
	var helmet := WorkerPoseArt.sample("helmet",0.45)
	var watch := WorkerPoseArt.sample("thoughtful",0.45)
	var stretch := WorkerPoseArt.sample("stretch",0.58)
	check(helmet.hands[1].y<-55 and watch.watch and stretch.hands[0].y<-55,"Helmet, watch/chin and stretch have distinct actual hand targets")
	for kind in ["downed","rise","aid_revive","aid_resuscitate","aid_bandage","aid_splint","limp"]:
		var pose := WorkerPoseArt.sample(kind,0.6,1.2)
		check(pose.hands.size()==2 and pose.feet.size()==2,"%s authors exactly two hands and two feet" % kind)
	var down := WorkerPoseArt.sample("downed",1)
	var rising := WorkerPoseArt.sample("rise",0.52)
	var recovered := WorkerPoseArt.sample("rise",1)
	check(absf(down.shoulder.x-down.hip.x)>absf(down.shoulder.y-down.hip.y) and rising.shoulder.y<down.shoulder.y and recovered.shoulder==base.shoulder,"Recovery articulates horizontal torso → supported kneel → upright shoulders")

	var world := Node2D.new()
	root.add_child(world)
	var patient = make_worker(world,Vector2(100,300),1)
	var helper = make_worker(world,Vector2(64,300),2)
	var visual: WorkerVisual = patient.get_node("PixelVisual")
	var helper_visual: WorkerVisual = helper.get_node("PixelVisual")
	visual.idle_clock.begin("helmet")
	visual.idle_clock.elapsed = 1.0
	visual._process(0)
	check(visual.special_pose=="helmet","WorkerVisual routes a natural idle gesture into its separate pose renderer")
	patient.velocity.x = 70
	visual._process(0.01)
	check(visual.special_pose.is_empty() and visual.pose_name=="walk","Walking instantly restores the existing atlas locomotion")
	patient.velocity = Vector2.ZERO
	var enemy := Node2D.new()
	enemy.position = patient.position+Vector2(150,0)
	world.add_child(enemy)
	enemy.add_to_group("enemies")
	visual.idle_clock.begin("boot")
	visual._process(0.01)
	check(visual.special_pose.is_empty() and not visual.idle_allowed(),"A nearby machine suppresses comic idle gestures")
	enemy.free()
	var incoming := Node2D.new()
	incoming.position = patient.position+Vector2(210,-30)
	world.add_child(incoming)
	incoming.add_to_group("air_projectiles")
	visual.idle_clock.begin("stretch")
	visual._process(0.01)
	check(visual.special_pose.is_empty() and not visual.idle_allowed(),"Incoming hostile air ammunition interrupts an otherwise safe idle")
	incoming.free()
	var weapon := WeaponProbe.new()
	weapon.name = "WorkerWeapon"
	patient.add_child(weapon)
	visual.idle_clock.begin("thoughtful")
	visual._process(0.01)
	check(visual.special_pose.is_empty() and visual.pose_name=="weapon","Aiming has immediate precedence over idle gestures")
	patient.medical.fractured = true
	patient.velocity.x = 70
	visual._process(0.1)
	check(visual._limp_lower and visual.special_pose.is_empty() and visual.weapon_pose()=="weapon","A fractured leg changes the lower gait while preserving the existing two-handed gun pose")
	weapon.queue_free()
	await process_frame
	patient.inventory={"ore":1}
	patient.pickup_animation=0
	visual._process(0.1)
	check(visual._limp_lower and visual.pose_name=="carry_walk" and visual.special_pose.is_empty(),"Limping with cargo retains the existing grip and visible material")
	patient.inventory.clear()
	patient.velocity=Vector2.ZERO
	patient.hp=60
	patient.medical.bleeding=2
	visual._process(0.1)
	check(visual.special_pose=="guard" and visual.medical_markers().bleeding==2 and not visual.medical_markers().splinted,"Untreated wounds show guarded anatomy and bounded bleeding without a premature splint")
	for facing in [-1.0,1.0]:
		patient.facing=facing
		for side in [-1.0,1.0]:
			for distance in [32.0,48.0]:
				helper.position=patient.position+Vector2(side*distance,0)
				helper.facing=-side
				helper.medical.aid_target=patient
				helper.medical.aid_kind="revive"
				helper.medical.aid_progress=0.42
				patient.medical.state="downed"
				helper_visual._process(0)
				var contact_ok:=true
				for hand: Vector2 in helper_visual.pose_skeleton.hands:
					var actual:=helper.to_global(hand*Vector2(helper.facing,1))
					var chest:=patient.to_global(Vector2(-17*facing,-12))
					var hip:=patient.to_global(Vector2(0,-10))
					contact_ok=contact_ok and actual.distance_to(Geometry2D.get_closest_point_to_segment(actual,chest,hip))<13
				check(contact_ok,"Revival hands reach the actual torso from side%d at%dpx with patient facing%d"%[side,distance,facing])
				patient.medical.state="wounded"
				helper.medical.aid_kind="splint"
				helper_visual._process(0)
				var shin_ok:=true
				for hand: Vector2 in helper_visual.pose_skeleton.hands:
					var actual:=helper.to_global(hand*Vector2(helper.facing,1))
					var ankle:=patient.to_global(Vector2(side*6,-10))
					shin_ok=shin_ok and actual.y>patient.global_position.y-24 and actual.distance_to(ankle)<16
				check(shin_ok,"Splint hands reach the lower leg from side%d at%dpx with patient facing%d"%[side,distance,facing])
	helper.medical.aid_target=null
	helper.medical.aid_kind=""
	helper.position=Vector2(64,300)
	helper.facing=1
	patient.facing=1
	await physics_frame
	await physics_frame
	var origin: Vector2=helper.position
	patient.medical.begin_or_continue_aid(helper,0.8)
	helper_visual._process(0.01)
	check(helper_visual.special_pose=="aid_splint" and helper_visual.special_progress>0 and helper.position==origin,"Real ongoing care selects a kneeling splint pose without moving the helper")
	helper.medical.interrupt()
	helper_visual._process(0.01)
	check(helper_visual.special_pose.is_empty() and helper.medical.charges==2,"Interrupted treatment immediately removes the helper pose and preserves medical supplies")
	patient.medical.begin_or_continue_aid(helper,MedicalCatalog.TREAT_TIME)
	visual._process(0.01)
	check(visual.medical_markers().bandaged and visual.medical_markers().splinted and visual.medical_markers().bleeding==0,"Successful real treatment replaces bleeding with actual bandage and splint markers")
	patient.invulnerability=0
	patient.take_damage(500)
	patient.medical.down_elapsed=1.0
	visual._process(0.01)
	check(visual.special_pose=="downed" and visual.pose_skeleton.shoulder.y>-20,"A real knockout chooses a fully lying articulated pose")
	patient.medical.begin_or_continue_aid(helper,1.0)
	helper_visual._process(0.01)
	check(helper_visual.special_pose=="aid_revive","A real ongoing revival drives two-handed chest care")
	patient.medical.begin_or_continue_aid(helper,MedicalCatalog.REVIVE_TIME)
	visual._process(0.01)
	check(not patient.is_downed() and not patient.can_act() and visual.special_pose=="rise","Actual completed revival starts the protected joint-by-joint rise animation")
	patient.medical.tick(MedicalCatalog.RECOVERY_TIME)
	visual._process(0.01)
	check(patient.can_act() and visual.special_pose!="rise","Standing recovery releases the normal controls after the actual medical timer")
	world.queue_free()
	await process_frame
	print("WORKER MEDICAL VISUAL: %d/%d checks passed" % [checks-failures,checks])
	quit(0 if failures==0 else 1)
