extends SceneTree
## Prepared wounds and starting positions in the actual main scene. Treatment,
## cancellation, supplies and revival use ordinary InputMap controls and physics.
var game
var patient
var helper
var checks := 0
var failures := 0
var recording_pid := -1
func _initialize(): run.call_deferred()
func check(value: bool,label: String):
	checks += 1
	print("MEDICAL INPUT ","PASS " if value else "FAIL ",label)
	if not value: failures += 1
func wait(seconds: float): await create_timer(seconds,false,true).timeout
func capture(label: String):
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/medical-%s.png" % label)
func start_help():
	# Walk to the actual body after knockback; never teleport a helper into reach.
	var direction: String = "p2_left" if helper.position.x>patient.position.x else "p2_right"
	Input.action_press(direction)
	for index in 120:
		await physics_frame
		if absf(helper.position.x-patient.position.x)<32: break
	Input.action_release(direction)
	await wait(0.2)
	helper.preferred_focus = patient.get_node("MedicalAidTarget")
	await wait(0.1)
	Input.action_press("p2_interact")
func end_help():
	Input.action_release("p2_interact")
	await wait(0.3)
func run():
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start(2)
	game.rounds.running = false
	game.notice_time = 0.0
	patient = game.players[0]
	helper = game.players[1]
	patient.position = Vector2(355,430)
	helper.position = Vector2(397,430)
	await wait(0.2)
	var cargo: Dictionary = patient.inventory.duplicate(true)
	var ammo: int = patient.get_node("WorkerWeapon").total_ammunition()
	var xp: float = helper.progression.xp
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		recording_pid = OS.create_process("/usr/bin/ffmpeg",PackedStringArray(["-y","-loglevel","error","-f","x11grab","-video_size","1440x900","-framerate","20","-i",OS.get_environment("DISPLAY"),"-t","31","-c:v","libx264","-preset","veryfast","-crf","22","-pix_fmt","yuv420p",ProjectSettings.globalize_path("res://artifacts/medical-coop-input.mp4")]))
	game.notify("PRÜFSZENE · vorbereiteter Treffer · P2 behandelt über gehaltene Interaktion")
	patient.take_damage(46,Vector2.ZERO)
	await wait(0.5)
	check(patient.medical.bleeding>0 and patient.medical.fractured,"Heavy fixture hit causes bleeding and fracture")
	await capture("wounded")
	await start_help()
	await wait(0.9)
	await capture("bandaging")
	check(is_instance_valid(helper.medical.aid_target),"Held P2 interaction selects the nearby patient")
	await end_help()
	check(helper.medical.charges==2 and patient.medical.bleeding>0,"Interrupted treatment spends no dressing")
	await start_help()
	await wait(2.6)
	await end_help()
	check(helper.medical.charges==1 and patient.medical.bleeding==0 and not patient.medical.fractured,"Completed help binds the wound and splints the leg for one charge")
	await capture("treated")
	patient.invulnerability = 0.0
	patient.take_damage(200,Vector2.ZERO)
	await wait(1.1)
	check(patient.is_downed(),"Second prepared hit knocks the patient down")
	var body_position: Vector2 = patient.position
	await capture("downed")
	await start_help()
	await wait(2.3)
	await capture("reviving")
	await wait(2.9)
	await end_help()
	check(not patient.is_downed() and helper.medical.charges==0,"Five-second held input revives the body in place")
	await capture("rising")
	await wait(1.3)
	check(patient.inventory==cargo and patient.get_node("WorkerWeapon").total_ammunition()==ammo and helper.progression.xp==xp,"Aid preserves cargo/ammunition and grants no farmable XP")
	check(patient.position.distance_to(body_position)<2,"Recovery stays at the body's location")
	# Explicitly arranged critical state and replenished fixture helper for the
	# longer animation. Gameplay timing/real core refill have separate tests.
	helper.medical.charges = 1
	patient.invulnerability = 0.0
	patient.take_damage(200,Vector2.ZERO)
	patient.medical.critical_remaining = 0.05
	await wait(1.1)
	check(patient.medical.state=="critical","Expired downed time enters persistent critical state")
	game.notify("PRÜFSZENE · kritisch: acht Sekunden ununterbrochene Wiederbelebung")
	await start_help()
	await wait(4.0)
	await capture("resuscitating")
	check(patient.is_downed(),"Critical casualty remains down after four seconds")
	await wait(4.3)
	await end_help()
	check(not patient.is_downed() and helper.medical.charges==0,"Critical revival also consumes exactly one charge")
	await capture("recovered")
	if recording_pid>0:
		while OS.is_process_running(recording_pid): await wait(0.25)
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("MEDICAL INPUT: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
