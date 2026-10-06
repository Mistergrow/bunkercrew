extends CharacterBody2D
## Transient offline escort, never an extra player, recruit, loot source or bank.
## The convoy owns its lifetime. Equipment survives stowing within this journey.
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Locomotion := preload("res://scripts/worker_locomotion.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const IdentityArt := preload("res://scripts/worker_identity_art.gd")
const Shot := preload("res://scripts/projectile.gd")
const Sound := preload("res://scripts/spatial_sound.gd")
const MAGAZINE := Balance.CONVOY_ESCORT_MAGAZINE
const INITIAL_RESERVE := Balance.CONVOY_ESCORT_RESERVE
const RANGE := Balance.CONVOY_ESCORT_RANGE
const SCAN_INTERVAL := 0.2
const SHOT_INTERVAL := Balance.CONVOY_ESCORT_SHOT_INTERVAL
const RELOAD_SECONDS := Balance.CONVOY_ESCORT_RELOAD_TIME
const SHOT_DAMAGE := Balance.CONVOY_ESCORT_DAMAGE
const SPEED := Balance.CONVOY_ESCORT_SPEED
const GRAVITY := 1100.0
const POST_DISTANCE := 180.0
const GUN_PIVOT := Vector2(10,-38)

var game: Node
var vehicle: Node2D
var character_id := "branko"
var post_side := 1.0
var max_hp := float(Balance.CONVOY_ESCORT_HP)
var hp := float(Balance.CONVOY_ESCORT_HP)
var ammo := MAGAZINE
var reserve := INITIAL_RESERVE
var dead := false
var active := false
var facing := 1.0
var aiming := false
var aim_direction := Vector2.RIGHT
var target: Node2D
var shots_fired := 0
var target_scans := 0
var cooldown := 0.0
var reload_timer := 0.0
var flash := 0.0
var recoil := 0.0
var hit_flash := 0.0
# Adapter for the existing presentation rig; no inventory/action input exists.
var drop_animation := 0.0
var body_visual: Node2D
var weapon_visual: Node2D
var pose: Dictionary = {}
var _locomotion := Locomotion.new()
var _scan_clock := 0.0
var _body_shape := RectangleShape2D.new()

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_PAUSABLE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group("convoy_defenders")
	post_side=-1.0 if post_side<0 else 1.0
	if not CharacterCatalog.contains(character_id): character_id="branko"
	collision_mask=1
	_body_shape.size=Vector2(14,46)
	var collider := CollisionShape2D.new()
	collider.name="EscortHitbox"
	collider.shape=_body_shape
	collider.position=Vector2(0,-23)
	add_child(collider)
	body_visual=Node2D.new()
	body_visual.name="EscortBody"
	body_visual.draw.connect(_draw_body)
	add_child(body_visual)
	weapon_visual=Node2D.new()
	weapon_visual.name="EscortRifle"
	weapon_visual.z_index=1
	weapon_visual.draw.connect(_draw_rifle)
	add_child(weapon_visual)
	pose=Personality.stance(PoseArt.neutral(),character_id)
	stow()

func carried_count() -> int: return 0

func offline_solo() -> bool:
	if not is_instance_valid(game) or game.is_queued_for_deletion() or not game.get("players") is Array: return false
	var network=game.get("network")
	if is_instance_valid(network) and bool(network.get("active")): return false
	var count := 0
	for person in game.players:
		if not is_instance_valid(person) or person.is_queued_for_deletion() or person.get("game")!=game: continue
		# A KO is still a human slot; an escort cannot appear when a partner falls.
		count+=1
	return count==1

func _repair_context() -> bool:
	return offline_solo() and is_instance_valid(vehicle) and not vehicle.is_queued_for_deletion() and vehicle.get("game")==game and not bool(vehicle.get("destroyed")) and float(vehicle.get("hp"))>0 and vehicle.get("journey_state") is Dictionary and str(vehicle.journey_state.get("phase",""))=="repair"

func deploy() -> bool:
	if dead or not is_inside_tree() or not _repair_context(): return false
	if active: return true
	var side := post_side*(-1.0 if float(vehicle.get("facing"))<0 else 1.0)
	var found := false
	for distance in [146.0,170.0,194.0]:
		var point := vehicle.global_position+Vector2(side*distance,0)
		var ground_query := PhysicsRayQueryParameters2D.create(point-Vector2(0,18),point+Vector2(0,100),1)
		var ground := get_world_2d().direct_space_state.intersect_ray(ground_query)
		if ground.is_empty() or ground.normal.y>-.6: continue
		point=Vector2(ground.position)-Vector2(0,.5)
		var body_query := PhysicsShapeQueryParameters2D.new()
		body_query.shape=_body_shape
		body_query.transform=Transform2D(0,point-Vector2(0,23))
		body_query.collision_mask=1|2
		body_query.exclude=[get_rid()]
		if not get_world_2d().direct_space_state.intersect_shape(body_query,1).is_empty(): continue
		global_position=point
		found=true
		break
	if not found: return false
	facing=side
	aim_direction=Vector2(side,0)
	velocity=Vector2.ZERO
	target=null
	aiming=false
	_scan_clock=0.0
	_locomotion.reset()
	active=true
	visible=true
	collision_layer=8
	_update_art(0.0)
	return true

func stow() -> void:
	if not active and not visible and collision_layer==0: return
	active=false
	aiming=false
	target=null
	velocity=Vector2.ZERO
	collision_layer=0
	visible=false
	position=Vector2(0,-20)
	_locomotion.reset()
	if is_instance_valid(weapon_visual): weapon_visual.visible=false

func can_be_targeted() -> bool:
	return active and not dead and hp>0 and not is_queued_for_deletion() and is_inside_tree() and _repair_context()

func attack_point() -> Vector2: return global_position-Vector2(0,29)
func impact_material() -> String: return "flesh"
func impact_sound() -> String: return "hit"

func take_damage(amount: float) -> void:
	if not can_be_targeted() or get_tree().paused or not is_finite(amount) or amount<=0: return
	hp=maxf(0,hp-amount)
	hit_flash=.18
	if hp<=0:
		dead=true
		active=false
		aiming=false
		target=null
		velocity=Vector2.ZERO
		collision_layer=0
		weapon_visual.visible=false
	if int(get_meta("impact_contact_frame",-1))!=Engine.get_physics_frames(): Sound.emit(game,"hit",attack_point())
	body_visual.queue_redraw()
	queue_redraw()

func _physics_process(delta: float) -> void:
	if not is_inside_tree() or get_tree().paused or not is_finite(delta) or delta<=0: return
	if not _repair_context():
		if active or visible: stow()
		return
	if not active or dead: return
	var dt := minf(delta,.1)
	cooldown=maxf(0,cooldown-dt)
	flash=maxf(0,flash-dt)
	recoil=WeaponEffectArt.recover_recoil(recoil,dt)
	hit_flash=maxf(0,hit_flash-dt)
	if reload_timer>0:
		var before := reload_timer
		reload_timer=maxf(0,reload_timer-dt)
		if before>RELOAD_SECONDS*.52 and reload_timer<=RELOAD_SECONDS*.52: Sound.emit(game,"reload_rifle_load",_gun_origin())
		if reload_timer==0:
			var transfer := mini(MAGAZINE-ammo,reserve)
			ammo+=transfer
			reserve-=transfer
			if transfer>0: Sound.emit(game,"reload_rifle_close",_gun_origin())
	_scan_clock-=dt
	if _scan_clock<=0:
		_scan_clock=SCAN_INTERVAL
		target=_choose_target()
	if not _valid_enemy(target): target=null
	aiming=is_instance_valid(target)
	if aiming:
		var direction := _enemy_point(target)-_gun_origin()
		if direction.length_squared()>.01:
			facing=-1.0 if direction.x<0 else 1.0
			aim_direction=(_enemy_point(target)-_gun_origin()).normalized()
		velocity.x=0
		if ammo==0 and reserve>0 and reload_timer==0:
			reload_timer=RELOAD_SECONDS
			Sound.emit(game,"reload_rifle_open",_gun_origin())
		elif cooldown==0 and reload_timer==0 and ammo>0:
			_fire()
	else:
		_move_to_post()
	velocity.y=minf(450,velocity.y+GRAVITY*dt)
	move_and_slide()
	_update_art(dt)
	queue_redraw()

func _move_to_post() -> void:
	var side := post_side*(-1.0 if float(vehicle.get("facing"))<0 else 1.0)
	var distance := vehicle.global_position.x+side*POST_DISTANCE-global_position.x
	velocity.x=0
	if absf(distance)<=6: return
	var direction := signf(distance)
	var point := global_position+Vector2(direction*16,0)
	var query := PhysicsRayQueryParameters2D.create(point-Vector2(0,3),point+Vector2(0,9),1)
	var ground := get_world_2d().direct_space_state.intersect_ray(query)
	if ground.is_empty() or ground.normal.y>-.6: return
	velocity.x=direction*minf(SPEED,absf(distance)*8.0)
	facing=direction
	aim_direction=Vector2(direction,0)

func _valid_enemy(candidate: Variant) -> bool:
	return is_instance_valid(candidate) and candidate is Node2D and not candidate.is_queued_for_deletion() and candidate.is_inside_tree() and candidate.get("game")==game and candidate.is_in_group("enemies") and not bool(candidate.get("dead")) and float(candidate.get("hp"))>0 and candidate.global_position.is_finite() and global_position.distance_squared_to(candidate.global_position)<=RANGE*RANGE

func _enemy_point(candidate: Node2D) -> Vector2:
	var height := float(candidate.get("body_height")) if candidate.get("body_height")!=null else 40.0
	return candidate.global_position-Vector2(0,clampf(height*.68,12,80))

func _gun_origin() -> Vector2: return global_position+GUN_PIVOT*Vector2(facing,1)

func _clear_line(candidate: Variant) -> bool:
	if not _valid_enemy(candidate): return false
	var side := -1.0 if candidate.global_position.x<global_position.x else 1.0
	var origin := global_position+GUN_PIVOT*Vector2(side,1)
	var query := PhysicsRayQueryParameters2D.create(origin,_enemy_point(candidate),1|2|4)
	query.exclude=[get_rid()]
	query.hit_from_inside=true
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider")==candidate

func _choose_target() -> Node2D:
	target_scans+=1
	var closest: Node2D
	var best := INF
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if not candidate is Node2D or not _valid_enemy(candidate) or not _clear_line(candidate): continue
		var distance: float=global_position.distance_squared_to(candidate.global_position)
		if distance<best:
			best=distance
			closest=candidate
	return closest

func _fire() -> bool:
	# Recheck at the actual shot, not only the five-per-second target scan.
	if not can_be_targeted() or get_tree().paused or ammo<=0 or reload_timer>0 or cooldown>0 or not _clear_line(target): return false
	var origin := _gun_origin()
	var direction := _enemy_point(target)-origin
	if not direction.is_finite() or direction.length_squared()<.01: return false
	var shot := Shot.new()
	shot.game=game
	shot.source=self
	shot.credit_worker=null
	shot.direction=direction.normalized()
	shot.damage=SHOT_DAMAGE
	shot.life=RANGE/shot.speed
	game.add_child(shot)
	shot.global_position=origin
	ammo-=1
	shots_fired+=1
	cooldown=SHOT_INTERVAL
	flash=.08
	recoil=2.0
	Sound.emit(game,"shot",origin+shot.direction*35)
	return true

func _update_art(delta: float) -> void:
	if not is_instance_valid(body_visual): return
	pose=_locomotion.advance(self,"walk" if absf(velocity.x)>8 else "idle",delta,false)
	if active and not dead:
		var local_direction := aim_direction*Vector2(facing,1)
		var gun := Transform2D(local_direction.angle(),GUN_PIVOT)
		pose.hands=[gun*Vector2(-1-recoil,1),gun*Vector2(15-recoil,-1)]
		pose.head_tilt=clampf(local_direction.angle()*.16,-.12,.12)
		pose.shoulder.x-=recoil*.16
		pose.head_shift.x-=recoil*.08
		if reload_timer>0:
			var progress := clampf(1.0-reload_timer/RELOAD_SECONDS,0,1)
			var grip: Vector2=pose.hands[1]
			var well: Vector2=gun*Vector2(7,8)
			var pouch := Vector2(9,-23)
			var chamber: Vector2=gun*Vector2(-2,-5)
			if progress<.17: pose.hands[1]=grip.lerp(well,smoothstep(0,.17,progress))
			elif progress<.4: pose.hands[1]=well.lerp(pouch,smoothstep(.17,.4,progress))
			elif progress<.64: pose.hands[1]=pouch.lerp(well,smoothstep(.4,.64,progress))
			elif progress<.76: pose.hands[1]=well
			elif progress<.9: pose.hands[1]=well.lerp(chamber,smoothstep(.76,.9,progress))
			else: pose.hands[1]=chamber.lerp(grip,smoothstep(.9,1,progress))
			pose.prop="rifle_magazine" if progress>=.34 and progress<.66 else ""
			var glance := smoothstep(.16,.38,progress)*(1.0-smoothstep(.64,.86,progress))
			pose.head_tilt+=glance*.07
			pose.head_shift.y+=glance*.6
			# Keep the receiver hand fixed and all reload contacts reachable.
			for unused in 5:
				var body := PoseArt.torso_transform(pose)
				for index in 2:
					var reach: Vector2=pose.hands[index]-body*PoseArt.shoulder_local(pose,index)
					if reach.length()>22.5: pose.shoulder+=reach.normalized()*(reach.length()-22.5)
	pose.continuous=true
	weapon_visual.position=GUN_PIVOT*Vector2(facing,1)
	weapon_visual.rotation=aim_direction.angle()
	weapon_visual.scale=Vector2(1,1 if aim_direction.x>=0 else -1)
	weapon_visual.visible=active and not dead
	body_visual.queue_redraw()
	weapon_visual.queue_redraw()

func _draw_body() -> void:
	if pose.is_empty(): return
	body_visual.draw_set_transform(Vector2(0,-12) if dead else Vector2.ZERO,post_side*PI*.5 if dead else 0.0,Vector2(facing,1))
	PoseArt.draw_identity_pose(body_visual,pose,character_id)
	body_visual.draw_set_transform(Vector2.ZERO)

func _draw_rifle() -> void:
	var kick := Vector2(-recoil,0)
	weapon_visual.draw_rect(Rect2(Vector2(-18,-4)+kick,Vector2(13,8)),Art.INK)
	weapon_visual.draw_rect(Rect2(Vector2(-16,-3)+kick,Vector2(10,5)),Color("887653"))
	weapon_visual.draw_rect(Rect2(Vector2(-8,-6)+kick,Vector2(23,12)),Art.INK)
	weapon_visual.draw_rect(Rect2(Vector2(-6,-4)+kick,Vector2(20,7)),Color("5d6b64"))
	weapon_visual.draw_rect(Rect2(Vector2(-3,4)+kick,Vector2(5,9)),Color("242f34"))
	var reload_progress := clampf(1.0-reload_timer/RELOAD_SECONDS,0,1)
	if reload_timer==0 or reload_progress<.22 or reload_progress>=.64:
		weapon_visual.draw_rect(Rect2(Vector2(5,4)+kick,Vector2(7,7)),Color("89917b"))
	weapon_visual.draw_rect(Rect2(Vector2(13,-2)+kick,Vector2(21,4)),Color("a0a997"))
	weapon_visual.draw_rect(Rect2(Vector2(29,-4)+kick,Vector2(7,8)),Color("253239"))
	weapon_visual.draw_rect(Rect2(Vector2(-2,-8)+kick,Vector2(10,3)),Color("8b957f"))
	for x in [-3,4,11]: weapon_visual.draw_rect(Rect2(Vector2(x,-2)+kick,Vector2(1,3)),Color("929d87"))
	# The escort's same rifle has the player's worn steel/wood material cues.
	# Fixed native clusters stay on the receiver through aim, mirror and kick.
	weapon_visual.draw_line(Vector2(-6,-4)+kick,Vector2(12,-4)+kick,Color("a7ad95"),1,false)
	weapon_visual.draw_line(Vector2(-6,2)+kick,Vector2(11,2)+kick,Color("34413e"),1,false)
	weapon_visual.draw_rect(Rect2(Vector2(-4,-2)+kick,Vector2(9,3)),Color("384944"))
	weapon_visual.draw_rect(Rect2(Vector2(-2,-2)+kick,Vector2(5,1)),Color("8a9682"))
	weapon_visual.draw_rect(Rect2(Vector2(8,-2)+kick,Vector2(5,2)),Color("b3b7a0"))
	weapon_visual.draw_rect(Rect2(Vector2(9,-1)+kick,Vector2(3,1)),Color("566358"))
	for point in [Vector2(-5,0),Vector2(6,-3)]: weapon_visual.draw_rect(Rect2(point+kick,Vector2.ONE),Color("c0b58e"))
	for index in 3: weapon_visual.draw_line(Vector2(-15+index*3,-2)+kick,Vector2(-16+index*3,1)+kick,Color("63553d"),1,false)
	weapon_visual.draw_line(Vector2(-15,-3)+kick,Vector2(-9,-3)+kick,Color("b0a17c"),1,false)
	weapon_visual.draw_line(Vector2(14,-2)+kick,Vector2(29,-2)+kick,Color("c0c4aa"),1,false)
	weapon_visual.draw_line(Vector2(14,1)+kick,Vector2(29,1)+kick,Color("34413e"),1,false)
	for x in [17,24]: weapon_visual.draw_rect(Rect2(Vector2(x,-3)+kick,Vector2(2,6)),Color("78877b"))
	weapon_visual.draw_rect(Rect2(Vector2(30,-3)+kick,Vector2(4,1)),Color("8c9480"))
	weapon_visual.draw_rect(Rect2(Vector2(33,-1)+kick,Vector2(2,2)),Color("101f23"))
	if reload_timer==0 or reload_progress<.22 or reload_progress>=.64:
		weapon_visual.draw_line(Vector2(5,5)+kick,Vector2(10,5)+kick,Color("b0b49a"),1,false)
		for index in 3: weapon_visual.draw_line(Vector2(6,6+index)+kick,Vector2(9,6+index)+kick,Color("5d6c5c"),1,false)
	WeaponEffectArt.muzzle(weapon_visual,Vector2(35-recoil,0),flash,.08,1,.72,shots_fired,WeaponEffectArt.reduced(game))
	# The same glove/skin pixels as the player stay above the receiver, so the
	# rigid rifle hides neither grip nor the forearms attached to those hands.
	var palette := IdentityArt.palette(character_id,PoseArt.C)
	for index in 2:
		var hand := weapon_visual.to_local(to_global(Vector2(pose.hands[index])*Vector2(facing,1)))
		weapon_visual.draw_rect(Rect2(hand+Vector2(-3,-2),Vector2(7,6)),palette.ink)
		weapon_visual.draw_rect(Rect2(hand+Vector2(-2,-1),Vector2(5,4)),palette.leather_light if index==1 else palette.leather)
		weapon_visual.draw_rect(Rect2(hand+Vector2(1,-1),Vector2(2,2)),palette.skin_light if index==1 else palette.skin)
		weapon_visual.draw_rect(Rect2(hand+Vector2(-2,2),Vector2(4,1)),palette.leather)

func _draw() -> void:
	if not active or dead: return
	if hp<max_hp: Art.bar(self,Rect2(-16,-66,32,3),hp/max_hp,Art.RED)
	if reserve==0 or reload_timer>0: Art.bar(self,Rect2(-12,-61,24,2),float(ammo)/MAGAZINE,Art.AMBER)
