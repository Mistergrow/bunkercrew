extends SceneTree
## Regression for a nonmounted bleed collapse inside a service-plane hull.
## All settling uses Worker.move_and_slide, with strict unchanged medical rays.
class Observer extends Node2D:
	var medical_supplies:=2
	func can_act(): return true
var game
var player
var checks:=0
var failures:=0
var largest_step:=0.0
var last_position:=Vector2.ZERO
func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks+=1
	print("COLLAPSE ","PASS " if value else "FAIL ",label)
	if not value:
		failures+=1
		push_error(label)
func frames(count:=3):
	for i in count: await physics_frame
func wait_until(condition: Callable,seconds: float) -> bool:
	var elapsed:=0.0
	while not condition.call() and elapsed<seconds:
		await physics_frame
		elapsed+=game.get_physics_process_delta_time()
	return bool(condition.call())
func watch():
	if is_instance_valid(player):
		largest_step=maxf(largest_step,player.position.distance_to(last_position))
		last_position=player.position
func reset_at(point: Vector2):
	player.medical.interrupt()
	player.medical.state="healthy"
	player.medical.bleeding=0
	player.medical.fractured=false
	player.medical.recovery_time=0
	player.medical.recovery_kind=""
	player.hp=player.max_hp
	player.invulnerability=0
	player.hurt_stun=0
	player.down_time=0
	player.knockback=0
	player.velocity=Vector2.ZERO
	player.climbing=false
	player.position=point
	player._safe_collapse.reset()
	last_position=point
	largest_step=0
func hull(point: Vector2,size: Vector2) -> StaticBody2D:
	var body:=StaticBody2D.new()
	body.collision_layer=2
	body.position=point
	body.add_to_group("walls")
	var collider:=CollisionShape2D.new()
	var box:=RectangleShape2D.new()
	box.size=size
	collider.shape=box
	collider.position=Vector2(0,-size.y*.5)
	body.add_child(collider)
	game.add_child(body)
	return body
func run():
	Engine.time_scale=2
	Engine.physics_ticks_per_second=120
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	game.start(1)
	game.rounds.set_process(false)
	player=game.players[0]
	game.rounds.wave=6
	game._round_phase_changed()
	player.inventory={"steel":3,"concrete":2,"ammo":1}
	for i in 6: game.flak_station.interact(player,.31)
	game.flak_station.interact(player,2.6)
	await frames()
	check(game.flak_station.built and player.carried_count()==0,"Regression uses a real paid flak hull and supported platform")
	reset_at(Vector2(530,35))
	await frames()
	var observer:=Observer.new()
	observer.position=Vector2(500,35)
	game.add_child(observer)
	player.hp=1
	player.medical.bleeding=3
	check(not player.medical.reachable_can_aid(observer),"Strict medical rays still reject a nearby patient enclosed by the hull")
	physics_frame.connect(watch)
	check(await wait_until(func():return player.is_downed(),2),"An actual bleed tick causes a nonmounted knockout inside the gun")
	check(player.position.distance_to(Vector2(530,35))<4 and player._safe_collapse.destination!=Vector2.INF,"KO plans a supported flank without instant relocation")
	check(await wait_until(func():return player._safe_collapse.destination==Vector2.INF,2),"Physical collapse settles onto the nearest clear flank")
	var settled:Vector2=player.position
	check(settled.x<504 and absf(settled.y-35)<2 and settled.distance_to(Vector2(530,35))<=48,"The body stays on the same platform and inside the 48-pixel bound")
	check(largest_step<=2.1,"All settling movement is physically stepped at no more than 90px/s")
	observer.position=Vector2(480,35)
	check(player.medical.reachable_can_aid(observer),"The settled body has a genuinely clear medical ray")
	check(await wait_until(func():return game.medic.revives_completed==1,30),"SAN-1 walks and climbs to revive the enclosed operator after physical settling")
	check(not player.is_downed() and player.position.distance_to(settled)<2 and game.medic.medical_supplies==1,"Revival consumes one charge at the settled position")
	# Terrain blocks both short exits; collapse must not pass through it.
	game.medic.set_physics_process(false)
	reset_at(Vector2(665,430))
	var left=game.add_terrain(Rect2(627,370,23,60))
	var right=game.add_terrain(Rect2(680,370,23,60))
	await frames()
	player.hp=0
	player._begin_knockout()
	await frames(45)
	check(player._safe_collapse.destination==Vector2.INF and absf(player.position.x-665)<1,"Solid terrain on both sides prevents a collapse escape through walls")
	left.queue_free()
	right.queue_free()
	# A wide hull has no eligible flank within 48 pixels, so no remote relocation.
	reset_at(Vector2(350,430))
	var wide=hull(Vector2(350,430),Vector2(180,65))
	await frames()
	player.hp=0
	player._begin_knockout()
	await frames(45)
	check(absf(player.position.x-350)<1 and player._safe_collapse.destination==Vector2.INF,"A hull wider than the local bound cannot teleport a body to a distant edge")
	wide.queue_free()
	# Dome panes share the crew's passable service plane. A bleed collapse in a
	# thin glass support must settle outside it without disabling that pane.
	var pane := DomeSegment.new()
	pane.configure(Vector2(950,350),Vector2(950,430),0)
	game.add_child(pane)
	pane.set_frame()
	pane.glaze()
	reset_at(Vector2(950,430))
	await frames()
	player.hp=0
	player._begin_knockout()
	await frames(45)
	check(absf(player.position.x-950)>18 and absf(player.position.y-430)<2,"A casualty also settles clear of a glazed dome support on the same floor")
	observer.position=player.position-Vector2(24,0)
	check(pane.is_blocking() and player.medical.reachable_can_aid(observer),"Dome glass remains physically intact while its casualty becomes reachable")
	pane.queue_free()
	# A tiny supported platform cannot be exchanged for a lateral fall.
	var small_floor=game.add_terrain(Rect2(1988,430,24,20))
	var small_hull=hull(Vector2(2000,430),Vector2(52,40))
	await frames()
	reset_at(Vector2(2000,430))
	player.hp=0
	player._begin_knockout()
	await frames(45)
	check(absf(player.position.x-2000)<1 and absf(player.position.y-430)<2,"Unsupported hull flanks are rejected instead of pushing the body off its platform")
	small_floor.queue_free()
	small_hull.queue_free()
	# An ordinary open-floor KO preserves its location and existing behavior.
	reset_at(Vector2(450,600))
	player.hp=0
	player._begin_knockout()
	await frames(45)
	check(absf(player.position.x-450)<1 and player._safe_collapse.destination==Vector2.INF,"Open-floor knockouts receive no artificial settling motion")
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("COLLAPSE CHECKS: ",checks-failures," passed / ",failures," failed")
	quit(1 if failures else 0)
