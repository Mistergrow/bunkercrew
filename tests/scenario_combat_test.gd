extends SceneTree
## Both physical approach lanes, real obstruction rays, aiming, and paid device
## placement. Does not rely on a mirrored viewport or move the whole world.
class CoreStub extends Node2D:
	var hp := 900.0
	func take_damage(value): hp -= value
class World extends Node2D:
	var scenario_combat: ScenarioCombat
	var core: Node2D
	var world_right:=1690.0
	var players: Array=[]
	var ladders: Array[Rect2]=[]
	func sound(_kind): pass
	func notify(_message): pass
	func fx(_at,_color,_count): pass
	func impact(_at,_kind,_normal=Vector2.UP,_force=1.0): pass
	func spawn_pickup(_kind,_count,_at): pass
class PlayerStub extends Node2D:
	var game: Node
	var player_id:=2
	var facing:=1.0
	var mounted_turret: Node2D
	var focus: Node2D
	func selected_material(): return ""
	var inventory: Dictionary={}
	func action(s): return "p%d_%s"%[player_id,s]
	func can_act(): return true
	func is_downed(): return false
	func take_item(_kind,_count): return false
class AimTarget extends Node2D:
	func attack_point(): return global_position
var checks:=0
var failures:=0
func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks+=1
	if value: print("PASS ",label)
	else:
		failures+=1
		push_error(label)
func wall(world,at: Vector2) -> DefenseWall:
	var node:=DefenseWall.new()
	node.game=world
	node.initial_state=DefenseWall.State.HARD
	node.position=at
	world.add_child(node)
	return node
func machine(world,at: Vector2,direction: float,kind: String="strider") -> SiegeMachine:
	var node:=SiegeMachine.new()
	node.game=world
	node.position=at
	node.attack_direction=direction
	node.kind=kind
	world.add_child(node)
	node.set_physics_process(false)
	return node
func run():
	InputSetup.install()
	var world:=World.new()
	root.add_child(world)
	var scenario:=ScenarioCombat.new()
	world.scenario_combat=scenario
	scenario.configure("center",-250,1690,430,400,1040,720)
	var core:=CoreStub.new()
	core.position=Vector2(720,430)
	world.core=core
	world.add_child(core)
	var floor_body:=StaticBody2D.new()
	floor_body.collision_layer=1
	var floor_shape:=CollisionShape2D.new()
	var rectangle:=RectangleShape2D.new()
	rectangle.size=Vector2(2240,18)
	floor_shape.shape=rectangle
	floor_body.add_child(floor_shape)
	floor_body.position=Vector2(720,439)
	world.add_child(floor_body)
	var left:=wall(world,Vector2(408,430))
	var right:=wall(world,Vector2(1032,430))
	var deep:=wall(world,Vector2(300,635))
	var east:=machine(world,Vector2(1232,430),-1)
	var west:=machine(world,Vector2(208,430),1)
	await physics_frame
	await physics_frame
	check(east.nearest_obstacle()==right and west.nearest_obstacle()==left,"Both approaches select their own first physical front; underground walls ignored")
	var start_e:=east.position.x
	var start_w:=west.position.x
	east._physics_process(0.1)
	west._physics_process(0.1)
	check(east.position.x<start_e and west.position.x>start_w,"Machines physically advance toward the core from both sides")
	for pair in [[east,right],[west,left]]:
		var enemy: SiegeMachine=pair[0]
		var defense: DefenseWall=pair[1]
		enemy.position.x=defense.position.x-enemy.attack_direction*enemy.attack_reach
		enemy.target=enemy.nearest_obstacle()
		enemy._pose_parts()
		await physics_frame
		var before:=defense.hp
		check(enemy.attack_obstacle() and defense.hp<before,"Directional attack damages the actual approached wall: %s"%enemy.attack_direction)
		check(core.hp==900,"Core protected by intervening wall: %s"%enemy.attack_direction)
	left.take_damage(9999)
	await physics_frame
	west.target=west.nearest_obstacle()
	check(west.target==core,"Breached west front exposes core without selecting east wall beyond core")
	west.position.x=core.position.x-west.attack_reach
	await physics_frame
	check(west.attack_obstacle() and core.hp<900,"Left approach can damage the exposed core")
	right.take_damage(9999)
	await physics_frame
	east.target=east.nearest_obstacle()
	check(east.target==core,"Breached east front exposes core")
	east.position.x=core.position.x+east.attack_reach
	await physics_frame
	var core_before:=core.hp
	check(east.attack_obstacle() and core.hp<core_before,"Right approach still damages exposed core")
	east.free(); west.free(); deep.free(); left.free(); right.free()
	var aim_target:=AimTarget.new()
	world.add_child(aim_target)
	for kind: String in EnemyCatalog.GROUND_CLASSES:
		if EnemyCatalog.is_human(kind): continue # Infantry has articulated human aim/ballistic checks.
		var enemy:=machine(world,Vector2(300,430),1,kind)
		enemy.target=aim_target
		for offset in [Vector2(300,-60),Vector2(300,0),Vector2(300,95)]:
			enemy._pose_parts()
			aim_target.position=enemy.weapon_part.global_position+offset
			enemy._pose_parts()
			var mouth: Vector2=enemy.weapon_part.to_global(enemy.weapon_muzzle())
			var direction: Vector2=(mouth-enemy.weapon_part.global_position).normalized()
			var expected: Vector2=enemy.abilities.launch_velocity(mouth,aim_target.global_position).normalized() if EnemyCatalog.is_vehicle(kind) and enemy.abilities.ballistic_attack() else offset.normalized()
			check(direction.dot(expected)>0.9999,"%s mirrored gun follows its actual launch path to target %s"%[kind,offset])
		check(enemy.scale==Vector2.ONE,"%s only visual parts mirror; world and text retain orientation"%kind)
		enemy.free()
	for mode: String in ["left","center","right"]:
		scenario.position_mode=mode
		for index in 2:
			var enemy:=SiegeMachine.new()
			scenario.configure_enemy(enemy,1,index)
			var expected:=1.0 if mode=="right" or (mode=="center" and index==1) else -1.0
			check(enemy.attack_direction==expected and (enemy.position.x<scenario.arena_left if expected>0 else enemy.position.x>scenario.arena_right),"%s dispatch %d uses correct ground edge"%[mode,index])
			enemy.free()
		var aircraft:=AirMachine.new()
		aircraft.game=world
		scenario.configure_enemy(aircraft,7,1)
		world.add_child(aircraft)
		aircraft.set_physics_process(false)
		var original:=aircraft.position.x
		for frame in 120: aircraft._move_flight(1.0/60.0)
		check(signf(aircraft.position.x-original)==aircraft.attack_direction,"%s aircraft physically enter toward assigned sky lane"%mode)
		var bounds:=aircraft.flight_bounds()
		aircraft.position=Vector2((bounds.x+bounds.y)*0.5,100)
		aircraft._move_flight(0.01)
		check(aircraft.entered,"%s aircraft enter and become combat-active"%mode)
		var toward_core:=Vector2(core.position.x,390)
		aircraft.locked_aim=toward_core
		aircraft.windup=0.5
		aircraft._pose_parts()
		check((aircraft.muzzle_global()-aircraft.weapon_part.global_position).normalized().dot((toward_core-aircraft.weapon_part.global_position).normalized())>0.999,"%s airborne muzzle correctly aims toward actual core"%mode)
		aircraft.free()
	scenario.position_mode="center"
	for wave in range(1,Balance.TOTAL_WAVES+1):
		var count: int=Balance.WAVE_COUNTS[wave-1]
		var roster:=EnemyCatalog.wave_roster(wave,count)
		var from_west:=false
		var from_east:=false
		for index in count:
			if AirEnemyCatalog.is_air(roster[index]): continue
			from_west=from_west or scenario.approach_direction(index)>0
			from_east=from_east or scenario.approach_direction(index)<0
		check(from_west and from_east,"Actual center roster wave %d retains ground attacks from both sides"%wave)
	for kind: String in AirEnemyCatalog.CLASS_ORDER:
		var aircraft:=AirMachine.new()
		aircraft.kind=kind
		aircraft.game=world
		scenario.configure_enemy(aircraft,20,1)
		world.add_child(aircraft)
		aircraft.set_physics_process(false)
		aircraft.position=Vector2(200,100)
		aircraft.locked_aim=Vector2(720,390)
		aircraft.windup=0.4
		aircraft._pose_parts()
		var muzzle_direction := (aircraft.muzzle_global()-aircraft.weapon_part.global_position).normalized()
		var launch_direction := Vector2.DOWN if float(aircraft.profile.gravity)>0 else (aircraft.locked_aim-aircraft.weapon_part.global_position).normalized()
		check(muzzle_direction.dot(launch_direction)>0.999,"%s left-side muzzle follows its physical gun aim or downward gravity-bomb bay"%kind)
		var bound:=aircraft.flight_bounds()
		for frame in 240: aircraft._move_flight(1.0/60.0)
		check(aircraft.position.x>=bound.x and aircraft.position.x<=bound.y,"%s remains inside actual western flight bounds"%kind)
		aircraft.free()
	var commander:=BossMachine.new()
	commander.game=world
	scenario.configure_enemy(commander,20,1)
	world.add_child(commander)
	commander.set_physics_process(false)
	commander.target=aim_target
	aim_target.position=commander.position+Vector2(300,-60)
	commander._pose_parts()
	check(commander.attack_direction>0 and commander.body_part.scale.x<0 and commander.weapon_part.to_global(commander.weapon_muzzle()).x>commander.weapon_part.global_position.x,"Final boss inherits western approach and articulated facing")
	commander.free()
	var gun:=RoofTurret.new()
	gun.game=world
	gun.position=Vector2(720,245)
	world.add_child(gun)
	gun.set_physics_process(false)
	var player:=PlayerStub.new()
	player.game=world
	world.players=[player]
	world.add_child(player)
	gun.enter(player)
	Input.action_press("p2_left")
	gun.aim_from_keys(0.1,1.1,-10,65)
	Input.action_release("p2_left")
	check(gun.facing_direction()<0,"Mounted second player switches gun left through its own InputMap action")
	Input.action_press("p1_right")
	gun.aim_from_keys(0.1,1.1,-10,65)
	Input.action_release("p1_right")
	check(gun.facing_direction()<0,"Player one movement does not steer player two's gun")
	gun.pose_barrel()
	check(gun.barrel.to_global(Vector2(60,0)).x<gun.global_position.x and gun.barrel.to_global(Vector2(0,-10)).y<gun.barrel.global_position.y,"Left gun art and muzzle face left while upper detail remains upright")
	var before_raise:=sin(gun.aim_angle)
	Input.action_press("p2_aim_up")
	gun.aim_from_keys(0.1,1.1,-10,65)
	Input.action_release("p2_aim_up")
	check(sin(gun.aim_angle)<before_raise,"Second player raises left-facing gun toward sky")
	gun.exit()
	var target:=machine(world,Vector2(485,220),1)
	var wall_left:=wall(world,Vector2(680,245))
	await physics_frame
	gun.aim_angle=-PI
	gun.cooldown=0
	gun.fire()
	check(world.get_children().filter(func(n):return n is BunkerProjectile).is_empty(),"Left-facing barrel sweep blocks actual close wall")
	wall_left.free()
	await physics_frame
	gun.cooldown=0
	gun.fire()
	for frame in 12: await physics_frame
	check(target.hp<target.max_hp,"Unobstructed roof gun's actual leftward projectile hits enemy")
	target.free()
	var flak:=FlakTurret.new()
	flak.game=world
	flak.position=Vector2(720,35)
	world.add_child(flak)
	flak.set_physics_process(false)
	var flak_aircraft:=AirMachine.new()
	flak_aircraft.game=world
	flak_aircraft.position=Vector2(280,110)
	flak_aircraft.attack_direction=1
	world.add_child(flak_aircraft)
	flak_aircraft.set_physics_process(false)
	await physics_frame
	check(flak.target_visible(flak_aircraft),"AA watch can acquire aircraft in western sky")
	var cover:=StaticBody2D.new()
	cover.collision_layer=1
	var cover_shape:=CollisionShape2D.new()
	var cover_box:=RectangleShape2D.new()
	cover_box.size=Vector2(30,220)
	cover_shape.shape=cover_box
	cover.add_child(cover_shape)
	cover.position=Vector2(500,80)
	world.add_child(cover)
	await physics_frame
	check(not flak.target_visible(flak_aircraft),"Western aircraft behind a real obstruction cannot be acquired")
	cover.free()
	await physics_frame
	flak.ammo=3
	for frame in 130: flak._watch_sky(1.0/60.0)
	check(flak.ammo<3 and cos(flak.aim_angle)<0,"AA watch rotates across sky and fires stocked rounds west")
	for frame in 25: await physics_frame
	check(flak_aircraft.hp<flak_aircraft.max_hp,"Actual AA projectile damages airborne western target")
	flak_aircraft.free()
	flak.free()
	var workshop:=FieldWorkshop.new()
	workshop.game=world
	world.add_child(workshop)
	player.position=Vector2(210,430)
	player.facing=-1
	check(workshop.placement_point(player,"jaw_trap")!=Vector2.INF,"Traps can be placed on supported left exterior")
	player.position=Vector2(1240,430)
	player.facing=1
	check(workshop.placement_point(player,"sentry_kit")!=Vector2.INF,"Sentries can be placed on supported right exterior")
	player.position=Vector2(700,430)
	check(workshop.placement_point(player,"jaw_trap")==Vector2.INF,"Exterior devices reject room interior")
	await preload("res://tests/scene_cleanup.gd").free_scene(world,self)
	print("SCENARIO COMBAT: %d/%d checks passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
