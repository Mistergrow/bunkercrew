extends SceneTree
## Actual main scene, real input and finite start stock / mined ore. Worker
## positions and a single approaching runner are arranged, travel is not tested.
var game
var p1
var p2
var checks := 0
var failures := 0

func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks += 1
	print("FIELD MAIN ","PASS " if ok else "FAIL ",label)
	if not ok:
		failures += 1
		push_error(label)
func step(frames:=3):
	for i in frames: await physics_frame
func hold(action: String,seconds: float):
	Input.action_press(action)
	await create_timer(seconds,false,true).timeout
	Input.action_release(action)
	await step()
func tap(action: String):
	# Personal movement consumes physics input, recipe/deployment consume frame
	# input. Keep synthetic presses across both callbacks even under slow GL.
	await process_frame
	Input.action_press(action)
	await process_frame
	await process_frame
	await step(2)
	Input.action_release(action)
	await process_frame
	await step()
func focus(player,target,at: Vector2):
	player.position=at
	player.velocity=Vector2.ZERO
	player.preferred_focus=target
	await step()
	check(player.focus==target,"P%d focuses %s"%[player.player_id,target.name])
func supply(kind: String):
	for source in get_nodes_in_group("supplies"):
		if source.kind==kind: return source
	return null
func ore(at: Vector2):
	for block in get_nodes_in_group("mine_blocks"):
		if block.position.distance_to(at)<1: return block
	return null
func choose(player,index: int):
	game.hud.close_crafting()
	await focus(player,game.workshop,game.workshop.position)
	check(game.hud.open_crafting(player,game.workshop),"P%d opens the explicit crafting menu" % player.player_id)
	game.hud.crafting_panel._select(index)
	game.hud.crafting_panel.confirm_button.pressed.emit()
	game.hud.close_crafting()
	await step()
func collect(player,index: int,seconds: float):
	await create_timer(seconds,false,true).timeout
	await choose(player,index)
func capture(path: String):
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run():
	Engine.time_scale=3.0
	Engine.physics_ticks_per_second=180
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	game.start(2)
	game.rounds.set_process(false)
	p1=game.players[0]
	p2=game.players[1]
	var bench=game.workshop
	# Prepared first excavated legacy service floor; mining/construction is
	# covered separately. All crafting materials still come from finite crates.
	game.expansion.unlock()
	game.expansion.excavate(1)
	for site in game.expansion.modules:
		if site.kind=="ammo_press":
			for block in site.excavation.blocks.duplicate(): block.queue_free()
	await step()
	bench.refresh_access()
	var steel=supply("steel")
	check(steel.amount==6,"Integration begins with the finite six-steel start stock")
	await focus(p1,steel,Vector2(580,430))
	await hold("p1_interact",0.96)
	check(p1.inventory.get("steel",0)==3 and steel.amount==3,"Input takes three actual start-stock steel")
	await choose(p1,2)
	check(bench.recipe_index(p1)==2 and bench.recipe_index(p2)==0,"Explicit menu confirms only the focused P1 blueprint")
	await collect(p1,2,3.3)
	check(p1.progression.armor_tier==1 and p1.inventory.get("steel",0)==0,"Held E pays, crafts and equips real personal armor")
	p1.take_damage(25)
	check(is_equal_approx(p1.hp,p1.max_hp-20),"Crafted armor reduces real incoming damage by twenty percent")
	p1.position.x=350
	await focus(p2,steel,Vector2(580,430))
	await hold("p2_interact",0.66)
	check(p2.inventory.get("steel",0)==2 and steel.amount==1,"P2 draws a separate finite delivery")
	await choose(p2,0)
	await collect(p2,0,2.3)
	check(p2.inventory.get("jaw_trap",0)==1 and p1.progression.armor_tier==1,"P2 receives a paid trap while P1 keeps personal armor")
	check(game.combat_events.unlocked.has("armor"),"Real armor crafting unlocks its achievement")
	game.notify("PRÜFAUFBAU · echte Herstellung aus endlichem Startvorrat")
	await capture("res://artifacts/field-workshop-live.png")
	p2.position=Vector2(1020,430)
	p2.velocity=Vector2.ZERO
	p2.facing=1
	p2.selected_kind="jaw_trap"
	await step()
	await capture("res://artifacts/field-trap-placement-live.png")
	await tap("p2_deploy")
	check(get_nodes_in_group("field_defenses").size()==1 and p2.inventory.get("jaw_trap",0)==0,"P2 deployment input creates a real finite trap")
	check(game.combat_events.unlocked.has("trap"),"Successful paid placement unlocks the trap achievement")
	if get_nodes_in_group("field_defenses").size()!=1:
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
		quit(1)
		return
	var jaw=get_nodes_in_group("field_defenses")[0]
	p2.position=Vector2(975,430)
	await create_timer(1.1,false,true).timeout
	var enemy=load("res://scenes/enemy.tscn").instantiate()
	enemy.game=game
	enemy.kind="runner"
	enemy.position=jaw.position+Vector2(12,0)
	game.add_child(enemy)
	await step(6)
	check(p2.progression.kills==1 and p2.progression.xp>0 and p1.progression.kills==0,"Actual trap kill awards XP and kill to its builder alone")
	check(jaw.charges==2,"The real runner consumes exactly one trap charge")
	await capture("res://artifacts/field-trap-kill-live.png")
	# The remaining starting steel and real mined ore fund a gun. No inventory
	# is injected; ore is consumed by the existing furnace before steel payment.
	await focus(p1,steel,Vector2(580,430))
	await hold("p1_interact",0.4)
	await choose(p1,4)
	check(bench.recipe_index(p1)==4,"P1 chooses the crafted gun blueprint through its menu")
	check(bench.order_for(p1).materials.get("steel",0)==1 and steel.amount==0,"Partial gun payment accounts for the last starting steel")
	for position_and_worker in [[Vector2(154,776),Vector2(110,800)],[Vector2(250,776),Vector2(300,800)]]:
		var block=ore(position_and_worker[0])
		check(is_instance_valid(block) and block.kind=="ore","Accessible required ore exists in the actual mine")
		await focus(p1,block,position_and_worker[1])
		await hold("p1_interact",1.34)
	check(p1.inventory.get("ore",0)==6,"Two exposed cells yield six actual carried ore")
	var furnace
	for station in get_nodes_in_group("stations"):
		if station.kind=="furnace": furnace=station
	await focus(p1,furnace,Vector2(660,800))
	# Wait for the observable output, not the sum of nominal timers: the software
	# renderer can schedule production frames between batches of physics input.
	Input.action_press("p1_interact")
	var smelting_deadline := Time.get_ticks_msec()+20000
	while p1.inventory.get("steel",0)<6 and Time.get_ticks_msec()<smelting_deadline:
		await physics_frame
	Input.action_release("p1_interact")
	await step()
	check(p1.inventory.get("steel",0)==6 and p1.inventory.get("ore",0)==0,"Real furnace converts finite mined ore to six steel")
	await choose(p1,4)
	check(bench.order_for(p1).materials.get("steel",0)==4 and p1.inventory.get("steel",0)==3,"Gun consumes only its remaining three steel")
	var concrete=supply("concrete")
	await focus(p1,concrete,Vector2(675,600))
	await hold("p1_interact",0.66)
	check(p1.inventory.get("concrete",0)==2 and concrete.amount==6,"Gun concrete comes from finite bunker stock")
	await choose(p1,4)
	await collect(p1,4,4.3)
	check(p1.inventory.get("sentry_kit",0)==1 and p1.inventory.get("concrete",0)==0,"Completed gun is carried as a paid kit")
	p1.position=Vector2(882,430)
	p1.velocity=Vector2.ZERO
	p1.facing=1
	p1.selected_kind="sentry_kit"
	await step()
	await tap("p1_deploy")
	var gun
	for defense in get_nodes_in_group("field_defenses"):
		if defense.kind=="sentry_kit": gun=defense
	check(is_instance_valid(gun) and gun.turret.ammo==0,"Actual B input builds an empty manual field gun")
	if not is_instance_valid(gun):
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
		quit(1)
		return
	check(game.combat_events.unlocked.has("turret"),"Only successful gun placement unlocks its achievement")
	var ammo=supply("ammo")
	await focus(p1,ammo,Vector2(648,245))
	await hold("p1_interact",0.4)
	await focus(p1,gun.turret,gun.position-Vector2(32,0))
	await tap("p1_interact")
	await tap("p1_reload")
	await create_timer(1.2,false,true).timeout
	check(p1.mounted_turret==gun.turret and gun.turret.ammo==20 and ammo.amount==17,"Actual enter/reload consumes one finite ammunition box")
	game.notify("PRÜFAUFBAU · Feldgeschütz aus Erz, Stahl und Beton · Rüstung + Falle")
	await capture("res://artifacts/field-gun-live.png")
	if "--capture" in OS.get_cmdline_user_args():
		await create_timer(10.0,false,true).timeout
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	Engine.time_scale=1
	Engine.physics_ticks_per_second=60
	print("FIELD MAIN: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
