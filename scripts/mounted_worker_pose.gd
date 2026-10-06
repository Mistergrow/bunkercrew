extends RefCounted
## Shared visible controls and hand targets; all motion derives from replicated
## gun state. No extra animation clock or gameplay state is needed on clients.
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Personality := preload("res://scripts/worker_personality.gd")

static func anchors(gun: Node2D, duration: float) -> Dictionary:
	var side: float = gun.facing_direction()
	var pitch := atan2(sin(gun.aim_angle),absf(cos(gun.aim_angle)))
	# The elevation linkage moves through a smaller arc than the barrel. This
	# leaves its two controls within arm's reach even when firing straight up.
	var linkage := pitch*0.28
	var kick: float = minf(gun.recoil,8.0)*0.30
	var pivot: Vector2 = gun.PIVOT
	var grips: Array[Vector2] = []
	for point: Vector2 in [Vector2(-21,5),Vector2(-15,9)]:
		var local := point.rotated(linkage)-Vector2(kick,0)
		grips.append(gun.to_global(pivot+local*Vector2(side,1)))
	var feed := gun.to_global(pivot+(Vector2(-18,-3).rotated(linkage)-Vector2(kick,0))*Vector2(side,1))
	return {"hands":grips,"feed":feed,"ammo_grab":gun.operator_position()+Vector2(-7*side,-21),
		"pitch":pitch,"recoil":gun.recoil,"reload_progress":1.0-clampf(gun.reload_timer/duration,0,1) if gun.reload_timer>0 else -1.0}

static func sample(worker: Node2D, controls: Dictionary) -> Dictionary:
	var pose := Personality.stance(PoseArt.neutral(),str(worker.character_id))
	var mirror := Vector2(float(worker.facing),1)
	var pitch: float = controls.pitch
	var kick: float = clampf(float(controls.recoil)/7.0,0,1)
	var lift := clampf(-pitch/(PI*0.5),0,1)
	var dip := clampf(pitch/(PI*0.5),0,1)
	pose.feet = [Vector2(-9,-3),Vector2(8,-3)] if CharacterCatalog.presentation_id(str(worker.character_id),"motion")!="branko" else [Vector2(-11,-3),Vector2(10,-3)]
	pose.hip = Vector2(-2-kick*1.2,-25+lift*1.5+dip)
	pose.shoulder = Vector2(2+lift*3+dip*2-kick*2.3,-42+lift*3+dip*1.5)
	pose.hands = [worker.to_local(controls.hands[0])*mirror,worker.to_local(controls.hands[1])*mirror]
	pose.head_shift = Vector2(1,-lift*1.4+dip*1.1)
	pose.head_tilt = pitch*0.30
	pose.mounted = true
	pose.prop = ""
	var progress: float = controls.reload_progress
	if progress>=0:
		# Release, fetch from belt, seat at the breech, then return to the grip.
		# The support hand stays on its control throughout the reload.
		var grip: Vector2 = pose.hands[1]
		var belt: Vector2 = worker.to_local(controls.ammo_grab)*mirror
		var feed: Vector2 = worker.to_local(controls.feed)*mirror
		if progress<0.28:
			pose.hands[1] = grip.lerp(belt,smoothstep(0.0,0.28,progress))
		elif progress<0.66:
			var t := smoothstep(0.28,0.66,progress)
			pose.hands[1] = belt.lerp(feed,t)+Vector2(-3,-5)*sin(t*PI)
			pose.prop = "mounted_rounds"
		elif progress<0.85:
			pose.hands[1] = feed+Vector2(2*sin((progress-0.66)/0.19*PI),0)
			pose.prop = "mounted_rounds" if progress<0.75 else ""
		else:
			pose.hands[1] = feed.lerp(grip,smoothstep(0.85,1.0,progress))
		pose.shoulder += Vector2(-1,1)*sin(progress*PI)
		pose.head_tilt = lerpf(pose.head_tilt,0.15,sin(progress*PI)*0.7)
	# Move the shoulder a few pixels when necessary, rather than allowing the
	# generic arm solver to clamp a glove away from the actual metal grip.
	for unused in 5:
		var transform := PoseArt.torso_transform(pose)
		for index in 2:
			var shoulder: Vector2 = transform*Vector2(-6 if index==0 else 3,0)
			var reach: Vector2 = Vector2(pose.hands[index])-shoulder
			if reach.length()>22.0:
				pose.shoulder += reach.normalized()*(reach.length()-22.0)
	# Counter the bracing lean so the gaze follows elevation in world space.
	pose.head_tilt -= PoseArt.torso_transform(pose).get_rotation()
	pose.blink = false
	return pose

static func draw_controls(node: CanvasItem, gun: Node2D, controls: Dictionary) -> void:
	var hub: Vector2 = gun.PIVOT+Vector2(-7*gun.facing_direction(),5)
	for target: Vector2 in controls.hands:
		var grip: Vector2 = gun.to_local(target).round()
		node.draw_line(hub.round(),grip,Color("151b1e"),5,false)
		node.draw_line(hub.round(),grip,Color("687970"),2,false)
		node.draw_rect(Rect2(grip-Vector2(2,4),Vector2(5,9)),Color("182324"))
		node.draw_rect(Rect2(grip-Vector2(1,3),Vector2(2,6)),Color("b3aa87"))
	var feed: Vector2 = gun.to_local(controls.feed).round()
	node.draw_rect(Rect2(feed-Vector2(5,2),Vector2(10,5)),Color("1b282a"))
	node.draw_line(feed-Vector2(4,2),feed+Vector2(4,2),Color("9ca393"),1,false)
