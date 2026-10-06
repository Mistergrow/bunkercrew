extends Node2D
## Mounted-player adapter. The owning vehicle replicates seats by player ID.
const NetInput := preload("res://scripts/network_input.gd")
const MountedPose := preload("res://scripts/mounted_worker_pose.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const VehicleArt := preload("res://scripts/convoy_vehicle_art.gd")
var vehicle: Node2D
var game: Node
var role := "driver"
var occupant: Node2D
var ammo: int:
	get:
		var weapon:=personal_weapon()
		return weapon.current_ammo() if weapon!=null else vehicle.ammo if is_instance_valid(vehicle) else 0
var reserve: int:
	get:
		var weapon:=personal_weapon()
		return weapon.reserve if weapon!=null else vehicle.reserve if is_instance_valid(vehicle) else 0
var reload_timer: float:
	get:
		var weapon:=personal_weapon()
		return weapon.reload_timer if weapon!=null else vehicle.reload_timer if is_instance_valid(vehicle) else 0.0
var recoil: float:
	get:
		var weapon:=personal_weapon()
		if weapon!=null: return float(weapon.recoil)
		return vehicle.recoil if is_instance_valid(vehicle) and role=="gunner" else 0.0
var _collision_layer := 8
var _collision_mask := 3
var _was_visible := true
var _synced_occupant: Node2D
var enter_frame := -10

func _ready() -> void:
	add_to_group("interactables")

func interaction_point() -> Vector2:
	return vehicle.global_position+Vector2(_seat_x()*vehicle.facing,-26)

func can_interact(worker) -> bool:
	if not is_instance_valid(vehicle) or not is_instance_valid(worker) or not worker is Node2D or worker.is_queued_for_deletion() or worker.get("game")!=game or vehicle.destroyed: return false
	if occupant==worker: return true
	# Rear-seat hotspots must not steal the tool interaction beside the wheel.
	if vehicle.journey_state.phase=="repair" and (worker.global_position-Vector2(0,20)).distance_to(vehicle.service_point())<90: return false
	return not is_instance_valid(occupant)

func _seat_x() -> float:
	return {"driver":58.0,"gunner":-21.0,"passenger_left":-73.0,"passenger_right":19.0}.get(role,0.0)

func allows_personal_weapon() -> bool:
	return role.begins_with("passenger_") or (role=="gunner" and not vehicle.has_mg)

func personal_weapon() -> Node2D:
	return occupant.get_node_or_null("WorkerWeapon") if allows_personal_weapon() and is_instance_valid(occupant) else null

func personal_weapon_origin() -> Vector2:
	return operator_position()+Vector2(facing_direction()*10,-30)

func projectile_exclusions() -> Array[RID]:
	return [vehicle.get_rid()]

func display_name(_uppercase: bool=false) -> String:
	if role=="passenger_left": return LocaleText.text("Konvoi · Heckwache")
	if role=="passenger_right": return LocaleText.text("Konvoi · Seitenwache")
	return LocaleText.text("Fahrersitz" if role=="driver" else ("Konvoi-MG" if vehicle.has_mg else "Mitfahrplatz"))

func ammo_capacity() -> int:
	var weapon:=personal_weapon()
	return weapon.magazine_size() if weapon!=null else 40

func prompt(worker: Node) -> String:
	if occupant==worker:
		var hint:=LocaleText.text("Ziel wechseln: freier Sitz · Interaktion: aussteigen")
		if allows_personal_weapon(): return LocaleText.text("Eigene Waffe: zielen, feuern und nachladen")+"\n"+hint
		if role=="driver":
			return (LocaleText.text("A/D fahren · E aussteigen · MG: Maus/LMB, R laden") if vehicle.has_mg else LocaleText.text("A/D fahren · E aussteigen · Zur Verteidigung anhalten und aussteigen"))+"\n"+hint
		if not vehicle.has_mg: return LocaleText.text("Mitfahrt · E aussteigen · Konvoi-MG im Technikbaum nachrüsten")
		return LocaleText.format("Konvoi-MG  %d/40 · Reserve %d\nMaus zielen · LMB feuern · R laden · E aussteigen",[vehicle.ammo,vehicle.reserve])+"\n"+hint
	if is_instance_valid(occupant): return LocaleText.text("Sitz besetzt")
	if allows_personal_weapon(): return LocaleText.text("Mitfahren und mit eigener Waffe verteidigen")
	return LocaleText.text("Konvoi fahren") if role=="driver" else LocaleText.text("Konvoi-MG bedienen")

func interact(worker: Node2D, _delta: float) -> void:
	if not vehicle.authoritative() or Engine.get_physics_frames()<=enter_frame+1: return
	if NetInput.just_pressed(worker,"interact"):
		if occupant==worker: exit()
		else: vehicle.board(worker,role)

func enter(worker) -> bool:
	if not is_instance_valid(vehicle) or not vehicle.authoritative() or vehicle.destroyed or is_instance_valid(occupant) or not is_instance_valid(worker) or not worker is Node2D or worker.is_queued_for_deletion() or worker.get("game")!=game: return false
	if worker.has_method("can_act") and not worker.can_act(): return false
	if is_instance_valid(worker.mounted_turret): return false
	occupant=worker
	occupant.mounted_turret=self
	if allows_personal_weapon(): occupant.facing=vehicle.facing*(-1 if role=="passenger_left" else 1)
	if not occupant.tree_exiting.is_connected(_occupant_leaving): occupant.tree_exiting.connect(_occupant_leaving)
	enter_frame=Engine.get_physics_frames()
	sync_operator()
	return true

func _occupant_leaving() -> void:
	exit(false)

func exit(move_outside: bool=true) -> void:
	if is_instance_valid(occupant):
		if occupant.tree_exiting.is_connected(_occupant_leaving): occupant.tree_exiting.disconnect(_occupant_leaving)
		occupant.mounted_turret=null
		occupant.collision_layer=_collision_layer
		occupant.collision_mask=_collision_mask
		occupant.visible=_was_visible
		if move_outside and is_instance_valid(vehicle): occupant.global_position=vehicle.global_position+Vector2((-116 if _seat_x()<0 else 116)*vehicle.facing,-3)
		occupant.velocity=Vector2.ZERO
	occupant=null
	_synced_occupant=null
	enter_frame=Engine.get_physics_frames()

func operator_position() -> Vector2:
	var elevation: float=-5 if role=="driver" else -40 if role=="gunner" and vehicle.has_mg else -29
	return vehicle.global_position+Vector2(_seat_x()*vehicle.facing,elevation+vehicle.suspension)

func facing_direction() -> float:
	if allows_personal_weapon() and is_instance_valid(occupant): return occupant.facing
	return vehicle.facing if role=="driver" or not vehicle.has_mg else (-1.0 if cos(vehicle.aim_angle)<0 else 1.0)

func sync_operator() -> void:
	if _synced_occupant!=occupant:
		if is_instance_valid(_synced_occupant):
			_synced_occupant.collision_layer=_collision_layer
			_synced_occupant.collision_mask=_collision_mask
			_synced_occupant.visible=_was_visible
		_synced_occupant=occupant
		if is_instance_valid(occupant):
			_collision_layer=occupant.collision_layer
			_collision_mask=occupant.collision_mask
			_was_visible=occupant.visible
			if not vehicle.authoritative():
				_collision_layer=8
				_collision_mask=3
				_was_visible=true
	if not is_instance_valid(occupant): return
	occupant.collision_layer=0
	occupant.collision_mask=0
	if role=="driver": occupant.hide()
	occupant.global_position=operator_position()
	occupant.facing=facing_direction()
	occupant.velocity=Vector2.ZERO
	occupant.queue_redraw()

func operator_pose_anchors() -> Dictionary:
	var side:=facing_direction()
	var origin:=operator_position()
	var pitch:=atan2(sin(vehicle.aim_angle),absf(cos(vehicle.aim_angle))) if role=="gunner" else 0.0
	var grip: Vector2=vehicle.gun_origin()+Vector2(-15*side,4) if role=="gunner" else origin+Vector2(14*side,-26)
	return {"hands":[grip+Vector2(-4*side,-3),grip+Vector2(2*side,2)],"feed":grip+Vector2(-4,-8),"ammo_grab":origin+Vector2(-7*side,-21),"pitch":pitch,"recoil":recoil,"reload_progress":1.0-vehicle.reload_timer/vehicle.reload_duration if vehicle.reload_timer>0 and role=="gunner" else -1.0}

func operator_pose_skeleton(worker: Node2D) -> Dictionary:
	if role=="gunner" and vehicle.has_mg:
		return _supported_gunner_pose(worker,MountedPose.sample(worker,operator_pose_anchors()))
	var pose:=PoseArt.neutral()
	pose.hip=Vector2(-8,-13)
	pose.shoulder=Vector2(-5,-30)
	pose.feet=[Vector2(10,-1),Vector2(14,-2)]
	pose.hands=[Vector2(10,-29),Vector2(14,-24)]
	pose.head_tilt=vehicle.velocity.x*0.00012
	if allows_personal_weapon():
		pose.hands=[Vector2(2,-16),Vector2(8,-14)]
		var weapon:=personal_weapon()
		if weapon!=null and (weapon.aiming or weapon.reload_timer>0):
			var aim: Vector2=Vector2(weapon.aim_direction)*Vector2(worker.facing,1)
			# The receiver slides along its real aim axis on every shot. Gloves
			# must follow that same kick, including left-facing and steep aim.
			var receiver:=Vector2(10,-30)-aim*float(weapon.recoil)
			pose.hands=[receiver+aim*13,receiver-aim*2]
			pose.head_tilt=aim.angle()*.18
			pose.shoulder=Vector2(-3-weapon.recoil*.18,-30)
			if weapon.reload_timer>0:
				var progress: float=1.0-weapon.reload_timer/weapon.reload_duration(weapon.weapon_kind)
				pose.hands[1]=Vector2(pose.hands[1]).lerp(Vector2(-4,-15),sin(progress*PI))
			# A seated upper body can lean; its feet and hips stay on the truck.
			# Keep both arms inside the native solver's reach instead of letting
			# it clamp a forearm away from the visible rifle grip.
			for unused in 5:
				var body:=PoseArt.torso_transform(pose)
				for index in 2:
					var shoulder: Vector2=body*Vector2(-6 if index==0 else 3,0)
					var reach: Vector2=Vector2(pose.hands[index])-shoulder
					if reach.length()>22.0: pose.shoulder+=reach.normalized()*(reach.length()-22.0)
			pose.head_tilt-=PoseArt.torso_transform(pose).get_rotation()
	pose.mounted=true
	pose.prop=""
	return pose

func _supported_gunner_pose(worker: Node2D, pose: Dictionary) -> Dictionary:
	# The seat and weapon remain fixed authoritative anchors. Only the rig's
	# boot soles/pelvis follow the painted platform as the sprung body pitches.
	var mirror:=Vector2(float(worker.facing),1)
	var shift:=Vector2.ZERO
	var gaze: float=PoseArt.torso_transform(pose).get_rotation()+float(pose.head_tilt)
	for index in 2:
		var original: Vector2=pose.feet[index]
		var support:=Vector2(_seat_x()+original.x*worker.facing/vehicle.facing,-42)
		var world: Vector2=vehicle.to_global(VehicleArt.body_point(vehicle,support))
		var foot: Vector2=worker.to_local(world)*mirror-Vector2(0,3)
		shift+=(foot-original)*.5
		pose.feet[index]=foot
	pose.hip+=shift
	pose.shoulder+=shift*.65
	# Keep both real control/reload targets unchanged and within the native
	# arm lengths after the stance follows the platform, including reverse aim.
	for unused in 6:
		var body:=PoseArt.torso_transform(pose)
		for index in 2:
			var shoulder: Vector2=body*Vector2(-6 if index==0 else 3,0)
			var reach: Vector2=Vector2(pose.hands[index])-shoulder
			if reach.length()>22.0: pose.shoulder+=reach.normalized()*(reach.length()-22.0)
	pose.head_tilt=gaze-PoseArt.torso_transform(pose).get_rotation()
	return pose
