class_name Worker
extends CharacterBody2D

const NetInput := preload("res://scripts/network_input.gd")

@export var player_id: int = 1
var game
var character_id := "mara"
var gore_mask := 0
var progression: PlayerProgression
var medical: WorkerMedical
var wetness: ActorWetness
var inventory: Dictionary = {}
var selected_kind: String = ""
var last_transfer_kind: String = ""
var pickup_animation := 0.0
var drop_animation := 0.0
var mounted_turret
var focus
var preferred_focus
var facing: float = 1.0
var max_hp := float(Balance.WORKER_HP)
var hp := float(Balance.WORKER_HP)
var invulnerability := 0.0
var hurt_flash := 0.0
var hurt_stun := 0.0
var down_time := 0.0
var since_hit := 99.0
var knockback := 0.0
var _requires_interact_release := false
var climbing := false
var mining := false
var _ladder := Rect2()
var _passage_jump_exit := false
var _animation_time := 0.0
var _interacting := false
var _interaction_held := false
var _locked_focus
var _mining_hold := false
var _awaiting_mine_continuation := false
var _instant_interaction_spent := false
var _drop_held := false
var _drop_time := 0.0
var _drop_committed := false
var _drop_kind := ""
var _landing_time := 0.0
var _jump_windup := 0.0
var _airborne := false
var _safe_collapse := preload("res://scripts/safe_collapse.gd").new()
const GRAVITY := 1100.0
const JUMP_SPEED := 390.0
const FLOOR_LEVELS := [245.0, 430.0, 600.0, 800.0]
static var MATERIAL_ORDER: Array[String]:
	get: return ItemCatalog.ordered()
const DROP_STACK_TIME := 0.4

func _ready() -> void:
	add_to_group("players")
	collision_layer = 8
	collision_mask = 1
	z_index = 15
	var spec := CharacterCatalog.data(character_id)
	character_id = spec.id
	max_hp = float(spec.hp)
	hp = max_hp
	progression = PlayerProgression.new()
	progression.name = "Progression"
	add_child(progression)
	medical = WorkerMedical.new()
	medical.name = "Medical"
	add_child(medical)
	var aid_target := MedicalAidTarget.new()
	aid_target.name = "MedicalAidTarget"
	aid_target.medical = medical
	add_child(aid_target)
	wetness=ActorWetness.new()
	wetness.name="Wetness"
	add_child(wetness)

func configure_character(id: String) -> bool:
	if not CharacterCatalog.contains(id):
		return false
	if is_node_ready() and is_instance_valid(game) and "started" in game and game.started:
		return false
	character_id = id
	var spec := CharacterCatalog.data(id)
	max_hp = float(spec.hp)
	hp = max_hp
	queue_redraw()
	return true

func damage_multiplier() -> float:
	return float(CharacterCatalog.data(character_id).damage)*(progression.damage_multiplier() if is_instance_valid(progression) else 1.0)

func is_downed() -> bool:
	if bool(get_meta("network_departed",false)): return true
	return medical.incapacitated() if is_instance_valid(medical) else down_time > 0.0

func can_act() -> bool:
	return not is_downed() and hurt_stun <= 0.0 and (not is_instance_valid(medical) or not medical.is_rising())

func can_be_targeted() -> bool:
	return not is_downed() and hp > 0.0

func take_damage(amount: float, direction: Vector2 = Vector2.LEFT, trauma: String = "") -> float:
	if not is_finite(amount) or amount <= 0.0 or invulnerability > 0.0 or is_downed():
		return 0.0
	var reduced := amount*(1.0-progression.armor_reduction() if is_instance_valid(progression) else 1.0)
	var applied := minf(hp, reduced)
	hp = maxf(0.0, hp - reduced)
	if is_instance_valid(medical): medical.on_damage(applied,trauma)
	since_hit = 0.0
	invulnerability = Balance.WORKER_IFRAMES
	hurt_flash = 0.22
	hurt_stun = 0.14
	knockback = (signf(direction.x) if absf(direction.x) > 0.01 else -facing) * 105.0
	if is_instance_valid(game) and not game.has_method("combat_contact") and int(get_meta("impact_contact_frame", -1)) != Engine.get_physics_frames():
		if game.has_method("impact"):
			game.impact(global_position-Vector2(0,25), "flesh", direction, clampf(amount/25.0,0.5,1.6))
		elif game.has_method("fx"):
			game.fx(global_position-Vector2(0,25), Color("cc6048"), 7)
	if hp <= 0.0:
		_begin_knockout()
	if is_instance_valid(game) and game.has_method("combat_contact"):
		game.combat_contact(self,applied,is_downed())
	queue_redraw()
	return applied

func _begin_knockout() -> void:
	if is_downed(): return
	if is_instance_valid(medical): medical.incapacitate()
	else: down_time = MedicalCatalog.CRITICAL_DELAY
	if is_instance_valid(progression):
		progression.break_combo()
	if is_instance_valid(mounted_turret):
		mounted_turret.exit()
	mounted_turret = null
	climbing = false
	_passage_jump_exit = false
	collision_mask = 1
	collision_layer = 0
	_jump_windup = 0.0
	_cancel_actions()
	var weapon := get_node_or_null("WorkerWeapon")
	if is_instance_valid(weapon) and weapon.has_method("cancel_actions"):
		weapon.cancel_actions()
	_safe_collapse.begin(self)
	if is_instance_valid(game) and game.has_method("notify"):
		game.notify(LocaleText.format("P%d bewusstlos · Verbündete können mit 1 Verband wiederbeleben. Fracht bleibt erhalten.", player_id))

func _cancel_actions() -> void:
	focus = null
	preferred_focus = null
	mining = false
	_interacting = false
	_interaction_held = false
	_locked_focus = null
	_mining_hold = false
	_awaiting_mine_continuation = false
	_instant_interaction_spent = false
	_drop_held = false
	_drop_time = 0.0
	_drop_kind = ""
	_drop_committed = false
	_requires_interact_release = true

func _update_health(delta: float) -> void:
	invulnerability = maxf(0.0, invulnerability-delta)
	hurt_flash = maxf(0.0, hurt_flash-delta)
	hurt_stun = maxf(0.0, hurt_stun-delta)
	since_hit += delta
	knockback = move_toward(knockback,0.0,delta*470.0)
	if is_instance_valid(medical): medical.tick(delta)
	if not is_downed() and hp < max_hp and since_hit >= Balance.WORKER_REGEN_DELAY and _near_core() and (not is_instance_valid(medical) or (medical.bleeding==0 and not medical.fractured)):
		hp = minf(max_hp, hp + Balance.WORKER_REGEN_RATE*delta)

func _near_core() -> bool:
	if not is_instance_valid(game) or not "core" in game or not is_instance_valid(game.core):
		return false
	if not game.core.is_visible_in_tree(): return false
	var core_pos: Vector2 = game.core.global_position
	return absf(global_position.y-core_pos.y) <= 45.0 and global_position.distance_to(core_pos) <= Balance.WORKER_REGEN_RADIUS

func _restore_from_aid(health_ratio: float) -> void:
	gore_mask=0
	var gore=game.get("combat_gore") if is_instance_valid(game) else null
	if is_instance_valid(gore): gore.reset_actor(self)
	_safe_collapse.reset()
	velocity = Vector2.ZERO
	knockback = 0.0
	hp = maxf(1.0,max_hp*clampf(health_ratio,0.01,1.0))
	down_time = 0.0
	hurt_stun = 0.0
	invulnerability = Balance.WORKER_RESPAWN_SHIELD
	collision_layer = 8
	collision_mask = 1
	_airborne = false
	_cancel_actions()

func action(suffix: String) -> String:
	return "p%d_%s" % [player_id, suffix]

func carried_count() -> int:
	var amount := 0
	for value in inventory.values():
		amount += int(value)
	return amount

func capacity() -> int:
	var shared: int = game.upgrades.carry_capacity() if is_instance_valid(game) and "upgrades" in game and is_instance_valid(game.upgrades) else Balance.CARRY_CAPACITY
	return shared + int(CharacterCatalog.data(character_id).capacity)-Balance.CARRY_CAPACITY + (progression.capacity_bonus() if is_instance_valid(progression) else 0)

func movement_multiplier() -> float:
	var shared: float = game.upgrades.movement_multiplier() if is_instance_valid(game) and "upgrades" in game and is_instance_valid(game.upgrades) else 1.0
	return shared*float(CharacterCatalog.data(character_id).speed)*(progression.speed_multiplier() if is_instance_valid(progression) else 1.0)*(medical.movement_multiplier() if is_instance_valid(medical) else 1.0)

func work_multiplier() -> float:
	var shared: float = game.upgrades.work_multiplier() if is_instance_valid(game) and "upgrades" in game and is_instance_valid(game.upgrades) else 1.0
	return shared*float(CharacterCatalog.data(character_id).work)*(progression.work_multiplier() if is_instance_valid(progression) else 1.0)*(medical.work_multiplier() if is_instance_valid(medical) else 1.0)

func floor_levels() -> Array:
	return game.floor_levels if is_instance_valid(game) and "floor_levels" in game else FLOOR_LEVELS

func selected_material() -> String:
	if int(inventory.get(selected_kind, 0)) > 0:
		return selected_kind
	var kinds := _carried_materials()
	selected_kind = kinds[0] if not kinds.is_empty() else ""
	return selected_kind

func material_kinds() -> Array[String]:
	return _carried_materials()

func _carried_materials() -> Array[String]:
	var kinds: Array[String] = []
	for kind: String in MATERIAL_ORDER:
		if int(inventory.get(kind, 0)) > 0:
			kinds.append(kind)
	# Custom materials remain selectable without relying on dictionary insertion order.
	var extras: Array[String] = []
	for kind: String in inventory:
		if int(inventory[kind]) > 0 and not kinds.has(kind):
			extras.append(kind)
	extras.sort()
	kinds.append_array(extras)
	return kinds

func cycle_material() -> void:
	if _drop_held:
		return
	var kinds := _carried_materials()
	if kinds.is_empty():
		selected_kind = ""
		return
	var current := kinds.find(selected_material())
	selected_kind = kinds[(current + 1) % kinds.size()]
	queue_redraw()

func drop_hold_progress() -> float:
	return clampf(_drop_time / DROP_STACK_TIME, 0.0, 1.0) if _drop_held and not _drop_committed else 0.0

func add_item(kind: String, amount: int = 1) -> int:
	if not ItemCatalog.contains(kind): return 0
	var accepted := mini(maxi(amount, 0), maxi(0, capacity() - carried_count()))
	if accepted > 0:
		inventory[kind] = int(inventory.get(kind, 0)) + accepted
		selected_material()
		last_transfer_kind = kind
		pickup_animation = 0.36
		queue_redraw()
	return accepted

func take_item(kind: String, amount: int = 1) -> bool:
	if amount < 0 or int(inventory.get(kind, 0)) < amount:
		return false
	if amount == 0:
		return true
	inventory[kind] = int(inventory.get(kind, 0)) - amount
	if inventory[kind] == 0:
		inventory.erase(kind)
	selected_material()
	queue_redraw()
	return true

func _physics_process(delta: float) -> void:
	_animation_time += delta
	_landing_time = maxf(0.0, _landing_time - delta)
	pickup_animation = maxf(0.0, pickup_animation - delta)
	drop_animation = maxf(0.0, drop_animation - delta)
	if not is_instance_valid(game) or not game.started:
		queue_redraw()
		return
	_update_health(delta)
	if is_downed():
		velocity.x = _safe_collapse.velocity_x(self,delta,knockback)
		velocity.y += GRAVITY*delta
		move_and_slide()
		queue_redraw()
		return
	if is_instance_valid(medical) and medical.is_rising():
		velocity.x = 0.0
		velocity.y += GRAVITY*delta
		move_and_slide()
		queue_redraw()
		return
	if hurt_stun > 0.0:
		velocity.x = knockback
		if not climbing and not is_instance_valid(mounted_turret):
			velocity.y += GRAVITY*delta
			move_and_slide()
		queue_redraw()
		return
	_update_material_controls(delta)
	if is_instance_valid(mounted_turret):
		focus = mounted_turret
		velocity = Vector2.ZERO
		mining = false
		_interacting = false
		_interaction_held = NetInput.is_pressed(self,"interact")
		_locked_focus = null
		_mining_hold = false
		_awaiting_mine_continuation = false
		queue_redraw()
		return
	mounted_turret = null
	var horizontal := NetInput.axis(self,"left","right")
	var vertical := NetInput.axis(self,"up","down")
	if absf(horizontal) > 0.1:
		facing = signf(horizontal)
	if not climbing and absf(vertical) > 0.25:
		var nearby := _nearby_ladder()
		if nearby.has_area():
			_ladder = nearby
			climbing = true
			_passage_jump_exit = false
			collision_mask = 0
	if climbing:
		_climb(delta, horizontal, vertical)
	else:
		_walk(delta, horizontal)
	var right_edge := float(game.world_right) if is_instance_valid(game) and "world_right" in game else 1400.0
	var left_edge: float=float(game.world_left) if is_instance_valid(game) and "world_left" in game else 70.0
	global_position.x = clampf(global_position.x, left_edge, right_edge)
	if global_position.y > float(floor_levels()[-1]) + 90.0:
		global_position = game.scenario_bunker.spawn_position(player_id) if is_instance_valid(game) and "scenario_bunker" in game and is_instance_valid(game.scenario_bunker) else Vector2(360, 800)
		velocity = Vector2.ZERO
	_update_interaction(delta)
	queue_redraw()

func _update_interaction(delta: float) -> void:
	var held := NetInput.is_pressed(self,"interact")
	if _requires_interact_release:
		if held:
			return
		_requires_interact_release = false
	if not held:
		_interaction_held = false
		_locked_focus = null
		_mining_hold = false
		_awaiting_mine_continuation = false
		_instant_interaction_spent = false
		_interacting = false
		mining = false
		if NetInput.just_pressed(self,"cycle_target"):
			cycle_target()
		focus = _chosen_focus()
		return
	if not _interaction_held:
		_locked_focus = _chosen_focus()
		_instant_interaction_spent = false
		_mining_hold = is_instance_valid(_locked_focus) and _locked_focus is MineBlock
		_awaiting_mine_continuation = false
		_watch_mining_target()
	_interaction_held = true
	# A completed mining cell may continue into reachable earth. Every other
	# interaction stays on its original object for the complete button press.
	if _mining_hold and _awaiting_mine_continuation:
		_locked_focus = _next_mining_target()
		if is_instance_valid(_locked_focus):
			_awaiting_mine_continuation = false
			_watch_mining_target()
	focus = _locked_focus if is_instance_valid(_locked_focus) and not _locked_focus.is_queued_for_deletion() else null
	_interacting = is_instance_valid(focus) and _target_in_reach(focus)
	mining = _interacting and (focus.is_in_group("mine_blocks") or focus.is_in_group("excavation_sites"))
	if not _interacting:
		return
	if focus.has_method("opens_action_menu") and focus.opens_action_menu():
		_interacting = false
		if not _instant_interaction_spent:
			_instant_interaction_spent = true
			focus.open_action_menu(self)
		return
	if absf(velocity.x) < 15 and not climbing:
		var point: Vector2 = focus.interaction_point() if focus.has_method("interaction_point") else focus.global_position
		if absf(point.x-global_position.x) > 8:
			facing = signf(point.x-global_position.x)
	if focus.is_in_group("pickups") or focus.is_in_group("solo_story_npcs") or focus.is_in_group("solo_story_finds"):
		if _instant_interaction_spent:
			return
		_instant_interaction_spent = true
	var real_time_work: bool = focus.is_in_group("medical_targets") or (focus.has_method("work_uses_real_time") and focus.work_uses_real_time())
	focus.interact(self, delta if real_time_work else delta * work_multiplier())
	if not is_instance_valid(focus) or focus.is_queued_for_deletion():
		focus = null
		_interacting = false
		mining = false

func _watch_mining_target() -> void:
	if _mining_hold and is_instance_valid(_locked_focus) and not _locked_focus.mined.is_connected(_on_held_mine_depleted):
		_locked_focus.mined.connect(_on_held_mine_depleted)

func _on_held_mine_depleted(block: MineBlock) -> void:
	if _interaction_held and _mining_hold and _locked_focus == block:
		_awaiting_mine_continuation = true

func _next_mining_target():
	var best_target
	var best_score := INF
	var center := global_position-Vector2(0,20)
	var walking := NetInput.axis(self,"left","right")
	var direction := signf(walking) if absf(walking)>0.1 else facing
	var candidates: Array = game.focus_candidates(self) if game.has_method("focus_candidates") else get_tree().get_nodes_in_group("mine_blocks")
	for candidate in candidates:
		if not candidate is MineBlock or candidate.depleted or not _target_in_reach(candidate):
			continue
		var surface: Vector2 = candidate.surface_near(center)
		var height := absf(candidate.global_position.y-center.y)
		var score := surface.distance_to(center)+height*0.65
		if (candidate.global_position.x-global_position.x)*direction < -4:
			score += 80
		if absf(walking)>0.1 and height<32:
			score -= 16
		if score < best_score:
			best_score = score
			best_target = candidate
	return best_target

func cycle_target() -> void:
	if _interaction_held:
		return
	var candidates: Array = game.focus_candidates(self)
	if candidates.size() < 2:
		return
	var current := candidates.find(_chosen_focus())
	preferred_focus = candidates[(current + 1) % candidates.size()]
	focus = preferred_focus

func _chosen_focus():
	if is_instance_valid(preferred_focus) and _target_in_reach(preferred_focus):
		return preferred_focus
	preferred_focus = null
	return game.get_focus(self)

func _target_in_reach(target) -> bool:
	if game.has_method("valid_focus"):
		return game.valid_focus(self, target)
	var point: Vector2 = target.interaction_point() if target.has_method("interaction_point") else target.global_position - Vector2(0, 20)
	var center := global_position - Vector2(0, 20)
	return absf(center.y - point.y) <= 68.0 and center.distance_to(point) <= 83.0

func _update_material_controls(delta: float) -> void:
	if NetInput.just_pressed(self,"cycle_material"):
		cycle_material()
	# Reliable press/release taps can arrive together after a network stall.
	# Replay their explicit edges while the latest held state keeps ordinary
	# long presses current. A queued release ends its tap even if a later
	# packet already starts another press.
	var pressed := NetInput.just_pressed(self,"drop")
	var released := NetInput.just_released(self,"drop")
	var held := (NetInput.is_pressed(self,"drop") or pressed) and (not released or pressed)
	if held:
		if not _drop_held:
			_drop_held = true
			_drop_time = 0.0
			_drop_committed = false
			_drop_kind = selected_material()
		_drop_time += delta
		if not _drop_committed and _drop_time >= DROP_STACK_TIME:
			_drop_committed = true
			_drop_material_kind(_drop_kind, int(inventory.get(_drop_kind, 0)))
	elif _drop_held:
		if not _drop_committed:
			_drop_material_kind(_drop_kind, 1)
		_drop_held = false
		_drop_time = 0.0
		_drop_kind = ""
		_drop_committed = false

func _walk(delta: float, horizontal: float) -> void:
	var carrying_weight := 1.0 - 0.14 * float(carried_count()) / capacity()
	velocity.x = horizontal * Balance.PLAYER_SPEED * carrying_weight * movement_multiplier() + knockback
	velocity.y += GRAVITY * delta
	if NetInput.just_pressed(self,"jump") and is_on_floor():
		_jump_windup = 0.06
	if _jump_windup > 0.0:
		_jump_windup -= delta
		if _jump_windup <= 0.0:
			velocity.y = -JUMP_SPEED*(MedicalCatalog.FRACTURE_JUMP if is_instance_valid(medical) and medical.fractured else 1.0)
	var grounded_before := is_on_floor()
	move_and_slide()
	if not grounded_before and is_on_floor():
		_landing_time = 0.15
	_airborne = not is_on_floor()

func _nearby_ladder() -> Rect2:
	for rect: Rect2 in game.ladders:
		var corridor := Rect2(rect.position + Vector2(-12, 20), rect.size + Vector2(24, 0))
		if corridor.has_point(global_position):
			return rect
	return Rect2()

func _climb(delta: float, horizontal: float, vertical: float) -> void:
	velocity = Vector2.ZERO
	_airborne = false
	_jump_windup = 0.0
	var top := _nearest_floor(_ladder.position.y + 40.0, 12.0)
	var bottom := _nearest_floor(_ladder.end.y, 12.0)
	global_position.x = move_toward(global_position.x, _ladder.get_center().x, 300.0 * delta)
	var next_y := clampf(global_position.y + vertical * Balance.CLIMB_SPEED * movement_multiplier() * delta, top, bottom)
	var jump_exit := NetInput.just_pressed(self,"jump") or _passage_jump_exit
	var side_exit := absf(horizontal) > 0.35 or jump_exit
	var landing := INF
	if side_exit:
		# Exit through the opening, then wait for its cover to support the feet.
		# Selecting the landing before moving also keeps held diagonal input
		# from immediately reopening a hatch which is still closing.
		for level: float in floor_levels():
			if global_position.y >= level - 8.0 and global_position.y < level + 42.0:
				next_y = level
				landing = level
				break
	elif (vertical < -0.25 and next_y <= top) or (vertical > 0.25 and next_y >= bottom):
		landing = next_y
	elif absf(vertical) < 0.1:
		var nearby_floor := _nearest_floor(global_position.y, 8.0)
		if nearby_floor != global_position.y or floor_levels().has(global_position.y):
			next_y = nearby_floor
			landing = nearby_floor
	if not is_equal_approx(next_y, global_position.y) and not LadderPassage.allow_motion(self, next_y):
		_passage_jump_exit = jump_exit
		return
	global_position.y = next_y
	if is_finite(landing) and not LadderPassage.landing_ready(self, landing):
		_passage_jump_exit = jump_exit
		return
	_passage_jump_exit = false
	if side_exit:
		climbing = false
		collision_mask = 1
		velocity.x = horizontal * Balance.PLAYER_SPEED
		if jump_exit:
			velocity.y = -JUMP_SPEED*(MedicalCatalog.FRACTURE_JUMP if is_instance_valid(medical) and medical.fractured else 1.0)
		move_and_slide()
	elif is_finite(landing):
		climbing = false
		collision_mask = 1

func _nearest_floor(value: float, tolerance: float) -> float:
	for level: float in floor_levels():
		if absf(value - level) <= tolerance:
			return level
	return value

func _drop_one() -> void:
	_drop_material_kind(selected_material(), 1)

func _drop_material_kind(kind: String, amount: int) -> bool:
	if not can_act() or kind.is_empty() or amount <= 0 or int(inventory.get(kind, 0)) < amount or not is_instance_valid(game):
		return false
	var dropped := false
	if game.has_method("drop_material"):
		# The game owns placement validation and consumes material only after success.
		dropped = game.drop_material(self, kind, amount)
	elif game.has_method("spawn_pickup"):
		# Compatibility for isolated test worlds without the arena placement helper.
		if take_item(kind, amount):
			game.spawn_pickup(kind, amount, global_position + Vector2(facing * 30, -10))
			dropped = true
	if dropped:
		last_transfer_kind = kind
		drop_animation = 0.36
		queue_redraw()
	return dropped
