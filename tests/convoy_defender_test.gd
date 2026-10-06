extends SceneTree
## Real CharacterBody/terrain/vehicle hull and swept projectiles; no fake hits.
const Defender := preload("res://scripts/convoy_defender.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
var checks := 0
var failures := 0
var game: Arena

class Room extends Node:
	var active := false
	var is_host := true

class Arena extends Node2D:
	var players: Array = []
	var network: Node
	var started := true
	var scenery: Node
	var combat_gore: Node
	var sounds: Array[Dictionary] = []
	var credited: Node
	var hit_calls := 0
	func sound_at(kind: String,at: Vector2) -> void: sounds.append({"kind":kind,"at":at})
	func impact(_point: Vector2,_material: String,_normal: Vector2,_power: float) -> void: pass
	func combat_hit(victim: Node,amount: float,worker: Node=null) -> float:
		credited=worker
		hit_calls+=1
		var before: float=victim.hp
		victim.take_damage(amount)
		return before-float(victim.hp)

class Human extends Node2D:
	var game: Node
	var downed := false
	var inventory := {"ammo":3,"steel":5}
	func is_downed() -> bool: return downed

class Van extends CharacterBody2D:
	var game: Node
	var hp := 600.0
	var destroyed := false
	var facing := 1.0
	var journey_state := {"phase":"repair"}

class Enemy extends CharacterBody2D:
	var game: Node
	var hp := 100.0
	var body_height := 40.0
	var dead := false
	var hits := 0
	func take_damage(amount: float) -> void:
		hp=maxf(0,hp-amount)
		hits+=1
		dead=hp==0
		if dead: collision_layer=0

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	print("ESCORT %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)

func shape(body: CollisionObject2D,size: Vector2,offset: Vector2=Vector2.ZERO) -> void:
	var collider := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size=size
	collider.shape=rectangle
	collider.position=offset
	body.add_child(collider)

func frames(count: int=3) -> void:
	for _frame in count: await physics_frame

func spawn_enemy(point: Vector2,world: Node=null,health: float=100.0) -> Enemy:
	var enemy := Enemy.new()
	enemy.game=game if world==null else world
	enemy.position=point
	enemy.hp=health
	enemy.collision_layer=4
	enemy.collision_mask=0
	enemy.add_to_group("enemies")
	shape(enemy,Vector2(28,48),Vector2(0,-24))
	game.add_child(enemy)
	return enemy

func spawn_defender(van: Van,side: float,id: String):
	var escort := Defender.new()
	escort.game=game
	escort.vehicle=van
	escort.post_side=side
	escort.character_id=id
	van.add_child(escort)
	escort.set_physics_process(false)
	return escort

func retire_shots() -> void:
	for child in game.get_children():
		if child is BunkerProjectile: child.queue_free()
	await frames()

func run() -> void:
	if not "--no-profile-save" in OS.get_cmdline_user_args() or not "--no-upnp" in OS.get_cmdline_user_args(): quit(2); return
	game=Arena.new()
	root.add_child(game)
	current_scene=game
	var room := Room.new()
	game.network=room
	game.add_child(room)
	var human := Human.new()
	human.game=game
	human.position=Vector2(950,430)
	game.add_child(human)
	game.players.append(human)
	var ground := StaticBody2D.new()
	ground.collision_layer=1
	ground.position=Vector2(1000,450)
	shape(ground,Vector2(2500,40))
	game.add_child(ground)
	var van := Van.new()
	van.game=game
	van.position=Vector2(1000,430)
	van.collision_layer=2
	van.collision_mask=1
	shape(van,Vector2(182,44),Vector2(0,-22))
	shape(van,Vector2(54,60),Vector2(62,-37))
	game.add_child(van)
	var left=spawn_defender(van,-1,"branko")
	var right=spawn_defender(van,1,"ivo")
	await frames()
	check(not left.active and not left.visible and left.collision_layer==0,"New vehicle children start safely stowed")
	check(left.ammo==24 and left.reserve==48 and right.ammo==24 and right.reserve==48,"Each escort owns exactly 72 finite rounds")
	check(not left.is_in_group("players") and not left.is_in_group("enemies") and game.players.size()==1,"Helpers neither claim human slots nor change enemy counts")
	human.downed=true
	check(left.offline_solo(),"A solo KO still counts as the existing human slot")
	human.downed=false
	check(left.deploy() and right.deploy(),"Both sides deploy only onto actual supported ground outside the van")
	var deployed_point: Vector2=right.global_position
	var deployed_pose: Dictionary=right.pose.duplicate(true)
	check(right.deploy() and right.global_position==deployed_point and right.pose==deployed_pose,"Repeated deploy preserves the exact active position and pose")
	check(left.weapon_visual.visible and right.weapon_visual.visible and not left.aiming and left.shots_fired==0,"Idle escorts visibly hold their rifles without inventing targets or shots")
	check(left.global_position.x<van.global_position.x-100 and right.global_position.x>van.global_position.x+100 and left.collision_layer==8,"Escort bodies expose real friendly hitboxes on opposite flanks")
	check(left.body_visual.get_script()==null and right.weapon_visual.get_script()==null,"Presentation uses native side-view nodes without hidden replica actor types")
	var initial_position: Vector2=right.global_position
	right.set_physics_process(true)
	await frames(22)
	right.set_physics_process(false)
	check(right.global_position.x>initial_position.x+10 and absf(right.global_position.y-430)<1,"Escort walks physically to its post and stands on the actual road")
	check(right.weapon_visual.visible and right.pose.hands[1].distance_to(right.pose.shoulder)>10 and right.shots_fired==0,"Walking escort keeps its rifle and supported grip while remaining silent")
	check(not right.pose.is_empty() and not bool(right.pose.get("front",false)),"Existing worker locomotion keeps side-view limb animation")
	var reload_stock := Vector2(right.ammo,right.reserve)
	var reload_position: Vector2=right.global_position
	var original_facing: float=right.facing
	var original_aim: Vector2=right.aim_direction
	var reload_excursion := 0.0
	for side in [-1.0,1.0]:
		right.facing=side
		for angle in [-.7,0.0,.55]:
			right.aim_direction=Vector2.from_angle(angle)*Vector2(side,1)
			right.reload_timer=0
			right._update_art(0)
			var fixed_feet: Array=right.pose.feet.duplicate()
			var original_grip: Vector2=right.pose.hands[1]
			for progress in [.0,.14,.3,.45,.6,.8,.95]:
				right.reload_timer=Defender.RELOAD_SECONDS*(1.0-progress)
				right._update_art(0)
				var body := PoseArt.torso_transform(right.pose)
				var reach_ok := true
				for index in 2:
					reach_ok=reach_ok and (body*PoseArt.shoulder_local(right.pose,index)).distance_to(right.pose.hands[index])<=22.9
				var receiver := Transform2D(angle,Defender.GUN_PIVOT)*Vector2(-1-right.recoil,1)
				check(reach_ok and Vector2(right.pose.hands[0]).distance_to(receiver)<.001 and right.pose.feet==fixed_feet,"Reload keeps a real receiver grip, reachable free glove and supported feet in both directions")
				reload_excursion=maxf(reload_excursion,Vector2(right.pose.hands[1]).distance_to(original_grip))
	check(reload_excursion>14 and Vector2(right.ammo,right.reserve)==reload_stock and right.global_position==reload_position,"Visible pouch/magazine reach cannot spend rounds or move the escort root")
	right.reload_timer=0
	right.facing=original_facing
	right.aim_direction=original_aim
	right._update_art(0)
	var enemy := spawn_enemy(Vector2(1370,430))
	await frames()
	right.target=enemy
	right.facing=1
	check(right._fire(),"Visible hostile receives a real swept rifle projectile")
	var shot: BunkerProjectile
	for child in game.get_children():
		if child is BunkerProjectile: shot=child
	check(is_instance_valid(shot) and shot.source==right and shot.credit_worker==null,"Projectile carries the actual escort source and no fake player attribution")
	await frames(16)
	check(enemy.hits==1 and enemy.hp==84 and game.hit_calls==1 and game.credited==null,"Only actual projectile contact removes health once")
	check(right.ammo==23 and right.reserve==48 and right.shots_fired==1 and human.inventory=={"ammo":3,"steel":5},"Shot consumes one escort round without changing player inventory")
	check(game.sounds.any(func(event): return event.kind=="shot" and event.at.x>right.global_position.x),"Rifle sound originates at the physical muzzle")
	var blocker := StaticBody2D.new()
	blocker.position=Vector2(1260,395)
	blocker.collision_layer=1
	shape(blocker,Vector2(24,80))
	game.add_child(blocker)
	await frames()
	right.cooldown=0
	var before_ammo: int=right.ammo
	check(not right._clear_line(enemy) and not right._fire() and right.ammo==before_ammo,"Terrain blocks the target and spends no ammunition")
	blocker.queue_free()
	await frames()
	enemy.global_position=Vector2(1180,430)
	await frames()
	left.target=enemy
	check(not left._clear_line(enemy) and not left._fire(),"The real van chassis blocks shots through the opposite flank")
	enemy.global_position=Vector2(1370,430)
	var rear_enemy := spawn_enemy(Vector2(620,430))
	await frames()
	left.target=rear_enemy
	left.facing=-1
	check(left._fire(),"Rear escort fires outward with correctly mirrored world ballistics")
	await frames(16)
	check(rear_enemy.hp==84,"Left-directed round hits its actual rear target")
	await retire_shots()
	var foreign := Node2D.new()
	game.add_child(foreign)
	var foreign_enemy := spawn_enemy(Vector2(1350,430),foreign)
	await frames()
	check(not right._valid_enemy(foreign_enemy),"Foreign-world enemies are never eligible")
	enemy.dead=true
	check(not right._valid_enemy(enemy),"Dead enemies are never eligible")
	enemy.dead=false
	enemy.queue_free()
	check(not right._valid_enemy(enemy),"Targets queued for deletion are rejected before their next frame")
	await frames()
	check(not right._valid_enemy(enemy),"Actually freed targets are rejected safely")
	right.target=foreign_enemy
	right.cooldown=0
	check(not right._fire(),"A stale or foreign target cannot bypass shot validation")
	foreign_enemy.queue_free()
	rear_enemy.queue_free()
	await frames()
	var durable := spawn_enemy(Vector2(1370,430),null,100000.0)
	await frames()
	right.target=durable
	right.cooldown=0
	paused=true
	var before_shots: int=right.shots_fired
	var before_position: Vector2=right.global_position
	var before_hp: float=right.hp
	right._physics_process(.1)
	right.take_damage(10)
	check(not right._fire() and right.shots_fired==before_shots and right.global_position==before_position and right.hp==before_hp,"Explicit callbacks respect pause without movement, shots or damage")
	paused=false
	right._physics_process(NAN)
	right.take_damage(INF)
	check(right.shots_fired==before_shots and right.hp==before_hp,"Nonfinite time and damage inputs are harmless")
	room.active=true
	room.is_host=true
	check(not right._fire() and not right.deploy(),"Even an online host cannot activate offline-only escorts")
	right._physics_process(.1)
	check(not right.active and not right.visible and right.collision_layer==0,"Entering a network room immediately stows cosmetic and combat state")
	room.is_host=false
	check(not right.deploy(),"A network guest cannot create escort combat")
	room.active=false
	room.is_host=true
	var second := Human.new()
	second.game=game
	second.downed=true
	game.add_child(second)
	game.players.append(second)
	check(not right.offline_solo() and not right.deploy(),"A KO second local human still disables solo escorts")
	game.players.erase(second)
	second.queue_free()
	await frames()
	check(right.deploy() and right.ammo==before_ammo and right.reserve==48,"Redeploy never refills prior escort equipment")
	# Run the real actor/projectile simulation faster, without manufacturing hit,
	# magazine, reload or channel completion. Physics time is capped at .1s.
	Engine.time_scale=6
	right.set_physics_process(true)
	before_shots=right.shots_fired
	var before_total: int=right.ammo+right.reserve
	var before_scans: int=right.target_scans
	var tick_count := 0
	var saw_reload := false
	while right.ammo+right.reserve>0 and tick_count<600:
		await physics_frame
		tick_count+=1
		saw_reload=saw_reload or right.reload_timer>0
	await frames(10)
	right.set_physics_process(false)
	Engine.time_scale=1
	check(saw_reload and right.shots_fired-before_shots==before_total and right.ammo==0 and right.reserve==0,"Actual reloads consume exactly all remaining rounds, then stop")
	check(durable.hits==before_total and human.inventory=={"ammo":3,"steel":5},"Finite real contact damage neither duplicates ammo nor steals player supplies")
	check(right.target_scans-before_scans<=ceili(float(tick_count+10)*.1/Defender.SCAN_INTERVAL)+1,"Crowd acquisition stays bounded to five scans per simulated second")
	before_shots=right.shots_fired
	right.cooldown=0
	check(not right._fire() and right.shots_fired==before_shots,"Empty escort cannot generate free projectiles")
	right.take_damage(25)
	check(right.hp==Balance.CONVOY_ESCORT_HP-25 and right.can_be_targeted(),"Live escort accepts real finite damage as a defense target")
	right.take_damage(1000)
	check(right.dead and right.hp==0 and not right.can_be_targeted() and right.collision_layer==0,"Incapacitated escort becomes nonblocking and untargetable")
	check(not right.deploy() and right.ammo==0 and right.reserve==0,"Dead escort cannot respawn or refill inside this journey")
	left.stow()
	var stowed_point: Vector2=left.position
	left.stow()
	check(left.position==stowed_point and not left.active and left.reserve==48,"Repeated stow changes neither equipment nor the parked state")
	var saved_ammo: int=left.ammo
	van.journey_state.phase="driving"
	check(not left.deploy() and left.ammo==saved_ammo,"Driving cannot deploy an escort or mutate its equipment")
	van.journey_state.phase="repair"
	check(left.deploy(),"Surviving escort may return at the same journey's repair phase")
	van.destroyed=true
	left._physics_process(.1)
	check(not left.active and not left.can_be_targeted(),"Destroyed vehicle invalidates escort combat immediately")
	var weak_left: WeakRef=weakref(left)
	var weak_right: WeakRef=weakref(right)
	van.queue_free()
	await frames()
	check(weak_left.get_ref()==null and weak_right.get_ref()==null,"Vehicle lifetime releases both escort bodies and their references")
	check(await Cleanup.free_scene(game,self),"Arena and real projectile playback teardown completes")
	print("ESCORT RESULTS %d passed, %d failed" % [checks-failures,failures])
	quit(0 if failures==0 else 1)
