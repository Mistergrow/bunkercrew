extends SceneTree
## Real impulse drawing: orientation, muzzle bounds, paused clock and F3 halo.
class WeatherStub extends Node:
	var reduced_effects := false
class GameStub extends Node2D:
	var weather := WeatherStub.new()
	func _ready() -> void:
		add_child(weather)
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
	print("ARC EFFECT %s: %s" % ["PASS" if value else "FAIL",label])

func capture(shot: WorkerShot, viewport: SubViewport) -> Image:
	shot.queue_redraw()
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func check_render() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(96,64)
	viewport.world_2d = World2D.new()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var game := GameStub.new()
	viewport.add_child(game)
	var shot := WorkerShot.new()
	shot.flavor = "arcgun"
	shot.game = game
	shot.position = Vector2(60,32)
	shot.distance_travelled = 31.0
	shot.age = .20
	game.add_child(shot)
	shot.set_physics_process(false)
	var full := await capture(shot,viewport)
	game.weather.reduced_effects = true
	var quiet := await capture(shot,viewport)
	var full_pixels := 0
	var quiet_pixels := 0
	var halo_pixels := 0
	var stray_pixels := 0
	for y in viewport.size.y:
		for x in viewport.size.x:
			var before := full.get_pixel(x,y)
			var after := quiet.get_pixel(x,y)
			if before.a > .01: full_pixels += 1
			if after.a > .01: quiet_pixels += 1
			if before.a > .01 and before.a < .3 and after.a < .01: halo_pixels += 1
			if after.a > .01 and x > 61: stray_pixels += 1
	check(full_pixels > quiet_pixels and quiet_pixels > 20,"F3 removes optional arc pixels while retaining the visible projectile")
	check(halo_pixels > 15,"Actual GPU output removes the additional translucent halo under F3")
	check(stray_pixels == 0,"Rendered impulse stays behind its physical leading point")
	var paused_age := shot.age
	shot.set_physics_process(true)
	paused = true
	await create_timer(.05,true,false,true).timeout
	check(shot.age == paused_age,"Pause leaves the presentation's projectile-age clock unchanged")
	paused = false
	await physics_frame
	await process_frame
	check(shot.age > paused_age,"Unpausing resumes the real projectile clock and movement")
	viewport.queue_free()
	await process_frame

func run() -> void:
	var shot := WorkerShot.new()
	check(shot.arc_paths().is_empty(),"A new projectile draws no trail through its shooter")
	for bearing in 8:
		shot.direction = Vector2.from_angle(float(bearing)*TAU/8.0)
		var valid := true
		for distance: float in [.5,2.0,8.0,12.0,31.0,120.0]:
			shot.distance_travelled = distance
			for phase in 8:
				shot.age = float(phase)/12.0
				var paths := shot.arc_paths()
				var quiet := shot.arc_paths(true)
				valid = valid and paths[0] == quiet[0] and quiet.size() == 1
				valid = valid and paths[0][-1] == Vector2.ZERO
				for path in paths:
					for point in path:
						var along := point.dot(shot.direction)
						valid = valid and point == point.round()
						valid = valid and along <= .75 and along >= -minf(31.0,distance)-.75
		check(valid,"Bearing %d: pixel corners, stable leading point and no trail before the muzzle" % bearing)
	shot.direction = Vector2.RIGHT
	shot.distance_travelled = 31.0
	shot.age = .01
	var first := shot.arc_paths()
	shot.age = .07
	check(first == shot.arc_paths(),"Corners stay stable within a 12-Hz animation phase")
	shot.age = .10
	check(first != shot.arc_paths(),"Electrical bends change between animation phases")
	check(shot.arc_paths().size() == 2 and shot.arc_paths(true).size() == 1,"F3 removes the secondary electrical branch")
	shot.free()
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await check_render()
	print("ARC PROJECTILE EFFECT: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
