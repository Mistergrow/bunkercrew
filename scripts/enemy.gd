class_name SiegeMachine
extends CharacterBody2D
const Quads := preload("res://scripts/canvas_quads.gd")

@export var wave := 1
@export var elite := false
@export var kind: String = "strider"
var show_status_labels := true
var attack_direction := -1.0 # +1 enters from the left; native machine art faces left.
var game: Node
var profile: Dictionary = {}
var abilities: GroundMachineAbilities
var variant_visual: GroundVariantVisual
var wetness: ActorWetness
var motion: Node2D
const MOTION = preload("res://scripts/enemy_motion.gd")
const LIMB_ART = preload("res://scripts/machine_limb_art.gd")
const MechanismArt := preload("res://scripts/machine_surface_details.gd")
const VehicleArt := preload("res://scripts/ground_vehicle_art.gd")
const RhythmPresentation := preload("res://scripts/rhythm_presentation.gd")
const PixelArt := preload("res://scripts/pixel_effect_art.gd")
var visual_scale := 1.0
var body_height := 43.0
var attack_reach := 63.0
var attack_damage := 12.0
var move_speed := 28.0
var hp := float(Balance.ENEMY_HP)
var max_hp := float(Balance.ENEMY_HP)
var gait := 0.0
var moving := false
var attack_clock := 0.0
var windup := 0.0
var hit_flash := 0.0
var stagger := 0.0
var weapon_recoil := 0.0
var muzzle_flash := 0.0
var target: Node2D
var body_part: Node2D
var legs_part: Node2D
var weapon_part: Node2D
var _weapon_draw_part_id := 0
var _weapon_draw_chassis := ""
var _weapon_draw_flash := false
var _weapon_draw_charge := -1.0
## Walker cannons: hand-pixelled families in baked aim keys
## (tools/generate_machine_weapons_v2.py), drawn upright on the world texel
## grid by a child that cancels the weapon node's turn and 0.78 scale. The
## node keeps the exact aim for muzzle, tracer and weather; only the drawing
## holds the nearest key (hysteresis as the infantry's living attitudes).
const WEAPON_KEYS := preload("res://assets/enemies/machine_weapons_v2.png")
const WEAPON_FAMILIES := {"runner":0,"strider":0,"breaker":1,"colossus":2,"assault":3,"siege":4}
const WEAPON_STEPS := Vector2i(-9,3)
const WEAPON_CELL := 96.0
const WEAPON_KEY := TAU/48.0
const WEAPON_DRAWN_SCALE := 0.78
## The keys baked at each walker's drawn scale (tools/bake_machine_weapons_world.py),
## drawn 1:1 on whole world texels; the v2 keys above stay the fallback.
const WEAPON_WORLD_PATH := "res://assets/enemies/machine_weapons_world.png"
const WeaponIndex := preload("res://scripts/machine_weapon_index.gd")
static var _weapon_world: Texture2D
## Presentation-only hull life in whole world texels (breath, wind-up crouch),
## carried by the drawn weapon key; the weapon node that fires stays exact.
var _hull_lift := Vector2.ZERO
## Bore of each family in world texels (the flash sits on the drawn muzzle).
const WEAPON_BORES := [-30.0,-30.0,-35.0,-34.0,-42.0]
var weapon_keys: Node2D
var _weapon_step := 0
var _weapon_keys_drawn := Vector3i(-1,0,-1)
var dead := false
var tracer_end := Vector2.ZERO
var burst_remaining := 0
var burst_clock := 0.0
var burst_target: Node2D
var locomotion_speed := 0.0
var age := 0.0
var crew_size_at_spawn := 1
var attack_count := 0
var chassis_atlas: Texture2D
var worker_target: Node2D
var worker_windup := 0.0
var worker_attack_clock := 1.6
var worker_attack_count := 0
const WORKER_TARGET_RANGE := 148.0
const WORKER_WINDUP_TIME := 0.48
const WORKER_ATTACK_INTERVAL := 2.6
const CHASSIS_PATH := "res://assets/enemies/chassis_atlas_v2.png"
## The world-texel chassis atlas: every chassis baked offline at each size it
## is drawn at, in lean stances (tools/world_density_bake.json). CHASSIS_PATH
## is its source, the bake key and the fallback for a size without a bake.
const CHASSIS_WORLD_PATH := "res://assets/enemies/chassis_world.png"
const BODY_REGIONS := {
	"runner": Rect2(96,243,344,198), "strider": Rect2(558,220,396,252),
	"breaker": Rect2(1012,232,489,245), "colossus": Rect2(47,513,433,428),
	"assault": Rect2(508,626,442,271), "siege": Rect2(987,525,530,412),
}

func _ready() -> void:
	add_to_group("enemies")
	if not EnemyCatalog.PROFILES.has(kind):
		kind = "strider"
	profile = EnemyCatalog.profile(kind)
	# Baked from the per-chassis grade (tools/grade_enemy_hulls.py); the
	# graded 1536 px atlas itself stays unloaded.
	if ResourceLoader.exists(CHASSIS_WORLD_PATH):
		chassis_atlas = load(CHASSIS_WORLD_PATH)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	crew_size_at_spawn = Balance.active_players(game)
	max_hp = Balance.enemy_hp_multiplier(crew_size_at_spawn) * float(profile.hp) * EnemyCatalog.hp_scale(wave) * (EnemyCatalog.ELITE_HP_SCALE if elite else 1.0)
	hp = max_hp
	visual_scale = float(profile.scale) * (EnemyCatalog.ELITE_SIZE_SCALE if elite else 1.0)
	body_height = float(profile.body_y) * (EnemyCatalog.ELITE_SIZE_SCALE if elite else 1.0)
	attack_reach = float(profile.reach)
	attack_damage = Balance.enemy_damage_multiplier(crew_size_at_spawn) * float(profile.damage) * EnemyCatalog.damage_scale(wave) * (EnemyCatalog.ELITE_DAMAGE_SCALE if elite else 1.0)
	move_speed = float(profile.speed) * EnemyCatalog.speed_scale(wave) * (0.90 if elite else 1.0)
	collision_layer = 4
	collision_mask = 0
	var hitbox := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = profile.hitbox * (EnemyCatalog.ELITE_SIZE_SCALE if elite else 1.0)
	hitbox.shape = shape
	hitbox.position = Vector2(0, -float(profile.center_y) * (EnemyCatalog.ELITE_SIZE_SCALE if elite else 1.0))
	hitbox.name = "MachineHitbox"
	add_child(hitbox)
	legs_part = _create_part("ArticulatedLegs", _draw_legs)
	body_part = _create_part("ArmoredBody", _draw_body)
	weapon_part = _create_part("ArticulatedWeapon", _draw_weapon)
	weapon_keys = Node2D.new()
	weapon_keys.name = "WeaponKeys"
	weapon_keys.use_parent_material = true
	weapon_keys.draw.connect(_draw_weapon_keys)
	weapon_part.add_child(weapon_keys)
	for part in [body_part, legs_part]:
		part.scale = Vector2.ONE * visual_scale
	weapon_part.scale = Vector2.ONE * visual_scale * 0.78
	_pose_parts()
	gait = global_position.x * 0.031
	attack_clock = 0.4
	if profile.has("ability"):
		abilities = GroundMachineAbilities.new()
		abilities.name = "CombatAbility"
		add_child(abilities)
		variant_visual = GroundVariantVisual.new()
		variant_visual.machine = self
		variant_visual.name = "VariantEquipment"
		body_part.add_child(variant_visual)
	wetness=ActorWetness.new()
	wetness.name="Wetness"
	add_child(wetness)
	motion = MOTION.new()
	motion.name = "MechanicalPerformance"
	add_child(motion)
	if VehicleArt.is_vehicle(kind):
		# The child still updates replicated presentation; its generic walker
		# mast and service bolt do not belong on the painted vehicle hull.
		motion.visible=false

func chassis_kind() -> String:
	return str(profile.get("chassis",kind))

func worker_windup_duration() -> float:
	return float(profile.get("worker_windup",WORKER_WINDUP_TIME))

func _create_part(part_name: String, draw_method: Callable) -> Node2D:
	var part := Node2D.new()
	part.name = part_name
	part.draw.connect(draw_method)
	add_child(part)
	return part

func _physics_process(delta: float) -> void:
	if dead:
		return
	age += delta
	hit_flash = maxf(0, hit_flash - delta)
	stagger = maxf(0, stagger - delta)
	muzzle_flash = maxf(0, muzzle_flash - delta)
	weapon_recoil = move_toward(weapon_recoil, 0, delta * (12 if chassis_kind() == "siege" else 24))
	attack_clock = maxf(0, attack_clock - delta)
	worker_attack_clock = maxf(0,worker_attack_clock-delta)
	var next_target := nearest_obstacle()
	if next_target != target:
		windup = 0
		burst_remaining = 0
	target = next_target
	if is_instance_valid(abilities):
		abilities.update(delta)
	moving = false
	var ability_busy := is_instance_valid(abilities) and abilities.blocks_action()
	var rushing := is_instance_valid(abilities) and abilities.rush_time>0
	var threatening_worker := _update_worker_attack(delta) if not ability_busy and not rushing else false
	if is_instance_valid(target) and not threatening_worker and not ability_busy:
		var distance := (target.global_position.x-global_position.x)*attack_direction
		if distance > attack_reach:
			moving = true
			windup = 0
			burst_remaining = 0
			var desired := move_speed * (0.3 if stagger > 0 else 1.0) * (abilities.movement_multiplier() if is_instance_valid(abilities) else 1.0)
			locomotion_speed = move_toward(locomotion_speed, desired, move_speed * delta * (10.0 if rushing else 3.6))
			global_position.x += attack_direction*minf(distance-attack_reach,locomotion_speed*delta)
		elif burst_remaining > 0:
			_process_burst(delta)
		elif attack_clock <= 0:
			if windup<=0 and is_instance_valid(abilities): abilities.prepare_attack(target_attack_point())
			windup += delta
			if windup >= float(profile.windup):
				if attack_obstacle():
					burst_remaining = int(profile.burst) - 1
					burst_target = target
					burst_clock = float(profile.burst_gap)
				windup = 0
				if burst_remaining == 0:
					attack_clock = float(profile.cooldown) * (0.90 if elite else 1.0)
	if moving:
		gait += delta * float(profile.gait) * clampf(locomotion_speed / move_speed, 0.3, 1.0)
	else:
		locomotion_speed = move_toward(locomotion_speed, 0, move_speed * delta * 4)
		gait = move_toward(gait, roundf(gait / PI) * PI, delta * 5)
	_pose_parts()
	for part in [body_part, legs_part]:
		part.queue_redraw()
	request_weapon_redraw()
	if is_instance_valid(variant_visual):
		variant_visual.queue_redraw()
	queue_redraw()

func _process_burst(delta: float) -> void:
	if target != burst_target or not is_instance_valid(burst_target):
		burst_remaining = 0
		attack_clock = float(profile.cooldown)
		return
	burst_clock -= delta
	if burst_clock > 0:
		return
	if not attack_obstacle():
		burst_remaining = 0
	else:
		burst_remaining -= 1
	burst_clock += float(profile.burst_gap)
	if burst_remaining == 0:
		attack_clock = float(profile.cooldown) * (0.90 if elite else 1.0)

func target_attack_point() -> Vector2:
	if not is_instance_valid(target):
		return global_position + Vector2(attack_direction*attack_reach,-40)
	if target.has_method("attack_point"):
		return target.attack_point()
	# The dome front deliberately anchors at450 so this strikes real lower glass410.
	return target.global_position + Vector2(0, -40)

## Readability (style bible §3): the smallest walkers sat dark and low
## against the fence base and the dark ground; their whole drawing is lifted
## a value step, so silhouette and contrast both carry the class.
const VALUE_LIFT := {"runner":Color(1.34,1.31,1.25), "repair_crawler":Color(1.26,1.24,1.19)}
const HULL_TILT_STEP := 0.03
## Hit read of a machine: the whole machine brightens together for the first
## frames of the replicated 0.2 s hit timer, then one gentler step, then off.
## A multiply keeps every texel of detail and reads the same on a downscaled
## painted hull, native limb plates and drawn weapons alike (the actor
## shader's silhouette rim works in atlas texels, so it outlined only the
## limbs). Reduced effects keep only the gentle step.
const FLASH_HOT := Color(1.42,1.36,1.22)
const FLASH_WARM := Color(1.16,1.13,1.08)

static func machine_flash(timer: float, quiet: bool = false) -> Color:
	if timer > .13: return FLASH_WARM if quiet else FLASH_HOT
	if timer > .08 and not quiet: return FLASH_WARM
	return Color.WHITE

func _pose_parts() -> void:
	RhythmPresentation.machine_accent(self)
	# Shared hit read: one flash on every part, a tiny swell of the hull only.
	var quiet_hits := WeaponEffectArt.reduced(game)
	var flash := machine_flash(hit_flash,quiet_hits)
	for part in [body_part,legs_part,weapon_part]:
		part.modulate = flash
	if VALUE_LIFT.has(kind):
		for part in [body_part,legs_part]: part.self_modulate = VALUE_LIFT[kind]
	# The hit pulse is whole texels (the vehicle's springs, the walker's
	# knock in _hull_life), never a swell of the baked hull.
	if VehicleArt.is_vehicle(kind):
		VehicleArt.pose_parts(self)
		return
	var mirror := -attack_direction
	for part in [body_part,legs_part]:
		part.scale = Vector2(mirror,1)*visual_scale
	weapon_part.scale = Vector2(mirror,1)*visual_scale*0.78
	var bob := absf(sin(gait)) * (2.6 if moving else 0.4) * visual_scale
	var brace := maxf(clampf(windup / maxf(0.01, float(profile.windup)), 0, 1),clampf(worker_windup/worker_windup_duration(),0,1))
	body_part.position = Vector2(weapon_recoil * 0.4 + brace * (2.0 if chassis_kind() == "siege" else 0.7), -body_height - bob + brace * 1.7)
	body_part.position.x *= mirror
	body_part.rotation = sin(gait) * (0.027 if moving else 0.0) + (0.035 if hit_flash > 0.1 else 0.0)
	weapon_part.position = Vector2(-22 * visual_scale + weapon_recoil, -body_height + 11 * visual_scale - bob + brace)
	weapon_part.position.x *= mirror
	if is_instance_valid(motion) and not motion.pose.is_empty():
		var offset: Vector2 = motion.pose.offset
		offset.x *= mirror
		body_part.position += offset*visual_scale
		body_part.rotation += float(motion.pose.roll)*mirror
		weapon_part.position += offset*visual_scale
	_hull_lift = _hull_life(brace,mirror)
	body_part.position += _hull_lift
	# The shot pitches the nose up for two tilt stances, settling with the recoil.
	body_part.rotation += 0.06*clampf(weapon_recoil/maxf(0.01,5.0*visual_scale),0.0,1.0)*mirror
	# Authored tilt steps: the painted hull holds each attitude for a few
	# frames instead of being resampled at a new sub-degree angle every frame,
	# which made its texel grid shimmer. Presentation only (aim is separate).
	body_part.rotation = snappedf(body_part.rotation,HULL_TILT_STEP)
	if kind=="repair_crawler":
		body_part.position.y+=8.0*visual_scale
		weapon_part.position.y+=8.0*visual_scale
	if is_instance_valid(target):
		var aim_point := worker_target.global_position-Vector2(0,23) if worker_windup>0 and is_instance_valid(worker_target) else target_attack_point()
		if muzzle_flash>0:
			# The worker windup clears immediately after firing. Retain the real
			# impact point through the flash instead of snapping back to the wall.
			aim_point = to_global(tracer_end)
		if is_instance_valid(abilities) and abilities.projectile_attack() and abilities.aim_locked:
			aim_point=abilities.aim_point
		var aim := to_local(aim_point) - weapon_part.position
		# Left/up is returned near -PI; normalize before applying the joint stops.
		# Using local coordinates also keeps scaled inspection scenes consistent.
		weapon_part.rotation = clampf(wrapf(Vector2(aim.x*mirror,aim.y).angle()-PI,-PI,PI),-1.12,0.38)*mirror
	if kind=="bastion":
		body_part.scale.x*=1.10
	_pose_weapon_keys()

## Life of a walker's hull on top of its gait (presentation only, whole world
## texels): a fresh hit knocks it a texel back; standing, it breathes up a
## texel on a held beat; through the wind-up it sinks into a brace in three
## held frames and leans back off the target (the anticipation of style bible
## 5, inside the existing wind-up).
func _hull_life(brace: float, mirror: float) -> Vector2:
	if VehicleArt.is_vehicle(kind): return Vector2.ZERO
	var clock: float = float(motion.get("clock")) if is_instance_valid(motion) else age
	if hit_flash > 0.13 and not WeaponEffectArt.reduced(game): return Vector2(mirror,0.0)
	if brace > 0.0:
		var frame := minf(3.0,floorf(brace*3.0+0.0001)+1.0)
		return Vector2((1.0 if frame >= 2.0 else 0.0)*mirror,frame)
	if moving: return Vector2.ZERO
	return Vector2(0.0,-1.0 if sin(clock*2.1+float(absi(kind.hash())%7)) > 0.3 else 0.0)

## Bake key of the drawn weapon keys: family and drawn scale x 1000 (as
## tools/bake_machine_weapons_world.py rounds it).
func weapon_bake_key() -> String:
	return "%d|%d" % [weapon_family(),floori(visual_scale*1000.0+0.5)]

static func weapon_world_texture() -> Texture2D:
	if _weapon_world == null and ResourceLoader.exists(WEAPON_WORLD_PATH): _weapon_world = load(WEAPON_WORLD_PATH)
	return _weapon_world

## Family row of the baked walker cannons, or -1 where the weapon is drawn by
## its vehicle or variant equipment.
func weapon_family() -> int:
	if VehicleArt.is_vehicle(kind) or GroundVariantVisual.has_special_weapon(kind): return -1
	return int(WEAPON_FAMILIES.get(chassis_kind(),0))

func _pose_weapon_keys() -> void:
	if not is_instance_valid(weapon_keys) or weapon_keys.get_parent() != weapon_part: return
	var family := weapon_family()
	weapon_keys.visible = family >= 0
	if family < 0: return
	var mirror := -float(attack_direction)
	var exact := weapon_part.rotation*mirror/WEAPON_KEY
	if absf(exact-float(_weapon_step)) > 0.9 or _weapon_step < WEAPON_STEPS.x or _weapon_step > WEAPON_STEPS.y:
		_weapon_step = clampi(roundi(exact),WEAPON_STEPS.x,WEAPON_STEPS.y)
	# Cancel the node's turn and 0.78 scale: one unit per world texel (the
	# keys baked at this drawn size), mirror only, riding the hull's life.
	var turned := Transform2D(weapon_part.rotation,weapon_part.scale,0.0,Vector2.ZERO)
	var baked := WeaponIndex.BASES.has(weapon_bake_key()) and weapon_world_texture() != null
	var unit := 1.0 if baked else visual_scale
	var upright := Transform2D(Vector2(mirror*unit,0.0),Vector2(0.0,unit),_hull_lift)
	weapon_keys.transform = turned.affine_inverse()*upright
	var charge := roundi(clampf(windup/maxf(0.01,float(profile.windup)),0.0,1.0)*16.0) if chassis_kind() == "siege" else 0
	var drawn := Vector3i(family,_weapon_step,charge)
	# The drawn key snaps to the world grid where the node stands, so a move
	# of the weapon node also redraws it.
	if drawn != _weapon_keys_drawn or baked:
		_weapon_keys_drawn = drawn
		weapon_keys.queue_redraw()

func _draw_weapon_keys() -> void:
	var family := weapon_family()
	if family < 0: return
	var key := weapon_bake_key()
	var baked := WeaponIndex.BASES.has(key) and weapon_world_texture() != null
	var drawn_scale := 1.0
	if baked:
		# The key baked at this drawn size, 1:1 with its pivot on a world texel.
		drawn_scale = visual_scale
		weapon_keys.draw_set_transform_matrix(WorldTexels.on_grid(weapon_keys,Transform2D.IDENTITY))
		var i := (int(WeaponIndex.BASES[key])+clampi(_weapon_step,WEAPON_STEPS.x,WEAPON_STEPS.y)-WeaponIndex.STEPS.x)*6
		var data: Array[int] = WeaponIndex.DATA
		var size := Vector2(data[i+2],data[i+3])
		weapon_keys.draw_texture_rect_region(weapon_world_texture(),Rect2(Vector2(data[i+4],data[i+5]),size),Rect2(Vector2(data[i],data[i+1]),size))
	else:
		_draw_weapon_key(weapon_keys,family,_weapon_step)
	if chassis_kind() == "siege":
		# Charge lamp in the drawn breech, on the key's own texels.
		var lamp := (Transform2D(float(_weapon_step)*WEAPON_KEY,Vector2.ZERO)*(Vector2(-34,-1)*drawn_scale)).round()
		var charge := float(_weapon_keys_drawn.z)/16.0
		Quads.rect(weapon_keys,Rect2(lamp-Vector2.ONE,Vector2(2,2)),Color("ef7c4f").lerp(Color("fff0bc"),charge))
	weapon_keys.draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_weapon_key(canvas: CanvasItem, family: int, step: int) -> void:
	var cell := Rect2(float(step-WEAPON_STEPS.x)*WEAPON_CELL,float(family)*WEAPON_CELL,WEAPON_CELL,WEAPON_CELL)
	canvas.draw_texture_rect_region(WEAPON_KEYS,Rect2(-Vector2.ONE*WEAPON_CELL*0.5,Vector2.ONE*WEAPON_CELL),cell)

func uses_rolling_contacts() -> bool:
	return VehicleArt.is_vehicle(kind)

func nearest_obstacle() -> Node2D:
	if is_instance_valid(game) and "expedition" in game and is_instance_valid(game.expedition):
		var convoy_target: Node2D=game.expedition.combat_target_for(self)
		if is_instance_valid(convoy_target): return convoy_target
	var closest: Node2D
	var nearest_distance := INF
	var scenario := ScenarioCombat.for_game(game)
	var core_distance := INF
	if scenario != null:
		core_distance = (scenario.core_x-global_position.x)*attack_direction+32.0
	for wall in get_tree().get_nodes_in_group("walls"):
		if not is_instance_valid(wall) or wall.is_queued_for_deletion() or wall.get("game")!=game: continue
		if not wall.is_blocking(): continue
		var distance: float = (wall.global_position.x-global_position.x)*attack_direction
		if scenario != null and (absf(wall.global_position.y-global_position.y)>74 or distance>core_distance):
			continue
		if distance>=-17 and distance<nearest_distance:
			closest = wall
			nearest_distance = distance
	if closest != null: return closest
	if is_instance_valid(game) and is_instance_valid(game.core): return game.core
	return null

func _visible_worker(candidate) -> bool:
	if not is_instance_valid(candidate) or not candidate is Node2D or candidate.is_queued_for_deletion() or candidate.get("game") != game or not candidate.has_method("can_be_targeted") or not candidate.can_be_targeted():
		return false
	var chest: Vector2 = candidate.global_position-Vector2(0,23)
	# Machines face the bunker. This prevents an unseen rearward attack while
	# still threatening anyone who steps outside cover or into the firing line.
	if (candidate.global_position.x-global_position.x)*attack_direction < -12 or absf(chest.y-weapon_part.global_position.y)>92 or chest.distance_to(weapon_part.global_position)>float(profile.get("worker_range",WORKER_TARGET_RANGE)):
		return false
	var query := PhysicsRayQueryParameters2D.create(weapon_part.global_position,chest,1|2|8)
	query.hit_from_inside = true
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider==candidate

func _update_worker_attack(delta: float) -> bool:
	if worker_windup <= 0 and worker_attack_clock <= 0 and burst_remaining==0:
		var distance := INF
		worker_target = null
		for candidate in get_tree().get_nodes_in_group("players"):
			if _visible_worker(candidate):
				var candidate_distance: float = global_position.distance_to(candidate.global_position)
				if candidate_distance < distance:
					distance = candidate_distance
					worker_target = candidate
		if is_instance_valid(worker_target):
			worker_windup = 0.001
			if is_instance_valid(abilities): abilities.prepare_attack(worker_target.global_position-Vector2(0,23))
	if worker_windup <= 0:
		return false
	if not _visible_worker(worker_target):
		worker_windup = 0.0
		worker_target = null
		worker_attack_clock = 0.35
		return false
	windup = 0.0
	worker_windup += delta
	if worker_windup >= worker_windup_duration():
		_pose_parts()
		if _fire_collision_shot(worker_target.global_position-Vector2(0,23),worker_target,worker_shot_damage()):
			worker_attack_count += 1
		worker_windup = 0.0
		worker_target = null
		worker_attack_clock = float(profile.get("worker_interval",WORKER_ATTACK_INTERVAL))
	return true

func worker_shot_damage() -> float:
	if not profile.has("worker_damage"): return clampf(attack_damage*.8,6.0,42.0)
	return float(profile.worker_damage)*attack_damage/float(profile.damage)

func attack_obstacle() -> bool:
	if not is_instance_valid(target) or not target.has_method("take_damage"):
		return false
	if target != nearest_obstacle():
		return false
	if absf(global_position.x - target.global_position.x) > attack_reach + 13:
		return false
	_pose_parts()
	return _fire_collision_shot(target_attack_point(),target,attack_damage*(abilities.strike_multiplier() if is_instance_valid(abilities) else 1.0))

func _fire_collision_shot(destination: Vector2, intended: Node2D, damage: float) -> bool:
	if dead: return false
	if is_instance_valid(abilities) and abilities.projectile_attack():
		return abilities.fire_projectiles(destination,damage)
	var start := weapon_part.global_position
	# A worker can intercept an enemy round. Terrain, concrete and glass always
	# stop it before the intended target; incapacitated workers have no hit layer.
	var query := PhysicsRayQueryParameters2D.create(start,destination,1|2|8)
	query.hit_from_inside = true
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	var victim: Node2D = intended
	var impact_pos := destination
	var surface_normal := (start-destination).normalized()
	if not hit.is_empty():
		victim = hit.collider
		impact_pos = hit.position
		if hit.normal.length_squared()>0.01:
			surface_normal = hit.normal
		var friendly_escort: bool=victim.is_in_group("convoy_defenders") and victim.get("game")==game and victim.has_method("can_be_targeted") and victim.can_be_targeted()
		if victim != intended and not victim.is_in_group("players") and not friendly_escort:
			return false
	if not is_instance_valid(victim) or not victim.has_method("take_damage"):
		return false
	if victim.is_in_group("convoy_defenders") and (victim.get("game")!=game or not victim.has_method("can_be_targeted") or not victim.can_be_targeted()): return false
	var worker_hit := victim.is_in_group("players") and victim.has_method("can_be_targeted")
	if worker_hit and not victim.can_be_targeted():
		return false
	preload("res://scripts/scenery_damage.gd").projectile_path(game,start,impact_pos,damage,"enemy",{},true)
	var produces_impact: bool = not worker_hit or victim.invulnerability <= 0.0
	if produces_impact and is_instance_valid(game):
		ImpactBurst.contact(game,victim,impact_pos,surface_normal,(destination-start).normalized(),clampf(damage/25.0,0.5,2.1))
	if worker_hit:
		victim.take_damage(damage,(destination-start).normalized())
	else:
		victim.take_damage(damage)
	if is_instance_valid(abilities):
		abilities.after_strike(victim,impact_pos,surface_normal)
	attack_count += 1
	tracer_end = impact_pos-global_position
	weapon_recoil = (11.0 if chassis_kind() == "siege" else (3.0 if chassis_kind() == "assault" else 5.0))*visual_scale
	muzzle_flash = 0.19 if chassis_kind() == "siege" else 0.09
	if is_instance_valid(game):
		preload("res://scripts/spatial_sound.gd").emit(game,"enemy_shot",global_position)
	return true

func take_damage(amount: float) -> void:
	if dead or not is_finite(amount) or amount<=0:
		return
	if is_instance_valid(game) and int(get_meta("impact_contact_frame",-1))!=Engine.get_physics_frames():
		if game.has_method("impact"):
			game.impact(global_position-Vector2(0,body_height),"metal",Vector2.LEFT,clampf(amount/32.0,0.5,1.8))
		else:
			game.fx(global_position-Vector2(0,body_height),Color("ebbe79"),8)
	if is_instance_valid(abilities):
		amount = abilities.filter_damage(amount)
		if amount<=0:
			if is_instance_valid(variant_visual):
				variant_visual.queue_redraw()
			return
	hp = maxf(0, hp - amount)
	hit_flash = 0.2
	stagger = 0.16
	if hp <= 0:
		die()
	else:
		queue_redraw()

func die() -> void:
	if dead:
		return
	dead = true
	CampaignSalvage.drop_for_enemy(game,self)
	collision_layer = 0
	remove_from_group("enemies")
	if is_instance_valid(game):
		if "stats" in game:
			game.stats["kills"] = int(game.stats.get("kills", 0)) + 1
		if game.has_method("impact"):
			game.impact(global_position-Vector2(0,body_height*0.7),"explosion",Vector2.UP,clampf(visual_scale,0.8,1.8))
		else:
			game.fx(global_position + Vector2(0, -35), Color("e9b466"), 22)
			game.fx(global_position + Vector2(0, -35), Color("758b8c"), 18)
		game.spawn_pickup("scrap", int(profile.scrap) + (1 if elite else 0), global_position + Vector2(-14, -14))
		game.spawn_pickup("core", int(profile.cores), global_position + Vector2(16, -18))
		preload("res://scripts/spatial_sound.gd").emit(game,"explosion",global_position)
	spawn_motion_wreck()
	queue_free()

func spawn_motion_wreck() -> void:
	if is_instance_valid(motion): motion.spawn_wreck()

func _draw() -> void:
	Quads.rect(self,Rect2(-44*visual_scale, -2, 87*visual_scale, 5), Color(0, 0, 0, 0.32))
	if hp < max_hp and not preload("res://scripts/threat_overlay.gd").covers(self):
		Art.bar(self, Rect2(-31*visual_scale, -body_height-37*visual_scale, 62*visual_scale, 4), hp / max_hp, Art.RED)
	# Names follow the overlay rule (elite, boss, final boss) also without a HUD.
	if show_status_labels and preload("res://scripts/threat_overlay.gd").shows_name(self) and not preload("res://scripts/threat_overlay.gd").covers(self):
		var label: String = str(profile.get("label", ""))
		Art.text(self, Vector2(-29*visual_scale, -body_height-41*visual_scale), LocaleText.format("ELITE · %s", label) if elite else LocaleText.text(label), 10, Color("ba8e69"))
	if is_instance_valid(abilities): abilities.draw_telegraph()
	if muzzle_flash > 0 and not (is_instance_valid(abilities) and abilities.projectile_attack()):
		# Hostile fire as a self-lit streak on the shared effect layer, once
		# per replicated shot; a plain line where no game layer exists.
		var muzzle_at: Vector2 = weapon_part.to_global(weapon_muzzle())
		var feel: Node2D = preload("res://scripts/combat_feel.gd").of(self)
		if feel == null:
			draw_line(to_local(muzzle_at), tracer_end, Color(1.0, 0.32, 0.19, 0.75), 2*visual_scale)
		elif int(get_meta(&"traced_shot", -1)) != attack_count:
			set_meta(&"traced_shot", attack_count)
			feel.trace(muzzle_at, to_global(tracer_end), roundf(1.4*visual_scale))
	if (windup > 0 or worker_windup > 0) and not VehicleArt.is_vehicle(kind):
		var charge := maxf(clampf(windup / float(profile.windup),0,1),clampf(worker_windup/worker_windup_duration(),0,1))
		var glow_pos := to_local(weapon_part.to_global(weapon_muzzle()))
		draw_circle(glow_pos, ((8+charge*12) if chassis_kind() == "siege" else (5+charge*5))*visual_scale, Color(1,0.26,0.07,charge*0.075))
		if chassis_kind() == "siege":
			draw_arc(glow_pos, (10+charge*4)*visual_scale, -PI*0.5, -PI*0.5+TAU*charge, 16, Color("ec9e56"),2)
			Art.bar(self,Rect2(-27*visual_scale,-body_height-34*visual_scale,54*visual_scale,4),charge,Color("ed764f"))

## Presentation only. Local foot travel per gait radian that equals the hull's
## real ground travel, from the replicated speed: a planted foot stays on its
## world position at every wave speed scale, during the speed ramp and in a rush.
func stride_per_radian() -> float:
	var rate := float(profile.gait)*maxf(0.001,visual_scale)
	# Prepared fixtures pose `moving` without the speed ramp of the simulation.
	if locomotion_speed<=0.0: return move_speed/rate if moving else 0.0
	return minf(locomotion_speed/clampf(locomotion_speed/move_speed,0.3,1.0),move_speed*3.0)/rate

## Eased 0..1 step height. Feet are set down while the hull brakes instead of
## snapping to the rest stance on the frame `moving` clears.
func stride_amount() -> float:
	if locomotion_speed<=0.0: return 1.0 if moving else 0.0
	return smoothstep(0.0,0.6,locomotion_speed/move_speed)

## Offset along the travel axis for one leg. Stance (the half cycle with the
## foot down) is linear in phase; the swing returns on a quintic whose end
## tangents match the stance, so toe-off and contact have no velocity step.
static func stride_offset(phase: float, per_radian: float) -> float:
	var theta := fposmod(phase-PI*0.5,TAU)
	if theta<PI: return per_radian*(theta-PI*0.5)
	var swing := (theta-PI)/PI
	var progress := swing*swing*swing*(10.0+swing*(-15.0+swing*6.0))
	return per_radian*PI*(0.5-progress+swing*(1.0-swing)*(1.0-2.0*swing))

func leg_foot(index: int) -> Vector2:
	if VehicleArt.is_vehicle(kind):
		return VehicleArt.contact(kind,index)
	var side := -1.0 if index<float(profile.legs)*0.5 else 1.0
	var phase := gait+(0.0 if index%2==0 else PI)
	var lift := maxf(0,cos(phase))*8.0*stride_amount()
	var spread := 21.0 if chassis_kind()=="runner" else 31.0
	var foot := Vector2(side*(spread+index%3*8)+stride_offset(phase,stride_per_radian()),-3.0-lift)
	if is_instance_valid(motion) and not motion.pose.is_empty(): foot.x += side*float(motion.pose.foot)
	return foot

func _draw_legs() -> void:
	if VehicleArt.is_vehicle(kind):
		VehicleArt.draw_running_gear(self)
		return
	var count := int(profile.legs)
	var amount := stride_amount()
	for index in count:
		var side := -1 if index < count/2.0 else 1
		var offset := 0.0 if index % 2 == 0 else PI
		var step := sin(gait + offset)*amount
		var lift := maxf(0, cos(gait + offset)) * 8.0 * amount
		var root_pos := legs_part.to_local(body_part.to_global(Vector2(side*17,5)))
		var spread := 21.0 if chassis_kind() == "runner" else 31.0
		var foot := leg_foot(index)
		# The knee leads the foot through the swing and trails it in stance.
		var knee := Vector2(side * (spread + index % 3 * 5) + (foot.x-side*(spread+index%3*8))*0.55 + step * 2.0, -body_height/visual_scale*0.48 - lift * 0.4)
		if is_instance_valid(motion) and not motion.pose.is_empty():
			knee.y += float(motion.pose.knee)
		var far_side := index%2==1
		var heavy := chassis_kind() in ["colossus","siege","breaker"]
		var limb_width := 13.0 if heavy else 10.0
		LIMB_ART.plate(legs_part,root_pos,knee,limb_width,index*11+7,far_side)
		LIMB_ART.plate(legs_part,knee,foot,limb_width-1,index*17+19,far_side)
		var rod_start := root_pos.lerp(knee,0.27)+Vector2(3,0)
		var rod_end := knee.lerp(foot,0.55)+Vector2(3,0)
		LIMB_ART.piston(legs_part,rod_start,rod_end,far_side)
		LIMB_ART.joint(legs_part,root_pos,4.0 if heavy else 3.5,far_side)
		LIMB_ART.joint(legs_part,knee,6.5 if heavy else 5.0,far_side)
		LIMB_ART.joint(legs_part,foot+Vector2(0,-3),3.5,far_side)
		LIMB_ART.foot(legs_part,foot,heavy,far_side)

## Where the painted chassis covers the body, in body units (before the
## machine's visual scale).
static func chassis_rect(machine_kind: String, machine_profile: Dictionary) -> Rect2:
	var chassis := str(machine_profile.get("chassis",machine_kind))
	var region: Rect2 = BODY_REGIONS.get(chassis,BODY_REGIONS.strider)
	var width: float = machine_profile.body_size.x
	if chassis == "colossus": width = 74.0
	elif chassis == "siege": width = 79.0
	elif chassis == "breaker": width = 78.0
	var dimensions := Vector2(width,width*region.size.y/region.size.x)
	return Rect2(Vector2(-dimensions.x*0.5,-24 if chassis != "runner" else -19),dimensions)

## World size of a chassis drawn at `drawn_scale` (the machine's visual
## scale): its bake key, one texel per world unit. The bastion's hull is
## drawn 10 % wider (_pose_parts).
static func chassis_texels(machine_kind: String, machine_profile: Dictionary, drawn_scale: float) -> Vector2i:
	var size := chassis_rect(machine_kind,machine_profile).size*drawn_scale
	if machine_kind == "bastion": size.x *= 1.10
	return Vector2i(size.round())

func _draw_chassis_art() -> void:
	var region: Rect2 = BODY_REGIONS.get(chassis_kind(),BODY_REGIONS.strider)
	var rect := chassis_rect(kind,profile)
	# The hit shows as the whole machine's flash (machine_flash), not as an
	# overexposed fill of the illustrated hull. The chassis is its bake at the
	# drawn size in the nearest lean stance, upright on world texels; the
	# graded atlas only for a size that was never baked.
	if not WorldTexels.draw_stance(body_part,CHASSIS_PATH,region,rect,chassis_texels(kind,profile,visual_scale)):
		body_part.draw_texture_rect_region(WorldTexels.fallback_source(CHASSIS_PATH),rect,region)
	# Tiny live sensor light complements the fixed illustrated optics.
	var sensor := Vector2(-rect.size.x*0.40,-3)
	var pulse := 0.11+sin(age*4.8)*0.035+clampf(windup,0,0.6)*0.13
	if PixelArt.supports_grid(body_part): PixelArt.grid_blob(body_part,sensor,6.0,Color(1,0.15,0.04,pulse))
	else: body_part.draw_circle(sensor,6,Color(1,0.15,0.04,pulse))
	# Marks on the plate in whole world texels of its upright frame.
	body_part.draw_set_transform_matrix(WorldTexels.upright(body_part))
	if elite:
		var bar := WorldTexels.upright_point(body_part,Vector2(-5,-27)).round()
		Quads.rect(body_part,Rect2(bar,Vector2(16,4)),Color("20251f"))
		for stripe in range(3):
			Quads.rect(body_part,Rect2(bar+Vector2(2+stripe*5,0),Vector2(3,3)),Color("e6af55"))
	if chassis_kind() == "assault" and burst_remaining > 0:
		Quads.rect(body_part,Rect2(WorldTexels.upright_point(body_part,Vector2(7,-11)).round(),Vector2(3,3)),Color("f3c270"))
	body_part.draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_body() -> void:
	if VehicleArt.is_vehicle(kind):
		VehicleArt.draw_hull(self)
		return
	if chassis_atlas != null:
		_draw_chassis_art()
		return
	var shell := Color("7c8985") if hit_flash > 0.13 else Color("46535a")
	if chassis_kind() == "runner":
		_draw_runner_body(shell)
		return
	body_part.draw_colored_polygon(PackedVector2Array([Vector2(-33, -14), Vector2(-23, -22), Vector2(19, -22), Vector2(36, -10), Vector2(32, 15), Vector2(-26, 15), Vector2(-36, 3)]), Art.INK)
	body_part.draw_colored_polygon(PackedVector2Array([Vector2(-30, -11), Vector2(-21, -18), Vector2(18, -18), Vector2(31, -8), Vector2(28, 11), Vector2(-24, 11), Vector2(-31, 1)]), shell)
	body_part.draw_line(Vector2(-21, -18), Vector2(18, -18), Color("9a9c8d"), 2)
	Quads.rect(body_part,Rect2(-11, -13, 25, 20), Color("222d34"))
	Quads.rect(body_part,Rect2(-9, -11, 21, 3), Color("64706e"))
	for index in range(5):
		Quads.rect(body_part,Rect2(-8 + index * 4, -6, 2, 11), Color("111c22"))
	Quads.rect(body_part,Rect2(17, -12, 10, 19), Color("596660"))
	Quads.rect(body_part,Rect2(18, -11, 8, 3), Color("939785"))
	body_part.draw_line(Vector2(23, -8), Vector2(19, 5), Color("343f43"), 2)
	Quads.rect(body_part,Rect2(-29, -11, 14, 12), Art.INK)
	body_part.draw_circle(Vector2(-25, -5), 10, Color(0.95, 0.12, 0.08, 0.1))
	Quads.rect(body_part,Rect2(-28, -8, 6, 6), Color("d44b3e"))
	Quads.rect(body_part,Rect2(-27, -7, 3, 3), Color("ffae83"))
	Quads.rect(body_part,Rect2(-34, 4, 8, 6), Color("232d34"))
	Quads.rect(body_part,Rect2(1, -26, 3, 7), Color("1a252b"))
	body_part.draw_line(Vector2(2, -25), Vector2(7, -35 if elite else -29), Color("596c6a"), 2)
	if elite:
		Quads.rect(body_part,Rect2(-17, -25, 32, 7), Art.INK)
		Quads.rect(body_part,Rect2(-14, -24, 25, 4), Color("958570"))
		Quads.rect(body_part,Rect2(4, -23, 6, 2), Color("f2aa57"))
	for point in [Vector2(-19, -15), Vector2(25, -7), Vector2(22, 8), Vector2(-22, 8)]:
		Quads.rect(body_part,Rect2(point, Vector2(2, 2)), Color("a5a591"))
	if chassis_kind() in ["breaker", "colossus", "siege"]:
		_draw_heavy_armor(shell)

func _draw_runner_body(shell: Color) -> void:
	body_part.draw_colored_polygon(PackedVector2Array([Vector2(-31,-9), Vector2(-18,-23), Vector2(15,-18), Vector2(31,-2), Vector2(16,12), Vector2(-23,8)]), Art.INK)
	body_part.draw_colored_polygon(PackedVector2Array([Vector2(-26,-7), Vector2(-17,-18), Vector2(13,-14), Vector2(24,-1), Vector2(14,7), Vector2(-21,4)]), shell)
	body_part.draw_line(Vector2(-17,-18),Vector2(13,-14),Color("8f9a8e"),2)
	Quads.rect(body_part,Rect2(-28,-8,15,8),Art.INK)
	Quads.rect(body_part,Rect2(-27,-6,11,3),Color("ff664b"))
	Quads.rect(body_part,Rect2(-25,-6,3,2),Color("ffe2b8"))
	Quads.rect(body_part,Rect2(8,-12,10,12),Color("26353d"))
	for i in 3:
		body_part.draw_line(Vector2(10+i*3,-10),Vector2(8+i*3,-2),Color("789088"),1)
	body_part.draw_line(Vector2(14,-16),Vector2(22,-29),Color("566e6c"),2)
	Quads.rect(body_part,Rect2(20,-31,5,4),Color("ed7751"))

func _draw_heavy_armor(shell: Color) -> void:
	# Faceted side shields and an elevated engine distinguish the armored classes.
	body_part.draw_colored_polygon(PackedVector2Array([Vector2(-29,-18),Vector2(-15,-27),Vector2(19,-25),Vector2(38,-9),Vector2(33,19),Vector2(15,22),Vector2(13,6),Vector2(-14,3),Vector2(-24,18),Vector2(-38,10)]),Art.INK)
	body_part.draw_colored_polygon(PackedVector2Array([Vector2(-25,-16),Vector2(-14,-23),Vector2(17,-21),Vector2(34,-7),Vector2(29,15),Vector2(19,17),Vector2(17,1),Vector2(-18,-1),Vector2(-26,13),Vector2(-33,7)]),shell.lightened(0.08))
	body_part.draw_line(Vector2(-14,-23),Vector2(17,-21),Color("b0a18a"),3)
	Quads.rect(body_part,Rect2(-33,-12,17,11),Art.INK)
	Quads.rect(body_part,Rect2(-31,-9,11,4),Color("f66748"))
	Quads.rect(body_part,Rect2(-10,-16,29,19),Color("27343b"))
	Quads.rect(body_part,Rect2(-8,-14,25,3),Color("819086"))
	for vent in 5:
		Quads.rect(body_part,Rect2(-6+vent*5,-8,2,8),Color("121e25"))
		Quads.rect(body_part,Rect2(-5+vent*5,-8,1,7),Color("62706a"))
	body_part.draw_line(Vector2(22,-17),Vector2(31,-8),Color("abb098"),2)
	body_part.draw_line(Vector2(31,-8),Vector2(27,11),Color("2b393e"),2)
	Quads.rect(body_part,Rect2(-29,4,6,5),Color("a38762"))
	for point in [Vector2(-19,-17),Vector2(-11,-21),Vector2(17,-18),Vector2(28,-5),Vector2(26,13),Vector2(-29,8)]:
		Quads.rect(body_part,Rect2(point-Vector2.ONE,Vector2(3,3)),Color("273138"))
		Quads.rect(body_part,Rect2(point,Vector2(1,1)),Color("d3c6a1"))
	for chip in [Vector2(-15,-20),Vector2(11,-19),Vector2(30,6),Vector2(-28,10)]:
		body_part.draw_line(chip,chip+Vector2(3,-1),Color("93a092"),1)
	for x in [-20,23]:
		Quads.rect(body_part,Rect2(x,4,5,9),Color("967656"))
		body_part.draw_line(Vector2(x,5),Vector2(x+5,9),Art.INK,2)
	if chassis_kind() == "colossus":
		for x in [13,25]:
			Quads.rect(body_part,Rect2(x,-40,8,21),Art.INK)
			Quads.rect(body_part,Rect2(x+2,-38,4,17),Color("758178"))
			Quads.rect(body_part,Rect2(x,-41,8,3),Color("b0855d"))
		Quads.rect(body_part,Rect2(-13,-36,25,13),Art.INK)
		Quads.rect(body_part,Rect2(-11,-34,21,9),Color("514b46"))
		Quads.rect(body_part,Rect2(-8,-31,14,3),Color("eb944e"))
		Quads.rect(body_part,Rect2(27,-16,14,24),Color("29363d"))
		for y in [-12,-7,-2]:
			Quads.rect(body_part,Rect2(29,y,9,2),Color("a97d59"))

func weapon_muzzle() -> Vector2:
	if VehicleArt.is_vehicle(kind):
		return VehicleArt.muzzle(kind)
	if GroundVariantVisual.has_special_weapon(kind):
		return GroundVariantVisual.weapon_tip(self)
	return Vector2(-49 if chassis_kind() == "siege" else (-42 if chassis_kind() in ["colossus","assault"] else -35),0)

func request_weapon_redraw() -> void:
	if not is_instance_valid(weapon_part): return
	# Aim, recoil, mirroring and mechanical poses move the CanvasItem itself.
	# Retain its unchanged drawing commands; shader instance parameters also
	# update independently. Variant and vehicle mechanisms still redraw fully.
	if VehicleArt.is_vehicle(kind) or GroundVariantVisual.has_special_weapon(kind):
		_weapon_draw_part_id = 0
		weapon_part.queue_redraw()
		return
	var chassis := chassis_kind()
	var flash := muzzle_flash > 0.0
	var charge := clampf(windup / float(profile.windup), 0.0, 1.0) if chassis == "siege" else 0.0
	var part_id := weapon_part.get_instance_id()
	if part_id == _weapon_draw_part_id and chassis == _weapon_draw_chassis and flash == _weapon_draw_flash and charge == _weapon_draw_charge:
		return
	weapon_part.queue_redraw()

func _draw_weapon() -> void:
	if VehicleArt.is_vehicle(kind):
		VehicleArt.draw_weapon(self)
		return
	if is_instance_valid(variant_visual) and GroundVariantVisual.has_special_weapon(kind):
		variant_visual.draw_weapon(weapon_part)
		return
	# Commit only when commands are actually drawn. A pending redraw can be
	# cancelled by visibility/tree changes before CanvasItem processes it.
	_weapon_draw_part_id = weapon_part.get_instance_id()
	_weapon_draw_chassis = chassis_kind()
	_weapon_draw_flash = muzzle_flash > 0.0
	_weapon_draw_charge = clampf(windup / float(profile.windup), 0.0, 1.0) if _weapon_draw_chassis == "siege" else 0.0
	var family := weapon_family()
	if not is_instance_valid(weapon_keys) or weapon_keys.get_parent() != weapon_part:
		# Wreck delegate or a replaced part: the level key turns with the node
		# (the wreck's texel-block shader rasterises it on its own grid).
		weapon_part.draw_set_transform_matrix(Transform2D(0.0,Vector2.ONE/WEAPON_DRAWN_SCALE,0.0,Vector2.ZERO))
		_draw_weapon_key(weapon_part,family,0)
		weapon_part.draw_set_transform_matrix(Transform2D.IDENTITY)
	if muzzle_flash > 0:
		# Shared layered flash: siege guns use the cannon class, walkers the rifle class.
		var heavy := chassis_kind() == "siege"
		var bore := Vector2(float(WEAPON_BORES[family])/WEAPON_DRAWN_SCALE,0.0)
		# The node carries the walker's scale: a small walker's flash grows back
		# towards the common size, so a runner's shot reads as a shot.
		var reach := clampf(0.9/maxf(0.1,visual_scale),1.0,1.6)
		WeaponEffectArt.muzzle(weapon_part,bore,muzzle_flash,0.19 if heavy else 0.09,-1,(1.3 if heavy else 0.8)*reach,attack_count,WeaponEffectArt.reduced(game))
