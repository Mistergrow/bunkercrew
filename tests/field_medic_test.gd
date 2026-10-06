extends SceneTree
## Real main-scene medic physics and shared health API. Patient positions,
## damage and late construction deliveries are arranged fixtures; SAN-1 itself
## receives no teleports, synthetic channel time or route shortcuts.
var game
var p1
var medic
var checks:=0
var failures:=0
var largest_step:=0.0
var saw_climb:=false
var saw_jump:=false
var last_position:=Vector2.ZERO
var capture_enabled:=false
func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks+=1
	print("MEDIC ","PASS " if value else "FAIL ",label)
	if not value:
		failures+=1
		push_error(label)
func frames(count:=3):
	for i in count: await physics_frame
func watch():
	if not is_instance_valid(medic): return
	largest_step=maxf(largest_step,medic.position.distance_to(last_position))
	last_position=medic.position
	saw_climb=saw_climb or medic.climbing
	saw_jump=saw_jump or (not medic.climbing and medic.velocity.y< -100)
func wait_until(condition: Callable,seconds: float) -> bool:
	var elapsed:=0.0
	while not condition.call() and elapsed<seconds:
		await physics_frame
		elapsed+=game.get_physics_process_delta_time()
	return bool(condition.call())
func wait_seconds(seconds: float):
	await wait_until(func():return false,seconds)
func fresh(player,point: Vector2):
	player.medical.interrupt()
	player.medical.bleeding=0
	player.medical.fractured=false
	player.medical.state="healthy"
	player.medical.recovery_time=0
	player.medical.recovery_kind=""
	player.hp=player.max_hp
	player.invulnerability=0
	player.hurt_stun=0
	player.down_time=0
	player.knockback=0
	player.velocity=Vector2.ZERO
	player.climbing=false
	player.collision_mask=1
	player.since_hit=99
	player.position=point
func wound(player,amount:=12.0):
	player.invulnerability=0
	player.take_damage(amount)
	player.knockback=0
	player.velocity=Vector2.ZERO
func wait_home_full() -> bool:
	return await wait_until(func():return medic.medical_supplies==2 and medic.position.distance_to(Vector2(205,430))<12,35)
func capture(name: String):
	if not capture_enabled or DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/"+name)
func rescue_floor(point: Vector2,label: String,downed:=false):
	fresh(p1,point)
	await frames()
	var prior:int=medic.treatments_completed
	var supplies:int=medic.medical_supplies
	var xp:float=p1.progression.xp
	var cargo:Dictionary=p1.inventory.duplicate(true)
	wound(p1,1000.0 if downed else 12.0)
	var patient_position:Vector2=p1.position
	check(await wait_until(func():return medic.treating and medic.target==p1,30),label+": physical assistant reaches patient")
	check(medic.global_position.distance_to(p1.global_position)<=48 and p1.medical.reachable_can_aid(medic),label+": treatment begins only in clear reachable range")
	if label=="bunker floor":
		var paused_position:Vector2=medic.position
		var paused_progress:float=p1.medical.progress_for(medic)
		paused=true
		await create_timer(.3,true,false,true).timeout
		check(medic.position==paused_position and p1.medical.progress_for(medic)==paused_progress,"Pause freezes physical AI travel and its shared medical channel")
		paused=false
	await capture("medic-"+label.replace(" ","-")+"-live.png")
	check(await wait_until(func():return medic.treatments_completed>prior,12),label+": real timed aid completes")
	check(medic.medical_supplies==supplies-1 and p1.progression.xp==xp and p1.inventory==cargo,label+": one charge, unchanged XP and cargo")
	if downed:
		check(not p1.is_downed() and p1.position.distance_to(patient_position)<2,label+": patient revives where they fell")
	else:
		check(p1.hp==p1.max_hp,label+": minor wound fully restored")
	fresh(p1,p1.position)
	check(await wait_home_full(),label+": assistant returns physically and restocks at core")

func run():
	capture_enabled=OS.get_cmdline_user_args().has("--capture")
	Engine.time_scale=3.0
	Engine.physics_ticks_per_second=180
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	game.start(1)
	game.rounds.set_process(false)
	p1=game.players[0]
	medic=game.medic
	last_position=medic.position
	physics_frame.connect(watch)
	await frames()
	check(medic.medical_supplies==2 and medic.is_in_group("medics") and not medic.is_in_group("players"),"Separate finite rescue unit is present in the actual main scene")
	await rescue_floor(Vector2(550,430),"bunker floor")
	await rescue_floor(Vector2(455,245),"roof")
	await rescue_floor(Vector2(650,800),"mine")
	await rescue_floor(Vector2(885,656),"ore ledge")
	check(saw_jump,"The rescue assistant uses a real ballistic jump to reach an exposed ore ledge")
	# Construct actual late routes through their paid public interaction methods.
	game.rounds.wave=6
	game._round_phase_changed()
	fresh(p1,Vector2(515,430))
	p1.inventory={"steel":3,"concrete":2,"ammo":1}
	for i in 6: game.flak_station.interact(p1,.31)
	game.flak_station.interact(p1,2.6)
	check(game.flak_station.built and p1.carried_count()==0,"AA route fixture is built by consuming its complete recipe")
	await frames()
	await rescue_floor(Vector2(570,35),"flak platform")
	fresh(p1,Vector2(530,35))
	p1.preferred_focus=game.flak_station.turret
	await frames()
	Input.action_press("p1_interact")
	await frames()
	Input.action_release("p1_interact")
	await frames()
	check(p1.mounted_turret==game.flak_station.turret,"Mounted rescue fixture uses the real gun entry")
	wound(p1,1000)
	check(p1.mounted_turret==null and p1.position.x<504,"Actual gun knockout exits onto the free platform beside its physical hull")
	var mounted_prior:int=medic.revives_completed
	check(await wait_until(func():return medic.revives_completed>mounted_prior,30),"SAN-1 climbs to and revives a real knocked-out flak operator")
	fresh(p1,p1.position)
	await wait_home_full()
	game.set_view_stage(3)
	for depth in [1,2]:
		var site=null
		for candidate in get_nodes_in_group("excavation_sites"):
			if candidate.depth==depth: site=candidate
		check(is_instance_valid(site),"Depth %d has an actual paid excavation site"%depth)
		if not is_instance_valid(site): continue
		fresh(p1,site.position)
		p1.inventory=site.cost().duplicate(true)
		for i in 4: site.interact(p1,.31)
		site.interact(p1,3.1)
		await frames()
		check(game.expansion.open_depths==depth and p1.carried_count()==0,"Depth %d consumes structural recipe before creating floor and ladder"%depth)
		await rescue_floor(Vector2(365,800+depth*220),"depth %d"%depth,depth==2)
	check(saw_climb and largest_step<14,"Every level is reached by bounded physical steps and actual ladder climbing")
	# A layer-1 obstruction blocks the floor and treatment rays. No hidden rescue
	# occurs until the real blocker is removed and the route is planned again.
	fresh(p1,Vector2(655,800))
	var barrier=game.add_terrain(Rect2(605,620,20,180))
	await frames()
	wound(p1)
	var count:int=medic.treatments_completed
	await wait_seconds(8)
	check(medic.treatments_completed==count and p1.hp<p1.max_hp and medic.status_label.contains("blockiert"),"Undug solid obstruction reports a blocked route and prevents remote healing")
	barrier.queue_free()
	await frames()
	check(await wait_until(func():return medic.treatments_completed>count,22),"Removing the physical obstruction triggers route retry and successful aid")
	fresh(p1,p1.position)
	await wait_home_full()
	# Critical remains rescuable. No automatic respawn or charge-free recovery.
	fresh(p1,Vector2(550,430))
	wound(p1,1000)
	p1.medical.critical_remaining=.01
	await frames()
	check(p1.medical.state=="critical","Prepared critical patient remains on the real bunker floor")
	count=medic.revives_completed
	check(await wait_until(func():return medic.treating,12),"Critical patient is reached physically")
	await wait_seconds(4)
	check(p1.is_downed() and medic.revives_completed==count,"Critical resuscitation does not complete after only four seconds")
	await capture("medic-critical-live.png")
	check(await wait_until(func():return medic.revives_completed>count,8) and not p1.is_downed(),"Critical resuscitation completes using the longer shared treatment channel")
	fresh(p1,p1.position)
	await wait_home_full()
	# Both charge consumption and restocking happen in real time at the core.
	medic.medical_supplies=0
	await wait_seconds(5)
	check(medic.medical_supplies==0,"Empty assistant cannot refill a six-second charge in five seconds")
	check(await wait_until(func():return medic.medical_supplies==1,2),"Exactly one charge appears after the actual core restock interval")
	await wait_home_full()
	medic.medical_supplies=0
	game.core.take_damage(1)
	await wait_seconds(6)
	check(medic.medical_supplies==0,"A real core hit postpones the six-second medical refill until combat has quieted")
	check(await wait_until(func():return medic.medical_supplies==1,5),"The core resumes bounded one-charge restocking after its combat delay")
	await wait_home_full()
	game.join_coop()
	var p2=game.players[1]
	fresh(p1,Vector2(465,430))
	fresh(p2,Vector2(540,430))
	wound(p2,1000)
	count=medic.revives_completed
	await wait_seconds(7)
	check(p2.is_downed() and medic.revives_completed==count and medic.status_label.contains("Koop"),"One standing coop player keeps the rescue assistant on standby")
	wound(p1,1000)
	check(await wait_until(func():return medic.revives_completed>count,18),"When both humans are down the assistant performs one emergency rescue")
	var standing:int=int(not p1.is_downed())+int(not p2.is_downed())
	await wait_seconds(7)
	check(standing==1 and medic.revives_completed==count+1 and (p1.is_downed() or p2.is_downed()),"After one rescue the surviving human regains responsibility for coop aid")
	check(largest_step<14,"No route or emergency case teleported the rescue assistant (largest step %.2f px)"%largest_step)
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("MEDIC CHECKS: ",checks-failures," passed / ",failures," failed")
	quit(1 if failures else 0)
