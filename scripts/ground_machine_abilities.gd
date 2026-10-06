class_name GroundMachineAbilities
extends Node
## Bounded combat abilities, separate from shared navigation and body animation.
const MAX_GROUND_ORDNANCE := 18
const MORTAR_GRAVITY := 380.0
var aim_point := Vector2.ZERO
var warning_point := Vector2.ZERO
var aim_locked := false
var _warning_origin := Vector2.ZERO
var _warning_clock := -1.0
const SHIELD_CAPACITY := 60.0
const SHIELD_CYCLE := 4.1
const SHIELD_CLOSED_TIME := 1.6
const RUSH_WARNING := 0.75
const RUSH_DURATION := 2.4
const RUSH_COOLDOWN := 5.5
const REPAIR_RESERVE := 64.0
const REPAIR_PULSE := 16.0
const REPAIR_INTERVAL := 2.6
const REPAIR_RANGE := 145.0
const MEDIC_RESERVE := 60.0
const MEDIC_PULSE := 20.0
const MEDIC_RANGE := 96.0
const MEDIC_WINDUP := 1.0
const MEDIC_INTERVAL := 4.0
const BASTION_REDUCTION := 0.35
const BASTION_VENT_TIME := 2.4
const DEMOLITION_RADIUS := 95.0

var machine
var mode := ""
var clock := 0.0
var shield_hp := SHIELD_CAPACITY
var shield_flash := 0.0
var shield_open := 0.0
var rush_warning := 0.0
var rush_time := 0.0
var rush_cooldown := 0.0
var rush_primed := false
var repair_remaining := REPAIR_RESERVE
var repair_clock := 0.8
var repair_flash := 0.0
var repair_endpoint := Vector2.ZERO
var repaired_total := 0.0
var heat := 0
var vent_time := 0.0
var shock_flash := 0.0
var _treatment_target: Node2D
var _treatment_hp := 0.0
var _worker_burst_pending := false
var _burst_recipient: Node2D
var _burst_endpoint := Vector2.ZERO
var _burst_damage := 0.0

func _ready() -> void:
	machine = get_parent()
	mode = str(machine.profile.get("ability",""))
	if mode=="infantry_medic": repair_remaining=MEDIC_RESERVE

func update(delta: float) -> void:
	var previous_cycle := int(clock/SHIELD_CYCLE)
	clock += delta
	if aim_locked and ballistic_attack() and authoritative(): _refresh_ballistic_warning()
	shield_flash = maxf(0.0,shield_flash-delta)
	var was_treating := mode=="infantry_medic" and is_instance_valid(_treatment_target)
	repair_flash = maxf(0.0,repair_flash-delta)
	if _worker_burst_pending: _update_worker_burst(delta)
	if mode=="infantry_medic" and authoritative():
		repair_clock=maxf(0,repair_clock-delta)
		if was_treating:
			if machine.stagger>0 or machine.hit_flash>0 or machine.hp<_treatment_hp or not _can_treat(_treatment_target):
				_treatment_target=null
				repair_flash=0
			elif repair_flash<=0:
				_complete_treatment()
		if repair_clock<=0 and repair_flash<=0 and not try_treat(): repair_clock=.5
	shock_flash = maxf(0.0,shock_flash-delta)
	if mode=="shield" and int(clock/SHIELD_CYCLE)!=previous_cycle:
		shield_hp = SHIELD_CAPACITY
	if mode=="shield":
		shield_open = move_toward(shield_open,0.0 if shield_closed() else 1.0,delta*5.0)
	if mode=="rush":
		rush_cooldown = maxf(0.0,rush_cooldown-delta)
		rush_time = maxf(0.0,rush_time-delta)
		if rush_time<=0 and rush_warning<=0:
			rush_primed = false
		if rush_warning>0:
			rush_warning = maxf(0.0,rush_warning-delta)
			if rush_warning<=0:
				rush_time = RUSH_DURATION
				rush_primed = true
		elif rush_time<=0 and rush_cooldown<=0 and is_instance_valid(machine.target):
			var distance: float = (machine.target.global_position.x-machine.global_position.x)*machine.attack_direction
			if distance>machine.attack_reach+35 and distance<280:
				rush_warning = RUSH_WARNING
				rush_cooldown = RUSH_COOLDOWN
	elif mode=="repair":
		repair_clock -= delta
		if repair_clock<=0:
			repair_clock = REPAIR_INTERVAL
			try_repair()
	elif mode=="bastion" and vent_time>0:
		vent_time = maxf(0.0,vent_time-delta)
		if vent_time<=0:
			heat = 0

func shield_closed() -> bool:
	return mode=="shield" and fposmod(clock,SHIELD_CYCLE)<SHIELD_CLOSED_TIME and shield_hp>0.0

func filter_damage(amount: float) -> float:
	if mode=="shield" and shield_closed():
		var absorbed := minf(shield_hp,amount)
		shield_hp -= absorbed
		shield_flash = 0.18
		return amount-absorbed
	if mode=="bastion" and vent_time<=0:
		return amount*(1.0-BASTION_REDUCTION)
	return amount

func blocks_action() -> bool:
	return rush_warning>0.0 or vent_time>0.0 or _worker_burst_pending or (mode=="infantry_medic" and repair_flash>0)

func movement_multiplier() -> float:
	return 2.8 if mode=="rush" and rush_time>0 else 1.0

func strike_multiplier() -> float:
	return 1.65 if mode=="rush" and rush_primed else 1.0

func after_strike(victim: Node2D, at: Vector2, normal: Vector2) -> void:
	if mode=="rush":
		rush_primed = false
		rush_time = 0.0
	elif mode=="bastion":
		heat += 1
		if heat>=6:
			vent_time = BASTION_VENT_TIME
	elif mode=="demolition":
		shock_flash = 0.45
		if is_instance_valid(machine.game) and machine.game.has_method("impact"):
			machine.game.impact(at,"explosion",normal,1.0)
		# A shockwave can hurt nearby exposed workers, but the struck concrete
		# remains in the ray query and therefore protects anyone behind it.
		var origin := at+normal*3.0
		for worker in get_tree().get_nodes_in_group("players"):
			if not is_instance_valid(worker) or worker.is_queued_for_deletion() or worker.get("game")!=machine.game or worker==victim or not worker.has_method("can_be_targeted") or not worker.can_be_targeted():
				continue
			var chest: Vector2 = worker.global_position-Vector2(0,23)
			if chest.distance_to(at)>DEMOLITION_RADIUS:
				continue
			var query := PhysicsRayQueryParameters2D.create(origin,chest,1|2|8)
			query.hit_from_inside = true
			var hit: Dictionary = machine.get_world_2d().direct_space_state.intersect_ray(query)
			if not hit.is_empty() and hit.collider==worker:
				worker.take_damage(14.0*EnemyCatalog.damage_scale(machine.wave)*Balance.enemy_damage_multiplier(machine.crew_size_at_spawn),(chest-origin).normalized())

func try_repair() -> float:
	if mode!="repair" or repair_remaining<=0 or machine.dead or not authoritative():
		return 0.0
	var recipient: Node2D
	var largest_missing := 0.0
	var origin: Vector2 = machine.global_position-Vector2(0,machine.body_height)
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(candidate) or candidate.is_queued_for_deletion() or candidate.get("game")!=machine.game or candidate==machine or candidate.dead or candidate.hp<=0 or candidate.is_in_group("air_enemies") or candidate.is_in_group("human_enemies"):
			continue
		var missing: float = maxf(0,candidate.max_hp-candidate.hp)
		var endpoint: Vector2 = candidate.global_position-Vector2(0,candidate.body_height)
		if missing<=largest_missing or endpoint.distance_to(origin)>REPAIR_RANGE:
			continue
		var query := PhysicsRayQueryParameters2D.create(origin,endpoint,1|2)
		query.hit_from_inside = true
		if not machine.get_world_2d().direct_space_state.intersect_ray(query).is_empty():
			continue
		recipient = candidate
		largest_missing = missing
	if not is_instance_valid(recipient):
		return 0.0
	var applied := minf(minf(REPAIR_PULSE,repair_remaining),largest_missing)
	recipient.hp = minf(recipient.max_hp,recipient.hp+applied)
	recipient.queue_redraw()
	repair_remaining -= applied
	repaired_total += applied
	repair_flash = 0.34
	repair_endpoint = recipient.global_position-Vector2(0,recipient.body_height)
	return applied

func projectile_attack() -> bool:
	return mode in ["grenade","infantry_rifle","infantry_medic","vehicle_gun","vehicle_mortar"]

func ballistic_attack() -> bool:
	return mode in ["grenade","vehicle_mortar"]

func authoritative() -> bool:
	var session=machine.game.get("network") if is_instance_valid(machine.game) else null
	return not is_instance_valid(session) or not session.active or session.is_host

func prepare_attack(destination: Vector2) -> void:
	if not projectile_attack() or not authoritative() or machine.dead: return
	aim_point=destination
	aim_locked=true
	warning_point=destination
	if mode=="grenade":
		var story=machine.game.get("story") if is_instance_valid(machine.game) else null
		if is_instance_valid(story): story.once("warning_grenadier",45.0)
	if ballistic_attack(): _refresh_ballistic_warning(true)

func _refresh_ballistic_warning(force: bool=false) -> void:
	var origin: Vector2=machine.weapon_part.to_global(machine.weapon_muzzle())
	# Elevating a mortar moves its mouth. Keep the advertised first impact tied
	# to that physical launch point. Stationary guns check moving cover at8Hz.
	if not force and origin.distance_squared_to(_warning_origin)<.25 and clock-_warning_clock<.12: return
	_warning_origin=origin
	_warning_clock=clock
	warning_point=aim_point
	var launch:=launch_velocity(origin,aim_point)
	var previous:=origin
	var flight:=flight_time(origin,aim_point)
	for step in range(1,19):
		var time:=flight*float(step)/18.0
		var point:=origin+launch*time+Vector2(0,MORTAR_GRAVITY*time*time*.5)
		var query:=PhysicsRayQueryParameters2D.create(previous,point,1|2|8)
		query.hit_from_inside=true
		var hit: Dictionary=machine.get_world_2d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			warning_point=hit.position
			break
		previous=point

func flight_time(origin: Vector2,destination: Vector2) -> float:
	return clampf(absf(destination.x-origin.x)/240.0,0.72,1.65 if mode=="vehicle_mortar" else 1.35)

func launch_velocity(origin: Vector2,destination: Vector2) -> Vector2:
	var time:=flight_time(origin,destination)
	return (destination-origin)/time-Vector2(0,MORTAR_GRAVITY*time*.5)

func fire_projectiles(destination: Vector2,damage: float) -> bool:
	if not projectile_attack() or not authoritative() or machine.dead or not is_instance_valid(machine.game): return false
	if mode=="infantry_medic" and repair_flash>0: return false
	var count:=1
	var active_ground:=0
	var active_total:=0
	for shot in get_tree().get_nodes_in_group("air_projectiles"):
		if not shot.is_queued_for_deletion() and shot.game==machine.game:
			active_total+=1
			if shot.is_in_group("ground_ordnance"): active_ground+=1
	if active_ground+count>MAX_GROUND_ORDNANCE or active_total+count>HostileAirProjectile.MAX_ACTIVE:
		aim_locked=false
		return false
	var origin: Vector2=machine.weapon_part.to_global(machine.weapon_muzzle())
	var muzzle_ray:=PhysicsRayQueryParameters2D.create(machine.weapon_part.global_position,origin,1|2|8)
	muzzle_ray.hit_from_inside=true
	var muzzle_hit: Dictionary=machine.get_world_2d().direct_space_state.intersect_ray(muzzle_ray)
	if not muzzle_hit.is_empty() and not muzzle_hit.collider.is_in_group("players"):
		aim_locked=false
		return false
	var endpoint:=aim_point if aim_locked else destination
	var direction:=(endpoint-origin).normalized()
	for _index in count:
		var shot:=HostileAirProjectile.new()
		shot.game=machine.game
		shot.name="GroundOrdnance"
		shot.position=machine.game.to_local(origin)
		shot.damage=damage/float(count)
		shot.flavor="grenade" if ballistic_attack() else "tracer"
		shot.gravity=MORTAR_GRAVITY if ballistic_attack() else 0.0
		shot.velocity=launch_velocity(origin,endpoint) if ballistic_attack() else direction*float(machine.profile.get("projectile_speed",620.0))
		shot.lifetime=3.0 if ballistic_attack() else float(machine.profile.get("projectile_lifetime",0.6))
		shot.add_to_group("ground_ordnance")
		machine.game.add_child(shot)
		if not muzzle_hit.is_empty():
			shot.global_position=muzzle_hit.position
			shot._impact(muzzle_hit.collider,muzzle_hit.position,muzzle_hit.normal)
	machine.attack_count+=1
	machine.tracer_end=machine.to_local(endpoint)
	machine.weapon_recoil=7.0 if machine.kind=="battle_tank" else (5.0 if ballistic_attack() else 2.0)
	machine.muzzle_flash=.13
	aim_locked=false
	if mode in ["infantry_rifle","vehicle_gun"] and int(machine.profile.get("worker_burst",1))>1 and machine.worker_windup>0 and not _worker_burst_pending:
		_worker_burst_pending=true
		_burst_recipient=machine.worker_target
		_burst_endpoint=endpoint
		_burst_damage=damage
		machine.burst_remaining=int(machine.profile.worker_burst)-1
		machine.burst_clock=float(machine.profile.burst_gap)
	var cue: String="cannon" if machine.kind=="battle_tank" else ("mortar_shot" if ballistic_attack() else "enemy_shot")
	preload("res://scripts/spatial_sound.gd").emit(machine.game,cue,origin)
	return true

func draw_telegraph() -> void:
	if mode=="infantry_medic" and repair_flash>0 and not machine.dead:
		var endpoint: Vector2=machine.to_local(repair_endpoint)
		var color := Color("b8c5a0")
		color.a=clampf(repair_flash,0,.85)
		# A small treatment mark at the ally is distinct from a repair beam.
		machine.draw_line(endpoint+Vector2(-3,0),endpoint+Vector2(3,0),color,1)
		machine.draw_line(endpoint+Vector2(0,-3),endpoint+Vector2(0,3),color,1)
	if not aim_locked or not projectile_attack() or machine.dead: return
	var charge:=maxf(machine.windup/float(machine.profile.windup),machine.worker_windup/machine.worker_windup_duration())
	if charge<=0: return
	if ballistic_attack():
		var point: Vector2=machine.to_local(warning_point).round()
		var color:=Color("deaa63")
		color.a=.5+clampf(charge,0,1)*.4
		# Small bracket, anchored to the first predicted physical impact surface.
		for side in [-1,1]:
			machine.draw_line(point+Vector2(side*14,-5),point+Vector2(side*14,5),color,2)
			machine.draw_line(point+Vector2(side*14,5),point+Vector2(side*8,5),color,1)
		machine.draw_line(point+Vector2(-10,9),point+Vector2(-10+20*clampf(charge,0,1),9),color,2)

	elif machine.kind=="marksman":
		var origin: Vector2=machine.weapon_part.to_global(machine.weapon_muzzle())
		var query := PhysicsRayQueryParameters2D.create(origin,aim_point,1|2|8)
		query.hit_from_inside=true
		var hit: Dictionary=machine.get_world_2d().direct_space_state.intersect_ray(query)
		var endpoint: Vector2=machine.to_local(hit.position if not hit.is_empty() else aim_point)
		var color := Color("bfb295")
		color.a=.25+.50*clampf(charge,0,1)
		for side in [-1,1]:
			machine.draw_line(endpoint+Vector2(side*7,-3),endpoint+Vector2(side*7,3),color,1)

func _can_treat(recipient: Node2D) -> bool:
	if not is_instance_valid(recipient) or recipient==machine or recipient.is_queued_for_deletion(): return false
	if not recipient.is_in_group("human_enemies") or recipient.game!=machine.game or not EnemyCatalog.is_human(recipient.kind): return false
	if recipient.dead or recipient.hp<=0 or recipient.hp>=recipient.max_hp or machine.dead or machine.hp<=0: return false
	var origin: Vector2=machine.global_position-Vector2(0,machine.body_height)
	var endpoint: Vector2=recipient.global_position-Vector2(0,recipient.body_height)
	if origin.distance_to(endpoint)>MEDIC_RANGE: return false
	var query := PhysicsRayQueryParameters2D.create(origin,endpoint,1|2)
	query.hit_from_inside=true
	return machine.get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func try_treat() -> bool:
	if mode!="infantry_medic" or not authoritative() or machine.dead or repair_remaining<=0 or repair_clock>0 or repair_flash>0: return false
	if machine.stagger>0 or machine.hit_flash>0: return false
	var recipient: Node2D
	var largest_missing := 0.0
	for candidate in get_tree().get_nodes_in_group("human_enemies"):
		if not _can_treat(candidate): continue
		var missing: float=candidate.max_hp-candidate.hp
		if missing>largest_missing:
			largest_missing=missing
			recipient=candidate
	if not is_instance_valid(recipient): return false
	_treatment_target=recipient
	_treatment_hp=machine.hp
	repair_endpoint=recipient.global_position-Vector2(0,recipient.body_height)
	repair_flash=MEDIC_WINDUP
	repair_clock=MEDIC_INTERVAL
	machine.windup=0
	machine.worker_windup=0
	machine.burst_remaining=0
	aim_locked=false
	return true

func _complete_treatment() -> float:
	var recipient := _treatment_target
	_treatment_target=null
	if not authoritative() or not _can_treat(recipient) or repair_remaining<=0: return 0.0
	var applied: float=minf(MEDIC_PULSE,minf(repair_remaining,recipient.max_hp-recipient.hp))
	recipient.hp=minf(recipient.max_hp,recipient.hp+applied)
	recipient.queue_redraw()
	repair_remaining-=applied
	repaired_total+=applied
	repair_endpoint=recipient.global_position-Vector2(0,recipient.body_height)
	repair_flash=.28
	return applied

func _update_worker_burst(delta: float) -> void:
	if not authoritative() or machine.dead or machine.burst_remaining<=0 or not is_instance_valid(_burst_recipient) or not machine._visible_worker(_burst_recipient):
		_worker_burst_pending=false
		machine.burst_remaining=0
		return
	machine.burst_clock-=delta
	if machine.burst_clock>0: return
	if fire_projectiles(_burst_endpoint,_burst_damage):
		machine.worker_attack_count+=1
		machine.burst_remaining-=1
	else:
		machine.burst_remaining=0
	machine.burst_clock+=float(machine.profile.burst_gap)
	if machine.burst_remaining<=0:
		_worker_burst_pending=false
		_burst_recipient=null
