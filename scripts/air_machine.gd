class_name AirMachine
extends CharacterBody2D
## Aircraft use bounded visible sky lanes. Body, propulsion and weapon animate
## independently; damage is exclusively delivered by physical swept ordnance.

@export var kind: String = "scout_drone"
@export var wave := 7
@export var elite := false
var game: Node
var profile: Dictionary = {}
var wetness: ActorWetness
var motion: Node2D
const MOTION = preload("res://scripts/enemy_motion.gd")
const AircraftArt := preload("res://scripts/aircraft_art.gd")
const AircraftPresentation := preload("res://scripts/aircraft_presentation.gd")
const AircraftAudioCatalog := preload("res://scripts/aircraft_audio_catalog.gd")
const RhythmPresentation := preload("res://scripts/rhythm_presentation.gd")
var flight_presentation: Node
var hp := 64.0
var max_hp := 64.0
var dead := false
var body_height := 0.0 # Aircraft positions are the center of their hittable hull.
var show_status_labels := true
var attack_direction := -1.0
var scenario_lanes := Vector2.ZERO
var scenario_floor := 430.0
var flight_velocity := Vector2.ZERO
var age := 0.0
var crew_size_at_spawn := 1
var entered := false
var entry_time := 0.0
var attack_clock := AirEnemyCatalog.ENTRY_GRACE
var windup := 0.0
var burst_remaining := 0
var burst_clock := 0.0
var attack_count := 0
var target: Node2D
var locked_aim := Vector2.ZERO
var hit_flash := 0.0
var shield_flash := 0.0
var weapon_recoil := 0.0
var muzzle_flash := 0.0
var body_part: Node2D
var propulsion_part: Node2D
var weapon_part: Node2D
var chassis_atlas: Texture2D
var formation_phase := 0.0
var dive_origin := Vector2.ZERO
var _flight_facing := -1.0
const PROJECTILE = preload("res://scripts/hostile_air_projectile.gd")
const BODY_REGIONS := AircraftArtCatalog.REGIONS

func _ready() -> void:
	if not AirEnemyCatalog.is_air(kind):
		kind = "scout_drone"
	profile = AirEnemyCatalog.profile(kind)
	crew_size_at_spawn = Balance.active_players(game)
	max_hp = Balance.enemy_hp_multiplier(crew_size_at_spawn)*float(profile.hp)*EnemyCatalog.hp_scale(wave)*(1.25 if elite else 1.0)
	hp = max_hp
	add_to_group("enemies")
	add_to_group("air_enemies")
	collision_layer = 4
	collision_mask = 0
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = profile.hitbox
	shape.shape = rectangle
	shape.name = "AircraftHull"
	add_child(shape)
	chassis_atlas = load(AircraftArtCatalog.TEXTURE_PATH) if ResourceLoader.exists(AircraftArtCatalog.TEXTURE_PATH) else null
	propulsion_part = _part("ArticulatedPropulsion",_draw_propulsion)
	body_part = _part("ArmoredHull",_draw_body)
	weapon_part = _part("AimingWeapon",_draw_weapon)
	if position.y < 40 or position.y > 180 or scenario_lanes != Vector2.ZERO:
		position.y = float(profile.lane)+(scenario_floor-430.0)
	formation_phase = float(get_tree().get_nodes_in_group("air_enemies").size()-1)*1.83
	_pose_parts()
	wetness=ActorWetness.new()
	wetness.name="Wetness"
	add_child(wetness)
	motion = MOTION.new()
	motion.name = "MechanicalPerformance"
	add_child(motion)
	flight_presentation = AircraftPresentation.new()
	flight_presentation.name = "FlightPresentation"
	add_child(flight_presentation)

func _part(title: String, draw_method: Callable) -> Node2D:
	var part := Node2D.new()
	part.name = title
	part.draw.connect(draw_method)
	add_child(part)
	return part

func flight_bounds() -> Vector2:
	if scenario_lanes != Vector2.ZERO: return scenario_lanes
	var right: float = float(game.get("world_right")) if is_instance_valid(game) and game.get("world_right") != null else 1400.0
	# Late aircraft already use the outside lane before a new pane is glazed.
	var dome = game.get("dome") if is_instance_valid(game) else null
	var outside_dome: bool = wave>=16 or (is_instance_valid(dome) and bool(dome.get("built")))
	var left := 1390.0 if outside_dome else 900.0
	return Vector2(left,maxf(left+95.0,right-90.0))

func _physics_process(delta: float) -> void:
	if dead or not authoritative() or not is_finite(delta) or delta <= 0.0:
		return
	age += delta
	hit_flash = maxf(0,hit_flash-delta)
	shield_flash = maxf(0,shield_flash-delta)
	muzzle_flash = maxf(0,muzzle_flash-delta)
	weapon_recoil = move_toward(weapon_recoil,0,delta*17)
	_move_flight(delta)
	if entered:
		entry_time += delta
		attack_clock = maxf(0,attack_clock-delta)
		_update_attack(delta)
	_pose_parts()
	for part in [body_part,propulsion_part,weapon_part]:
		part.queue_redraw()
	queue_redraw()

func _move_flight(delta: float) -> void:
	var bounds := flight_bounds()
	var lane := float(profile.lane)+(scenario_floor-430.0)
	var drift := age+formation_phase
	var desired := Vector2(lerpf(bounds.x,bounds.y,0.60)+sin(drift*0.36)*55.0,lane+sin(drift*1.1)*7.0)
	match kind:
		"scout_drone":
			desired.x = lerpf(bounds.x,bounds.y,0.33)+sin(drift*0.85)*90.0
			desired.y += sin(drift*2.0)*20.0
		"gunship":
			desired.x = lerpf(bounds.x,bounds.y,0.50)+sin(drift*0.55)*45.0
		"bomber":
			desired.x = lerpf(bounds.x,bounds.y,0.5)+sin(drift*0.30)*(bounds.y-bounds.x)*0.46
		"interceptor", "dive_bomber":
			var diving := windup>0 or burst_remaining>0
			desired.x = clampf(dive_origin.x+attack_direction*105.0,bounds.x,bounds.y) if diving else (bounds.x+35.0 if attack_direction>0 else bounds.y-35.0)
			desired.y = (174.0 if diving else 78.0+sin(drift)*6.0)+(scenario_floor-430.0)
		"shield_airship":
			desired.x = lerpf(bounds.x,bounds.y,0.72)+sin(drift*0.23)*28.0
		"sky_fortress":
			desired.x = lerpf(bounds.x,bounds.y,0.53)+sin(drift*0.22)*28.0
		"rocket_drone":
			desired.x = lerpf(bounds.x,bounds.y,0.36)+sin(drift*.72)*80
			desired.y += sin(drift*1.3)*10
		"patrol_plane":
			desired.x = lerpf(bounds.x,bounds.y,.5)+sin(drift*.44)*(bounds.y-bounds.x)*.46
		"tiltrotor":
			desired.x = dive_origin.x if windup>0 or burst_remaining>0 else lerpf(bounds.x,bounds.y,.5)+sin(drift*.36)*(bounds.y-bounds.x)*.37
			desired.y = lane+sin(drift*.7)*4
		"pulse_fighter":
			desired.x = lerpf(bounds.x,bounds.y,.5)+sin(drift*.61)*(bounds.y-bounds.x)*.40
			desired.y += sin(drift*.8)*13
		"heavy_zeppelin":
			desired.x = lerpf(bounds.x,bounds.y,.67)+sin(drift*.16)*24
	desired.x = clampf(desired.x,bounds.x,bounds.y)
	desired.y = clampf(desired.y,scenario_floor-368.0,scenario_floor-252.0)
	var previous := global_position
	var speed := float(profile.speed)*(1.75 if not entered else 1.0)
	var offset := desired-global_position
	var desired_velocity := offset.normalized()*minf(speed,offset.length()*3.0)
	velocity = velocity.move_toward(desired_velocity,speed*3.0*delta)
	global_position += velocity*delta
	global_position.y = clampf(global_position.y,scenario_floor-368.0,scenario_floor-252.0)
	if entered: global_position.x = clampf(global_position.x,bounds.x,bounds.y)
	if global_position.x>=bounds.x-12.0 and global_position.x<=bounds.y+12.0:
		entered = true
	flight_velocity = (global_position-previous)/maxf(delta,0.0001)
	velocity = flight_velocity

func authoritative() -> bool:
	if not is_instance_valid(game): return true
	var session = game.get("network")
	return not is_instance_valid(session) or not bool(session.get("active")) or bool(session.get("is_host"))

func visual_age() -> float:
	return float(flight_presentation.clock) if is_instance_valid(flight_presentation) else age

func muzzle_global() -> Vector2:
	return weapon_part.to_global(Vector2(0,8) if str(profile.get("flavor",""))=="bomb" else Vector2(-24+weapon_recoil,0))

func attack_point_for(candidate: Node2D) -> Vector2:
	if candidate.has_method("attack_point"):
		return candidate.attack_point()
	if candidate.is_in_group("players"):
		return candidate.global_position-Vector2(0,23)
	return candidate.global_position-Vector2(0,40)

func visible_worker(candidate) -> bool:
	if not is_instance_valid(candidate) or not candidate is Node2D or candidate.is_queued_for_deletion() or candidate.get("game") != game or not candidate.has_method("can_be_targeted") or not candidate.can_be_targeted():
		return false
	var point := attack_point_for(candidate)
	if point.distance_to(global_position)>1300 or (point.x-global_position.x)*attack_direction < -55:
		return false
	var query := PhysicsRayQueryParameters2D.create(muzzle_global(),point,1|2|8)
	query.hit_from_inside = true
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider==candidate

func choose_target() -> Node2D:
	var candidate: Node2D
	var distance := INF
	for worker in get_tree().get_nodes_in_group("players"):
		if visible_worker(worker):
			var next_distance: float = global_position.distance_to(worker.global_position)
			if next_distance<distance:
				candidate = worker
				distance = next_distance
	if is_instance_valid(candidate):
		return candidate
	for flak in get_tree().get_nodes_in_group("anti_air"):
		if not is_instance_valid(flak) or flak.is_queued_for_deletion(): continue
		var owner_game: Node=flak.get("game")
		# Roof flak exposes its ownership through its damageable hull.
		if owner_game==null and is_instance_valid(flak.get("gun")):
			owner_game=flak.gun.get("game")
		if owner_game!=game: continue
		if not flak.has_method("can_be_targeted") or not flak.can_be_targeted():
			continue
		var point: Vector2 = attack_point_for(flak)
		var ray := PhysicsRayQueryParameters2D.create(muzzle_global(),point,1|2|8)
		var hit := get_world_2d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and hit.collider==flak:
			return flak
	# The physical projectile will still strike any earlier roof or glass pane.
	var nearest_distance := INF
	for wall in get_tree().get_nodes_in_group("walls"):
		if not is_instance_valid(wall) or wall.is_queued_for_deletion() or wall.get("game")!=game: continue
		if wall.has_method("is_blocking") and wall.is_blocking():
			var approach_distance: float = (wall.global_position.x-global_position.x)*attack_direction
			if approach_distance>=-55 and approach_distance<nearest_distance:
				candidate = wall
				nearest_distance = approach_distance
	if is_instance_valid(candidate):
		return candidate
	if is_instance_valid(game) and is_instance_valid(game.get("core")):
		return game.core
	return null

func _update_attack(delta: float) -> void:
	if dead or not authoritative() or not is_finite(delta) or delta<=0.0: return
	if burst_remaining>0:
		burst_clock -= delta
		if burst_clock<=0:
			_fire_at(_burst_destination())
			burst_remaining -= 1
			burst_clock = float(profile.burst_gap)
			if burst_remaining==0:
				attack_clock = float(profile.cooldown)
		return
	if attack_clock>0:
		return
	if windup<=0:
		target = choose_target()
		if not is_instance_valid(target):
			attack_clock = 0.4
			return
		locked_aim = attack_point_for(target)
		dive_origin = global_position
		windup = 0.001
		var audio_profile := AircraftAudioCatalog.profile_for(kind)
		var warning: String = str(audio_profile.get("charge_key",audio_profile.get("lock_key","")))
		if not warning.is_empty(): preload("res://scripts/spatial_sound.gd").emit(game,warning,muzzle_global())
	# Scout tracks during the first half of its tell; every shot has a dodge window.
	if kind=="scout_drone" and windup<float(profile.windup)*0.5 and is_instance_valid(target):
		locked_aim = attack_point_for(target)
	windup += delta
	if windup>=float(profile.windup):
		_fire_at(_burst_destination())
		burst_remaining = int(profile.burst)-1
		burst_clock = float(profile.burst_gap)
		windup = 0
		if burst_remaining==0:
			attack_clock = float(profile.cooldown)

func _burst_destination() -> Vector2:
	var index := attack_count % int(profile.burst)
	var offset := 0.0
	match kind:
		"rocket_drone": offset = -20.0 if index==0 else 20.0
		"patrol_plane": offset = -36.0+24.0*index
		"tiltrotor": offset = (index-1)*18.0
		"dive_bomber": offset = -22.0 if index==0 else 22.0
		"heavy_zeppelin": offset = -14.0 if index==0 else 14.0
	return locked_aim+Vector2(offset,0)

func _fire_at(destination: Vector2) -> bool:
	if dead or not authoritative() or not destination.is_finite() or not is_inside_tree() or not is_instance_valid(get_parent()):
		return false
	var active := 0
	for projectile in get_tree().get_nodes_in_group("air_projectiles"):
		if is_instance_valid(projectile) and not projectile.is_queued_for_deletion() and projectile.get("game") == game and not bool(projectile.get("spent")):
			active += 1
			if active >= HostileAirProjectile.MAX_ACTIVE:
				return false
	_pose_parts(destination)
	var origin := muzzle_global()
	if not origin.is_finite(): return false
	var shot := PROJECTILE.new()
	shot.game = game
	shot.damage = float(profile.damage)*EnemyCatalog.damage_scale(wave)*Balance.enemy_damage_multiplier(crew_size_at_spawn)
	shot.gravity = float(profile.gravity)
	shot.flavor = str(profile.flavor)
	if shot.gravity>0:
		var flight_time := clampf(origin.distance_to(destination)/float(profile.projectile_speed),0.6,3.6)
		shot.velocity = (destination-origin-Vector2(0,0.5*shot.gravity*flight_time*flight_time))/flight_time
	else:
		shot.velocity = (destination-origin).normalized()*float(profile.projectile_speed)
	get_parent().add_child(shot)
	shot.global_position = origin
	attack_count += 1
	weapon_recoil = 8.0 if kind in ["sky_fortress","heavy_zeppelin"] else 4.0
	muzzle_flash = 0.22 if kind in ["sky_fortress","heavy_zeppelin"] else 0.10
	if is_instance_valid(game) and game.has_method("sound"):
		preload("res://scripts/spatial_sound.gd").emit(game,str(AircraftAudioCatalog.profile_for(kind).get("fire_key","enemy_shot")),origin)
	return true

func shield_active() -> bool:
	return kind=="shield_airship" and windup<=0 and burst_remaining==0 and fmod(age,7.0)<4.0

func take_damage(amount: float) -> void:
	if dead or not authoritative() or not is_finite(amount) or amount<=0:
		return
	if shield_active():
		amount *= 0.5
		shield_flash = 0.25
	if int(get_meta("impact_contact_frame",-1))!=Engine.get_physics_frames():
		ImpactBurst.emit(game,global_position,"metal",Vector2.LEFT,clampf(amount/32,0.4,1.8))
	hp = maxf(0,hp-amount)
	hit_flash = 0.20
	if hp<=0:
		die()

func die() -> void:
	if dead or not authoritative():
		return
	dead = true
	CampaignSalvage.drop_for_enemy(game,self)
	remove_from_group("enemies")
	remove_from_group("air_enemies")
	collision_layer = 0
	ImpactBurst.emit(game,global_position,"explosion",Vector2.UP,1.7 if kind=="sky_fortress" else 1.0)
	if is_instance_valid(game):
		if game.get("stats") is Dictionary:
			game.stats.kills += 1
		if game.has_method("spawn_pickup"):
			var right: float = float(game.get("world_right")) if game.get("world_right")!=null else 1400.0
			# Aircraft never drop a required pile beyond the arena or onto the dome.
			var scenario := ScenarioCombat.for_game(game)
			var landing_x := clampf(global_position.x,1395.0 if wave>=16 else 895.0,maxf(1400,right)-35.0)
			if scenario != null: landing_x = clampf(global_position.x,scenario.arena_left+24,scenario.arena_right-38)
			game.spawn_pickup("scrap",int(profile.scrap),Vector2(landing_x,global_position.y+18))
			game.spawn_pickup("core",int(profile.cores),Vector2(landing_x+13,global_position.y+18))
		if game.has_method("sound"):
			preload("res://scripts/spatial_sound.gd").emit(game,"air_crash",global_position)
	spawn_motion_wreck()
	queue_free()

func spawn_motion_wreck() -> void:
	if is_instance_valid(motion): motion.spawn_wreck()

func _pose_parts(aim_override: Vector2 = Vector2.INF) -> void:
	if not is_instance_valid(body_part):
		return
	RhythmPresentation.machine_accent(self)
	var mirror := -attack_direction
	var size: float = float(profile.get("scale",1.0))
	var fixed_wing := kind in ["interceptor","dive_bomber","pulse_fighter","patrol_plane"]
	var body_mirror := mirror
	var turn_width := 1.0
	if fixed_wing and entered:
		if absf(flight_velocity.x)>1.0: _flight_facing = signf(flight_velocity.x)
		body_mirror = -_flight_facing
		# A return pass narrows through an edge-on bank before its side changes.
		turn_width = lerpf(.30,1.0,clampf(absf(flight_velocity.x)/24.0,0,1))
	for part in [body_part,propulsion_part]: part.scale = Vector2(body_mirror*turn_width,1)*size
	weapon_part.scale = Vector2(mirror,1)*size
	var pitch := clampf(flight_velocity.x*.0006,-.075,.075)
	if fixed_wing:
		pitch = clampf(-atan2(flight_velocity.y,maxf(60,absf(flight_velocity.x)))*body_mirror,-.28,.28)
	body_part.rotation = pitch+sin(age*24)*0.025*(hit_flash/0.2)
	propulsion_part.rotation = pitch
	body_part.position = Vector2.ZERO
	propulsion_part.position = Vector2.ZERO
	if is_instance_valid(motion) and not motion.pose.is_empty():
		var offset: Vector2 = Vector2(motion.pose.offset)*size
		offset.x *= mirror
		body_part.position = offset
		propulsion_part.position = offset
		body_part.rotation += float(motion.pose.roll)*mirror
		propulsion_part.rotation += float(motion.pose.roll)*mirror
	body_part.modulate = Color(1.65,1.5,1.4) if hit_flash>0.1 else Color.WHITE
	weapon_part.position = body_part.position+Vector2(0,float(profile.body_size.y)*0.34*size)
	if kind=="heavy_zeppelin": weapon_part.position.x += (-14 if attack_count%2==0 else 14)*mirror*size
	if str(profile.flavor)=="bomb":
		weapon_part.rotation = 0.0
		return
	var aim := aim_override if aim_override.is_finite() else (locked_aim if windup>0 or burst_remaining>0 or muzzle_flash>0 else global_position+Vector2(250*attack_direction,140))
	var difference := aim-weapon_part.global_position
	weapon_part.rotation = wrapf(Vector2(difference.x*mirror,difference.y).angle()-PI,-PI,PI)*mirror

func _draw_body() -> void:
	AircraftArt.body(self,body_part)

func _draw_propulsion() -> void:
	AircraftArt.propulsion(self,propulsion_part)

func _draw_weapon() -> void:
	AircraftArt.weapon(self,weapon_part)

func _draw() -> void:
	var size: Vector2 = profile.get("body_size",Vector2(57,34))
	if shield_active() or shield_flash>0:
		var color := Color(0.45,0.83,0.96,0.5+shield_flash)
		for side in [-1,1]:
			draw_arc(Vector2(side*36,0),48,-PI*0.55 if side>0 else PI*0.45,PI*0.55 if side>0 else PI*1.55,14,color,2)
	if hp<max_hp or windup>0:
		Art.bar(self,Rect2(-size.x*0.45,size.y*0.5+13,size.x*0.9,3),hp/max_hp,Art.RED)
		if show_status_labels:
			Art.text(self,Vector2(-size.x*0.45,size.y*0.5+29),LocaleText.text(str(profile.label)),10,Art.LIGHT)
