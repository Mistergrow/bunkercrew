extends SceneTree
## Actual main scene and InputMap. Wave gates/positions are arranged; initial
## tower construction consumes finite original stock. Late dome materials are
## explicitly supplied for an access regression, not a campaign playthrough.
var game
var p1
var p2
var checks:=0
var failures:=0
func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks+=1
	print("FLAK ACCESS ","PASS " if value else "FAIL ",label)
	if not value:
		failures+=1
		push_error(label)
func frames(count:=3):
	for i in count: await physics_frame
func hold(action: String,seconds: float):
	Input.action_press(action)
	await create_timer(seconds,false,true).timeout
	Input.action_release(action)
	await frames()
func tap(action: String):
	Input.action_press(action)
	await frames(3)
	await process_frame
	Input.action_release(action)
	await frames()
func focus(player,target,at: Vector2):
	player.position=at
	player.velocity=Vector2.ZERO
	player.preferred_focus=target
	await frames()
	check(player.focus==target,"P%d can select %s"%[player.player_id,target.name])
func source(kind: String):
	for node in get_nodes_in_group("supplies"):
		if node.kind==kind: return node
	return null
func capture(path: String):
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func wait_for_feedback():
	# Keep the actual game UI, but let transient achievement plates expire before
	# taking a geometry screenshot of the small tower directly behind them.
	var deadline:=Time.get_ticks_msec()+10000
	while not game.hud.combat_overlay.banners.is_empty() and Time.get_ticks_msec()<deadline:
		await process_frame
func walk_to(player,x: float):
	var action: String=player.action("right" if player.position.x<x else "left")
	var sign_direction:=signf(x-player.position.x)
	Input.action_press(action)
	for i in 220:
		await physics_frame
		if (x-player.position.x)*sign_direction<3: break
	Input.action_release(action)
	await frames()
func late_materials(player,kind: String,amount: int):
	check(player.add_item(kind,amount)==amount,"Prepared late fixture cargo fits ordinary carrying capacity")

func run():
	Engine.time_scale=2.0
	Engine.physics_ticks_per_second=120
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	game.start(2)
	game.rounds.set_process(false)
	p1=game.players[0]
	p2=game.players[1]
	var station=game.flak_station
	check(not station.available and not station.built,"Starting bunker does not contain a free AA gun")
	game.rounds.wave=6
	game.rounds.phase="build"
	game._round_phase_changed()
	check(station.available and game.view_stage==2,"Wave-six construction pause reveals the reachable flak console")
	for row in [["steel",3,Vector2(580,430),0.96],["concrete",2,Vector2(675,600),0.66],["ammo",1,Vector2(648,245),0.4]]:
		var stock=source(row[0])
		var before: int=stock.amount
		await focus(p1,stock,row[2])
		await hold("p1_interact",row[3])
		check(p1.inventory.get(row[0],0)==row[1] and stock.amount==before-row[1],"Tower %s comes from finite bunker stock"%row[0])
	await focus(p1,station,Vector2(515,430))
	await hold("p1_interact",4.8)
	check(station.built and station.turret.ammo==20 and p1.carried_count()==0,"Actual held interaction constructs a paid tower with twenty commissioned rounds")
	if not station.built:
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
		quit(1)
		return
	var gun=station.turret
	await walk_to(p1,530)
	await hold("p1_up",2.75)
	check(absf(p1.position.y-35)<2 and not p1.climbing and p1.collision_mask==1,"P1 climbs continuously from bunker floor through roof to the real platform")
	check(absf(p2.position.y-430)<2 and p2.mounted_turret==null,"P1 ladder input leaves the second worker on the bunker floor")
	await tap("p1_interact")
	check(gun.occupant==p1 and p1.mounted_turret==gun,"The accessible elevated flak can be entered through ordinary input")
	await tap("p1_craft_next")
	check(not gun.autonomous,"Focused G explicitly disables automatic watch")
	await tap("p1_craft_next")
	check(gun.autonomous,"Focused G explicitly restores finite automatic watch")
	await tap("p1_interact")
	check(p1.mounted_turret==null and absf(p1.position.y-35)<3,"Exiting the gun lands on the platform instead of falling off its edge")
	await walk_to(p1,530)
	await hold("p1_down",2.75)
	check(absf(p1.position.y-430)<2,"The same ladder returns the player safely to the bunker interior")
	p1.position.x=465
	p2.position=Vector2(530,430)
	p2.velocity=Vector2.ZERO
	await frames()
	await hold("p2_up",2.75)
	await tap("p2_interact")
	check(gun.occupant==p2 and p1.mounted_turret==null,"The second player's own keys independently climb and occupy the AA gun")
	var old_angle: float=gun.aim_angle
	await hold("p2_aim_down" if old_angle<0 else "p2_aim_up",0.18)
	check(absf(gun.aim_angle-old_angle)>0.1,"Second-player aiming changes the actual weapon articulation")
	await tap("p2_interact")
	await walk_to(p2,530)
	await hold("p2_down",2.75)
	p2.position.x=465
	var aircraft=load("res://scenes/air_enemy.tscn").instantiate()
	aircraft.game=game
	aircraft.wave=7
	aircraft.kind="scout_drone"
	aircraft.position=Vector2(1160,95)
	game.add_child(aircraft)
	var before_ammo: int=gun.ammo
	var deadline:=Time.get_ticks_msec()+12000
	while p1.progression.kills==0 and Time.get_ticks_msec()<deadline:
		await physics_frame
	check(p1.progression.kills==1 and p1.progression.xp>0 and p2.progression.kills==0,"Automatic flak destroys a real moving aircraft and credits its actual builder")
	check(gun.ammo<before_ammo and gun.ammo>=before_ammo-5,"Air defense spends real finite ammunition on its moving target")
	await wait_for_feedback()
	game.notify("PRÜFAUFBAU WELLE 6 · FLAK aus endlichem Stahl, Beton und einer Munitionskiste")
	await capture("res://artifacts/flak-tower-access-live.png")
	# Late dome access has prepared material deliveries. All build methods and
	# physical hulls are the actual game objects; paid flak ammunition is retained.
	game.rounds.wave=16
	game._round_phase_changed()
	game.upgrades.owned["bunker_fortress"]=true
	game.dome.unlock()
	for row in [["steel",4],["alloy",4]]:
		late_materials(p1,row[0],row[1])
		for i in row[1]: game.dome.interact(p1,0.31)
	game.dome.interact(p1,1.3)
	for batch in 2:
		late_materials(p1,"glass",6)
		for i in 6: game.dome.interact(p1,0.31)
	game.dome.interact(p1,2.1)
	check(game.dome.built and p1.carried_count()==0,"Prepared late materials are consumed by the actual dome build")
	await frames(8)
	check(game.dome.flak_port_active,"A built flak mast opens the real dome service port")
	p1.position=Vector2(530,430)
	p1.velocity=Vector2.ZERO
	await frames()
	await hold("p1_up",2.75)
	check(absf(p1.position.y-35)<2 and not p1.climbing,"The late glass dome leaves the full flak service ladder usable")
	var ray:=PhysicsRayQueryParameters2D.create(Vector2(530,90),Vector2(530,49),2)
	check(game.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(),"The ladder crosses an actual opening rather than an intact glass collider")
	var side_ray:=PhysicsRayQueryParameters2D.create(Vector2(595,90),Vector2(595,49),2)
	check(not game.get_world_2d().direct_space_state.intersect_ray(side_ray).is_empty(),"Neighboring dome glass remains physically closed")
	var screen: Vector2=game.get_canvas_transform()*gun.global_position
	check(screen.y>112 and screen.y<760,"The flak platform is visible between the main HUD panels")
	game.notify("PRÜFAUFBAU WELLE 16 · geschlossene Kuppel mit echter Wartungsöffnung zum Flakturm")
	await capture("res://artifacts/flak-dome-access-live.png")
	if "--capture" in OS.get_cmdline_user_args():
		await create_timer(6.0,false,true).timeout
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	Engine.time_scale=1
	Engine.physics_ticks_per_second=60
	print("FLAK ACCESS: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
