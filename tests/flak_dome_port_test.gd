extends SceneTree
## Arrange late construction; assert real glass collision before and after a
## separately paid flak tower. No ray mask exemptions are allowed for weapons.
var game
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PORT ","PASS " if ok else "FAIL ",label)
	if not ok:
		failures += 1
		push_error(label)

func frames(n := 4) -> void:
	for i in n:
		await physics_frame
		await process_frame

func ray_at(x: float) -> Dictionary:
	return game.get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(Vector2(x,50),Vector2(x,105),2))

func run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start()
	game.rounds.set_process(false)
	game.rounds.wave=16
	game.set_view_stage(4)
	for pane in game.dome.segments:
		pane.set_frame()
		pane.glaze()
	await frames()
	check(not ray_at(530).is_empty(),"Unbuilt flak leaves the complete dome roof physically sealed")
	var station=game.flak_station
	station.unlock()
	var worker=game.players[0]
	worker.inventory.clear()
	for kind in {"steel":3,"concrete":2,"ammo":1}:
		worker.add_item(kind,{"steel":3,"concrete":2,"ammo":1}[kind])
	for i in 30: station.interact(worker,0.3)
	await frames()
	check(station.built and worker.inventory.is_empty(),"Six exact cargo units pay for the tower and its first ammunition")
	check(game.dome.flak_port_active and ray_at(530).is_empty(),"Paid mast has a real open passage through the existing dome")
	check(not ray_at(460).is_empty() and not ray_at(610).is_empty(),"Adjacent glass stays collidable on both sides of the mast")
	check(is_inf(game.dome.cover_height(530)) and not is_inf(game.dome.cover_height(460)),"Weather cover follows the actual aperture polygons")
	check(game.weather.rain_surface(530)==35,"Flak platform shields the access shaft from rain")
	var valid_geometry:=true
	for pane in game.dome.segments:
		for polygon in pane.polygons:
			valid_geometry=valid_geometry and not Geometry2D.triangulate_polygon(polygon).is_empty()
	check(valid_geometry,"All clipped collision and drawing polygons remain triangulable")
	var target=load("res://scenes/air_enemy.tscn").instantiate()
	target.game=game
	target.kind="gunship"
	target.position=Vector2(1450,145)
	game.add_child(target)
	target.set_physics_process(false)
	station.turret.autonomous=false
	await frames()
	var from: Vector2=station.turret.global_position+RoofTurret.PIVOT
	var aim=(target.global_position-from).angle()
	station.turret.aim_angle=aim
	var hp: float=target.hp
	check(station.turret.fire(),"Flak can fire from its raised platform above the glass shell")
	await create_timer(1.4).timeout
	check(target.hp<hp,"A real flak projectile reaches an aircraft outside the dome")
	check(game.get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(Vector2(530,150),Vector2(1450,145),2)).get("collider") is DomeSegment,"A lower forbidden firing line is still blocked by glass")
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("FLAK DOME PORT: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
