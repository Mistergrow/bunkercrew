extends SceneTree
## Arranged late-wave main scene. Glass is prepared via its real pane API;
## rainfall/exposure and panel failure remain the runtime implementations.
var game
var failures:=0
var checks:=0
func _initialize(): run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	print("RAIN DOME ","PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func wait(seconds: float): await create_timer(seconds,false,true).timeout
func capture(label: String):
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/rain-dome-%s.png"%label)
func run():
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start(2)
	game.rounds.running=false
	game.rounds.wave=16
	game.set_view_stage(4)
	for pane in game.dome.segments:
		pane.set_frame()
		pane.glaze()
	game.players[0].position=Vector2(1480,430)
	game.players[1].position=Vector2(1030,430)
	var ground=game._entity("enemy",Vector2(1650,430),{"kind":"siege"})
	ground.set_physics_process(false)
	var air=game._entity("air_enemy",Vector2(1780,140),{"kind":"scout_drone"})
	air.set_physics_process(false)
	game.notify("WETTERPRÜFUNG · vorbereitete Welle 16 / verglaste Kuppel")
	await wait(12.0)
	check(game.players[0].wetness.amount>.8,"Exposed late-wave worker becomes wet")
	check(game.players[1].wetness.amount<.01,"Intact dome keeps exterior ground worker dry")
	check(ground.wetness.amount>.8 and air.wetness.amount>.8,"Expanded weather reaches far ground and airborne machines")
	check(game.weather.surface_effects.patches.size()<=SurfaceWeather.MAX_PATCHES,"Wide-view surface storage stays bounded")
	await capture("intact")
	var contact:Dictionary=game.weather.trace_rain(Vector2(1030,-400),Vector2(1030,400),false)
	check(contact.get("collider") is DomeSegment,"Actual glass is the first hit above the covered worker")
	if contact.get("collider") is DomeSegment:
		contact.collider.take_damage(100000)
	await wait(12.0)
	check(game.players[1].wetness.amount>.6,"Broken pane admits rainfall and visibly wets the sheltered worker")
	await capture("broken")
	var initial:float=game.weather.elapsed
	paused=true
	await create_timer(.3,true).timeout
	check(game.weather.elapsed==initial,"Pause freezes the new weather in the full late scene")
	paused=false
	print("RAIN DOME METRICS: contacts=%d primary=%d patches=%d"%[game.weather.contact_count,game.weather.rain.size(),game.weather.surface_effects.patches.size()])
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("RAIN DOME: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
