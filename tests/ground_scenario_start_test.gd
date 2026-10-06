extends SceneTree
## Enter selected worlds through the real main-scene start path, no cache reset.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("GROUND START %s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(1)
		return
	for environment in ["abandoned_harbor", "flooded_power_station", "frozen_rail_yard"]:
		var game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		await process_frame
		game.start_scenario(1, {"environment": environment, "position": "left", "build_type": "bastion"})
		game.rounds.running = false
		var surfaces = game.weather.surface_effects
		# An eager tool/debug call during construction must not poison the cache.
		surfaces.ground.prepare()
		for tick in 6:
			await physics_frame
			await process_frame
		var fields: Array = surfaces.ground.fields
		check(not fields.is_empty(), "%s creates visible ground fields after real selected-world construction" % environment)
		var all_supported := true
		for field in fields:
			var contact: Dictionary = surfaces.sample_contact(field.point)
			all_supported = all_supported and contact.supported and contact.kind == field.kind
		check(all_supported, "%s field pixels and footstep material agree without a test cache reset" % environment)
		if environment != "frozen_rail_yard" and not fields.is_empty():
			surfaces.particles.clear()
			surfaces.footstep(fields[0].point)
			var clear_water := false
			for particle in surfaces.particles:
				clear_water = clear_water or particle.kind == "water"
			check(clear_water, "%s authored puddles throw clear water rather than only brown soil" % environment)
		paused = false
		check(await Cleanup.free_scene(game, self), "%s real game releases cleanly" % environment)
	print("GROUND SCENARIO START: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
