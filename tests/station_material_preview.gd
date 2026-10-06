extends SceneTree
## Prepared real station scenes: fixed production phase, native and 2x display.
const CLEANUP := preload("res://tests/scene_cleanup.gd")
const PATHS := ["res://scenes/station.tscn", "res://scenes/glass_furnace.tscn", "res://scenes/alloy_furnace.tscn", "res://scenes/ammo_press.tscn"]
const LABELS := ["SCHMELZOFEN · REFERENZ", "GLASOFEN", "LEGIERUNGSOFEN", "MUNITIONSPRESSE"]

class Gallery extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1440, 1020), Color("111917"))
		Art.text(self, Vector2(32, 40), "PRODUKTIONSMASCHINEN / MATERIALSTUDIE", 24)
		Art.text(self, Vector2(32, 69), "Echte Szenen · vorbereitete Produktion · gleiche Licht- und Kamerabedingungen", 14, Color("99a094"))
		for column in 4:
			Art.text(self, Vector2(30 + column * 360, 116), LABELS[column], 15)
			for height in [282, 619, 959]:
				draw_line(Vector2(30 + column * 360, height), Vector2(330 + column * 360, height), Color("34413a"))
		Art.text(self, Vector2(32, 306), "Originalgröße · Ruhezustand", 14, Color("99a094"))
		Art.text(self, Vector2(32, 644), "2x · Ruhezustand", 14, Color("99a094"))
		Art.text(self, Vector2(32, 988), "2x · laufende Herstellung bei festgehaltenen 40 %", 14, Color("99a094"))

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Use a graphical display and --no-profile-save")
		quit(1)
		return
	ThemeDB.fallback_font = load("res://assets/mono.ttf")
	root.content_scale_size = Vector2i(1440, 1020)
	root.size = Vector2i(1440, 1020)
	var gallery := Gallery.new()
	root.add_child(gallery)
	var machines: Array[Node2D] = []
	for row in 3:
		for column in 4:
			var station = load(PATHS[column]).instantiate()
			if column == 0:
				station.kind = "furnace"
			gallery.add_child(station)
			station.position = Vector2(180 + column * 360, [282, 619, 959][row])
			station.scale = Vector2.ONE * (1.0 if row == 0 else 2.0)
			station.set_process(false)
			station.elapsed = 2.4
			station.working = row == 2
			station.production_time = station.duration() * 0.4 if station.working else 0.0
			station.queue_redraw()
			machines.append(station)
	for frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var destination := "res://artifacts/graphics-audit/stations/after.png"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			destination = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir()))
	var result := root.get_texture().get_image().save_png(destination)
	if "--video" in OS.get_cmdline_user_args():
		var frames_path := destination.get_base_dir() + "/frames"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(frames_path))
		for frame in 180:
			for machine in machines:
				machine.elapsed = 2.4 + float(frame) / 30.0
				machine.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var frame_result := root.get_texture().get_image().save_png(frames_path + "/%04d.png" % frame)
			if frame_result != OK:
				result = frame_result
		var manifest := FileAccess.open(destination.get_base_dir() + "/capture.json", FileAccess.WRITE)
		manifest.store_string(JSON.stringify({"prepared":true, "scenes":PATHS, "fps":30, "frames":180, "size":[1440,1020], "magnifications":[1,2], "phase":"Four real production scenes; production held at 40 percent while visual elapsed time advances at normal speed. Steel furnace keeps its original body atlas and uses the shared new oven effects. No game profile or network.", "engine":Engine.get_version_info().string}, "\t"))
		manifest.close()
	var cleaned := await CLEANUP.free_scene(gallery, self)
	print("STATION MATERIAL PREVIEW: ", destination, " result=", result)
	quit(0 if result == OK and cleaned else 1)
