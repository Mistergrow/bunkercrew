extends SceneTree
## Full-world rain regressions. Fixture positions/materials are arranged; contact
## rays, moving silhouettes, glass failure and paid flak geometry are real.
var game
var weather
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print("RAIN ","PASS " if ok else "FAIL ",label)
	if not ok:
		failures += 1
		push_error(label)

func frames(count := 3) -> void:
	for index in count:
		await physics_frame
		await process_frame

func vertical(x: float, top: float = -400.0, bottom: float = 460.0, actors: bool = true) -> Dictionary:
	return weather.trace_rain(Vector2(x,top),Vector2(x,bottom),actors)

func run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start(2)
	game.rounds.set_process(false)
	weather=game.weather
	weather.set_process(false)
	game.medic.set_physics_process(false)
	for worker in game.players:
		worker.set_physics_process(false)
	await frames()
	check(weather.rain.size()==120 and weather.rain_layers.size()==3,"Three populated depth bands use a fixed 120-drop primary budget")
	var counts := [0,0,0]
	for drop in weather.rain:
		counts[int(drop.band)]+=1
	check(counts==[44,52,24],"Foreground uses fewer thick fast streaks than the finer middle and distance bands")
	check(RainCatalog.BANDS[0].speed<RainCatalog.BANDS[1].speed and RainCatalog.BANDS[1].speed<RainCatalog.BANDS[2].speed,"Rain perspective separates depth through fall speed")
	check(RainCatalog.BANDS[0].length<RainCatalog.BANDS[2].length and RainCatalog.BANDS[0].parallax!=RainCatalog.BANDS[2].parallax,"Depth also changes streak length and camera response")
	var roof := vertical(600)
	check(not roof.is_empty() and absf(roof.position.y-245)<0.1 and roof.material=="concrete","Physical concrete roof is the first rain contact")
	var slope := vertical(820,200,390,false)
	check(not slope.is_empty() and absf(slope.position.y-(279.0+45.0*45.0/98.0))<0.1,"Attached gallery splash lies on the drawn sloping roof")
	check(slope.normal.x>0.30 and slope.normal.y< -0.8,"Sloped concrete supplies an outward normal for directional rebound")
	var swept:Dictionary=weather.trace_rain(Vector2(950,200),Vector2(1150,700),false)
	check(not swept.is_empty() and absf(swept.position.y-430)<0.1 and swept.material=="concrete","Long swept motion cannot tunnel through the paved courtyard")
	var approach_swept:Dictionary=weather.trace_rain(Vector2(1250,200),Vector2(1390,700),false)
	check(not approach_swept.is_empty() and absf(approach_swept.position.y-430)<0.1 and approach_swept.material=="soil","Long swept motion beyond the paved courtyard still reaches exterior soil")
	check(weather.exposure_at(Vector2(600,220))>0.9 and weather.exposure_at(Vector2(600,340))==0,"Roof blocks incoming rain above interior rooms")
	check(weather.exposure_at(Vector2(600,780))==0 and weather.exposure_at(Vector2(1000,330))>0.9,"Mine remains dry while the exposed approach is wet")
	var wall=game._entity("wall",Vector2(1110,430),{"initial_state":4})
	await frames()
	var wall_hit:=vertical(1110,260,460,false)
	check(wall_hit.get("collider")==wall and absf(wall_hit.position.y-340)<0.1,"Newly built exterior wall intercepts rain above the ground")
	wall.take_damage(100000)
	await frames()
	var breach:=vertical(1110,260,460,false)
	check(breach.get("collider")!=wall and absf(breach.position.y-430)<0.1,"Destroyed defense immediately lets rain through the opening")
	var worker=game.players[0]
	worker.position=Vector2(600,245)
	await frames()
	var worker_hit:=vertical(600,100,260)
	check(worker_hit.get("collider")==worker and worker_hit.position.y<210,"Worker helmet receives contact before the roof below")
	var belongs:=false
	for segment:Dictionary in worker.wetness.rain_segments():
		if Geometry2D.get_closest_point_to_segment(worker_hit.position,segment.from,segment.to).distance_to(worker_hit.position)<0.15:
			belongs=true
	check(belongs,"Worker contact lies on a visible pose contour rather than the capsule edge")
	var wet_before:float=worker.wetness.amount
	weather._rain_contact(worker_hit,Vector2(30,310),1.0)
	check(worker.wetness.amount>wet_before,"A real rain contact increases the actor's wetness")
	worker.position=Vector2(620,245)
	await frames()
	check(vertical(600,100,260).get("collider")!=worker and vertical(620,100,260).get("collider")==worker,"Moving worker carries the rain contact silhouette with the animation")
	var barrel:=vertical(399,100,260,false)
	check(barrel.get("collider")!=null and barrel.collider.name=="RoofBarrel" and barrel.material=="metal" and barrel.position.y<235,"Decorative roof barrel stops rain at painted metal")
	check(bool(barrel.get("weather_prop",false)),"Painted prop contacts keep attachment metadata for surface effects")
	var gun:=vertical(735,100,260,false)
	check(gun.get("collider")==game.turret and gun.material=="metal","Main roof gun has a weather contour without new gameplay blockers")
	var machine=game._entity("enemy",Vector2(1180,430),{"kind":"strider"})
	machine.set_physics_process(false)
	await frames()
	var machine_hit:=vertical(1180,250,450)
	check(machine_hit.get("collider")==machine and machine_hit.position.y<405,"Ground machine receives rain on its animated chassis")
	var aircraft=game._entity("air_enemy",Vector2(1220,140),{"kind":"scout_drone"})
	aircraft.set_physics_process(false)
	await frames()
	var air_hit:=vertical(1220,95,230)
	check(air_hit.get("collider")==aircraft and air_hit.position.y<165,"Airborne machine intercepts rain before the ground")
	machine.queue_free()
	aircraft.queue_free()
	worker.position=Vector2(305,430)
	game.rounds.wave=16
	game.set_view_stage(4)
	for pane in game.dome.segments:
		pane.set_frame()
		pane.glaze()
	await frames()
	game.set_process(false)
	game.camera.position=Vector2(850,630)
	game.camera.zoom=Vector2.ONE*0.48
	game.camera.force_update_scroll()
	await frames()
	var view_center:Vector2=game.camera.get_screen_center_position()
	var half_view:Vector2=game.get_viewport_rect().size*0.5/game.camera.zoom
	check(weather._sky_left()<=view_center.x-half_view.x-39 and weather._sky_right()>=view_center.x+half_view.x+39,"Deepest wide camera has rain coverage beyond both visible sides")
	check(weather._sky_top()<=view_center.y-half_view.y-29,"Wide sky rain begins above the visible upper camera edge")
	var foundation:Dictionary=weather.trace_rain(Vector2(1000,400),Vector2(1000,450),false)
	var foundation_fallback:Dictionary=weather.collision._fallback_trace(Vector2(1160,400),Vector2(1160,450))
	check(foundation.material=="concrete" and absf(foundation.position.y-430)<0.1 and foundation_fallback.material=="concrete","Expanded foundations use concrete at the unchanged playable support height")
	check(weather.trace_rain(Vector2(1280,400),Vector2(1280,450),false).material=="soil","Exposed ground beyond the completed foundation and courtyard remains muddy soil")
	var glass:=vertical(1030,-300,400,false)
	check(glass.get("collider") is DomeSegment and glass.material=="glass","Completed dome uses physical curved panes as first rain cover")
	var exact_cover:=true
	for x in range(0,1320,7):
		var cached:float=weather.collision.dome_cover_height(float(x))
		var uncached:float=game.dome.cover_height(float(x))
		exact_cover=exact_cover and ((is_inf(cached) and is_inf(uncached)) or absf(cached-uncached)<0.001)
	check(exact_cover,"Cached dome edges preserve exact cover across 189 columns including polygon joints")
	check(absf(glass.normal.x)>0.1 and glass.normal.y<0,"Dome supplies its curved outward normal for glass glancing droplets")
	var below_panel: Vector2 = glass.position+Vector2(0,24)
	check(weather.exposure_at(below_panel)==0,"Closed glass shell shelters the space immediately under the panel")
	var pane=glass.get("collider")
	pane.take_damage(100000)
	await frames()
	var broken:=vertical(1030,-300,460,false)
	check(broken.get("collider")!=pane and broken.position.y>glass.position.y+100,"Broken glass panel allows rain through without a phantom roof")
	check(weather.rain_surface(1030)>glass.position.y+100,"Dome cache discards a destroyed pane on the next frame")
	# Far below the break, the slanted sky ray can correctly hit an adjacent
	# intact windward pane. Measure just below the actual destroyed surface.
	check(weather.exposure_at(below_panel)>0.9,"Broken dome changes actual sky exposure immediately beneath its opening")
	pane.repair(pane.max_hp)
	await frames()
	check(vertical(1030,-300,460,false).get("collider")==pane and absf(weather.rain_surface(1030)-game.dome.cover_height(1030))<0.001,"Glass repair restores both physical and cached rain shelter")
	var station=game.flak_station
	station.unlock()
	worker.inventory.clear()
	for kind in {"steel":3,"concrete":2,"ammo":1}:
		worker.add_item(kind,{"steel":3,"concrete":2,"ammo":1}[kind])
	for index in 30:
		station.interact(worker,0.3)
	await frames()
	check(station.built and is_inf(game.dome.cover_height(530)),"Paid flak opens the actual dome service aperture")
	check(is_inf(weather.collision.dome_cover_height(530)),"Cached cover follows the newly clipped flak service aperture")
	var platform:Dictionary=weather.trace_rain(Vector2(480,12),Vector2(480,100),false)
	check(not platform.is_empty() and absf(platform.position.y-35)<0.1 and platform.material=="metal","Rain entering flak service opening lands on its physical platform")
	check(vertical(530,-300,100,false).material=="metal","Flak gun itself receives rain above its platform")
	check(vertical(460,-300,100,false).material=="glass","Glass next to the service opening remains watertight")
	var flak_contours:Array=weather.prop_surfaces.rain_segments().filter(func(segment):return segment.get("collider")==station.turret)
	var contour_contacts:=0
	var exact_flak:=true
	for x in range(500,561,6):
		var hit:=vertical(x,-200,35,false)
		if hit.get("collider")!=station.turret:
			continue
		contour_contacts+=1
		var on_contour:=false
		for segment:Dictionary in flak_contours:
			if Geometry2D.get_closest_point_to_segment(hit.position,segment.from,segment.to).distance_to(hit.position)<0.15:
				on_contour=true
		exact_flak=exact_flak and on_contour
	check(contour_contacts>=3 and exact_flak,"Flak rain uses painted contours across its width rather than the generous projectile hitbox")
	# Secondary budget/lifetime is exercised with the real shared helper.
	for index in 300:
		weather._rain_contact(roof,Vector2(40,350),float(index%3))
	check(weather.surface_effects.particles.size()<=SurfaceWeather.MAX_PARTICLES and weather.surface_effects.splashes.size()<=SurfaceWeather.MAX_SPLASHES,"Repeated contacts respect bounded spray and splash storage")
	weather.surface_effects.set_physics_process(false)
	for index in 90:
		weather.surface_effects.advance(1.0/60.0)
	check(weather.surface_effects.particles.is_empty() and weather.surface_effects.splashes.is_empty(),"Secondary water expires instead of bouncing indefinitely")
	var before:int=weather.contact_count
	var old_clock:float=weather.elapsed
	weather.set_reduced_effects(true)
	weather._process(1.0)
	check(weather.contact_count==before and weather.elapsed==old_clock and weather.lightning_strength()==0,"Reduced effects freezes primary rain, contacts and lightning")
	weather.set_reduced_effects(false)
	weather._process(1.0/60.0)
	check(weather.elapsed>old_clock,"Rain resumes after reduced effects are disabled")
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("RAIN COLLISION: %d passed, %d failed"%[checks-failures,failures])
	quit(1 if failures else 0)
