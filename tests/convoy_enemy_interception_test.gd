extends SceneTree
## Actual main/road, native vehicle hull and escort colliders, production enemy
## hitscan. Positions isolate each ray; health is changed only by accepted hits.
const Journey := preload("res://scripts/convoy_journey.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/convoy-defense-20261004/gameplay"
var game
var checks := 0
var failures := 0
var evidence: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	print("ESCORT INTERCEPT %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)

func frames(count: int=3) -> void:
	for _frame in count:
		await physics_frame
		await process_frame

func cover_at(point: Vector2) -> StaticBody2D:
	var cover := StaticBody2D.new()
	cover.position=point
	cover.collision_layer=1
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size=Vector2(24,100)
	collider.shape=shape
	cover.add_child(collider)
	game.add_child(cover)
	return cover

func first_contact(enemy: Node2D,at: Vector2) -> Dictionary:
	var ray := PhysicsRayQueryParameters2D.create(enemy.weapon_part.global_position,at,1|2|8)
	ray.hit_from_inside=true
	return enemy.get_world_2d().direct_space_state.intersect_ray(ray)

func run() -> void:
	if not "--no-profile-save" in OS.get_cmdline_user_args() or not "--no-upnp" in OS.get_cmdline_user_args(): quit(2); return
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(1,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	game.rounds.running=false
	game.rounds.wave=20
	check(game.expedition.on_victory(),"Prepared actual victory opens the solo garage")
	check(game.campaign.select_destination("harbor") and not game.campaign.begin_journey().is_empty(),"Actual finite campaign checkpoint permits the road fixture")
	game.expedition._start_road()
	game.expedition.set_physics_process(false)
	game.medic.set_physics_process(false)
	game.set_process(false)
	game.hud.overlay=""
	paused=false
	var truck: Node2D=game.expedition.vehicle
	truck.set_physics_process(false)
	truck.position=Vector2(1740,430)
	for person in game.players:
		person.set_physics_process(false)
		person.get_node("WorkerWeapon").set_physics_process(false)
	await frames()
	Journey.change_phase(truck.journey_state,"driving")
	check(truck.begin_breakdown(),"Actual tire breakdown deploys the transient offline crew")
	truck._sync_solo_defenders()
	check(truck.defenders.size()==2 and truck.active_defenders()==2,"Both genuine escort bodies are deployed")
	for escort in truck.defenders: escort.set_physics_process(false)
	var rear: Node2D=truck.defenders[0]
	var front: Node2D=truck.defenders[1]
	var enemy: Node2D=game._entity("enemy",truck.position+Vector2(390,0),{"kind":"strider","wave":1})
	enemy.set_meta("expedition_guard",true)
	enemy.target=truck
	enemy.process_mode=Node.PROCESS_MODE_DISABLED
	enemy._pose_parts()
	await frames()
	var collision := first_contact(enemy,truck.attack_point())
	check(not collision.is_empty() and collision.collider==front,"Aimed-at-vehicle enemy ray first contacts the real front escort hitbox")
	check(game.expedition.combat_target_for(enemy)==front,"Actual repair target selection chooses the exposed front escort")
	var front_hp: float=front.hp
	var rear_hp: float=rear.hp
	var truck_hp: float=truck.hp
	var attacks: int=enemy.attack_count
	check(enemy._fire_collision_shot(truck.attack_point(),truck,12),"Production enemy shot accepts a same-game live escort intercept")
	check(front.hp==front_hp-12 and rear.hp==rear_hp and truck.hp==truck_hp,"Intercept damage reaches only the physical first-contact escort")
	check(enemy.attack_count==attacks+1 and enemy.to_global(enemy.tracer_end).distance_to(collision.position)<.01,"One accepted shot records exactly one attack and its actual contact tracer")
	evidence.append({"case":"live_intercept","enemy_aim":"vehicle","physical_victim":"front_escort","escort_hp_before":front_hp,"escort_hp_after":front.hp,"truck_hp_before":truck_hp,"truck_hp_after":truck.hp,"first_contact":[collision.position.x,collision.position.y],"tracer_endpoint":[enemy.to_global(enemy.tracer_end).x,enemy.to_global(enemy.tracer_end).y]})
	var cover := cover_at(truck.position+Vector2(290,-35))
	await frames()
	front_hp=front.hp
	attacks=enemy.attack_count
	check(first_contact(enemy,truck.attack_point()).get("collider")==cover,"Real terrain geometry precedes escort and hull along the enemy ray")
	check(not enemy._fire_collision_shot(truck.attack_point(),truck,12) and front.hp==front_hp and truck.hp==truck_hp and enemy.attack_count==attacks,"Terrain protects escort and vehicle without manufacturing an accepted attack")
	check(game.expedition.combat_target_for(enemy)==truck,"Blocked candidate falls back to the actual vehicle target")
	cover.queue_free()
	await frames()
	front.stow()
	await frames()
	check(first_contact(enemy,rear.attack_point()).get("collider")==truck,"Native vehicle hull precedes the opposite rear escort")
	check(not enemy._fire_collision_shot(rear.attack_point(),rear,12) and rear.hp==rear_hp and truck.hp==truck_hp,"The hull stops a shot aimed through it at the rear escort")
	check(enemy._fire_collision_shot(truck.attack_point(),truck,12) and truck.hp==truck_hp-12*truck.incoming_damage_multiplier,"With the exposed escort stowed, an actual hull contact damages only the intended truck")
	truck_hp=truck.hp
	check(front.deploy(),"Live front escort returns with its existing health and finite gear")
	await frames()
	front_hp=front.hp
	front.active=false
	attacks=enemy.attack_count
	check(front.collision_layer==8 and not front.can_be_targeted(),"Ineligible escort fixture retains the real collider for the targetability admission check")
	check(not enemy._fire_collision_shot(truck.attack_point(),truck,12) and front.hp==front_hp and truck.hp==truck_hp and enemy.attack_count==attacks,"A physically intercepted but untargetable escort is rejected without damage")
	check(game.expedition.combat_target_for(enemy)==truck,"Untargetable escort cannot redirect the guard's selected target")
	front.active=true
	var other_world := Node2D.new()
	game.add_child(other_world)
	front.game=other_world
	check(not enemy._fire_collision_shot(truck.attack_point(),truck,12) and front.hp==front_hp and truck.hp==truck_hp and enemy.attack_count==attacks,"A same-layer foreign-world escort is never granted friendly interception")
	check(game.expedition.combat_target_for(enemy)==truck,"Foreign ownership is rejected by repair target selection")
	front.game=game
	check(game.expedition.combat_target_for(enemy)==front,"Restored same-game eligible escort is selected again")
	front.queue_free()
	check(game.expedition.combat_target_for(enemy)==truck,"Queued escort is rejected before the deferred retirement")
	await frames()
	check(game.expedition.combat_target_for(enemy)==truck,"Actually freed escort reference is safely ignored in the vehicle roster")
	check(rear.hp==rear_hp and game.players.size()==1,"Other escort and actual human roster remain unchanged")
	evidence.append({"case":"admission_and_cover","terrain_first_contact":true,"hull_blocks_opposite_escort":true,"untargetable_collider_rejected":true,"foreign_ownership_rejected":true,"queued_and_freed_target_rejected":true})
	check(await Cleanup.free_scene(game,self),"Actual scene, transient effects and native audio teardown completes")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var out := FileAccess.open(OUTPUT+"/enemy-interception.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"checks":checks,"passed":checks-failures,"failures":failures,"prepared_state":"Actual solo main scene, prepared wave20 victory and paid-valid harbor campaign boundary; production road at x1740 and Journey.breakdown; real escort bodies and strider weapon. Autonomous actor/controller motion disabled only to isolate each native physics ray. Enemy damage is12 for measurement, actual production hit handling unchanged. No fake HP contact, save edits or new wire kinds.","evidence":evidence},"\t"))
	out.close()
	print("ESCORT INTERCEPT RESULTS %d passed, %d failed" % [checks-failures,failures])
	quit(0 if failures==0 else 1)
