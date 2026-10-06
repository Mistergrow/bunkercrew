extends SceneTree
## Real selected worlds and real actor art; isolated, deliberately triggered
## contact impulses make the small ground effects inspectable at 3–4x zoom.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/movement-effects/ground"
const FRAMES := "/tmp/lastshift-ground-contact-frames"
const CASES := [
	{"id": "dry-worker", "world": "ash_foundry", "label": "STAUB / LEICHTER SCHRITT", "weight": 0.75},
	{"id": "dry-colossus", "world": "ash_foundry", "label": "KIES / SCHWERER BODENKONTAKT", "weight": 2.2},
	{"id": "water-worker", "world": "flooded_power_station", "label": "PFÜTZE / WASSERFÄCHER UND RING", "weight": 1.0},
	{"id": "ice-worker", "world": "frozen_rail_yard", "label": "FROST / KRÜMEL UND SOHLENSPUR", "weight": 1.0},
]
var checks := 0
var failures := 0

class Caption extends Node2D:
	var title := ""
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1440, 80), Color("101917"))
		Art.text(self, Vector2(28, 33), title, 22, Color("e0dfcf"))
		Art.text(self, Vector2(28, 61), "Echte Welt und Figuren · gezielt ausgelöste Kontaktimpulse · 3–4x Kameravergrößerung", 14, Color("aab6ac"))

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("GROUND GPU %s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		freeze(child)

func frame() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(1)
		return
	root.size = Vector2i(1440, 900)
	root.content_scale_size = Vector2i(1440, 900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if "--video" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(FRAMES)
	var manifest: Array[Dictionary] = []
	for case_index in CASES.size():
		var spec: Dictionary = CASES[case_index]
		var game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		await process_frame
		game.start_scenario(1, {"environment": spec.world, "position": "left", "build_type": "bastion"})
		game.rounds.running = false
		for tick in 6:
			await physics_frame
			await process_frame
		var surfaces = game.weather.surface_effects
		var point := Vector2(1060, 430)
		if spec.id in ["water-worker", "ice-worker"]:
			for field in surfaces.ground.fields:
				if field.point.x > 820 and field.point.x < 1540:
					point = field.point
					break
		var actor: Node2D = game.players[0]
		if spec.id == "dry-colossus":
			actor.hide()
			actor = SiegeMachine.new()
			actor.game = game
			actor.kind = "colossus"
			game.add_child(actor)
			actor.show_status_labels = false
		actor.position = point
		freeze(game)
		game.hud.canvas.hide()
		for layer in game.weather.rain_layers:
			layer.hide()
		game.weather.wind_layer.hide()
		var feet := ActorWeatherGeometry.feet(actor)
		if not feet.is_empty():
			var foot: Vector2 = feet[0] + Vector2(0, 3.0)
			actor.position += point - foot
		var zoom := 3.0 if spec.id == "dry-colossus" else 4.0
		game.camera.zoom = Vector2.ONE * zoom
		game.camera.position = point + Vector2(0, -85 if spec.id == "dry-colossus" else -40)
		game.camera.force_update_scroll()
		game.weather.refresh_collision_cache()
		surfaces.particles.clear()
		surfaces.splashes.clear()
		surfaces.ground.chips.clear()
		surfaces.ground.plumes.clear()
		var overlay := CanvasLayer.new()
		overlay.layer = 110
		var caption := Caption.new()
		caption.title = spec.label
		overlay.add_child(caption)
		game.add_child(overlay)
		surfaces._redraw()
		var baseline := await frame()
		baseline.save_png(OUTPUT + "/%s-before.png" % spec.id)
		var state: Dictionary = surfaces.sample_contact(point)
		check(state.supported and absf(float(state.distance)) < 0.1, "%s visual sample uses actual physical ground" % spec.id)
		var expected := "water" if spec.id == "water-worker" else ("ice" if spec.id == "ice-worker" else "dry")
		check(state.kind == expected, "%s visual sample uses its real %s surface" % [spec.id, expected])
		surfaces.contact_event(point, float(spec.weight), actor, state)
		for tick in 6:
			surfaces._physics_process(1.0 / 60.0)
		var contact := await frame()
		check(contact.get_data() != baseline.get_data(), "%s adds visible local contact pixels" % spec.id)
		contact.save_png(OUTPUT + "/%s-after.png" % spec.id)
		manifest.append({"case": spec.id, "world": spec.world, "point": [point.x, point.y], "zoom": zoom, "kind": state.kind, "strength": spec.weight})
		if "--video" in OS.get_cmdline_user_args():
			for tick in 60:
				if tick % 24 == 0:
					surfaces.contact_event(point, float(spec.weight), actor, state)
				surfaces._physics_process(1.0 / 30.0)
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_jpg(FRAMES + "/%04d.jpg" % (case_index * 60 + tick), 0.97)
		check(await Cleanup.free_scene(game, self), "%s preview releases cleanly" % spec.id)
	var file := FileAccess.open(OUTPUT + "/capture.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"prepared": true, "cases": manifest, "fps": 30, "frames": 240 if "--video" in OS.get_cmdline_user_args() else 4,
		"description": "Real selected game scenes and original actors. Simulation and poses frozen; supported contact events intentionally triggered while SurfaceWeather advances at normal speed. Close camera magnification exposes small local particles; this is not a locomotion integration or performance test."}, "\t"))
	file.close()
	print("GROUND CONTACT GALLERY: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
