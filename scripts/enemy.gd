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
	if ResourceLoader.exists("res://assets/enemies/chassis_atlas.png"):
		chassis_atlas = load("res://assets/enemies/chassis_atlas.png")
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

func _pose_parts() -> void:
	RhythmPresentation.machine_accent(self)
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
	if hp < max_hp:
		Art.bar(self, Rect2(-31*visual_scale, -body_height-37*visual_scale, 62*visual_scale, 4), hp / max_hp, Art.RED)
	if show_status_labels and chassis_kind() in ["breaker", "colossus", "siege"]:
		var label: String = str(profile.get("label", ""))
		Art.text(self, Vector2(-29*visual_scale, -body_height-41*visual_scale), LocaleText.format("ELITE · %s", label) if elite else LocaleText.text(label), 10, Color("ba8e69"))
	if is_instance_valid(abilities): abilities.draw_telegraph()
	if muzzle_flash > 0 and not (is_instance_valid(abilities) and abilities.projectile_attack()):
		draw_line(to_local(weapon_part.to_global(weapon_muzzle())), tracer_end, Color(1.0, 0.32, 0.19, 0.75), 2*visual_scale)
	if (windup > 0 or worker_windup > 0) and not VehicleArt.is_vehicle(kind):
		var charge := maxf(clampf(windup / float(profile.windup),0,1),clampf(worker_windup/worker_windup_duration(),0,1))
		var glow_pos := to_local(weapon_part.to_global(weapon_muzzle()))
		draw_circle(glow_pos, ((8+charge*12) if chassis_kind() == "siege" else (5+charge*5))*visual_scale, Color(1,0.26,0.07,charge*0.075))
		if chassis_kind() == "siege":
			draw_arc(glow_pos, (10+charge*4)*visual_scale, -PI*0.5, -PI*0.5+TAU*charge, 16, Color("ec9e56"),2)
			Art.bar(self,Rect2(-27*visual_scale,-body_height-34*visual_scale,54*visual_scale,4),charge,Color("ed764f"))

func leg_foot(index: int) -> Vector2:
	if VehicleArt.is_vehicle(kind):
		return VehicleArt.contact(kind,index)
	var side := -1.0 if index<float(profile.legs)*0.5 else 1.0
	var phase := gait+(0.0 if index%2==0 else PI)
	var lift := maxf(0,cos(phase))*(8.0 if moving else 0.0)
	var spread := 21.0 if chassis_kind()=="runner" else 31.0
	var foot := Vector2(side*(spread+index%3*8)-sin(phase)*(9.0 if moving else 0.0),-3.0-lift)
	if is_instance_valid(motion) and not motion.pose.is_empty(): foot.x += side*float(motion.pose.foot)
	return foot

func _draw_legs() -> void:
	if VehicleArt.is_vehicle(kind):
		VehicleArt.draw_running_gear(self)
		return
	var count := int(profile.legs)
	for index in count:
		var side := -1 if index < count/2.0 else 1
		var offset := 0.0 if index % 2 == 0 else PI
		var step := sin(gait + offset)
		var lift := maxf(0, cos(gait + offset)) * (8 if moving else 0)
		var root_pos := legs_part.to_local(body_part.to_global(Vector2(side*17,5)))
		var spread := 21.0 if chassis_kind() == "runner" else 31.0
		var knee := Vector2(side * (spread + index % 3 * 5) + step * 5, -body_height/visual_scale*0.48 - lift * 0.4)
		var foot := leg_foot(index)
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

func _draw_chassis_art() -> void:
	var region: Rect2 = BODY_REGIONS.get(chassis_kind(),BODY_REGIONS.strider)
	var width: float = profile.body_size.x
	if chassis_kind() == "colossus": width = 74.0
	elif chassis_kind() == "siege": width = 79.0
	elif chassis_kind() == "breaker": width = 78.0
	var dimensions := Vector2(width,width*region.size.y/region.size.x)
	var rect := Rect2(Vector2(-dimensions.x*0.5,-24 if chassis_kind() != "runner" else -19),dimensions)
	var tint := Color(1.55,1.45,1.15) if hit_flash > 0.13 else Color.WHITE
	body_part.draw_texture_rect_region(chassis_atlas,rect,region,tint)
	# Tiny live sensor light complements the fixed illustrated optics.
	var sensor := Vector2(-dimensions.x*0.40,-3)
	var pulse := 0.11+sin(age*4.8)*0.035+clampf(windup,0,0.6)*0.13
	body_part.draw_circle(sensor,6,Color(1,0.15,0.04,pulse))
	if elite:
		Quads.rect(body_part,Rect2(-5,-27,16,4),Color("20251f"))
		for stripe in range(3):
			Quads.rect(body_part,Rect2(-3+stripe*5,-27,3,3),Color("e6af55"))
	if chassis_kind() == "assault" and burst_remaining > 0:
		Quads.rect(body_part,Rect2(7,-11,3,3),Color("f3c270"))

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
	Quads.rect(weapon_part,Rect2(-19, -8, 28, 18), Art.INK)
	MechanismArt.face(weapon_part,Rect2(-17,-6,24,12),"dark",2)
	Quads.rect(weapon_part,Rect2(-34, -5, 20, 11), Art.INK)
	MechanismArt.face(weapon_part,Rect2(-33,-3,18,6),"steel",3)
	Quads.rect(weapon_part,Rect2(-35, -6, 7, 12), Color("263038"))
	Quads.rect(weapon_part,Rect2(-35, -3, 3, 5), Color("e35842"))
	Quads.rect(weapon_part,Rect2(-12, -5, 14, 2), Color("b2aa89"))
	Quads.rect(weapon_part,Rect2(-9, 2, 6, 8), Color("202b32"))
	if chassis_kind() in ["breaker", "colossus", "siege"]:
		Quads.rect(weapon_part,Rect2(-31,6,23,7),Art.INK)
		MechanismArt.face(weapon_part,Rect2(-29,7,19,3),"steel",1)
		Quads.rect(weapon_part,Rect2(-23,-10,21,5),Color("85785c"))
		weapon_part.draw_line(Vector2(-29,-6),Vector2(-25,7),Color("262f34"),3)
		if chassis_kind() == "colossus":
			Quads.rect(weapon_part,Rect2(-42,-8,11,17),Art.INK)
			MechanismArt.face(weapon_part,Rect2(-40,-5,7,10),"brass",2)
			Quads.rect(weapon_part,Rect2(-40,-2,4,5),Color("fa6c48"))
	if chassis_kind() == "assault":
		Quads.rect(weapon_part,Rect2(-38,-10,23,21),Art.INK)
		for barrel_index in range(3):
			var y := -7+barrel_index*6
			MechanismArt.face(weapon_part,Rect2(-42,y,25,4),"steel",barrel_index)
			Quads.rect(weapon_part,Rect2(-42,y+1,5,2),Color("252e29"))
			Quads.rect(weapon_part,Rect2(-30,y,4,2),Color("b39562"))
	if chassis_kind() == "siege":
		Quads.rect(weapon_part,Rect2(-49,-11,37,23),Art.INK)
		MechanismArt.face(weapon_part,Rect2(-47,-8,34,17),"dark",3)
		Quads.rect(weapon_part,Rect2(-47,-8,34,3),Color("b4ab8b"))
		Quads.rect(weapon_part,Rect2(-49,-9,8,20),Color("29312e"))
		Quads.rect(weapon_part,Rect2(-50,-5,5,11),Color("a89770"))
		for rib in range(4):
			Quads.rect(weapon_part,Rect2(-38+rib*6,-9,3,19),Color("313b34"))
			Quads.rect(weapon_part,Rect2(-38+rib*6,-8,2,3),Color("9e895f"))
		var charge := clampf(windup/float(profile.windup),0,1)
		Quads.rect(weapon_part,Rect2(-46,-2,3,5),Color("ef7c4f").lerp(Color("fff0bc"),charge))
	# Small rust chips, worn edges and a vented receiver match the chassis palette.
	for chip in range(34):
		var chip_pos := Vector2(-28+(chip*11)%33,-5+(chip*7)%11)
		var patina := Color("8a7551") if chip%3==0 else (Color("626750") if chip%2 else Color("30392e"))
		Quads.rect(weapon_part,Rect2(chip_pos,Vector2(1+chip%2,1)),patina)
	for vent in range(3):
		Quads.rect(weapon_part,Rect2(-14+vent*5,-3,3,6),Color("1c251e"))
		Quads.rect(weapon_part,Rect2(-14+vent*5,-3,3,1),Color("898f75"))
	for screw in [Vector2(-18,-5),Vector2(4,-4),Vector2(3,5)]:
		Quads.rect(weapon_part,Rect2(screw-Vector2.ONE,Vector2(3,3)),Color("242b22"))
		Quads.rect(weapon_part,Rect2(screw,Vector2.ONE),Color("d5c095"))
	if muzzle_flash > 0 and chassis_kind() == "siege":
		var mouth := weapon_muzzle()
		weapon_part.draw_colored_polygon(PackedVector2Array([mouth+Vector2(2,-5),mouth+Vector2(-19,-14),mouth+Vector2(-12,-3),mouth+Vector2(-44,0),mouth+Vector2(-14,5),mouth+Vector2(-21,14),mouth+Vector2(2,6)]),Color("ffac56"))
		weapon_part.draw_line(mouth,mouth+Vector2(-28,0),Color("fff2c1"),4)
	elif muzzle_flash > 0:
		var mouth := weapon_muzzle()
		weapon_part.draw_colored_polygon(PackedVector2Array([mouth+Vector2(1,-3),mouth+Vector2(-11,-8),mouth+Vector2(-7,-2),mouth+Vector2(-21,1),mouth+Vector2(-9,4),mouth+Vector2(-13,8),mouth+Vector2(1,4)]), Color("fb6a3f"))
		weapon_part.draw_line(mouth,mouth+Vector2(-15,0),Color("ffd29a"),3)
