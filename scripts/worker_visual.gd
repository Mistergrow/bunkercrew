class_name WorkerVisual
extends Node2D

const NetInput := preload("res://scripts/network_input.gd")

const MountedPose := preload("res://scripts/mounted_worker_pose.gd")
const MiningPose := preload("res://scripts/mining_worker_pose.gd")
const WorkPose := preload("res://scripts/worker_work_pose.gd")
const ConvoyMechanicPose := preload("res://scripts/convoy_mechanic_pose.gd")
const IdentityArt := preload("res://scripts/worker_identity_art.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const Locomotion := preload("res://scripts/worker_locomotion.gd")
const RhythmPose := preload("res://scripts/worker_rhythm_pose.gd")
const RhythmPresentation := preload("res://scripts/rhythm_presentation.gd")
## Continuous articulated movement with native pixel clothes and equipment.
## Action frame metadata remains independent from the presentation rig.

const FRAME_SIZE := Vector2(112, 112)
const FEET_ANCHOR := Vector2(48, 90)
const TRANSFER_DURATION := 0.36
const LADDER_RUNG_SPACING := 14.0
const CLIMB_CYCLE_DISTANCE := LADDER_RUNG_SPACING * 4.0
const MINING_FPS := 12.8
const MINING_STRIKE_FRAME := 3
static var _frame_metadata: Dictionary = {}
static var _armor_metadata: Dictionary = {}

static func _load_metadata() -> void:
	if _frame_metadata.is_empty():
		var frame_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/workers/worker_frames.json"))
		_frame_metadata = frame_data.get("states",{}) if frame_data is Dictionary else {}
	if _armor_metadata.is_empty():
		var armor_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/workers/armor_anchors.json"))
		_armor_metadata = armor_data if armor_data is Dictionary else {}

var worker: CharacterBody2D
var pose_name := "idle"
var pose_frame := 0
var crouched := false
var ceiling_height := 68.0
var _frames: Dictionary = {}
var _equipment_anchors: Dictionary = {}
var _time := 0.0
var _step := 0.0
var _clearance_time := 0.0
var idle_clock := WorkerIdleClock.new()
var expression_clock := preload("res://scripts/worker_expression_clock.gd").new()
var special_pose := ""
var special_progress := 0.0
var pose_skeleton: Dictionary = {}
var mining_pose: Dictionary = {}
var work_pose: Dictionary = {}
var locomotion_pose: Dictionary = {}
var locomotion := Locomotion.new()
var rhythm := RhythmPose.new()
var _safe_idle := false
var _safe_carry_idle := false
var _limp_step := 0.0
var _limp_lower := false
var _identity: Node2D
var _character_id := ""


func _ready() -> void:
	if not is_instance_valid(worker):
		worker = get_parent() as CharacterBody2D
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_metadata()
	_frames = _frame_metadata
	_equipment_anchors = _armor_metadata
	assert(not _frames.is_empty(), "Worker animation frame metadata missing")
	_select_identity()
	_identity=Node2D.new()
	_identity.name="WorkerIdentity"
	_identity.draw.connect(_draw_identity)
	add_child(_identity)
	var ground_shadow:=preload("res://scripts/actor_ground_shadow.gd").new()
	ground_shadow.name="GroundShadow"
	ground_shadow.worker=worker
	add_child(ground_shadow)
	queue_redraw()


func _select_identity() -> void:
	var selected := str(worker.character_id)
	if selected==_character_id:
		return
	_character_id = selected
	idle_clock.configure(worker.player_id*719+selected.hash(),selected)
	expression_clock.reset()
	var character_frames := Personality.frames(selected)
	if not character_frames.is_empty():
		_equipment_anchors = character_frames
	special_pose = ""
	pose_skeleton = {}
	locomotion.reset()
	locomotion_pose = {}
	rhythm.configure(selected)
	_step = 0.0


func _physics_process(delta: float) -> void:
	if not is_instance_valid(worker):
		return
	if worker.climbing:
		crouched = false
		ceiling_height = 128.0
		return
	# The mining collider remains small enough for a dug tile. The worker visibly
	# bends their knees under low ceilings, using authored crouching poses.
	_clearance_time -= delta
	if _clearance_time <= 0.0:
		_clearance_time = 0.08
		var query := PhysicsRayQueryParameters2D.create(worker.global_position + Vector2(0, -39), worker.global_position + Vector2(0, -68), 1)
		query.exclude = [worker.get_rid()]
		query.hit_from_inside = true
		var space := worker.get_world_2d().direct_space_state
		var contact := space.intersect_ray(query)
		if absf(worker.velocity.x)>15.0:
			# Begin ducking before the head enters the overhang. The movement
			# collider and input stay unchanged; this is only an art clearance probe.
			var ahead := Vector2(signf(worker.velocity.x)*48.0,0)
			query.from+=ahead
			query.to+=ahead
			var approaching := space.intersect_ray(query)
			if not approaching.is_empty() and (contact.is_empty() or float(approaching.position.y)>float(contact.position.y)):
				contact=approaching
		crouched = not contact.is_empty()
		ceiling_height = worker.global_position.y-float(contact.position.y) if crouched else 128.0


func _process(delta: float) -> void:
	if not is_instance_valid(worker) or _frames.is_empty():
		return
	_select_identity()
	_time += delta
	if "hurt_flash" in worker and worker.hurt_flash > 0.0:
		modulate = Color(1.0,0.42,0.30)
	elif worker.has_method("is_downed") and worker.is_downed():
		modulate = Color(0.66,0.69,0.66)
	elif "invulnerability" in worker and worker.invulnerability > 0.0:
		modulate = Color(0.70,0.90,1.0,0.65) if int(_time*4)%2==0 else Color.WHITE
	else:
		modulate = Color.WHITE
	var next_pose := _choose_pose()
	if next_pose != pose_name:
		# Walking/carrying share footfall phases; other actions begin at anticipation.
		if not (pose_name.ends_with("walk") and next_pose.ends_with("walk")):
			_step = 0.0
		pose_name = next_pose
	var count: int = int(_frames[pose_name].frames)
	var fps := 12.0
	if pose_name.ends_with("idle") or pose_name == "crouch":
		fps = 3.0
	elif pose_name.ends_with("walk"):
		fps = clampf(absf(worker.velocity.x) / 16.0, 5.0, 15.0)
	elif pose_name == "climb":
		# Worker climbs by changing position and deliberately has zero velocity.
		# World-distance phase freezes at rest and retraces when descending. Input
		# time cannot represent blocked motion, analog speed or direction changes.
		fps = 0.0
	elif pose_name.ends_with("mine"):
		fps = MINING_FPS
	elif pose_name == "work":
		fps = 8.0
	fps *= Personality.playback_rate(_character_id,pose_name)
	var previous_step := _step
	_step += delta * fps
	pose_frame = int(_step) % count
	match pose_name:
		"weapon", "weapon_up", "weapon_down":
			pose_frame = weapon_frame()
		"climb":
			pose_frame = climb_frame()
		"pickup":
			pose_frame = mini(count - 1, int((1.0 - worker.pickup_animation / TRANSFER_DURATION) * count))
		"drop":
			pose_frame = mini(count - 1, int((1.0 - worker.drop_animation / TRANSFER_DURATION) * count))
		"land":
			pose_frame = 0 if worker._jump_windup > 0.0 else mini(count - 1, int((1.0 - worker._landing_time / 0.15) * count))
		"jump_up", "fall":
			pose_frame = mini(count - 1, int(_step * 0.45))
		"turret":
			var recoil: float = worker.mounted_turret.recoil
			pose_frame = 1 if recoil > 3.5 else (2 if recoil > 0.2 else 0)
	pose_frame = clampi(pose_frame, 0, count - 1)
	var rhythm_frame := _dance_frame()
	var previous_pose := pose_skeleton
	_update_special_pose(delta, rhythm_frame)
	mining_pose = {}
	if pose_name.ends_with("mine") and special_pose.is_empty() and worker.can_act() and is_instance_valid(worker.focus) and not worker.focus.is_queued_for_deletion():
		mining_pose = MiningPose.sample(worker, worker.focus, pose_frame, crouched, fposmod(_step, 1.0))
		if not mining_pose.is_empty():
			pose_skeleton = mining_pose
			pose_skeleton.splint = bool(medical_markers().splinted)
	locomotion_pose = {}
	work_pose = {}
	if special_pose.is_empty() and mining_pose.is_empty() and not _limp_lower and Locomotion.supports(pose_name):
		if ((previous_pose.has("dance_style") or previous_pose.has("head_pivot")) and not (_safe_idle or _safe_carry_idle)) or (previous_pose.has("work_action") and pose_name!="work"):
			# Locomotion normally remembers its stance before cosmetic dance is
			# applied. Start its existing short transition at the painted joints
			# when an action interrupts floor work, rather than snapping upright.
			# Gun/load anchors are still reapplied exactly by Locomotion.advance.
			locomotion.follow(previous_pose, worker)
		var locomotion_state := pose_name
		if pose_name=="work" and absf(worker.velocity.x)>15.0:
			locomotion_state = "crouch_walk" if crouched else "carry_walk" if worker.carried_count()>0 else "walk"
		locomotion_pose = locomotion.advance(worker, locomotion_state, delta, not weapon_pose().is_empty(), self)
		if locomotion_pose.has("cargo"):
			locomotion_pose.cargo_kind = worker.last_transfer_kind if pose_name=="drop" else worker.selected_material()
			locomotion_pose.cargo_pour = false
			locomotion_pose.cargo_clock = _time
		if pose_name=="work" and worker.can_act() and is_instance_valid(worker.focus) and not worker.focus.is_queued_for_deletion():
			work_pose = WorkPose.sample(worker,worker.focus,crouched,locomotion_pose)
			if not work_pose.is_empty():
				locomotion_pose = work_pose
		pose_skeleton = locomotion_pose
		pose_skeleton.splint = bool(medical_markers().splinted)
	elif _limp_lower and not weapon_pose().is_empty():
		# Retain the injured gait, but brace both real arms on the gun rather than
		# drawing an atlas upper body whose hands can be hidden by the weapon.
		Locomotion._weapon(pose_skeleton,worker,self)
		locomotion_pose = pose_skeleton
		locomotion.follow(pose_skeleton,worker)
	elif not pose_skeleton.is_empty():
		locomotion.follow(pose_skeleton, worker)
	var rhythm_allowed := (_safe_idle or _safe_carry_idle) and special_pose.is_empty() and not locomotion_pose.is_empty()
	if rhythm.advance(delta, rhythm_allowed, rhythm_frame) > 0.0:
		if _safe_carry_idle:
			rhythm.apply_carry_nod(pose_skeleton, rhythm_frame)
		else:
			rhythm.apply(pose_skeleton, rhythm_frame)
	_present_mining_strikes(previous_step, count)
	queue_redraw()
	_identity.queue_redraw()

func _dance_frame() -> Dictionary:
	var frame := RhythmPresentation.frame_for(worker)
	if frame.is_empty():
		return frame
	# Per-character unlock state must never mutate the shared mixer frame.
	frame = frame.duplicate()
	var dance_level := int(worker.progression.level) if "progression" in worker and is_instance_valid(worker.progression) else 1
	var world = worker.get("game")
	var dance_preview: bool = is_instance_valid(world) and world.has_meta("dance_preview") and bool(world.get_meta("dance_preview"))
	if is_instance_valid(world) and "combat_events" in world and is_instance_valid(world.combat_events) and world.combat_events.has_method("dance_level"):
		dance_level = world.combat_events.dance_level(_character_id, dance_level)
	frame.character_level = 10 if dance_preview else dance_level
	frame.dance_preview = dance_preview
	return frame


func _present_mining_strikes(previous_step: float, frame_count: int) -> void:
	var session = NetInput.session(worker)
	if session!=null and not session.is_host:
		return
	if not pose_name.ends_with("mine") or not special_pose.is_empty() or not worker.can_act():
		return
	var target = worker.focus
	if not is_instance_valid(target) or target.is_queued_for_deletion() or not target.has_method("mining_strike"):
		return
	# Contact happens on the forward tool frame. Count crossings rather than
	# comparing displayed frames, so a slow render frame cannot lose a strike.
	var before := floori((previous_step - MINING_STRIKE_FRAME) / frame_count)
	var after := floori((_step - MINING_STRIKE_FRAME) / frame_count)
	for _strike in range(after - before):
		target.mining_strike(worker)


func medical_state():
	return worker.medical if "medical" in worker and is_instance_valid(worker.medical) else null


func has_articulated_pose() -> bool:
	return not pose_skeleton.is_empty() and (not special_pose.is_empty() or not mining_pose.is_empty() or not locomotion_pose.is_empty())


func idle_allowed(allow_carry: bool = false) -> bool:
	var resting: bool = pose_name=="idle" or (allow_carry and pose_name=="carry_idle" and worker.carried_count()>0)
	if not resting or not worker.can_act() or absf(worker.velocity.x)>1 or absf(worker.velocity.y)>1 or crouched:
		return false
	var medical = medical_state()
	if is_instance_valid(medical) and (medical.bleeding>0 or medical.fractured or is_instance_valid(medical.aid_target) or medical.recovery_time>0):
		return false
	if worker.hp<worker.max_hp*0.55 or worker.hurt_flash>0 or not weapon_pose().is_empty():
		return false
	for action_name in NetInput.ACTIONS:
		if NetInput.is_pressed(worker,action_name):
			return false
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if _live_threat(enemy) and worker.global_position.distance_to(enemy.global_position)<370:
			return false
	for projectile in get_tree().get_nodes_in_group("air_projectiles"):
		if _live_threat(projectile) and worker.global_position.distance_to(projectile.global_position)<270:
			return false
	return true


func _live_threat(candidate: Node) -> bool:
	# SceneTree groups include the isolated lab's separate SubViewport too.
	# Only live combat objects sharing this actor's physics world are threats.
	return candidate is Node2D and candidate.is_inside_tree() and not candidate.is_queued_for_deletion() and candidate.get_world_2d()==worker.get_world_2d()


func _round_phase() -> String:
	if not is_instance_valid(worker.game) or not "rounds" in worker.game:
		return ""
	var rounds = worker.game.rounds
	return str(rounds.phase) if is_instance_valid(rounds) else ""


func _update_special_pose(delta: float, rhythm_frame: Dictionary = {}) -> void:
	var allowed := idle_allowed()
	_safe_idle = allowed
	_safe_carry_idle = pose_name=="carry_idle" and idle_allowed(true)
	var gesture_allowed := allowed and not rhythm.follows_kicks(rhythm_frame)
	var trigger := expression_clock.tick(delta,gesture_allowed,pose_name in ["mine","crouch_mine","work"],_round_phase())
	if not trigger.is_empty():
		idle_clock.begin(Personality.reaction(_character_id,trigger))
	idle_clock.tick(delta,gesture_allowed)
	special_pose = ""
	special_progress = 0.0
	pose_skeleton = {}
	_limp_lower = false
	_limp_step += absf(worker.velocity.x)*delta/15.0
	var medical = medical_state()
	if worker.is_downed():
		special_pose = "downed"
		var elapsed: float = medical.down_elapsed if is_instance_valid(medical) else Balance.WORKER_KO_TIME-worker.down_time
		special_progress = clampf(elapsed/0.40,0,1)
	elif pose_name=="turret" and worker.mounted_turret.has_method("operator_pose_anchors"):
		special_pose = "mounted"
		if worker.mounted_turret.has_method("operator_pose_skeleton"):
			pose_skeleton=worker.mounted_turret.operator_pose_skeleton(worker)
		else:
			pose_skeleton = MountedPose.sample(worker,worker.mounted_turret.operator_pose_anchors())
		pose_skeleton.splint = is_instance_valid(medical) and bool(medical.get("splinted"))
		return
	elif is_instance_valid(medical) and medical.is_rising():
		special_pose = "rise"
		special_progress = 1.0-clampf(medical.recovery_time/MedicalCatalog.RECOVERY_TIME,0,1)
	elif is_instance_valid(medical) and is_instance_valid(medical.aid_target) and not medical.aid_kind.is_empty():
		special_pose = (str(medical.aid_kind)+"_self") if medical.aid_target==worker else ("aid_"+str(medical.aid_kind))
		special_progress = medical.aid_progress
	elif worker._interacting:
		var mechanic := ConvoyMechanicPose.sample(worker)
		if not mechanic.is_empty():
			special_pose="convoy_service"
			pose_skeleton=mechanic
			pose_skeleton.splint=is_instance_valid(medical) and bool(medical.get("splinted"))
			return
	elif is_instance_valid(medical) and medical.fractured and pose_name in ["walk","carry_walk"]:
		_limp_lower = true
		if worker.carried_count()==0 and weapon_pose().is_empty():
			special_pose = "limp"
	elif pose_name=="idle" and (worker.hp<worker.max_hp*0.55 or (is_instance_valid(medical) and (medical.bleeding>0 or medical.fractured))):
		special_pose = "guard"
	elif not idle_clock.gesture.is_empty():
		special_pose = idle_clock.gesture
		special_progress = idle_clock.progress()
	if not special_pose.is_empty() or _limp_lower:
		var reach := Vector2(24,-13)
		if is_instance_valid(medical) and is_instance_valid(medical.aid_target):
			var patient: Node2D = medical.aid_target
			var near_side := signf(patient.to_local(worker.global_position).x)
			if near_side==0: near_side=-worker.facing
			# Reach the visible near side of the body, including when approaching a
			# lying patient from their feet. A fixed far-side chest coordinate would
			# put hands in empty space at the edge of the medical interaction range.
			var chest := Vector2(near_side*7,-34)
			if patient.has_method("is_downed") and patient.is_downed():
				chest = Vector2((-16 if near_side==-patient.facing else -3)*float(patient.facing),-12)
			elif medical.aid_kind=="splint":
				chest = Vector2(near_side*6,-10)
			reach = worker.to_local(patient.to_global(chest))*Vector2(worker.facing,1)
		pose_skeleton = WorkerPoseArt.sample(special_pose if not special_pose.is_empty() else "limp",special_progress,_limp_step,reach,_character_id)
		pose_skeleton.splint = is_instance_valid(medical) and bool(medical.get("splinted"))


func medical_markers() -> Dictionary:
	var medical = medical_state()
	return {"bleeding":int(medical.bleeding) if is_instance_valid(medical) else 0,"bandaged":bool(medical.get("bandaged")) if is_instance_valid(medical) else false,"splinted":bool(medical.get("splinted")) if is_instance_valid(medical) else false}


func _draw_medical_marks() -> void:
	var markers := medical_markers()
	var hip := Vector2(0,-25)
	var shoulder := Vector2(0,-42)
	if not pose_skeleton.is_empty():
		hip = pose_skeleton.hip
		shoulder = pose_skeleton.shoulder
	elif _equipment_anchors.has(pose_name):
		var anchor: Dictionary = _equipment_anchors[pose_name][pose_frame]
		hip = Vector2(anchor.hip[0],anchor.hip[1])
		shoulder = Vector2(anchor.shoulder[0],anchor.shoulder[1])
	if markers.bandaged:
		var at := shoulder+Vector2(6,8)
		draw_rect(Rect2(at,Vector2(6,5)),Color("d8d5b8"))
		draw_rect(Rect2(at+Vector2(1,2),Vector2(5,1)),Color("949d89"))
	if markers.splinted and not has_articulated_pose() and not _limp_lower and pose_name!="climb":
		# A standing/carrying pose keeps its existing arms and item. Only the leg
		# dressing is overlaid; atlas locomotion itself stays unchanged after cure.
		var foot := Vector2(5,-3)
		var frame := Personality.frame(_character_id,pose_name,pose_frame)
		if not frame.is_empty():
			foot = Vector2(frame.feet[1][0],frame.feet[1][1])
		WorkerPoseArt.draw_splint(self,hip+Vector2(4,0),foot)
	var gore=worker.game.get("combat_gore") if is_instance_valid(worker.game) else null
	if int(markers.bleeding)<=0 or (is_instance_valid(gore) and gore.level==0):
		return
	var wound := shoulder.lerp(hip,0.65)+Vector2(8,0)
	draw_rect(Rect2(wound.round(),Vector2(3,3)),Color("843c31"))
	# Three tiny short-lived drips at most. They belong to the wound pose; no
	# accumulating particles, decals or new material objects enter the world.
	for index in mini(3,int(markers.bleeding)):
		var fall := fposmod(_time*0.75+index*0.36,2.3)
		if fall>0.70: continue
		var at := wound+Vector2(index-1,minf(-wound.y-2,fall*38))
		draw_rect(Rect2(at.round(),Vector2(1,2)),Color(0.58,0.22,0.17,1-fall/0.85))


func _draw_resting_cargo() -> void:
	if worker.carried_count()<=0:
		return
	var kind: String = worker.selected_material()
	var at := Vector2(47,-10) if special_pose in ["downed","rise"] else Vector2(-26,-10)
	if not kind.is_empty() and not ItemCatalog.draw_icon(self,kind,Rect2(at-Vector2(12,12),Vector2(24,24))):
		MaterialArt.draw_material(self,kind,at)


func climb_frame() -> int:
	var rung_origin: float = worker._ladder.position.y + 15.0
	var distance := fposmod(rung_origin - worker.global_position.y, CLIMB_CYCLE_DISTANCE)
	return int(roundf(distance / (CLIMB_CYCLE_DISTANCE / 8.0))) % 8


func sprite_facing() -> float:
	# The ladder sprite faces into the screen, independent of the approach side.
	if not mining_pose.is_empty():
		return float(mining_pose.facing)
	if not work_pose.is_empty() and work_pose.has("facing"):
		return float(work_pose.facing)
	return 1.0 if pose_name == "climb" else worker.facing


func weapon_pose() -> String:
	if (worker.has_method("can_act") and not worker.can_act()) or worker.climbing or worker.mining or worker._interacting or worker.carried_count() > 0 or is_instance_valid(worker.mounted_turret):
		return ""
	var weapon := worker.get_node_or_null("WorkerWeapon")
	if not is_instance_valid(weapon) or not (weapon.aiming or weapon.flash > 0.0 or weapon.recoil > 0.0):
		return ""
	var angle: float = atan2(weapon.aim_direction.y, weapon.aim_direction.x * worker.facing)
	return "weapon_up" if angle < -0.3 else ("weapon_down" if angle > 0.3 else "weapon")


func weapon_frame() -> int:
	var weapon := worker.get_node_or_null("WorkerWeapon")
	if not is_instance_valid(weapon):
		return 0
	return 1 if weapon.recoil > 2.5 else (2 if weapon.recoil > 0.1 else 0)


func _choose_pose() -> String:
	if worker.has_method("is_downed") and worker.is_downed():
		return "crouch"
	if is_instance_valid(worker.mounted_turret):
		return "turret"
	if worker.climbing:
		return "climb"
	var walking: bool = absf(worker.velocity.x) > 15.0
	if crouched:
		if worker.mining:
			return "crouch_mine"
		return "crouch_walk" if walking else "crouch"
	if worker._airborne:
		return "jump_up" if worker.velocity.y < -30.0 else "fall"
	if worker._jump_windup > 0.0 or worker._landing_time > 0.01:
		return "land"
	if worker.mining:
		return "mine"
	if worker.drop_animation > 0.0:
		return "drop"
	if worker.pickup_animation > 0.0:
		return "pickup"
	if worker._interacting and is_instance_valid(worker.focus) and not worker.focus.is_in_group("pickups"):
		return "work"
	if worker.carried_count() > 0:
		return "carry_walk" if walking else "carry_idle"
	var armed := weapon_pose()
	if not armed.is_empty() and not walking:
		return armed
	return "walk" if walking else "idle"


func _draw() -> void:
	if not is_instance_valid(worker) or _frames.is_empty():
		return
	var body_texture := IdentityArt.body(worker.character_id)
	var arm_texture := IdentityArt.arms(worker.character_id)
	var descriptor: Dictionary = _frames[pose_name]
	var region := Rect2(Vector2(pose_frame * FRAME_SIZE.x, int(descriptor.row) * FRAME_SIZE.y), FRAME_SIZE)
	# The two-part sprite gives cargo a real grip: jacket behind, glove in front.
	var downed: bool = worker.has_method("is_downed") and worker.is_downed()
	var flinch: float = sin(clampf(worker.hurt_flash/0.22,0.0,1.0)*PI)*-0.13 if "hurt_flash" in worker and not downed and special_pose!="mounted" and mining_pose.is_empty() else 0.0
	var offset := Vector2(0,sin(absf(flinch)*8)*2)
	draw_set_transform(offset,worker.facing*flinch,Vector2(sprite_facing(), 1))
	var armed := weapon_pose()
	if not special_pose.is_empty():
		var visible_pose := pose_skeleton.duplicate()
		visible_pose.hidden_limbs=preload("res://scripts/combat_gore.gd").visible_mask(worker)
		WorkerPoseArt.draw_pose(self,visible_pose,worker)
		if special_pose.begins_with("aid_") or special_pose in ["downed","rise"]:
			_draw_resting_cargo()
	elif not mining_pose.is_empty():
		var visible_pose := mining_pose.duplicate()
		visible_pose.hidden_limbs=preload("res://scripts/combat_gore.gd").visible_mask(worker)
		MiningPose.draw_pose(self,visible_pose,worker)
	elif not locomotion_pose.is_empty():
		var visible_pose := locomotion_pose.duplicate()
		visible_pose.hidden_limbs=preload("res://scripts/combat_gore.gd").visible_mask(worker)
		WorkerPoseArt.draw_pose(self,visible_pose,worker)
	elif _limp_lower or (not armed.is_empty() and pose_name in ["walk", "jump_up", "fall", "land"]):
		# The belt separates the moving legs from the braced upper body. This also
		# replaces the rear hand, so running cannot swing a third hand through a gun.
		var split := FEET_ANCHOR.y - 25.0
		var lower_size := Vector2(FRAME_SIZE.x, FRAME_SIZE.y - split)
		if _limp_lower:
			WorkerPoseArt.draw_legs(self,pose_skeleton,worker.character_id)
		else:
			draw_texture_rect_region(body_texture, Rect2(-FEET_ANCHOR + Vector2(0, split), lower_size), Rect2(region.position + Vector2(0, split), lower_size))
		var upper_size := Vector2(FRAME_SIZE.x, split)
		var armed_at := Vector2(weapon_frame() * FRAME_SIZE.x, int(_frames[armed].row) * FRAME_SIZE.y) if not armed.is_empty() else region.position
		draw_texture_rect_region(body_texture, Rect2(-FEET_ANCHOR, upper_size), Rect2(armed_at, upper_size))
	else:
		draw_texture_rect_region(body_texture, Rect2(-FEET_ANCHOR, FRAME_SIZE), region)
	if special_pose.is_empty() and mining_pose.is_empty() and locomotion_pose.is_empty():
		_draw_equipment(armed)
		_draw_material(descriptor)
		var arm_region := region
		var arm_offset := Vector2.ZERO
		if not armed.is_empty():
			# Running and airborne bodies keep their locomotion, while the foreground
			# forearm follows the same aim/recoil as the separately drawn firearm.
			arm_region = Rect2(Vector2(weapon_frame() * FRAME_SIZE.x, int(_frames[armed].row) * FRAME_SIZE.y), FRAME_SIZE)
			if crouched:
				arm_offset = Vector2(0, 17)
		draw_texture_rect_region(arm_texture, Rect2(-FEET_ANCHOR + arm_offset, FRAME_SIZE), arm_region)
	_draw_medical_marks()
	draw_set_transform(Vector2.ZERO)


func _draw_identity() -> void:
	# This separate canvas keeps the P1/P2 label dry and legible when a material
	# shader darkens the wet clothing, helmet, armour and equipment underneath.
	if not is_instance_valid(worker): return
	var tint: Color = PartyConfig.player_color(worker.player_id)
	var label_y := -61.0 if crouched and pose_name != "climb" else -77.0
	if has_articulated_pose():
		label_y = minf(-32.0,float(pose_skeleton.shoulder.y)-35.0)
	_identity.draw_rect(Rect2(-10, label_y - 12, 22, 14), Art.INK)
	Art.text(_identity, Vector2(-8, label_y - 1), "P%d" % worker.player_id, 11, tint)
	_identity.draw_colored_polygon(PackedVector2Array([Vector2(-3, label_y + 4), Vector2(3, label_y + 4), Vector2(0, label_y + 8)]), tint)
	if worker.carried_count() > 0:
		Art.bar(_identity, Rect2(-10, label_y + 2, 22, 2), float(worker.carried_count()) / worker.capacity(), tint)


func _draw_material(descriptor: Dictionary) -> void:
	if pose_name in ["mine", "crouch_mine", "climb", "turret"]:
		return
	var kind: String = worker.selected_material()
	if pose_name == "drop":
		kind = worker.last_transfer_kind
		if pose_frame >= 4:
			return
	if kind.is_empty() or not ItemCatalog.contains(kind):
		return
	var anchor_data: Array = descriptor.item_anchors[pose_frame]
	var anchor := Vector2(float(anchor_data[0]), float(anchor_data[1]))
	if pose_name in ["jump_up", "fall", "land"]:
		anchor += Vector2(-2, -3)
	if kind in ["limestone", "glass", "tungsten", "alloy", "jaw_trap", "blast_trap", "sentry_kit"]:
		MaterialArt.draw_material(self,kind,anchor)
		return
	var pouring := pose_name == "work" and kind == "concrete" and pose_frame >= 2
	# Carrying physics stays in Worker; this visible load is the selected material.
	ItemCatalog.draw_carried(self,kind,anchor,1.0,pouring)
	if pouring:
		for i in 3:
			var fall: float = float((int(_time * 36.0) + i * 5) % 16)
			draw_rect(Rect2(anchor + Vector2(7 + i * 2, fall + 11), Vector2(2, 3)), Color("a6ab91"))


func _draw_equipment(armed: String) -> void:
	if not "character_id" in worker or not _equipment_anchors.has(pose_name):
		return
	var equipment_pose := pose_name
	var equipment_frame := pose_frame
	if not armed.is_empty() and pose_name in ["walk", "jump_up", "fall", "land"]:
		equipment_pose = armed
		equipment_frame = weapon_frame()
	var anchor: Dictionary = _equipment_anchors[equipment_pose][equipment_frame]
	var shoulder := Vector2(anchor.shoulder[0],anchor.shoulder[1])
	var hip := Vector2(anchor.hip[0],anchor.hip[1])
	var spec := CharacterCatalog.data(worker.character_id)
	var accent := Color(spec.accent)
	var tier: int = worker.progression.armor_tier if "progression" in worker and is_instance_valid(worker.progression) else 0
	# Anchors come from this character's 110 authored body poses. Plates follow the
	# chest in every animation; on ladders the rear pack stays visible between straps.
	if tier > 0:
		if pose_name == "climb":
			for side in [-1,1]:
				draw_rect(Rect2(shoulder+Vector2(side*9-2,-2),Vector2(4,17)),Color("222b2d"))
				draw_rect(Rect2(shoulder+Vector2(side*9-1,-1),Vector2(2,14)),Color("77817a"))
		else:
			var shape := PackedVector2Array([shoulder+Vector2(-8,0),shoulder+Vector2(4,0),shoulder+Vector2(7,5),hip+Vector2(6,-3),hip+Vector2(-7,-3)])
			draw_colored_polygon(shape,Color("242d2e"))
			var plate := PackedVector2Array([shoulder+Vector2(-6,1),shoulder+Vector2(2,1),shoulder+Vector2(4,5),hip+Vector2(3,-5),hip+Vector2(-5,-5)])
			draw_colored_polygon(plate,Color("727f79") if tier==1 else Color("88958b"))
			draw_line(shoulder+Vector2(-6,1),shoulder+Vector2(2,1),Color("bec0a4"),1)
			draw_line(shoulder+Vector2(-5,8),shoulder+Vector2(3,8),Color("485554"),2)
			for bolt in [Vector2(-5,3),Vector2(2,4)]:
				draw_rect(Rect2(shoulder+bolt,Vector2(1,1)),Color("d0c6a5"))
		if tier==2:
			draw_rect(Rect2(shoulder+Vector2(-10,-3),Vector2(7,5)),Color("293235"))
			draw_rect(Rect2(shoulder+Vector2(-9,-2),Vector2(5,2)),Color("a4ab98"))
	# A small stitched patch sits on top of the character-specific clothing.
	# The separate P1/P2 label identifies local players independent of this outfit.
	draw_rect(Rect2(shoulder+Vector2(-7,3),Vector2(5,5)),Color("26312f"))
	draw_rect(Rect2(shoulder+Vector2(-6,4),Vector2(3,2)),accent)
	if CharacterCatalog.presentation_id(str(worker.character_id),"visual") == "branko":
		draw_rect(Rect2(shoulder+Vector2(-6,7),Vector2(3,1)),accent.darkened(0.2))
	elif CharacterCatalog.presentation_id(str(worker.character_id),"visual") == "ivo":
		draw_rect(Rect2(shoulder+Vector2(-5,3),Vector2(1,5)),accent.lightened(0.12))
