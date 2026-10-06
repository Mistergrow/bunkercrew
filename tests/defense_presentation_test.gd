extends SceneTree
## Prepared late-game art states: independent cabinet redraws, physically open
## aperture presentation and shallow glass returns in every bunker position.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var game
var checks := 0
var failures := 0
var cabinet_draws := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	print("DEFENSE ART ","PASS " if ok else "FAIL ",label)
	if not ok:
		failures+=1
		push_error(label)

func frames(count: int=4) -> void:
	for unused in count: await process_frame

func refresh() -> void:
	game.dome._process(0)
	await frames()

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	LocaleText.set_locale("de",false)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(2,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.rounds.set_process(false)
	game.rounds.wave=16
	game.medic.set_physics_process(false)
	for worker in game.players:
		worker.set_physics_process(false)
		worker.position=Vector2(-400,430)
		worker.focus=null
	var dome: DomeController=game.dome
	dome.unlock()
	dome.set_process(false)
	dome.console_layer.draw.connect(func(): cabinet_draws+=1)
	await refresh()
	check(dome.z_index==-3 and dome.console_layer.z_index+dome.z_index==5,"Cabinet is above room machines while glass remains behind workers")
	var stable := cabinet_draws
	for unused in 8: await refresh()
	check(cabinet_draws==stable,"Unchanged cabinet state reuses its draw commands")
	dome.frame_built=true
	await refresh()
	check(cabinet_draws>stable,"Direct replicated frame state redraws the separate cabinet")
	stable=cabinet_draws
	dome.built=true
	for pane in dome.segments:
		pane.set_frame()
		pane.glaze()
	await refresh()
	check(cabinet_draws>stable,"Direct replicated completion redraws cabinet readiness")
	stable=cabinet_draws
	dome.segments[0].hp-=15
	await refresh()
	check(cabinet_draws>stable,"Independent panel damage redraws the cabinet warning")
	stable=cabinet_draws
	dome.segments[0].hp=dome.segments[0].max_hp
	await refresh()
	check(cabinet_draws>stable,"Replicated pane repair clears the cabinet warning")
	stable=cabinet_draws
	game.players[0].position=dome.interaction_point()+Vector2(0,20)
	await refresh()
	check(cabinet_draws>stable and UiArt.world_label_visible(dome),"Approaching the floor service point reveals its contextual label")
	stable=cabinet_draws
	game.players[0].focus=dome
	await refresh()
	check(cabinet_draws>stable and not UiArt.world_label_visible(dome),"Focused console uses the existing HUD without a duplicate world label")
	stable=cabinet_draws
	LocaleText.set_locale("en",false)
	await refresh()
	check(cabinet_draws>stable,"Locale changes refresh the cabinet label")
	for mode in ["left","center","right"]:
		var left: float={"left":90.0,"center":400.0,"right":710.0}[mode]
		var specimen := DomeController.new()
		specimen.game=game
		specimen.configure_for_scenario(left,left+640,left+224)
		game.add_child(specimen)
		specimen.set_process(false)
		specimen.unlock()
		var valid := true
		var clear := true
		var grounded := true
		var unchanged := true
		for pane: DomeSegment in specimen.segments:
			if pane.curve.is_empty(): continue
			pane.update_service_port(true)
			var physics_before := pane.polygons.duplicate(true)
			var rear := pane._rear_curve()
			var shape := pane.curve.duplicate()
			var returning := rear.duplicate()
			returning.reverse()
			shape.append_array(returning)
			for piece: PackedVector2Array in pane._clip_visual_shape(shape):
				valid=valid and not Geometry2D.triangulate_polygon(piece).is_empty()
				var min_x := INF
				var max_x := -INF
				for point in piece:
					min_x=minf(min_x,point.x+pane.global_position.x)
					max_x=maxf(max_x,point.x+pane.global_position.x)
				clear=clear and (max_x<=specimen.flak_port_left+.01 or min_x>=specimen.flak_port_right-.01)
			for path: PackedVector2Array in pane._rear_paths(rear):
				for point in path:
					var x := point.x+pane.global_position.x
					clear=clear and (x<=specimen.flak_port_left+.01 or x>=specimen.flak_port_right-.01)
			for point in rear: grounded=grounded and point.y+pane.global_position.y<=245.01
			unchanged=unchanged and pane.polygons==physics_before
		check(valid,"%s perspective glass pieces form drawable polygons"%mode)
		check(clear,"%s glass returns and back rails preserve the real flak opening"%mode)
		check(grounded,"%s perspective returns meet the roof spring without sinking below it"%mode)
		check(unchanged,"%s visual depth leaves physical glass geometry unchanged"%mode)
		game.remove_child(specimen)
		specimen.free()
	LocaleText.set_locale("de",false)
	check(await Cleanup.free_scene(game,self),"Prepared fixture releases all scene resources")
	print("DEFENSE PRESENTATION: %d/%d checks passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
