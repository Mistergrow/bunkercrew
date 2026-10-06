extends SceneTree
## Arranged actor positions hold real sliding hatches open. No terrain or rain
## contacts are mocked; the flak is assembled through its paid interaction path.
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ",label)
	if not ok:
		failures += 1
		push_error(label)

func frames(count: int = 16) -> void:
	for index in count:
		await physics_frame
		await process_frame

func passage_at(point: Vector2) -> LadderPassage:
	for passage: LadderPassage in get_nodes_in_group("ladder_passages"):
		if passage.global_position.distance_to(point)<1:
			return passage
	return null

func contact(weather: ShiftWeather,x: float,from_y: float,to_y: float) -> Dictionary:
	return weather.trace_rain(Vector2(x,from_y),Vector2(x,to_y),false)

func hold_open(worker: Node2D,passage: LadderPassage) -> void:
	worker.global_position = passage.global_position+Vector2(0,35)
	worker.climbing = true
	worker.velocity = Vector2.ZERO

func leave(worker: Node2D,bunker: ScenarioBunker) -> void:
	worker.global_position = bunker.spawn_position(worker.player_id)
	worker.climbing = false
	worker.velocity = Vector2.ZERO

func run() -> void:
	for mode: String in ["left","center","right"]:
		var game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		game.start_scenario(2,{"environment":"sector07","build_type":"bastion","position":mode})
		game.rounds.set_process(false)
		game.weather.set_process(false)
		game.medic.set_physics_process(false)
		for worker in game.players:
			worker.set_physics_process(false)
		await frames(4)
		var bunker: ScenarioBunker = game.scenario_bunker
		var weather: ShiftWeather = game.weather
		var shaft_x := bunker.room_left+54.0
		var roof := passage_at(Vector2(shaft_x,245))
		var deck := passage_at(Vector2(shaft_x,430))
		check(is_instance_valid(roof) and is_instance_valid(deck),"%s has real roof and main-floor passages"%mode)
		if not is_instance_valid(roof) or not is_instance_valid(deck):
			await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
			continue
		var closed := contact(weather,shaft_x,220,300)
		check(closed.get("collider")==roof and closed.get("material")=="metal","%s closed roof hatch intercepts drops on actual steel"%mode)
		check(weather.rain_surface(shaft_x)==245.0,"%s closed architectural cover agrees with physical roof hatch"%mode)
		for offset: float in [-LadderPassage.WIDTH*.5-4,LadderPassage.WIDTH*.5+4]:
			# Rooftop crates and the west gun have their own valid rain contours.
			# Begin immediately above the slab to isolate its actual rim geometry.
			var rim := contact(weather,shaft_x+offset,244.9,300)
			check(rim.get("material")=="concrete" and absf(float(rim.get("position",Vector2.ZERO).y)-245)<0.1,"%s concrete beside shaft remains watertight at offset%.0f"%[mode,offset])
		hold_open(game.players[0],roof)
		await frames(2)
		check(roof.opening>0.0 and roof.opening<.999,"%s steel cover actually retracts over several physics frames"%mode)
		check(contact(weather,shaft_x,244.9,300).is_empty() and weather.rain_surface(shaft_x)==430.0,"%s partial opening already passes drops through its real center gap"%mode)
		var remaining_leaf := contact(weather,shaft_x-LadderPassage.WIDTH*.5+1,244.9,300)
		check(remaining_leaf.get("collider")==roof and remaining_leaf.get("material")=="metal","%s partly retracted leaf still blocks rain on its occupied edge"%mode)
		await frames()
		check(roof.opening>.999 and roof.collision_layer==0,"%s crossing body actually retracts roof leaves"%mode)
		check(contact(weather,shaft_x,240,300).is_empty(),"%s no fallback roof seals the open hatch"%mode)
		var lower := contact(weather,shaft_x,240,500)
		check(lower.get("collider")==deck and lower.get("material")=="metal","%s drops continue to the next closed floor hatch"%mode)
		check(weather.rain_surface(shaft_x)==430.0 and weather.is_outdoors(Vector2(shaft_x,300)),"%s rain clipping follows open roof to the real lower cover"%mode)
		hold_open(game.players[1],deck)
		await frames()
		var raw_floor := contact(weather,shaft_x,240,700)
		check(deck.opening>.999 and absf(float(raw_floor.get("position",Vector2.ZERO).y)-635)<0.1,"%s simultaneous roof and floor openings reach the solid raw-mine floor"%mode)
		check(weather.rain_surface(shaft_x)==635.0 and weather.is_outdoors(Vector2(shaft_x,550)),"%s no continuous y430 earth fallback seals the actual shaft"%mode)
		for worker in game.players:
			leave(worker,bunker)
		await frames()
		check(roof.opening<.001 and deck.opening<.001 and weather.rain_surface(shaft_x)==245.0,"%s vacant passages close and restore dry indoor cover"%mode)
		check(contact(weather,shaft_x,220,300).get("collider")==roof,"%s rain contact cache recognizes the reclosed steel cover"%mode)
		var flak: FlakStation = game.flak_station
		game.rounds.wave = 7
		flak.unlock()
		var builder = game.players[0]
		for kind: String in FlakStation.SPECS[1].cost:
			for index in int(FlakStation.SPECS[1].cost[kind]):
				builder.add_item(kind,1)
				flak.interact(builder,Balance.TRANSFER_TIME)
		flak.interact(builder,float(FlakStation.SPECS[1].time))
		await frames(4)
		var tower_roof := passage_at(Vector2(flak.access.get_center().x,245))
		var tower_top := passage_at(Vector2(flak.access.get_center().x,35))
		check(flak.built and is_instance_valid(tower_roof) and is_instance_valid(tower_top),"%s paid flak owns passages through roof and platform"%mode)
		if is_instance_valid(tower_roof) and is_instance_valid(tower_top):
			var tower_x := tower_top.global_position.x
			check(weather.rain_surface(tower_x)==35.0,"%s closed flak platform covers its service ladder"%mode)
			hold_open(game.players[0],tower_top)
			await frames()
			check(weather.rain_surface(tower_x)==245.0,"%s open flak platform reveals the roof cover below"%mode)
			hold_open(game.players[1],tower_roof)
			await frames()
			check(contact(weather,tower_x,244.9,300).is_empty(),"%s second ladder has no phantom concrete roof"%mode)
			check(weather.rain_surface(tower_x)==430.0,"%s both open flak passages expose the room's solid bottom floor"%mode)
			for worker in game.players:
				leave(worker,bunker)
			await frames()
			check(weather.rain_surface(tower_x)==35.0,"%s flak hatches restore cover after both crew leave"%mode)
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("PASSAGE WEATHER: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
