extends SceneTree
## Prepared real mountain pass. GPU stills isolate a real strike, its finite
## flash and existing fire/fall response, without combat or camera movement.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/storm-events/"
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("STORM GPU %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures += 1
		push_error(label)

func descendants(node: Node) -> Array[Node]:
	var nodes: Array[Node] = [node]
	for child in node.get_children(): nodes.append_array(descendants(child))
	return nodes

func capture(name: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	if not name.is_empty(): image.save_png(OUTPUT+name+".png")
	return image

func changed(first: Image,second: Image,rect: Rect2i) -> int:
	var count := 0
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			var a := first.get_pixel(x,y)
			var b := second.get_pixel(x,y)
			if maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))>.025: count += 1
	return count

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1440,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1,{"environment":"mountain_pass","position":"left","build_type":"bastion"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.audio.settings_path = "user://storm-preview.cfg"
	game.hud.canvas.hide()
	game.camera.position = Vector2(720,450)
	game.camera.zoom = Vector2.ONE
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	for frame in 5: await physics_frame
	var props = game.scenery.props_layer
	var storm = game.weather.storm_events
	for node in descendants(game):
		node.set_process(false)
		node.set_physics_process(false)
	var before := await capture("01-before")
	check(storm.trigger_tree_strike(),"An exposed real tree accepts the authored lightning event")
	check(storm.target_index>=0,"The event targets a live catalogue tree")
	if storm.target_index<0:
		await Cleanup.free_scene(game,self)
		quit(1)
		return
	var strike := await capture("02-crown-strike")
	var endpoint: Vector2 = game.get_canvas_transform()*storm.target
	var hit_box := Rect2i(Vector2i(endpoint)-Vector2i(80,130),Vector2i(160,160)).intersection(Rect2i(0,0,1440,900))
	check(changed(before,strike,hit_box)>120,"Actual rendered crown area contains a clear local lightning arc")
	check(changed(before,strike,Rect2i(100,300,560,120))==0,"Protected bunker pixels remain unchanged by the flash")
	check(changed(before,strike,Rect2i(780,470,540,160))==0,"Underground pixels remain unchanged by the flash")
	game.weather.set_reduced_effects(true)
	storm.queue_redraw()
	var reduced := await capture("")
	check(changed(before,reduced,hit_box)<changed(before,strike,hit_box),"F3 removes the local flash and keeps a smaller visible strike")
	check(changed(before,reduced,hit_box)>5,"Reduced effects still communicate the damaging event")
	game.weather.set_reduced_effects(false)
	storm._process(.6)
	var finished := await capture("")
	check(changed(before,finished,hit_box)==0,"The isolated lightning presentation leaves no persistent flash")
	for tick in 66:
		props.reactions._process(1.0/30.0)
		props._process(1.0/30.0)
		props.debris._process(1.0/30.0)
	var fire := await capture("03-burning-tree")
	var state: Dictionary = props.reactions.state_for(storm.target_index)
	check(state.burning and state.broken,"The existing burn controller weakens and breaks the struck tree")
	check(changed(before,fire,Rect2i(760,235,560,202))>150,"Existing fire, falling wood and light are visible after the bolt ends")
	print("STORM GPU: %d/%d checks passed" % [checks-failures,checks])
	await Cleanup.free_scene(game,self)
	quit(1 if failures else 0)
