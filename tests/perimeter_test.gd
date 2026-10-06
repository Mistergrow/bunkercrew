extends SceneTree
const Controller=preload("res://scripts/perimeter_controller.gd")
const Catalog=preload("res://scripts/perimeter_catalog.gd")
const Cleanup=preload("res://tests/scene_cleanup.gd")
class ForeignActor extends Node2D:
	var game: Node
	var player_id:=1
	var inventory: Dictionary={"steel":20}
	var dead:=false
	func can_act(): return true
	func take_item(kind,amount):
		inventory[kind]=int(inventory.get(kind,0))-amount
		return true
var game
var controller
var player
var checks:=0
var failures:=0
func _initialize(): run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	print("PERIMETER ","PASS " if ok else "FAIL ",label)
	if not ok:
		failures+=1
		push_error(label)
func frames(count:=3):
	for index in count: await physics_frame
func site(role: String,side:=1,ordinal:=0):
	return controller.sites.filter(func(item):return item.role==role and item.side==side)[ordinal]
func build(target,level: int):
	player.position=target.global_position-Vector2(25,0)
	player.inventory=target.next_spec().cost.duplicate()
	for index in 150:
		if target.tier>=level: break
		target.interact(player,.1)
	check(target.tier==level,"Real deposits and assembly build %s tier%d"%[target.role,level])
	check(player.inventory.values().all(func(value):return int(value)==0),"Every required construction item leaves the builder's inventory once")
func settle_rounds():
	for index in 100:
		if get_nodes_in_group("perimeter_rounds").is_empty(): return
		await physics_frame
func spawn_machine(point: Vector2):
	var enemy=preload("res://scenes/enemy.tscn").instantiate()
	enemy.game=game
	enemy.kind="strider"
	enemy.position=point
	game.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy
func run():
	game=preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(1,{"environment":"sector07","position":"left","build_type":"workshop"})
	game.rounds.set_process(false)
	game.medic.set_physics_process(false)
	game.combat_events.persistence_enabled=false
	player=game.players[0]
	player.set_physics_process(false)
	controller=game.get("perimeter")
	if not is_instance_valid(controller):
		controller=Controller.new()
		game.add_child(controller)
		controller.bootstrap(game)
	check(controller.sites.size()==3,"Left bunker creates exactly three bounded east-front sites")
	controller.bootstrap(game)
	check(controller.sites.size()==3,"Bootstrap is idempotent")
	var fence=site("fence")
	var gun=site("ground")
	var front=site("ground",1,1)
	check(gun.position.x<front.position.x and front.position.x<fence.position.x and gun.position.x>game.scenario_combat.bunker_right,"Guns stand behind their barrier and outside the occupied bunker")
	check(fence.tier==1 and fence.hp==120 and fence.builder_player_id==0,"A new round begins with its existing outer mesh installed as infrastructure")
	fence.take_damage(10000)
	check(not fence.is_blocking() and fence.collision_layer==0,"Unbuilt stakes cannot obstruct movement or catch shots")
	check(not gun.lock_reason().is_empty() and "2" in gun.prompt(player),"Locked guns explain both their unlock and their material price")
	player.inventory={"steel":1}
	player.position=fence.global_position
	for index in 50: fence.interact(player,.1)
	check(fence.tier==0 and fence.materials=={"steel":1} and int(player.inventory.get("steel",0))==0,"An incomplete shared deposit stays paid without constructing a free fence")
	player.inventory={"steel":1}
	for index in 50: fence.interact(player,.1)
	check(fence.tier==1 and fence.hp==120 and int(player.inventory.get("steel",0))==0,"Second real unit finishes the affordable two-steel fence")
	player.position=Vector2(400,430)
	fence._physics_process(1)
	await frames()
	check(fence.is_blocking() and fence.collision_layer==3,"Closed fence is real crew terrain and projectile cover")
	var clear_edge:=PhysicsRayQueryParameters2D.create(fence.global_position+Vector2(-27,-80),fence.global_position+Vector2(-27,-12),2)
	var solid_center:=PhysicsRayQueryParameters2D.create(fence.global_position+Vector2(0,-80),fence.global_position+Vector2(0,-12),2)
	check(fence.get_world_2d().direct_space_state.intersect_ray(clear_edge).is_empty(),"Slim side-view barrier has no invisible wide collision beside its upright")
	var center_hit: Dictionary=fence.get_world_2d().direct_space_state.intersect_ray(solid_center)
	check(not center_hit.is_empty() and center_hit.collider==fence,"Narrow barrier still blocks physical shots through its center")
	var enemy=spawn_machine(fence.global_position+Vector2(130,0))
	check(enemy.nearest_obstacle()==fence,"Approaching AI targets the outer fence before the bunker")
	player.position=fence.global_position+Vector2(55,0)
	fence._physics_process(.2)
	check(fence.gate_open and not fence.is_blocking() and fence.collision_layer==0,"Crew proximity opens the physical gate without trapping the player")
	check(enemy.nearest_obstacle()!=fence,"Enemies can pass an open crew gate as the prompt promises")
	player.hp=0
	fence._physics_process(.4)
	check(fence.gate_open,"An incapacitated crew member keeps the gate open for rescue")
	player.hp=player.max_hp
	player.invulnerability=1
	fence._physics_process(.2)
	check(fence.gate_open,"Spawn protection never excludes a player from gate safety")
	player.position=Vector2(400,430)
	game.medic.position=fence.global_position-Vector2(55,0)
	fence._physics_process(.3)
	check(fence.gate_open and fence.navigation_passable(),"SAN-1 opens the same gate and exposes a planning-only passability hook")
	game.medic.position=Vector2(450,430)
	fence._physics_process(.25)
	check(fence.gate_open,"Closing grace keeps the passage clear behind a departing actor")
	fence._physics_process(.8)
	check(fence.is_blocking(),"Gate closes again after its safe passage interval")
	fence.take_damage(50)
	player.inventory={"steel":1}
	player.position=fence.global_position
	for index in 10: fence.interact(player,.1)
	check(fence.hp==120 and int(player.inventory.get("steel",0))==0,"Repair spends one actual steel item and clamps HP at its maximum")
	game.rounds.wave=6
	game.upgrades.owned.bunker_armor=true
	build(fence,2)
	check(fence.cure==8 and fence.hp<fence.max_hp,"New concrete must cure before reaching full strength")
	fence._physics_process(8)
	check(fence.cure==0 and is_equal_approx(fence.hp,320),"Curing adds only the unpaid strength reserve over eight seconds")
	game.rounds.wave=11
	build(fence,3)
	check(fence.max_hp==620 and fence.impact_material()=="metal","Armor-steel fence has distinct real durability and material feedback")
	game.upgrades.owned.perimeter_automation=true
	build(gun,1)
	gun.set_physics_process(false)
	check(gun.ammo==0 and gun.builder_player_id==1,"Autonomous construction creates no free ammunition and records its builder")
	player.inventory={"ammo":1}
	player.position=gun.global_position
	for index in 10: gun.interact(player,.1)
	check(gun.ammo==20 and int(player.inventory.get("ammo",0))==0,"One physical ammunition crate supplies exactly twenty rounds")
	player.position=Vector2(400,430)
	fence._physics_process(1)
	enemy.position=fence.global_position+Vector2(100,0)
	gun.tracking_target=enemy
	gun.aim_angle=gun.target_angle(enemy)
	await frames()
	gun.set_physics_process(false)
	var before_hp: float=enemy.hp
	var xp: float=player.progression.xp
	check(gun.target_visible(enemy) and gun.fire(),"Low ground gun has a real clear shot through its closed steel firing port")
	check(gun.ammo==19 and enemy.hp==before_hp,"A shot spends one round before any physical impact")
	await settle_rounds()
	check(enemy.hp<before_hp and player.progression.xp>xp,"Swept autonomous fire hits real enemies and credits the recorded builder")
	gun.cooldown=0
	gun.aim_angle=gun.target_angle(enemy)-.05
	check(gun.target_visible(enemy) and not gun.fire() and gun.ammo==19,"A tracking error toward our own plate cannot consume ammunition")
	gun.aim_angle=gun.target_angle(enemy)

	var block:=StaticBody2D.new()
	block.collision_layer=1
	block.position=gun.global_position+Vector2(120,-110)
	var shape:=CollisionShape2D.new()
	var box:=RectangleShape2D.new()
	box.size=Vector2(18,180)
	shape.shape=box
	block.add_child(shape)
	game.add_child(block)
	await frames()
	gun.cooldown=0
	check(not gun.target_visible(enemy) and not gun.fire() and gun.ammo==19,"Intervening cover prevents automatic fire and preserves ammunition")
	block.free()
	build(front,1)
	front.set_physics_process(false)
	front.ammo=20
	front.tracking_target=enemy
	front.aim_angle=front.target_angle(enemy)
	player.position=Vector2(400,430)
	fence._physics_process(1)
	await frames()
	gun.cooldown=0
	check(gun.target_visible(enemy) and front.target_visible(enemy),"Both compact guns retain a firing lane through the closed steel fence")
	before_hp=enemy.hp
	check(gun.fire() and front.fire(),"Rear rounds clear the real front chassis without excluding either cover body")
	await settle_rounds()
	check(enemy.hp<=before_hp-20,"Both independently supplied guns deliver real impacts outside the barrier")
	check(not controller.air_defense_ready() and controller.sites.all(func(item):return item.role!="flak"),"No outer flak or ground-gun air-wave unlock remains")
	check(gun.name=="East_ground_rear" and front.name=="East_ground_front" and fence.name=="East_fence","Repeated ground roles retain stable unique network names")
	for index in 3:
		check(is_equal_approx(controller.sites[index].position.x-game.scenario_combat.bunker_right,Catalog.SITES[index].distance),"Site%d uses the shared forward distance"%index)
	# A port is real empty space in either direction, while its frame is cover.
	for direction in [-1,1]:
		var opening:=PhysicsRayQueryParameters2D.create(fence.global_position+Vector2(60*direction,-38),fence.global_position+Vector2(-60*direction,-38),1|2|8)
		check(fence.get_world_2d().direct_space_state.intersect_ray(opening).is_empty(),"Firing port passes hostile and allied rays in direction%d"%direction)
	var plate:=PhysicsRayQueryParameters2D.create(fence.global_position+Vector2(60,-54),fence.global_position+Vector2(-60,-54),1|2|8)
	check(fence.get_world_2d().direct_space_state.intersect_ray(plate).get("collider")==fence,"Reinforced panel above the slit still catches incoming shots")
	var receiver:=PhysicsRayQueryParameters2D.create(front.global_position+Vector2(65,-40),front.global_position+Vector2(-20,-40),1|2|8)
	check(front.get_world_2d().direct_space_state.intersect_ray(receiver).get("collider")==front.head_hurtbox,"Hostile rounds hit the compact receiver rather than crossing its art")
	before_hp=front.hp
	front.head_hurtbox.take_damage(13)
	check(front.hp==before_hp-13,"Receiver damage reaches the same authoritative site HP")
	var hostile:=HostileAirProjectile.new()
	hostile.game=game
	hostile.position=front.global_position+Vector2(60,-40)
	hostile.velocity=Vector2.LEFT*500
	hostile.damage=11
	game.add_child(hostile)
	for index in 12: await physics_frame
	check(front.hp==before_hp-24,"An actual hostile swept projectile damages the receiver on first contact")
	var fence_before: float=fence.hp
	var covered:=HostileAirProjectile.new()
	covered.game=game
	covered.position=fence.global_position+Vector2(60,-54)
	covered.velocity=Vector2.LEFT*500
	covered.damage=9
	game.add_child(covered)
	for index in 12: await physics_frame
	check(fence.hp==fence_before-9,"Normal incoming ordnance damages solid plate above the firing slit")

	gun.ammo=20
	gun.burst_left=0
	for index in 3:
		gun.cooldown=0
		check(gun.fire() and gun.burst_left==2-index,"Finite burst shot%d advances its replicated count"%index)
		check(is_equal_approx(gun.cooldown,.14 if index<2 else 1.7),"Burst shot%d sets its proper interval or reload pause"%index)
	check(not gun.fire() and gun.ammo==17,"Reload pause cannot emit a fourth immediate round")
	gun.tracking_target=null
	gun._scan_clock=10
	gun.burst_left=2
	gun.cooldown=.1
	gun._watch(.01)
	check(gun.burst_left==0 and is_equal_approx(gun.cooldown,1.7),"Losing a target cannot bypass the finite burst reload pause")
	await settle_rounds()
	var large=spawn_machine(fence.global_position+Vector2(70,0))
	large.body_height=75
	enemy.position=fence.global_position+Vector2(150,0)
	gun.cooldown=10
	gun._scan_clock=0
	gun._watch(.01)
	check(gun.tracking_target==enemy,"Small visible raider takes priority over a nearer heavy machine")
	large.free()
	var other_game:=Node2D.new()
	root.add_child(other_game)
	var foreign:=ForeignActor.new()
	foreign.game=other_game
	foreign.position=fence.global_position
	foreign.add_to_group("players")
	foreign.add_to_group("enemies")
	other_game.add_child(foreign)
	var before_materials: Dictionary=fence.materials.duplicate()
	for index in 10: fence.interact(foreign,.2)
	check(foreign.inventory.steel==20 and fence.materials==before_materials and not gun.target_visible(foreign),"Another game cannot supply this site or become an autonomous target")
	fence._physics_process(1)
	check(not fence.gate_open,"A foreign game's player cannot hold this gate open")
	var foreign_wall=preload("res://scenes/wall.tscn").instantiate()
	foreign_wall.game=other_game
	foreign_wall.initial_state=DefenseWall.State.HARD
	foreign_wall.position=enemy.global_position-Vector2(10,0)
	other_game.add_child(foreign_wall)
	await frames()
	check(enemy.nearest_obstacle()==fence,"Ground enemies ignore a closer wall belonging to another game")
	other_game.free()
	var before_state: Array=[fence.hp,fence.tier,gun.ammo,gun.shot_serial]
	var was_active: bool=game.network.active
	var was_host: bool=game.network.is_host
	game.network.active=true
	game.network.is_host=false
	fence.take_damage(500)
	gun.cooldown=0
	check(not gun.fire(),"Guest-side automatic fire is rejected even through a direct API call")
	fence.interact(player,.25)
	fence._physics_process(.25)
	check(before_state==[fence.hp,fence.tier,gun.ammo,gun.shot_serial],"Guest-side damage, construction and simulation cannot mutate authoritative site state")
	game.network.active=was_active
	game.network.is_host=was_host
	gun.ammo=40
	gun.tracking_target=enemy
	gun.aim_angle=gun.target_angle(enemy)
	for index in 12:
		gun.cooldown=0
		gun.fire()
	gun.cooldown=0
	check(not gun.fire() and gun.ammo==28 and get_nodes_in_group("perimeter_rounds").size()==12,"All outposts share a hard twelve-round in-flight budget")
	for projectile in get_nodes_in_group("perimeter_rounds"): projectile.free()
	paused=true
	var before_cooldown: float=gun.cooldown
	var before_gate: float=fence.gate_amount
	for index in 3: await process_frame
	check(gun.cooldown==before_cooldown and fence.gate_amount==before_gate,"Pause freezes gate animation and weapon clocks")
	paused=false
	var paid: int=fence.tier
	fence.take_damage(10000)
	check(paid==3 and fence.tier==0 and fence.hp==0 and fence.ruined and not fence.is_blocking(),"Destroyed fencing leaves a traversable paid reconstruction site")
	player.position=fence.global_position
	player.inventory={}
	for index in 30: fence.interact(player,.1)
	check(fence.tier==0,"A destroyed fence cannot rebuild without paying again")
	check(await Cleanup.free_scene(game,self),"All gates, hulls, guns and projectile owners release cleanly")
	print("PERIMETER: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
