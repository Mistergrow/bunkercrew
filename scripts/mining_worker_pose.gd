class_name MiningWorkerPose
extends RefCounted
## Target-relative, eight-pose pick swing. Gameplay still owns work accumulation;
## WorkerVisual owns the unchanged frame-3 contact clock.

const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const HANDLE_LENGTH := 48.0
const PICK_REACH := 12.0
const ARM_REACH := 22.8
const SWING := [-1.02, -1.40, -1.18, 0.0, -0.10, -0.32, -0.61, -0.84]
const TOOLS := preload("res://assets/workers/tool_turns.png")
const PICK_STEPS := 48
const PICK_COLUMNS := 24
const PICK_CELL := 112
const PICK_CENTRE := Vector2(56, 56)
const STRIKE_FRAME := 3
## Chips knocked off the face on the contact frame and the one after it, in
## whole texels on the actor's own grid (direction away from the rock).
const CHIPS := [Vector2(-5, -6), Vector2(-8, -1), Vector2(-3, -9), Vector2(-9, -5)]
const WEIGHT := [0.18, 0.0, 0.12, 1.0, 0.90, 0.68, 0.42, 0.27]

static func sample(worker: Node2D, target: Node2D, frame: int, crouched: bool, fraction: float=0.0) -> Dictionary:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return {}
	var start := worker.global_position + Vector2(0, -22)
	var contact: Vector2
	if target.has_method("_contact_from"):
		contact = target._contact_from(start)
	elif target.has_method("surface_near"):
		contact = target.surface_near(start)
	else:
		# Excavation consoles retain their authored action rather than swinging
		# into an invented rock surface.
		return {}
	var local := worker.to_local(contact)
	var facing := signf(local.x) if absf(local.x) > 0.5 else float(worker.facing)
	var pose := _sample_local(local * Vector2(facing, 1), frame, crouched, str(worker.character_id), fraction)
	pose.facing = facing
	pose.contact_world = contact
	return pose

static func _sample_local(contact: Vector2, frame: int, crouched: bool, identity: String, fraction: float=0.0) -> Dictionary:
	var pose := Personality.stance(PoseArt.neutral(), identity)
	var index := posmod(frame, 8)
	# Interpolate the rigid shaft and body, keeping the entire contact frame
	# exact. Tool impacts still cross frame 3 in WorkerVisual's original clock.
	var t := smoothstep(0.0, 1.0, clampf(fraction, 0, 1)) if index!=3 else 0.0
	var weight := lerpf(WEIGHT[index], WEIGHT[(index+1)%8], t)
	pose.continuous=true
	var spread := 11.0 if identity == "branko" else (8.0 if identity == "ivo" else 9.0)
	pose.feet = [Vector2(-spread, -3), Vector2(spread, -3)]
	var far := clampf((contact.x - 44.0) / 44.0, 0, 1)
	var hip := Vector2(far * 7.0, -20.0 if not crouched else -14.0)
	var lean := clampf(0.30 + far * 1.10, 0.0, 1.40)
	if contact.y < -49.0:
		# An overhead seam receives an upward stroke, with the gaze and chest
		# raised together. The bent knees remain distinct from standing mining.
		lean *= clampf((contact.y + 100.0) / 51.0, 0.0, 1.0)
		hip.y -= clampf((-contact.y - 49.0) * 0.13, 0, 6)
	var shoulder := hip + Vector2(sin(lean), -cos(lean)) * 18.0
	var direction := (contact - shoulder).normalized()
	var distance := contact.distance_to(shoulder)
	var grip_distance := clampf(distance - 14.0, 15.0, HANDLE_LENGTH - 9.0)
	var contact_angle := direction.angle() - atan2(PICK_REACH, grip_distance)
	var contact_axis := Vector2.from_angle(contact_angle)
	var contact_head := contact + contact_axis.orthogonal() * PICK_REACH
	var contact_hand := contact_head - contact_axis * grip_distance
	# Keep the shaft rigid. At the outer interaction boundary the upper body
	# reaches towards the tool; no root, foot, collider or target is translated.
	for unused in 4:
		var tx := Transform2D((shoulder - hip).angle() + PI * 0.5, shoulder)
		for hand in 2:
			var origin := tx * Vector2(-6 if hand == 0 else 3, 0)
			var goal := contact_hand - contact_axis * (7.0 if hand == 0 else 0.0)
			var reach := goal - origin
			if reach.length() > ARM_REACH:
				shoulder += reach.normalized() * (reach.length() - ARM_REACH)
	# The return is slower than the strike; frame 3 retains the exact surface
	# endpoint for its whole frame while anticipation and recovery stay fluid.
	pose.hip = hip + Vector2(-2.0 * (1.0 - weight), -(1.0 - weight))
	pose.shoulder = shoulder + Vector2(-4.0 * (1.0 - weight), -2.0 * (1.0 - weight))
	var pivot := contact_hand + Vector2(-4.0 * (1.0 - weight), -2.0 * (1.0 - weight)) - direction * (7.0 * (1.0 - weight))
	var swing := lerpf(SWING[index], SWING[(index+1)%8], t)*(0.52 if crouched else 1.0)
	var axis := Vector2.from_angle(contact_angle + swing)
	pose.hands = [pivot - axis * 7.0, pivot]
	pose.tool_head = pivot + axis * grip_distance
	pose.tool_butt = pose.tool_head - axis * HANDLE_LENGTH
	pose.tool_axis = axis
	pose.tool_tip = pose.tool_head - axis.orthogonal() * PICK_REACH
	pose.contact_local = contact
	pose.swing_frame = index
	pose.swing_fraction = fraction
	var body := PoseArt.torso_transform(pose)
	var gaze := clampf((contact - Vector2(pose.shoulder)).angle() * 0.22, -0.34, 0.28)
	pose.head_tilt = gaze - body.get_rotation() * 0.70
	return pose

static func draw_pose(canvas: CanvasItem, pose: Dictionary, worker: Node) -> void:
	var previous_continuous: bool=PoseArt._continuous
	PoseArt._continuous=bool(pose.get("continuous",false))
	PoseArt.draw_pose(canvas, pose, worker)
	# The pick is an authored sprite in 48 attitudes (generate_tool_turns.py),
	# drawn upright with its head on a whole texel: the haft stays a clean
	# stepped line instead of a freely rotated one.
	var axis: Vector2 = pose.tool_axis
	var step := posmod(roundi(axis.angle()/TAU*PICK_STEPS),PICK_STEPS)
	var region := Rect2(Vector2(step%PICK_COLUMNS,floori(float(step)/PICK_COLUMNS))*PICK_CELL,Vector2.ONE*PICK_CELL)
	canvas.draw_texture_rect_region(TOOLS,Rect2(Vector2(pose.tool_head).round()-PICK_CENTRE,region.size),region)
	_draw_strike(canvas,pose,worker)
	# Repaint the two gripping gloves, not another arm; both palms stay on the
	# same shaft and the existing rig remains the only source of arm geometry.
	var hidden := int(pose.get("hidden_limbs", 0))
	for hand in 2:
		if hidden & (1 << hand):
			continue
		var at: Vector2 = pose.hands[hand]
		PoseArt._box(canvas, at - Vector2(3, 2), Vector2(7, 6), Color("17211f"))
		PoseArt._box(canvas, at - Vector2(2, 1), Vector2(5, 4), PoseArt.colors.leather_light if hand == 1 else PoseArt.colors.leather)
		PoseArt._box(canvas, at + Vector2(1, -1), Vector2(2, 2), PoseArt.colors.skin_light)
	PoseArt._continuous=previous_continuous

## Impact frame: on the contact frame a hot glint and a burst of four rock
## chips leave the tip, the chips fly and drop on the next frame, then they
## are gone. Driven by the swing frame (host and guests animate the same
## clock); reduced effects keep the chips without the bright glint.
static func _draw_strike(canvas: CanvasItem, pose: Dictionary, worker: Node) -> void:
	var index := int(pose.get("swing_frame", -1))
	if index != STRIKE_FRAME and index != STRIKE_FRAME + 1: return
	var t := float(pose.get("swing_fraction", 0.0)) + (1.0 if index == STRIKE_FRAME + 1 else 0.0)
	var tip: Vector2 = Vector2(pose.tool_tip).round()
	var away: Vector2 = (Vector2(pose.shoulder) - tip).normalized()
	var flip := signf(away.x) if absf(away.x) > 0.1 else -1.0
	var reduced: bool = WeaponEffectArt.reduced(worker.get("game")) if worker != null else false
	if index == STRIKE_FRAME and not reduced:
		PoseArt._box(canvas, tip - Vector2(1, 1), Vector2(3, 3), Color("fff0b9"))
		PoseArt._box(canvas, tip + Vector2(-3, 0), Vector2(7, 1), Color("e6c47c"))
		PoseArt._box(canvas, tip + Vector2(0, -3), Vector2(1, 7), Color("e6c47c"))
	for chip in CHIPS.size():
		var travel: Vector2 = CHIPS[chip] * Vector2(-flip, 1) * (0.5 + t * 0.9) + Vector2(0, t * t * 7.0)
		var size := Vector2(2, 2) if chip % 2 == 0 else Vector2(1, 1)
		PoseArt._box(canvas, (tip + travel).round(), size, Color("6f6a58") if chip % 2 == 0 else Color("b9ae8a"))
