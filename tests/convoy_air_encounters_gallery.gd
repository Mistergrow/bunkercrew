extends SceneTree
## Native prepared road plates, with only the replicated vehicle presentation
## clock fixed for captures. This is art/timing evidence, not a live playthrough.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Flybys := preload("res://scripts/convoy_air_encounters.gd")
const Catalog := preload("res://scripts/convoy_air_encounter_catalog.gd")
const OUTPUT := "res://artifacts/convoy-experience-20261004/air/"
var game
var truck
var flybys: Node2D
var view: SubViewport
var captures: Array[Dictionary] = []
var checks := 0
var failures := 0
var foreground_pixels := 0
var video_frames := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func frames(count: int=3) -> void:
	for unused in count: await process_frame

func draw_state(route: String,phase: float,reduced: bool=false,resolution: Vector2i=Vector2i(1920,1080)) -> void:
	view.size=resolution
	game.expedition.state.pending_node=route
	game.expedition.stop_done=false
	game.weather.reduced_effects=reduced
	var spec: Dictionary=Catalog.DEFINITIONS[Catalog.ROUTES[route]]
	truck.animation_time=Catalog.FIRST_AT+float(spec.duration)*phase
	game.camera.position=Vector2(1750,280)
	game.camera.zoom=Vector2.ONE*1.7
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	for child in game.get_children():
		if child.get_script()!=null and child.get_script().resource_path=="res://scripts/expedition_road_art.gd":
			child.depth._update_view()
			child.queue_redraw()
	flybys.update_state(0)
	await frames()

func capture(id: String,route: String,phase: float,reduced: bool=false,resolution: Vector2i=Vector2i(1920,1080)) -> void:
	await draw_state(route,phase,reduced,resolution)
	await RenderingServer.frame_post_draw
	var picture:=view.get_texture().get_image()
	check(picture.get_size()==resolution and picture.save_png(OUTPUT+id+".png")==OK,"Native route flyby "+id)
	var stats: Dictionary=flybys.diagnostics()
	check(stats.visible_aircraft>0 and stats.visible_aircraft<=2 and stats.playing_motors>0 and stats.playing_motors<=2,"Visible authored aircraft and actual motor sources "+id)
	captures.append({"id":id,"file":id+".png","route":route,"phase":phase,"reduced":reduced,"resolution":[resolution.x,resolution.y],"diagnostics":stats})
	if id=="survey-mid":
		flybys.cloud_nodes[1].hide()
		await frames()
		await RenderingServer.frame_post_draw
		var clear:=view.get_texture().get_image()
		var plane: Node2D=flybys.aircraft[0]
		var hull: Vector2=plane.profile.body_size
		var transform: Transform2D=plane.get_global_transform_with_canvas()
		var a: Vector2=transform*(-hull*.5)
		var b: Vector2=transform*(hull*.5)
		for y in range(maxi(0,floori(minf(a.y,b.y))),mini(resolution.y,ceili(maxf(a.y,b.y)))):
			for x in range(maxi(0,floori(minf(a.x,b.x))),mini(resolution.x,ceili(maxf(a.x,b.x)))):
				if picture.get_pixel(x,y)!=clear.get_pixel(x,y): foreground_pixels+=1
		check(foreground_pixels>100,"Foreground cloud actually alters native framebuffer pixels over the visible aircraft hull bounds")
		check(clear.save_png(OUTPUT+"survey-without-front-cloud.png")==OK,"Native same-frame cloud comparison")
		flybys.cloud_nodes[1].show()

func _run() -> void:
	var args:=OS.get_cmdline_user_args()
	if "--no-profile-save" not in args or "--capture" not in args or DisplayServer.get_name()=="headless": quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	AudioServer.set_bus_mute(0,true)
	view=SubViewport.new()
	view.size=Vector2i(1920,1080)
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	AudioServer.set_bus_mute(0,true)
	game.start_scenario(2,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.audio.persistence_enabled=false
	game.campaign.persistence_enabled=false
	game.expedition.state.pending_node="harbor"
	game.expedition.state.expedition.stage="travel"
	game.expedition.ensure_road()
	for unused in 3: await physics_frame
	freeze(game)
	game.hud.hide()
	truck=load("res://scenes/convoy_vehicle.tscn").instantiate()
	truck.game=game
	truck.expedition=game.expedition
	game.add_child(truck)
	truck.configure_trip(Vector2(1750,430),Vector2(740,3700),{"hp":600,"fuel":12,"ammo":40,"reserve":0,"cargo":{"steel":4}})
	truck.has_mg=true
	truck.aim_angle=-.08
	truck.velocity=Vector2(125,0)
	truck.wheel_phase=2.8
	truck.journey_state=ConvoyJourney.new_state("driving")
	game.expedition.vehicle=truck
	for index in game.players.size():
		var worker=game.players[index]
		worker.position=truck.position
		check(truck.board(worker,"driver" if index==0 else "gunner"),"Prepared actual worker occupies real travel seat "+str(index+1))
	freeze(truck)
	truck.sync_replica()
	flybys=game.get_node_or_null("ConvoyAirEncounters")
	if flybys==null:
		flybys=Flybys.new()
		flybys.name="ConvoyAirEncounters"
		flybys.game=game
		flybys.controller=game.expedition
		game.add_child(flybys)
	flybys.set_process(false)
	for entry in [{"prefix":"survey","route":"harbor"},{"prefix":"transport","route":"quarry"},{"prefix":"jets","route":"canyon"},{"prefix":"zeppelin","route":"steelworks"}]:
		for sample in [{"id":"approach","phase":.18},{"id":"mid","phase":.5},{"id":"departure","phase":.80}]:
			await capture(str(entry.prefix)+"-"+str(sample.id),str(entry.route),float(sample.phase))
	await capture("transport-reduced","quarry",.5,true)
	await capture("jets-720p","canyon",.5,false,Vector2i(1280,720))
	await capture("zeppelin-qhd","steelworks",.5,false,Vector2i(2560,1440))
	if "--video" in args:
		var frame_directory:=OS.get_environment("BUNKERCREW_AIR_VIDEO_FRAMES")
		if not frame_directory.is_absolute_path():
			check(false,"Native video requires an explicit disposable frame directory")
		else:
			DirAccess.make_dir_recursive_absolute(frame_directory)
			for route: String in ["harbor","quarry","canyon","steelworks"]:
				var spec: Dictionary=Catalog.DEFINITIONS[Catalog.ROUTES[route]]
				var count:=ceili(float(spec.duration)*20.0)
				for frame in count:
					await draw_state(route,float(frame)/float(count-1),false,Vector2i(1280,720))
					await RenderingServer.frame_post_draw
					var image:=view.get_texture().get_image()
					if image.save_jpg(frame_directory.path_join("%05d.jpg"%video_frames),.90)!=OK:
						check(false,"Native video frame save")
						break
					video_frames+=1
			check(video_frames==890,"Four complete authored passes render 890 native 20 fps frames")
	check(not game.network.active and not game.microphone.capturing,"Native gallery opens neither sockets nor microphone")
	check(AudioServer.is_bus_mute(0),"Native gallery keeps its own audio output muted")
	check(await Cleanup.free_scene(game,self),"Native road scene retires flyby and engine playback handles")
	view.queue_free()
	await process_frame
	var fixture:="Actual two-worker Aschewerk road, real driver and roof-MG seats, authored convoy/aircraft/cloud atlases, native independent SubViewport at real y430. Journey stage and animation_time samples prepared, gameplay/waves held. This documents cosmetic approach/pass/departure, not live driving or combat; no input injection, profile saves, sockets or microphone; own master muted."
	FileAccess.open(OUTPUT+"gallery.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"passed":checks-failures,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"foreground_cloud_pixels_over_hull_bounds":foreground_pixels,"video_frames":video_frames,"video":"flybys-native.mp4" if video_frames>0 else "","video_fixture":"Silent native 1280x720 20 fps presentation-clock review of four complete flybys. Camera/car/gameplay held; aircraft/propulsion/clouds animated. Frames generated by the game's own renderer, not user window recording." if video_frames>0 else "","fixture":fixture,"captures":captures},"  "))
	var html:="<!doctype html><html lang='de'><meta charset='utf-8'><meta name='viewport' content='width=device-width'><title>Bunkercrew · Streckenüberflüge</title><style>body{background:#101918;color:#dfdfce;font:16px system-ui;margin:24px}p{max-width:90ch}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(420px,1fr));gap:20px}figure{margin:0}img{width:100%;display:block}figcaption{padding:8px 0}a{color:#e7bd77}</style><h1>Streckenüberflüge</h1><p>Vier entfernte, rein atmosphärische Flugformationen mit eigenständiger Propulsion, räumlichen Motoren und Wolken davor und dahinter. Kein Gegner, kein unsichtbarer Schaden, keine Sperre der Fahrzeugsteuerung. Vorbereitete native Bildfolge mit angehaltenem Spiel und vorgegebener replizierter Fahrzeugzeit; keine Behauptung eines Live-Durchlaufs.</p><p><a href='gallery.json'>Prüfdaten</a> · <a href='survey-without-front-cloud.png'>Identischer Frame ohne vordere Wolke</a></p><main>"
	if video_frames>0: html+="<figure><video controls muted loop preload='metadata' style='width:100%' src='flybys-native.mp4'></video><figcaption>Vier vollständige Überflüge · 20 fps · ohne Ton · native Präsentationszeit, Fahrzeug und Spiel angehalten</figcaption></figure>"
	for shot: Dictionary in captures:
		html+="<figure><a href='%s'><img src='%s' loading='lazy'></a><figcaption>%s · %s · %.0f %% · %s</figcaption></figure>"%[shot.file,shot.file,shot.id,shot.route,float(shot.phase)*100,str(shot.resolution)]
	html+="</main></html>"
	FileAccess.open(OUTPUT+"index.html",FileAccess.WRITE).store_string(html)
	print("CONVOY AIR ENCOUNTERS GALLERY: %d/%d passed; %d captures"%[checks-failures,checks,captures.size()])
	quit(1 if failures else 0)
