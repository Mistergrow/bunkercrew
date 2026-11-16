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
const Keys := preload("res://scripts/worker_motion_keys.gd")
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
var _last_shield := 0.0
var _shield_grant := 0.0
## Tending a running production machine in focus (WorkerMotionKeys.TEND_KEYS).
var _tending := false
var _tend_time := 0.0
## The look-ahead clearance probe met a wall or gate panel, not a lintel.
var _wall_ahead := false
## Standing special poses that take the authored hit keys on top.
const STANDING_GESTURES := ["guard", "limp"]
## Aid on a downed patient: the authored kneel beside the body
## (WorkerMotionKeys.aid_pose), drawn behind the patient, then the rise;
## bandaging a patient on their feet is done standing (treat_pose).
const AID_KNEEL := ["aid_revive", "aid_resuscitate"]
const AID_STANDING := ["aid_bandage"]
var _aid_time := 0.0
var _aid_offset := 0.0
## Seconds into the rise after a revival; negative while there is none.
var _aid_rise := -1.0


func _ready() -> void:
	if not is_instance_valid(worker):
		worker = get_parent() as CharacterBody2D
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_metadata()
	_frames = _frame_metadata
	_equipment_anchors = _armor_metadata
	assert(not _frames.is_empty(), "Worker animation frame metadata missing")
	_select_identity()
	# This visual ticks the rig's hit clock every frame, also while a medical
	# or gesture pose replaces locomotion.
	locomotion.external_hit = true
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
		_wall_ahead = false
		if absf(worker.velocity.x)>15.0:
			# Begin ducking before the head enters the overhang. The movement
			# collider and input stay unchanged; this is only an art clearance probe.
			var ahead := Vector2(signf(worker.velocity.x)*48.0,0)
			query.from+=ahead
			query.to+=ahead
			var approaching := space.intersect_ray(query)
			if not approaching.is_empty() and (contact.is_empty() or float(approaching.position.y)>float(contact.position.y)):
				_wall_ahead = contact.is_empty() and _reaches_floor(space, query)
				contact=approaching
		crouched = not contact.is_empty()
		ceiling_height = worker.global_position.y-float(contact.position.y) if crouched else 128.0


func _process(delta: float) -> void:
	if not is_instance_valid(worker) or _frames.is_empty():
		return
	_select_identity()
	_time += delta
	locomotion.hit.tick(worker, delta)
	var hurt: float = worker.hurt_flash if "hurt_flash" in worker else 0.0
	# A hit reads as a red silhouette rim over a light red cast that keeps the
	# sprite's detail, not a solid red figure (actor_wet.gdshader `struck`).
	WeaponEffectArt.strike(self,hurt-.02,WeaponEffectArt.reduced(worker.get("game")),WeaponEffectArt.HURT_RIM,false)
	# The replicated invulnerability timer: a fresh grant longer than the hit
	# i-frames is the revive shield. The figure always stays opaque: a
	# translucent blink let the layered body parts and the scenery show
	# through each other and read as a green double image after every hit.
	var shield: float = float(worker.invulnerability) if "invulnerability" in worker else 0.0
	if shield > _last_shield + .05: _shield_grant = shield
	_last_shield = shield
	if hurt > 0.0:
		modulate = Color(1.0,0.90,0.86)
	elif worker.has_method("is_downed") and worker.is_downed():
		modulate = Color(0.66,0.69,0.66)
	elif shield > 0.0 and _shield_grant > Balance.WORKER_IFRAMES + .05:
		# Revive shield: a cool tint that breathes slowly (0.8 Hz, no flicker),
		# held still with reduced effects. Hit i-frames show nothing extra: the
		# hit reads as the short flash and the knockback.
		var breath := 0.5 if WeaponEffectArt.reduced(worker.get("game")) else 0.5-0.5*cos(_time*TAU*.8)
		modulate = Color.WHITE.lerp(Color(0.78,0.90,1.0),0.3+0.35*breath)
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
		if ((previous_pose.has("dance_style") or previous_pose.has("head_pivot")) and not (_safe_idle or _safe_carry_idle)) or (previous_pose.has("work_action") and pose_name!="work" and not _tending):
			# Locomotion normally remembers its stance before cosmetic dance is
			# applied. Start its existing short transition at the painted joints
			# when an action interrupts floor work, rather than snapping upright.
			# Gun/load anchors are still reapplied exactly by Locomotion.advance.
			locomotion.follow(previous_pose, worker)
		var locomotion_state := pose_name
		if pose_name=="work" and absf(worker.velocity.x)>15.0:
			locomotion_state = "crouch_walk" if crouched else "carry_walk" if worker.carried_count()>0 else "walk"
		elif pose_name=="work" and _idle_aid_focus():
			# A held button on a crew mate who needs no more help is no work.
			locomotion_state = "idle"
		locomotion_pose = locomotion.advance(worker, locomotion_state, delta, not weapon_pose().is_empty(), self)
		if locomotion_pose.has("cargo"):
			locomotion_pose.cargo_kind = worker.last_transfer_kind if pose_name=="drop" else worker.selected_material()
			locomotion_pose.cargo_pour = false
			locomotion_pose.cargo_clock = _time
		if pose_name=="work" and worker.can_act() and is_instance_valid(worker.focus) and not worker.focus.is_queued_for_deletion():
			work_pose = WorkPose.sample(worker,worker.focus,crouched,locomotion_pose)
			if not work_pose.is_empty():
				locomotion_pose = work_pose
		elif _tending:
			# A worker idling at the running machine in focus tends it: the
			# authored mallet knocks and drum watch, eased in from the stance.
			var before := _tend_time
			_tend_time += delta
			var tend := Keys.tend_pose(locomotion_pose, _tend_time, worker.selected_material() if worker.carried_count()>0 else "")
			work_pose = Locomotion._blend(locomotion_pose, tend, smoothstep(0.0, 0.12, _tend_time))
			locomotion_pose = work_pose
			_knock_drum(before)
		elif _aid_rise>=0.0:
			locomotion_pose = _aid_rise_pose(locomotion_pose, delta)
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
	var rhythm_allowed := (_safe_idle or _safe_carry_idle) and special_pose.is_empty() and not locomotion_pose.is_empty() and not _tending and _aid_rise<0.0
	# The reviver kneels behind the body it treats (and rises from there).
	z_index = -1 if special_pose in AID_KNEEL or _aid_rise>=0.0 else 0
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


## Presentation only: the solid the look-ahead probe met also stands on the
## floor in front (a closed or lowering gate panel, a wall), so it is no
## lintel to duck under. `crouched` itself (and the weapon height read from
## it) is unchanged; only the drawn body stays upright (body_crouched).
func _reaches_floor(space: PhysicsDirectSpaceState2D, probe: PhysicsRayQueryParameters2D) -> bool:
	var low := PhysicsRayQueryParameters2D.create(probe.from+Vector2(0, 9), probe.from+Vector2(0, 31), probe.collision_mask)
	low.exclude = probe.exclude
	low.hit_from_inside = true
	return not space.intersect_ray(low).is_empty()

## Whether the drawn body crouches: the clearance probe's answer, except for a
## wall or gate ahead while unarmed (an armed worker keeps the low gun pose).
func body_crouched() -> bool:
	return crouched and not (_wall_ahead and weapon_pose().is_empty())

## The running production machine in focus, close enough to tend.
func _tend_station() -> bool:
	var station: Variant = worker.get("focus")
	if not is_instance_valid(station) or not station is ProductionStation or station.is_queued_for_deletion(): return false
	if not bool(station.working) or bool(worker.get("_interacting")): return false
	return absf(station.interaction_point().x-worker.global_position.x)<48.0


## The mallet's contact keys knock the tended drum on the frame they begin:
## MixerAnimation jolts it and puffs dust at the mallet face. Presentation only.
func _knock_drum(before: float) -> void:
	var key := Keys.tend_key(_tend_time)
	if not bool(key.get("hit", false)) or Keys.tend_key(before) == key: return
	var station: Variant = worker.get("focus")
	var drum: Node = station.get_node_or_null("MixerAnimation") if is_instance_valid(station) else null
	if drum == null or not drum.has_method("knock"): return
	var face := Transform2D(float(key.angle), Vector2(key.hand))*Keys.MALLET_FACE
	drum.knock(to_global(face*Vector2(sprite_facing(), 1.0)), float(worker.facing))


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
	var was_tending := _tending
	_tending = (_safe_idle or _safe_carry_idle) and _tend_station()
	if not _tending or not was_tending: _tend_time = 0.0
	var gesture_allowed := allowed and not rhythm.follows_kicks(rhythm_frame) and not _tending and _aid_rise<0.0
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
	var down_since := -1.0
	if worker.is_downed():
		special_pose = "downed"
		var elapsed: float = medical.down_elapsed if is_instance_valid(medical) else Balance.WORKER_KO_TIME-worker.down_time
		special_progress = clampf(elapsed/Keys.collapse_seconds(),0,1)
		down_since = elapsed-Keys.collapse_seconds()
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
	if special_pose in AID_KNEEL:
		_aid_rise = -1.0
	elif _aid_time>0.0:
		# The kneel has ended: get up through the rise keys when standing still
		# or bandaging on (_aid_rise_pose), else straight into the next action.
		if special_pose.is_empty() or special_pose in AID_STANDING:
			if _aid_rise<0.0: _aid_rise = 0.0
		else:
			_end_aid_rise()
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
				# From the feet side the hands go past the hips to the chest, on top
				# of it (the supine coat is about 16 texels deep), so they stay in
				# sight over the body the reviver kneels behind (aid_offset).
				chest = Vector2((-16 if near_side==-patient.facing else -9)*float(patient.facing),-19)
			elif medical.aid_kind=="splint":
				chest = Vector2(near_side*6,-10)
			reach = worker.to_local(patient.to_global(chest))*Vector2(worker.facing,1)
		if special_pose in AID_KNEEL:
			_aid_time = maxf(0.001,_aid_elapsed(medical))
			_aid_offset = Keys.aid_offset(reach)
			pose_skeleton = Keys.aid_pose(Personality.stance(WorkerPoseArt.neutral(),_character_id),reach,_aid_time,special_pose)
		elif special_pose in AID_STANDING:
			pose_skeleton = Keys.treat_pose(Personality.stance(WorkerPoseArt.neutral(),_character_id),reach,_aid_elapsed(medical))
			if _aid_rise>=0.0:
				_aid_rise += delta
				if _aid_rise<Keys.aid_rise_seconds(): pose_skeleton = Keys.aid_rise_pose(pose_skeleton,_aid_rise,_aid_offset,Keys.treat_offset(reach))
				else: _end_aid_rise()
		else:
			pose_skeleton = WorkerPoseArt.sample(special_pose if not special_pose.is_empty() else "limp",special_progress,_limp_step,reach,_character_id)
		pose_skeleton.splint = is_instance_valid(medical) and bool(medical.get("splinted"))
		if down_since>=0.0: _lie_still(pose_skeleton,down_since)
		if special_pose in STANDING_GESTURES or (not special_pose.is_empty() and idle_clock.gesture==special_pose):
			# A hit during a guard, a limp or an idle gesture plays the same
			# authored impact and recovery as on the locomotion rig.
			Keys.apply_hit(pose_skeleton, Keys.hit_key(locomotion.hit.age), locomotion.hit.side, WeaponEffectArt.reduced(worker.get("game")))

## The reviver gets up after the revival (WorkerMotionKeys.AID_RISE) over the
## standing locomotion pose: off the knee, up and back to its own place. Any
## movement or action other than the still-held interact ends it at once.
func _aid_rise_pose(stance: Dictionary, delta: float) -> Dictionary:
	var acting := false
	for action_name in NetInput.ACTIONS:
		if action_name!="interact" and NetInput.is_pressed(worker,action_name): acting = true
	if acting or not pose_name in ["idle","work"] or absf(worker.velocity.x)>1.0 or not worker.can_act():
		_end_aid_rise()
		return stance
	_aid_rise += delta
	if _aid_rise>=Keys.aid_rise_seconds():
		_end_aid_rise()
		return stance
	var pose := Keys.aid_rise_pose(stance, _aid_rise, _aid_offset)
	# Locomotion's own short blend then leaves from the drawn rise key.
	locomotion.follow(pose, worker)
	return pose

## Seconds of the replicated aid channel so far (its progress over the
## patient's aid time at this crew member's medical speed): keys stay in step
## on every peer.
func _aid_elapsed(medical: Variant) -> float:
	var patient: Variant = medical.aid_target
	var duration: float = patient.medical.aid_duration() if is_instance_valid(patient) and "medical" in patient and is_instance_valid(patient.medical) else MedicalCatalog.REVIVE_TIME
	return float(medical.aid_progress)*duration/maxf(0.1,float(CharacterCatalog.medical_speed(_character_id)))

func _end_aid_rise() -> void:
	_aid_rise = -1.0
	_aid_time = 0.0

## The held interact still rests on a crew mate's aid point that has nothing
## left to treat (just revived or healed).
func _idle_aid_focus() -> bool:
	var target: Variant = worker.get("focus")
	if not is_instance_valid(target) or not target.is_in_group("medical_targets"): return false
	var patient_medical: Variant = target.get("medical")
	return not is_instance_valid(patient_medical) or not patient_medical.needs_medical_help() or patient_medical.is_rising()


## After the authored fall and floor strike (WorkerMotionKeys.COLLAPSE_KEYS)
## the body breathes slowly while unconscious: the chest and the hand on it
## lift one texel, the head lolls a little. Pure function of the replicated
## down time.
func _lie_still(pose: Dictionary, since: float) -> void:
	var breath := roundf(maxf(0.0,sin(since*TAU*0.42-0.6)))
	pose.shoulder = Vector2(pose.shoulder)+Vector2(0,-breath)
	pose.head_tilt = float(pose.head_tilt)+sin(since*TAU*0.21)*0.05
	pose.hands[1] = Vector2(pose.hands[1])+Vector2(0,-breath)


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
	if body_crouched():
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
	# The articulated rig plays its own knockback (WorkerLocomotion._hurt); only
	# the remaining atlas poses tilt as a whole, which would break the texel grid.
	var flinch: float = sin(clampf(worker.hurt_flash/0.22,0.0,1.0)*PI)*-0.13 if "hurt_flash" in worker and not downed and special_pose!="mounted" and mining_pose.is_empty() and locomotion_pose.is_empty() else 0.0
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
	var layout := _tag_layout()
	var label_y: float = layout.label_y
	_identity.draw_set_transform(layout.origin, 0.0, Vector2.ONE*float(layout.grow))
	# The plate carries the player's colour, so at combat zoom the colour block,
	# not the small digits, tells P1 from P2.
	_identity.draw_rect(Rect2(-11, label_y - 13, 24, 16), Art.INK)
	_identity.draw_rect(Rect2(-10, label_y - 12, 22, 14), tint)
	Art.text(_identity, Vector2(-8, label_y - 1), "P%d" % worker.player_id, 11, Art.INK)
	_identity.draw_colored_polygon(PackedVector2Array([Vector2(-4, label_y + 3), Vector2(4, label_y + 3), Vector2(0, label_y + 8)]), Art.INK)
	_identity.draw_colored_polygon(PackedVector2Array([Vector2(-3, label_y + 3), Vector2(3, label_y + 3), Vector2(0, label_y + 7)]), tint)
	if worker.carried_count() > 0:
		# The load meter sits inside the coloured plate: ink on a shaded track.
		var load_ratio := clampf(float(worker.carried_count()) / worker.capacity(), 0.0, 1.0)
		_identity.draw_rect(Rect2(-8, label_y, 18, 2), tint.darkened(0.4))
		_identity.draw_rect(Rect2(-8, label_y, floorf(18.0 * load_ratio), 2), Art.INK)
	_identity.draw_set_transform(Vector2.ZERO)

## Where the P tag goes: its height above the feet for the current pose, the
## growth at the zoomed-out couch camera and the draw origin (sideways steps
## included). The drawing and tag_bounds() share it.
func _tag_layout() -> Dictionary:
	var label_y := -61.0 if crouched and pose_name != "climb" else -77.0
	if has_articulated_pose():
		label_y = minf(-32.0,float(pose_skeleton.shoulder.y)-35.0)
	# At the zoomed-out couch co-op camera the tag grows around its arrow tip
	# until its letters reach TAG_MIN_PIXELS real pixels (at most 2x).
	var pixels := UiArt.output_scale(_identity)
	var grow := clampf(TAG_MIN_PIXELS/(11.0*pixels),1.0,2.0) if pixels>0.0 else 1.0
	var tip := Vector2(0, label_y + 8)
	# A machine in focus may name a part the tag must not hide (the mixer's
	# drum mouth): the tag then steps sideways just clear of it. Two crew at
	# one post step apart instead of stacking their tags.
	var shift := _tag_clearance(Rect2(-10, label_y - 12, 22, 20)) + _tag_spread(grow)
	return {"label_y": label_y, "grow": grow, "origin": shift + tip*(1.0-grow)}

## The P tag's global rect (plate and arrow); empty while it is not shown.
## World labels and combat words placed by the HUD keep clear of it.
func tag_bounds() -> Rect2:
	if not is_instance_valid(worker) or not is_instance_valid(_identity) or not _identity.is_visible_in_tree(): return Rect2()
	var layout := _tag_layout()
	var grow: float = layout.grow
	var shown := Rect2(Vector2(layout.origin) + Vector2(-11, float(layout.label_y) - 13)*grow, Vector2(24, 21)*grow)
	var frame := _identity.get_global_transform()
	return Rect2(frame*shown.position, Vector2.ZERO).expand(frame*shown.end)

## Smallest height of the tag's 11-unit letters on screen, in real pixels.
const TAG_MIN_PIXELS := 13.0

## Local sideways step that keeps this tag clear of another crew member's tag
## at the same height (two gunners on one roof gun): each moves half the
## overlap away from the other, the one further left to the left.
func _tag_spread(grow: float) -> Vector2:
	var game: Variant = worker.get("game")
	if not is_instance_valid(game) or not "players" in game: return Vector2.ZERO
	var width := 24.0*grow+2.0
	var shift := 0.0
	for other: Variant in game.players:
		if other == worker or not is_instance_valid(other) or not other is Node2D: continue
		var delta: Vector2 = (other as Node2D).global_position-worker.global_position
		if absf(delta.y) >= 16.0*grow or absf(delta.x) >= width: continue
		var leftmost: bool = delta.x > 0.0 or (is_zero_approx(delta.x) and int(other.player_id) > int(worker.player_id))
		shift += (width-absf(delta.x))*(-0.5 if leftmost else 0.5)
	if is_zero_approx(shift): return Vector2.ZERO
	return get_global_transform().affine_inverse().basis_xform(Vector2(roundf(shift),0.0))

## Local offset of the identity tag away from the focused machine's
## label_keepout() (a global rect), the smaller of a step left or right;
## zero when there is nothing to clear.
func _tag_clearance(tag: Rect2) -> Vector2:
	var target: Variant = worker.get("focus")
	if not is_instance_valid(target) or not target.has_method("label_keepout"): return Vector2.ZERO
	var keepout: Rect2 = target.label_keepout()
	if not keepout.has_area(): return Vector2.ZERO
	var frame := get_global_transform()
	var shown := Rect2(frame*tag.position,Vector2.ZERO).expand(frame*tag.end)
	if not shown.intersects(keepout): return Vector2.ZERO
	var right := keepout.end.x+1.0-shown.position.x
	var left := keepout.position.x-1.0-shown.end.x
	var step := right if absf(right)<=absf(left) else left
	return frame.affine_inverse().basis_xform(Vector2(roundf(step),0.0))


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
