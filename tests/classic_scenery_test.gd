extends SceneTree
## Restore the existing classic artwork without duplicating scene state or
## adding invisible terrain/actors. Exercise actual restart and mode changes.
const CLEANUP := preload("res://tests/scene_cleanup.gd")
const MAIN := preload("res://scenes/main.tscn")
const DRAWING := preload("res://scripts/scenery_layer.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func verify_backing(game: Node2D) -> void:
	var layers: Array = game.scenery.legacy_layers
	check(layers.size()==4,"classic contains the original earth, interior, prop and structure drawings")
	var indices: Array[int] = []
	var fixed := true
	var no_gameplay := true
	for layer: Node2D in layers:
		indices.append(int(layer.layer))
		fixed = fixed and layer.get_script()==DRAWING and layer.position==Vector2.ZERO and layer.get_parent()==game.scenery and layer.z_index==int(layer.layer)
		no_gameplay = no_gameplay and layer.find_children("*","CollisionObject2D",true,false).is_empty() and not layer.has_method("_process") and not layer.has_method("_physics_process")
	check(indices==[1,2,3,4] and fixed,"classic uses its existing style at fixed world coordinates in the original layer order")
	check(no_gameplay,"classic backing adds only static drawing, without actors, physics or update loops")
	check(game.scenery.find_children("ClassicDrawing*","Node2D",true,false).size()==4,"exactly one classic backing instance exists per drawing")
	check(game.scenery.lighting.z_index==6,"existing classic lighting stays above the restored backing")
	var outside: Node2D = game.scenery.vegetation_layer.outskirts
	check(outside.landscape==[Rect2(-960,245,930,1),Rect2(1440,430,960,1)],"outer roots match the actual classic hillside and eastern road tops")
	var localization: Node = root.get_node("Localization")
	check(localization.locale_changed.is_connected(game.scenery._redraw_legacy_labels),"runtime language changes invalidate the static classic labels")

func count_draw(state: Dictionary,index: int) -> void:
	state.counts[index] += 1

func verify_language_draws(game: Node2D) -> void:
	if DisplayServer.get_name()=="headless": return
	LocaleText.set_locale("de",false)
	var state := {"counts":[0,0,0,0]}
	var layers: Array = game.scenery.legacy_layers
	for index in layers.size(): layers[index].draw.connect(count_draw.bind(state,index))
	for index in 2: await RenderingServer.frame_post_draw
	var body_count := game.find_children("*","CollisionObject2D",true,false).size()
	var positions: Array[Vector2] = []
	for layer: Node2D in layers: positions.append(layer.position)
	for locale in ["en","de"]:
		var before: Array = state.counts.duplicate()
		LocaleText.set_locale(locale,false)
		for index in 2: await RenderingServer.frame_post_draw
		var updated := true
		for index in layers.size(): updated = updated and int(state.counts[index])==int(before[index])+1
		check(updated,locale+": switching language triggers exactly one actual redraw of all classic label layers")
		check(game.find_children("*","CollisionObject2D",true,false).size()==body_count,locale+": label redraw leaves physical terrain unchanged")
		var fixed := true
		for index in layers.size(): fixed = fixed and layers[index].position==positions[index]
		check(fixed,locale+": label redraw keeps every classic ground and room at its existing world position")

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var game := MAIN.instantiate() as Node2D
	root.add_child(game)
	current_scene = game
	game.start(1)
	game.rounds.running = false
	verify_backing(game)
	await verify_language_draws(game)
	var body_count := game.find_children("*","CollisionObject2D",true,false).size()
	game.start(1)
	check(game.find_children("*","CollisionObject2D",true,false).size()==body_count,"starting an already running classic scene preserves its original physical world")
	check(game.scenery.legacy_layers.size()==4,"idempotent classic start never duplicates backing")
	var old: WeakRef = weakref(game.scenery)
	check(game.restart(),"actual offline classic restart accepted")
	var deadline := Time.get_ticks_msec()+3000
	while Time.get_ticks_msec()<deadline and (current_scene==game or not is_instance_valid(current_scene) or not bool(current_scene.get("started"))):
		await process_frame
	game = current_scene as Node2D
	check(is_instance_valid(game) and bool(game.get("started")),"actual scene reload restores a running classic round")
	if not is_instance_valid(game) or not bool(game.get("started")):
		quit(1)
		return
	game.rounds.running = false
	verify_backing(game)
	check(old.get_ref()==null,"classic restart retires all old backing and outer meshes")
	old = weakref(game.scenery)
	check(game.return_to_menu(),"actual classic return to menu accepted")
	deadline = Time.get_ticks_msec()+3000
	while Time.get_ticks_msec()<deadline and (current_scene==game or not is_instance_valid(current_scene) or bool(current_scene.get("started"))):
		await process_frame
	game = current_scene as Node2D
	check(is_instance_valid(game) and not bool(game.get("started")),"normal menu return retires the classic world before scenario selection")
	game.start_scenario(1,{"environment":"mountain_pass","build_type":"bastion","position":"center"})
	game.rounds.running = false
	await process_frame
	check(old.get_ref()==null,"switching classic to a scenario releases the restored classic backing")
	check(game.scenery.find_children("ClassicDrawing*","Node2D",true,false).is_empty(),"scenario panorama and terrain do not inherit duplicate classic drawings")
	check(is_instance_valid(game.scenario_bunker) and is_instance_valid(game.scenery.vegetation_layer.outskirts),"scenario world and its own cosmetic outskirts remain integrated")
	check(await CLEANUP.free_scene(game,self),"classic/scenario lifetime test cleanup")
	print("CLASSIC SCENERY: %d/%d checks passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
