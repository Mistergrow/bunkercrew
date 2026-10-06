extends SceneTree
## Real assembled scenario, paid resources and authoritative combat events.
## Time is stepped for phase regression; this is not a human balance playtest.
var checks:=0
var failures:=0
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if ok: print("PASS ",label)
	else:
		failures+=1
		push_error(label)
func frames(count:=3):
	for frame in count:
		await physics_frame
		await process_frame
func clear_enemies(game):
	for enemy in get_nodes_in_group("enemies"):
		game.combat_hit(enemy,enemy.hp+5000,game.players[0])
	await frames()
func create_game(mode: String,count:=1):
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(count,{"environment":"sector07","build_type":"bastion","position":mode})
	game.rounds.set_process(false)
	await frames(5)
	return game
func run():
	for mode: String in ["left","center","right"]:
		var game=await create_game(mode,2 if mode=="center" else 1)
		var bunker: ScenarioBunker=game.scenario_bunker
		check(bunker.built_rooms==1 and game.players.size()==(2 if mode=="center" else 1),"%s starts actual one-room scene with correct worker count"%mode)
		var index:=0
		for gun: RoofTurret in bunker.roof_guns:
			var direction:=1.0 if gun.position.x>bunker.core_x else -1.0
			var target:=SiegeMachine.new()
			target.game=game
			target.attack_direction=-direction
			target.position=Vector2((bunker.room_right+145) if direction>0 else bunker.room_left-145,430)
			game.add_child(target)
			target.set_physics_process(false)
			await frames()
			var destination:=target.global_position-Vector2(0,40)
			var start:=gun.global_position+RoofTurret.PIVOT
			var ray:=PhysicsRayQueryParameters2D.create(start,destination,1|2|4)
			var hit: Dictionary=game.get_world_2d().direct_space_state.intersect_ray(ray)
			check(hit.get("collider")==target,"%s edge gun%d has actual free path beyond roof toward ground enemy"%[mode,index])
			gun.aim_angle=gun.clamped_aim((destination-start).angle())
			gun.cooldown=0
			var before:=target.hp
			gun.fire()
			for frame in 20: await physics_frame
			check(target.hp<before,"%s edge gun%d real projectile hits intended front"%[mode,index])
			target.free()
			index+=1
		game.rounds.begin_warning()
		check(game.rounds.phase=="warning" and ("BEIDE" in game.notice if mode=="center" else ("LINKS" in game.notice if mode=="right" else "RECHTS" in game.notice)),"%s warning states actual attack sides"%mode)
		game.rounds._process(Balance.WARNING_TIME+0.01)
		check(game.rounds.phase=="attack","%s warning enters attack"%mode)
		var total: int=game.rounds.wave_total
		for spawn in total:
			game.rounds.spawn_clock=0
			game.rounds._process(0.0)
			var enemies:=get_nodes_in_group("enemies")
			for enemy in enemies: enemy.set_physics_process(false)
		check(get_nodes_in_group("enemies").size()==total and total==ceili(Balance.WAVE_COUNTS[0]*(Balance.wave_multiplier(2) if mode=="center" else 1.0)),"%s real factory dispatches full correctly scaled wave"%mode)
		var correct:=true
		var west:=false
		var east:=false
		for enemy in get_nodes_in_group("enemies"):
			west=west or enemy.attack_direction>0
			east=east or enemy.attack_direction<0
			correct=correct and enemy.nearest_obstacle()!=null and enemy.nearest_obstacle().get_meta("scenario_front",false)
		check(correct and ((west and east) if mode=="center" else (west and not east if mode=="right" else east and not west)),"%s actual factory actors select approached physical bunker front"%mode)
		await clear_enemies(game)
		game.rounds._process(0)
		check(game.rounds.phase=="salvage" and game.stats.kills==total,"%s actual credited kills finish wave and enter salvage"%mode)
		game.rounds._process(Balance.SALVAGE_TIME+0.01)
		check(game.rounds.phase=="build" and game.rounds.wave==2 and bunker.built_rooms==1,"%s next build phase preserves one room until paid construction"%mode)
		game.rounds.wave=5
		check("BAUPLAN GLASWERK" in game.rounds._expansion_notice() and bunker.built_rooms==1,"%s milestone advertises blueprint without inventing an already built glassworks"%mode)
		game.rounds.wave=Balance.TOTAL_WAVES
		game.rounds._begin_attack()
		game.rounds.spawned=game.rounds.wave_total-1
		game.rounds.spawn_clock=0
		game.rounds._process(0)
		await frames()
		var final:=get_nodes_in_group("enemies")
		check(final.size()==1 and final[0] is BossMachine,"%s final phase spawns actual boss through scenario factory"%mode)
		await clear_enemies(game)
		game.rounds._process(0)
		check(game.rounds.phase=="victory" and game.hud.overlay=="victory" and paused,"%s final boss defeat reaches victory and pauses scene"%mode)
		paused=false
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	# Test real reload_current_scene against a scene loaded via SceneTree.
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	await process_frame
	var defeat_game=current_scene
	defeat_game.start_scenario(2,{"environment":"sector07","build_type":"workshop","position":"center"})
	defeat_game.rounds.set_process(false)
	await frames()
	defeat_game.core.take_damage(defeat_game.core.hp+1)
	check(defeat_game.rounds.phase=="defeat" and defeat_game.hud.overlay=="defeat" and paused,"Actual core destruction reaches defeat in cooperative scenario")
	defeat_game.return_to_menu()
	await process_frame
	await process_frame
	await process_frame
	var restarted=current_scene
	check(restarted!=defeat_game and not restarted.started and restarted.hud.overlay=="menu","Return to menu recreates a clean actual main menu without program restart")
	restarted.start_scenario(1,ScenarioCatalog.last_selection)
	restarted.rounds.set_process(false)
	await frames()
	check(restarted.rounds.wave==1 and restarted.rounds.phase=="build" and restarted.core.hp==restarted.core.max_hp and restarted.scenario_bunker.built_rooms==1,"Restarted selected scenario returns to full-health one-room wave one")
	paused=false
	await preload("res://tests/scene_cleanup.gd").free_scene(restarted,self)
	print("SCENARIO ROUND INTEGRATION: %d/%d checks passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
