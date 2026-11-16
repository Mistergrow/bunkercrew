extends SceneTree
## The world camera settles on a whole number of physical pixels per world unit
## (one art texel) at every window size, with its canvas origin on whole pixels,
## while the UI keeps the project stretch. Runs headless: window sizes are set on
## the root window, so the real canvas_items stretch path is exercised.
const PixelGrid := preload("res://scripts/pixel_grid.gd")
const CameraRig := preload("res://scripts/player_camera.gd")
const SIZES := [Vector2i(960,600),Vector2i(1280,720),Vector2i(1366,768),Vector2i(1440,900),Vector2i(1600,900),Vector2i(1680,1050),
	Vector2i(1920,1080),Vector2i(1920,1200),Vector2i(2560,1080),Vector2i(2560,1440),Vector2i(3440,1440),Vector2i(3840,2160)]
## Expected settled pixels per texel of the default follow camera (zoom 1.25).
const FOLLOW := {"960x600":1,"1280x720":1,"1366x768":1,"1440x900":1,"1600x900":1,"1680x1050":2,"1920x1080":2,"1920x1200":2,"2560x1080":2,"2560x1440":2,"3440x1440":2,"3840x2160":3}
var game
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("PIXEL GRID FAIL: ", label)

func whole(value: float) -> bool:
	return absf(value - roundf(value)) < .002

func settle(seconds: float = 3.0) -> void:
	# Frame-rate independent: the real ease plus its minimum approach speed.
	for step in int(seconds * 60.0): game.player_camera.update_view(1.0 / 60.0)
	await process_frame

func origin_whole(label: String) -> void:
	# Below one pixel per texel (wide fits) no whole grid exists; nothing to pin.
	var canvas: Transform2D = root.get_final_transform() * root.get_canvas_transform()
	if canvas.x.x < 1.0 - .002: return
	check(whole(canvas.origin.x) and whole(canvas.origin.y), "%s: canvas origin on whole pixels %s" % [label, canvas.origin])
	# On a whole scale, texel edges (integer world coordinates) land on pixel edges.
	if not whole(canvas.x.x): return
	var edge: Vector2 = canvas * Vector2(roundf(game.camera.position.x) + 17.0, roundf(game.camera.position.y) - 9.0)
	check(whole(edge.x) and whole(edge.y), "%s: world texel edge on a pixel edge %s" % [label, edge])

func run() -> void:
	# Pure rules first.
	check(PixelGrid.settle_scale(1.5, INF, Vector2(1920,1080)) == 2.0, "1.5 rounds up to 2 at 1080p (960x540 world units still frame the fight)")
	check(PixelGrid.settle_scale(1.25, INF, Vector2(1440,900)) == 1.0, "1.25 rounds to 1 (ratio-nearest)")
	check(PixelGrid.settle_scale(1.458, INF, Vector2(1680,1050)) == 2.0, "1680x1050 takes the larger step")
	check(PixelGrid.settle_scale(1.5, INF, Vector2(1600,900)) == 1.0, "the larger step is refused when it would show less than MIN_FRAME")
	check(PixelGrid.settle_scale(2.6, 2.4, Vector2(3840,2160)) == 2.0, "a fit limit floors to the next whole step")
	check(is_equal_approx(PixelGrid.settle_scale(1.5, .8, Vector2(1920,1080)), .8), "fits below one pixel per texel keep their exact value")
	check(PixelGrid.settle_scale(.833, INF, Vector2(960,600)) == 1.0 and is_equal_approx(PixelGrid.settle_scale(.6, INF, Vector2(960,600)), .6), "960x600 default rounds to one pixel per texel; a deliberate wide zoom stays")
	check(PixelGrid.fit_scale(1.99) == 1.0 and PixelGrid.fit_scale(2.0) == 2.0, "fits never grow past their area")
	check(PixelGrid.nearest_scale(4.8) == 5.0 and PixelGrid.nearest_scale(4.4) == 4.0, "authored close-ups take the nearest whole step")

	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	for frame in 4: await process_frame
	game.start_scenario(1, {"environment": "sector07", "build_type": "bastion", "position": "left"})
	game.rounds.set_process(false)
	for worker in game.players: worker.set_physics_process(false)
	game.hud.visible = false
	game.player_camera.set_shake(0.0)
	game.reset_camera_view()
	var solo: Node2D = game.players[0]
	for size: Vector2i in SIZES:
		var label := "%dx%d" % [size.x, size.y]
		root.size = size
		await process_frame
		await process_frame
		solo.global_position = Vector2(860, 430)
		await settle()
		var scale: Vector2 = game.player_camera.presented_scale()
		check(whole(scale.x) and whole(scale.y) and absf(scale.x - scale.y) < .002, "%s follow: whole pixels per texel, got %s" % [label, scale])
		check(int(roundf(scale.y)) == int(FOLLOW[label]), "%s follow: %d px per texel expected, got %s" % [label, FOLLOW[label], scale])
		var view: Vector2 = Vector2(size) / scale
		check(view.x >= PixelGrid.MIN_FRAME.x - 1.0 or int(roundf(scale.y)) == 1, "%s follow: rounded-up framing keeps at least %s world units (%s)" % [label, PixelGrid.MIN_FRAME, view])
		origin_whole(label + " follow")
		var screen: Vector2 = root.get_canvas_transform() * solo.global_position
		check(root.get_visible_rect().grow(-40).has_point(screen), "%s follow: worker on screen at %s" % [label, screen])
		var below: float = (game.camera.position.y + view.y * .5) - solo.global_position.y
		check(below <= CameraRig.BELOW_FEET + 1.0, "%s follow: at most %d world units below the feet (%.1f)" % [label, CameraRig.BELOW_FEET, below])
		# Walking: every frame of a moving camera still has a whole-pixel origin
		# and keeps the settled scale (no zoom drift while scrolling).
		for step in 12:
			solo.global_position.x += 1.37
			game.player_camera.update_view(1.0 / 60.0)
		await process_frame
		origin_whole(label + " scrolling")
		check(game.player_camera.presented_scale().is_equal_approx(scale), "%s scrolling keeps the settled scale" % label)
		# Overview keeps the whole stage framing and floors to a whole step.
		game.set_camera_mode("overview")
		await settle()
		scale = game.player_camera.presented_scale()
		var wanted: float = game.camera_target_zoom * minf(PixelGrid.stretch(root).x, PixelGrid.stretch(root).y)
		check(scale.y <= wanted + .002, "%s overview never cuts the stage framing" % label)
		if wanted >= 1.0: check(whole(scale.y), "%s overview: whole pixels per texel, got %s" % [label, scale])
		var designed_bottom: float = game.camera_target_center.y + root.get_visible_rect().size.y * .5 / game.camera_target_zoom
		var shown_bottom: float = game.camera.position.y + float(size.y) * .5 / scale.y
		check(absf(shown_bottom - designed_bottom) <= 1.0, "%s overview keeps the designed lower edge (%.1f vs %.1f): extra height goes to the sky" % [label, shown_bottom, designed_bottom])
		origin_whole(label + " overview")
		game.reset_camera_view()
	# Every wheel notch changes the view by one whole step (no dead notches).
	root.size = Vector2i(1920, 1080)
	await process_frame
	await settle()
	var rig = game.player_camera
	var steps: Array[float] = []
	for direction: float in [1.0, -1.0, -1.0, -1.0]:
		rig.set_zoom(rig.wheel_zoom(rig.view_zoom * pow(1.12, direction), direction))
		await settle()
		steps.append(snappedf(rig.presented_scale().y, .001))
	check(steps.slice(0, 3) == [3.0, 2.0, 1.0] and steps[3] < 1.0, "wheel notches step 2 -> 3 -> 2 -> 1 -> wider at 1080p, got %s" % [steps])
	game.reset_camera_view()
	await settle()
	# Couch co-op on two floors: both workers stay on screen; whole steps wherever
	# the pair fits at one pixel per texel or more.
	game.join_coop()
	for worker in game.players: worker.set_physics_process(false)
	check(game.players.size() == 2, "second local worker joined")
	var partner: Node2D = game.players[-1]
	for size: Vector2i in SIZES:
		var label := "%dx%d" % [size.x, size.y]
		root.size = size
		await process_frame
		await process_frame
		solo.global_position = Vector2(700, 430)
		partner.global_position = Vector2(980, 635)
		await settle()
		var scale: Vector2 = game.player_camera.presented_scale()
		if scale.y >= 1.0 - .002: check(whole(scale.x) and whole(scale.y), "%s co-op: whole pixels per texel, got %s" % [label, scale])
		for worker: Node2D in [solo, partner]:
			check(root.get_visible_rect().has_point(root.get_canvas_transform() * worker.global_position), "%s co-op: both workers on screen" % label)
		origin_whole(label + " co-op")
	# Mouse aim maps exactly through the presented transform.
	root.size = Vector2i(1920, 1080)
	await process_frame
	await settle()
	var pointer := Vector2(1234, 567)
	var world: Vector2 = root.get_canvas_transform().affine_inverse() * pointer
	check((root.get_canvas_transform() * world).distance_to(pointer) < .01, "pointer world position round-trips through the camera")
	# Shake offsets are whole physical pixels too.
	game.player_camera.set_shake(1.0)
	game.player_camera.trauma = .8
	game.player_camera._update_impulses(1.0 / 60.0)
	var offset_pixels: Vector2 = game.camera.offset * game.player_camera.presented_scale()
	check(whole(offset_pixels.x) and whole(offset_pixels.y), "camera shake moves whole physical pixels %s" % offset_pixels)
	paused = false
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game, self), "scene releases cleanly")
	print("PIXEL GRID CAMERA: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
