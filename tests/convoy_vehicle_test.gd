extends SceneTree
const Vehicle := preload("res://scripts/convoy_vehicle.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks:=0
var failures:=0

class Room extends Node:
	var active:=false
	var is_host:=true
	var local_player_id:=1

class Fixture extends Node2D:
	var network: Node
	var upgrades: Node
	var players: Array=[]
	var destroyed_calls:=0
	var started:=true
	func vehicle_destroyed() -> void: destroyed_calls+=1
	func sound_at(_kind: String,_at: Vector2) -> void: pass

class Crew extends CharacterBody2D:
	var mounted_turret: Node2D
	var game: Node
	var player_id:=1
	var facing:=1.0
	var character_id: String="mara"
	var climbing:=false
	var mining:=false
	@warning_ignore("unused_private_class_variable")
	var _interacting:=false
	var inventory: Dictionary={}
	func carried_count() -> int: return 1
	func take_item(kind: String,amount: int) -> bool:
		if int(inventory.get(kind,0))<amount: return false
		inventory[kind]=int(inventory[kind])-amount
		return true
	func can_act() -> bool: return true
	func action(kind: String) -> String: return "p%d_%s"%[player_id,kind]

class Target extends StaticBody2D:
	var hp:=100.0
	func take_damage(amount: float) -> void: hp-=amount

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	print("CONVOY %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok: failures+=1

func collider(node: CollisionObject2D,size: Vector2,offset:=Vector2.ZERO) -> void:
	var child:=CollisionShape2D.new()
	var shape:=RectangleShape2D.new()
	shape.size=size
	child.shape=shape
	child.position=offset
	node.add_child(child)

func run() -> void:
	var game:=Fixture.new()
	root.add_child(game)
	var room:=Room.new()
	game.network=room
	game.add_child(room)
	var ground:=StaticBody2D.new()
	ground.collision_layer=1
	ground.position=Vector2(2000,450)
	collider(ground,Vector2(5000,40))
	game.add_child(ground)
	var vehicle:=Vehicle.new()
	vehicle.game=game
	vehicle.expedition=game
	game.add_child(vehicle)
	vehicle.set_physics_process(false)
	vehicle.configure_trip(Vector2(1000,430),Vector2(900,3300),{"hp":600.0,"fuel":12.0,"cargo":{"steel":4},"ammo":3,"reserve":0})
	for id in [1,2,3,4]:
		var crew:=Crew.new()
		crew.player_id=id
		crew.game=game
		crew.collision_layer=8
		crew.collision_mask=3
		game.add_child(crew)
		crew.position=Vector2(1000,430)
		game.players.append(crew)
		var weapon:=WorkerWeapon.new()
		weapon.name="WorkerWeapon"
		crew.add_child(weapon)
		weapon.set_physics_process(false)
	await physics_frame
	check(vehicle.hp==600 and vehicle.max_fuel==30 and vehicle.cargo_capacity==18,"600 HP, 30 litre tank, 18 cargo slots")
	check(vehicle.board(game.players[0]),"driver can board nearby recovered truck")
	check(not game.players[0].visible and game.players[0].collision_layer==0,"cab shows its seated portrait and protects real crew collision")
	check(not vehicle.board(game.players[1]),"occupied driver seat rejects second player")
	check(vehicle.board(game.players[1],"gunner"),"second player rides as passenger before MG research")
	check(not vehicle.fire(game.players[1]),"passenger seat has no free MG before research")
	check(vehicle.board_any(game.players[2]) and vehicle.board_any(game.players[3]),"four crew board without any research")
	check(vehicle.free_seat()==null and not vehicle.switch_seat(game.players[0]),"full truck neither overbooks nor silently moves another occupant")
	check(vehicle.seats.size()==4 and vehicle.passenger_left_seat.occupant==game.players[2] and vehicle.passenger_right_seat.occupant==game.players[3],"four fixed roles retain independent crew references")
	var rear: WorkerWeapon=game.players[2].get_node("WorkerWeapon")
	var front: WorkerWeapon=game.players[3].get_node("WorkerWeapon")
	check(rear.can_use() and front.can_use() and game.players[1].get_node("WorkerWeapon").can_use(),"all three passengers can defend using personal weapons, with stowed material")
	check(not game.players[0].get_node("WorkerWeapon").can_use(),"driver cannot fire a personal rifle through the cab")
	check(vehicle.dismount(game.players[2]) and vehicle.switch_seat(game.players[3]),"crew can move into a genuinely free seat")
	check(vehicle.seat_for(game.players[3])==vehicle.passenger_left_seat and vehicle.board_any(game.players[2]),"seat switch preserves occupant identity and frees old place")
	check(vehicle.passenger_left_seat.ammo==rear.current_ammo() and vehicle.passenger_right_seat.ammo==front.current_ammo(),"seat HUD reads finite personal ammunition")

	vehicle.dismount(game.players[1])
	vehicle.vehicle_upgrades=["convoy_mg"]
	vehicle.has_mg=true
	check(vehicle.board(game.players[1],"gunner"),"second player boards unlocked gunner seat")
	check(game.players[1].mounted_turret==vehicle.gunner_seat,"gunner uses established mounted controls")
	check(not vehicle.board(game.players[0],"gunner"),"one worker cannot occupy both seats")
	var before:=vehicle.position.x
	var start_fuel:=vehicle.fuel
	for unused in 150:
		await physics_frame
		vehicle.advance_motion(1.0/60.0,1)
	var distance:=vehicle.position.x-before
	check(distance>200 and distance<315,"accelerates and physically travels on ground")
	check(absf(vehicle.position.y-430)<0.15,"suspension vehicle rests on physical road")
	check(absf(start_fuel-vehicle.fuel-distance/300.0)<0.001,"fuel charged from actual distance only")
	check(vehicle.wheel_phase>10,"wheel rotation derives from travelled distance")
	vehicle.velocity=Vector2.ZERO
	start_fuel=vehicle.fuel
	for unused in 12:
		await physics_frame
		vehicle.advance_motion(1.0/60.0,0)
	check(absf(start_fuel-vehicle.fuel)<0.00001,"stationary truck does not consume travel fuel")
	vehicle.position.x=3299
	vehicle.velocity.x=125
	start_fuel=vehicle.fuel
	await physics_frame
	vehicle.advance_motion(1.0/60.0,1)
	check(vehicle.position.x==3300 and absf(start_fuel-vehicle.fuel-1.0/300)<0.001,"road end clamps position and charges only last real metre")
	vehicle.position.x=1500
	vehicle.velocity=Vector2.ZERO
	vehicle.fuel=0
	await physics_frame
	vehicle.advance_motion(1.0/60.0,1)
	check(vehicle.position.x==1500,"empty tank prevents driving")
	check(vehicle.accept_material("ore",40)==14 and vehicle.cargo_count()==18,"cargo capacity bounds actual material transfer")
	check(vehicle.accept_material("ore",1)==0 and vehicle.accept_material("unknown",1)==0,"full hold and unknown resources rejected")
	check(vehicle.take_material("ore",14) and not vehicle.take_material("ore",1),"unloading cannot duplicate missing cargo")
	check(not vehicle.take_material("steel",-1) and vehicle.accept_material("steel",-1)==0,"negative material transfers rejected")
	vehicle.take_damage(55)
	check(vehicle.hp==545,"host damage lowers hull integrity")
	vehicle.position=Vector2(1000,430)
	vehicle.velocity=Vector2.ZERO
	vehicle.aim_angle=0
	var target:=Target.new()
	target.add_to_group("enemies")
	target.collision_layer=4
	target.position=Vector2(1260,390)
	collider(target,Vector2(40,80))
	game.add_child(target)
	await physics_frame
	check(vehicle.fire(game.players[1]) and vehicle.ammo==2,"MG consumes one physical round per shot")
	check(not vehicle.fire(game.players[1]),"fire cadence blocks immediate second shot")
	for unused in 18: await physics_frame
	check(target.hp==82,"real projectile reaches and damages enemy")
	check(vehicle.hp==545,"own MG projectile clears chassis without self damage")
	for worker in [game.players[2],game.players[3]]:
		worker.facing=1
		var weapon: WorkerWeapon=worker.get_node("WorkerWeapon")
		weapon._update_origin()
		weapon.aim_direction=Vector2.RIGHT
		check(weapon.fire() and weapon.current_ammo()==29,"passenger %d fires one personal round"%worker.player_id)
	for unused in 30: await physics_frame
	check(target.hp==50 and vehicle.hp==545,"both passenger rounds leave chassis and deal real enemy damage")
	var personal_snapshot:=rear.total_ammunition()
	rear.loaded.rifle=4
	rear.reserve=7
	check(rear.start_reload(),"seated personal weapon can reload")
	rear._physics_process(1.2)
	check(rear.current_ammo()==11 and rear.reserve==0,"passenger reload conserves limited remaining rounds")
	check(personal_snapshot>rear.total_ammunition(),"personal stores remain separate from vehicle magazine")

	var cover:=StaticBody2D.new()
	cover.collision_layer=2
	cover.position=Vector2(1150,390)
	collider(cover,Vector2(20,80))
	game.add_child(cover)
	await physics_frame
	vehicle.cooldown=0
	check(vehicle.fire(game.players[1]),"covered shot still spends ammunition")
	for unused in 18: await physics_frame
	check(target.hp==50,"physical cover stops vehicle MG rounds")
	cover.queue_free()
	for unused in 2: await physics_frame
	var hostile:=HostileAirProjectile.new()
	hostile.game=game
	hostile.velocity=Vector2(-450,0)
	hostile.damage=13
	hostile.position=Vector2(1210,400)
	game.add_child(hostile)
	for unused in 25: await physics_frame
	check(vehicle.hp==532,"actual hostile ordnance hits armoured chassis")
	vehicle.ammo=0
	check(not vehicle.start_reload(),"empty reserve never creates free ammunition")
	check(vehicle.accept_material("ammo",1)==1 and vehicle.start_reload(),"one loaded ammunition crate enables reload")
	check(vehicle.reserve==20 and not vehicle.cargo.has("ammo"),"crate atomically becomes finite20-round reserve")
	vehicle._physics_process(1.5)
	check(vehicle.ammo==20 and vehicle.reserve==0,"reload transfers existing rounds only")
	var schema := preload("res://scripts/network_replication_schema.gd")
	var snapshot := {}
	for field: String in schema.fields("convoy_vehicle"): snapshot[field]=vehicle.get(field)
	check(schema.valid_state("convoy_vehicle",snapshot),"live vehicle satisfies the actual replication schema")
	var invalid := snapshot.duplicate(true)
	invalid.fuel=NAN
	check(not schema.valid_state("convoy_vehicle",invalid),"actual wire schema rejects nonfinite fuel")
	invalid=snapshot.duplicate(true)
	invalid.vehicle_upgrades=["convoy_armor_heavy"]
	check(not schema.valid_state("convoy_vehicle",invalid),"actual wire schema validates armor prerequisites")
	room.active=true
	room.is_host=false
	before=vehicle.position.x
	start_fuel=vehicle.fuel
	var previous_hp:=vehicle.hp
	vehicle.advance_motion(1.0/60,1)
	vehicle.take_damage(10)
	check(not vehicle.fire() and not vehicle.start_reload(),"client cannot simulate gunfire or reload")
	check(vehicle.accept_material("steel",1)==0 and not vehicle.take_material("steel",1),"client cannot alter cargo")
	check(vehicle.position.x==before and vehicle.fuel==start_fuel and vehicle.hp==previous_hp,"client cannot simulate driving/fuel/damage")
	check(vehicle.driver_seat.occupant==game.players[0] and vehicle.gunner_seat.occupant==game.players[1],"replica retains exact driver and gunner")
	check(vehicle.passenger_left_seat.occupant==game.players[3] and vehicle.passenger_right_seat.occupant==game.players[2],"replica retains both passenger identities")
	var personal_rounds:=front.total_ammunition()
	front.cooldown=0
	check(not front.fire() and not front.start_reload() and front.total_ammunition()==personal_rounds,"replica cannot fire or reload personal passenger weapons")
	room.active=false
	var departing=game.players[3]
	departing.queue_free()
	await process_frame
	check(vehicle.passenger_left_seat.occupant==null and vehicle.free_seat()==vehicle.passenger_left_seat,"departing crew clears its seat immediately")
	vehicle.vehicle_upgrades=CampaignCatalog.VEHICLE_UPGRADES.duplicate()
	vehicle.refresh_upgrades()
	check(vehicle.top_speed==140 and vehicle.acceleration==250 and vehicle.braking==460 and is_equal_approx(vehicle.reload_duration,1.05) and vehicle.mg_damage==21,"researched driving and weapon improvements change live stats")
	var protected_hp:=vehicle.hp
	vehicle.take_damage(100)
	check(is_equal_approx(vehicle.hp,protected_hp-85),"blast lining reduces real incoming vehicle damage by fifteen percent")
	check(vehicle.dismount(game.players[0]) and game.players[0].visible and game.players[0].collision_layer==8,"leaving cab restores visible worker and collision")
	vehicle.take_damage(10000)
	check(vehicle.destroyed and vehicle.hp==0 and game.destroyed_calls==1,"destroyed vehicle notifies campaign exactly once")
	check(game.players[1].mounted_turret==null,"destruction ejects surviving gunner")
	vehicle.take_damage(10000)
	check(game.destroyed_calls==1 and not vehicle.board(game.players[0]),"wreck neither repeats failure nor allows boarding")
	await Cleanup.free_scene(game,self)
	print("CONVOY VEHICLE: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
