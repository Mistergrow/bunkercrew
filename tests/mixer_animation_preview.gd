extends SceneTree
## The actual production station inside the actual first bunker. Simulation
## is frozen while explicit replicated clocks are prepared for inspection.
const DEST := "res://artifacts/mixer-animation/"
const Cleanup := preload("res://tests/scene_cleanup.gd")
var view: SubViewport
var game
var mixer: ProductionStation
var before := false
var checks := 0
var failures := 0
var prepared_time := 0.0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func frames(count := 3) -> void:
	for frame in count: await process_frame

func capture(label: String) -> Image:
	await frames()
	await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	var path := DEST+("before/" if before else "after/")+label+".png"
	check(picture.save_png(path) == OK, "Native mixer capture: "+label)
	return picture

func pose(at: float, running: bool) -> void:
	mixer.working = running
	var animation := mixer.get_node_or_null("MixerAnimation")
	# Advance the actual presentation controller at a normal display cadence.
	# Its source clock is the same elapsed field used by network snapshots.
	if is_instance_valid(animation):
		if at < prepared_time:
			mixer.elapsed = at
			animation.advance_visual(0.0)
		else:
			var remaining := at-prepared_time
			while remaining > 0.00001:
				var delta := minf(remaining,1.0/60.0)
				mixer.elapsed += delta
				animation.advance_visual(delta)
				remaining -= delta
	else:
		mixer.elapsed = at
	prepared_time = at
	mixer.production_time = fmod(at,mixer.duration()) if running else 0.0
	mixer.queue_redraw()

func changed_fraction(a: Image, b: Image, local_rect: Rect2) -> float:
	var pixel_rect := Rect2i(mixer.get_global_transform_with_canvas()*local_rect)
	var changed := 0
	var count := 0
	for y in range(pixel_rect.position.y,pixel_rect.end.y):
		for x in range(pixel_rect.position.x,pixel_rect.end.x):
			var first := a.get_pixel(x,y)
			var second := b.get_pixel(x,y)
			if maxf(absf(first.r-second.r),maxf(absf(first.g-second.g),absf(first.b-second.b))) > 4.0/255.0:
				changed += 1
			count += 1
	return float(changed)/maxi(1,count)

func fixed_rim(a: Image,b: Image) -> bool:
	# Sample the original opening's metal collar, between its contents and shell.
	# A spinning whole sprite or a wobbling drum shifts these fixed world pixels.
	var transform := mixer.get_global_transform_with_canvas()
	for index in 48:
		var angle := TAU*float(index)/48.0
		var radial := Vector2(.83646,.54802)*cos(angle)*9.2 + Vector2(-.54802,.83646)*sin(angle)*18.1
		var point := Vector2i(transform*(Vector2(-17.5,-79)+radial*1.04))
		if a.get_pixelv(point) != b.get_pixelv(point): return false
	return true

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": quit(2); return
	before = "--before" in OS.get_cmdline_user_args()
	var folder := DEST+("before/" if before else "after/")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder+"frames"))
	AudioServer.set_bus_mute(0,true)
	LocaleText.set_locale("de",false)
	root.size = Vector2i(320,180)
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	view = SubViewport.new()
	view.world_2d = World2D.new()
	view.size = Vector2i(640,480)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.start_scenario(1,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.rounds.running = false
	game.dialogue.reset()
	game.notice_time = 0
	game.players[0].position = Vector2(470,430)
	mixer = get_nodes_in_group("stations").filter(func(station): return station.game == game and station.kind == "mixer")[0]
	await frames(5)
	freeze(game)
	game.hud.canvas.visible = false
	game.camera.position = mixer.position+Vector2(0,-53)
	game.camera.zoom = Vector2.ONE*4.0
	game.camera.force_update_scroll()
	pose(0.0,false)
	await capture("idle")
	var phases: Array[Image] = []
	for index in 4:
		pose(.25+index*.55,true)
		phases.append(await capture("working-phase-%d" % index))
	if not before:
		check(is_instance_valid(mixer.get_node_or_null("MixerAnimation")), "Actual mixer owns its independent visual controller")
		for index in range(1,phases.size()):
			var shell_change := changed_fraction(phases[0],phases[index],Rect2(0,-70,13,12))
			check(shell_change > .25, "Orange shell changes visibly between production phases: %.1f%%" % (shell_change*100.0))
			check(changed_fraction(phases[0],phases[index],Rect2(-42,-27,75,27)) == 0.0, "Wheels and support frame remain fixed while the shell rotates")
			check(fixed_rim(phases[0],phases[index]), "Opening collar stays fixed in position and perspective")
		# Eighty samples at 24 fps cover one full turn at the authored 0.3 rps.
		for frame in 80:
			pose(1.9+float(frame)/24.0,true)
			await capture("frames/%03d" % frame)
		pose(6.5,false)
		var stopped := await capture("idle-stopped")
		pose(7.5,false)
		var held := await capture("idle-held")
		check(changed_fraction(stopped,held,Rect2(-36,-98,74,65)) == 0.0, "Idle drum retains its final orientation without further motion")
	view.size = Vector2i(2560,1440)
	view.size_2d_override = Vector2i(1600,900)
	view.size_2d_override_stretch = true
	game.hud.canvas.visible = true
	game.hud._layout_viewport()
	game.players[0].position = mixer.position+Vector2(63,0)
	game.players[0].focus = mixer
	game.camera.position = Vector2(430,335)
	game.camera.zoom = Vector2.ONE*1.25
	game.camera.force_update_scroll()
	pose(1.35,true)
	await capture("qhd-gameplay-de")
	check(await Cleanup.free_scene(game,self), "Mixer preview releases without player-save changes")
	view.queue_free()
	await process_frame
	print("MIXER ANIMATION PREVIEW: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
