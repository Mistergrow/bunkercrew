extends SceneTree
## Identical active machine scenes, one row with material lighting disabled.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const PATHS := ["res://scenes/station.tscn", "res://scenes/glass_furnace.tscn", "res://scenes/alloy_furnace.tscn", "res://scenes/ammo_press.tscn"]
const OUTPUT := "res://artifacts/station-shaders"
const FRAMES := "/tmp/lastshift-station-shader-frames"

class Gallery extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1440, 900), Color("111917"))
		Art.text(self, Vector2(32, 38), "MASCHINEN / WÄRME UND ENERGIE", 24)
		Art.text(self, Vector2(32, 65), "Echte Produktionsszenen · identische Phase · 2x Pixelansicht", 14, Color("99a094"))
		Art.text(self, Vector2(32, 110), "BISHER: FLAMMEN UND LICHTBÖGEN", 15, Color("a8ada3"))
		Art.text(self, Vector2(32, 480), "ZUSÄTZLICH: LICHT AUF MAUERWERK, METALL UND ELEKTRODEN", 15, Color("e6d5b5"))
		Art.text(self, Vector2(32, 870), "Kein Bildschirmfilter · unveränderte Texturkonturen · Pause hält Effekte an · F3 reduziert Zusatzlicht", 14, Color("99a094"))
		for y in [443, 817]:
			draw_line(Vector2(30, y), Vector2(1410, y), Color("34413a"))

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Use a graphical display and --no-profile-save")
		quit(1)
		return
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1440, 900)
	var gallery := Gallery.new()
	root.add_child(gallery)
	var machines: Array[Node2D] = []
	for row in 2:
		for column in 4:
			var machine = load(PATHS[column]).instantiate()
			if column == 0:
				machine.kind = "furnace"
			gallery.add_child(machine)
			machine.position = Vector2(180 + column * 360, 442 + row * 374)
			machine.scale = Vector2.ONE * 2.0
			machine.set_process(false)
			machine.elapsed = 2.4
			machine.working = true
			machine.production_time = machine.duration() * 0.4
			machines.append(machine)
	for frame in 5:
		await process_frame
	for index in machines.size():
		var machine = machines[index]
		var effects = machine.get_node("MaterialEffects")
		effects.set_process(false)
		if index < 4:
			machine.material = null
		else:
			effects._refresh()
		machine.queue_redraw()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var result := root.get_texture().get_image().save_png(OUTPUT + "/comparison.png")
	if "--video" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(FRAMES)
		for frame in 180:
			for index in machines.size():
				var machine = machines[index]
				machine.elapsed = 2.4 + float(frame) / 30.0
				if index >= 4:
					machine.get_node("MaterialEffects")._refresh()
				machine.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var saved := root.get_texture().get_image().save_jpg(FRAMES + "/%04d.jpg" % frame, 0.97)
			if saved != OK:
				result = saved
	var manifest := FileAccess.open(OUTPUT + "/capture.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"prepared": true, "scenes": PATHS, "size": [1440, 900], "fps": 30, "frames": 180 if "--video" in OS.get_cmdline_user_args() else 1, "phase": "Production held at 40%; source flames/arcs and material clocks advance normally. Upper row disables only the new material shader, lower row enables it.", "engine": Engine.get_version_info().string}, "\t"))
	manifest.close()
	var cleaned := await Cleanup.free_scene(gallery, self)
	print("STATION SHADER PREVIEW: ", result)
	quit(0 if result == OK and cleaned else 1)
