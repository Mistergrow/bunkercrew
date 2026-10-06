extends RefCounted
## Read-only presentation of actual wall work and production handoffs. Targets
## retain their work clocks, costs and completion; no tool can consume material.
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const NetInput := preload("res://scripts/network_input.gd")

class MaterialView extends RefCounted:
	# RecipeStation uses selected_material() to rank real ingredient buffers.
	# This view shares its read-only input but cannot change the player's
	# selected slot when the original method chooses a fallback material.
	var inventory: Dictionary
	var selected := ""
	func _init(worker: Node2D) -> void:
		inventory = worker.inventory
		selected = str(worker.selected_kind)
		if int(inventory.get(selected,0))<=0:
			var choices: Array = worker._carried_materials()
			selected = str(choices[0]) if not choices.is_empty() else ""
	func selected_material() -> String:
		return selected

static func action(worker: Node2D, target: Node2D) -> Dictionary:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return {}
	if target is DefenseWall:
		var kind: String = target.action_for(worker)
		var session = NetInput.session(worker)
		var replica: bool = is_instance_valid(session) and not session.is_host
		# A snapshot's work_frame belongs to the host's clock. Replicas show the
		# still-active shared action until the host accepts a replacement.
		if target.work>0.0 and kind!=target.work_action and (replica or Engine.get_physics_frames()-target.last_work_frame<4):
			return {"kind":"wait", "phase":0.0}
		return {"kind":kind, "phase":clampf(float(target.work),0.0,1.0), "material":"concrete" if kind in ["pour","repair"] else "steel"} if not kind.is_empty() else {"kind":"wait", "phase":0.0}
	if target is ProductionStation:
		if target.working:
			return {"kind":"wait", "phase":0.0}
		var phase := clampf(float(target.transfer.get(worker.get_instance_id(),0.0))/Balance.TRANSFER_TIME,0.0,1.0)
		if target.output_amount>0:
			return {"kind":"collect", "phase":phase, "material":target.output_kind()} if worker.carried_count()<Balance.capacity_for(worker) else {"kind":"wait", "phase":0.0}
		if target is RecipeStation:
			var needed: String = target._needed_material(MaterialView.new(worker))
			return {"kind":"deposit", "phase":phase, "material":needed} if not needed.is_empty() else {"kind":"wait", "phase":0.0}
		if target.binder<int(target.recipe().get("binder",0)) or target.input_amount>=target.input_cost(target.input_kind()):
			return {"kind":"wait", "phase":0.0}
		var material: String = target.input_kind()
		if int(worker.inventory.get(material,0))<=0:
			for alternate: String in target.recipe().get("alternates",{}):
				if int(worker.inventory.get(alternate,0))>0:
					material = alternate
					break
		return {"kind":"deposit", "phase":phase, "material":material} if int(worker.inventory.get(material,0))>0 else {"kind":"wait", "phase":0.0}
	return {}

static func pressure(phase: float) -> float:
	# Preparation occupies the first third. Contact is quick and deliberately
	# held, then the wrist and upper body recover more slowly together.
	if phase<0.32:
		return -smoothstep(0.0,0.32,phase)*0.35
	if phase<0.42:
		return lerpf(-0.35,1.0,smoothstep(0.32,0.42,phase))
	if phase<0.57:
		return 1.0
	return 1.0-smoothstep(0.57,1.0,phase)

static func sample(worker: Node2D, target: Node2D, crouched: bool=false, resting_pose: Dictionary={}) -> Dictionary:
	var task := action(worker,target)
	if task.is_empty():
		return {}
	var pose := Personality.stance(PoseArt.neutral(),str(worker.character_id))
	pose.continuous = true
	pose.hip_spread = 2.0
	pose.work_action = str(task.kind)
	pose.work_phase = float(task.phase)
	if task.kind=="wait":
		if not resting_pose.is_empty():
			pose = resting_pose.duplicate(true)
			pose.work_action = "wait"
		return pose
	var point: Vector2 = worker.to_local(target.interaction_point())
	# A held interaction can continue while walking away. Aim the rendered
	# working rig at its real target without turning the authoritative actor.
	var facing := signf(point.x) if absf(point.x)>.5 else float(worker.facing)
	pose.facing = facing
	point*=Vector2(facing,1)
	# Work is permitted at the existing interaction range. The rig reaches the
	# near casing rather than pushing hands through the center of the machine.
	if target is DefenseWall:
		point.x-=15.0 if point.x>=0.0 else -15.0
	var contact := Vector2(clampf(point.x,14.0,47.0),clampf(point.y,-43.0,-19.0))
	var reach := smoothstep(23.0,47.0,contact.x)
	var pulse := pressure(float(task.phase))
	var lean := 0.18+reach*0.64+maxf(0.0,pulse)*0.035
	if task.kind=="pour":
		lean = 0.18+reach*0.28
	pose.hip = Vector2(lerpf(float(pose.hip.x),5.0,reach),-14.0 if crouched else -24.0)
	if absf(worker.velocity.x)>15.0 and not resting_pose.is_empty():
		# Locomotion is expressed in worker.facing, whereas work may look back.
		# Convert its lower rig, including hip attachments, so changing the
		# drawing direction cannot slide a planted world-space sole or hip.
		var direction := Vector2(float(worker.facing)*facing,1)
		pose.feet = [Vector2(resting_pose.feet[0])*direction,Vector2(resting_pose.feet[1])*direction]
		pose.hip = Vector2(resting_pose.hip)*direction
		pose.hip_spread = float(resting_pose.get("hip_spread",2.0))*direction.x
	for index in 2:
		var spread := float(pose.hip_spread)
		var dx: float = pose.feet[index].x-(pose.hip.x+(-spread if index==0 else spread))
		pose.hip.y = maxf(pose.hip.y,pose.feet[index].y-sqrt(maxf(1.0,23.7*23.7-dx*dx)))
	pose.shoulder = pose.hip+Vector2(sin(lean),-cos(lean))*17.0
	pose.head_tilt = -lean*0.65+0.09
	pose.head_shift = Vector2(1,1)
	pose.work_contact = contact
	match str(task.kind):
		"form","reinforce","upgrade":
			# One hand braces the work; the other prepares and presses the tool.
			pose.hands = [contact+Vector2(-4,4),contact+Vector2(-11,-4-pulse*4)]
			pose.prop = "work_hammer" if task.kind=="form" else "work_wrench"
			pose.work_tool_angle = lerpf(-0.48,0.05,maxf(0.0,pulse))
		"repair":
			pose.hands = [contact+Vector2(-4,5),contact+Vector2(-10,-2+float(task.phase)*5)]
			pose.prop = "work_trowel"
			pose.work_tool_angle = lerpf(-0.20,0.10,maxf(0.0,pulse))
		"pour":
			var flow := smoothstep(0.16,0.30,float(task.phase))*(1.0-smoothstep(0.82,1.0,float(task.phase)))
			pose.cargo = Vector2(contact.x-14,maxf(-31.0,contact.y+4)-maxf(0.0,pulse)*0.5)
			pose.cargo_kind = "concrete"
			pose.cargo_pour = flow>0.0
			pose.cargo_flow = flow
			pose.cargo_flow_end = Vector2(contact.x-3,minf(0.0,contact.y+24))
			pose.cargo_clock = float(task.phase)*Balance.WALL_WORK_TIME
			pose.hands = [pose.cargo+Vector2(-7,0),pose.cargo+Vector2(5,3)]
		"deposit","collect":
			var lift := smoothstep(0.0,0.45,float(task.phase))
			var return_weight := smoothstep(0.66,1.0,float(task.phase))
			var handoff := lift*(1.0-return_weight*0.25)
			pose.cargo = Vector2(17,-30).lerp(contact+Vector2(-10,-1),handoff)
			pose.cargo_kind = str(task.material)
			pose.cargo_pour = false
			pose.hands = [pose.cargo+Vector2(-7,0),pose.cargo+Vector2(5,3)]
	# The hands are the rigid tool/load grips. Bring the chest towards them;
	# never silently clamp a glove off its tool or move an authoritative root.
	for unused in 6:
		var body := PoseArt.torso_transform(pose)
		for index in 2:
			var offset: Vector2 = pose.hands[index]-body*PoseArt.shoulder_local(pose,index)
			if offset.length()>22.65:
				pose.shoulder+=offset.normalized()*(offset.length()-22.65)
	return pose
