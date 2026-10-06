extends SceneTree
## The real environment fan draw path at native size and 3x, fixed visual times.
const PropArt := preload("res://scripts/scenario_prop_art.gd")
const Catalog := preload("res://scripts/scenario_prop_catalog.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")

class Fan extends Node2D:
	var clock := 0.0
	func _draw() -> void:
		var profile := Catalog.profile("sector07")
		PropArt.draw(self, {"kind":"fan", "position":Vector2.ZERO, "tint":Color(profile.metal), "accent":Color(profile.accent), "phase":0.0}, clock, 1.0, profile.wind)

class Gallery extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1080, 700), Color("111917"))
		Art.text(self, Vector2(36, 44), "SEKTOR 07 / INDUSTRIELÜFTER", 24)
		Art.text(self, Vector2(36, 76), "Originalgröße und 3x · drei vorbereitete Rotorstellungen", 14, Color("9ba696"))
		for column in 3:
			Art.text(self, Vector2(100 + column * 360, 127), "%.1f Sekunden" % (column * 0.7), 15)
			draw_line(Vector2(45 + column * 360, 240), Vector2(315 + column * 360, 240), Color("374238"))
			draw_line(Vector2(45 + column * 360, 600), Vector2(315 + column * 360, 600), Color("374238"))
		Art.text(self, Vector2(36, 276), "Originalgröße", 14, Color("9ba696"))
		Art.text(self, Vector2(36, 643), "3x · festes Gehäuse, bewegter Rotor, Schutzgitter vor den Schaufeln", 14, Color("9ba696"))

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Use a graphical display and --no-profile-save")
		quit(1)
		return
	root.size = Vector2i(1080, 700)
	root.content_scale_size = Vector2i(1080, 700)
	ThemeDB.fallback_font = load("res://assets/mono.ttf")
	var gallery := Gallery.new()
	root.add_child(gallery)
	for column in 3:
		for row in 2:
			var fan := Fan.new()
			fan.clock = column * 0.7
			fan.position = Vector2(180 + column * 360, 240 if row == 0 else 600)
			fan.scale = Vector2.ONE * (1.0 if row == 0 else 3.0)
			gallery.add_child(fan)
	for frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var destination := "res://artifacts/graphics-audit/fan/after.png"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			destination = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir()))
	var result := root.get_texture().get_image().save_png(destination)
	var cleaned := await Cleanup.free_scene(gallery, self)
	print("FAN MATERIAL PREVIEW: ", destination, " result=", result)
	quit(0 if result == OK and cleaned else 1)
