extends SceneTree
const World=preload("res://scripts/network_world.gd")
var checks:=0
var failures:=0
func _initialize(): run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	print("ENTITY ID %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)
func run():
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(1,{"position":"left","environment":"sector07","build_type":"workshop"})
	paused=true
	var first=World.new()
	first.bind(game)
	var old=game._entity("enemy",Vector2(1400,430),{"kind":"strider"})
	var gone_id: String=first._id(old)
	old.queue_free()
	await process_frame
	var rebound=World.new()
	rebound.bind(game)
	var survivor=game._entity("enemy",Vector2(1450,430),{"kind":"strider"})
	var survivor_id: String=rebound._id(survivor)
	check(survivor_id!=gone_id,"Rebinding an empty field does not reuse a recently removed actor's ID")
	var inserted=game._entity("enemy",Vector2(1500,430),{"kind":"strider"})
	game.move_child(inserted,0)
	var third=World.new()
	third.bind(game)
	check(third._id(survivor)==survivor_id and third._id(inserted)!=survivor_id,"New nodes before retained nodes cannot collide with existing IDs")
	var shot=game._entity("projectile",Vector2(1500,400))
	check(third._id(shot)!=third._id(inserted) and third._id(shot)!=gone_id,"New projectiles also reserve distinct monotone IDs")
	var snapshot: Dictionary=third.capture()
	check(third._validate(snapshot),"Rebound actors and projectiles form a valid complete graph: "+third.last_error)
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Rebind regression releases the scene")
	print("ENTITY IDS: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
