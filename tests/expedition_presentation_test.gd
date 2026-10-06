extends SceneTree
## Actual journey composition, visual-only bunker isolation, depth and F3.
const Cleanup:=preload("res://tests/scene_cleanup.gd")
const Journey:=preload("res://scripts/convoy_journey.gd")
var game
var checks:=0
var failures:=0

func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2);return
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.start_scenario(2,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	game.rounds.running=false
	game.rounds.wave=20
	check(game.expedition.on_victory(),"A real wave20 victory prepares the garage")
	check(game.campaign.select_destination("harbor"),"Choose actual harbor journey")
	check(game.campaign.select_stop("harbor:fuel"),"Select a real finite roadside stop")
	check(not game.campaign.begin_journey().is_empty(),"Finite-fuel journey commits")
	game.expedition._start_road()
	game.expedition.set_physics_process(false)
	var truck=game.expedition.vehicle
	truck.set_physics_process(false)
	Journey.change_phase(truck.journey_state,"driving")
	truck.position.x=2000
	truck.velocity.x=80
	truck.sync_replica()
	game.player_camera.update_view(0,true)
	var roads: Array=game.get_children().filter(func(node):return node.get_script()!=null and node.get_script().resource_path=="res://scripts/expedition_road_art.gd")
	check(roads.size()==1,"Exactly one road presentation owns the journey")
	var road=roads[0]
	road._sync_travel_view()
	check(not game.scenery.visible and not game.scenario_bunker.visible and not game.core.visible,"Journey excludes the defended bunker painting")
	check(game.core.is_inside_tree() and game.core.hp>0,"Presentation keeps authoritative bunker nodes alive")
	check(truck.visible and game.players.all(func(worker):return worker.is_inside_tree()),"Vehicle and actual crew remain present")
	check(road.get_children().filter(func(node):return node is Sprite2D).size()==8,"Eight roadside facilities remain distinct from depth plates")
	check(road.depth.layers.size()==3 and road.depth._ground_layer!=null,"Three painted depths and shallow road section fill the journey")
	var before: Array=[]
	road.depth._update_view()
	for index in 3: before.append(road.depth.layers[index].position.x-game.camera.position.x)
	game.camera.position.x+=70
	game.camera.force_update_scroll()
	road.depth._update_view()
	for index in 3:
		check(road.depth.layers[index].position.x-game.camera.position.x!=before[index],"Camera motion separates painted depth "+str(index))
	game.weather.set_reduced_effects(true)
	var elapsed: float=road.elapsed
	road._process(.1)
	check(road.elapsed==elapsed,"F3 freezes roadside cloth clock")
	for child in road.get_children():
		if child is Sprite2D: check(child.material.get_shader_parameter("motion_gain")==0,"F3 disables facility sway without removing its silhouette")
	game.weather.set_reduced_effects(false)
	road._process(.1)
	check(road.elapsed>elapsed,"Ordinary weather resumes facilities")
	game.campaign.expedition.stage="preparation"
	road._sync_travel_view()
	check(game.scenery.visible and game.scenario_bunker.visible and game.core.visible,"Returning to bunker restores its original visibility")
	game.campaign.expedition.stage="travel"
	road._sync_travel_view()
	road._exit_tree()
	check(game.scenery.visible and game.scenario_bunker.visible and game.core.visible,"Road teardown also restores original visibility")
	await Cleanup.free_scene(game,self)
	print("EXPEDITION PRESENTATION: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
