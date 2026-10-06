extends SceneTree
## Cosmetic state invariants use the real actors/art. Weather and surface probes
## isolate rain exposure from particle chance; integrated rain tests cover roofs.

class SurfaceProbe extends Node2D:
	var contacts: Array[Vector2] = []
	var drips: Array[Vector2] = []
	var floor_y := 430.0
	func surface_state_at(point: Vector2) -> Dictionary:
		return {"wetness":0.8,"mud":0.9,"material":"earth","distance":floor_y-point.y,"support_y":floor_y} if absf(point.y-floor_y)<7.0 else {}
	func footstep(point: Vector2,_strength: float,_actor: Node=null): contacts.append(point)
	func emit_drip(point: Vector2,_velocity: Vector2,_wet: float,_actor: Node=null): drips.append(point)

class WeatherProbe extends Node2D:
	var raining := true
	var rain_strength := 1.0
	var reduced_effects := false
	var surface_effects: SurfaceProbe
	func _ready():
		surface_effects=SurfaceProbe.new()
		add_child(surface_effects)
	func exposure_at(point: Vector2,_actor: Node=null) -> float:
		return 1.0 if raining and point.x>800.0 and point.y<431 else 0.0

class World extends Node2D:
	var started := false
	var weather: WeatherProbe

var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks+=1
	if value: print("PASS ",label)
	else:
		failures+=1
		push_error(label)
func stop_actor(actor: Node):
	actor.set_physics_process(false)
	for child in actor.find_children("*","Node",true,false):
		child.set_physics_process(false)
		child.set_process(false)
func step(wetness: ActorWetness,seconds: float):
	for tick in ceili(seconds*60): wetness.advance(1.0/60.0)
func run():
	InputSetup.install()
	var world := World.new()
	root.add_child(world)
	world.weather=WeatherProbe.new()
	world.add_child(world.weather)
	var worker = load("res://scenes/player.tscn").instantiate()
	worker.game=world
	worker.position=Vector2(400,430)
	world.add_child(worker)
	stop_actor(worker)
	var wet: ActorWetness=worker.wetness
	var visual: WorkerVisual=worker.get_node("PixelVisual")
	check(wet.is_in_group("weather_actors") and wet.actor==worker,"Worker registers its cosmetic rain receiver")
	worker.hide()
	check(wet.rain_segments().is_empty(),"Hidden workers never cast invisible rain collisions")
	worker.show()
	check(not wet.rain_segments().is_empty(),"Showing the worker restores its real art silhouette")
	check(visual.material is ShaderMaterial and visual.get_node("WorkerIdentity").material==null,"Only actor art receives wet shading; identity label remains unshaded")
	step(wet,15)
	check(is_zero_approx(wet.amount),"Sheltered worker remains dry during fifteen seconds of rain")
	worker.position.x=1000
	step(wet,5)
	check(wet.amount>0.30 and wet.amount<0.45,"Direct exposure gradually wets clothing instead of toggling an instant blue tint")
	step(wet,15)
	check(is_equal_approx(wet.amount,1.0) and wet.drops_emitted>0,"Prolonged exposure saturates actor and sheds real positioned drips")
	worker.position.x=400
	step(wet,10)
	check(wet.amount>0.90 and wet.amount<0.97,"Wet clothing persists indoors and dries gradually")
	var before := wet.amount
	world.weather.reduced_effects=true
	var drips := wet.drops_emitted
	step(wet,5)
	check(wet.amount<before and wet.drops_emitted==drips,"F3 suppresses droplets while wet state continues drying")
	worker.position.x=1000
	step(wet,2)
	check(wet.amount>before and wet.drops_emitted==drips,"Reduced effects retain continuous rainfall saturation")
	world.weather.reduced_effects=false
	var speed: float=worker.velocity.x
	var hp: float=worker.hp
	var capacity: int=worker.capacity()
	wet.receive_rain(INF,worker.position,Vector2.UP)
	wet.receive_rain(-1,worker.position,Vector2.UP)
	check(is_finite(wet.amount) and worker.velocity.x==speed and worker.hp==hp and worker.capacity()==capacity,"Invalid deposits are ignored and wetness never alters movement, health or cargo")
	var dry_amount: float=wet.amount
	worker.position.x=400
	step(wet,180)
	check(wet.amount<0.001 and dry_amount>0.8,"A sheltered actor eventually dries completely")
	worker.position=Vector2(1000,430)
	worker.velocity.x=100
	for cycle in 3:
		for frame in 60:
			worker.position.x+=100.0/60.0
			visual._process(1.0/60.0)
			wet.advance(1.0/60.0)
	check(wet.mud>0.15 and wet.steps_emitted>=6,"Boot contact transitions kick wet dirt in step with continuous walking")
	check(world.weather.surface_effects.contacts.all(func(point):return absf(point.y-430)<2.2),"Every foot splash is on supported ground rather than a lifted foot")
	var splashes: int=wet.steps_emitted
	worker.climbing=true
	for frame in 8:
		worker.position.y-=7
		visual._process(0.07)
		wet.advance(0.07)
		var feet := wet.feet()
		var expected: Array=visual.pose_skeleton.feet
		check(feet[0].is_equal_approx(visual.to_global(expected[0])) and feet[1].is_equal_approx(visual.to_global(expected[1])),"Climbing mud stays on continuous boot endpoints frame %d"%frame)
	check(wet.steps_emitted==splashes,"A climbing worker never produces ground footsteps")
	worker.climbing=false
	worker.velocity=Vector2.ZERO
	for pose in ["downed","rise","aid_revive","aid_bandage","helmet","boot","thoughtful","stretch"]:
		visual.special_pose=pose
		visual.pose_skeleton=WorkerPoseArt.sample(pose,0.6)
		var segments := wet.rain_segments()
		check(segments.size()>=5 and wet.feet().size()==2 and segments.all(func(segment):return Vector2(segment.from).distance_to(worker.global_position)<100 and Vector2(segment.to).distance_to(worker.global_position)<100),"%s has finite articulated rain and boot anchors"%pose)
	visual.special_pose="downed"
	visual.pose_skeleton=WorkerPoseArt.sample("downed",1)
	var lying := wet.rain_segments()
	check(lying.all(func(segment):return segment.from.y>worker.global_position.y-40),"Lying worker no longer exposes a phantom standing helmet")
	for kind in ["runner","strider","breaker","colossus","assault","siege","shield_guard","lancer","sniper","demolisher","repair_crawler","bastion"]:
		var enemy := SiegeMachine.new()
		enemy.kind=kind
		enemy.game=world
		enemy.position=Vector2(1200,430)
		world.add_child(enemy)
		stop_actor(enemy)
		var contours := enemy.wetness.rain_segments()
		check(contours.size()>5 and enemy.wetness.feet().size()==int(enemy.profile.legs),"%s uses visible animated hull and leg contours"%kind)
		enemy.free()
	for kind in AirEnemyCatalog.CLASS_ORDER:
		var air := AirMachine.new()
		air.kind=kind
		air.game=world
		air.position=Vector2(1200,130)
		world.add_child(air)
		stop_actor(air)
		check(air.wetness.rain_segments().size()>5 and air.wetness.feet().is_empty(),"%s collects hull rain without invented feet or mud splashes"%kind)
		air.free()
	check(get_nodes_in_group("weather_actors").size()==1,"Deleting machines also removes their weather receivers")
	visual.special_pose=""
	visual.pose_name="idle"
	visual.pose_frame=0
	visual.pose_skeleton={}
	wet.set_physics_process(true)
	var pause_age := wet.age
	paused=true
	await create_timer(0.06,true,false,true).timeout
	check(is_equal_approx(wet.age,pause_age),"Game pause freezes wet simulation and shimmer clock")
	paused=false
	worker.free()
	check(get_nodes_in_group("weather_actors").is_empty(),"Deleting worker clears weather registration without lingering particle nodes")
	world.free()
	print("ACTOR WETNESS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
