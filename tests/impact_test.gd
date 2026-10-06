extends SceneTree
## Presets and global budgets, real ray contacts, one-bounce fragments, pause and cleanup.
class TestGame extends Node2D:
	var impacts: Array = []
	func sound(_kind): pass
	func on_core_destroyed(): pass
	func fx(point, color, count):
		var effect = load("res://scripts/effect.gd").new()
		effect.position = point
		effect.color = color
		effect.count = count
		add_child(effect)
	func impact(point, kind, normal=Vector2.LEFT, strength=1.0):
		impacts.append([point,kind,normal,strength])
		var burst = ImpactBurst.new()
		burst.position = point
		burst.surface_material = kind
		burst.direction = normal
		burst.power = strength
		burst.seed_value = 827
		add_child(burst)

class FakeGame extends Node:
	var calls := 0
	func fx(_point,_color,_count): calls += 1

class Machine extends StaticBody2D:
	var hp := 100.0
	func _ready():
		collision_layer = 4
		add_to_group("enemies")
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(40,60)
		shape.shape = box
		shape.position.y = -30
		add_child(shape)
	func take_damage(amount): hp -= amount

var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(condition: bool, label: String):
	checks += 1
	if condition: print("PASS ",label)
	else:
		failures += 1
		push_error(label)
func box(parent, rect: Rect2):
	var body := StaticBody2D.new()
	body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = rect.size
	shape.shape = rectangle
	body.position = rect.get_center()
	body.add_child(shape)
	parent.add_child(body)
	return body
func shoot(game, point: Vector2, handheld:=false, flavor:="rifle"):
	var bullet = load("res://scripts/worker_projectile.gd" if handheld else "res://scripts/projectile.gd").new()
	bullet.game = game
	bullet.position = point
	if handheld: bullet.flavor = flavor
	game.add_child(bullet)
	bullet._physics_process(0.2)

func run():
	var game := TestGame.new()
	root.add_child(game)
	var normal_counts := {}
	for kind in ["metal","concrete","earth","glass","flesh","explosion","arc","mining_ore","mining_limestone","mining_tungsten","mining_sand"]:
		var burst := ImpactBurst.new()
		burst.surface_material = kind
		burst.seed_value = 193
		game.add_child(burst)
		burst.set_physics_process(false)
		normal_counts[kind] = burst.bits.size()
		check(burst.bits.size()>0 and burst.bits.size()<=ImpactBurst.MAX_PARTICLES,"%s preset creates a bounded, nonempty particle set" % kind)
		check(burst.bits.all(func(bit): return bit.life<=1.65 and bit.bounces==0),"%s particles have finite lifetimes and begin without prior bounces" % kind)
		if kind=="flesh":
			check(burst.bits.size()<=10 and burst.bits.all(func(bit): return bit.type!="sparks" and bit.life<=0.4) and burst._preset.flash==0,"Injuries use only brief small red flecks/dust, without bright flash or large fragments")
		if kind=="metal":
			check(burst.bits.filter(func(bit): return bit.type=="sparks").size()>burst.bits.filter(func(bit): return bit.type=="shards").size(),"Metal emphasizes fast directional sparks")
		if kind=="earth":
			check(burst.bits.all(func(bit): return bit.type!="sparks"),"Earth produces stone and dust instead of unexplained glowing sparks")
		if kind.begins_with("mining_"):
			check(burst.bits.size()<=12 and burst._preset.flash==0 and burst.bits.all(func(bit): return bit.type!="sparks"),"%s creates local chips without combat flashes or a dense particle cloud"%kind)
			check(burst.bits.filter(func(bit): return bit.type=="shards").all(func(bit): return bit.size<=2.6 and bit.velocity.length()<160),"%s fragments stay small and close to the strike"%kind)
		burst.retire()
		var small := ImpactBurst.new()
		small.surface_material = kind
		small.reduced = true
		game.add_child(small)
		check(small.bits.size()<int(normal_counts[kind]) and small.bits.size()<=16,"Reduced effects lower %s particle count" % kind)
		small.retire()
	await process_frame
	var oldest: ImpactBurst
	for index in 110:
		var burst := ImpactBurst.new()
		burst.surface_material="explosion"
		burst.power=99
		game.add_child(burst)
		if index==0: oldest=burst
	check(get_nodes_in_group(ImpactBurst.GROUP).size()==36,"More than a hundred same-frame explosions retain at most36 active bursts")
	check(oldest.retired and not oldest.visible and oldest.is_queued_for_deletion(),"An evicted burst hides immediately before its deferred free")
	check(get_nodes_in_group(ImpactBurst.GROUP).all(func(b):return b.bits.size()<=48 and b.power<=2),"Extreme callers cannot exceed the per-burst particle or power limit")
	for index in 60: game.fx(Vector2.ZERO,Art.AMBER,1000)
	check(get_nodes_in_group(ImpactBurst.GROUP).size()==36 and get_nodes_in_group(ImpactBurst.GROUP).all(func(b):return b.bits.size()<=16),"Legacy fx calls share the same global limit and clamp excessive requested counts")
	for burst in get_nodes_in_group(ImpactBurst.GROUP): burst.retire()
	await process_frame
	var fake := FakeGame.new()
	root.add_child(fake)
	ImpactBurst.emit(fake,Vector2.ZERO,"glass")
	check(fake.calls==1,"Old test doubles without impact still receive the compatible fx fallback")
	fake.queue_free()

	var wall: DefenseWall=load("res://scenes/wall.tscn").instantiate()
	wall.game=game
	wall.initial_state=DefenseWall.State.HARD
	wall.position=Vector2(200,100)
	game.add_child(wall)
	var ore: MineBlock=load("res://scenes/mine_block.tscn").instantiate()
	ore.game=game
	ore.position=Vector2(200,250)
	game.add_child(ore)
	var machine := Machine.new()
	machine.position=Vector2(200,400)
	game.add_child(machine)
	var glass := DomeSegment.new()
	glass.game=game
	glass.configure(Vector2(200,460),Vector2(200,560),1)
	game.add_child(glass)
	glass.set_frame()
	glass.glaze()
	await physics_frame
	await physics_frame
	game.impacts.clear()
	shoot(game,Vector2(20,55))
	check(is_equal_approx(wall.hp,Balance.WALL_HP) and game.impacts.size()==1,"Roof projectiles stop on allied walls and create one contact effect without damage")
	check(game.impacts[-1][1]=="concrete" and absf(game.impacts[-1][0].x-185)<0.1 and game.impacts[-1][2].x<0,"Wall debris originates at the actual collider face and exits along its normal")
	var previous_hp: float=wall.hp
	shoot(game,Vector2(20,55),true)
	check(wall.hp==previous_hp and game.impacts[-1][1]=="concrete","Handheld rounds still stop on walls without friendly structural damage")
	shoot(game,Vector2(20,250))
	check(game.impacts[-1][1]=="earth" and not ore.depleted,"A projectile strikes real earth without turning damage into free mining")
	shoot(game,Vector2(20,370))
	check(machine.hp==100-Balance.SHOT_DAMAGE and game.impacts[-1][1]=="metal","Actual machine collider produces metal effects with unchanged damage")
	shoot(game,Vector2(20,370),true,"arcgun")
	check(game.impacts[-1][1]=="arc","The impulse weapon uses its distinct electric impact preset")
	shoot(game,Vector2(20,510))
	check(game.impacts[-1][1]=="glass" and is_equal_approx(glass.hp,glass.max_hp),"An actual allied dome pane blocks the shot without damage and selects glass")
	game.impacts.clear()
	glass.remove_meta("impact_contact_frame")
	glass.take_damage(10000)
	check(glass.stage==DomeSegment.Stage.BROKEN and game.impacts[-1][1]=="glass" and game.impacts[-1][3]>1,"Shattering a pane emits a stronger glass burst while opening its existing collider")
	game.impacts.clear()
	wall.remove_meta("impact_contact_frame")
	wall.take_damage(10000)
	check(not wall.is_blocking() and game.impacts[-1][1]=="concrete" and game.impacts[-1][3]==2,"Destroyed concrete emits extra debris without changing destruction rules")
	for burst in get_nodes_in_group(ImpactBurst.GROUP): burst.retire()
	await process_frame

	box(game,Rect2(450,640,160,20))
	box(game,Rect2(535,0,20,1000))
	await physics_frame
	await physics_frame
	var fragments := ImpactBurst.new()
	fragments.surface_material="concrete"
	fragments.direction=Vector2(1,0.45)
	fragments.position=Vector2(500,610)
	fragments.seed_value=321
	game.add_child(fragments)
	fragments.set_physics_process(false)
	for frame in 150: fragments._physics_process(0.01)
	check(fragments.collision_count>0,"Fragments use real swept collisions against floor and side wall")
	check(fragments.bits.all(func(bit):return bit.bounces<=1),"No fragment can bounce more than once")
	check(fragments.bits.all(func(bit):return bit.pos.x+500<535.1 and bit.pos.y+610<640.1),"Swept fragments remain on the near side of solid floor and wall")
	fragments._physics_process(0.2)
	check(fragments.retired and fragments.is_queued_for_deletion(),"The entire burst retires within1.65 simulated seconds")
	await process_frame
	var paused_burst := ImpactBurst.new()
	game.add_child(paused_burst)
	await physics_frame
	var before_age := paused_burst.age
	paused=true
	await create_timer(0.1,true,false,true).timeout
	check(is_equal_approx(paused_burst.age,before_age),"Pause freezes particle positions and lifetime with the game")
	paused=false
	await create_timer(1.8,true,false,true).timeout
	check(not is_instance_valid(paused_burst) and get_nodes_in_group(ImpactBurst.GROUP).is_empty(),"Unpausing resumes motion and all finished particle nodes clean up")
	game.queue_free()
	await process_frame

	var main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.weather.set_reduced_effects(true)
	for index in 40: main.impact(Vector2(500,400),"explosion",Vector2.UP,2)
	check(get_nodes_in_group(ImpactBurst.GROUP).size()<=16 and get_nodes_in_group(ImpactBurst.GROUP).all(func(b):return b.reduced and b.bits.size()<=16),"Actual game.impact obeys the existing F3 reduced-effects state and its smaller global budget")
	main.fx(Vector2(100,100),Art.CYAN,8)
	check(get_nodes_in_group(ImpactBurst.GROUP)[-1].bits.size()<=3,"Reduced mode also cuts legacy pickup/build puff counts")
	paused=false
	if not await preload("res://tests/scene_cleanup.gd").free_scene(main, self):
		failures += 1
	print("IMPACT CHECKS: %d passed, %d failed" % [checks-failures,failures])
	quit(0 if failures==0 else 1)
