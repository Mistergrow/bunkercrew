extends SceneTree
## Exercises actual menu buttons, scene replacement and independently controlled workers.
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
		await process_frame
		await physics_frame
func run():
	var entries:=ScenarioCatalog.environments()
	check(entries.size()==9,"Original sector plus eight complete selectable environments")
	var signatures: Dictionary={}
	for index in entries.size():
		var entry: Dictionary=entries[index]
		var tex:=ScenarioCatalog.texture(entry.path)
		check(tex!=null and tex.get_width()>=1600 and tex.get_height()>=900,"%s has full-size imported panorama"%entry.id)
		var digest:=FileAccess.get_sha256(entry.path)
		check(not signatures.has(digest),"%s is a distinct image, not a duplicated background"%entry.id)
		signatures[digest]=true
		var game=load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene=game
		await frames()
		var event:=InputEventAction.new()
		event.action="join" if index%2==1 else "start"
		event.pressed=true
		game.hud._unhandled_input(event)
		await frames()
		check(game.hud.overlay=="scenario" and not game.started and paused,"Start first opens setup without starting a wave")
		var panel: ScenarioSelectPanel=game.hud.scenario_panel
		panel.cards[index].pressed.emit()
		panel.cards[9+index%3].pressed.emit()
		panel.cards[12+index%3].pressed.emit()
		panel.next_button.pressed.emit()
		await frames()
		check(game.hud.overlay=="characters" and game.hud.selection_count==(2 if index%2==1 else 1),"Actual setup buttons preserve solo/coop into character selection")
		game.hud.character_panel.back_button.pressed.emit()
		await frames()
		check(game.hud.overlay=="scenario" and game.hud.scenario_panel.options.environment==entry.id,"Back preserves chosen environment")
		game.hud.scenario_panel.next_button.pressed.emit()
		await frames()
		game.hud.character_panel.cards[2].pressed.emit()
		game.hud.character_panel.begin_button.pressed.emit()
		game.rounds.set_process(false)
		await frames(6)
		check(game.started and not paused and game.hud.overlay.is_empty(),"Actual Begin starts the selected scenario")
		check(game.scenery is ScenarioScenery and game.scenery.panorama.texture==ScenarioCatalog.texture(str(entry.get("city_path",entry.path))) and game.scenario_options.environment==entry.id,"Selected scene uses its actual imported panorama")
		check(game.scenario_bunker.built_rooms==1 and game.scenario_bunker.room_left==[90.0,400.0,710.0][index%3],"Selection relocates real one-room bunker")
		check(get_nodes_in_group("stations").size()==2 and get_nodes_in_group("supplies").size()==5,"Legacy scene removed: exactly two initial production machines and five crates")
		check(game.core.max_hp==(570.0 if index%3==0 else 450.0),"Bastion core benefit is applied once")
		check(game.players[0].character_id=="ivo","Selected worker identity reaches actual player")
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
			game.notice=""
			game.notice_time=0
			game.camera.position=game.camera_target_center
			game.camera.zoom=Vector2.ONE*game.camera_target_zoom
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/scenario-scene-%s.png"%entry.id)
		if game.players.size()==2:
			var first: Vector2=game.players[0].position
			var second: Vector2=game.players[1].position
			Input.action_press("p1_right")
			await frames(12)
			Input.action_release("p1_right")
			check(game.players[0].position.x>first.x+5 and absf(game.players[1].position.x-second.x)<1,"P1 movement leaves P2 still in relocated cooperative scene")
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	check(ScenarioCatalog.validate({"environment":"missing","build_type":"missing","position":"missing"})=={"environment":"sector07","build_type":"bastion","position":"left"},"Unknown setup values resolve to playable defaults")
	print("SCENARIO SELECTION: %d/%d checks passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
