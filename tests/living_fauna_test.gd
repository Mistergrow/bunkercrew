extends SceneTree
## Habitat, genuine atlas poses, threat reactions, and bounded presentation
## costs are exercised with real scene processing, without player saves.
const Fauna := preload("res://scripts/living_fauna.gd")
const Catalog := preload("res://scripts/fauna_catalog.gd")
var checks := 0
var failures := 0

class FakeWeather extends Node:
	var reduced_effects := false

class FakeBunker extends Node:
	var room_left := 400.0
	var room_right := 1040.0

class FakeGame extends Node:
	var players: Array[Node] = []
	var weather: FakeWeather
	var scenario_bunker: FakeBunker

class FakeWeapon extends Node2D:
	var _shot_index := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	print("FAUNA %s: %s"%["PASS" if value else "FAIL",label])
	if not value:
		failures += 1
		push_error(label)

func make_game() -> FakeGame:
	var game := FakeGame.new()
	game.weather = FakeWeather.new()
	game.scenario_bunker = FakeBunker.new()
	game.add_child(game.weather)
	game.add_child(game.scenario_bunker)
	root.add_child(game)
	return game

func make_fauna(game: FakeGame,environment: String,menu := false) -> Node2D:
	var fauna := Fauna.new()
	fauna.configure(game,environment)
	fauna.menu_mode = menu
	game.add_child(fauna)
	fauna.set_process(false)
	return fauna

func check_ground_bounds(fauna: Node2D,environment: String) -> void:
	var grounded := 0
	var valid := true
	for entry: Dictionary in fauna.entries:
		if entry.mode in ["ground","hopper"]:
			grounded += 1
			var point: Vector2 = entry.position
			var bounds: Vector2 = entry.ground_range
			valid = valid and point.x>=bounds.x and point.x<=bounds.y and is_equal_approx(point.y,Catalog.GROUND_Y)
			valid = valid and not (point.x>400-48 and point.x<1040+48)
	check(valid and grounded>0,"%s animals remain on real ground outside the bunker and its doors"%environment)

func run() -> void:
	check(Catalog.PROFILES.size()==13,"all thirteen environments have an ecological profile")
	for environment: String in Catalog.PROFILES:
		var fixture_game := make_game()
		var fixture_fauna := make_fauna(fixture_game,environment)
		var identical := make_fauna(fixture_game,environment)
		check(fixture_fauna.debug_snapshot()==identical.debug_snapshot(),"%s population and initial poses are deterministic"%environment)
		check(fixture_fauna.entries.size()==Catalog.population(environment) and fixture_fauna.entries.size()<=Catalog.MAX_POPULATION,"%s has its bounded species mix"%environment)
		check(fixture_fauna.atlas!=null,"%s loads the genuine generated wildlife atlas"%environment)
		var habitat: Dictionary = Catalog.profile(environment)
		var valid_species := true
		var quiet_roster: bool = fixture_fauna.entries.size()>=1 and fixture_fauna.entries.size()<=2
		for entry: Dictionary in fixture_fauna.entries:
			valid_species = valid_species and habitat.species.has(entry.species)
			quiet_roster = quiet_roster and not Catalog.airborne(entry.species) and entry.mode in ["ground","hopper"]
			if entry.species=="frog": valid_species = valid_species and bool(habitat.wetland)
			if bool(habitat.cold): valid_species = valid_species and entry.species not in ["frog","moth"]
		check(valid_species,"%s wildlife matches its climate and wetland habitat"%environment)
		check(quiet_roster,"%s has only one or two quiet ground animals and no birds, bats, or moths"%environment)
		check_ground_bounds(fixture_fauna,environment)
		var original_snapshot: Array[Dictionary] = fixture_fauna.debug_snapshot()
		for tick in 300: fixture_fauna._process(1.0/60.0)
		var quiet_rest := true
		for index in fixture_fauna.entries.size(): quiet_rest = quiet_rest and fixture_fauna.entries[index].position==original_snapshot[index].position and fixture_fauna.entries[index].frame==0
		check(quiet_rest,"%s rests without sliding or flickering poses for at least five seconds"%environment)
		for tick in 1200: fixture_fauna._process(1.0/60.0)
		var foraged := false
		for index in fixture_fauna.entries.size(): foraged = foraged or Vector2(fixture_fauna.entries[index].position).distance_to(original_snapshot[index].position)>.5
		check(foraged,"%s makes occasional small foraging movements after a longer rest"%environment)
		check_ground_bounds(fixture_fauna,environment)
		fixture_game.weather.reduced_effects = true
		fixture_fauna.refresh_presentation()
		var reduced_stats: Dictionary = fixture_fauna.debug_stats()
		check(reduced_stats.active>0 and reduced_stats.active<=ceili(fixture_fauna.entries.size()/3.0),"%s F3 keeps a small representative population"%environment)
		fixture_game.weather.reduced_effects = false
		fixture_fauna.refresh_presentation()
		check(fixture_fauna.debug_stats().active==fixture_fauna.entries.size(),"%s full wildlife returns when F3 is disabled"%environment)
		fixture_fauna.position = Vector2(5000,5000)
		fixture_fauna.refresh_presentation()
		for entry: Dictionary in fixture_fauna.entries: entry.hidden_delta = 0.0
		fixture_fauna._process(.01)
		check(fixture_fauna.debug_stats().visible==0,"%s wildlife outside the camera is culled"%environment)
		check(fixture_fauna.simulated_entries==0,"%s offscreen creatures skip full per-frame simulation"%environment)
		fixture_fauna.position = Vector2.ZERO
		fixture_fauna.refresh_presentation()
		var menu := make_fauna(fixture_game,environment,true)
		check(menu.entries.is_empty(),"%s menu remains free of animals and flying sprites"%environment)
		check(fixture_fauna.debug_stats().collision_queries==0 and fixture_fauna.get_child_count()==0,"%s uses no wildlife physics bodies or per-animal nodes"%environment)
		fixture_game.queue_free()
		await process_frame

	var game := make_game()
	var fauna := make_fauna(game,"overgrown_steelworks")
	var texture_bounds := Rect2(Vector2.ZERO,fauna.atlas.get_size())
	for species: String in Catalog.SPECIES_ORDER:
		var source_frames: Array = fauna._atlas_frames[species]
		var anchors: Array = fauna._atlas_frame_anchors[species]
		var canvas: Vector2 = fauna._atlas_canvas_sizes[species]
		var valid_atlas := source_frames.size()==4 and anchors.size()==4 and canvas.x>0 and canvas.y>0
		for index in source_frames.size():
			var frame: Rect2 = source_frames[index]
			var anchor: Vector2 = anchors[index]
			valid_atlas = valid_atlas and texture_bounds.encloses(frame) and frame.size.x>1 and frame.size.y>1 and anchor.x>=0 and anchor.x<=1 and anchor.y>=0 and anchor.y<=1
		check(valid_atlas,"%s has four measured atlas poses with stable authored pivots"%species)
		var sample: Dictionary = fauna.entries[0].duplicate(true)
		sample.species = species
		sample.size = Catalog.SPECIES[species].size
		sample.mode = Catalog.SPECIES[species].mode
		sample.airborne = true
		sample.position = Vector2(900,350)
		sample.hop_lift = 0.0
		var stable_geometry := true
		for frame in 4:
			var anchor: Vector2 = anchors[frame]
			sample.direction = 1.0
			var forward: Rect2 = fauna._sprite_rect(sample,frame)
			sample.direction = -1.0
			var mirrored: Rect2 = fauna._sprite_rect(sample,frame)
			var forward_pivot := forward.position+forward.size*anchor
			var mirrored_pivot := mirrored.position+mirrored.size*anchor
			stable_geometry = stable_geometry and forward_pivot.distance_to(sample.position)<.8 and mirrored_pivot.distance_to(sample.position)<.8
			stable_geometry = stable_geometry and is_equal_approx(absf(forward.size.x)/source_frames[frame].size.x,float(sample.size.x)/canvas.x)
		check(stable_geometry,"%s preserves its body pivot and native pixel scale across animation and facing changes"%species)

	var mouse: Dictionary = {}
	var frog: Dictionary = {}
	for entry: Dictionary in fauna.entries:
		if entry.species=="mouse" and mouse.is_empty(): mouse = entry
		if entry.species=="frog" and frog.is_empty(): frog = entry
	var initial_mouse: Vector2 = mouse.position
	mouse.hidden_delta = 0.0
	fauna.notify_disturbance(initial_mouse-Vector2(22,0),100)
	check(mouse.state=="flee" and float(mouse.direction)>0 and mouse.flee_events==1,"nearby disturbance sends a mouse away from the source")
	var serial := int(mouse.flee_events)
	fauna.notify_disturbance(initial_mouse,100)
	check(int(mouse.flee_events)==serial,"a brief disturbance cooldown prevents repeated panic resets")
	for tick in 20: fauna._process(1.0/60.0)
	check(Vector2(mouse.position).distance_to(initial_mouse)>8,"the actual flee state moves the mouse along the terrain")
	check_ground_bounds(fauna,"flee")
	var hopping: Dictionary = frog.duplicate(true)
	hopping.state = "hop"
	hopping.state_time = 0.0
	hopping.position = Vector2(1200,Catalog.GROUND_Y)
	hopping.target = Vector2(1350,Catalog.GROUND_Y)
	hopping.remaining = 3.0
	var sync_valid := true
	var raised_frames := 0
	for tick in 140:
		var before_x: float = hopping.position.x
		fauna._step_entry(hopping,.01)
		if float(hopping.hop_lift)>.2:
			raised_frames += 1
			sync_valid = sync_valid and hopping.frame==2
		if hopping.frame in [0,1,3]: sync_valid = sync_valid and is_equal_approx(hopping.position.x,before_x)
		sync_valid = sync_valid and float(hopping.hop_lift)<=3.01
	check(sync_valid and raised_frames>0,"a frog's short hop matches its push-off pose and avoids sliding grounded feet")
	hopping.remaining = .001
	for tick in 100: fauna._step_entry(hopping,.01)
	check(hopping.state=="rest" and hopping.frame==0 and hopping.hop_lift==0.0 and hopping.remaining>=5,"a short hop lands and returns to a still resting pose")

	for entry: Dictionary in fauna.entries: entry.protected_time = 0.0
	mouse.position = Vector2(1180,Catalog.GROUND_Y)
	mouse.state = "rest"
	mouse.remaining = 4.0
	var player := Node2D.new()
	player.position = Vector2(1160,Catalog.GROUND_Y)
	var weapon := FakeWeapon.new()
	weapon.name = "WorkerWeapon"
	player.add_child(weapon)
	game.add_child(player)
	game.players.append(player)
	fauna._sample_disturbances()
	check(mouse.state=="flee","real scene proximity samples react to a player without physics raycasts")
	for entry: Dictionary in fauna.entries: entry.protected_time = 0.0
	mouse.position = Vector2(1280,Catalog.GROUND_Y)
	mouse.state = "rest"
	weapon._shot_index += 1
	fauna._sample_disturbances()
	check(mouse.state=="flee","a new weapon shot serial scares wildlife beyond the ordinary proximity radius")

	for index in 90:
		var enemy := Node2D.new()
		enemy.position = Vector2(1800,430)
		game.add_child(enemy)
		enemy.add_to_group("enemies")
	for entry: Dictionary in fauna.entries: entry.protected_time = 0.0
	var before_queries: int = fauna.threat_queries
	fauna._sample_disturbances()
	check(fauna.threat_queries-before_queries<=Catalog.MAX_POPULATION*Fauna.MAX_THREAT_SOURCES,"many enemies retain a bounded proximity query budget")
	var initial_nodes := game.get_child_count()
	for tick in 1200: fauna._process(1.0/60.0)
	check(game.get_child_count()==initial_nodes and fauna.entries.size()==Catalog.population("overgrown_steelworks"),"a sustained wildlife update creates no entities or growing populations")
	check_ground_bounds(fauna,"sustained")

	fauna.set_process(true)
	await process_frame
	await process_frame
	var before_pause: float = fauna.elapsed
	paused = true
	await create_timer(.07,true,false,true).timeout
	check(is_equal_approx(fauna.elapsed,before_pause),"actual SceneTree pause freezes gameplay wildlife")
	paused = false
	await process_frame
	await process_frame
	check(fauna.elapsed>before_pause,"wildlife resumes after the game is unpaused")
	fauna.set_menu_mode(true)
	check(fauna.entries.is_empty(),"switching an already prepared world to menu mode removes all wildlife")
	var menu_clock: float = fauna.elapsed
	paused = true
	await create_timer(.07,true,false,true).timeout
	check(fauna.elapsed==menu_clock,"an empty menu wildlife layer spends no time on simulation while paused")
	paused = false
	game.scenario_bunker = null
	var classic := make_fauna(game,"sector07")
	var supported := true
	for entry: Dictionary in classic.entries:
		if entry.mode in ["ground","hopper"]: supported = supported and entry.position.x>=921 and entry.position.x<=1410 and is_equal_approx(entry.position.y,Catalog.GROUND_Y)
	check(supported,"classic bunker ground wildlife remains on its actual 75..1440 floor outside the building")
	var weak_fauna: WeakRef = weakref(fauna)
	game.queue_free()
	await process_frame
	check(weak_fauna.get_ref()==null,"world teardown releases wildlife and its texture references")
	print("FAUNA: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
