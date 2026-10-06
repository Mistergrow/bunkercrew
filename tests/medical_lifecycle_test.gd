extends SceneTree
## Medical state must pause with the world and disappear on an ordinary restart.
var failures := 0
var checks := 0
func _initialize(): run.call_deferred()
func check(value: bool,label: String):
	checks += 1
	print("MEDICAL LIFECYCLE ","PASS " if value else "FAIL ",label)
	if not value: failures += 1
func run():
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start(2)
	game.rounds.running = false
	var patient = game.players[0]
	var helper = game.players[1]
	patient.position = Vector2(330,430)
	helper.position = Vector2(360,430)
	await create_timer(0.2).timeout
	patient.take_damage(44,Vector2.RIGHT)
	await create_timer(0.4).timeout
	helper.preferred_focus = patient.get_node("MedicalAidTarget")
	Input.action_press("p2_interact")
	await create_timer(0.8).timeout
	check(is_instance_valid(helper.medical.aid_target),"Ordinary input starts care before lifecycle checks")
	paused = true
	var hp_before: float = patient.hp
	var progress_before: float = helper.medical.aid_progress
	var medic_before: Vector2 = game.medic.position
	await create_timer(0.4,true).timeout
	check(is_equal_approx(patient.hp,hp_before),"Pause freezes bleeding")
	check(is_equal_approx(helper.medical.aid_progress,progress_before),"Pause freezes treatment progress")
	check(game.medic.position==medic_before,"Pause freezes AI movement")
	Input.action_release("p2_interact")
	var old_patient: WeakRef = weakref(patient)
	var old_medic: WeakRef = weakref(game.medic)
	game.restart()
	for frame in 5: await process_frame
	game = current_scene
	check(not is_instance_valid(old_patient.get_ref()) and not is_instance_valid(old_medic.get_ref()),"Restart frees the old casualty and rescue unit")
	check(get_nodes_in_group("medics").size()==1 and game.players.size()==2,"Restart recreates the rescue unit and the original two-worker party")
	var fresh = game.players[0]
	check(fresh.hp==fresh.max_hp and fresh.medical.charges==2 and fresh.medical.state=="healthy","Restart restores a clean new-round medical state")
	check(not is_instance_valid(fresh.medical.aid_target) and fresh.medical.aid_progress==0,"Restart retains no dangling treatment channel")
	check(not paused and game.hud.overlay=="" and game.started and game.rounds.wave==1,"Restart begins a playable first wave with the original party")
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("MEDICAL LIFECYCLE: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
