extends SceneTree
## Rendered main-scene inspection with prepared positions and stopped waves.
## Weather, saturation, drying, footsteps and player motion run normally.
var game
var checks := 0
var failures := 0
var recording_pid := -1

func _initialize(): run.call_deferred()

func check(ok: bool, label: String):
	checks += 1
	print("RAIN LIVE ", "PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func wait(seconds: float): await create_timer(seconds, false, true).timeout

func capture(label: String):
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/rain-%s.png" % label)

func walk(worker, target: float):
	var action: String = "p%d_%s" % [worker.player_id,"right" if target>worker.position.x else "left"]
	var start: float = worker.position.x
	Input.action_press(action)
	for frame in 480:
		await physics_frame
		if (worker.position.x-target)*(start-target)<=0.0: break
	Input.action_release(action)
	await wait(0.2)
	check(absf(worker.position.x-target)<12.0,"P%d reaches %.0f through normal movement" % [worker.player_id,target])

func run():
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	game.start(2)
	game.rounds.running=false
	game.notice_time=0.0
	var exposed=game.players[0]
	var sheltered=game.players[1]
	exposed.position=Vector2(570,245)
	sheltered.position=Vector2(500,430)
	var machine=game._entity("enemy",Vector2(1270,430),{"kind":"strider"})
	machine.set_physics_process(false)
	var aircraft=game._entity("air_enemy",Vector2(1200,160),{"kind":"scout_drone"})
	aircraft.set_physics_process(false)
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		recording_pid=OS.create_process("/usr/bin/ffmpeg",PackedStringArray(["-y","-loglevel","error","-f","x11grab","-video_size","1440x900","-framerate","20","-i",OS.get_environment("DISPLAY"),"-t","42","-c:v","libx264","-preset","veryfast","-crf","20","-pix_fmt","yuv420p",ProjectSettings.globalize_path("res://artifacts/rain-live.mp4")]))
	game.notify("WETTERPRÜFUNG · vorbereitete Positionen · P1 draußen / P2 unter dem Dach")
	await wait(12.0)
	check(exposed.wetness.amount>0.8,"Exposed worker becomes visibly wet from actual rain")
	check(sheltered.wetness.amount<0.01,"Bunker roof keeps the sheltered worker dry")
	check(machine.wetness.amount>0.8 and aircraft.wetness.amount>0.8,"Ground and airborne machines become wet")
	check(game.weather.contact_count>150,"Moving rain generates real contacts during the rendered scene")
	await capture("roof-and-machines")
	await walk(exposed,465)
	check(exposed.wetness.steps_emitted>0,"Walking the wet roof produces foot contact splashes")
	await walk(sheltered,1120)
	await wait(2.0)
	await walk(sheltered,990)
	await capture("mud-and-footsteps")
	check(sheltered.wetness.mud>0.02 and sheltered.wetness.steps_emitted>0,"Real steps on rainy exterior soil dirty boots and displace water")
	await walk(sheltered,690)
	await wait(0.3)
	var before: float=sheltered.wetness.amount
	var drips: int=sheltered.wetness.drops_emitted
	await wait(3.0)
	check(sheltered.wetness.exposure==0.0 and sheltered.wetness.amount<before,"Returning through the front into shelter starts gradual drying")
	check(sheltered.wetness.drops_emitted>drips,"Wet clothing keeps dripping briefly inside shelter")
	await capture("returning-to-shelter")
	var event:=InputEventKey.new()
	event.physical_keycode=KEY_F3
	event.pressed=true
	Input.parse_input_event(event)
	await wait(0.3)
	check(game.weather.reduced_effects,"Real F3 input switches to reduced weather")
	var wet_before: float=exposed.wetness.amount
	await wait(0.5)
	check(exposed.wetness.amount>=wet_before,"Reduced visuals preserve exposure state")
	await capture("reduced-effects")
	event=InputEventKey.new()
	event.physical_keycode=KEY_F3
	event.pressed=false
	Input.parse_input_event(event)
	await wait(0.1)
	event=InputEventKey.new()
	event.physical_keycode=KEY_F3
	event.pressed=true
	Input.parse_input_event(event)
	await wait(0.2)
	check(not game.weather.reduced_effects,"Second F3 input restores rain")
	print("RAIN LIVE METRICS: contacts=%d patches=%d P1wet=%.3f P2wet=%.3f P2mud=%.3f steps=%d" % [game.weather.contact_count,game.weather.surface_effects.patches.size(),exposed.wetness.amount,sheltered.wetness.amount,sheltered.wetness.mud,sheltered.wetness.steps_emitted])
	if recording_pid>0:
		while OS.is_process_running(recording_pid): await wait(0.25)
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("RAIN LIVE: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
