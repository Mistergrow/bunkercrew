extends SceneTree
## RENDERED FIXTURE: enemy/worker starting positions and carried items are set up.
## Injury and KO come from normal enemy physics. The fixture then explicitly
## ceases enemy fire and positions P2 for a normal held-input, paid revival.
## This fixture never calls take_damage or edits health, shields or KO timers.
var game
var worker
var enemy
var hurt_saved := false
var knockout_saved := false
var recovered_saved := false
var recording_pid := -1
var events: Array = []

func _initialize():
	if DisplayServer.get_name()=="headless":
		push_error("Health gallery needs a real display")
		quit(1)
		return
	call_deferred("run")

func capture(name: String):
	await RenderingServer.frame_post_draw
	var path := "res://artifacts/health-%s.png" % name
	var result := root.get_texture().get_image().save_png(path)
	print("HEALTH GALLERY ",name," image=",result," HP=",worker.hp," KO=",worker.down_time," enemy attacks=",enemy.worker_attack_count)
	events.append({"frame":Engine.get_physics_frames(),"event":name,"hp":worker.hp,"down_time":worker.down_time,"position":[worker.position.x,worker.position.y],"enemy_attacks":enemy.attack_count})

func run():
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start(2)
	if is_instance_valid(game.medic): game.medic.set_physics_process(false)
	game.rounds.running = false
	game.rounds.phase = "attack"
	game.rounds.wave = 20
	worker = game.players[0]
	worker.position = Vector2(860,430)
	worker.inventory = {"ore":2,"steel":1,"ammo":1}
	game.players[1].position = Vector2(540,430)
	var cargo_before: Dictionary = worker.inventory.duplicate(true)
	var weapon = worker.get_node("WorkerWeapon")
	var rounds_before: int = weapon.total_ammunition()
	game.notice = "TESTSZENE · Vorbereitete Positionen · Verletzungen durch echte Gegner-KI"
	game.notice_time = 3.5
	enemy = load("res://scenes/enemy.tscn").instantiate()
	enemy.kind = "siege"
	enemy.wave = 20
	enemy.elite = true
	enemy.game = game
	enemy.position = Vector2(955,430)
	game.add_child(enemy)
	await capture("before")
	recording_pid = OS.create_process("/usr/bin/ffmpeg",PackedStringArray(["-y","-loglevel","error","-f","x11grab","-video_size","1440x900","-framerate","15","-i",OS.get_environment("DISPLAY"),"-t","22","-c:v","libx264","-preset","veryfast","-crf","27","-pix_fmt","yuv420p",ProjectSettings.globalize_path("res://artifacts/health-enemy-ko-recovery.mp4")]))
	var elapsed := 0.0
	while elapsed<25.0:
		await physics_frame
		elapsed += 1.0/Engine.physics_ticks_per_second
		if not hurt_saved and worker.hp<worker.max_hp and not worker.is_downed():
			hurt_saved = true
			await capture("hit")
		if not knockout_saved and worker.is_downed():
			knockout_saved = true
			await capture("knees-buckle")
			await create_timer(0.20).timeout
			await capture("falling")
			await create_timer(0.30).timeout
			await capture("incapacitated")
			# Prepared ceasefire isolates the real medical channel from combat.
			enemy.set_physics_process(false)
			var helper = game.players[1]
			helper.position = worker.position+Vector2(36,0)
			helper.velocity = Vector2.ZERO
			helper.preferred_focus = worker.get_node("MedicalAidTarget")
			game.notice = "TESTSZENE · Feuerpause · P2 hält ENTER: Wiederbeleben mit 1 Verband"
			game.notice_time = 8.0
			await physics_frame
			Input.action_press("p2_interact")
			await create_timer(1.0).timeout
			await capture("partner-aid")
		if knockout_saved and not worker.is_downed() and not recovered_saved:
			recovered_saved = true
			Input.action_release("p2_interact")
			await capture("recovered")
			await create_timer(1.2).timeout
			await capture("standing-after-aid")
		if recovered_saved and elapsed>22.5:
			break
	Input.action_release("p2_interact")
	var passed: bool = hurt_saved and knockout_saved and recovered_saved and worker.inventory==cargo_before and weapon.total_ammunition()==rounds_before and game.players[1].medical.charges==1
	if not passed: push_error("Rendered real enemy KO / held paid partner revival did not finish with conserved cargo and ammo")
	var report := FileAccess.open("res://artifacts/health-gallery-events.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"fixture":"Prepared main-scene positions, automatic medic disabled, one real wave20 elite siege machine; after real KO enemy fire is paused and P2 positioned for held P2 interaction (Enter) revival. No direct player damage/HP/timer edits","events":events,"cargo_preserved":worker.inventory==cargo_before,"ammo_preserved":weapon.total_ammunition()==rounds_before,"helper_charges_remaining":game.players[1].medical.charges,"passed":passed},"\t"))
	print("HEALTH GALLERY COMPLETE: actual enemy injury, KO, explicit ceasefire, five-second held partner revival; passed=",passed)
	while recording_pid>0 and OS.is_process_running(recording_pid):
		await create_timer(0.2).timeout
	var released: bool = await preload("res://tests/scene_cleanup.gd").free_scene(game, self)
	quit(0 if released and passed else 1)
