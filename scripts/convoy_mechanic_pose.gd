extends RefCounted
## The real tool lease, wheel travel and service clock drive this rig. Sampling
## only moves painted joints; it cannot change crew, inventory or repair work.
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const VehicleArt := preload("res://scripts/convoy_vehicle_art.gd")
const Journey := preload("res://scripts/convoy_journey.gd")
const PICKUP_TIME := 0.16
const SOCKET_TIP := Vector2(12,-3)
const STAGE_IDS := ["jack","remove","fit","tighten","lower"]

static func _local_point(worker: Node2D, truck: Node2D, point: Vector2) -> Vector2:
	return worker.to_local(truck.to_global(point))*Vector2(float(worker.facing),1)

static func _socket_angle(service: Dictionary, clock: float) -> float:
	# Prepare slowly, pull through the actual timing window, then return the
	# handle without moving the socket off its selected nut. Held work keeps
	# the existing accessible fallback and never creates a second success.
	var cursor := clampf(float(service.get("cursor",0.0)),0,1)
	var windup := smoothstep(0.08,Journey.TIMING_START,cursor)
	var pull := smoothstep(Journey.TIMING_START,Journey.TIMING_END,cursor)
	var recover := smoothstep(Journey.TIMING_END,1.0,cursor)
	var angle := lerpf(0.54,0.94,windup)
	angle = lerpf(angle,-0.24,pull)
	angle = lerpf(angle,0.54,recover)
	return angle+sin(clock*TAU*4.0)*0.015*pull*(1.0-recover)

static func _stage_pose(worker: Node2D, truck: Node2D, service: Dictionary, clock: float) -> Dictionary:
	var pose := Personality.stance(PoseArt.neutral(),str(worker.character_id))
	var step := str(service.step)
	var contact := Vector2.ZERO
	pose.prop = ""
	match step:
		"jack","lower":
			contact = _local_point(worker,truck,VehicleArt.jack_grip(truck,service))
			# The near glove pumps the grip, the other braces the same steel
			# handle. Neither follows a disconnected generic wrist sine.
			pose.hands = [contact,contact+Vector2(5,-0.5)]
		"remove","fit":
			contact = _local_point(worker,truck,Vector2(service.wheel_position))
			pose.hands = [contact+Vector2(-9,-5),contact+Vector2(-6,3)]
		"tighten":
			contact = _local_point(worker,truck,VehicleArt.service_tool_point(truck,service))
			var angle := _socket_angle(service,clock)
			var socket := Transform2D(angle,Vector2.ZERO)
			var rim := _local_point(worker,truck,Vector2(service.hub_position))
			pose.hands = [rim+Vector2(-10,-3),contact-socket*SOCKET_TIP]
			pose.prop = "work_wrench"
			pose.work_tool_angle = angle
			pose.work_contact = contact
	# The stance derives from the unchanged service station, so the boots stay
	# planted as the wheel moves, the jack lifts and the next task is selected.
	var station := _local_point(worker,truck,truck.service_point())
	var stance := clampf((station.x-50.0)*0.65,-14.0,36.0)
	pose.feet = [Vector2(-7+stance,-3),Vector2(20+stance,-3)]
	pose.hip_spread = 2.0
	var hands_center: Vector2 = (Vector2(pose.hands[0])+Vector2(pose.hands[1]))*0.5
	pose.hip = Vector2(stance+clampf(hands_center.x-stance-30.0,-4.0,17.0),-12.0 if step in ["jack","lower"] else -15.0)
	if step=="fit": pose.hip.y-=smoothstep(0.15,0.9,float(service.work))*2.5
	pose.shoulder = pose.hip+Vector2(13,-15)
	# Keep painted boots supported and both shins within the real leg rig.
	for index in 2:
		var dx: float = pose.feet[index].x-(pose.hip.x+(-2.0 if index==0 else 2.0))
		pose.hip.y = maxf(pose.hip.y,pose.feet[index].y-sqrt(maxf(1.0,23.5*23.5-dx*dx)))
	# Contacts are rigid. Bring the chest towards the work instead of letting
	# WorkerPoseArt clamp a detached glove to the end of an overlong arm.
	for unused in 7:
		var body := PoseArt.torso_transform(pose)
		for index in 2:
			var offset: Vector2 = pose.hands[index]-body*PoseArt.shoulder_local(pose,index)
			if offset.length()>22.5:
				pose.shoulder+=offset.normalized()*(offset.length()-22.5)
	pose.head_pivot = Vector2(1,10)
	pose.head_shift = Vector2(1,1)
	pose.head_tilt = 0.16-PoseArt.torso_transform(pose).get_rotation()
	pose.continuous = true
	pose.convoy_mechanic = true
	pose.service_step = step
	pose.service_contact = contact
	return pose

static func _pickup_pose(worker: Node2D, truck: Node2D, service: Dictionary, step: String) -> Dictionary:
	if step=="jack":
		var ready := Personality.stance(PoseArt.neutral(),str(worker.character_id))
		var station := _local_point(worker,truck,truck.service_point())
		var stance := clampf((station.x-50.0)*0.65,-14.0,36.0)
		ready.feet = [Vector2(-7+stance,-3),Vector2(20+stance,-3)]
		ready.hip_spread=2.0
		ready.hip.x+=stance
		var old_height: float=ready.hip.y
		for index in 2:
			var dx: float=ready.feet[index].x-(ready.hip.x+(-2.0 if index==0 else 2.0))
			ready.hip.y=maxf(ready.hip.y,ready.feet[index].y-sqrt(maxf(1.0,23.5*23.5-dx*dx)))
		# Anticipation already uses the wide planted work stance. Lower the
		# whole upper body with its pelvis instead of stretching a standing leg.
		var shift := Vector2(stance,ready.hip.y-old_height)
		ready.shoulder+=shift
		for index in 2: ready.hands[index]+=shift
		return ready
	var previous := service.duplicate()
	previous.step = STAGE_IDS[STAGE_IDS.find(step)-1]
	previous.work = 1.0
	previous.phase_time = 0.0
	previous.cursor = Journey.TIMING_END
	if step=="remove": previous.lift=1.0
	elif step=="fit": previous.wheel_position=Vector2((VehicleArt.WHEELS[0]-36)*truck.facing,-11+VehicleArt.FLAT_DROP)
	elif step=="tighten": previous.wheel_position=service.hub_position
	elif step=="lower": previous.bolts=2
	return _stage_pose(worker,truck,previous,0.0)

static func sample(worker: Node2D) -> Dictionary:
	if not is_instance_valid(worker) or not worker.can_act() or is_instance_valid(worker.mounted_turret): return {}
	if not worker._interacting or not is_instance_valid(worker.focus): return {}
	var truck = worker.focus
	if not "journey_state" in truck or not "game" in truck or truck.game!=worker.game: return {}
	var state: Dictionary = truck.journey_state
	if state.get("phase","")!="repair" or int(state.get("repair_operator",0))!=int(worker.player_id): return {}
	var step := str(state.get("repair_step","none"))
	if step not in STAGE_IDS: return {}
	var service := VehicleArt.repair_visual_state(truck)
	var clock := float(service.get("phase_time",state.get("phase_time",0.0)))
	var pose := _stage_pose(worker,truck,service,clock)
	if clock<PICKUP_TIME:
		var ready := _pickup_pose(worker,truck,service,step)
		var weight := smoothstep(0.0,PICKUP_TIME,clock)
		for key in ["hip","shoulder","head_shift"]:
			pose[key] = Vector2(ready[key]).lerp(Vector2(pose[key]),weight)
		for key in ["hands","feet"]:
			for index in 2: pose[key][index]=Vector2(ready[key][index]).lerp(Vector2(pose[key][index]),weight)
		pose.head_tilt=lerpf(float(ready.head_tilt),float(pose.head_tilt),weight)
		# The wrench appears only once the free hand has reached the socket.
		if weight<0.75: pose.prop=""
	pose.service_contact_ready = clock>=PICKUP_TIME
	return pose
