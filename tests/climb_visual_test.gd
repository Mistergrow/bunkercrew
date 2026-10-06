extends SceneTree
## Uses real Worker movement and the running main scene. Optional -- --capture
## saves actual rendered close-ups; headless execution verifies the same motion.

var checks := 0
var failures := 0
var game
var p1
var p2
var capture := false


func _initialize() -> void:
	capture = OS.get_cmdline_user_args().has("--capture")
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
	else:
		print("PASS ", label)


func settle(frames: int = 4) -> void:
	for i in frames:
		await physics_frame
	await process_frame
	if capture:
		await RenderingServer.frame_post_draw
	else:
		# SceneTree.process_frame precedes Node._process; calculate the pose for
		# this completed physics position when the headless renderer is absent.
		for worker in [p1, p2]:
			worker.get_node("PixelVisual")._process(0.0)


func prepare(worker, ladder: Rect2, feet_y: float) -> void:
	worker.global_position = Vector2(ladder.get_center().x, feet_y)
	worker.velocity = Vector2.ZERO
	worker._ladder = ladder
	worker.climbing = true
	worker.collision_mask = 0
	worker._airborne = false
	worker._landing_time = 0.0


func rung_error(world_y: float, rung_origin: float) -> float:
	var remainder := fposmod(world_y - rung_origin, 14.0)
	return minf(remainder, 14.0 - remainder)


func grip_is_on_rung(worker) -> bool:
	var visual: WorkerVisual = worker.get_node("PixelVisual")
	var descriptor: Dictionary = visual._frames.climb
	var side := 0 if visual.pose_frame < 4 else 1
	var hand: Array = descriptor.hands[visual.pose_frame][side]
	var foot: Array = descriptor.feet[visual.pose_frame][side]
	var origin: float = worker._ladder.position.y + 15.0
	return rung_error(worker.global_position.y + float(hand[1]), origin) <= 3.6 and rung_error(worker.global_position.y + float(foot[1]) + 3.0, origin) <= 3.6


func screenshot(label: String) -> void:
	if not capture:
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/ladder-%s.png" % label)


func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start(2)
	p1 = game.players[0]
	p2 = game.players[1]
	var v1: WorkerVisual = p1.get_node("PixelVisual")
	var v2: WorkerVisual = p2.get_node("PixelVisual")
	if capture:
		game.hud.hide()
		var camera := Camera2D.new()
		camera.position = Vector2(291, 595)
		camera.zoom = Vector2(2, 2)
		game.add_child(camera)
		camera.make_current()
	prepare(p1, game.ladders[0], 540.0)
	prepare(p2, game.ladders[1], 650.0)
	p1.facing = -1.0
	p2.facing = 1.0
	await settle()
	Input.action_press("p1_up")
	Input.action_press("p2_down")
	var start_1: float = p1.position.y
	var start_2: float = p2.position.y
	var visited_frames: Dictionary = {}
	var every_grip := true
	for i in 24:
		await settle(1)
		visited_frames[v1.pose_frame] = true
		every_grip = every_grip and grip_is_on_rung(p1) and grip_is_on_rung(p2)
	check(p1.position.y < start_1 - 40.0 and p2.position.y > start_2 + 40.0, "Real InputMap ascent and descent move independently")
	check(v1.pose_name == "climb" and v2.pose_name == "climb", "Both moving workers use back-view ladder poses")
	check(visited_frames.size() >= 7, "Actual ladder movement exercises the complete climbing cycle")
	check(every_grip, "Supporting hand and boot stay on drawn rungs within pixel-frame tolerance")
	check(v1.sprite_facing() == 1.0 and v2.sprite_facing() == 1.0, "Approaching from left/right cannot mirror the back view")
	Input.action_release("p1_up")
	Input.action_release("p2_down")
	await settle(2)
	var stopped_y: float = p1.position.y
	var stopped_frame := v1.pose_frame
	await settle(18)
	check(p1.climbing and is_equal_approx(p1.position.y, stopped_y), "Releasing input holds position in the middle of the ladder")
	check(v1.pose_frame == stopped_frame, "Hands and feet hold their pose while waiting on a ladder")
	await screenshot("hold")
	Input.action_press("p1_down")
	Input.action_press("p2_up")
	await settle(10)
	check(p1.position.y > stopped_y + 20.0 and v1.pose_frame == v1.climb_frame(), "Reversing direction derives the exact reverse phase from movement")
	Input.action_release("p1_down")
	Input.action_release("p2_up")
	await screenshot("reverse")
	# Isolate jump exit below clear headroom. Reversal can end just below the
	# production slab, where a correct jump immediately hits the ceiling.
	prepare(p2, game.ladders[1], 740.0)
	await settle(7)
	# Dispatch the edge-triggered jump at the beginning of the physics frame.
	# action_press from a post-render screenshot callback misses that frame's
	# just_pressed window; real keyboard events are delivered before physics.
	await physics_frame
	Input.action_press("p1_right")
	Input.action_press("p2_jump")
	await settle(3)
	Input.action_release("p1_right")
	Input.action_release("p2_jump")
	check(not p1.climbing and p1.collision_mask == 1, "Side exit restores terrain collision")
	check(not p2.climbing and p2.velocity.y < 0.0, "Jump exit immediately leaves ladder mode")
	check(v1.pose_name != "climb" and v2.pose_name == "jump_up", "Exiting restores walking/falling or jumping art without a stuck ladder pose")
	await screenshot("exit")
	prepare(p1, game.ladders[0], 270.0)
	Input.action_press("p1_up")
	await settle(14)
	Input.action_release("p1_up")
	check(not p1.climbing and absf(p1.position.y - 245.0) < 1.0 and v1.pose_name != "climb", "Reaching the rooftop ends the climbing pose")
	var bottom: float = p2._nearest_floor(game.ladders[1].end.y, 12.0)
	prepare(p2, game.ladders[1], bottom - 22.0)
	Input.action_press("p2_down")
	await settle(13)
	Input.action_release("p2_down")
	check(not p2.climbing and absf(p2.position.y - bottom) < 1.0 and v2.pose_name != "climb", "Reaching the lower landing ends the climbing pose")
	# Mixer retirement depends on actual frames, especially with several weather
	# layers under software rendering. Wait for the existing shared cleanup probe.
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Scene and audio playback retire without leaking resources")
	print("CLIMB VISUAL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
