extends SceneTree
const Damage := preload("res://scripts/scenery_damage.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
var game: FixtureGame
var props: FixtureProps
var reactions: Node
var seed_states: Dictionary

class FixtureNetwork extends Node:
	var active := false
	var is_host := false
class FixtureWeather extends Node:
	var rain_strength := 0.0
	var covered := false
	var reduced_effects := false
	func exposure_at(_point: Vector2) -> float: return 0.0 if covered else 1.0
class FixtureGame extends Node2D:
	var network: Node
	var weather: Node
	var scenery: Node
	func sound(_kind: String) -> void: pass
	func impact(_at: Vector2,_material: String,_normal: Vector2,_power: float) -> void: pass
	func combat_hit(victim: Node,power: float,_worker: Node) -> void: victim.take_damage(power)
class FixtureProps extends Node2D:
	var game: Node
	var entries: Array[Dictionary] = []
	var elapsed := 1.75
	@warning_ignore("unused_private_class_variable") # Read by the real damage controller.
	var _motion_scale := 1.0
	@warning_ignore("unused_private_class_variable")
	var _gust_strength := 1.2
	@warning_ignore("unused_private_class_variable")
	var _profile := {"wind":1.1}
class Target extends StaticBody2D:
	var hp := 500.0
	func take_damage(power: float) -> void: hp -= power

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("SCENERY DAMAGE %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok:
		failures += 1
		push_error(label)

func entry(kind: String,x: float,state: String = "intact") -> void:
	props.entries.append({"index":props.entries.size(),"kind":kind,"position":Vector2(x,200),"size":Vector2(110,150),"initial_state":state})

func reset_states() -> void:
	reactions.states = seed_states.duplicate(true)
	game.network.active = false
	game.weather.rain_strength = 0.0
	game.weather.covered = false
	reactions.replica_only = false
	reactions._rain_exposure.clear()

func wall(at: Vector2,size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = at
	body.collision_layer = 1
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	game.add_child(body)
	return body

func shot(script_path: String,at: Vector2) -> Node2D:
	var round_node: Node2D = load(script_path).new()
	round_node.game = game
	round_node.position = at
	round_node.damage = 12.0
	if round_node is HostileAirProjectile: round_node.velocity = Vector2(1000,0)
	else:
		round_node.speed = 1000.0
		round_node.direction = Vector2.RIGHT
	round_node.process_mode = Node.PROCESS_MODE_DISABLED
	game.add_child(round_node)
	return round_node

func run() -> void:
	game = FixtureGame.new()
	game.network = FixtureNetwork.new()
	game.weather = FixtureWeather.new()
	game.add_child(game.network)
	game.add_child(game.weather)
	props = FixtureProps.new()
	props.game = game
	entry("tree",100)
	entry("tree",200)
	entry("fan",350)
	entry("cable",500)
	entry("rubble",650)
	entry("tree",800,"broken")
	entry("tree",1000,"burning")
	for kind in ["grass","frost_grass","brush","reeds","vines","windsock","tape","pipe","signal","ore_cart","bollard"]:
		entry(kind,1200+float(props.entries.size()-7)*150)
	game.add_child(props)
	reactions = Damage.new()
	reactions.props = props
	props.add_child(reactions)
	root.add_child(game)
	current_scene = game
	reactions.set_process(false)
	seed_states = reactions.states.duplicate(true)
	await physics_frame
	check(Damage.valid_states(reactions.states,props.entries),"Initial bounded state passes wire validation")
	check(reactions.state_for(4).is_empty() and reactions.state_for(5).broken,"Rubble has no damage target; broken seed is settled")
	check(reactions.state_for(6).burning and reactions.state_for(6).charred,"Authored burning tree starts finite fire")
	for index in range(7,props.entries.size()):
		var aim: Vector2 = reactions.target_point(index)
		check(aim.is_finite() and reactions.trace_damage(aim-Vector2(8,0),aim+Vector2(8,0),5,"rifle",{})==1,"Authored %s segment reacts at its current material position"%props.entries[index].kind)
	var visited := {}
	check(reactions.trace_damage(Vector2(20,150),Vector2(130,150),12.0,"rifle",visited)==1,"Visible trunk accepts swept contact")
	check(reactions.trace_damage(Vector2(99,150),Vector2(110,150),12.0,"rifle",visited)==0 and reactions.state_for(0).hp==60.0,"Projectile visited set prevents repeated trunk damage")
	check(reactions.trace_damage(Vector2(20,80),Vector2(130,80),12.0,"rifle",{})==0,"Empty image area above trunk does not catch shots")
	check(reactions.trace_damage(Vector2(468,160),Vector2(532,160),12.0,"rifle",{})==0,"Open span between cable posts stays transparent")
	check(reactions.trace_damage(Vector2(460,160),Vector2(468,160),12.0,"rifle",{})==1,"Cable support has narrow hittable geometry")
	# Aim at the same rounded wire vertices PropArt draws. Distinct rates and
	# stiffness must move damage with the wire, including reduced-effects sway.
	for settings: Vector3 in [Vector3(.73,.95,1),Vector3(1.36,2.1,1),Vector3(1.36,2.1,.24)]:
		var cable: Dictionary = props.entries[3]
		cable.wind_rate = settings.x
		cable.stiffness = settings.y
		props._motion_scale = settings.z
		props._gust_strength = 1.5
		for time: float in [2.1,8.4,17.0]:
			props.elapsed = time
			await physics_frame
			var clock := time*settings.x
			var gust := Damage.PropArt.wind(clock,0.0,settings.z*1.1*1.5/settings.y)
			var wire_x := -39.0+70.0*.5
			var wire_y := -95.0+(18+gust*3)+sin(clock*1.8+2.0)*absf(gust)*1.7
			var visible_point: Vector2 = Vector2(cable.position)+Vector2(wire_x,wire_y).round()
			check(reactions.trace_damage(visible_point-Vector2(.1,0),visible_point+Vector2(.1,0),.1,"rifle",{})==1,"Cable contact follows drawn rate %.2f / stiffness %.2f / motion %.2f at %.1fs"%[settings.x,settings.y,settings.z,time])
	props.elapsed = 1.75
	props._motion_scale = 1.0
	props._gust_strength = 1.2
	check(not reactions.damage_entry(5,20,"fire") and reactions.state_for(5).serial==0,"Destroyed objects cannot emit another hit or reignite")
	check(not reactions.damage_entry(0,NAN,"fire") and not reactions.damage_entry(0,-10,"fire"),"Invalid and negative damage cannot mutate state")
	reset_states()
	var blocker := wall(Vector2(70,150),Vector2(10,90))
	await physics_frame
	check(reactions.trace_damage(Vector2(20,150),Vector2(250,150),12.0,"rifle",{})==0,"Public trace clips at the first physical wall")
	check(Damage.explosion(game,Vector2(20,150),150,80)==0,"Explosion cannot break trunks through a wall")
	blocker.queue_free()
	await physics_frame
	await physics_frame
	check(Damage.explosion(game,Vector2(20,150),150,80)==1,"Uncovered explosion reaches nearby actual trunk")
	check(reactions.state_for(0).burning and not reactions.state_for(1).burning,"Explosion range affects only nearby material")
	reset_states()
	check(reactions.damage_entry(2,12,"arcgun") and not reactions.state_for(2).burning,"Metal takes arc damage without igniting")
	reactions.damage_entry(0,8,"arcgun")
	for tick in 33: reactions._process(.25)
	check(reactions.state_for(0).broken and not reactions.state_for(0).burning and reactions.state_for(0).burn_left==0.0,"Dry fire consumes finite fuel and ends as a broken charred object")
	check(reactions.state_for(0).serial==2 and reactions.state_for(6).serial==1,"Fire emits exactly one destruction serial, including simultaneous fuel exhaustion")
	check(reactions.state_for(6).broken and not reactions.state_for(6).burning,"Authored ash fire also expires instead of burning forever")
	reset_states()
	game.weather.rain_strength = 1.0
	reactions.damage_entry(0,8,"fire")
	for tick in 12: reactions._process(.25)
	check(not reactions.state_for(0).burning and not reactions.state_for(0).broken and reactions.state_for(0).charred,"Exposed rain extinguishes early and preserves burn scars")
	check(reactions.state_for(0).serial==1,"Rain extinguishing cannot create a false hit serial or impact burst")
	reset_states()
	game.weather.rain_strength = 1.0
	game.weather.covered = true
	reactions.damage_entry(0,8,"fire")
	for tick in 12: reactions._process(.25)
	check(reactions.state_for(0).burning,"Roof shelter prevents rain extinguishing a covered fire")
	var full_weather: Node = game.weather
	var minimal_weather := Node.new()
	game.add_child(minimal_weather)
	game.weather = minimal_weather
	var before_fuel: float = reactions.state_for(0).burn_left
	reactions._process(.25)
	check(is_equal_approx(before_fuel-reactions.state_for(0).burn_left,.25),"Minimal weather without rain_strength safely behaves as dry weather")
	game.weather = full_weather
	minimal_weather.queue_free()
	var saved: Dictionary = reactions.states.duplicate(true)
	paused = true
	reactions._process(1.0)
	reactions.damage_entry(0,20,"rifle")
	check(reactions.states==saved,"Pause freezes burn clocks and rejects new damage")
	paused = false
	game.weather.reduced_effects = true
	reactions._process(.25)
	check(reactions.state_for(0).burn_left<saved[0].burn_left,"F3 changes only presentation; host fire still advances")
	game.network.active = true
	game.network.is_host = false
	saved = reactions.states.duplicate(true)
	reactions.damage_entry(1,100,"fire")
	reactions._process(2.0)
	check(reactions.states==saved,"Connected client cannot damage or advance fire even via direct calls")
	game.network.is_host = true
	check(reactions.damage_entry(1,5,"rifle"),"Host remains the authority in online play")
	reactions.replica_only = true
	check(not reactions.damage_entry(1,5,"rifle"),"Snapshot replica remains read-only independently of session flags")
	for script_path in ["res://scripts/worker_projectile.gd","res://scripts/projectile.gd","res://scripts/flak_projectile.gd","res://scripts/hostile_air_projectile.gd"]:
		reset_states()
		var round_node := shot(script_path,Vector2(20,150))
		round_node._physics_process(.082)
		round_node._physics_process(.003)
		check(reactions.state_for(0).hp==60.0 and round_node.position.x>100,"%s actually crosses trunk once without changing projectile travel"%script_path.get_file())
		round_node.queue_free()
		reset_states()
		round_node = shot(script_path,Vector2(20,80))
		round_node._physics_process(.12)
		check(reactions.state_for(0).hp==72.0,"%s misses transparent sprite area"%script_path.get_file())
		round_node.queue_free()
		blocker = wall(Vector2(70,150),Vector2(10,90))
		await physics_frame
		round_node = shot(script_path,Vector2(20,150))
		round_node._physics_process(.24)
		check(reactions.state_for(0).hp==72.0 and reactions.state_for(1).hp==72.0 and round_node.is_queued_for_deletion(),"%s stops at wall and cannot damage scenery behind it"%script_path.get_file())
		blocker.queue_free()
		await physics_frame
		await physics_frame
	reset_states()
	var machine: SiegeMachine = load("res://scenes/enemy.tscn").instantiate()
	machine.game = game
	machine.process_mode = Node.PROCESS_MODE_DISABLED
	game.add_child(machine)
	machine.weapon_part.global_position = Vector2(20,150)
	var victim := Target.new()
	victim.position = Vector2(240,150)
	game.add_child(victim)
	check(machine._fire_collision_shot(victim.position,victim,12.0) and reactions.state_for(0).hp==60.0 and reactions.state_for(1).hp==60.0,"Actual ground enemy ray damages the scenery crossed by its shot")
	reset_states()
	blocker = wall(Vector2(70,150),Vector2(10,90))
	await physics_frame
	check(not machine._fire_collision_shot(victim.position,victim,12.0) and reactions.state_for(0).hp==72.0,"Blocked ground enemy attack cannot damage scenery through cover")
	print("SCENERY DAMAGE: %d/%d checks passed"%[checks-failures,checks])
	await Cleanup.free_scene(game,self)
	quit(1 if failures else 0)
