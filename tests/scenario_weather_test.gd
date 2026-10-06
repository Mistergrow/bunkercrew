extends SceneTree
## Real scene positions, physical shelter and paid assembly. Layouts are selected
## normally; timers are stepped only for focused construction regressions.
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if ok: print("PASS ",label)
	else:
		failures+=1
		push_error(label)
func frames(count:=3):
	for index in count:
		await physics_frame
		await process_frame
func contact(weather,x:float,from_y:float=-500.0,to_y:float=460.0) -> Dictionary:
	return weather.trace_rain(Vector2(x,from_y),Vector2(x,to_y),false)
func feed(site,worker,cost:Dictionary):
	worker.inventory.clear()
	for kind:String in cost:
		for index in int(cost[kind]):
			worker.add_item(kind,1)
			site.interact(worker,Balance.TRANSFER_TIME)
func run():
	for mode:String in ["left","center","right"]:
		var game=load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene=game
		game.start_scenario(1,{"environment":"sector07","build_type":"bastion","position":mode})
		game.rounds.set_process(false)
		game.weather.set_process(false)
		game.medic.set_physics_process(false)
		var worker=game.players[0]
		worker.set_physics_process(false)
		await frames(5)
		var bunker:ScenarioBunker=game.scenario_bunker
		var weather:ShiftWeather=game.weather
		var left:=bunker.room_left
		var right:=bunker.room_right
		# Probe the free service bay. Five crates occupy +312..560 with only
		# four-pixel gaps; a former +350 probe now correctly hits the ore crate.
		var roof_x:=left+265.0
		var roof:=contact(weather,roof_x)
		check(not roof.is_empty() and absf(roof.position.y-245.0)<0.1 and roof.material=="concrete","%s actual relocated roof receives rain at y245"%mode)
		check(is_equal_approx(weather.rain_surface(roof_x),245.0),"%s architectural rain clip agrees with actual roof"%mode)
		check(weather.exposure_at(Vector2(roof_x,225))>0.9 and weather.exposure_at(Vector2(roof_x,380))==0.0,"%s roof is exposed while inhabited room is sheltered"%mode)
		check(weather.exposure_at(Vector2(left+75,600))==0.0,"%s initial underground raw shaft stays sheltered"%mode)
		for x:float in [left-145.0,right+145.0]:
			var floor_contact:=contact(weather,x)
			var expected_material := "concrete" if mode=="center" or (mode=="left" and x>right) or (mode=="right" and x<left) else "soil"
			check(not floor_contact.is_empty() and absf(floor_contact.position.y-430.0)<0.1 and floor_contact.material==expected_material,"%s outdoor approach%s receives rain on its actual paved/earth finish at430"%[mode,x])
			check(is_equal_approx(weather.rain_surface(x),430.0) and weather.exposure_at(Vector2(x,400))>0.9,"%s outdoor approach%s is exposed in clipping and wind ray"%[mode,x])
		# Select a column belonging to the old fixed75..750 roof but outside this
		# chosen bunker. The left layout retains that range, so probe old hillside.
		var legacy_x:=50.0 if mode=="left" else 220.0
		var former_roof:=contact(weather,legacy_x)
		check(not former_roof.is_empty() and absf(former_roof.position.y-430.0)<0.1 and weather.rain_surface(legacy_x)==430.0,"%s old fixed roof/hillside no longer creates invisible shelter"%mode)
		check(weather.is_outdoors(Vector2(legacy_x,340)),"%s rain may visibly cross old roof columns above actual earth"%mode)
		var pole_x:=left+30.0
		var pole:=contact(weather,pole_x,100.0,230.0)
		check(pole.get("collider")==weather and pole.get("material")=="metal" and absf(pole.position.y-174.0)<0.1,"%s flagpole rain contour follows actual moved roof flag"%mode)
		var cloth_top: Vector2 = weather.flag_offset()+(weather.flag_panel(2)[0]+weather.flag_panel(2)[1])*.5
		var cloth:=contact(weather,cloth_top.x,140.0,230.0)
		check(cloth.get("collider")==weather and cloth.get("material")=="cloth" and absf(cloth.position.y-cloth_top.y)<.1,"%s animated flagcloth and contact surface share relocated coordinates"%mode)
		var flags_fit:=true
		for segment:Dictionary in weather.prop_surfaces.rain_segments():
			if segment.get("collider")!=weather: continue
			flags_fit=flags_fit and Vector2(segment.from).x>=left+28-0.01 and Vector2(segment.to).x<=left+67+0.01
		check(flags_fit,"%s no weather-only flag silhouette remains at legacy origin"%mode)
		# Prepared excavation uses actual mining calls; this weather fixture moves
		# its worker beside each face. The input playtest verifies the walking route.
		var site:ScenarioRoomSite=bunker.modules[0]
		check(await preload("res://tests/scenario_excavation_fixture.gd").clear_terrain(bunker.fields[0],worker),"%s real earth is removed before the room is supported"%mode)
		worker.position=site.position
		feed(site,worker,site.support_cost())
		site.interact(worker,ScenarioRoomCatalog.SUPPORT_TIME)
		check(site.supported and site.support_materials=={"steel":2},"%s two paid steel supports precede all room fitting"%mode)
		feed(site,worker,site.room_cost())
		site.interact(worker,ScenarioRoomCatalog.BUILD_TIME)
		site._process(ScenarioRoomCatalog.CURE_TIME)
		await frames()
		check(site.built and bunker.built_rooms==2 and worker.inventory.is_empty(),"%s paid first room actually exists before testing underground shelter"%mode)
		check(weather.exposure_at(Vector2(left+75,610))==0.0 and weather.exposure_at(Vector2(left+500,610))==0.0,"%s complete expanded room stays dry across its whole width"%mode)
		worker.position=Vector2(left+95,635)
		await frames()
		var rescue_route:Array=game.medic.navigation.route_to(worker)
		check(not rescue_route.is_empty() and rescue_route.any(func(edge):return edge.kind=="climb"),"%s SAN-1 has a physical ladder route from core to paid underground room"%mode)
		worker.position=Vector2(bunker.core_x+66,430)
		game.rounds.wave=16
		game.upgrades.owned["bunker_fortress"]=true
		game.set_view_stage(4)
		var dome:DomeController=game.dome
		feed(dome,worker,{"steel":4,"alloy":4})
		dome.interact(worker,DomeController.FRAME_TIME)
		feed(dome,worker,{"glass":12})
		dome.interact(worker,DomeController.GLAZE_TIME)
		await frames()
		check(dome.built and worker.inventory.is_empty() and dome.materials==DomeController.COST,"%s physical late-wave dome finishes at selected site with exact paid recipe"%mode)
		# Test the narrow pane opening during calm. In a strong crosswind an
		# intact neighbour can correctly shelter a point vertically below it.
		weather.elapsed = 50.0
		var dome_x:=left+555.0
		var glass:=contact(weather,dome_x)
		check(glass.get("collider") is DomeSegment and glass.get("material")=="glass" and glass.position.y<245,"%s curved relocated glass intercepts rain before bunker roof"%mode)
		check(absf(weather.rain_surface(dome_x)-dome.cover_height(dome_x))<0.001 and weather.exposure_at(Vector2(dome_x,200))==0,"%s exact rain clipping and incoming wind recognize dome shelter"%mode)
		var pane:DomeSegment=glass.collider
		pane.take_damage(100000)
		await frames()
		var broken:=contact(weather,dome_x)
		check(broken.get("collider")!=pane and broken.position.y>=205,"%s broken relocated glass lets rain continue to real roof equipment"%mode)
		check(weather.exposure_at(Vector2(dome_x,200))>0.9,"%s broken relocated pane opens actual sky exposure"%mode)
		pane.repair(pane.max_hp)
		await frames()
		check(contact(weather,dome_x).get("collider")==pane and weather.exposure_at(Vector2(dome_x,200))==0.0,"%s repaired pane restores both physical and incoming-rain shelter"%mode)
		var flak:FlakStation=game.flak_station
		flak.unlock()
		feed(flak,worker,FlakStation.SPECS[1].cost)
		flak.interact(worker,float(FlakStation.SPECS[1].time))
		await frames(5)
		check(flak.built and dome.flak_port_active and worker.inventory.is_empty(),"%s paid relocated flak changes actual dome roof aperture"%mode)
		var platform_x:=flak.platform.position.x+6.0
		var platform:=contact(weather,platform_x,10,140)
		check(not platform.is_empty() and absf(platform.position.y-35.0)<0.1 and platform.material=="metal","%s relocated physical flak platform receives rain at y35"%mode)
		check(weather.rain_surface(platform_x)==35.0,"%s architectural clipping follows relocated flak platform"%mode)
		var flak_hit:=contact(weather,flak.gun_position.x,-200,100)
		check(flak_hit.get("collider")==flak.turret and flak_hit.material=="metal" and flak_hit.position.y<35,"%s relocated flak gun silhouette receives drops above its deck"%mode)
		check(is_inf(weather.collision.dome_cover_height(flak.gun_position.x)) and is_inf(dome.cover_height(flak.gun_position.x)),"%s dynamic dome aperture has no stale closed-rain cache"%mode)
		var neighbor:=contact(weather,flak.gun_position.x+75,-300,200)
		check(neighbor.get("material")=="glass","%s glass alongside relocated service port remains watertight"%mode)
		var exact:=true
		for x in range(int(left)-95,int(right)+96,9):
			var cached:float=weather.collision.dome_cover_height(x)
			var current:float=dome.cover_height(x)
			exact=exact and ((is_inf(cached) and is_inf(current)) or absf(cached-current)<0.001)
		check(exact,"%s cached cover matches all relocated curved-pane and port boundaries"%mode)
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("SCENARIO WEATHER: %d/%d checks passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
